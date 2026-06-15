/// 协议编解码器 — WS 协议 v1.0
library;

import 'dart:convert';
import 'message.dart';

class ProtocolCodec {
  const ProtocolCodec();

  String encode(ProtocolFrame frame) => jsonEncode(frame.toJson());
  ProtocolFrame decode(String data) =>
      ProtocolFrame.fromJson(jsonDecode(data) as Map<String, dynamic>);

  /// auth: {type:"auth", payload:{token, device_id?}}
  static ProtocolFrame auth(String token, {String? deviceId}) {
    final p = <String, dynamic>{'token': token};
    if (deviceId != null) p['device_id'] = deviceId;
    return ProtocolFrame(type: MessageType.auth, payload: p);
  }

  /// send_message: {type:"send_message", payload:{client_msg_id, conversation_id, content, ...}}
  static ProtocolFrame sendMessage(String clientMsgId, Map<String, dynamic> payload) {
    final p = Map<String, dynamic>.from(payload);
    p['client_msg_id'] = clientMsgId;
    return ProtocolFrame(type: MessageType.sendMessage, payload: p);
  }

  /// send_event: {type:"send_event", payload:{event, ...}}
  static ProtocolFrame sendEvent(Map<String, dynamic> payload) {
    return ProtocolFrame(type: MessageType.sendEvent, payload: payload);
  }

  /// sync: {type:"sync", payload:{last_received_seq, limit:200}}
  static ProtocolFrame sync(int lastReceivedSeq, {int limit = 200}) {
    return ProtocolFrame(type: MessageType.sync, payload: {
      'last_received_seq': lastReceivedSeq,
      'limit': limit,
    });
  }

  /// ping: {type:"ping", payload:{}}
  static const ProtocolFrame ping = ProtocolFrame(
    type: MessageType.ping,
    payload: <String, dynamic>{},
  );

  /// 通用 payload 帧（join/leave/typing 等）
  static ProtocolFrame withPayload(MessageType type, Map<String, dynamic> payload) {
    return ProtocolFrame(type: type, payload: payload);
  }
}
