/// 协议消息类型定义 — WS 协议 v1.0
///
/// 所有消息遵循统一信封：{type, request_id?, seq?, payload:{...}}
library;

/// WebSocket 消息类型枚举
enum MessageType {
  // ---- 客户端 → 服务端 ----
  /// 认证请求：连接建立后立即发送，payload: {token, device_id?}
  auth,

  /// 聊天消息发送：payload: {client_msg_id, conversation_id, content, ...}
  sendMessage('send_message'),

  /// 状态事件发送（fire-and-forget，不走 ACK）：payload: {event, ...}
  sendEvent('send_event'),

  /// 消息确认回执：payload: {seq}
  ackReceive('ack_receive'),

  /// 同步请求：payload: {last_received_seq, limit?}
  sync,

  /// 心跳保活：payload: {}
  ping,

  /// 加入会话房间：payload: {conversation_id}
  join,

  /// 离开会话房间：payload: {conversation_id}
  leave,

  /// 正在输入：payload: {conversation_id}
  typing,

  /// 停止输入：payload: {conversation_id}
  stopTyping('stop_typing'),

  // ---- 服务端 → 客户端 ----
  /// 认证结果：payload: {success, user_id?, code?, msg?}
  authResult('auth_result'),

  /// 确认回执：payload: {client_msg_id, server_seq, message_id, status, msg?}
  ack,

  /// 推送消息：seq + payload: {event, data: {...}}
  message,

  /// 同步结果：payload: {list, count, has_more?, current_max_seq?}
  syncResult('sync_result'),

  /// 心跳响应：payload: {}
  pong,

  /// 错误通知：payload: {code, msg}
  error;

  final String wireName;
  const MessageType([this.wireName = '']);
  String get jsonName => wireName.isNotEmpty ? wireName : name;

  static MessageType fromJsonName(String name) {
    for (final type in values) {
      if (type.jsonName == name) return type;
    }
    throw FormatException('Unknown message type: $name');
  }
}

/// 协议消息帧（v1.0 统一信封格式）
///
/// ```json
/// { "type": "send_message", "request_id": "req_001", "payload": { "client_msg_id": "uuid", ... } }
/// ```
class ProtocolFrame {
  final MessageType type;
  final String? requestId;
  final int? seq;
  final Map<String, dynamic>? payload;
  /// 完整原始 JSON（用于访问未建模的自定义字段）
  final Map<String, dynamic>? rawJson;

  const ProtocolFrame({
    required this.type,
    this.requestId,
    this.seq,
    this.payload,
    this.rawJson,
  });

  /// 从 JSON Map 解码
  factory ProtocolFrame.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    final type = typeStr != null
        ? MessageType.fromJsonName(typeStr)
        : MessageType.message;

    var payload = json['payload'] as Map<String, dynamic>?;
    // 向后兼容旧协议（字段平铺无 payload 包裹）
    if (payload == null) {
      payload = _extractLegacyPayload(json, type);
    }

    return ProtocolFrame(
      type: type,
      requestId: json['request_id'] as String?,
      seq: json['seq'] as int?,
      payload: payload,
      rawJson: json,
    );
  }

  /// 旧协议帧字段平铺 → 聚合成 payload
  static Map<String, dynamic>? _extractLegacyPayload(
      Map<String, dynamic> json, MessageType type) {
    switch (type) {
      case MessageType.authResult:
        return {
          if (json.containsKey('success')) 'success': json['success'],
          if (json.containsKey('user_id')) 'user_id': json['user_id'],
        };
      case MessageType.ack:
        return {
          if (json.containsKey('client_msg_id')) 'client_msg_id': json['client_msg_id'],
          if (json.containsKey('server_seq')) 'server_seq': json['server_seq'],
          if (json.containsKey('message_id')) 'message_id': json['message_id'],
          if (json.containsKey('status')) 'status': json['status'],
          if (json.containsKey('msg')) 'msg': json['msg'],
        };
      case MessageType.error:
        return {
          if (json.containsKey('code')) 'code': json['code'],
          if (json.containsKey('msg')) 'msg': json['msg'],
          if (json.containsKey('message')) 'message': json['message'],
        };
      case MessageType.syncResult:
        final list = json['list'] ?? json['messages'];
        return {
          if (json.containsKey('count')) 'count': json['count'],
          if (list != null) 'list': list,
          'has_more': json['has_more'] ?? false,
        };
      case MessageType.message:
        return Map<String, dynamic>.from(json)
          ..remove('type')
          ..remove('seq')
          ..remove('request_id');
      default:
        return null;
    }
  }

  /// 编码为 JSON Map
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type.jsonName};
    if (requestId != null) map['request_id'] = requestId;
    if (seq != null) map['seq'] = seq;
    if (payload != null) map['payload'] = payload;
    return map;
  }

  // ── 便捷：从 payload 读取字段 ──

  /// auth_result: payload.success
  bool? get success => payload?['success'] as bool?;

  /// auth_result: payload.user_id
  int? get userId => payload is Map ? (payload!['user_id'] as int?) : null;

  /// error: payload.msg 或 payload.code
  String? get errorMsg => payload is Map
      ? ((payload!['msg'] ?? payload!['message'] ?? payload!['error']) as String?)
      : null;

  /// ack: payload.client_msg_id
  String? get ackClientMsgId => payload is Map ? payload!['client_msg_id'] as String? : null;

  /// ack: payload.message_id
  int? get ackMessageId => payload is Map ? payload!['message_id'] as int? : null;

  /// ack: payload.server_seq
  int? get ackServerSeq => payload is Map ? payload!['server_seq'] as int? : null;

  /// sync_result: payload.list
  List<dynamic>? get syncList => payload is Map ? payload!['list'] as List<dynamic>? : null;

  /// session_list: payload.sessions
  List<dynamic>? get sessionList => payload is Map ? payload!['sessions'] as List<dynamic>? : null;

  /// friend_online / typing 等自定义事件
  String? get eventName => payload is Map ? payload!['event'] as String? : null;

  @override
  String toString() =>
      'ProtocolFrame(type: ${type.name}, requestId: $requestId, seq: $seq)';
}
