import 'package:facebook_clone/models/comment.dart';
import 'package:facebook_clone/providers/comment_state.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/api/comment_service.dart';
import 'package:facebook_clone/services/comic_service.dart';
import 'package:facebook_clone/services/sound_service.dart';
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
  final CommentSectionKey key;
  final CommentService _commentService = CommentService();
  final ComicService _comicService = ComicService();

  CommentNotifier(this.key) : super(const CommentState()) {
    loadComments();
  }

  bool get _isPost => key.targetType == 'post';

  // ═══════════════════════════════════════════════════════════
  //  Loading & Pagination
  // ═══════════════════════════════════════════════════════════

  Future<void> loadComments() async {
    if (!mounted) return;
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
        final resp = await _comicService.getEventComments(key.targetId, page: state.page);
        data = resp.data;
      }

      if (data != null) {
        final list = (data['comments'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        comments = list.map((e) => Comment.fromJson(e)).toList();
        final total = data['total'] ?? 0;
        hasMore = comments.length < (total is int ? total : comments.length + 1);
      } else {
        comments = [];
        hasMore = false;
      }

      if (mounted) {
        state = state.copyWith(
          comments: comments,
          isLoading: false,
          hasMore: hasMore,
          error: null,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
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
                (total is int ? total : state.comments.length + newComments.length + 1),
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

    final parentId = state.replyingToId != null ? int.tryParse(state.replyingToId!) : null;
    final replyingToUserId = state.replyingToUserId;

    // 立即播放发送音效
    SoundService().playSendSound();

    // 乐观更新：立即显示评论
    final optimisticComment = Comment(
      id: -DateTime.now().millisecondsSinceEpoch,
      content: text,
      userId: 0, // 会由服务端返回真实值
      postId: key.targetId,
      parentId: parentId,
      replyToUserId: replyingToUserId,
      likeCount: 0,
      replyCount: 0,
      isLiked: false,
      createdAt: DateTime.now(),
      replies: const [],
    );

    final oldState = state;
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
        final data = resp.data as Map<String, dynamic>;
        final commentJson = data['comment'] as Map<String, dynamic>?;
        if (commentJson != null && mounted) {
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
        // 失败：回退乐观评论
        state = oldState.copyWith(isSending: false, error: resp.message ?? '评论发送失败');
        return resp.message ?? '评论发送失败';
      }
    } catch (e) {
      // 网络错误：回退乐观评论
      state = oldState.copyWith(isSending: false, error: '评论发送失败: $e');
      return '评论发送失败';
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Like / Unlike
  // ═══════════════════════════════════════════════════════════

  Future<void> toggleLike(int commentId) async {
    if (state.likingIds.contains(commentId)) return;

    final newLiking = Set<int>.from(state.likingIds)..add(commentId);
    state = state.copyWith(likingIds: newLiking);

    // Optimistic update
    final updated = List<Comment>.from(state.comments);
    bool found = false;
    for (int i = 0; i < updated.length; i++) {
      if (updated[i].id == commentId) {
        updated[i] = updated[i].copyWith(
          isLiked: !updated[i].isLiked,
          likeCount: updated[i].isLiked
              ? updated[i].likeCount - 1
              : updated[i].likeCount + 1,
        );
        found = true;
        break;
      }
      // Check in replies
      final replies = updated[i].replies;
      for (int j = 0; j < replies.length; j++) {
        if (replies[j].id == commentId) {
          final newReplies = List<Comment>.from(replies);
          newReplies[j] = newReplies[j].copyWith(
            isLiked: !newReplies[j].isLiked,
            likeCount: newReplies[j].isLiked
                ? newReplies[j].likeCount - 1
                : newReplies[j].likeCount + 1,
          );
          updated[i] = updated[i].copyWith(replies: newReplies);
          found = true;
          break;
        }
      }
      if (found) break;
    }

    if (found && mounted) {
      state = state.copyWith(comments: updated);
    }

    try {
      if (_isPost) {
        // Determine if liked now
        final isNowLiked =
            state.comments.expand((c) => [c, ...c.replies]).any(
                  (c) => c.id == commentId && c.isLiked,
                );
        if (isNowLiked) {
          await _commentService.likeComment(commentId);
        } else {
          await _commentService.unlikeComment(commentId);
        }
      } else {
        await _comicService.likeComment(commentId);
      }
    } catch (_) {
      // Revert on error
      if (mounted) {
        final reverted = List<Comment>.from(state.comments);
        bool revertedFound = false;
        for (int i = 0; i < reverted.length; i++) {
          if (reverted[i].id == commentId) {
            reverted[i] = reverted[i].copyWith(
              isLiked: !reverted[i].isLiked,
              likeCount: reverted[i].isLiked
                  ? reverted[i].likeCount - 1
                  : reverted[i].likeCount + 1,
            );
            revertedFound = true;
            break;
          }
          final replies = reverted[i].replies;
          for (int j = 0; j < replies.length; j++) {
            if (replies[j].id == commentId) {
              final newReplies = List<Comment>.from(replies);
              newReplies[j] = newReplies[j].copyWith(
                isLiked: !newReplies[j].isLiked,
                likeCount: newReplies[j].isLiked
                    ? newReplies[j].likeCount - 1
                    : newReplies[j].likeCount + 1,
              );
              reverted[i] = reverted[i].copyWith(replies: newReplies);
              revertedFound = true;
              break;
            }
          }
          if (revertedFound) break;
        }
        if (revertedFound) {
          state = state.copyWith(comments: reverted);
        }
      }
    } finally {
      if (mounted) {
        final cleared = Set<int>.from(state.likingIds)..remove(commentId);
        state = state.copyWith(likingIds: cleared);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Delete
  // ═══════════════════════════════════════════════════════════

  Future<bool> deleteComment(int commentId) async {
    try {
      if (_isPost) {
        await _commentService.deleteComment(commentId);
      } else {
        await _comicService.deleteComment(commentId);
      }
      if (mounted) {
        state = state.copyWith(
          comments:
              state.comments.where((c) => c.id != commentId).toList(),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
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
        final resp = await _commentService.getReplies(key.targetId, parentId: parentId);
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
            updated[i] = updated[i].copyWith(
              replies: replies,
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
        final collapsed = Set<int>.from(state.expandedReplies)..remove(parentId);
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
        final resp = await _comicService.getCommentReplies(parentId, page: nextPage);
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
        final loadingIds = Set<int>.from(state.loadingRepliesIds)..remove(parentId);
        state = state.copyWith(comments: updated, loadingRepliesIds: loadingIds);
      }
    } catch (_) {
      if (mounted) {
        final loadingIds = Set<int>.from(state.loadingRepliesIds)..remove(parentId);
        state = state.copyWith(loadingRepliesIds: loadingIds);
      }
    }
  }

  void toggleExpandReplies(int commentId) {
    if (state.expandedReplies.contains(commentId)) {
      final collapsed = Set<int>.from(state.expandedReplies)..remove(commentId);
      state = state.copyWith(expandedReplies: collapsed, comments: List.from(state.comments));
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
    _mounted = false;
    super.dispose();
  }
}

/// Family provider: creates one CommentNotifier per (targetType, targetId) pair.
final commentProvider = StateNotifierProvider.family<CommentNotifier, CommentState, CommentSectionKey>(
  (ref, key) => CommentNotifier(key),
);