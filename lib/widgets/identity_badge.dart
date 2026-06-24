import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';

class IdentityBadge extends StatelessWidget {
  final String? label;
  final EdgeInsetsGeometry padding;

  const IdentityBadge({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    final text = label?.trim();
    if (text == null || text.isEmpty || text == '普通用户') {
      return const SizedBox.shrink();
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
