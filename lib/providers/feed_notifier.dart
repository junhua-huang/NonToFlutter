import 'dart:async';

import 'package:nonto/models/post.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/post_interaction_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable feed state.
class FeedState {
  final List<Post> posts;
  final int page;
  final String? nextCursor;
  final String trackKey;
  final String? feedStatus;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? error;
  final DateTime? lastUpdatedAt;

  const FeedState({
    this.posts = const [],
    this.page = 1,
    this.trackKey = 'recommended',
    this.nextCursor,
    this.feedStatus,
    this.hasMore = true,
    this.isInitialLoading = true,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.error,
    this.lastUpdatedAt,
  });

  bool get isLoading => isInitialLoading || isRefreshing || isLoadingMore;

  FeedState copyWith({
    List<Post>? posts,
    int? page,
    String? trackKey,
    String? nextCursor,
    bool clearNextCursor = false,
    String? feedStatus,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    DateTime? lastUpdatedAt,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      page: page ?? this.page,
      trackKey: trackKey ?? this.trackKey,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      feedStatus: feedStatus ?? this.feedStatus,
      hasMore: hasMore ?? this.hasMore,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}

/// FeedNotifier manages the main feed tab's state:
/// posts list, pagination, loading, error, and like toggle.
class FeedNotifier extends StateNotifier<FeedState> {
  final Set<int> _likingPostIds = {};
  StreamSubscription? _sub;
  bool _loadInProgress = false;
  final DataLayer _dataLayer;
  final Map<String, FeedState> _trackStates = {};

  FeedNotifier({
    FeedState initialState = const FeedState(),
    DataLayer? dataLayer,
    bool loadOnInit = true,
  })  : _dataLayer = dataLayer ?? DataLayer(),
        super(initialState) {
    if (loadOnInit) _loadCached();
    _sub = _dataLayer.changeStream.listen((key) {
      if (key == '__auth:logout') {
        reset();
      } else if (key == CacheKeys.feedTrackPosts(state.trackKey) ||
          (state.trackKey == 'recommended' && key == CacheKeys.feedPosts)) {
        _loadCached();
      }
    });
  }

  /// 构造时先读缓存，空则触发网络加载
  Future<void> _loadCached() async {
    if (state.posts.isNotEmpty || _loadInProgress) return;
    _loadInProgress = true;
    final requestTrackKey = state.trackKey;
    try {
      final result = await _dataLayer
          .query(CacheKeys.feedTrackPosts(requestTrackKey), () async => null)
          .timeout(const Duration(seconds: 2));
      final cached = result.data;
      if (state.trackKey != requestTrackKey) return;
      if (cached is List && cached.isNotEmpty) {
        final posts = cached
            .map((e) => Post.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(posts: posts, page: 2, isInitialLoading: false);
        _rememberCurrentTrackState();
        return;
      }
      // 缓存空 → 触发网络加载。
      // 直接调 _fetchAndRefreshFeed 而非 loadPosts()，因为 loadPosts 内部有
      // `_loadInProgress` guard，此时该标志已被本方法置为 true，会被直接
      // return 掉，导致 isLoading 永远卡在 true（骨架屏不消失）。
      await _fetchAndRefreshFeed();
    } catch (_) {
      if (state.trackKey == requestTrackKey) await _fetchAndRefreshFeed();
    } finally {
      _loadInProgress = false;
    }
  }

  List<Post> _mergeUniquePosts(List<Post> existing, List<Post> incoming) {
    final seen = existing.map((p) => p.id).toSet();
    final merged = List<Post>.from(existing);
    for (final post in incoming) {
      if (seen.add(post.id)) merged.add(post);
    }
    return merged;
  }

  /// Parse posts from API response data and update state.
  void _applyPostsFromData(
    String requestTrackKey,
    int requestPage,
    Map<String, dynamic> data,
    List postsJson,
  ) {
    if (state.trackKey != requestTrackKey) return;
    final posts =
        postsJson.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    final isFirstPage = requestPage == 1;
    final nextCursor = data['next_cursor'] as String?;
    final feedStatus = data['feed_status'] as String?;
    final newPosts =
        isFirstPage ? posts : _mergeUniquePosts(state.posts, posts);
    state = state.copyWith(
      posts: newPosts,
      hasMore: data['has_more'] == true ||
          (nextCursor != null && nextCursor.isNotEmpty),
      nextCursor: nextCursor,
      clearNextCursor: nextCursor == null || nextCursor.isEmpty,
      feedStatus: feedStatus,
      page: requestPage + 1,
      clearError: true,
      lastUpdatedAt: DateTime.now(),
    );
    _rememberCurrentTrackState();
    _syncFeedToCache();
  }

  /// Fetch chronological timeline feed. Recommendation feed is intentionally unused.
  Future<Map<String, dynamic>?> _fetchFeedResponse(
    String requestTrackKey,
    int requestPage,
  ) async {
    try {
      ApiResponse? resp;
      switch (requestTrackKey) {
        case 'recommended':
          resp = await PostService().getFeed(page: requestPage);
          break;
        case 'following':
          resp = await PostService().getRelatedToMe(page: requestPage);
          break;
        default:
          return null;
      }
      if (resp.success && resp.data != null) {
        return resp.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('FeedNotifier timeline error: $e');
    }
    return null;
  }

  Future<void> _fetchAndRefreshFeed() async {
    final requestTrackKey = state.trackKey;
    final requestPage = state.page;
    try {
      final data = await _fetchFeedResponse(requestTrackKey, requestPage);
      if (state.trackKey != requestTrackKey) return;
      if (data != null) {
        final List postsJson = data['posts'] ?? data['items'] ?? [];
        _applyPostsFromData(requestTrackKey, requestPage, data, postsJson);
      } else {
        state = state.copyWith(
          error: state.posts.isEmpty ? '加载失败' : '刷新失败，正在显示上次内容',
        );
        _rememberCurrentTrackState();
      }
    } catch (e) {
      if (state.trackKey != requestTrackKey) return;
      debugPrint('FeedNotifier _fetchAndRefreshFeed error: $e');
      state = state.copyWith(
        error: state.posts.isEmpty ? '加载失败' : '刷新失败，正在显示上次内容',
      );
      _rememberCurrentTrackState();
    } finally {
      if (state.trackKey == requestTrackKey) {
        state = state.copyWith(
          isInitialLoading: false,
          isRefreshing: false,
          isLoadingMore: false,
        );
        _rememberCurrentTrackState();
      }
    }
  }

  void _rememberCurrentTrackState() {
    _trackStates[state.trackKey] = state;
  }

  Future<void> switchTrack(String trackKey) async {
    if (state.trackKey == trackKey) return;
    _rememberCurrentTrackState();
    final cachedState = _trackStates[trackKey];
    if (cachedState != null) {
      state = cachedState.copyWith(
        isRefreshing: false,
        isLoadingMore: false,
        clearError: true,
      );
      return;
    }
    state = state.copyWith(
      posts: const [],
      page: 1,
      trackKey: trackKey,
      hasMore: trackKey == 'recommended' || trackKey == 'following',
      isInitialLoading: true,
      isRefreshing: false,
      isLoadingMore: false,
      clearNextCursor: true,
      clearError: true,
    );
    await _fetchAndRefreshFeed();
  }

  /// Pull-to-refresh: reset to page 1 and force-reload.
  Future<void> refreshPosts() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    // 保留现有 posts 防止闪烁，只标记刷新状态 + 重置 cursor/page
    state = state.copyWith(
      isRefreshing: state.posts.isNotEmpty,
      isInitialLoading: state.posts.isEmpty,
      isLoadingMore: false,
      page: 1,
      hasMore: true,
      clearNextCursor: true,
      clearError: true,
    );
    try {
      await _fetchAndRefreshFeed();
    } finally {
      _loadInProgress = false;
    }
  }

  /// Load more posts (pagination).
  Future<void> loadPosts() async {
    if (!state.hasMore) return;
    // 用独立标志防止重入，不阻塞 UI 显示
    if (_loadInProgress) return;
    _loadInProgress = true;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      await _fetchAndRefreshFeed();
    } finally {
      _loadInProgress = false;
    }
  }

  /// Insert a newly created post at the top of the recommended track only.
  void insertNewPost(Post post) {
    if (state.trackKey != 'recommended') return;
    if (state.posts.any((p) => p.id == post.id)) return;
    state = state.copyWith(posts: [post, ...state.posts]);
    _rememberCurrentTrackState();
    _syncFeedToCache();
  }

  void _rollbackLikeMutation(
    int postId, {
    required bool expectedLiked,
    required int likeDelta,
    String? error,
  }) {
    final currentIdx = state.posts.indexWhere((p) => p.id == postId);
    if (currentIdx == -1) {
      if (error != null) state = state.copyWith(error: error);
      return;
    }
    final currentPost = state.posts[currentIdx];
    if ((currentPost.isLiked ?? false) != expectedLiked) {
      if (error != null) state = state.copyWith(error: error);
      return;
    }
    final nextCount = currentPost.likeCount - likeDelta;
    final rollbackPosts = List<Post>.from(state.posts);
    rollbackPosts[currentIdx] = currentPost.copyWith(
      isLiked: !expectedLiked,
      likeCount: nextCount < 0 ? 0 : nextCount,
    );
    state = state.copyWith(posts: rollbackPosts, error: error);
    _rememberCurrentTrackState();
    _syncFeedToCache();
  }

  /// Toggle like with optimistic update.
  Future<void> toggleLike(int postId) async {
    if (_likingPostIds.contains(postId)) return;
    _likingPostIds.add(postId);

    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx == -1) {
      _likingPostIds.remove(postId);
      return;
    }

    final post = state.posts[idx];
    final wasLiked = post.isLiked ?? false;
    final likeDelta = wasLiked ? -1 : 1;
    final nextLikeCount = post.likeCount + likeDelta;
    final updatedPost = post.copyWith(
      isLiked: !wasLiked,
      likeCount: nextLikeCount < 0 ? 0 : nextLikeCount,
    );

    // Optimistic update
    final updatedPosts = List<Post>.from(state.posts);
    updatedPosts[idx] = updatedPost;
    state = state.copyWith(posts: updatedPosts);
    _rememberCurrentTrackState();
    _syncFeedToCache();

    try {
      final resp = wasLiked
          ? await PostService().unlikePost(postId)
          : await PostService().likePost(postId);
      if (!resp.success) {
        _rollbackLikeMutation(
          postId,
          expectedLiked: !wasLiked,
          likeDelta: likeDelta,
          error: apiFailureMessage(resp, fallback: '操作失败，请重试'),
        );
        return;
      }
      PostInteractionNotifier().notifyLikeChanged(
        postId,
        !wasLiked,
        updatedPost.likeCount,
      );
    } catch (_) {
      _rollbackLikeMutation(
        postId,
        expectedLiked: !wasLiked,
        likeDelta: likeDelta,
        error: '操作失败，请重试',
      );
    } finally {
      _likingPostIds.remove(postId);
    }
  }

  /// Update a single post in the list (e.g. after view count change).
  void updatePost(int postId, Post Function(Post) updater) {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final updatedPosts = List<Post>.from(state.posts);
    updatedPosts[idx] = updater(updatedPosts[idx]);
    state = state.copyWith(posts: updatedPosts);
    _rememberCurrentTrackState();
  }

  /// Remove blocked-user posts from memory and persist even an empty result.
  Future<void> removePostsByUser(int userId) async {
    final filtered =
        state.posts.where((post) => post.userId != userId).toList();
    if (filtered.length == state.posts.length) return;
    state = state.copyWith(posts: filtered);
    _rememberCurrentTrackState();
    await _syncFeedToCache();
  }

  /// Sync current posts to the canonical feed cache, including empty lists.
  Future<void> _syncFeedToCache() async {
    final data = state.posts.map((p) => p.toJson()).toList();
    await _dataLayer.write(CacheKeys.feedTrackPosts(state.trackKey), data);
    if (state.trackKey == 'recommended') {
      await _dataLayer.write(CacheKeys.feedPosts, data);
    }
  }

  /// Reset to initial state.
  void reset() {
    _loadInProgress = false;
    state = const FeedState();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  return FeedNotifier();
});
