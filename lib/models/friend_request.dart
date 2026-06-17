import 'package:nonto/utils/date_utils.dart';
import 'user.dart';

enum FriendStatus { none, pending, accepted, rejected }

class FriendRequest {
  final int id;
  final int senderId;
  final int receiverId;
  final String status;
  final User? sender;
  final DateTime? createdAt;

  FriendRequest({
    required this.id, required this.senderId, required this.receiverId,
    required this.status, this.sender, this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
    id: _p(json['id']), senderId: _p(json['sender_id']),
    receiverId: _p(json['receiver_id']), status: json['status'] ?? 'pending',
    sender: json['sender'] != null ? User.fromJson(json['sender']) : null,
    createdAt: json['created_at'] != null ? AppDateUtils.parseBeijingTime(json['created_at'].toString()) : null,
  );

  static int _p(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
}
