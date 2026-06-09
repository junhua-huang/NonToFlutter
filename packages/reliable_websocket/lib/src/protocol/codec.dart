/// 协议编解码器
///
/// 负责 JSON 帧的构造与解析，区分控制消息和业务透传 payload。
library;

import 'dart:convert';
import 'message.dart';

/// WebSocket 协议编解码器
class ProtocolCodec {
  const ProtocolCodec();

  /// 编码为 JSON 字符串
  String encode(ProtocolFrame frame) {
    return jsonEncode(frame.toJson());
  }

  /// 解码 JSON 字符串为协议帧
  ProtocolFrame decode(String data) {
    final json = jsonDecode(data) as Map<String, dynamic>;
    return ProtocolFrame.fromJson(json);
  }

  /// 便捷方法：构造 auth 帧
  static ProtocolFrame auth(String token) {
    return ProtocolFrame(type: MessageType.auth, token: token);
  }

  /// 便捷方法：构造 send 帧
  static ProtocolFrame send(String clientMsgId, Map<String, dynamic> payload) {
    return ProtocolFrame(
      type: MessageType.send,
      clientMsgId: clientMsgId,
      payload: payload,
    );
  }

  /// 便捷方法：构造 sync 帧
  static ProtocolFrame sync(int lastReceivedSeq) {
    return ProtocolFrame(
      type: MessageType.sync,
      lastReceivedSeq: lastReceivedSeq,
    );
  }

  /// 便捷方法：构造 ping 帧
  static const ProtocolFrame ping = ProtocolFrame(type: MessageType.ping);
}
