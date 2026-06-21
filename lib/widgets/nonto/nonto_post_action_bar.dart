import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nonto/config/app_theme.dart';

const String _commentIconPath =
    'M1.751 10c0-4.42 3.584-8 8.005-8h4.366c4.49 0 8.129 3.64 8.129 8.13 0 2.96-1.607 5.68-4.196 7.11l-8.054 4.46v-3.69h-.067c-4.49.1-8.183-3.51-8.183-8.01zm8.005-6c-3.317 0-6.005 2.69-6.005 6 0 3.37 2.77 6.08 6.138 6.01l.351-.01h1.761v2.3l5.087-2.81c1.951-1.08 3.163-3.13 3.163-5.36 0-3.39-2.744-6.13-6.129-6.13H9.756z';
const String _heartOutlineIconPath =
    'M16.697 5.5c-1.222-.06-2.679.51-3.89 2.16l-.805 1.09-.806-1.09C9.984 6.01 8.526 5.44 7.304 5.5c-1.243.07-2.349.78-2.91 1.91-.552 1.12-.633 2.78.479 4.82 1.074 1.97 3.257 4.27 7.129 6.61 3.87-2.34 6.052-4.64 7.126-6.61 1.111-2.04 1.03-3.7.477-4.82-.561-1.13-1.666-1.84-2.908-1.91zm4.187 7.69c-1.351 2.48-4.001 5.12-8.379 7.67l-.503.3-.504-.3c-4.379-2.55-7.029-5.19-8.382-7.67-1.36-2.5-1.41-4.86-.514-6.67.887-1.79 2.647-2.91 4.601-3.01 1.651-.09 3.368.56 4.798 2.01 1.429-1.45 3.146-2.1 4.796-2.01 1.954.1 3.714 1.22 4.601 3.01.896 1.81.846 4.17-.514 6.67z';
const String _heartFilledIconPath =
    'M20.884 13.19c-1.351 2.48-4.001 5.12-8.379 7.67l-.503.3-.504-.3c-4.379-2.55-7.029-5.19-8.382-7.67-1.36-2.5-1.41-4.86-.514-6.67.887-1.79 2.647-2.91 4.601-3.01 1.651-.09 3.368.56 4.798 2.01 1.429-1.45 3.146-2.1 4.796-2.01 1.954.1 3.714 1.22 4.601 3.01.896 1.81.846 4.17-.514 6.67z';
const String _statsIconPath =
    'M8.75 21V3h2v18h-2zM18 21V8.5h2V21h-2zM4 21l.004-10h2L6 21H4zm9.248 0v-7h2v7h-2z';
const String _shareIconPath =
    'M12 2.59l5.7 5.7-1.41 1.42L13 6.41V16h-2V6.41l-3.3 3.3-1.41-1.42L12 2.59zM21 15l-.02 3.51c0 1.38-1.12 2.49-2.5 2.49H5.5C4.11 21 3 19.88 3 18.5V15h2v3.5c0 .28.22.5.5.5h12.98c.28 0 .5-.22.5-.5L19 15h2z';

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
            iconPath: _commentIconPath,
            count: commentCount,
            onTap: onComment,
          ),
          NontoLikeButton(
            isLiked: isLiked,
            count: likeCount,
            onTap: onLike,
          ),
          NontoPostActionButton(
            iconPath: _statsIconPath,
            count: viewCount,
            onTap: onView,
          ),
          if (onShare != null)
            NontoPostActionButton(
              iconPath: _shareIconPath,
              count: 0,
              onTap: onShare!,
            ),
        ],
      ),
    );
  }
}

class NontoLikeButton extends StatelessWidget {
  final bool isLiked;
  final int count;
  final VoidCallback onTap;

  const NontoLikeButton({
    super.key,
    required this.isLiked,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isLiked ? AppColors.likeRed : AppColors.textSecondary;
    return NontoPostActionButton(
      iconPath: isLiked ? _heartFilledIconPath : _heartOutlineIconPath,
      count: count,
      color: color,
      onTap: onTap,
      iconBuilder: (_) => NontoAnimatedLikeIcon(
        isLiked: isLiked,
        size: 18,
        likedColor: AppColors.likeRed,
        unlikedColor: AppColors.textSecondary,
      ),
    );
  }
}

class NontoAnimatedLikeIcon extends StatefulWidget {
  final bool isLiked;
  final double size;
  final Color likedColor;
  final Color unlikedColor;

  const NontoAnimatedLikeIcon({
    super.key,
    required this.isLiked,
    required this.size,
    required this.likedColor,
    required this.unlikedColor,
  });

  @override
  State<NontoAnimatedLikeIcon> createState() => _NontoAnimatedLikeIconState();
}

class _NontoAnimatedLikeIconState extends State<NontoAnimatedLikeIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 0.72), weight: 24),
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.28), weight: 38),
      TweenSequenceItem(tween: Tween(begin: 1.28, end: 1), weight: 38),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant NontoAnimatedLikeIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isLiked && widget.isLiked) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: NontoSvgIcon(
        widget.isLiked ? _heartFilledIconPath : _heartOutlineIconPath,
        size: widget.size,
        color: widget.isLiked ? widget.likedColor : widget.unlikedColor,
      ),
    );
  }
}

class NontoPostActionButton extends StatelessWidget {
  final String iconPath;
  final int count;
  final Color? color;
  final VoidCallback onTap;
  final Widget Function(Widget icon)? iconBuilder;

  const NontoPostActionButton({
    super.key,
    required this.iconPath,
    required this.count,
    this.color,
    required this.onTap,
    this.iconBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;
    final label = formatNontoCompactCount(count);
    final icon = NontoSvgIcon(iconPath, size: 18, color: effectiveColor);
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
              iconBuilder?.call(icon) ?? icon,
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

class NontoSvgIcon extends StatelessWidget {
  final String path;
  final double size;
  final Color color;

  const NontoSvgIcon(
    this.path, {
    super.key,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      '<svg width="$size" height="$size" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="$path" fill="currentColor"/></svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
