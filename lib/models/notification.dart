import 'package:nonto/utils/date_utils.dart';
import 'user.dart';

enum NotificationType {
  like,
  comment,
  friendRequest,
  friendAccept,
  mention,
  message,
  communityJoinRequest,
  system,
}

class AppNotification {
  final int id;
  final int userId;
  final int? senderId;
  final User? sender;
  final String notificationType;
  final String? title;
  final String? content;
  final int? relatedId;
  final String? relatedType;
  final bool isRead;
  final DateTime? createdAt;

  AppNotification({
    required this.id, required this.userId, this.senderId,
    this.sender, required this.notificationType, this.title, this.content,
    this.relatedId, this.relatedType, this.isRead = false, this.createdAt,
  });

  AppNotification copyWith({
    int? id,
    int? userId,
    int? senderId,
    User? sender,
    String? notificationType,
    String? title,
    String? content,
    int? relatedId,
    String? relatedType,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      senderId: senderId ?? this.senderId,
      sender: sender ?? this.sender,
      notificationType: notificationType ?? this.notificationType,
      title: title ?? this.title,
      content: content ?? this.content,
      relatedId: relatedId ?? this.relatedId,
      relatedType: relatedType ?? this.relatedType,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: _p(json['id']), userId: _p(json['user_id']),
    senderId: json['sender_id'] != null ? _p(json['sender_id']) : null,
    sender: json['sender'] is Map
        ? User.fromJson(Map<String, dynamic>.from(json['sender']))
        : null,
    notificationType: (json['notification_type'] ?? json['type']) ?? '',
    title: json['title'], content: json['content'],
    relatedId: json['related_id'] != null ? _p(json['related_id']) : null,
    relatedType: json['related_type'],
    isRead: json['is_read'] ?? false,
    createdAt: json['created_at'] != null ? AppDateUtils.parseBeijingTime(json['created_at'].toString()) : null,
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
      case 'community_join_request': return NotificationType.communityJoinRequest;
      case 'system': return NotificationType.system;
      default: return NotificationType.system;
    }
  }
}
