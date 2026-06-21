import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 结构迁移器。
///
/// SharedPreferences 存储非结构化 key-value，没有内置 schema 概念。
/// 此迁移器维护一个全局 `__prefs_schema_version`：
/// - 结构性变更（key 改名 / JSON 结构变化）= currentVersion +1
/// - 在 [run] 中追加 `if (from < N) { ... }` 分支
/// - 已发布的分支永不修改
///
/// 版本历史：
/// - v1 (2026-06): 首版基线，无历史 key 需迁移
class PrefsMigrator {
  PrefsMigrator._();

  static const int currentVersion = 1;
  static const String _versionKey = '__prefs_schema_version';

  /// 在 runApp 前调用一次，幂等。
  /// 迁移失败不抛错（避免阻断启动），仅打印日志。
  static Future<void> run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final from = prefs.getInt(_versionKey) ?? 0;
      if (from == currentVersion) return;

      debugPrint('[PrefsMigrator] $from → $currentVersion');

      // v1: 首版基线，无需迁移历史 key
      // if (from < 1) { ... }

      // 未来示例：
      // if (from < 2) {
      //   // 旧 key 'user_cache' → 新 key 'user:profile'
      //   final old = prefs.getString('user_cache');
      //   if (old != null) {
      //     await prefs.setString('user:profile', old);
      //     await prefs.remove('user_cache');
      //   }
      // }

      await prefs.setInt(_versionKey, currentVersion);
    } catch (e) {
      debugPrint('[PrefsMigrator] migration failed (non-fatal): $e');
    }
  }
}
