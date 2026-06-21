import 'package:nonto/config/app_theme.dart';
import 'package:nonto/data/emoji_data.dart';
import 'package:nonto/models/comment.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/comment_notifier.dart';
import 'package:nonto/providers/comment_state.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Public comment section — unified for posts and comic events.
///
/// Pure UI layer. All state is managed by [CommentNotifier] via Riverpod.
///
/// Usage:
/// ```dart
/// CommentSection(
///   targetType: 'post',
///   targetId: postId,
///   scrollController: _scrollController,
/// )
/// ```
class CommentSection extends ConsumerStatefulWidget {
  final String targetType; // 'post' | 'comic'
  final int targetId;
  final ScrollController? scrollController;
  final void Function(int commentCount)? onCommentCountChanged;

  const CommentSection({
    super.key,
    required this.targetType,
    required this.targetId,
    this.scrollController,
    this.onCommentCountChanged,
  });

  @override
  ConsumerState<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<CommentSection> {
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  final _inputScrollController = ScrollController();

  late final CommentSectionKey _sectionKey;

  bool _initialCountReported = false;

  /// 输入框是否有内容（去除首尾空白后）
  /// 用于驱动发送按钮的禁用/激活状态切换，与 chat_room_screen 保持一致
  final ValueNotifier<bool> _hasText = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _sectionKey = CommentSectionKey(
      targetType: widget.targetType,
      targetId: widget.targetId,
    );
    _commentController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _commentController.removeListener(_onTextChanged);
    _commentController.dispose();
    _commentFocusNode.dispose();
    _inputScrollController.dispose();
    _hasText.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _hasText.value = _commentController.text.trim().isNotEmpty;
  }

