import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('notification UX regressions', () {
    test('refresh does not implicitly mark all notifications read', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, isNot(contains('NotificationService().markAllRead()')));
    });

    test('notification tap marks read through provider state', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(
        source,
        contains('notificationsProvider.notifier).markAsRead(id)'),
      );
      expect(source, isNot(contains('NotificationService().markRead(id)')));
    });

    test('message notification does not open a synthetic conversation id 0',
        () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, isNot(contains('id: 0,')));
    });

    test('notification badge uses server/provider unread count', () {
      final source = read('lib/providers/core_providers.dart');

      expect(source, contains('return state.unreadCount;'));
      expect(
        source,
        isNot(contains('state.notifications.where((n) => !n.isRead).length')),
      );
    });

    test('messages tab tap does not clear all conversation unread counts', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, isNot(contains('clearAllUnreadCounts()')));
    });

    test('friend request drawer badge only counts unread friend requests', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(
          source, contains('n.parsedType == NotificationType.friendRequest'));
      expect(source, contains('!n.isRead'));
    });
  });
}
