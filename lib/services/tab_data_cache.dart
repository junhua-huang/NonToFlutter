import 'package:nonto/services/cache_service.dart';

/// 标签页预加载数据缓存 — 各 Tab 首次加载时优先读取，避免 loading 转圈。
///
/// HomeScreen._preloadTabData() 在首帧后异步写入缓存；
/// Tab 的 initState / _activate 中同步尝试读取，命中则直接渲染。
class TabDataCache {
  static final TabDataCache _instance = TabDataCache._internal();
  factory TabDataCache() => _instance;
  TabDataCache._internal();

  final CacheService _cache = CacheService();

  /// 通知列表缓存（JSON list）
  Future<List<dynamic>?> get notifications =>
      _cache.getList(CacheKeys.notifications());

  /// Feed 帖子第 1 页缓存（JSON list）
  Future<List<dynamic>?> get feedPosts =>
      _cache.getList(CacheKeys.feed(1));

  /// 当前登录用户信息缓存（JSON map）
  Future<Map<String, dynamic>?> get currentUser =>
      _cache.getMap(CacheKeys.currentUser());

  /// 用户帖子缓存（JSON list）
  Future<List<dynamic>?> userPosts(int userId) =>
      _cache.getList(CacheKeys.userPosts(userId));

  // ---- 写入方法（供 preload / 静默刷新使用） ----

  Future<void> setNotifications(List<dynamic> data) =>
      _cache.set(CacheKeys.notifications(), data, expireMinutes: 5);

  Future<void> setFeedPosts(List<dynamic> data) =>
      _cache.set(CacheKeys.feed(1), data, expireMinutes: 10);

  Future<void> setCurrentUser(Map<String, dynamic> data) =>
      _cache.set(CacheKeys.currentUser(), data, expireMinutes: 30);

  Future<void> setUserPosts(int userId, List<dynamic> data) =>
      _cache.set(CacheKeys.userPosts(userId), data, expireMinutes: 10);
}
