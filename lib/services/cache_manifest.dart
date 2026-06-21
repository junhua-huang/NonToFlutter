import 'package:flutter/foundation.dart';

/// 单个缓存条目的元数据 — 描述缓存了 What / Where / How long。
class CacheEntry {
  /// 唯一键字符串（参见 [CacheKeys]）
  final String key;

  /// 业务域：conv / msg / feed / user / notif / explore / search / post / comic
  final String domain;

  /// 中文描述
  final String description;

  /// L1/L2 存活时间（秒）
  final int ttlSeconds;

  /// 数据类型描述（如 List<Map> / Map / int）
  final String dataShape;

  /// 是否应在 AppWarmup 阶段预加载
  final bool isWarmup;

  /// 是否为参数化 key（运行时由方法生成，如 msgRecent(convId)）
  final bool isParameterized;

  /// 该条目 payload 的数据结构版本。
  /// 与 [CacheEnvelope] 的 `_v` 字段对齐：payload 结构变更时 +1。
  /// DataLayer 读取时若版本不匹配，调用 [migrate] 升级或丢弃。
  final int dataVersion;

  /// payload 旧版本 → 当前 [dataVersion] 的升级函数。
  /// - 返回升级后的 payload（会回写缓存）
  /// - 返回 null 表示丢弃，DataLayer 会删除该缓存条目并走 L3 网络
  /// - 为 null 表示无升级路径，版本不匹配直接丢弃
  final dynamic Function(int fromVersion, dynamic payload)? migrate;

  const CacheEntry({
    required this.key,
    required this.domain,
    required this.description,
    required this.ttlSeconds,
    required this.dataShape,
    this.isWarmup = false,
    this.isParameterized = false,
    this.dataVersion = 1,
    this.migrate,
  });
}

/// 所有缓存条目的中心化注册表。
///
/// 打开这一个文件，就能看到项目中「哪些数据进入了缓存层」。
///
/// 参数化 key 使用 `{param}` 占位，实际 key 由 [CacheKeys] 方法生成。
///
/// ```dart
/// // 遍历所有缓存条目
/// CacheManifest.entries.forEach((e) => print('${e.domain} | ${e.key}'));
///
/// // 打印完整注册表
/// CacheManifest.printAll();
/// ```
class CacheManifest {
  CacheManifest._();

  // ═══════════════════════════════════════════════════════════════
  //  所有缓存条目 —— 按域分组
  //  模板语法：{param} 为参数占位，实际 key 见 CacheKeys
  // ═══════════════════════════════════════════════════════════════

  // ── 会话 ──
  static final _convFullList = const CacheEntry(
    key: 'conv:full:list',
    domain: 'conv',
    description: '会话完整列表',
    ttlSeconds: 120,
    dataShape: 'List<Map>',
    isWarmup: true,
  );

  static final _convPattern = const CacheEntry(
    key: 'conv:*:list',
    domain: 'conv',
    description: '会话域 invalidate 模式',
    ttlSeconds: 0,
    dataShape: '-',
  );

  // ── 聊天消息 ──
  static final _msgWarmup = const CacheEntry(
    key: 'msg:{convId}:1',
    domain: 'msg',
    description: '会话预热消息（page=1）',
    ttlSeconds: 300,
    dataShape: 'List<Map>',
    isWarmup: true,
    isParameterized: true,
  );

  static final _msgRecent = const CacheEntry(
    key: 'msg:{convId}:recent',
    domain: 'msg',
    description: '会话最近消息（运行时）',
    ttlSeconds: 300,
    dataShape: 'List<Map>',
    isParameterized: true,
  );

  static final _msgRecentByUser = const CacheEntry(
    key: 'msg:{userId}:{convId}:recent',
    domain: 'msg',
    description: '用户维度最近消息',
    ttlSeconds: 300,
    dataShape: 'List<Map>',
    isParameterized: true,
  );

  // ── Feed ──
  static final _feedPage1 = const CacheEntry(
    key: 'feed:1:posts',
    domain: 'feed',
    description: '首页 Feed 第1页',
    ttlSeconds: 300,
    dataShape: 'List<Map>',
    isWarmup: true,
  );

  static final _feedPaged = const CacheEntry(
    key: 'feed:{page}:posts',
    domain: 'feed',
    description: 'Feed 分页',
    ttlSeconds: 300,
    dataShape: 'List<Map>',
    isParameterized: true,
  );

  // ── 用户 ──
  static final _userProfile = const CacheEntry(
    key: 'user:{userId}:profile',
    domain: 'user',
    description: '用户资料',
    ttlSeconds: 600,
    dataShape: 'Map',
    isWarmup: true,
    isParameterized: true,
  );

  static final _userPosts = const CacheEntry(
    key: 'user:{userId}:posts',
    domain: 'user',
    description: '用户帖子列表',
    ttlSeconds: 600,
    dataShape: 'List<Map>',
    isWarmup: true,
    isParameterized: true,
  );

  static final _userPostsPaged = const CacheEntry(
    key: 'user:{userId}:posts:{page}',
    domain: 'user',
    description: '用户帖子列表（分页）',
    ttlSeconds: 600,
    dataShape: 'List<Map>',
    isParameterized: true,
  );

