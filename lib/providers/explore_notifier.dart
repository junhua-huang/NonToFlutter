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

  /// 构造时先读缓存，无论是否命中都触发网络全量加载
  Future<void> _loadCached() async {
    if (state.trendingPosts.isNotEmpty) return;
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
      }
    } catch (_) {}
    // 始终触发网络全量加载（含漫展、话题、帖子、用户）
    unawaited(loadDefault());
  }

  List<Topic> _parseTopics(dynamic data) {
    try {
      if (data is List) {
        return data.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  List<Post> _parsePosts(dynamic data) {
    try {
      if (data is List) {
        return data.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  List<User> _parseUsers(dynamic data) {
    try {
      if (data is List) {
        return data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  List<ComicEvent> _parseComicEvents(dynamic data) {
    try {
      if (data is List) {
        return data.map((e) => ComicEvent.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> loadDefault({bool forceRefresh = false}) async {
    // Try cache first (isolated try-catch: cache failure must not break network fallback)
    if (!forceRefresh) {
      try {
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
          cachedTopics = _parseTopics(topicResult.data);
        }
        if (postResult.data is List && (postResult.data as List).isNotEmpty) {
          cachedPosts = _parsePosts(postResult.data);
        }
        if (userResult.data is List && (userResult.data as List).isNotEmpty) {
          cachedUsers = _parseUsers(userResult.data);
        }

        if (cachedTopics != null || cachedPosts != null || cachedUsers != null) {
          state = state.copyWith(
            trendingTopics: cachedTopics ?? state.trendingTopics,
            trendingPosts: cachedPosts ?? state.trendingPosts,
            suggestedUsers: cachedUsers ?? state.suggestedUsers,
            isLoading: false,
          );
        }
      } catch (e) {
        debugPrint('ExploreNotifier cache read error: $e');
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

      // History (isolated try-catch: 单个 API 失败不影响其他)
      List<String> history = [];
      try {
        final histResp = results[0];
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
      } catch (e) {
        debugPrint('ExploreNotifier history parse error: $e');
      }

      // Trending topics
      List<Topic> topics = state.trendingTopics;
      try {
        final topicResp = results[1];
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
      } catch (e) {
        debugPrint('ExploreNotifier topics parse error: $e');
      }

      // Trending posts
      List<Post> posts = state.trendingPosts;
      try {
        final postResp = results[2];
        if (postResp.success && postResp.data != null) {
          final data = postResp.data;
          List list = [];
          if (data is Map) {
            list = data['posts'] as List? ?? [];
          } else if (data is List) {
            list = data;
          }
          posts = list
              .map((e) => Post.fromJson(e as Map<String, dynamic>))
              .toList();
          DataLayer().write('explore:trending_posts', list, ttlSeconds: 300);
        }
      } catch (e) {
        debugPrint('ExploreNotifier posts parse error: $e');
      }

      // Suggested users
      List<User> users = state.suggestedUsers;
      try {
        final userResp = results[3];
        if (userResp.success && userResp.data != null) {
          final data = userResp.data;
          List userList = [];
          if (data is List) {
            userList = data;
          } else if (data is Map) {
            userList = data['users'] ?? data['items'] ?? data['suggested_users'] ?? [];
          }
          users = userList
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
          DataLayer().write('explore:suggested_users', userList, ttlSeconds: 600);
        }
      } catch (e) {
        debugPrint('ExploreNotifier users parse error: $e');
      }

      // Comic events
      List<ComicEvent> recentComics = state.recentComicEvents;
      try {
        final comicResp = results[4];
        if (comicResp.success && comicResp.data != null) {
          if (comicResp.data is ComicEventsPage) {
            recentComics = (comicResp.data as ComicEventsPage).records;
          } else if (comicResp.data is Map) {
            final map = comicResp.data as Map;
            final records = map['records'] as List? ?? [];
            recentComics = records
                .map((e) => ComicEvent.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      } catch (e) {
        debugPrint('ExploreNotifier comic events parse error: $e');
      }

      List<ComicEvent> followedComics = state.followedComicEvents;
      try {
        final followedResp = results[5];
        if (followedResp.success && followedResp.data != null) {
          if (followedResp.data is ComicEventsPage) {
            followedComics = (followedResp.data as ComicEventsPage).records;
          } else if (followedResp.data is Map) {
            final map = followedResp.data as Map;
            final records = map['records'] as List? ?? [];
            followedComics = records
                .map((e) => ComicEvent.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      } catch (e) {
        debugPrint('ExploreNotifier followed comics parse error: $e');
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
