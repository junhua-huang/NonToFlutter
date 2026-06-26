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
    this.quoteMessageId,
    this.quotePreview,
    this.isRecalled = false,
    this.tempBytes,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: _p(json['id']),
        conversationId: _p(json['conversation_id']),
        senderId: _p(json['sender_id']),
        content: json['content'],
        messageType: _messageTypeFromJson(json),
        mediaUrl: json['media_url']?.toString() ?? json['file_url']?.toString(),
        relatedId: json['related_id'] != null ? _p(json['related_id']) : null,
        isRead: json['is_read'] ?? false,
        createdAt: AppDateUtils.parseServerTime(json['created_at']?.toString()),
        requestId: json['request_id']?.toString(),
        clientMsgId: json['client_msg_id']?.toString() ??
            json['clientMsgId']?.toString(),
        seq: json['seq'] != null ? _p(json['seq']) : null,
        status: json['status'] ?? 'sent',
        uploadProgress: json['upload_progress'] is num
            ? (json['upload_progress'] as num).toDouble()
            : double.tryParse(json['upload_progress']?.toString() ?? ''),
        quoteMessageId: json['quote_message_id'] != null
            ? _p(json['quote_message_id'])
            : (json['related_type'] == 'quote' && json['related_id'] != null
                ? _p(json['related_id'])
                : null),
        quotePreview: json['quote_preview']?.toString(),
        isRecalled: json['is_recalled'] == true || json['status'] == 'recalled',
      );

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
