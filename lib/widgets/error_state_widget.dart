import 'package:nonto/config/app_theme.dart';
import 'package:flutter/material.dart';

/// 通用错误状态组件（图标 + 错误文字 + 重试按钮）
class ErrorStateWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final String? retryLabel;
  final VoidCallback? onRetry;

  const ErrorStateWidget({
    super.key,
    this.message = '加载失败',
    this.icon = Icons.error_outline,
    this.retryLabel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(retryLabel ?? '重试'),
            ),
          ],
        ],
      ),
    );
  }
}
