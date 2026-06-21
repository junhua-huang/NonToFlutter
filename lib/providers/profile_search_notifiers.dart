import 'dart:async';
import 'dart:convert';

import 'package:nonto/models/post.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/search_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProfileState {
  final List<Post> userPosts;
  final int friendCount;
  final int likeCount;
  final int postsPage;
  final bool postsHasMore;
  final bool isLoadingPosts;
  final bool isLoadingLikes;
  final bool isInitialLoading;
  final String? error;

  const ProfileState({
    this.userPosts = const [],
    this.friendCount = 0,
    this.likeCount = 0,
    this.postsPage = 1,
    this.postsHasMore = true,
    this.isLoadingPosts = false,
    this.isLoadingLikes = false,
    this.isInitialLoading = true,
    this.error,
  });

  ProfileState copyWith({
    List<Post>? userPosts,
    int? friendCount,
    int? likeCount,
    int? postsPage,
    bool? postsHasMore,
    bool? isLoadingPosts,
    bool? isLoadingLikes,
    bool? isInitialLoading,
    String? error,
    bool clearError = false,
  }) {
    return ProfileState(
      userPosts: userPosts ?? this.userPosts,
      friendCount: friendCount ?? this.friendCount,
      likeCount: likeCount ?? this.likeCount,
      postsPage: postsPage ?? this.postsPage,
      postsHasMore: postsHasMore ?? this.postsHasMore,
      isLoadingPosts: isLoadingPosts ?? this.isLoadingPosts,
      isLoadingLikes: isLoadingLikes ?? this.isLoadingLikes,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final int userId;
  final PostService _postService = PostService();
  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _wsConnSub;

  ProfileNotifier(this.userId) : super(const ProfileState()) {
    _wsConnSub = _ws.connectionStream.listen((connected) {
      if (connected) _loadPosts(refresh: true);
    });
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (refresh) {
      state = state.copyWith(postsPage: 1, postsHasMore: true);
    }
    if (!state.postsHasMore && !refresh) return;

    state = state.copyWith(isLoadingPosts: true, clearError: true);
    try {
      final cacheKey = 'user:$userId:posts:${state.postsPage}';
      final result = await DataLayer().query(cacheKey, () async {
        final resp =
            await _postService.getUserPosts(userId, page: state.postsPage);
        if (resp.success && resp.data != null) {
          final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
          final list =
              data['posts'] as List<dynamic>? ?? (data as List<dynamic>);
          return list;
        }
        return null;
      }, forceRefresh: refresh);

      if (result.data != null) {
        final list = (result.data as List<dynamic>)
            .map((e) => Post.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(
          userPosts: refresh ? list : [...state.userPosts, ...list],
          postsPage: state.postsPage + 1,
          postsHasMore: list.length >= 20,
          isLoadingPosts: false,
          isInitialLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoadingPosts: false,
          isInitialLoading: false,
          postsHasMore: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoadingPosts: false,
        isInitialLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadLikes() async {
    state = state.copyWith(isLoadingLikes: true);
    try {
      final cacheKey = 'user:$userId:likes';
      final result = await DataLayer().query(cacheKey, () async {
        final resp = await _postService.getUserLikedPosts(userId);
        if (resp.success && resp.data != null) {
          final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
          return data['total'] ?? data['like_count'] ?? 0;
        }
        return null;
      });
      if (result.data != null) {
        state = state.copyWith(
          likeCount: result.data is int
              ? result.data
              : int.tryParse(result.data.toString()) ?? 0,
          isLoadingLikes: false,
        );
      } else {
        state = state.copyWith(isLoadingLikes: false);
      }
    } catch (e) {
      state = state.copyWith(isLoadingLikes: false);
    }
  }

  /// Initiate full profile data load (called from tab activation).
  Future<void> init() async {
    await Future.wait([
      _loadPosts(),
      loadLikes(),
    ]);
  }

  /// Insert a new post at the top.
  void addPost(Post post) {
    state = state.copyWith(userPosts: [post, ...state.userPosts]);
  }

  /// Update post interaction stats.
  void updatePostInteraction(int postId,
      {int? likeCount, int? commentCount, int? viewCount}) {
    final posts = state.userPosts.map((p) {
      if (p.id == postId) {
        return p.copyWith(
          likeCount: likeCount ?? p.likeCount,
          commentCount: commentCount ?? p.commentCount,
          viewCount: viewCount ?? p.viewCount,
        );
      }
      return p;
    }).toList();
    state = state.copyWith(userPosts: posts);
  }

  void setFriendCount(int count) {
    state = state.copyWith(friendCount: count);
  }

  @override
  void dispose() {
    _wsConnSub?.cancel();
    super.dispose();
  }
}

final profileProvider =
    StateNotifierProvider.family<ProfileNotifier, ProfileState, int>(
  (ref, userId) {
    return ProfileNotifier(userId);
  },
);

// ── Search Provider ──

class SearchState {
  final List<Map<String, dynamic>> userResults;
  final List<Map<String, dynamic>> postResults;
  final List<Map<String, dynamic>> topicResults;
  final List<String> searchHistory;
  final List<Map<String, dynamic>> trendingTopics;
  final List<Map<String, dynamic>> trendingPosts;
  final List<Map<String, dynamic>> suggestedUsers;
  final bool isSearching;
  final String currentQuery;
  final String? error;
  final int usersPage;
  final int postsPage;
  final bool usersHasMore;
  final bool postsHasMore;

  const SearchState({
    this.userResults = const [],
    this.postResults = const [],
    this.topicResults = const [],
    this.searchHistory = const [],
    this.trendingTopics = const [],
    this.trendingPosts = const [],
    this.suggestedUsers = const [],
    this.isSearching = false,
    this.currentQuery = '',
    this.error,
    this.usersPage = 1,
    this.postsPage = 1,
    this.usersHasMore = true,
    this.postsHasMore = true,
  });

  SearchState copyWith({
    List<Map<String, dynamic>>? userResults,
    List<Map<String, dynamic>>? postResults,
    List<Map<String, dynamic>>? topicResults,
    List<String>? searchHistory,
    List<Map<String, dynamic>>? trendingTopics,
    List<Map<String, dynamic>>? trendingPosts,
    List<Map<String, dynamic>>? suggestedUsers,
    bool? isSearching,
    String? currentQuery,
    String? error,
    int? usersPage,
    int? postsPage,
    bool? usersHasMore,
    bool? postsHasMore,
    bool clearError = false,
  }) {
    return SearchState(
      userResults: userResults ?? this.userResults,
      postResults: postResults ?? this.postResults,
      topicResults: topicResults ?? this.topicResults,
      searchHistory: searchHistory ?? this.searchHistory,
      trendingTopics: trendingTopics ?? this.trendingTopics,
      trendingPosts: trendingPosts ?? this.trendingPosts,
      suggestedUsers: suggestedUsers ?? this.suggestedUsers,
      isSearching: isSearching ?? this.isSearching,
      currentQuery: currentQuery ?? this.currentQuery,
      error: clearError ? null : (error ?? this.error),
      usersPage: usersPage ?? this.usersPage,
      postsPage: postsPage ?? this.postsPage,
      usersHasMore: usersHasMore ?? this.usersHasMore,
      postsHasMore: postsHasMore ?? this.postsHasMore,
    );
  }

  SearchState clearSearch() {
    return const SearchState(searchHistory: []);
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final SearchService _searchService = SearchService();

  SearchNotifier() : super(const SearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    state = state.copyWith(
      isSearching: true,
      currentQuery: query,
      clearError: true,
      userResults: [],
      postResults: [],
      usersPage: 1,
      postsPage: 1,
      usersHasMore: true,
      postsHasMore: true,
    );

    try {
      final cacheKey = 'search:$query:global:1';
      final result = await DataLayer().query(cacheKey, () async {
        final resp = await _searchService.globalSearch(query);
        if (resp.success && resp.data != null) {
          final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
          return data;
        }
        return null;
      });

      if (result.data != null && result.data is Map<String, dynamic>) {
        final data = result.data as Map<String, dynamic>;
        final users = (data['users'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final posts = (data['posts'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        state = state.copyWith(
          userResults: users,
          postResults: posts,
          isSearching: false,
          usersHasMore: users.length >= 10,
          postsHasMore: posts.length >= 10,
        );
      } else {
        state = state.copyWith(isSearching: false);
      }
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadTrending() async {
    try {
      final results = await Future.wait([
        _searchService.trendingHashtags(limit: 10),
        _searchService.getHistory(limit: 20),
      ]);

      if (results[0].success && results[0].data != null) {
        final data = results[0].data is String
            ? jsonDecode(results[0].data)
            : results[0].data;
        final topics = (data['hashtags'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        state = state.copyWith(trendingTopics: topics);
      }

      if (results[1].success && results[1].data != null) {
        final data = results[1].data is String
            ? jsonDecode(results[1].data)
            : results[1].data;
        final history = (data['history'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        state = state.copyWith(searchHistory: history);
      }
    } catch (_) {}
  }

  void addToHistory(String query) {
    if (query.trim().isEmpty) return;
    final history = [query, ...state.searchHistory.where((h) => h != query)];
    state = state.copyWith(searchHistory: history.take(20).toList());
    _searchService.saveHistory(query, 'global');
  }

  void clearSearch() {
    state = state.clearSearch();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier();
});
