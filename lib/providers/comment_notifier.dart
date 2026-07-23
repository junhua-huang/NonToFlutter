import 'package:nonto/models/comment.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/comment_state.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/comment_service.dart';
import 'package:nonto/services/comic_service.dart';
import 'package:nonto/services/sound_service.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Family parameter for comment provider — identifies a comment section uniquely.
class CommentSectionKey {
  final String targetType; // 'post' | 'comic'
  final int targetId;

  const CommentSectionKey({required this.targetType, required this.targetId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommentSectionKey &&
          targetType == other.targetType &&
          targetId == other.targetId;

  @override
  int get hashCode => Object.hash(targetType, targetId);
}

/// Riverpod StateNotifier managing comment state for a single target (post / comic).
///
/// Handles:
///   - Loading / pagination
///   - Submit comment / reply
///   - Like / unlike (optimistic)
///   - Delete
///   - Expand replies
///   - Reply targeting
class CommentNotifier extends StateNotifier<CommentState> {
  static final Set<CommentNotifier> _activeNotifiers = {};

  static void removeUserFromActiveSections(int userId) {
    for (final notifier in List<CommentNotifier>.from(_activeNotifiers)) {
      notifier.removeCommentsByUser(userId);
    }
  }

  final CommentSectionKey key;
  final CommentService _commentService = CommentService();
  final ComicService _comicService = ComicService();
  final User? _currentUser; // 用于乐观更新显示头像和名称

  CommentNotifier(
    this.key, {
    User? currentUser,
    CommentState initialState = const CommentState(),
    bool loadOnInit = true,
  })  : _currentUser = currentUser,
        super(initialState) {
    _activeNotifiers.add(this);
    if (loadOnInit) loadComments();
  }

  bool get _isPost => key.targetType == 'post';
  bool get _isComic => key.targetType == 'comic';

  void _warnUnknownTarget() {
    if (!_isPost && !_isComic) {
      debugPrint(
          '[CommentNotifier] ⚠️ Unknown targetType "${key.targetType}" — falling back to comic API');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Loading & Pagination
  // ═══════════════════════════════════════════════════════════

  Future<void> loadComments() async {
    if (!mounted) return;
    _warnUnknownTarget();
    state = state.copyWith(isLoading: true, error: null);
    try {
      final List<Comment> comments;
      final bool hasMore;
      final Map<String, dynamic>? data;

      if (_isPost) {
        final resp =
            await _commentService.getComments(key.targetId, page: state.page);
        data = resp.data as Map<String, dynamic>?;
      } else {
        final resp = await _comicService.getEventComments(key.targetId,
            page: state.page);
        data = resp.data;
      }

      if (data != null) {
        final list = (data['comments'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        comments = list.map((e) => Comment.fromJson(e)).toList();
        final total = data['total'] ?? 0;
        hasMore =
            comments.length < (total is int ? total : comments.length + 1);
      } else {
        comments = [];
        hasMore = false;
      }

      if (mounted) {
        // 合并：保留本地已添加但服务器尚未返回的评论，避免加载覆盖
        final serverIds = comments.map((c) => c.id).toSet();
        final kept = state.comments
            .where((c) => c.id < 0 || !serverIds.contains(c.id))
            .toList();
        state = state.copyWith(
          comments: [...kept, ...comments],
          isLoading: false,
          hasMore: hasMore,
          error: null,
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: '评论加载失败');
      }
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoading: true);
    final nextPage = state.page + 1;
    try {
      final List<Comment> newComments;
      final Map<String, dynamic>? data;

      if (_isPost) {
        final resp =
            await _commentService.getComments(key.targetId, page: nextPage);
        data = resp.data as Map<String, dynamic>?;
      } else {
        final resp =
            await _comicService.getEventComments(key.targetId, page: nextPage);
        data = resp.data;
      }

      if (data != null) {
        final list = (data['comments'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        newComments = list.map((e) => Comment.fromJson(e)).toList();
        final total = data['total'] ?? 0;
        if (mounted) {
          state = state.copyWith(
            comments: [...state.comments, ...newComments],
            isLoading: false,
            hasMore: state.comments.length + newComments.length <
                (total is int
                    ? total
                    : state.comments.length + newComments.length + 1),
            page: nextPage,
          );
        }
      } else {
        if (mounted) state = state.copyWith(isLoading: false, hasMore: false);
      }
    } catch (e) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Submit Comment (乐观更新 + 音效)
  // ═══════════════════════════════════════════════════════════

  /// 提交评论或回复，先乐观显示再异步发送，失败则回退内容到输入框。
  /// 返回 null 表示成功，返回 String 表示失败时的错误消息（内容回退到输入框）。
  Future<String?> submitComment(String content) async {
    final text = content.trim();
    if (text.isEmpty || state.isSending) return null;

    final parentId =
        state.replyingToId != null ? int.tryParse(state.replyingToId!) : null;
    final replyingToUserId = state.replyingToUserId;

    // 立即播放发送音效
    SoundService().playSendSound();

    // 乐观更新：立即显示评论，使用当前登录用户信息
    final optimisticComment = Comment(
      id: -DateTime.now().millisecondsSinceEpoch,
      content: text,
      userId: _currentUser?.id ?? 0,
      user: _currentUser,
      postId: key.targetId,
      parentId: parentId,
      replyToUserId: replyingToUserId,
      likeCount: 0,
      replyCount: 0,
      isLiked: false,
      createdAt: DateTime.now(),
      replies: const [],
    );

    if (parentId != null) {
      final updated = List<Comment>.from(state.comments);
      for (int i = 0; i < updated.length; i++) {
        if (updated[i].id == parentId) {
          updated[i] = updated[i].copyWith(
            replies: [...updated[i].replies, optimisticComment],
            replyCount: updated[i].replyCount + 1,
          );
          break;
        }
      }
      state = state.copyWith(
        comments: updated,
        isSending: true,
        replyingToId: null,
        replyingToName: null,
        replyingToUserId: null,
      );
    } else {
      state = state.copyWith(
        comments: [optimisticComment, ...state.comments],
        isSending: true,
      );
    }

    try {
      final ApiResponse resp;

      if (_isPost) {
        resp = await _commentService.createComment(
          key.targetId,
          text,
          parentId: parentId,
          replyToUserId: replyingToUserId,
        );
      } else {
        resp = await _comicService.postEventComment(
          key.targetId,
          content: text,
          parentId: parentId,
          replyToUserId: replyingToUserId,
        );
      }

      if (resp.success && resp.data != null) {
        if (!mounted) return null;
        final data = resp.data as Map<String, dynamic>;
        final commentJson = data['comment'] as Map<String, dynamic>?;
        if (commentJson != null) {
          final realComment = Comment.fromJson(commentJson);
          // 替换乐观评论为真实评论
          final updated = List<Comment>.from(state.comments);
          for (int i = 0; i < updated.length; i++) {
            if (updated[i].id == optimisticComment.id) {
              updated[i] = realComment;
              break;
            }
            // 也检查回复中的乐观评论
            final replies = List<Comment>.from(updated[i].replies);
            for (int j = 0; j < replies.length; j++) {
              if (replies[j].id == optimisticComment.id) {
                replies[j] = realComment;
                updated[i] = updated[i].copyWith(replies: replies);
                break;
              }
            }
          }
          state = state.copyWith(comments: updated, isSending: false);
        } else {
          state = state.copyWith(isSending: false);
        }
        return null; // 成功
      } else {
        // 失败：只移除本次乐观评论，保留等待期间的其它状态更新
        final message = apiFailureMessage(resp, fallback: '评论发送失败');
        if (mounted) {
          _removeOptimisticComment(optimisticComment.id, parentId: parentId);
          state = state.copyWith(isSending: false, error: message);
        }
        return message;
      }
    } catch (_) {
      // 网络错误：只移除本次乐观评论，保留等待期间的其它状态更新
      if (mounted) {
        _removeOptimisticComment(optimisticComment.id, parentId: parentId);
        state = state.copyWith(isSending: false, error: '评论发送失败');
      }
      return '评论发送失败';
    }
  }

  void _removeOptimisticComment(int optimisticCommentId, {int? parentId}) {
    if (parentId != null) {
      final updated = List<Comment>.from(state.comments);
      for (int i = 0; i < updated.length; i++) {
        if (updated[i].id == parentId) {
          final replies = updated[i]
              .replies
              .where((reply) => reply.id != optimisticCommentId)
              .toList();
          final removed = updated[i].replies.length - replies.length;
          if (removed == 0) return;
          final nextReplyCount = updated[i].replyCount - removed;
          updated[i] = updated[i].copyWith(
            replies: replies,
            replyCount: nextReplyCount < 0 ? 0 : nextReplyCount,
          );
          state = state.copyWith(comments: updated);
          return;
        }
      }
      return;
    }

    final comments = state.comments
        .where((comment) => comment.id != optimisticCommentId)
        .toList();
    if (comments.length != state.comments.length) {
      state = state.copyWith(comments: comments);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Like / Unlike
  // ═══════════════════════════════════════════════════════════

  Future<void> toggleLike(int commentId) async {
    if (state.likingIds.contains(commentId)) return;

    final newLiking = Set<int>.from(state.likingIds)..add(commentId);
    state = state.copyWith(likingIds: newLiking);

    final currentComment = _findComment(commentId);
    if (currentComment == null) {
      state = state.copyWith(
          likingIds: Set<int>.from(state.likingIds)..remove(commentId));
      return;
    }
    final wasLiked = currentComment.isLiked;
    final likeDelta = wasLiked ? -1 : 1;

    // Optimistic update
    final updated = _applyLikeDeltaInComments(
      state.comments,
      commentId,
      isLiked: !wasLiked,
      likeDelta: likeDelta,
    );
    if (updated != null && mounted) {
      state = state.copyWith(comments: updated);
    }

    try {
      final ApiResponse resp;
      if (_isPost) {
        resp = wasLiked
            ? await _commentService.unlikeComment(commentId)
            : await _commentService.likeComment(commentId);
      } else {
        resp = await _comicService.likeComment(commentId);
      }
      if (!resp.success) {
        if (mounted) {
          _rollbackLikeMutation(
            commentId,
            expectedLiked: !wasLiked,
            likeDelta: likeDelta,
          );
          state = state.copyWith(
            error: apiFailureMessage(resp, fallback: '操作失败，请重试'),
          );
        }
        return;
      }
    } catch (_) {
      // Revert on error
      if (mounted) {
        _rollbackLikeMutation(
          commentId,
          expectedLiked: !wasLiked,
          likeDelta: likeDelta,
        );
        state = state.copyWith(error: '操作失败，请重试');
      }
    } finally {
      if (mounted) {
        final cleared = Set<int>.from(state.likingIds)..remove(commentId);
        state = state.copyWith(likingIds: cleared);
      }
    }
  }

  void _rollbackLikeMutation(
    int commentId, {
    required bool expectedLiked,
    required int likeDelta,
  }) {
    final reverted = _applyLikeDeltaInComments(
      state.comments,
      commentId,
      isLiked: !expectedLiked,
      likeDelta: -likeDelta,
      onlyIfLiked: expectedLiked,
    );
    if (reverted != null) {
      state = state.copyWith(comments: reverted);
    }
  }

  Comment? _findComment(int commentId) {
    for (final comment in state.comments) {
      if (comment.id == commentId) return comment;
      for (final reply in comment.replies) {
        if (reply.id == commentId) return reply;
      }
    }
    return null;
  }

  List<Comment>? _applyLikeDeltaInComments(
    List<Comment> comments,
    int commentId, {
    required bool isLiked,
    required int likeDelta,
    bool? onlyIfLiked,
  }) {
    final updated = List<Comment>.from(comments);
    for (int i = 0; i < updated.length; i++) {
      if (updated[i].id == commentId) {
        final next = _applyLikeDelta(
          updated[i],
          isLiked: isLiked,
          likeDelta: likeDelta,
          onlyIfLiked: onlyIfLiked,
        );
        if (next == null) return null;
        updated[i] = next;
        return updated;
      }

      final replies = updated[i].replies;
      for (int j = 0; j < replies.length; j++) {
        if (replies[j].id == commentId) {
          final next = _applyLikeDelta(
            replies[j],
            isLiked: isLiked,
            likeDelta: likeDelta,
            onlyIfLiked: onlyIfLiked,
          );
          if (next == null) return null;
          final newReplies = List<Comment>.from(replies);
          newReplies[j] = next;
          updated[i] = updated[i].copyWith(replies: newReplies);
          return updated;
        }
      }
    }
    return null;
  }

  Comment? _applyLikeDelta(
    Comment comment, {
    required bool isLiked,
    required int likeDelta,
    bool? onlyIfLiked,
  }) {
    if (onlyIfLiked != null && comment.isLiked != onlyIfLiked) return null;
    final nextCount = comment.likeCount + likeDelta;
    return comment.copyWith(
      isLiked: isLiked,
      likeCount: nextCount < 0 ? 0 : nextCount,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Delete
  // ═══════════════════════════════════════════════════════════

  Future<bool> deleteComment(int commentId) async {
    try {
      final resp = _isPost
          ? await _commentService.deleteComment(commentId)
          : await _comicService.deleteComment(commentId);
      if (!resp.success) {
        if (mounted) {
          state = state.copyWith(
            error: apiFailureMessage(resp, fallback: '删除失败，请重试'),
          );
        }
        return false;
      }
      if (mounted) {
        _removeDeletedComment(commentId);
      }
      return true;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(error: '删除失败，请重试');
      }
      return false;
    }
  }

  void _removeDeletedComment(int commentId) {
    final updated = <Comment>[];
    var changed = false;
    for (final comment in state.comments) {
      if (comment.id == commentId) {
        changed = true;
        continue;
      }
      final replies =
          comment.replies.where((reply) => reply.id != commentId).toList();
      if (replies.length != comment.replies.length) {
        changed = true;
        final removed = comment.replies.length - replies.length;
        final nextReplyCount = comment.replyCount - removed;
        updated.add(comment.copyWith(
          replies: replies,
          replyCount: nextReplyCount < 0 ? 0 : nextReplyCount,
        ));
      } else {
        updated.add(comment);
      }
    }
    if (changed) state = state.copyWith(comments: updated);
  }

  // ═══════════════════════════════════════════════════════════
  //  Replies (分页加载)
  // ═══════════════════════════════════════════════════════════

  Future<void> loadReplies(int parentId, {int page = 1}) async {
    final expanded = Set<int>.from(state.expandedReplies)..add(parentId);
    state = state.copyWith(expandedReplies: expanded);

    try {
      final List<Comment> replies;
      bool hasMore = false;
      if (_isPost) {
        final resp =
            await _commentService.getReplies(key.targetId, parentId: parentId);
        final data = resp.data as Map<String, dynamic>?;
        if (resp.success && data != null) {
          final list = (data['comments'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          replies = list.map((e) => Comment.fromJson(e)).toList();
          hasMore = data['has_more'] == true;
        } else {
          replies = [];
        }
      } else {
        final resp = await _comicService.getCommentReplies(parentId);
        final data = resp.data;
        if (resp.success && data != null) {
          final list = (data['replies'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          replies = list.map((e) => Comment.fromJson(e)).toList();
          hasMore = data['has_more'] == true;
        } else {
          replies = [];
        }
      }

      if (mounted) {
        final updated = List<Comment>.from(state.comments);
        for (int i = 0; i < updated.length; i++) {
          if (updated[i].id == parentId) {
            // 保留乐观回复（id < 0），不被 API 返回的结果覆盖
            final existingReplies = updated[i].replies;
            final optimisticReplies =
                existingReplies.where((r) => r.id < 0).toList();
            final merged = [...replies, ...optimisticReplies];
            updated[i] = updated[i].copyWith(
              replies: merged,
              repliesHasMore: hasMore,
              repliesPage: page,
            );
            break;
          }
        }
        state = state.copyWith(comments: updated);
      }
    } catch (_) {
      if (mounted) {
        final collapsed = Set<int>.from(state.expandedReplies)
          ..remove(parentId);
        state = state.copyWith(expandedReplies: collapsed);
      }
    }
  }

  /// 加载更多回复（分页）
  Future<void> loadMoreReplies(int parentId) async {
    final parent = state.comments.firstWhere(
      (c) => c.id == parentId,
      orElse: () => state.comments.first,
    );
    if (parent.id != parentId || !parent.repliesHasMore) return;
    if (state.loadingRepliesIds.contains(parentId)) return;

    state = state.copyWith(
      loadingRepliesIds: {...state.loadingRepliesIds, parentId},
    );

    final nextPage = parent.repliesPage + 1;
    try {
      final List<Comment> newReplies;
      bool hasMore = false;
      if (_isPost) {
        final resp = await _commentService.getReplies(key.targetId,
            parentId: parentId, page: nextPage);
        final data = resp.data as Map<String, dynamic>?;
        if (resp.success && data != null) {
          final list = (data['comments'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          newReplies = list.map((e) => Comment.fromJson(e)).toList();
          hasMore = data['has_more'] == true;
        } else {
          newReplies = [];
        }
      } else {
        final resp =
            await _comicService.getCommentReplies(parentId, page: nextPage);
        final data = resp.data;
        if (resp.success && data != null) {
          final list = (data['replies'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          newReplies = list.map((e) => Comment.fromJson(e)).toList();
          hasMore = data['has_more'] == true;
        } else {
          newReplies = [];
        }
      }

      if (mounted) {
        final updated = List<Comment>.from(state.comments);
        for (int i = 0; i < updated.length; i++) {
          if (updated[i].id == parentId) {
            updated[i] = updated[i].copyWith(
              replies: [...updated[i].replies, ...newReplies],
              repliesHasMore: hasMore,
              repliesPage: nextPage,
            );
            break;
          }
        }
        final loadingIds = Set<int>.from(state.loadingRepliesIds)
          ..remove(parentId);
        state =
            state.copyWith(comments: updated, loadingRepliesIds: loadingIds);
      }
    } catch (_) {
      if (mounted) {
        final loadingIds = Set<int>.from(state.loadingRepliesIds)
          ..remove(parentId);
        state = state.copyWith(loadingRepliesIds: loadingIds);
      }
    }
  }

  void toggleExpandReplies(int commentId) {
    if (state.expandedReplies.contains(commentId)) {
      final collapsed = Set<int>.from(state.expandedReplies)..remove(commentId);
      state = state.copyWith(
          expandedReplies: collapsed, comments: List.from(state.comments));
    } else {
      loadReplies(commentId);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Reply targeting
  // ═══════════════════════════════════════════════════════════

  void startReply(String commentId, String name, int userId) {
    state = state.copyWith(
      replyingToId: commentId,
      replyingToName: name,
      replyingToUserId: userId,
    );
    // 自动展开被回复评论的回复列表
    final cid = int.tryParse(commentId);
    if (cid != null && !state.expandedReplies.contains(cid)) {
      loadReplies(cid);
    }
  }

  void cancelReply() {
    state = state.copyWith(
      replyingToId: null,
      replyingToName: null,
      replyingToUserId: null,
      clearReplyingToId: true,
      clearReplyingToName: true,
      clearReplyingToUserId: true,
    );
  }

  void removeCommentsByUser(int userId) {
    List<Comment> filter(List<Comment> comments) {
      return comments
          .where((comment) => comment.userId != userId)
          .map((comment) {
        final replies = filter(comment.replies);
        return comment.copyWith(
          replies: replies,
          replyCount: replies.length,
        );
      }).toList();
    }

    state = state.copyWith(comments: filter(state.comments));
  }

  /// Helper: notifier is still mounted after dispose.
  @override
  bool get mounted {
    // StateNotifier.mounted is available in newer riverpod versions;
    // fallback to true if not. We track manually.
    return _mounted;
  }

  bool _mounted = true;

  @override
  void dispose() {
    _activeNotifiers.remove(this);
    _mounted = false;
    super.dispose();
  }
}

/// Family provider: creates one CommentNotifier per (targetType, targetId) pair.
final commentProvider = StateNotifierProvider.family<CommentNotifier,
    CommentState, CommentSectionKey>(
  (ref, key) => CommentNotifier(key, currentUser: ref.read(authProvider).user),
);
