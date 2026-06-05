import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/services/api/comment_service.dart';
import 'package:facebook_clone/services/comic_service.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 公共评论区组件 — 帖子/漫展通用
///
/// 使用方式：
/// ```dart
/// CommentSection(
///   targetType: 'post',    // 或 'comic'
///   targetId: postId,      // 帖子ID或漫展eventId
///   scrollController: _scrollController,
/// )
/// ```
class CommentSection extends StatefulWidget {
  final String targetType; // 'post' 或 'comic'
  final int targetId;
  final ScrollController? scrollController;
  final String? heroTag;
  final void Function(int commentCount)? onCommentCountChanged;

  const CommentSection({
    super.key,
    required this.targetType,
    required this.targetId,
    this.scrollController,
    this.heroTag,
    this.onCommentCountChanged,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  final _inputScrollController = ScrollController();

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _hasMore = true;
  int _page = 1;
  final Set<int> _expandedReplies = {};
  final Set<int> _likingSet = {};
  final Set<int> _pendingRepliesLoads = {};

  String? _replyingToId;
  String? _replyingToName;
  int? _replyingToUserId;

  CommentService get _commentService => CommentService();
  ComicService get _comicService => ComicService();

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    _inputScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (!mounted) return;
    try {
      if (widget.targetType == 'comic') {
        final resp = await _comicService.getEventComments(widget.targetId, page: _page);
        if (resp.success && resp.data != null && mounted) {
          final data = resp.data as Map<String, dynamic>;
          final list = (data['comments'] as List?) ?? [];
          final total = data['total'] ?? 0;
          setState(() {
            _comments = list.cast<Map<String, dynamic>>();
            _hasMore = _comments.length < total;
            _isLoading = false;
          });
          widget.onCommentCountChanged?.call(total);
        }
      } else {
        final resp = await _commentService.getComments(widget.targetId, page: _page);
        if (resp.success && resp.data != null && mounted) {
          final data = resp.data as Map<String, dynamic>;
          final list = (data['comments'] as List?) ?? [];
          final total = data['total'] ?? 0;
          setState(() {
            _comments = list.cast<Map<String, dynamic>>();
            _hasMore = _comments.length < total;
            _isLoading = false;
          });
          widget.onCommentCountChanged?.call(total);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;
    _page++;
    await _loadComments();
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      if (widget.targetType == 'comic') {
        final resp = await _comicService.postEventComment(
          widget.targetId,
          content: content,
          parentId: _replyingToId != null ? int.tryParse(_replyingToId!) : null,
          replyToUserId: _replyingToUserId,
        );
        if (resp.success && resp.data != null && mounted) {
          final comment = resp.data!['comment'] as Map<String, dynamic>?;
          if (comment != null) {
            if (_replyingToId != null) {
              // 找到父评论并添加回复
              for (int i = 0; i < _comments.length; i++) {
                if (_comments[i]['id'].toString() == _replyingToId) {
                  final replies = List<Map<String, dynamic>>.from(_comments[i]['replies'] ?? []);
                  replies.add(comment);
                  _comments[i]['replies'] = replies;
                  _comments[i]['reply_count'] = (_comments[i]['reply_count'] ?? 0) + 1;
                  break;
                }
              }
            } else {
              _comments.insert(0, comment);
            }
            setState(() {});
          }
        }
      } else {
        final resp = await _commentService.createComment(
          widget.targetId,
          content,
          parentId: _replyingToId != null ? int.tryParse(_replyingToId!) : null,
        );
        if (resp.success && resp.data != null && mounted) {
          final comment = resp.data!['comment'] as Map<String, dynamic>?;
          if (comment != null) {
            if (_replyingToId != null) {
              for (int i = 0; i < _comments.length; i++) {
                if (_comments[i]['id'].toString() == _replyingToId) {
                  final replies = List<Map<String, dynamic>>.from(_comments[i]['replies'] ?? []);
                  replies.add(comment);
                  _comments[i]['replies'] = replies;
                  _comments[i]['reply_count'] = (_comments[i]['reply_count'] ?? 0) + 1;
                  break;
                }
              }
            } else {
              _comments.insert(0, comment);
            }
            setState(() {});
          }
        }
      }
      _commentController.clear();
      _cancelReply();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _startReply(Map<String, dynamic> comment) {
    setState(() {
      _replyingToId = comment['id'].toString();
      _replyingToName = (comment['user']?['display_name'] ?? comment['user']?['username'] ?? '用户').toString();
      _replyingToUserId = comment['user_id'] as int?;
    });
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
      _replyingToUserId = null;
    });
  }

  Future<void> _toggleLike(Map<String, dynamic> comment) async {
    final cid = comment['id'] as int;
    if (_likingSet.contains(cid)) return;
    _likingSet.add(cid);

    final wasLiked = comment['is_liked'] == true;
    // Optimistic update
    setState(() {
      comment['is_liked'] = !wasLiked;
      comment['like_count'] = (comment['like_count'] ?? 0) + (wasLiked ? -1 : 1);
    });

    try {
      if (widget.targetType == 'comic') {
        await _comicService.likeComment(cid);
      } else {
        if (!wasLiked) {
          await _commentService.likeComment(cid);
        } else {
          await _commentService.unlikeComment(cid);
        }
      }
    } catch (_) {
      // Revert
      if (mounted) {
        setState(() {
          comment['is_liked'] = wasLiked;
          comment['like_count'] = (comment['like_count'] ?? 0) + (wasLiked ? 1 : -1);
        });
      }
    } finally {
      _likingSet.remove(cid);
    }
  }

  Future<void> _loadMoreReplies(int parentId) async {
    _pendingRepliesLoads.add(parentId);
    try {
      if (widget.targetType == 'comic') {
        final resp = await _comicService.getCommentReplies(parentId);
        if (resp.success && resp.data != null && mounted) {
          if (!_expandedReplies.contains(parentId)) return;
          final replies = (resp.data!['replies'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (int i = 0; i < _comments.length; i++) {
            if (_comments[i]['id'] == parentId) {
              _comments[i]['replies'] = replies;
              setState(() {});
              break;
            }
          }
        }
      } else {
        final resp = await _commentService.getReplies(parentId);
        if (resp.success && resp.data != null && mounted) {
          if (!_expandedReplies.contains(parentId)) return;
          final replies = (resp.data!['replies'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (int i = 0; i < _comments.length; i++) {
            if (_comments[i]['id'] == parentId) {
              _comments[i]['replies'] = replies;
              setState(() {});
              break;
            }
          }
        }
      }
    } catch (_) {} finally {
      _pendingRepliesLoads.remove(parentId);
    }
  }

  void _toggleExpandReplies(int commentId) {
    if (_expandedReplies.contains(commentId)) {
      setState(() {
        _expandedReplies.remove(commentId);
        // 收起时清空回复数据，防止残留
        for (int i = 0; i < _comments.length; i++) {
          if (_comments[i]['id'] == commentId) {
            _comments[i]['replies'] = <Map<String, dynamic>>[];
            break;
          }
        }
      });
    } else {
      setState(() => _expandedReplies.add(commentId));
      _loadMoreReplies(commentId);
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确定要删除这条评论吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (widget.targetType == 'comic') {
        await _comicService.deleteComment(comment['id'] as int);
      } else {
        await _commentService.deleteComment(comment['id'] as int);
      }
      setState(() {
        _comments.removeWhere((c) => c['id'] == comment['id']);
      });
      widget.onCommentCountChanged?.call(_comments.length);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSheetScroll = widget.scrollController != null;

    if (hasSheetScroll) {
      // Sheet mode: input pinned at bottom, list scrolls internally
      return Column(
        children: [
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_comments.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('还没有评论，来说两句吧',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            Expanded(child: _buildCommentList()),
          _buildCommentInput(),
        ],
      );
    }

    // Inline mode (original behavior)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isLoading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('还没有评论，来说两句吧',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ],
              ),
            ),
          )
        else
          _buildCommentList(),
        _buildCommentInput(),
      ],
    );
  }

  Widget _buildCommentList() {
    final hasSheetScroll = widget.scrollController != null;
    return ListView.builder(
      controller: widget.scrollController,
      shrinkWrap: !hasSheetScroll,
      physics: hasSheetScroll ? null : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _comments.length + 1, // +1 for "load more"
      itemBuilder: (_, index) {
        if (index >= _comments.length) {
          if (!_hasMore) return const SizedBox(height: 16);
          return Center(
            child: TextButton(
              onPressed: _loadMore,
              child: const Text('加载更多', style: TextStyle(fontSize: 13)),
            ),
          );
        }
        final c = _comments[index];
        final auth = context.read<AuthProvider>();
        final isOwner = c['user_id'] == auth.user?.id;
        final isExpanded = _expandedReplies.contains(c['id'] as int);
        final replies = (c['replies'] as List?) ?? [];
        final replyCount = c['reply_count'] ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCommentItem(c, isOwner: isOwner),
              // Replies
              if (replies.isNotEmpty && isExpanded) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Column(
                    children: replies.map<Widget>((r) => _buildCommentItem(r, isOwner: r['user_id'] == auth.user?.id)).toList(),
                  ),
                ),
              ] else if (isExpanded && replyCount == 0)
                const SizedBox.shrink(),
              // Toggle expand
              if (replyCount > 0) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: GestureDetector(
                    onTap: () => _toggleExpandReplies(c['id'] as int),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        isExpanded ? '收起回复' : '查看 $replyCount 条回复',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
              const Divider(height: 1, thickness: 0.5),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment, {bool isOwner = false}) {
    final user = comment['user'] as Map<String, dynamic>?;
    final avatar = user?['avatar'] as String?;
    final displayName = user?['display_name'] ?? user?['username'] ?? '用户';
    final username = user?['username'] ?? '';
    final content = comment['content'] ?? '';
    final likeCount = comment['like_count'] ?? 0;
    final isLiked = comment['is_liked'] == true;
    final replyToUser = comment['reply_to_user'] as Map<String, dynamic>?;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ImageUtils.buildAvatar(user != null ? User.fromJson(user) : null, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  children: [
                    TextSpan(text: '$displayName ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (replyToUser != null) ...[
                      WidgetSpan(
                        child: Icon(Icons.reply, size: 12, color: AppColors.textSecondary),
                      ),
                      TextSpan(
                        text: ' ${replyToUser['display_name'] ?? replyToUser['username']}',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                    TextSpan(text: '  $content'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _formatTimeAgo(comment['created_at']),
                    style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => _startReply(comment),
                    child: const Text('回复', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                  if (isOwner) ...[
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _deleteComment(comment),
                      child: const Text('删除', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _toggleLike(comment),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          size: 13,
                          color: isLiked ? Colors.red : AppColors.textTertiary,
                        ),
                        if (likeCount > 0) ...[
                          const SizedBox(width: 2),
                          Text('$likeCount', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimeAgo(dynamic time) {
    if (time == null) return '';
    try {
      final dt = DateTime.tryParse(time.toString());
      if (dt == null) return '';
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}月${dt.day}日';
    } catch (_) {
      return '';
    }
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 8, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_replyingToName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Text('回复 $_replyingToName',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: TextField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: '写评论...',
                      hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isSending ? null : _submitComment,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _isSending ? AppColors.primary.withOpacity(0.5) : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: _isSending
                    ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
