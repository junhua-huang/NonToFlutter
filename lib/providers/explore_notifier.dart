import 'dart:async';

import 'package:facebook_clone/models/comic_event.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/topic.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/services/api/recommendation_service.dart';
import 'package:facebook_clone/services/api/search_service.dart';
import 'package:facebook_clone/services/api/topic_service.dart';
import 'package:facebook_clone/services/comic_service.dart';
import 'package:facebook_clone/services/data_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable explore/search state.
class ExploreState {
  final List<String> searchHistory;
  final List<Topic> trendingTopics;
  final List<Post> trendingPosts;
  final List<User> suggestedUsers;
  final List<ComicEvent> recentComicEvents;
  final List<ComicEvent> followedComicEvents;
  final bool isLoading;
  final String? error;

  const ExploreState({
    this.searchHistory = const [],
    this.trendingTopics = const [],
    this.trendingPosts = const [],
    this.suggestedUsers = const [],
    this.recentComicEvents = const [],
    this.followedComicEvents = const [],
    this.isLoading = true,
    this.error,
  });

  ExploreState copyWith({
    List<String>? searchHistory,
    List<Topic>? trendingTopics,
    List<Post>? trendingPosts,
    List<User>? suggestedUsers,
    List<ComicEvent>? recentComicEvents,
    List<ComicEvent>? followedComicEvents,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ExploreState(
      searchHistory: searchHistory ?? this.searchHistory,
      trendingTopics: trendingTopics ?? this.trendingTopics,
      trendingPosts: trendingPosts ?? this.trendingPosts,
      suggestedUsers: suggestedUsers ?? this.suggestedUsers,
      recentComicEvents: recentComicEvents ?? this.recentComicEvents,
      followedComicEvents: followedComicEvents ?? this.followedComicEvents,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ExploreNotifier extends StateNotifier<ExploreState> {
  StreamSubscription? _sub;

  ExploreNotifier() : super(const ExploreState()) {
    _loadCached();
    _sub = DataLayer().changeStream.listen((key) {
      if (key == '__auth:logout') {
        _reset();
      } else if (key.startsWith('explore:')) {
        _loadCached();
      }
    });
  }

  /// 构造时先读缓存（topics/posts/users），漫展数据走网络
  Future<void> _loadCached() async {
    if (state.trendingPosts.isNotEmpty) return;
    bool hit = false;
    try {
      final topicResult = await DataLayer().query('explore:trending_topics', () async => null);
      final postResult = await DataLayer().query('explore:trending_posts', () async => null);
      final userResult = await DataLayer().query('explore:suggested_users', () async => null);

      final topics = _parseTopics(topicResult.data);
      final posts = _parsePosts(postResult.data);
      final users = _parseUsers(userResult.data);

      if (topics.isNotEmpty || posts.isNotEmpty || users.isNotEmpty) {
        state = state.copyWith(
          trendingTopics: topics,
          trendingPosts: posts,
          suggestedUsers: users,
          isLoading: false,
        );
        hit = true;
      }
    } catch (_) {}
    // 始终拉漫展数据（不在预热范围）; 缓存命中时静默更新
    await _loadComics(showLoading: !hit);
  }

  Future<void> _loadComics({bool showLoading = true}) async {
    try {
      final results = await Future.wait([
        ComicService().getEvents(size: 4),
        ComicService().getMyFollowed(),
      ]);
      final recent = results[0].data?.records ?? state.recentComicEvents;
      final followed = results[1].data?.records ?? state.followedComicEvents;
      state = state.copyWith(
        recentComicEvents: recent,
        followedComicEvents: followed,
        isLoading: showLoading ? false : null,
      );
    } catch (_) {}
  }

  List<Topic> _parseTopics(dynamic data) {
    if (data is List) {
      return data.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  List<Post> _parsePosts(dynamic data) {
    if (data is List) {
      return data.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  List<User> _parseUsers(dynamic data) {
    if (data is List) {
      return data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  List<ComicEvent> _parseComicEvents(dynamic data) {
    if (data is List) {
      return data.map((e) => ComicEvent.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<void> loadDefault({bool forceRefresh = false}) async {
    // Try cache first
    if (!forceRefresh) {
      final topicResult =
          await DataLayer().query('explore:trending_topics', () async => null);
      final postResult =
          await DataLayer().query('explore:trending_posts', () async => null);
      final userResult =
          await DataLayer().query('explore:suggested_users', () async => null);

      List<Topic>? cachedTopics;
      List<Post>? cachedPosts;
      List<User>? cachedUsers;

      if (topicResult.data is List && (topicResult.data as List).isNotEmpty) {
        cachedTopics = (topicResult.data as List)
            .map((e) => Topic.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (postResult.data is List && (postResult.data as List).isNotEmpty) {
        cachedPosts = (postResult.data as List)
            .map((e) => Post.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (userResult.data is List && (userResult.data as List).isNotEmpty) {
        cachedUsers = (userResult.data as List)
            .map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      if (cachedTopics != null || cachedPosts != null || cachedUsers != null) {
        state = state.copyWith(
          trendingTopics: cachedTopics ?? state.trendingTopics,
          trendingPosts: cachedPosts ?? state.trendingPosts,
          suggestedUsers: cachedUsers ?? state.suggestedUsers,
          isLoading: false,
        );
      }
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final results = await Future.wait([
        SearchService().getHistory(),
        TopicService().getTrending(limit: 8),
        RecommendationService().getTrending(limit: 5),
        RecommendationService().suggestUsers(limit: 5),
        ComicService().getEvents(size: 4),
        ComicService().getMyFollowed(size: 4),
      ]).timeout(const Duration(seconds: 15));

      // History
      final histResp = results[0];
      List<String> history = [];
      if (histResp.success && histResp.data != null) {
        final data = histResp.data;
        List items = [];
        if (data is List) {
          items = data;
        } else if (data is Map) {
          items = data['history'] ?? data['items'] ?? [];
        }
        history = items
            .map((e) =>
                e is Map ? e['query']?.toString() ?? '' : e.toString())
            .where((s) => s.isNotEmpty)
            .take(3)
            .toList();
      }

      // Trending topics
      final topicResp = results[1];
      List<Topic> topics = state.trendingTopics;
      if (topicResp.success && topicResp.data != null) {
        final data = topicResp.data;
        List topicList = [];
        if (data is List) {
          topicList = data;
        } else if (data is Map) {
          topicList = data['topics'] ?? data['items'] ?? [];
        }
        topics = topicList
            .map((e) => Topic.fromJson(e as Map<String, dynamic>))
            .toList();
        DataLayer().write('explore:trending_topics', topicList, ttlSeconds: 600);
      }

      // Trending posts
      final postResp = results[2];
      List<Post> posts = state.trendingPosts;
      if (postResp.success && postResp.data != null) {
        final data = postResp.data as Map<String, dynamic>;
        final list = data['posts'] as List? ?? [];
        posts = list
            .map((e) => Post.fromJson(e as Map<String, dynamic>))
            .toList();
        DataLayer().write('explore:trending_posts', list, ttlSeconds: 300);
      }

      // Suggested users
      final userResp = results[3];
      List<User> users = state.suggestedUsers;
      if (userResp.success && userResp.data != null) {
        final data = userResp.data;
        List userList = [];
        if (data is List) {
          userList = data;
        } else if (data is Map) {
          userList =
              data['users'] ?? data['items'] ?? data['suggested_users'] ?? [];
        }
        users = userList
            .map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList();
        DataLayer().write('explore:suggested_users', userList,
            ttlSeconds: 600);
      }

      // Comic events
      final comicResp = results[4];
      List<ComicEvent> recentComics = state.recentComicEvents;
      if (comicResp.success && comicResp.data != null) {
        final page = comicResp.data as ComicEventsPage;
        recentComics = page.records;
      }

      final followedResp = results[5];
      List<ComicEvent> followedComics = state.followedComicEvents;
      if (followedResp.success && followedResp.data != null) {
        final page = followedResp.data as ComicEventsPage;
        followedComics = page.records;
      }

      state = state.copyWith(
        searchHistory: history,
        trendingTopics: topics,
        trendingPosts: posts,
        suggestedUsers: users,
        recentComicEvents: recentComics,
        followedComicEvents: followedComics,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('ExploreNotifier error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _reset() {
    state = const ExploreState();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final exploreProvider =
    StateNotifierProvider<ExploreNotifier, ExploreState>((ref) {
  return ExploreNotifier();
});
