import 'dart:typed_data';

import 'package:nonto/utils/date_utils.dart';

enum MessageType { text, image, video, post, system }

class Message {
  final int id;
  final int conversationId;
  final int senderId;
  final String? content;
  final MessageType messageType;
  final String? mediaUrl;
  final int? relatedId;
  bool isRead;
  final DateTime? createdAt;
  final String? requestId;

  /// 可靠 WebSocket 发件箱返回的客户端消息 ID，用于匹配服务端回显
  String? clientMsgId;

  /// 服务端生成的消息序号（单调递增，用于排序和离线同步基准）
  int? seq;

  /// 消息发送状态：uploading / sending / sent / failed
  String status;

  /// 本地上传进度：0.0 - 1.0，仅用于上传中的乐观消息
  final double? uploadProgress;

  /// 发送失败的稳定错误码（如 CONTENT_REJECTED / MODERATION_UNAVAILABLE）
  String? failureCode;

  /// 发送失败的安全用户提示
  String? failureMessage;

  /// 失败消息是否允许用户手动重试
  bool? failureRetryable;

  bool get canRetry => status == 'failed' && failureRetryable == true;

  /// 引用的消息 ID
  final int? quoteMessageId;

  /// 引用消息预览文本
  final String? quotePreview;

  /// 是否已撤回
  final bool isRecalled;

