import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/models/deployment.dart';
import 'package:nonto/providers/deployment_providers.dart';
import 'package:nonto/services/api/deployment_service.dart';
import 'package:nonto/services/deployment_file_picker.dart';

typedef DeploymentPicker = Future<DeploymentFile?> Function(
    {required bool manifest});

class DeploymentsScreen extends ConsumerWidget {
  final DeploymentPicker? picker;
  const DeploymentsScreen({super.key, this.picker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(deploymentSessionProvider);
    Widget denied(String message) => Scaffold(
          appBar: AppBar(title: const Text('部署管理')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24), child: Text(message))),
        );
    if (!ref.watch(deploymentWebProvider)) return denied('部署管理仅在 Web 端可用。');
    if (session.token == null) return denied('请先登录后访问部署管理。');
    return _DeploymentConsole(
      key: ValueKey(session),
      service: ref.watch(deploymentServiceProvider),
      picker: picker ?? pickDeploymentFile,
      session: session,
    );
  }
}

class _DeploymentConsole extends ConsumerStatefulWidget {
  final DeploymentService service;
  final DeploymentPicker picker;
  final ({String? token, String? userId}) session;
  const _DeploymentConsole(
      {super.key,
      required this.service,
      required this.picker,
      required this.session});
  @override
  ConsumerState<_DeploymentConsole> createState() => _DeploymentConsoleState();
}

class _DeploymentConsoleState extends ConsumerState<_DeploymentConsole> {
  Timer? _timer;
  bool _busy = false;
  bool _loading = true;
  bool _allowed = false;
  DeploymentFailure? _failure;
  DeploymentPage<DeploymentArtifact> _artifacts = const DeploymentPage([], 0);
  DeploymentPage<DeploymentJob> _jobs = const DeploymentPage([], 0);
  DeploymentActive _active = const DeploymentActive();
  DeploymentJob? _detail;
  String? _artifactId;
  DeploymentFile? _manifest;
  DeploymentFile? _bundle;
  double? _progress;
  String? _fileError;
  String? _pendingSignature;
  String? _pendingKey;
  BuildContext? _dialogContext;
  bool get _current =>
      mounted && ref.read(deploymentSessionProvider) == widget.session;
  bool get _canAct => _allowed && !_busy && _failure == null;

