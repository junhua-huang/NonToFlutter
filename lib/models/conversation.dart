import 'message.dart';
import 'user.dart';

class Conversation {
  final int id;
  final int user1Id;
  final int user2Id;
  final DateTime? lastMessageAt;
  final User? otherUser;
  final Message? lastMessage;
  final int unreadCount;

  Conversation({
    required this.id, required this.user1Id, required this.user2Id,
    this.lastMessageAt, this.otherUser, this.lastMessage, this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: _p(json['id']), user1Id: _p(json['user1_id']),
    user2Id: _p(json['user2_id']),
    lastMessageAt: json['last_message_at'] != null
        ? DateTime.tryParse(json['last_message_at'].toString()) : null,
    otherUser: json['other_user'] is Map
        ? User.fromJson(Map<String, dynamic>.from(json['other_user']))
        : null,
    lastMessage: json['last_message'] is Map
        ? Message.fromJson(Map<String, dynamic>.from(json['last_message']))
        : null,
    unreadCount: _p(json['unread_count']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user1_id': user1Id,
    'user2_id': user2Id,
    'last_message_at': lastMessageAt?.toIso8601String(),
    'other_user': otherUser?.toJson(),
    'last_message': lastMessage?.toJson(),
    'unread_count': unreadCount,
  };

  static int _p(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
}
