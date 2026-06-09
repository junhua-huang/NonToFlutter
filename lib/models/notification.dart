import 'user.dart';

enum NotificationType { like, comment, friendRequest, friendAccept, mention, message }

class AppNotification {
  final int id;
  final int userId;
  final int senderId;
  final User? sender;
  final String notificationType;
  final String? title;
  final String? content;
  final int? relatedId;
  final String? relatedType;
  final bool isRead;
  final DateTime? createdAt;

  AppNotification({
    required this.id, required this.userId, required this.senderId,
    this.sender, required this.notificationType, this.title, this.content,
    this.relatedId, this.relatedType, this.isRead = false, this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: _p(json['id']), userId: _p(json['user_id']),
    senderId: _p(json['sender_id']),
    sender: json['sender'] != null ? User.fromJson(json['sender']) : null,
    notificationType: json['notification_type'] ?? '',
    title: json['title'], content: json['content'],
    relatedId: json['related_id'] != null ? _p(json['related_id']) : null,
    relatedType: json['related_type'],
    isRead: json['is_read'] ?? false,
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
  );

  static int _p(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

  Map<String, dynamic> toJson() => {
    'id': id, 'user_id': userId, 'sender_id': senderId,
    'sender': sender?.toJson(), 'notification_type': notificationType,
    'title': title, 'content': content, 'related_id': relatedId,
    'related_type': relatedType, 'is_read': isRead,
    'created_at': createdAt?.toIso8601String(),
  };

  NotificationType get parsedType {
    switch (notificationType) {
      case 'like': return NotificationType.like;
      case 'comment': return NotificationType.comment;
      case 'friend_request': return NotificationType.friendRequest;
      case 'friend_accept': return NotificationType.friendAccept;
      case 'mention': return NotificationType.mention;
      case 'message': return NotificationType.message;
      default: return NotificationType.message;
    }
  }
}
