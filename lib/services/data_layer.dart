import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:facebook_clone/services/database/app_database.dart';

/// Source of cached data returned from [DataLayer.query].
enum CacheSource { memory, local, remote }

/// Result wrapper returned by [DataLayer.query], carrying a [source] flag
/// so UI can decide whether to show a loading indicator.
class QueryResult {
  final dynamic data;
  final CacheSource source;

  const QueryResult({required this.data, required this.source});
}

/// Three-tier cache layer: L1 (memory LRU) → L2 (SQLite) → L3 (fetcher).
///
/// 响应式机制：write() 时会广播 changeStream，Provider 可监听对应 key 自动刷新 UI。
class DataLayer {
  static final DataLayer _instance = DataLayer._internal();
  factory DataLayer() => _instance;
  DataLayer._internal();

  AppDatabase? _db;

  /// 响应式通知流 — write() 时广播更新的 cacheKey
  final _changeController = StreamController<String>.broadcast();
  Stream<String> get changeStream => _changeController.stream;

  void init(AppDatabase db) {
    _db = db;
  }

  // ── L1: in-memory LRU ──
  static const int _maxL1 = 200;
  final LinkedHashMap<String, _L1Entry> _l1 = LinkedHashMap();

  // ── Network dedup ──
  final Map<String, Future<dynamic>?> _inflight = {};

  // ── TTL per domain (seconds) ──
  static const _defaultTtl = 300;
  static const _ttlByDomain = <String, int>{
    'conv': 120, 'msg': 300, 'feed': 300, 'user': 600, 'notif': 180,
  };

  int _ttlFor(String cacheKey) {
    final domain = cacheKey.split(':').first;
    return _ttlByDomain[domain] ?? _defaultTtl;
  }

  // ── App lifecycle state ──
  DateTime? _lastBackgroundTime;

  // ── Public API ──

  /// Query with cascade: L1 → L2 → L3(fetcher).
  /// If [forceRefresh] is true, skip L1/L2 and go directly to network.
  Future<QueryResult> query(
    String cacheKey,
    Future<dynamic> Function() fetcher, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      // L1
      final l1 = _l1[cacheKey];
      if (l1 != null && !l1.isExpired) {
        _l1.remove(cacheKey);
        _l1[cacheKey] = l1;
        return QueryResult(data: l1.data, source: CacheSource.memory);
      }
      // L2 (带超时，防止 Web IndexedDB 卡死阻塞整个查询)
      try {
        final l2Raw = await _db?.cacheGet(cacheKey).timeout(
          const Duration(seconds: 2),
        );
        if (l2Raw != null) {
          try {
            final decoded = jsonDecode(l2Raw);
            _addL1(cacheKey, decoded);
            return QueryResult(data: decoded, source: CacheSource.local);
          } catch (_) {}
        }
      } catch (_) {
        // DB not ready, schema error, or IndexedDB hang → fall through to L3
      }
    }

    // L3 — dedup in-flight
    if (_inflight.containsKey(cacheKey)) {
      final data = await _inflight[cacheKey];
      return QueryResult(data: data, source: CacheSource.remote);
    }

