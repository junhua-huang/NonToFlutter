/// 基于 Drift 的强壮 WebSocket 模块
///
/// 提供消息确认、有序交付、发件箱持久化、自动重连等可靠性保障，
/// 与业务完全解耦。
library;

export 'src/client.dart';
export 'src/protocol/message.dart';
export 'src/models/connection_state.dart';
