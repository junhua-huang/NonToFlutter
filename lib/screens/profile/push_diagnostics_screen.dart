import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/local_notification_service.dart';
import 'package:nonto/services/push_diagnostics_service.dart';

/// Hidden diagnostics for vendor notification delivery and foreground WS state.
class PushDiagnosticsScreen extends StatefulWidget {
  const PushDiagnosticsScreen({super.key});

  @override
  State<PushDiagnosticsScreen> createState() => _PushDiagnosticsScreenState();
}

class _PushDiagnosticsScreenState extends State<PushDiagnosticsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _diagnostics;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await PushDiagnosticsService().collect();
      if (!mounted) return;
      setState(() => _diagnostics = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final data = _diagnostics;
    if (data == null) return;
    final text = PushDiagnosticsService().format(data);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('诊断信息已复制')),
    );
  }

  Future<void> _sendTestNotification() async {
    final ok = await LocalNotificationService().showTestNotification();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已发送通知测试' : '通知测试未发出，请查看诊断')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _diagnostics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('推送诊断'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Flutter WebSocket 仅在前台连接；后台或被结束后由厂商推送送达。此页面只展示投递健康状态，不展示消息内容。',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新诊断'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: data == null ? null : _copy,
                    icon: const Icon(Icons.copy),
                    label: const Text('复制诊断信息'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _sendTestNotification,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('发送通知测试'),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _buildError(_error!)
            else if (data != null) ...[
              _buildSection('设备与通知', data['device']),
              const SizedBox(height: 12),
              _buildSection('阿里云推送', data['aliyunPush']),
              const SizedBox(height: 12),
              _buildSection('华为厂商推送', data['huaweiVendor']),
              const SizedBox(height: 12),
              _buildSection('阿里云原生回调', data['aliyunNative']),
              const SizedBox(height: 12),
              _buildSection('Flutter WebSocket（仅前台）', data['webSocket']),
              const SizedBox(height: 12),
              _buildSection('通知权限测试', data['localNotification']),
              const SizedBox(height: 12),
              _buildRawText(PushDiagnosticsService().format(data)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, Object? value) {
    final map = value is Map ? value : const <String, dynamic>{};
    final visibleEntries = map.entries.where(
      (entry) => entry.value != null && entry.value.toString().isNotEmpty,
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          for (final entry in visibleEntries)
            _buildRow(entry.key.toString(), entry.value),
        ],
      ),
    );
  }

  Widget _buildRow(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 154,
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.toString(),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildError(String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(0x12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withAlpha(0x33)),
      ),
      child: Text(error, style: const TextStyle(color: Colors.red)),
    );
  }
}