  /// 上传失败时暂存的原始 bytes（仅内存，不序列化）
  Uint8List? tempBytes;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.content,
    this.messageType = MessageType.text,
    this.mediaUrl,
    this.relatedId,
    this.isRead = false,
    this.createdAt,
    this.requestId,
    this.clientMsgId,
    this.seq,
    this.status = 'sent',
    this.uploadProgress,
    this.failureCode,
    this.failureMessage,
    this.failureRetryable,
    this.quoteMessageId,
    this.quotePreview,
    this.isRecalled = false,
    this.tempBytes,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final data = normalizeJson(json);
    return Message(
      id: _p(data['id']),
      conversationId: _p(data['conversation_id']),
      senderId: _p(data['sender_id']),
      content: data['content'],
      messageType: _messageTypeFromJson(data),
      mediaUrl: data['media_url']?.toString() ?? data['file_url']?.toString(),
      relatedId: data['related_id'] != null ? _p(data['related_id']) : null,
      isRead: data['is_read'] ?? false,
      createdAt: _serverTime(data),
      requestId: data['request_id']?.toString(),
      clientMsgId:
          data['client_msg_id']?.toString() ?? data['clientMsgId']?.toString(),
      seq: data['seq'] != null ? _p(data['seq']) : null,
      status: data['status'] ?? 'sent',
      uploadProgress: data['upload_progress'] is num
          ? (data['upload_progress'] as num).toDouble()
          : double.tryParse(data['upload_progress']?.toString() ?? ''),
      failureCode: data['failure_code']?.toString(),
      failureMessage: data['failure_message']?.toString(),
      failureRetryable: data['failure_retryable'] is bool
          ? data['failure_retryable'] as bool
          : null,
      quoteMessageId: data['quote_message_id'] != null
          ? _p(data['quote_message_id'])
          : (data['related_type'] == 'quote' && data['related_id'] != null
              ? _p(data['related_id'])
              : null),
      quotePreview: data['quote_preview']?.toString(),
      isRecalled: data['is_recalled'] == true || data['status'] == 'recalled',
    );
  }

  static Map<String, dynamic> normalizeJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json);
    final canonicalTime = data['created_at'] ??
        data['createdAt'] ??
        data['sent_at'] ??
        data['sentAt'] ??
        data['timestamp'] ??
        data['time'];
    data
      ..remove('createdAt')
      ..remove('sent_at')
      ..remove('sentAt')
      ..remove('timestamp')
      ..remove('time');
    if (canonicalTime != null) {
      data['created_at'] = canonicalTime;
    }
    return data;
  }

  static DateTime? _serverTime(Map<String, dynamic> json) {
    final raw = json['created_at'];
    if (raw is num) {
      final value = raw.toInt();
      final milliseconds = value > 1000000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    }
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final numeric = int.tryParse(text);
    if (numeric != null) {
      final milliseconds = numeric > 1000000000000 ? numeric : numeric * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    }
    return AppDateUtils.parseServerTime(text);
  }

  static int _p(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

  static MessageType _messageTypeFromJson(Map<String, dynamic> json) {
    final raw = (json['message_type'] ?? json['type'] ?? 'text').toString();
    return MessageType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MessageType.text,
    );
  }

  bool get isText => messageType == MessageType.text;
  bool get isImage => messageType == MessageType.image;
  bool get isVideo => messageType == MessageType.video;
  bool get isPostCard => messageType == MessageType.post;
  bool get isSystem => messageType == MessageType.system;
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'message_type': messageType.name,
        'media_url': mediaUrl,
        'related_id': relatedId,
        'is_read': isRead,
        'created_at': createdAt?.toIso8601String(),
        'request_id': requestId,
        'client_msg_id': clientMsgId,
        'seq': seq,
        'status': status,
        if (uploadProgress != null) 'upload_progress': uploadProgress,
        if (failureCode != null) 'failure_code': failureCode,
        if (failureMessage != null) 'failure_message': failureMessage,
        if (failureRetryable != null) 'failure_retryable': failureRetryable,
        if (quoteMessageId != null) 'quote_message_id': quoteMessageId,
        if (quotePreview != null) 'quote_preview': quotePreview,
        'is_recalled': isRecalled,
      };

  Message copyWith({
    int? id,
    int? conversationId,
    int? senderId,
    String? content,
    MessageType? messageType,
    String? mediaUrl,
    int? relatedId,
    bool? isRead,
    DateTime? createdAt,
    String? requestId,
    String? clientMsgId,
    int? seq,
    String? status,
    double? uploadProgress,
    String? failureCode,
    String? failureMessage,
    bool? failureRetryable,
    int? quoteMessageId,
    String? quotePreview,
    bool? isRecalled,
    Uint8List? tempBytes,
    bool clearTempBytes = false,
  }) =>
      Message(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        senderId: senderId ?? this.senderId,
        content: content ?? this.content,
        messageType: messageType ?? this.messageType,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        relatedId: relatedId ?? this.relatedId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt ?? this.createdAt,
        requestId: requestId ?? this.requestId,
        clientMsgId: clientMsgId ?? this.clientMsgId,
        seq: seq ?? this.seq,
        status: status ?? this.status,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        failureCode: failureCode ?? this.failureCode,
        failureMessage: failureMessage ?? this.failureMessage,
        failureRetryable: failureRetryable ?? this.failureRetryable,
        quoteMessageId: quoteMessageId ?? this.quoteMessageId,
        quotePreview: quotePreview ?? this.quotePreview,
        isRecalled: isRecalled ?? this.isRecalled,
        tempBytes: clearTempBytes ? null : (tempBytes ?? this.tempBytes),
      );
}

class PaginatedMessages {
  final List<Message> messages;
  final bool hasMore;
  final int currentPage;
  final int pages;

  PaginatedMessages(
      {this.messages = const [],
      this.hasMore = false,
      this.currentPage = 1,
      this.pages = 1});

  factory PaginatedMessages.fromJson(Map<String, dynamic> json) {
    final dynamic rawMessages = json['messages'];
    return PaginatedMessages(
      messages: rawMessages is List
          ? rawMessages
              .map((e) => Message.fromJson(
                  e is Map<String, dynamic> ? e : <String, dynamic>{}))
              .toList()
          : [],
      hasMore: json['has_more'] ?? false,
      currentPage: json['current_page'] ?? 1,
      pages: json['pages'] ?? 1,
    );
  }
}
