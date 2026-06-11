import 'dart:async';

import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/recommendation_service.dart';
import 'package:facebook_clone/services/data_layer.dart';
import 'package:facebook_clone/services/post_interaction_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable feed state.
class FeedState {
  final List<Post> posts;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final String? error;

  const FeedState({
    this.posts = const [],
    this.page = 1,
    this.hasMore = true,
    this.isLoading = false,
    this.error,
  });

  FeedState copyWith({
    List<Post>? posts,
    int? page,
    bool? hasMore,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// FeedNotifier manages the main feed tab's state:
/// posts list, pagination, loading, error, and like toggle.
class FeedNotifier extends StateNotifier<FeedState> {
  final Set<int> _likingPostIds = {};
  StreamSubscription? _sub;

  FeedNotifier() : super(const FeedState()) {
    _loadCached();
    _sub = DataLayer().changeStream.listen((key) {
      if (key == '__auth:logout') {
        reset();
      } else if (key == 'feed:1:posts') {
        _loadCached();
      }
    });
  }

  /// 构造时先读缓存，空则触发网络加载
  Future<void> _loadCached() async {
    if (state.posts.isNotEmpty) return;
    try {
      final result = await DataLayer()
          .query('feed:1:posts', () async => null)
          .timeout(const Duration(seconds: 2));
      final cached = result.data;
      if (cached is List && cached.isNotEmpty) {
        final posts =
            cached.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
        state = state.copyWith(posts: posts, isLoading: false);
        return;
      }
    } catch (_) {}
    // 缓存空 → 触发网络加载
    unawaited(loadPosts());
  }

  Future<void> _fetchAndRefreshFeed() async {
    try {
      final resp = await RecommendationService().getFeed(page: state.page);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final List postsJson = data['posts'] ?? data['items'] ?? [];
        final posts =
            postsJson.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();

        final newPosts =
            state.page == 1 ? posts : [...state.posts, ...posts];
        state = state.copyWith(
          posts: newPosts,
          hasMore: data['has_more'] == true || posts.length >= 20,
          page: state.page + 1,
          clearError: true,
        );

        if (state.page <= 2) {
          await DataLayer().write('feed:1:posts', postsJson);
        }
      } else {
        state = state.copyWith(hasMore: false);
      }
    } catch (e) {
      debugPrint('FeedNotifier loadPosts error: $e');
      // Fallback to basic feed
      try {
        final resp = await PostService().getFeed(page: state.page);
        if (resp.success && resp.data != null) {
          final data = resp.data as Map<String, dynamic>;
          final List postsJson = data['posts'] ?? data['items'] ?? [];
          final posts =
              postsJson.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();

          final newPosts =
              state.page == 1 ? posts : [...state.posts, ...posts];
          state = state.copyWith(
            posts: newPosts,
            hasMore: data['has_more'] == true,
            page: state.page + 1,
            clearError: true,
          );

          if (state.page <= 2) {
            await DataLayer().write('feed:1:posts', postsJson);
          }
        } else {
          state = state.copyWith(hasMore: false);
        }
      } catch (e2) {
        debugPrint('FeedNotifier fallback error: $e2');
        state = state.copyWith(
          hasMore: false,
          error: state.posts.isEmpty ? '加载失败' : null,
        );
      }
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Pull-to-refresh: reset to page 1 and force-reload.
  Future<void> refreshPosts() async {
    state = const FeedState(isLoading: true);
    state = state.copyWith(page: 1);
    await _fetchAndRefreshFeed();
  }

  /// Load more posts (pagination).
  Future<void> loadPosts() async {
    if (!state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoading: true);
    await _fetchAndRefreshFeed();
  }

  /// Insert a newly created post at the top.
  void insertNewPost(Post post) {
    if (state.posts.any((p) => p.id == post.id)) return;
    state = state.copyWith(posts: [post, ...state.posts]);
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
    final updatedPost = post.copyWith(
      isLiked: !wasLiked,
      likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
    );

    // Optimistic update
    final updatedPosts = List<Post>.from(state.posts);
    updatedPosts[idx] = updatedPost;
    state = state.copyWith(posts: updatedPosts);
    _syncFeedToCache();

    try {
      if (wasLiked) {
        await PostService().unlikePost(postId);
      } else {
        await PostService().likePost(postId);
      }
      PostInteractionNotifier().notifyLikeChanged(
        postId,
        !wasLiked,
        wasLiked ? post.likeCount - 1 : post.likeCount + 1,
      );
    } catch (e) {
      // Rollback
      final rollbackPosts = List<Post>.from(state.posts);
      rollbackPosts[idx] = post;
      state = state.copyWith(posts: rollbackPosts);
      _syncFeedToCache();
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
  }

  /// Sync current posts to DataLayer cache.
  void _syncFeedToCache() {
    if (state.posts.isEmpty) return;
    final data = state.posts.map((p) => p.toJson()).toList();
    DataLayer().write('feed:${state.page}:posts', data);
    if (state.page <= 2) {
      DataLayer().write('feed:1:posts', data);
    }
  }

  /// Reset to initial state.
  void reset() {
    state = const FeedState();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final feedProvider =
    StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  return FeedNotifier();
});
