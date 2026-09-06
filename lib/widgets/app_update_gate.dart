import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/models/app_update.dart';
import 'package:nonto/providers/app_update_notifier.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/external_link_service.dart';

class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(appUpdateProvider.notifier).check(automatic: true),
        );
      }
    });
  }

  Future<void> _openUpdate(AppUpdateInfo info) async {
    final opened = await const ExternalLinkService().perform(
      action: info.updateAction,
      url: info.downloadUrl,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新地址暂时无法打开，请稍后重试')),
      );
    }
  }

  Future<void> _showUpdateDialog(AppUpdateInfo info) async {
    if (_dialogVisible || !mounted) return;
    final navigatorContext =
        ApiClient.navigatorKey.currentState?.overlay?.context ??
            (Navigator.maybeOf(context) == null ? null : context);
    if (navigatorContext == null) return;
    _dialogVisible = true;
    await showDialog<void>(
      context: navigatorContext,
      barrierDismissible: !info.forceUpdate,
      builder: (dialogContext) {
        return PopScope(
          canPop: !info.forceUpdate,
          child: AlertDialog(
            title: Text(info.forceUpdate ? '需要更新' : '发现新版本'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('最新版本：${info.latestVersion ?? '-'}'),
                    if (info.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('更新内容',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ...info.releaseNotes.map((note) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• $note'),
                          )),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (!info.forceUpdate)
                TextButton(
                  onPressed: () {
                    ref.read(appUpdateProvider.notifier).dismissOptional();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('稍后'),
                ),
              FilledButton(
                onPressed: () => _openUpdate(info),
                child: Text(info.forceUpdate ? '立即更新' : '更新'),
              ),
            ],
          ),
        );
      },
    );
    _dialogVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppUpdateState>(appUpdateProvider, (previous, next) {
      if (next.shouldPresent && previous?.shouldPresent != true) {
        unawaited(_showUpdateDialog(next.info));
      }
    });
    return widget.child;
  }
}
