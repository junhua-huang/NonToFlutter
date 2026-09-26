import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/services/api/api_client.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  StreamController<T> trackedController<T>() {
    return StreamController<T>.broadcast();
  }

  MessagesNotifier createNotifier({
    required Future<ApiResponse> Function(int) loadUserStatus,
    Stream<bool>? connectionStream,
    Stream<Map<String, dynamic>>? friendOnlineStream,
    Stream<Map<String, dynamic>>? friendOfflineStream,
  }) {
    return MessagesNotifier(
      101,
      loadUserStatus: loadUserStatus,
      connectionStream: connectionStream ?? const Stream<bool>.empty(),
      friendOnlineStream:
          friendOnlineStream ?? const Stream<Map<String, dynamic>>.empty(),
      friendOfflineStream:
          friendOfflineStream ?? const Stream<Map<String, dynamic>>.empty(),
      loadMessagesOnInit: false,
    );
  }

  group('direct chat presence refresh behavior', () {
    test('a bool status response updates the peer presence', () async {
      final notifier = createNotifier(
        loadUserStatus: (_) async =>
            ApiResponse(success: true, data: {'is_online': true}),
      );
      addTearDown(notifier.dispose);

      notifier.init(1, otherUserId: 2);
      await notifier.refreshOtherUserStatus(2);

      expect(notifier.state.otherUserIsOnline, isTrue);
    });

    test('errors, non-map data, and non-bool values preserve known presence',
        () async {
      final responses = <Future<ApiResponse> Function()>[
        () async => ApiResponse(success: true, data: {'is_online': true}),
        () async => throw StateError('status unavailable'),
        () async => ApiResponse(success: true, data: const ['not-a-map']),
        () async => ApiResponse(success: true, data: {'is_online': 'true'}),
      ];
      var request = 0;
      final notifier = createNotifier(
        loadUserStatus: (_) => responses[request++](),
      );
      addTearDown(notifier.dispose);

      notifier.init(1, otherUserId: 2);
      await notifier.refreshOtherUserStatus(2);
      expect(notifier.state.otherUserIsOnline, isTrue);

      await notifier.refreshOtherUserStatus(2);
      expect(notifier.state.otherUserIsOnline, isTrue);

      await notifier.refreshOtherUserStatus(2);
      expect(notifier.state.otherUserIsOnline, isTrue);

      await notifier.refreshOtherUserStatus(2);
      expect(notifier.state.otherUserIsOnline, isTrue);
    });

    test('init, reconnect, and offline events coalesce one pending request',
        () async {
      final connection = trackedController<bool>();
      final online = trackedController<Map<String, dynamic>>();
      final offline = trackedController<Map<String, dynamic>>();
      final requests = <Completer<ApiResponse>>[];
      final notifier = createNotifier(
        connectionStream: connection.stream,
        friendOnlineStream: online.stream,
        friendOfflineStream: offline.stream,
        loadUserStatus: (_) {
          final request = Completer<ApiResponse>();
          requests.add(request);
          return request.future;
        },
      );
      addTearDown(() async {
        notifier.dispose();
        await connection.close();
        await online.close();
        await offline.close();
      });

      notifier.init(1, otherUserId: 2);
      final first = notifier.refreshOtherUserStatus(2);
      final repeated = notifier.refreshOtherUserStatus(2);
      notifier.init(1, otherUserId: 2);
      connection.add(true);
      offline.add({'user_id': 2});
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(1));
      requests.single.complete(
        ApiResponse(success: true, data: {'is_online': true}),
      );
      await Future.wait([first, repeated]);
      expect(notifier.state.otherUserIsOnline, isTrue);

      offline.add({'user_id': 2});
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(2));
      requests.last.complete(
        ApiResponse(success: true, data: {'is_online': false}),
      );
      await notifier.refreshOtherUserStatus(2);
      expect(notifier.state.otherUserIsOnline, isFalse);
    });

    test('an older user response cannot overwrite the current user status',
        () async {
      final requests = <int, Completer<ApiResponse>>{};
      final notifier = createNotifier(
        loadUserStatus: (userId) {
          return (requests[userId] ??= Completer<ApiResponse>()).future;
        },
      );
      addTearDown(notifier.dispose);

      notifier.init(1, otherUserId: 2);
      final oldUserRefresh = notifier.refreshOtherUserStatus(2);
      notifier.init(1, otherUserId: 3);
      final currentUserRefresh = notifier.refreshOtherUserStatus(3);

      requests[3]!.complete(
        ApiResponse(success: true, data: {'is_online': false}),
      );
      await currentUserRefresh;
      expect(notifier.state.otherUserIsOnline, isFalse);

      requests[2]!.complete(
        ApiResponse(success: true, data: {'is_online': true}),
      );
      await oldUserRefresh;
      expect(notifier.state.otherUserIsOnline, isFalse);
    });
  });

  group('direct chat presence subscription lifecycle', () {
    test('repeated init replaces peer subscriptions without duplicates',
        () async {
      final connection = trackedController<bool>();
      final online = trackedController<Map<String, dynamic>>();
      final offline = trackedController<Map<String, dynamic>>();
      final notifier = createNotifier(
        connectionStream: connection.stream,
        friendOnlineStream: online.stream,
        friendOfflineStream: offline.stream,
        loadUserStatus: (_) async =>
            ApiResponse(success: false, data: const <String, dynamic>{}),
      );
      addTearDown(() async {
        notifier.dispose();
        await connection.close();
        await online.close();
        await offline.close();
      });

      notifier.init(1, otherUserId: 2);
      notifier.init(1, otherUserId: 3);
      online.add({'user_id': 2});
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.otherUserIsOnline, isNull);

      online.add({'user_id': 3});
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.otherUserIsOnline, isTrue);
      expect(connection.hasListener, isTrue);
      expect(online.hasListener, isTrue);
      expect(offline.hasListener, isTrue);
    });

    test('dispose cancels connection, online, and offline subscriptions',
        () async {
      final connection = trackedController<bool>();
      final online = trackedController<Map<String, dynamic>>();
      final offline = trackedController<Map<String, dynamic>>();
      final pendingStatus = Completer<ApiResponse>();
      final notifier = createNotifier(
        connectionStream: connection.stream,
        friendOnlineStream: online.stream,
        friendOfflineStream: offline.stream,
        loadUserStatus: (_) => pendingStatus.future,
      );

      notifier.init(1, otherUserId: 2);
      expect(connection.hasListener, isTrue);
      expect(online.hasListener, isTrue);
      expect(offline.hasListener, isTrue);

      notifier.dispose();
      expect(connection.hasListener, isFalse);
      expect(online.hasListener, isFalse);
      expect(offline.hasListener, isFalse);

      pendingStatus.complete(
        ApiResponse(success: true, data: {'is_online': true}),
      );
      await Future<void>.delayed(Duration.zero);
      await connection.close();
      await online.close();
      await offline.close();
    });
  });

  group('direct chat presence UI regressions', () {
    test('chat room distinguishes online offline and unknown status text', () {
      final source = read('lib/screens/chat/chat_room_screen.dart');
      final statusStart = source.indexOf('final isOnline =');
      final statusEnd = source.indexOf('final statusColor =', statusStart);
      expect(statusStart, greaterThanOrEqualTo(0));
      expect(statusEnd, greaterThan(statusStart));
      final statusSource = source.substring(statusStart, statusEnd);

      expect(statusSource, contains('isOnline == true'));
      expect(statusSource, contains('isOnline == false'));
      expect(statusSource,
          contains('msgState.otherUserIsOnline ?? otherUser?.isOnline'));
      expect(statusSource, contains("'@\${otherUser?.username ?? ''}'"));
      expect(statusSource, isNot(contains('?? false')));
    });
  });
}
