/// 连接状态枚举
enum ConnectionState {
  /// 未连接
  disconnected,

  /// 正在连接中
  connecting,

  /// 已认证，可正常通信
  authenticated,

  /// 正在重连中
  reconnecting,
}