  CommentNotifier get _notifier => ref.read(commentProvider(_sectionKey).notifier);
  CommentState get _state => ref.watch(commentProvider(_sectionKey));

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Report comment count once loaded
    if (!state.isLoading && !_initialCountReported) {
      _initialCountReported = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onCommentCountChanged?.call(state.comments.length);
      });
    }

    // Error banner
    if (state.error != null && state.comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: colors.error),
              const SizedBox(height: 12),
              Text(state.error!, style: TextStyle(color: colors.error)),
            ],
          ),
        ),
      );
    }

    final hasSheetScroll = widget.scrollController != null;

    return Column(
      children: [
        Expanded(
          child: state.isLoading && state.comments.isEmpty
              ? const _CommentSkeleton()
              : state.comments.isEmpty
                  ? _buildEmptyState(colors)
                  : _buildCommentList(colors, hasSheetScroll),
        ),
        _buildCommentInput(colors, state),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Empty State
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState(ColorScheme colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 48, color: colors.outlineVariant),
          const SizedBox(height: 12),
          Text(
            '还没有评论，来说两句吧',
            style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Comment List
  // ═══════════════════════════════════════════════════════════

  Widget _buildCommentList(ColorScheme colors, bool hasSheetScroll) {
    final state = _state;
    return ListView.builder(
      controller: widget.scrollController,
      shrinkWrap: !hasSheetScroll,
      physics: hasSheetScroll ? null : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: state.comments.length + 1,
      itemBuilder: (_, index) {
        if (index >= state.comments.length) {
          if (!state.hasMore) return const SizedBox(height: 16);
          return _AutoLoadMore(
            isLoading: state.isLoading,
            onVisible: () {
              if (!state.isLoading && state.hasMore) {
                _notifier.loadMore();
              }
            },
          );
        }

        final comment = state.comments[index];
        final isExpanded = state.expandedReplies.contains(comment.id);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CommentItem(
                comment: comment,
                targetType: widget.targetType,
                isOwner: false, // handled inside
                onReply: () => _notifier.startReply(
                  comment.id.toString(),
                  comment.user?.displayName ?? comment.user?.username ?? '用户',
                  comment.userId,
                ),
                onLike: () => _notifier.toggleLike(comment.id),
                onDelete: () => _confirmDelete(comment),
                isLiking: state.likingIds.contains(comment.id),
              ),
              // Reply list — show expand button only if there are replies
              if (comment.replyCount > 0) ...[
                if (comment.replies.isNotEmpty && isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(left: 48),
                    child: Column(
                      children: [
                        ...comment.replies.map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: _CommentItem(
                            comment: r,
                            targetType: widget.targetType,
                            isOwner: false,
                            onReply: () => _notifier.startReply(
                              r.id.toString(),
                              r.user?.displayName ?? r.user?.username ?? '用户',
                              r.userId,
                            ),
                            onLike: () => _notifier.toggleLike(r.id),
                            onDelete: () => _confirmDelete(r),
                            isLiking: state.likingIds.contains(r.id),
                          ),
                        )),
                        if (comment.repliesHasMore)
                          _AutoLoadMore(
                            isLoading: state.loadingRepliesIds.contains(comment.id),
                            key: ValueKey('reply_more_${comment.id}'),
                            onVisible: () {
                              _notifier.loadMoreReplies(comment.id);
                            },
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 48, top: 0),
                  child: GestureDetector(
                    onTap: () => _notifier.toggleExpandReplies(comment.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        isExpanded ? '收起回复' : '查看 ${comment.replyCount} 条回复',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const Divider(height: 1, thickness: 0.3, indent: 0),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(Comment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除评论',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text('确定要删除这条评论吗？',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final ok = await _notifier.deleteComment(comment.id);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Comment Input — Twitter/X 风格，与聊天室 (chat_room_screen) 输入栏一致
  //  • 顶部细分割线 (AppColors.borderLight)
  //  • 输入框：AppColors.surface (#F7F9F9) 圆角药丸 + 极淡边框
  //  • Emoji 按钮使用主蓝色平铺图标，无背景方块
  //  • 发送按钮：仅在有内容时显示蓝色图标，无内容时占位防止高度抖动
  //  • 回复 chip 改用 AppColors.selectionHighlight (淡蓝)，与 X 风格回复气泡一致
  // ═══════════════════════════════════════════════════════════

  Widget _buildCommentInput(ColorScheme colors, CommentState state) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.borderLight, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply chip — Twitter 风格淡蓝底
          if (state.replyingToName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.selectionHighlight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '回复 ${state.replyingToName}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: _notifier.cancelReply,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 16, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Emoji button — 与 chat_room_screen 一致：纯图标，无背景方块
              IconButton(
                onPressed: () => _showEmojiPicker(context, colors),
                icon: const Icon(
                  Icons.emoji_emotions_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.borderLight,
                      width: 0.8,
                    ),
                  ),
                  child: TextField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    maxLines: null,
                    minLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: '写评论...',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: AppColors.textTertiary,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: _submitWithText,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Send button — 仅在有文字 / 发送中时显示，与聊天室一致
              ValueListenableBuilder<bool>(
                valueListenable: _hasText,
                builder: (_, hasText, __) {
                  if (!hasText && !state.isSending) {
                    // 占位，避免高度抖动
                    return const SizedBox(width: 36, height: 36);
                  }
                  if (state.isSending) {
                    return const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  }
                  return IconButton(
                    onPressed: () => _submitWithText(_commentController.text),
                    icon: const Icon(
                      Icons.send_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submitWithText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_state.isSending) return; // 防止快速双击/异步竞态
    _commentController.clear();
    _commentFocusNode.unfocus();
    final error = await _notifier.submitComment(trimmed);
    if (error != null && mounted) {
      // 发送失败，将内容恢复到输入框
      _commentController.text = trimmed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Emoji Picker — 统一使用 EmojiData.categories，与聊天室一致
  // ═══════════════════════════════════════════════════════════

  void _insertEmoji(String emoji) {
    final text = _commentController.text;
    final selection = _commentController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _commentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _commentFocusNode.requestFocus();
  }

  void _showEmojiPicker(BuildContext context, ColorScheme colors) {
    final currentIndexNotifier = ValueNotifier<int>(0);
    final categories = EmojiData.categories;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.42,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Category tabs (emoji icons)
              SizedBox(
                height: 44,
                child: Row(
                  children: List.generate(categories.length, (i) {
                    return Expanded(
                      child: ValueListenableBuilder<int>(
                        valueListenable: currentIndexNotifier,
                        builder: (_, tabIndex, __) {
                          final active = i == tabIndex;
                          return GestureDetector(
                            onTap: () => currentIndexNotifier.value = i,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: active ? colors.primary : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Text(categories[i].key, style: const TextStyle(fontSize: 20)),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 4),
              Divider(height: 1, thickness: 0.3, color: colors.outlineVariant),
              // Emoji grid
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: currentIndexNotifier,
                  builder: (_, tabIndex, __) {
                    final emojis = categories[tabIndex].value;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: emojis.length,
                      itemBuilder: (_, i) => InkWell(
                        onTap: () {
                          _insertEmoji(emojis[i]);
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Center(
                          child: Text(emojis[i], style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _CommentItem — individual comment widget (top-level or reply)
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentItem extends ConsumerWidget {
  final Comment comment;
  final String targetType;
  final bool isOwner;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final bool isLiking;

  const _CommentItem({
    required this.comment,
    required this.targetType,
    required this.isOwner,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.isLiking,
  });

  void _navigateToProfile(BuildContext context, User? user) {
    if (user == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => UserProfileScreen(user: user),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final user = comment.user;
    final displayName = user?.displayName ?? user?.username ?? '用户';
    final isOwnerCheck = user?.id == ref.watch(authProvider).user?.id;
    final double touchSize = 44; // M3 minimum touch target

    // 整条评论可点击触发回复
    return GestureDetector(
      onTap: onReply,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar — 可点击进入个人主页
            GestureDetector(
              onTap: () => _navigateToProfile(context, user),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ImageUtils.buildAvatar(user, radius: 16),
              ),
            ),
            const SizedBox(width: 10),
            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：名字 + @被回复人 + 时间 + 点赞
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => _navigateToProfile(context, user),
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                            if (comment.replyToUser != null)
                              GestureDetector(
                                onTap: () => _navigateToProfile(context, comment.replyToUser),
                                child: Text(
                                  '@${comment.replyToUser!.displayName ?? comment.replyToUser!.username}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                            Text(
                              AppDateUtils.formatTimeAgo(comment.createdAt),
                              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Like button
                      SizedBox(
                        width: touchSize,
                        height: touchSize,
                        child: TextButton(
                          onPressed: isLiking ? null : onLike,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(40, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                comment.isLiked ? Icons.favorite : Icons.favorite_border,
                                size: 14,
                                color: comment.isLiked ? AppColors.likeRed : colors.onSurfaceVariant,
                              ),
                              if (comment.likeCount > 0) ...[
                                const SizedBox(width: 2),
                                Text(
                                  '${comment.likeCount}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: comment.isLiked ? AppColors.likeRed : colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 内容行
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      comment.content,
                      style: TextStyle(fontSize: 13, color: colors.onSurface),
                    ),
                  ),
                  // 删除按钮（仅自己可见）
                  if (isOwnerCheck)
                    SizedBox(
                      width: touchSize,
                      height: touchSize,
                      child: TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '删除',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _AutoLoadMore — 自动触发加载更多（VisibilityDetector 驱动）
// ═══════════════════════════════════════════════════════════════════════════════

class _AutoLoadMore extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onVisible;

  const _AutoLoadMore({
    super.key,
    required this.isLoading,
    required this.onVisible,
  });

  @override
  State<_AutoLoadMore> createState() => _AutoLoadMoreState();
}

class _AutoLoadMoreState extends State<_AutoLoadMore> {
  bool _hasTriggered = false;
  bool _wasLoading = false;

  @override
  void didUpdateWidget(covariant _AutoLoadMore oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 加载完成后重置触发标记，以便下一批数据也能自动加载
    if (_wasLoading && !widget.isLoading) {
      _hasTriggered = false;
    }
    _wasLoading = widget.isLoading;
  }

  @override
  Widget build(BuildContext context) {
    _wasLoading = widget.isLoading;
    return VisibilityDetector(
      key: widget.key ?? const Key('auto_load_more'),
      onVisibilityChanged: (info) {
        if (!_hasTriggered && info.visibleFraction > 0.5) {
          _hasTriggered = true;
          widget.onVisible();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: widget.isLoading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : null,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _CommentSkeleton — loading placeholder
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleContainer(radius: 16, color: colors.surfaceContainerHighest),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    width: 80,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CircleContainer extends StatelessWidget {
  final double radius;
  final Color color;
  const CircleContainer({super.key, required this.radius, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}