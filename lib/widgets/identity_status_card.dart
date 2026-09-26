import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/identity_application.dart';

class IdentityStatusCard extends StatelessWidget {
  final IdentityApplication application;
  final VoidCallback? onTap;

  const IdentityStatusCard({
    super.key,
    required this.application,
    this.onTap,
  });

  Color get _statusColor {
    if (application.isVerified) return AppColors.primary;
    if (application.isPending) return Colors.orange;
    if (application.needsMoreInfo) return Colors.purple;
    if (application.isRejected) return Colors.red;
    return AppColors.textSecondary;
  }

  IconData get _statusIcon {
    if (application.isVerified) return Icons.verified_outlined;
    if (application.isPending) return Icons.hourglass_empty;
    if (application.needsMoreInfo) return Icons.error_outline;
    if (application.isRejected) return Icons.cancel_outlined;
    return Icons.pause_circle_outline;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.borderLight),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_statusIcon, color: _statusColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${application.roleLabel} ${application.statusLabel}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      application.isVerified
                          ? '可在主页和帖子中展示'
                          : application.isPending
                              ? '已提交申请，等待管理员审核'
                              : application.reviewComment ?? '查看认证状态和提交材料',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
