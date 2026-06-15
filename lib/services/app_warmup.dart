import 'dart:async';

import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';

/// 应用本地缓存预热 — 仅从 L2（SQLite）读到 L1（内存），不发网络请求。
///
/// 网络数据加载由各个 UI Provider 的初始化函数自行负责，
/// 闪屏页确保在进入首页之前 token 已经过校验。
class AppWarmup {
  AppWarmup._();

  /// L2 → L1：将 SQLite 中已有的缓存数据预读到内存 DataLayer。
  /// 不发起任何网络请求。
  static Future<void> warmup(String userIdStr) async {
    final layer = DataLayer();
    final keys = [
      'feed:1:posts',
      'notif:list:1',
      CacheKeys.notifUnreadCount,
      'explore:trending_topics',
      'explore:trending_posts',
      'explore:suggested_users',
      'user:$userIdStr:posts',
      'user:$userIdStr:liked:1',
      CacheKeys.convFullList,
    ];

    for (final key in keys) {
      try {
        await layer
            .query(key, () async => null)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }
}
