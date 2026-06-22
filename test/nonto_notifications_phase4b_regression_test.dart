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

    test('notifications first paint does not wait fifteen seconds to fetch',
        () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source,
          isNot(contains('Future.delayed(const Duration(seconds: 15)')));
      expect(source, contains('_loadInitialNotifications'));
      expect(source, contains('Future.microtask(_loadInitialNotifications)'));
      expect(source, contains('loadNotifications(refresh: true)'));
    });

    test('notifications skeleton only covers an empty initial load', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(
        source,
        contains('state.isInitialLoading && state.notifications.isEmpty'),
      );
      expect(source, contains('_buildNotificationsLoadingState()'));
      expect(
        source,
        isNot(contains(
            'state.isLoading\n            ? _buildNotificationsLoadingState()')),
        reason:
            'Refreshing or loading more must not cover cached notifications.',
      );
    });

    test('cached empty notifications end the initial skeleton', () {
      final notifier = read('lib/providers/notifications_notifier.dart');
      final loadCachedStart = notifier.indexOf('Future<void> _loadCached()');
      final nextMethod =
          notifier.indexOf('void _onWsNotification', loadCachedStart);

      expect(loadCachedStart, greaterThanOrEqualTo(0));
      expect(nextMethod, greaterThan(loadCachedStart));

      final loadCachedBody = notifier.substring(loadCachedStart, nextMethod);
      expect(loadCachedBody, contains('DataLayer()'));
      expect(loadCachedBody, contains('.query(CacheKeys.notifList'));
      expect(loadCachedBody, contains('if (result.data is List)'));
      expect(loadCachedBody, contains('notifications: list'));
      expect(loadCachedBody, contains('isInitialLoading: false'));
      expect(loadCachedBody, isNot(contains('isNotEmpty')));
    });

    test('notifications cache path uses centralized cache keys', () {
      final notifier = read('lib/providers/notifications_notifier.dart');
      final keys = read('lib/services/cache_keys.dart');

      expect(keys, contains('notifList'));
      expect(keys, contains('notifPattern'));
      expect(
        notifier,
        contains("import 'package:nonto/services/cache_keys.dart';"),
      );
      expect(notifier, contains('CacheKeys.notifList'));
      expect(notifier, contains('CacheKeys.notifPattern'));
      expect(notifier, isNot(contains("'notif:list:1'")));
      expect(notifier, isNot(contains("'notif:*'")));
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
