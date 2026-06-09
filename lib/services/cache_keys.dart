/// 统一缓存键名常量，避免硬编码字符串散落各处。
///
/// 命名规范：`domain:entity[:params]`
/// - domain: 数据域（conv / msg / feed / user / notif）
/// - entity: 实体类型
/// - params: 可选参数（会话 ID / 用户 ID / 页码等）
class CacheKeys {
  CacheKeys._();

  // ── 会话 ──
  static const String convFullList = 'conv:full:list';
  /// 用于 invalidate 的泛匹配模式
  static const String convPattern = 'conv:*:list';

  // ── 聊天消息 ──
  /// 预热缓存（page 1，AppWarmup 写入）
  static String msgWarmup(int convId) => 'msg:$convId:1';
  /// 会话最近消息（标准 key）
  static String msgRecent(int convId) => 'msg:$convId:recent';
  /// 用户维度最近消息（带 userId 前缀）
  static String msgRecentByUser(int convId, String userId) => 'msg:$userId:$convId:recent';
}