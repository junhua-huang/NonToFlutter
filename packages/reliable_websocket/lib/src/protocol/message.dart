/// 协议消息类型定义
///
/// 客户端和服务端之间的所有通信都遵循此协议格式。
/// 业务数据封装在 [payload] 字段中，模块透传不解析。
library;

/// WebSocket 消息类型枚举
enum MessageType {
  // ---- 客户端 → 服务端 ----
  /// 认证请求：连接建立后立即发送，携带 [token]
  auth,

  /// 业务消息发送：携带 [clientMsgId] 和 [payload]
  send,

  /// 消息确认回执：确认收到某条消息（可选，用于流量控制）
  ackReceive('ack_receive'),

  /// 同步请求：重连后请求补发缺失消息，携带 [lastReceivedSeq]
  sync,

  /// 心跳保活
  ping,

  /// 加入会话房间
  join,

  /// 离开会话房间
  leave,

  /// 正在输入
  typing,

  /// 停止输入
  stopTyping('stop_typing'),

  // ---- 服务端 → 客户端 ----
  /// 认证结果：携带 [success] 和可选的 [error]
  authResult('auth_result'),

  /// 服务端确认收到客户端消息：携带 [clientMsgId] 和 [serverSeq]
  ack,

  /// 服务端推送消息：携带 [seq] 和 [payload]
  message,

  /// 同步结果：响应 sync 请求，返回补发消息列表
  syncResult('sync_result'),

  /// 心跳响应
  pong,

  /// 服务端错误通知：携带 [error]（message 字段）和 [clientMsgId]
  error;

  /// JSON 序列化时使用的线格式名称
  final String wireName;

  const MessageType([this.wireName = '']);

  /// 获取线格式名称（有自定义名称用自定义，否则用枚举名）
  String get jsonName => wireName.isNotEmpty ? wireName : name;

  /// 从线格式名称解析
  static MessageType fromJsonName(String name) {
    // 先按 wireName 匹配
    for (final type in values) {
      if (type.jsonName == name) return type;
    }
    throw FormatException('Unknown message type: $name');
  }
}

/// 协议消息帧
///
/// 所有上下行消息均为此 JSON 格式：
/// ```json
/// { "type": "send", "clientMsgId": "...", "payload": {...} }
/// ```
class ProtocolFrame {
  /// 消息类型
  final MessageType type;

  /// 客户端消息 ID（send / ack 帧使用）
  final String? clientMsgId;

  /// 服务端序号（message / ack 帧使用）
  final int? seq;

  /// 服务端分配的序号（ack 帧使用）
  final int? serverSeq;

  /// 业务 payload（send / message 帧使用）
  final Map<String, dynamic>? payload;

  /// 认证 token（auth 帧使用）
  final String? token;

  /// 认证结果（auth_result 帧使用）
  final bool? success;

  /// 错误信息（auth_result 帧使用）
  final String? error;

  /// 最后已接收序号（sync 帧使用）
  final int? lastReceivedSeq;

  /// 补发消息列表（sync_result 帧使用）
  final List<ProtocolFrame>? messages;

  const ProtocolFrame({
    required this.type,
    this.clientMsgId,
    this.seq,
    this.serverSeq,
    this.payload,
    this.token,
    this.success,
    this.error,
    this.lastReceivedSeq,
    this.messages,
  });

  /// 从 JSON Map 解码
  factory ProtocolFrame.fromJson(Map<String, dynamic> json) {
    // sync_result 内嵌消息可能没有 type 字段，默认为 message
    final typeStr = json['type'] as String?;
    final type = typeStr != null
        ? MessageType.fromJsonName(typeStr)
        : MessageType.message;

    final messagesRaw = json['messages'];
    List<ProtocolFrame>? messages;
    if (messagesRaw is List) {
      messages = messagesRaw
          .map((m) => ProtocolFrame.fromJson(m as Map<String, dynamic>))
          .toList();
    }

    return ProtocolFrame(
      type: type,
      clientMsgId: json['clientMsgId'] as String?,
      seq: json['seq'] as int?,
      serverSeq: json['serverSeq'] as int?,
      payload: json['payload'] as Map<String, dynamic>?,
      token: json['token'] as String?,
      success: json['success'] as bool?,
      // error 帧用 message 字段，auth_result 用 error 字段
      error: (json['error'] ?? json['message']) as String?,
      lastReceivedSeq: json['lastReceivedSeq'] as int?,
      messages: messages,
    );
  }

  /// 编码为 JSON Map
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type.jsonName};

    void putIf(String key, Object? value) {
      if (value != null) map[key] = value;
    }

    putIf('clientMsgId', clientMsgId);
    putIf('seq', seq);
    putIf('serverSeq', serverSeq);
    putIf('payload', payload);
    putIf('token', token);
    putIf('success', success);
    putIf('error', error);
    putIf('lastReceivedSeq', lastReceivedSeq);
    if (messages != null) {
      map['messages'] = messages!.map((m) => m.toJson()).toList();
    }

    return map;
  }

  @override
  String toString() => 'ProtocolFrame(type: ${type.name}, '
      'clientMsgId: $clientMsgId, seq: $seq)';
}
