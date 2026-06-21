import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';

String formatNontoCompactCount(int count) {
  if (count <= 0) return '';
  if (count < 1000) return '$count';
  if (count < 10000) {
    final value = count / 1000;
    final truncated = (value * 10).truncate() / 10;
    return truncated == truncated.truncateToDouble()
        ? '${truncated.toInt()}K'
        : '${truncated.toStringAsFixed(1)}K';
  }
  final value = count / 10000;
  final truncated = (value * 10).truncate() / 10;
  return truncated == truncated.truncateToDouble()
      ? '${truncated.toInt()}万'
      : '${truncated.toStringAsFixed(1)}万';
}

class NontoPostActionBar extends StatelessWidget {
  final int commentCount;
  final int likeCount;
  final int viewCount;
  final bool isLiked;
  final VoidCallback onComment;
  final VoidCallback onLike;
  final VoidCallback onView;
  final VoidCallback? onShare;
  final EdgeInsetsGeometry padding;

  const NontoPostActionBar({
    super.key,
    required this.commentCount,
    required this.likeCount,
    required this.viewCount,
    required this.isLiked,
    required this.onComment,
    required this.onLike,
    required this.onView,
    this.onShare,
    this.padding = const EdgeInsets.fromLTRB(8, 8, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          NontoPostActionButton(
            icon: Icons.comment_outlined,
            count: commentCount,
            onTap: onComment,
          ),
          NontoPostActionButton(
            icon: isLiked ? Icons.favorite : Icons.favorite_border,
            count: likeCount,
            color: isLiked ? AppColors.likeRed : null,
            onTap: onLike,
          ),
          NontoPostActionButton(
            icon: Icons.bar_chart,
            count: viewCount,
            onTap: onView,
          ),
          if (onShare != null)
            NontoPostActionButton(
              icon: Icons.ios_share_outlined,
              count: 0,
              onTap: onShare!,
            ),
        ],
      ),
    );
  }
}

class NontoPostActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const NontoPostActionButton({
    super.key,
    required this.icon,
    required this.count,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;
    final label = formatNontoCompactCount(count);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: effectiveColor),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(color: effectiveColor, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