  @override
  void initState() {
    super.initState();
    ref.listenManual(deploymentSessionProvider, (previous, next) {
      if (next != widget.session) {
        _timer?.cancel();
        final dialog = _dialogContext;
        if (dialog != null && dialog.mounted) Navigator.of(dialog).pop();
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _fail(Object error) {
    _failure = error is DeploymentFailure ? error : const DeploymentFailure();
    if (_failure!.denied) {
      _allowed = false;
      _artifacts = const DeploymentPage([], 0);
      _jobs = const DeploymentPage([], 0);
      _active = const DeploymentActive();
      _detail = null;
      _manifest = null;
      _bundle = null;
      _artifactId = null;
    }
  }

  // A new timer is scheduled only after the previous request sequence finishes.
  void _schedule() {
    _timer?.cancel();
    if (_current &&
        _failure == null &&
        (_active.job?.active == true ||
            _detail?.active == true ||
            _jobs.items.any((job) => job.active))) {
      _timer = Timer(const Duration(seconds: 3), _refresh);
    }
  }

  Future<void> _loadData() async {
    final artifacts = await widget.service.artifacts();
    if (!_current) return;
    final jobs = await widget.service.jobs();
    if (!_current) return;
    final active = await widget.service.active();
    if (!_current) return;
    final selectedId = _detail?.id ?? active.job?.id;
    final detail =
        selectedId == null ? null : await widget.service.job(selectedId);
    if (!_current) return;
    _artifacts = artifacts;
    _jobs = jobs;
    _active = active;
    _detail = detail;
    if (!artifacts.items.any((item) => item.id == _artifactId)) {
      _artifactId = artifacts.items.firstOrNull?.id;
    }
  }

  Future<void> _refresh() async {
    if (_busy || !_current) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      final capability = await widget.service.capabilities();
      if (!_current) return;
      if (!capability.allowed) throw const DeploymentFailure(403);
      _allowed = true;
      await _loadData();
      if (!_current) return;
      _failure = null;
    } catch (error) {
      if (_current) _fail(error);
    } finally {
      if (_current) {
        setState(() {
          _busy = false;
          _loading = false;
        });
        _schedule();
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_canAct || !_current) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      await action();
      if (!_current) return;
      await _loadData();
      if (!_current) return;
      _failure = null;
    } catch (error) {
      if (_current) _fail(error);
    } finally {
      if (_current) {
        setState(() {
          _busy = false;
          _progress = null;
        });
        _schedule();
      }
    }
  }

  Future<_Confirmation?> _confirm(String title, String explanation,
      {bool approval = false, bool backend = false}) async {
    _timer?.cancel();
    final result = await showDialog<_Confirmation>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          _dialogContext = context;
          return _DeploymentConfirmation(
              title: title,
              explanation: explanation,
              approval: approval,
              backend: backend);
        });
    _dialogContext = null;
    if (!_current) return null;
    _schedule();
    return result;
  }

  Future<void> _pick(bool manifest) async {
    if (!_canAct) return;
    try {
      final file = await widget.picker(manifest: manifest);
      if (!_current || file == null) return;
      if (manifest) {
        if (!file.name.toLowerCase().endsWith('.json') ||
            jsonDecode(utf8.decode(file.bytes)) is! Map) {
          throw const FormatException();
        }
      } else if (!file.name.toLowerCase().endsWith('.tar.gz') ||
          file.bytes.length < 2 ||
          file.bytes[0] != 0x1f ||
          file.bytes[1] != 0x8b) {
        throw const FormatException();
      }
      setState(() {
        if (manifest) {
          _manifest = file;
        } else {
          _bundle = file;
        }
        _fileError = null;
      });
    } catch (_) {
      if (_current) setState(() => _fileError = '请选择有效的 JSON 清单和 tar.gz 发布包。');
    }
  }

  Future<void> _upload() async {
    final confirmation = await _confirm('上传发布包', '确认上传所选清单和发布包，由服务器验证完整性。');
    if (confirmation == null || !_current) return;
    await _run(() async {
      final artifact = await widget.service.upload(
          manifest: _manifest!.bytes,
          bundle: _bundle!.bytes,
          reason: confirmation.reason,
          progress: (sent, total) {
            if (_current) {
              setState(() => _progress = total > 0 ? sent / total : null);
            }
          });
      if (!_current) return;
      _artifactId = artifact.id;
      _manifest = null;
      _bundle = null;
    });
  }

  Future<void> _create(String operation) async {
    final artifactId = _artifactId;
    if (artifactId == null) return;
    final artifact =
        _artifacts.items.firstWhere((item) => item.id == artifactId);
    final confirmation = await _confirm(
        _operationLabel(operation),
        '${artifact.label}\n${switch (operation) {
          'preflight' => '仅执行服务器预检。',
          'deploy' => '切换服务器发布版本，可能中断服务；涉及迁移时必须再次批准。',
          'register' => '将此发布包登记到服务器发布记录。',
          _ => '恢复所选发布版本。数据库不会自动回退，必须核对版本与当前数据库兼容性。',
        }}');
    if (confirmation == null || !_current) return;
    // Reuse the key for an identical retry after a lost response; never auto-retry a mutation.
    final signature = jsonEncode([artifactId, operation, confirmation.reason]);
    if (_pendingSignature != signature) {
      _pendingSignature = signature;
      final random = Random.secure();
      _pendingKey = List.generate(
              24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
    }
    await _run(() async {
      final job = await widget.service.create(
          artifactId: artifactId,
          operation: operation,
          reason: confirmation.reason,
          idempotencyKey: _pendingKey!);
      if (!_current) return;
      _detail = job;
      _pendingSignature = null;
      _pendingKey = null;
    });
  }

  Future<void> _approve(DeploymentJob job) async {
    final components = job.components.isNotEmpty
        ? job.components
        : _artifacts.items
                .where((item) => item.id == job.artifactId)
                .firstOrNull
                ?.components ??
            <String>[];
    final backend = components.isEmpty ||
        components.any((component) => const ['backend', 'server', 'api']
            .contains(component.toLowerCase()));
    final confirmation = await _confirm('批准部署',
        '任务 ${job.id}\n批准后服务器将继续执行。恢复旧版本不会撤销数据库迁移；不兼容的 schema 可能导致数据损坏或服务不可用。',
        approval: true, backend: backend);
    if (confirmation == null || !_current) return;
    await _run(() async {
      final updated = await widget.service.approve(job.id,
          reason: confirmation.reason,
          migrationConfirmed: confirmation.migration,
          schemaCompatible: confirmation.schema);
      if (_current) _detail = updated;
    });
  }

  Future<void> _cancel(DeploymentJob job) async {
    final confirmation =
        await _confirm('取消任务', '请求取消任务 ${job.id}。已完成的操作不会自动撤销，最终状态由服务器决定。');
    if (confirmation == null || !_current) return;
    await _run(() async {
      final updated =
          await widget.service.cancel(job.id, reason: confirmation.reason);
      if (_current) _detail = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('部署管理'), actions: [
        IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh)),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_failure?.message ?? '无部署权限。')))
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      if (_busy) LinearProgressIndicator(value: _progress),
                      if (_failure != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_failure!.message,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      Text('当前发布',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(_active.release?.label ?? '尚无发布记录'),
                      if (_active.job != null)
                        Text(
                            '活动任务 ${_active.job!.id} · ${_statusLabel(_active.job!.status)} · ${_active.job!.phase}'),
                      const Divider(height: 32),
                      Text('发布包',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: _canAct ? () => _pick(true) : null,
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('选择 manifest.json')),
                        OutlinedButton.icon(
                            onPressed: _canAct ? () => _pick(false) : null,
                            icon: const Icon(Icons.folder_zip_outlined),
                            label: const Text('选择 bundle.tar.gz')),
                        FilledButton.icon(
                            onPressed:
                                _canAct && _manifest != null && _bundle != null
                                    ? _upload
                                    : null,
                            icon: const Icon(Icons.upload),
                            label: const Text('上传发布包')),
                      ]),
                      if (_manifest != null)
                        Text(_manifest!.name, overflow: TextOverflow.ellipsis),
                      if (_bundle != null)
                        Text(_bundle!.name, overflow: TextOverflow.ellipsis),
                      if (_fileError != null)
                        Text(_fileError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_artifactId),
                        initialValue: _artifactId,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText:
                                '选择发布包 (${_artifacts.items.length}/${_artifacts.total})',
                            border: const OutlineInputBorder()),
                        items: _artifacts.items
                            .map((item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: _canAct
                            ? (value) => setState(() => _artifactId = value)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final operation in [
                          'preflight',
                          'deploy',
                          'register',
                          'restore'
                        ])
                          OutlinedButton.icon(
                              onPressed: _canAct &&
                                      _artifactId != null &&
                                      _active.job?.active != true
                                  ? () => _create(operation)
                                  : null,
                              icon: Icon(switch (operation) {
                                'preflight' => Icons.fact_check_outlined,
                                'deploy' => Icons.publish,
                                'register' => Icons.app_registration,
                                _ => Icons.restore
                              }),
                              label: Text(_operationLabel(operation))),
                      ]),
                      const Divider(height: 32),
                      Text('任务记录 (${_jobs.items.length}/${_jobs.total})',
                          style: Theme.of(context).textTheme.titleMedium),
                      if (_jobs.items.isEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('暂无任务')),
                      for (final job in _jobs.items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          selected: _detail?.id == job.id,
                          title: Text(
                              '${_operationLabel(job.operation)} · ${_statusLabel(job.status)}'),
                          subtitle: Text(
                              '${job.id}\n${job.version ?? job.artifactId} · ${job.phase}\n${job.createdAt ?? ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _canAct
                              ? () => _run(() async {
                                    final detail =
                                        await widget.service.job(job.id);
                                    if (_current) _detail = detail;
                                  })
                              : null,
                        ),
                      if (_detail != null) ..._detailWidgets(context, _detail!),
                    ]),
                  )),
    );
  }

  List<Widget> _detailWidgets(BuildContext context, DeploymentJob job) => [
        const Divider(height: 32),
        Text('任务详情', style: Theme.of(context).textTheme.titleMedium),
        SelectableText(
            '${job.id}\n${_operationLabel(job.operation)} · ${_statusLabel(job.status)} · ${job.phase}\n发布包 ${job.artifactId}'),
        Text(
            '版本 ${job.version ?? '-'} (${job.buildNumber ?? '-'}) · ${job.components.join(', ')}'),
        Text(
            '创建 ${job.createdAt ?? '-'}\n开始 ${job.startedAt ?? '-'}\n结束 ${job.finishedAt ?? '-'}'),
        if (job.errorCode != null)
          Text('错误代码 ${job.errorCode}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (job.status == 'manual_recovery')
          Text('需要人工恢复。请由运维人员核对服务器与数据库状态后处理。',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold)),
        Wrap(spacing: 12, runSpacing: 8, children: [
          if (job.status == 'awaiting_approval')
            FilledButton.icon(
                onPressed: _canAct ? () => _approve(job) : null,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('批准部署')),
          if (job.status == 'queued' || job.status == 'awaiting_approval')
            OutlinedButton.icon(
                onPressed: _canAct ? () => _cancel(job) : null,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('取消任务')),
        ]),
        const SizedBox(height: 12),
        for (final event in job.events)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(
                  '${event.at ?? ''} ${event.phase}\n${event.message ?? ''}')),
      ];
}

