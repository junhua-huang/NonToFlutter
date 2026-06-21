import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4B notifications source regressions', () {
    test('notifications tab uses Nonto-owned activity wording', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, contains('Nonto 通知页'));
      expect(source, contains('新的互动'));
      expect(source, contains('稍早动态'));
      expect(source, isNot(contains('Twitter')));
      expect(source, isNot(contains('X-style')));
    });

    test('notifications feed renders lazily with builder', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, contains('ListView.builder'));
      expect(source, contains('_buildNotificationEntries('));
      expect(source, contains('itemBuilder: (context, index)'));
      expect(
          source,
          isNot(contains(
              'children: [\n                          ...unread.map')));
      expect(
          source, isNot(contains('read.map(_buildNotificationTile).toList()')));
    });

    test('notifications tab has reusable loading and empty states', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, contains('_buildNotificationsLoadingState()'));
      expect(source, contains('_buildNotificationsEmptyState()'));
      expect(source, contains('当有人与你互动时会出现在这里'));
    });

    test('collapsed read notifications are not built as tiles', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(
          source, contains('_NotificationFeedEntry.readToggle(read.length)'));
      expect(source, contains('if (_showReadNotifications)'));
      expect(source, contains('_NotificationFeedEntry.notification(n)'));
    });

    test('notifications tab keeps reliability semantics', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(
          source, contains('notificationsProvider.notifier).markAsRead(id)'));
      expect(source, contains('SmartRefresher'));
      expect(source, isNot(contains('NotificationService().markAllRead()')));
      expect(source, isNot(contains('id: 0,')));
    });
  });
}
