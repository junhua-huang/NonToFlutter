import 'dart:convert';

/// JSON 缓存信封 —— 所有进入 L2（SQLite cache 表）的缓存数据统一封装。
///
/// 信封结构：
/// ```jsonc
/// { "_v": 1, "_t": 1718800000000, "d": <真实 payload> }
/// ```
/// - `_v`: 数据结构版本（与 CacheEntry.dataVersion 对齐）
/// - `_t`: 写入时间戳（毫秒）
/// - `d`: 真实业务数据
///
/// 读取时按版本号走兼容解码：若 `_v` 与当前期望版本不一致，
/// 由 [CacheEntry.migrate] 决定升级或丢弃。
class CacheEnvelope {
  CacheEnvelope._();

  /// 默认（首版）数据结构版本
  static const int defaultVersion = 1;

  /// 编码 payload 为信封 JSON 字符串。
  static String encode(dynamic payload, {int version = defaultVersion}) {
    return jsonEncode({
      '_v': version,
      '_t': DateTime.now().millisecondsSinceEpoch,
      'd': payload,
    });
  }

  /// 解码信封 JSON 字符串。
  ///
  /// 返回 `(version, payload)`；结构异常/反序列化失败返回 `null`
  /// （让调用方走 L3 网络兜底）。
  static ({int version, dynamic payload})? decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final v = m['_v'] is int
          ? m['_v'] as int
          : defaultVersion; // 兼容历史无版本号数据
      return (version: v, payload: m['d']);
    } catch (_) {
      return null;
    }
  }
}
