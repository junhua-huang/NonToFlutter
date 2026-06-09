import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 通用缓存服务 - 减少网络请求
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 缓存数据（带过期时间，单位：分钟）
  Future<void> set(String key, dynamic data, {int expireMinutes = 5}) async {
    final prefs = await _preferences;
    final cacheEntry = {
      'data': data,
      'expireAt': DateTime.now().add(Duration(minutes: expireMinutes)).millisecondsSinceEpoch,
    };
    await prefs.setString(key, jsonEncode(cacheEntry));
  }

  /// 获取缓存数据
  Future<T?> get<T>(String key) async {
    final prefs = await _preferences;
    final jsonStr = prefs.getString(key);
    if (jsonStr == null) return null;

    try {
      final cacheEntry = jsonDecode(jsonStr) as Map<String, dynamic>;
      final expireAt = cacheEntry['expireAt'] as int?;
      if (expireAt != null) {
        final expireTime = DateTime.fromMillisecondsSinceEpoch(expireAt);
        if (DateTime.now().isAfter(expireTime)) {
          await prefs.remove(key);
          return null;
        }
      }
      return cacheEntry['data'] as T?;
    } catch (e) {
      await prefs.remove(key);
      return null;
    }
  }

  /// 获取缓存数据（List）
  Future<List<dynamic>?> getList(String key) async {
    final data = await get<dynamic>(key);
    if (data is List) return data;
    return null;
  }

  /// 获取缓存数据（Map）
  Future<Map<String, dynamic>?> getMap(String key) async {
    final data = await get<dynamic>(key);
    if (data is Map) return data as Map<String, dynamic>;
    return null;
  }

  /// 删除缓存
  Future<void> remove(String key) async {
    final prefs = await _preferences;
    await prefs.remove(key);
  }

  /// 清空所有缓存
  Future<void> clear() async {
    final prefs = await _preferences;
    await prefs.clear();
  }

  /// 批量删除匹配前缀的缓存
  Future<void> clearByPrefix(String prefix) async {
    final prefs = await _preferences;
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

/// 缓存键名常量
class CacheKeys {
  static String feed(int page) => 'feed_page_$page';
  static String userPosts(int userId) => 'user_posts_$userId';
  static String postDetail(int postId) => 'post_detail_$postId';
  static String conversations() => 'conversations';
  static String messages(int convId) => 'messages_$convId';
  static String notifications() => 'notifications';
  static String userProfile(int userId) => 'user_profile_$userId';
  static String trendingTopics() => 'trending_topics';
  static String trendingPosts() => 'trending_posts';
  static String suggestedUsers() => 'suggested_users';
  static String friends() => 'friends';
  static String currentUser() => 'current_user';
  static String searchResults(String query) => 'search_${query.hashCode}';
}
