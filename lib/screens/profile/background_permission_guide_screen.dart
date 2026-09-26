import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nonto/config/app_theme.dart';

/// Optional system settings that can affect vendor push delivery.
class BackgroundPermissionGuideScreen extends StatelessWidget {
  const BackgroundPermissionGuideScreen({super.key});

  static const MethodChannel _channel = MethodChannel('nonto/app_settings');

  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<bool>('openAppSettings');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('厂商推送通知设置'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '南图在后台或应用被结束后，通过阿里云及手机厂商推送送达通知。以下设置只会影响厂商推送送达，不用于维持 WebSocket 连接。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _step('1', '允许通知', '在系统设置中允许南图发送通知，并确认消息提醒分类已开启。'),
          _step(
            '2',
            '检查应用启动设置',
            '部分华为、OPPO、vivo 等机型会限制厂商推送组件，可在手机管家或应用启动管理中允许南图自动管理或自启动。',
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings),
            label: const Text('去系统设置'),
          ),
          const SizedBox(height: 16),
          Text(
            '不同品牌和系统版本的设置名称可能不同；若通知已正常送达，无需修改其他设置。',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _step(String index, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, child: Text(index)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