    final future = fetcher();
    _inflight[cacheKey] = future;
    try {
      final result = await future;
      if (result != null) {
        await write(cacheKey, result);
      }
      return QueryResult(data: result, source: CacheSource.remote);
    } finally {
      _inflight.remove(cacheKey);
    }
  }

  /// Dual-write L1 + L2. [ttlSeconds] overrides domain-based TTL when set.
  Future<void> write(String cacheKey, dynamic data, {int? ttlSeconds}) async {
    _addL1(cacheKey, data);
    try {
      await _db?.cacheSet(cacheKey, jsonEncode(data),
          ttlSeconds: ttlSeconds ?? _ttlFor(cacheKey));
    } catch (_) {}
  }

  /// Invalidate L1 + L2 entries matching a key pattern.
  /// Supports `*` wildcard: `conv:*:list` matches `conv:42:list`.
  Future<void> invalidate(String pattern) async {
    if (pattern.contains('*')) {
      final regex = RegExp('^${pattern.replaceAll('*', r'[^:]+')}\$');
      _l1.removeWhere((k, _) => regex.hasMatch(k));
      final likePattern = pattern.replaceAll('*', '%');
      try { await _db?.cacheDeleteLike(likePattern); } catch (_) {}
    } else {
      _l1.remove(pattern);
      try { await _db?.cacheDelete(pattern); } catch (_) {}
    }
  }

  /// Preload (always calls fetcher). Each entry: {'key': String, 'fetcher': Function}.
  Future<void> preload(List<Map<String, dynamic>> requests) async {
    await Future.wait(requests.map((r) async {
      try {
        final data = await (r['fetcher'] as Future<dynamic> Function())();
        if (data != null) await write(r['key'] as String, data);
      } catch (_) {}
    }));
  }

  /// Warmup: cascade L1→L2→fetcher for each request.
  Future<void> warmup(List<Map<String, dynamic>> requests) async {
    await Future.wait(requests.map((r) async {
      try {
        await query(r['key'] as String, r['fetcher'] as Future<dynamic> Function());
      } catch (_) {}
    }));
  }

  // ── Offline Queue ──
  // TODO: ReliableWebSocket outbox 已内置离线消息持久化+自动重发能力。
  // 此 DataLayer 级离线队列与 ReliableWebSocket 的 outbox 功能重叠，后续可清理。

  /// Write to offline queue when network is unavailable.
  Future<void> writeToQueue(String cacheKey, dynamic data,
      {String action = 'write'}) async {
    _addL1(cacheKey, data);
    try {
      await _db?.offlineQueueInsert(cacheKey, jsonEncode(data), action);
    } catch (_) {}
  }

  /// Flush pending offline queue entries in FIFO order.
  /// Returns {'synced': int, 'failed': int}.
  Future<Map<String, int>> flushOfflineQueue() async {
    final db = _db;
    if (db == null) return {'synced': 0, 'failed': 0};
    final entries = await db.offlineQueueGetAll();
    if (entries.isEmpty) return {'synced': 0, 'failed': 0};

    int synced = 0, failed = 0;
    for (final entry in entries) {
      try {
        dynamic data;
        try { data = jsonDecode(entry.data); } catch (_) { data = entry.data; }
        if (entry.action == 'invalidate') {
          await invalidate(entry.cacheKey);
        } else {
          await write(entry.cacheKey, data);
        }
        await db.offlineQueueDelete(entry.id);
        synced++;
      } catch (_) { failed++; }
    }
    return {'synced': synced, 'failed': failed};
  }

  // ── Memory lifecycle ──

  void onAppBackground() {
    _lastBackgroundTime = DateTime.now();
  }

  Future<void> onAppForeground() async {
    if (_lastBackgroundTime == null) return;
    final elapsed = DateTime.now().difference(_lastBackgroundTime!);
    if (elapsed.inMinutes >= 5) {
      _l1.clear();
    }
    _lastBackgroundTime = null;
  }

  void clearMemory(String keyPrefix) {
    _l1.removeWhere((key, _) => key.startsWith(keyPrefix));
  }

  /// 清空所有内存缓存 + 数据库引用，并广播退出登录事件。
  /// 在用户登出或切换账号时调用，确保新账号不会看到旧账号的缓存数据。
  void clearAll() {
    _l1.clear();
    _inflight.clear();
    _db = null;
    _changeController.add('__auth:logout');
  }

  // ── Internal ──
  void _addL1(String key, dynamic data) {
    if (_l1.length >= _maxL1) _l1.remove(_l1.keys.first);
    _l1.remove(key);
    _l1[key] = _L1Entry(data, _ttlFor(key));
    _changeController.add(key);
  }
}

class _L1Entry {
  final dynamic data;
  final DateTime _expireAt;
  _L1Entry(this.data, int ttlSeconds)
      : _expireAt = DateTime.now().add(Duration(seconds: ttlSeconds));
  bool get isExpired => DateTime.now().isAfter(_expireAt);
}
