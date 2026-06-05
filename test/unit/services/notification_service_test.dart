import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import '../../helpers/test_helpers.dart';

void main() {
  late NotificationService notificationService;

  setUp(() {
    notificationService = NotificationService();
  });

  tearDown(() {
    tearDownMockDio();
  });

  group('notification_service - getNotifications', () {
    test('getNotifications 列表解析', () async {
      mockSuccess({
        'items': [
          {
            'id': 1, 'user_id': 1, 'sender_id': 2,
            'notification_type': 'like', 'title': 'New like',
            'is_read': false, 'created_at': '2024-03-10T08:00:00.000Z',
          },
        ],
        'page': 1, 'per_page': 20,
      });
      final resp = await notificationService.getNotifications();
      expectSuccess(resp);
    });

    test('getNotifications 分页参数', () async {
      mockSuccess({'items': [], 'page': 2});
      final resp = await notificationService.getNotifications(page: 2, perPage: 10);
      expectSuccess(resp);
    });
  });

  group('notification_service - getUnreadCount', () {
    test('getUnreadCount 返回值', () async {
      mockSuccess({'unread_count': 3});
      final resp = await notificationService.getUnreadCount();
      expectSuccess(resp);
      expect(resp.data['unread_count'], 3);
    });

    test('getUnreadCount 为 0 时', () async {
      mockSuccess({'unread_count': 0});
      final resp = await notificationService.getUnreadCount();
      expectSuccess(resp);
      expect(resp.data['unread_count'], 0);
    });
  });

  group('notification_service - markAllRead', () {
    test('markAllAsRead 调用正确', () async {
      mockSuccess({'message': 'ok'});
      final resp = await notificationService.markAllRead();
      expectSuccess(resp);
    });
  });

  group('notification_service - markRead & delete', () {
    test('markRead 正确调用', () async {
      mockSuccess({'message': 'ok'});
      final resp = await notificationService.markRead(1);
      expectSuccess(resp);
    });

    test('deleteNotification 正确调用', () async {
      mockSuccess({'message': 'deleted'});
      final resp = await notificationService.deleteNotification(1);
      expectSuccess(resp);
    });

    test('clearAll 正确调用', () async {
      mockSuccess({'message': 'cleared'});
      final resp = await notificationService.clearAll();
      expectSuccess(resp);
    });
  });

  group('notification_service - settings', () {
    test('getSettings 正确调用', () async {
      mockSuccess({'push_enabled': true});
      final resp = await notificationService.getSettings();
      expectSuccess(resp);
    });

    test('updateSettings 正确调用', () async {
      mockSuccess({'message': 'updated'});
      final resp = await notificationService.updateSettings({'push_enabled': false});
      expectSuccess(resp);
    });
  });
}
