import 'dart:async';
import 'dart:convert';

import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/recommendation_service.dart';
import 'package:facebook_clone/services/api/topic_service.dart';
import 'package:facebook_clone/services/cache_keys.dart';
import 'package:facebook_clone/services/data_layer.dart';

/// 应用全量数据预热 — 拿到 token 后立即执行
///
/// 两阶段：
///   1. L2 → L1（同步级）：有缓存则 Provider 立即可用，无则骨架屏
///   2. L3 网络 → L2+L1（异步，后台）：静默更新，不阻塞 UI
///
/// 覆盖所有 Tab 页面首屏数据：Feed、通知、探索、消息、个人主页。
class AppWarmup {
  AppWarmup._();

  static Map<String, Future<dynamic> Function()> _fetchers(String userIdStr) {
    return {
      'feed:1:posts': () async {
        final resp = await RecommendationService()
            .getFeed(page: 1)
            .timeout(const Duration(seconds: 20));
        return _extractList(resp, 'posts');
      },
      'notif:list:1': () async {
        final resp = await NotificationService()
            .getNotifications(page: 1)
            .timeout(const Duration(seconds: 20));
        return _extractList(resp, 'notifications');
      },
      'explore:trending_topics': () async {
        final resp = await TopicService()
            .getTrending(limit: 8)
            .timeout(const Duration(seconds: 20));
        return _extractList(resp, 'topics', fallbackKey: 'items');
      },
      'explore:trending_posts': () async {
        final resp = await RecommendationService()
            .getTrending(limit: 5)
            .timeout(const Duration(seconds: 20));
        return _extractList(resp, 'posts');
      },
      'user:$userIdStr:posts': () async {
        final resp = await PostService()
            .getUserPosts(int.tryParse(userIdStr) ?? 0)
            .timeout(const Duration(seconds: 20));
        return _extractList(resp, 'posts');
      },
      'user:$userIdStr:liked:1': () async {
        final resp = await PostService()
            .getUserLikedPosts(int.tryParse(userIdStr) ?? 0)
            .timeout(const Duration(seconds: 20));
        return _extractList(resp, 'posts');
      },
      CacheKeys.convFullList: () async {
        final resp = await ApiClient()
            .get('/chat/sessions')
            .timeout(const Duration(seconds: 8));
        return _extractList(resp, 'conversations', fallbackKey: 'sessions');
      },
    };
  }

  static Future<void> warmup(String userIdStr) async {
    final layer = DataLayer();

    // ── Phase 1: L2 → L1 ──
    final allKeys = [
      ..._fetchers(userIdStr).keys,
      'explore:suggested_users',
    ];
    for (final key in allKeys) {
      try {
        await layer
            .query(key, () async => null)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    // ── Phase 2: L3 → L2+L1（交错执行，避免瞬间占满并发槽位）───
    var staggerMs = 0;
    for (final entry in _fetchers(userIdStr).entries) {
      _networkRefresh(layer, entry.key, entry.value, staggerMs);
      staggerMs += 200; // 每个间隔 200ms，7 个共需 1.4s
    }

    // ── 会话消息批量预取（依赖 Phase 2 的 convFullList 已缓存）───
    _prefetchConversationMessages(layer, staggerMs + 300);
  }

  static void _networkRefresh(
    DataLayer layer,
    String key,
    Future<dynamic> Function() fetcher,
    int delayMs,
  ) {
    () async {
      try {
        if (delayMs > 0) await Future.delayed(Duration(milliseconds: delayMs));
        await layer
            .query(key, fetcher, forceRefresh: true)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }();
  }

  /// 自缓存 convFullList 读取会话 ID，批量拉取最近消息写入 L1（msg warmup）.
  static void _prefetchConversationMessages(DataLayer layer, int delayMs) {
    () async {
      try {
        if (delayMs > 0) await Future.delayed(Duration(milliseconds: delayMs));

        final convResult = await layer
            .query(CacheKeys.convFullList, () async => null)
            .timeout(const Duration(seconds: 4));
        if (convResult.data is! List || (convResult.data as List).isEmpty) return;

        final convIds = (convResult.data as List<dynamic>)
            .take(50)
            .map((c) => (c as Map<String, dynamic>)['id'])
            .whereType<int>()
            .toList();
        if (convIds.isEmpty) return;

        final resp = await ApiClient()
            .get('/chat/messages/batch', params: {
              'conv_ids': convIds.join(','),
              'per_page': 30,
            })
            .timeout(const Duration(seconds: 8));
        if (!resp.success || resp.data == null) return;

        final data = resp.data is String
            ? (() { try { return jsonDecode(resp.data); } catch (_) { return {}; } })()
            : resp.data;
        final conversations = data['data']?['conversations'] ??
            data['conversations'] ??
            <dynamic>[];
        for (final c in (conversations as List<dynamic>)) {
          if (c is! Map<String, dynamic>) continue;
          final convId = c['conversation_id'] ?? c['id'];
          final messages = c['messages'];
          if (convId != null && messages is List && messages.isNotEmpty) {
            layer.write(CacheKeys.msgWarmup(convId), messages);
          }
        }
      } catch (_) {}
    }();
  }

  static List<dynamic>? _extractList(
    dynamic resp, String key, {
    String? fallbackKey,
  }) {
    if (resp == null) return null;
    final data = resp is Map<String, dynamic>
        ? resp
        : resp.data is Map<String, dynamic>
            ? resp.data as Map<String, dynamic>
            : resp.data is String
                ? (() {
                    try { return jsonDecode(resp.data as String); }
                    catch (_) { return {}; }
                  })()
                : {};
    if (data is! Map) return null;
    final list = data[key] ?? (fallbackKey != null ? data[fallbackKey] : null);
    return list is List ? list : null;
  }
}
