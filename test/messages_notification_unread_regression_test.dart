import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/services/api/api_client.dart';

void main() {
  group('NotificationsNotifier unread refresh', () {
    test('accepts unread_count and count with integer or string values',
        () async {
      final responses = <ApiResponse>[
        ApiResponse(success: true, data: {'unread_count': 4}),
        ApiResponse(success: true, data: {'count': '9'}),
      ];
      var requestIndex = 0;
      final notifier = NotificationsNotifier(
        getUnreadCount: () async => responses[requestIndex++],
      );
      addTearDown(notifier.dispose);

      await notifier.refreshUnreadCount();
      expect(notifier.state.unreadCount, 4);

      await notifier.refreshUnreadCount();
      expect(notifier.state.unreadCount, 9);
    });

    test('parses a JSON-encoded map response', () async {
      final notifier = NotificationsNotifier(
        getUnreadCount: () async =>
            ApiResponse(success: true, data: '{"unread_count":"8"}'),
      );
      addTearDown(notifier.dispose);

      await notifier.refreshUnreadCount();

      expect(notifier.state.unreadCount, 8);
    });

    test('keeps cached count on failure, malformed data, and exceptions',
        () async {
      var requestIndex = 0;
      final notifier = NotificationsNotifier(
        getUnreadCount: () async {
          requestIndex++;
          switch (requestIndex) {
            case 1:
              return ApiResponse(success: true, data: {'count': '7'});
            case 2:
              return ApiResponse(success: false, data: {'count': 0});
            case 3:
              return ApiResponse(success: true, data: {'unread_count': 'bad'});
            default:
              throw StateError('network unavailable');
          }
        },
      );
      addTearDown(notifier.dispose);

      await notifier.refreshUnreadCount();
      expect(notifier.state.unreadCount, 7);

      await notifier.refreshUnreadCount();
      expect(notifier.state.unreadCount, 7);

      await notifier.refreshUnreadCount();
      expect(notifier.state.unreadCount, 7);

      await notifier.refreshUnreadCount();
      expect(notifier.state.unreadCount, 7);
    });

    test('coalesces concurrent unread count refreshes', () async {
      final responses = [
        Completer<ApiResponse>(),
        Completer<ApiResponse>(),
      ];
      var requests = 0;
      final notifier = NotificationsNotifier(
        getUnreadCount: () => responses[requests++].future,
      );
      addTearDown(notifier.dispose);

      final first = notifier.refreshUnreadCount();
      final second = notifier.refreshUnreadCount();

      expect(requests, 1);
      responses[0]
          .complete(ApiResponse(success: true, data: {'unread_count': 6}));
      await Future.wait([first, second]);

      expect(requests, 1);
      expect(notifier.state.unreadCount, 6);

      final third = notifier.refreshUnreadCount();

      expect(requests, 2);
      responses[1]
          .complete(ApiResponse(success: true, data: {'unread_count': 11}));
      await third;

      expect(notifier.state.unreadCount, 11);
    });
  });

  group('MessagesTab notification unread wiring', () {
    final projectRoot = Directory.current.path;
    String read(String relativePath) =>
        File('$projectRoot/$relativePath').readAsStringSync();

    test('initial entry refreshes conversations and notification unread count',
        () {
      final source = read('lib/screens/messages/messages_tab.dart');
      final initStart = source.indexOf('void initState()');
      final initEnd =
          source.indexOf('void _preloadRecentChatMessages()', initStart);
      expect(initStart, greaterThanOrEqualTo(0));
      expect(initEnd, greaterThan(initStart));
      final initSource = source.substring(initStart, initEnd);

      expect(initSource, contains('conversationsProvider.notifier'));
      expect(initSource, contains('.loadConversations()'));
      expect(initSource, contains('notificationsProvider.notifier'));
      expect(initSource, contains('.refreshUnreadCount()'));
    });

    test('pull refresh awaits conversations and notification unread count', () {
      final source = read('lib/screens/messages/messages_tab.dart');
      final refreshStart = source.indexOf('Future<void> _onRefresh()');
      final refreshEnd =
          source.indexOf('void _openNotifications()', refreshStart);
      expect(refreshStart, greaterThanOrEqualTo(0));
      expect(refreshEnd, greaterThan(refreshStart));
      final refreshSource = source.substring(refreshStart, refreshEnd);

      expect(refreshSource, contains('await Future.wait'));
      expect(refreshSource, contains('conversationsProvider.notifier'));
      expect(refreshSource, contains('.loadConversations()'));
      expect(refreshSource, contains('notificationsProvider.notifier'));
      expect(refreshSource, contains('.refreshUnreadCount()'));
    });

    test('badge source is notifications provider, not conversations state', () {
      final messages = read('lib/screens/messages/messages_tab.dart');
      final coreProviders = read('lib/providers/core_providers.dart');

      expect(messages, contains('ref.watch(unreadNotificationsCountProvider)'));
      expect(coreProviders, contains('ref.watch(notificationsProvider)'));
      expect(coreProviders, contains('return state.unreadCount;'));
    });

    test(
        'conversations refresh does not fetch notification-center unread count',
        () {
      final conversations = read('lib/providers/chat_notifiers.dart');

      expect(conversations, isNot(contains('NotificationService()')));
      expect(
        conversations,
        isNot(contains("services/api/notification_service.dart")),
      );
    });
  });
}
