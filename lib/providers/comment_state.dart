import 'package:facebook_clone/models/comment.dart';

/// Immutable state for comment sections (post / comic).
class CommentState {
  final List<Comment> comments;
  final bool isLoading;
  final bool isSending;
  final bool hasMore;
  final int page;
  final String? error;

  // Reply state
  final String? replyingToId;
  final String? replyingToName;
  final int? replyingToUserId;

  // Expanded reply tracking
  final Set<int> expandedReplies;

  // Like debounce
  final Set<int> likingIds;

  // Reply loading state (per-parent comment)
  final Set<int> loadingRepliesIds;

  const CommentState({
    this.comments = const [],
    this.isLoading = true,
    this.isSending = false,
    this.hasMore = true,
    this.page = 1,
    this.error,
    this.replyingToId,
    this.replyingToName,
    this.replyingToUserId,
    this.expandedReplies = const {},
    this.likingIds = const {},
    this.loadingRepliesIds = const {},
  });

  CommentState copyWith({
    List<Comment>? comments,
    bool? isLoading,
    bool? isSending,
    bool? hasMore,
    int? page,
    String? error,
    bool clearError = false,
    String? replyingToId,
    bool clearReplyingToId = false,
    String? replyingToName,
    bool clearReplyingToName = false,
    int? replyingToUserId,
    bool clearReplyingToUserId = false,
    Set<int>? expandedReplies,
    Set<int>? likingIds,
    Set<int>? loadingRepliesIds,
  }) {
    return CommentState(
      comments: comments ?? this.comments,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
      replyingToId: clearReplyingToId ? null : (replyingToId ?? this.replyingToId),
      replyingToName: clearReplyingToName ? null : (replyingToName ?? this.replyingToName),
      replyingToUserId: clearReplyingToUserId ? null : (replyingToUserId ?? this.replyingToUserId),
      expandedReplies: expandedReplies ?? this.expandedReplies,
      likingIds: likingIds ?? this.likingIds,
      loadingRepliesIds: loadingRepliesIds ?? this.loadingRepliesIds,
    );
  }

  /// Whether there are no comments and initial load is done.
  bool get isEmpty => !isLoading && comments.isEmpty;
}