String _operationLabel(String operation) =>
    const {
      'preflight': '预检',
      'deploy': '部署',
      'register': '登记',
      'restore': '恢复',
    }[operation] ??
    operation;
String _statusLabel(String status) =>
    const {
      'awaiting_approval': '等待批准',
      'queued': '排队中',
      'running': '运行中',
      'verifying': '验证中',
      'succeeded': '成功',
      'failed': '失败',
      'cancelled': '已取消',
      'manual_recovery': '需人工恢复',
    }[status] ??
    status;

class _Confirmation {
  final String reason;
  final bool migration;
  final bool schema;
  const _Confirmation(this.reason, this.migration, this.schema);
}

class _DeploymentConfirmation extends StatefulWidget {
  final String title;
  final String explanation;
  final bool approval;
  final bool backend;
  const _DeploymentConfirmation(
      {required this.title,
      required this.explanation,
      required this.approval,
      required this.backend});
  @override
  State<_DeploymentConfirmation> createState() =>
      _DeploymentConfirmationState();
}

class _DeploymentConfirmationState extends State<_DeploymentConfirmation> {
  final _reason = TextEditingController();
  final _schemaText = TextEditingController();
  bool _migration = false;
  bool _schema = false;
  @override
  void dispose() {
    _reason.dispose();
    _schemaText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _reason.text.trim().isNotEmpty &&
        (!widget.approval ||
            (_schema &&
                _schemaText.text.trim() == '兼容' &&
                (!widget.backend || _migration)));
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.explanation),
              const SizedBox(height: 16),
              TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: '操作原因（必填）'),
                  onChanged: (_) => setState(() {})),
              if (widget.approval) ...[
                if (widget.backend)
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _migration,
                      onChanged: (value) =>
                          setState(() => _migration = value ?? false),
                      title: const Text('我已审查后端数据库迁移及其不可逆影响，并确认执行。')),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _schema,
                    onChanged: (value) =>
                        setState(() => _schema = value ?? false),
                    title:
                        const Text('我已验证目标版本与当前数据库 schema 兼容；恢复版本不等于回滚数据库。')),
                TextField(
                    controller: _schemaText,
                    decoration: const InputDecoration(labelText: '输入“兼容”以明确确认'),
                    onChanged: (_) => setState(() {})),
              ],
            ],
          ))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('返回')),
        FilledButton(
            onPressed: valid
                ? () => Navigator.pop(context,
                    _Confirmation(_reason.text.trim(), _migration, _schema))
                : null,
            child: const Text('确认')),
      ],
    );
  }
}
