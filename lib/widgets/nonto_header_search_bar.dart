import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/utils/image_utils.dart';

class NontoHeaderSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final User? user;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onAvatarTap;
  final Widget? suffixIcon;
  final Widget? trailing;
  final bool keepExpandedWhenNotEmpty;

  const NontoHeaderSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.user,
    this.onChanged,
    this.onSubmitted,
    this.onAvatarTap,
    this.suffixIcon,
    this.trailing,
    this.keepExpandedWhenNotEmpty = true,
  });

  @override
  State<NontoHeaderSearchBar> createState() => _NontoHeaderSearchBarState();
}

class _NontoHeaderSearchBarState extends State<NontoHeaderSearchBar> {
  late final FocusNode _ownedFocusNode;
  late final FocusNode _focusNode;
  bool _hasFocus = false;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  bool get showAvatar =>
      !_hasFocus && !(widget.keepExpandedWhenNotEmpty && _hasText);

  @override
  void initState() {
    super.initState();
    _ownedFocusNode = FocusNode();
    _focusNode = widget.focusNode ?? _ownedFocusNode;
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_syncFocus);
    widget.controller.addListener(_syncText);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_syncFocus);
    widget.controller.removeListener(_syncText);
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _syncFocus() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  void _syncText() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: showAvatar
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: showAvatar ? 1 : 0,
                        child: NontoHeaderAvatar(
                          user: widget.user,
                          radius: 18,
                          onTap: widget.onAvatarTap,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  onTapOutside: (_) => _focusNode.unfocus(),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    suffixIcon: widget.suffixIcon,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 0,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );
  }
}

class NontoHeaderAvatar extends StatelessWidget {
  final User? user;
  final double radius;
  final VoidCallback? onTap;

  const NontoHeaderAvatar({
    super.key,
    required this.user,
    this.radius = 18,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = ImageUtils.buildAvatar(user, radius: radius);
    if (onTap == null) return avatar;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: avatar,
    );
  }
}
