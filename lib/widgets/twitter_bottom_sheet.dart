import 'package:facebook_clone/config/app_theme.dart';
import 'package:flutter/material.dart';

/// 推特风格底部选项弹窗 — 统一组件
///
/// - 底部滑入，300ms 过渡
/// - 白色卡片，顶部大圆角
/// - 拖拽指示条，无标题和关闭按钮
/// - 选项：左图标 + 右文字，间隔细线
/// - 危险操作用红色文字
/// - 半透明遮罩，点击关闭
///
/// 用法：
/// ```dart
/// final result = await TwitterBottomSheet.show<String>(
///   context,
///   groupLabel: '更多操作',
///   options: [
///     TwitterSheetOption(icon: Icons.edit, label: '编辑', value: 'edit'),
///     TwitterSheetOption(icon: Icons.delete, label: '删除', value: 'delete', isDestructive: true),
///   ],
/// );
/// ```

/// 单个选项模型
class TwitterSheetOption<T> {
  final IconData icon;
  final String label;
  final T value;
  final bool isDestructive;

  const TwitterSheetOption({
    required this.icon,
    required this.label,
    required this.value,
    this.isDestructive = false,
  });
}

/// 弹窗入口
class TwitterBottomSheet {
  TwitterBottomSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    String? groupLabel,
    required List<TwitterSheetOption<T>> options,
    Color? destructiveColor,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      transitionAnimationController: null,
      builder: (ctx) => _TwitterSheetContent<T>(
        groupLabel: groupLabel,
        options: options,
        destructiveColor: destructiveColor ?? AppColors.likeRed,
      ),
    );
  }
}

/// 弹窗主体
class _TwitterSheetContent<T> extends StatelessWidget {
  final String? groupLabel;
  final List<TwitterSheetOption<T>> options;
  final Color destructiveColor;

  const _TwitterSheetContent({
    this.groupLabel,
    required this.options,
    required this.destructiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: bottomPadding > 0 ? bottomPadding : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽指示条
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.borderDivider,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 分组标签
            if (groupLabel != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  groupLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.borderLight, indent: 20, endIndent: 20),
            ],
            // 选项列表
            for (int i = 0; i < options.length; i++) ...[
              if (i > 0 || groupLabel != null)
                const Divider(height: 1, color: AppColors.borderLight, indent: 20, endIndent: 0),
              _OptionTile<T>(
                option: options[i],
                destructiveColor: destructiveColor,
                onTap: () => Navigator.pop(context, options[i].value),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 单个选项 Tile
class _OptionTile<T> extends StatelessWidget {
  final TwitterSheetOption<T> option;
  final Color destructiveColor;
  final VoidCallback onTap;

  const _OptionTile({
    required this.option,
    required this.destructiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        option.isDestructive ? destructiveColor : AppColors.textPrimary;
    final iconColor =
        option.isDestructive ? destructiveColor : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.borderLight,
        highlightColor: AppColors.borderLight.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Icon(option.icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 4),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 15,
                  color: textColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
