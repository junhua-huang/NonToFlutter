import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/widgets/identity_badge.dart';

class PostAuthorMetaLine extends StatelessWidget {
  final Post post;
  final bool showUsername;
  final VoidCallback? onTap;

  const PostAuthorMetaLine({
    super.key,
    required this.post,
    this.showUsername = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = post.user?.displayName ?? '未知用户';
    final username = post.user?.username ?? '';
    final time = AppDateUtils.formatTimeAgo(post.createdAt);

    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IdentityBadge(label: post.displayRoleLabel),
          if (showUsername && username.isNotEmpty) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '@$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Text('· $time',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
