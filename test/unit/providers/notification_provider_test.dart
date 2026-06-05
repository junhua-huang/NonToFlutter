import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/notification.dart';

/// 通知相关业务逻辑验证

void main() {
  group('notification_parsed_type', () {
    test('like 通知类型映射正确', () {
      final n = AppNotification(
        id: 1, userId: 1, senderId: 2,
        notificationType: 'like',
      );
      expect(n.parsedType, NotificationType.like);
    });

    test('comment 通知类型映射正确', () {
      final n = AppNotification(
        id: 2, userId: 1, senderId: 2,
        notificationType: 'comment',
      );
      expect(n.parsedType, NotificationType.comment);
    });

    test('friend_request 通知类型映射正确', () {
      final n = AppNotification(
        id: 3, userId: 1, senderId: 2,
        notificationType: 'friend_request',
      );
      expect(n.parsedType, NotificationType.friendRequest);
    });

    test('friend_accept 通知类型映射正确', () {
      final n = AppNotification(
        id: 4, userId: 1, senderId: 2,
        notificationType: 'friend_accept',
      );
      expect(n.parsedType, NotificationType.friendAccept);
    });

    test('mention 通知类型映射正确', () {
      final n = AppNotification(
        id: 5, userId: 1, senderId: 2,
        notificationType: 'mention',
      );
      expect(n.parsedType, NotificationType.mention);
    });

    test('message 通知类型映射正确', () {
      final n = AppNotification(
        id: 6, userId: 1, senderId: 2,
        notificationType: 'message',
      );
      expect(n.parsedType, NotificationType.message);
    });

    test('未知类型降级为 message', () {
      final n = AppNotification(
        id: 7, userId: 1, senderId: 2,
        notificationType: 'unknown_type',
      );
      expect(n.parsedType, NotificationType.message);
    });
  });

  group('notification_is_read', () {
    test('isRead 默认 false', () {
      final n = AppNotification(
        id: 1, userId: 1, senderId: 2,
        notificationType: 'like',
      );
      expect(n.isRead, false);
    });

    test('isRead 从 JSON 解析', () {
      final n = AppNotification.fromJson({
        'id': 1, 'user_id': 1, 'sender_id': 2,
        'notification_type': 'like', 'is_read': true,
      });
      expect(n.isRead, true);
    });
  });

  group('notification_sender', () {
    test('sender 从 JSON 正确解析', () {
      final n = AppNotification.fromJson({
        'id': 1, 'user_id': 1, 'sender_id': 2,
        'notification_type': 'like',
        'sender': {'id': 2, 'username': 'friend', 'email': 'f@e.com'},
      });
      expect(n.sender, isNotNull);
      expect(n.sender!.id, 2);
      expect(n.sender!.username, 'friend');
    });
  });

  group('notification_count_logic', () {
    test('unreadCount 正确计算', () {
      final notifications = [
        AppNotification(id: 1, userId: 1, senderId: 2, notificationType: 'like', isRead: false),
        AppNotification(id: 2, userId: 1, senderId: 3, notificationType: 'comment', isRead: false),
        AppNotification(id: 3, userId: 1, senderId: 4, notificationType: 'like', isRead: true),
      ];
      final unreadCount = notifications.where((n) => !n.isRead).length;
      expect(unreadCount, 2);
    });
  });
}
