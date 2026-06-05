enum MessageType { text, image, video, file, post, comment }

class Message {
  final int id;
  final int conversationId;
  final int senderId;
  final String? content;
  final MessageType messageType;
  final String? mediaUrl;
  final int? relatedId;
  final bool isRead;
  final DateTime? createdAt;

  Message({
    required this.id, required this.conversationId, required this.senderId,
    this.content, this.messageType = MessageType.text, this.mediaUrl,
    this.relatedId, this.isRead = false, this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: _p(json['id']), conversationId: _p(json['conversation_id']),
    senderId: _p(json['sender_id']), content: json['content'],
    messageType: MessageType.values.firstWhere(
      (e) => e.name == (json['message_type'] ?? 'text'),
      orElse: () => MessageType.text),
    mediaUrl: json['media_url'],
    relatedId: json['related_id'] != null ? _p(json['related_id']) : null,
    isRead: json['is_read'] ?? false,
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
  );

  static int _p(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

  bool get isText => messageType == MessageType.text;
  bool get isImage => messageType == MessageType.image;
  bool get isVideo => messageType == MessageType.video;
  bool get isFile => messageType == MessageType.file;
  bool get isPostCard => messageType == MessageType.post;
  bool get isCommentCard => messageType == MessageType.comment;
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id, 'conversation_id': conversationId, 'sender_id': senderId,
    'content': content, 'message_type': messageType.name,
    'media_url': mediaUrl, 'related_id': relatedId,
    'is_read': isRead, 'created_at': createdAt?.toIso8601String(),
  };
}

class PaginatedMessages {
  final List<Message> messages;
  final bool hasMore;
  final int currentPage;
  final int pages;

  PaginatedMessages({this.messages = const [], this.hasMore = false,
    this.currentPage = 1, this.pages = 1});

  factory PaginatedMessages.fromJson(Map<String, dynamic> json) => PaginatedMessages(
    messages: (json['messages'] as List<dynamic>?)?.map((e) => Message.fromJson(e)).toList() ?? [],
    hasMore: json['has_more'] ?? false,
    currentPage: json['current_page'] ?? 1, pages: json['pages'] ?? 1,
  );
}
