import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/widgets/identity_badge.dart';

class ProfileIdentitySection extends StatelessWidget {
  final List<String> labels;
  final bool isOwnProfile;
  final VoidCallback? onManage;

  const ProfileIdentitySection({
    super.key,
    required this.labels,
    this.isOwnProfile = false,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty && !isOwnProfile) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (labels.isNotEmpty)
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: labels
                    .map(
                      (label) => IdentityBadge(
                        label: label,
                        margin: EdgeInsets.zero,
                      ),
                    )
                    .toList(),
              ),
            )
          else
            Expanded(
              child: Text(
                '还没有认证身份',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          if (isOwnProfile && onManage != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onManage,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(labels.isEmpty ? '申请身份' : '管理'),
            ),
          ],
        ],
      ),
    );
  }
}