  static final _userLiked = const CacheEntry(
    key: 'user:{userId}:liked:1',
    domain: 'user',
    description: '用户点赞帖子',
    ttlSeconds: 600,
    dataShape: 'List<Map>',
    isWarmup: true,
    isParameterized: true,
  );

  // ── 通知 ──
  static final _notifList1 = const CacheEntry(
    key: 'notif:list:1',
    domain: 'notif',
    description: '通知列表第1页',
    ttlSeconds: 180,
    dataShape: 'List<Map>',
    isWarmup: true,
  );

  static final _notifPattern = const CacheEntry(
    key: 'notif:*',
    domain: 'notif',
    description: '通知域 invalidate 模式',
    ttlSeconds: 0,
    dataShape: '-',
  );

  // ── 发现 ──
  static final _exploreTopics = const CacheEntry(
    key: 'explore:trending_topics',
    domain: 'explore',
    description: '热门话题',
    ttlSeconds: 600,
    dataShape: 'List<Map>',
    isWarmup: true,
  );

  static final _explorePosts = const CacheEntry(
    key: 'explore:trending_posts',
    domain: 'explore',
    description: '热门帖子',
    ttlSeconds: 300,
    dataShape: 'List<Map>',
    isWarmup: true,
  );

  static final _exploreUsers = const CacheEntry(
    key: 'explore:suggested_users',
    domain: 'explore',
    description: '推荐用户',
    ttlSeconds: 600,
    dataShape: 'List<Map>',
    isWarmup: true,
  );

  // ── 搜索 ──
  static final _searchGlobal = const CacheEntry(
    key: 'search:{query}:global:1',
    domain: 'search',
    description: '全局搜索结果',
    ttlSeconds: 120,
    dataShape: 'Map',
    isParameterized: true,
  );

  // ── 帖子详情 ──
  static final _postDetail = const CacheEntry(
    key: 'post:{postId}:detail',
    domain: 'post',
    description: '帖子详情',
    ttlSeconds: 300,
    dataShape: 'Map',
    isParameterized: true,
  );

  // ── 漫展 ──
  static final _comicEvents = const CacheEntry(
    key: 'comic:events',
    domain: 'comic',
    description: '漫展事件列表',
    ttlSeconds: 600,
    dataShape: 'List<Map>',
  );

  static final _comicDetail = const CacheEntry(
    key: 'comic:{eventId}:detail',
    domain: 'comic',
    description: '漫展详情',
    ttlSeconds: 600,
    dataShape: 'Map',
    isParameterized: true,
  );

  // ═══════════ 汇总 ═══════════

  /// 所有已注册的缓存条目。
  static final List<CacheEntry> entries = [
    _convFullList,
    _convPattern,
    _msgWarmup,
    _msgRecent,
    _msgRecentByUser,
    _feedPage1,
    _feedPaged,
    _userProfile,
    _userPosts,
    _userPostsPaged,
    _userLiked,
    _notifList1,
    _notifPattern,
    _exploreTopics,
    _explorePosts,
    _exploreUsers,
    _searchGlobal,
    _postDetail,
    _comicEvents,
    _comicDetail,
  ];

  /// 需要 AppWarmup 预热的条目。
  static List<CacheEntry> get warmupEntries =>
      entries.where((e) => e.isWarmup).toList();

  /// 按域筛选。
  static List<CacheEntry> byDomain(String domain) =>
      entries.where((e) => e.domain == domain).toList();

  /// 按精确 key 查找（参数化 key 不参与匹配，返回 null）。
  /// 用于 DataLayer 读取时获取该条目的 dataVersion / migrate。
  static CacheEntry? byKey(String key) {
    for (final e in entries) {
      if (e.isParameterized) continue;
      if (e.key == key) return e;
    }
    return null;
  }

  /// 按 domain 前缀匹配参数化 key 的 dataVersion。
  /// 用于 DataLayer 读取运行时生成的 key（如 `msg:42:recent`）时
  /// 回退到同 domain 的 dataVersion。
  static CacheEntry? byDomainMatch(String key) {
    final domain = key.split(':').first;
    // 优先返回同 domain 的非参数化条目，其次参数化条目
    for (final e in entries) {
      if (e.domain == domain && !e.isParameterized) return e;
    }
    for (final e in entries) {
      if (e.domain == domain && e.isParameterized) return e;
    }
    return null;
  }

  /// 域列表。
  static List<String> get domains =>
      entries.map((e) => e.domain).toSet().toList()..sort();

  /// 调试：打印完整注册表。
  static void printAll() {
    debugPrint('═══ CacheManifest ═══');
    var currentDomain = '';
    for (final e in entries) {
      if (e.domain != currentDomain) {
        currentDomain = e.domain;
        debugPrint('');
        debugPrint('  ── ${e.domain} ──');
      }
      final warmup = e.isWarmup ? '[warmup]' : '';
      final param = e.isParameterized ? '(param)' : '';
      debugPrint(
        '  ${e.key.padRight(32)} ${e.dataShape.padRight(16)} $warmup$param  ${e.description}',
      );
    }
  }
}