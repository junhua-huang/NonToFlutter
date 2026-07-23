import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/services/aliyun_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

AliyunPushService _bindingService({
  required bool Function() hasAuthToken,
  required Future<bool> Function(String deviceId) registerDevice,
  required Future<bool> Function(String deviceId) unregisterDevice,
  Future<String> Function()? initializeDevice,
  String? Function()? authSessionKey,
}) {
  return AliyunPushService.forTesting(
    hasAuthToken: hasAuthToken,
    authSessionKey: authSessionKey,
    deviceIdProvider: () async => 'device-1',
    registerDevice: registerDevice,
    unregisterDevice: unregisterDevice,
    initializeDevice: initializeDevice,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('Aliyun backend binding reconciliation', () {
    test('logout queues unregister after a held register', () async {
      var authenticated = true;
      final registerGate = Completer<void>();
      final operations = <String>[];
      final service = _bindingService(
        hasAuthToken: () => authenticated,
        registerDevice: (deviceId) async {
          operations.add('register:$deviceId');
          await registerGate.future;
          return true;
        },
        unregisterDevice: (deviceId) async {
          operations.add('unregister:$deviceId');
          return true;
        },
      );

      final binding = service.reconcileBackendBinding(authenticated: true);
      await _flushAsyncWork();
      authenticated = false;
      final unbinding = service.reconcileBackendBinding(authenticated: false);

      expect(operations, <String>['register:device-1']);
      registerGate.complete();
      await Future.wait(<Future<void>>[binding, unbinding]);

      expect(
        operations,
        <String>['register:device-1', 'unregister:device-1'],
      );
    });

    test('logout still attempts unregister without in-memory bound state',
        () async {
      var unregisterCalls = 0;
      final service = _bindingService(
        hasAuthToken: () => true,
        registerDevice: (deviceId) async => true,
        unregisterDevice: (deviceId) async {
          unregisterCalls++;
          return true;
        },
      );

      await service.reconcileBackendBinding(authenticated: false);

      expect(unregisterCalls, 1);
    });

    test('repeated bind requests coalesce to one backend registration',
        () async {
      final registerGate = Completer<void>();
      var registerCalls = 0;
      final service = _bindingService(
        hasAuthToken: () => true,
        registerDevice: (deviceId) async {
          registerCalls++;
          await registerGate.future;
          return true;
        },
        unregisterDevice: (deviceId) async => true,
      );

      final first = service.reconcileBackendBinding(authenticated: true);
      final second = service.reconcileBackendBinding(authenticated: true);
      final third = service.reconcileBackendBinding(authenticated: true);
      await _flushAsyncWork();

      expect(registerCalls, 1);
      registerGate.complete();
      await Future.wait(<Future<void>>[first, second, third]);
      await service.reconcileBackendBinding(authenticated: true);

      expect(registerCalls, 1);
    });

    test('a changed authenticated session gets its own registration', () async {
      var sessionKey = 'session-1';
      var registerCalls = 0;
      final service = _bindingService(
        hasAuthToken: () => true,
        authSessionKey: () => sessionKey,
        registerDevice: (deviceId) async {
          registerCalls++;
          return true;
        },
        unregisterDevice: (deviceId) async => true,
      );

      await service.reconcileBackendBinding(authenticated: true);
      sessionKey = 'session-2';
      await service.reconcileBackendBinding(authenticated: true);

      expect(registerCalls, 2);
    });

    test('init without a token records readiness but does not call backend',
        () async {
      var authenticated = false;
      final operations = <String>[];
      final service = _bindingService(
        hasAuthToken: () => authenticated,
        initializeDevice: () async => 'device-1',
        registerDevice: (deviceId) async {
          operations.add('register:$deviceId');
          return true;
        },
        unregisterDevice: (deviceId) async {
          operations.add('unregister:$deviceId');
          return true;
        },
      );

      await service.init();
      expect(operations, isEmpty);

      authenticated = true;
      await service.reconcileBackendBinding(authenticated: true);
      expect(operations, <String>['register:device-1']);
    });
  });

  group('AuthNotifier push binding lifecycle', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'access_token': 'test-token',
        'current_user_id': '7',
        'current_user_json': jsonEncode(<String, Object>{
          'id': 7,
          'username': 'cached-user',
          'email': 'cached@example.test',
        }),
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('cold cached-token restore requests backend binding exactly once',
        () async {
      var tokenActive = false;
      var registerCalls = 0;
      final pushService = _bindingService(
        hasAuthToken: () => tokenActive,
        registerDevice: (deviceId) async {
          registerCalls++;
          return true;
        },
        unregisterDevice: (deviceId) async => true,
      );
      final notifier = AuthNotifier.forTesting(
        prefs,
        pushService: pushService,
        setToken: (token, {connectWs = true}) {
          tokenActive = token != null && token.isNotEmpty;
        },
      );
      addTearDown(notifier.dispose);

      await notifier.restoredSessionReady;
      await pushService.reconcileBackendBinding(authenticated: true);

      expect(tokenActive, isTrue);
      expect(registerCalls, 1);
    });

    test(
        'logout invalidates WebSocket before unbind and clears token after attempt',
        () async {
      String? token = 'test-token';
      final unregisterGate = Completer<void>();
      final events = <String>[];
      final pushService = _bindingService(
        hasAuthToken: () => token != null,
        registerDevice: (deviceId) async => true,
        unregisterDevice: (deviceId) async {
          events.add('unregister:$token');
          await unregisterGate.future;
          return true;
        },
      );
      final notifier = AuthNotifier.forTesting(
        prefs,
        pushService: pushService,
        setAppForeground: (foreground) {
          events.add('foreground:$foreground');
        },
        disconnectWebSocket: () async {
          events.add('disconnect');
        },
        setToken: (value, {connectWs = true}) {
          token = value;
          events.add('token:${value == null ? 'cleared' : 'active'}');
        },
        clearLocalSession: () async {
          events.add('local-clear');
        },
      );
      addTearDown(notifier.dispose);
      await notifier.restoredSessionReady;
      events.clear();

      final logout = notifier.logout();
      await _flushAsyncWork();

      expect(events.first, 'foreground:false');
      expect(events, contains('unregister:test-token'));
      expect(events, isNot(contains('token:cleared')));

      unregisterGate.complete();
      await logout;

      expect(
        events.indexOf('unregister:test-token'),
        lessThan(events.indexOf('token:cleared')),
      );
      expect(token, isNull);
    });

    test('logout clears a refreshed token written during unregister', () async {
      String? token = 'test-token';
      final unregisterGate = Completer<void>();
      final events = <String>[];
      final pushService = _bindingService(
        hasAuthToken: () => token != null,
        registerDevice: (deviceId) async => true,
        unregisterDevice: (deviceId) async {
          events.add('unregister:$token');
          await unregisterGate.future;
          return true;
        },
      );
      final notifier = AuthNotifier.forTesting(
        prefs,
        pushService: pushService,
        setAppForeground: (foreground) {
          events.add('foreground:$foreground');
        },
        disconnectWebSocket: () async {
          events.add('disconnect');
        },
        setToken: (value, {connectWs = true}) {
          token = value;
          events.add('token:${value == null ? 'cleared' : 'active'}');
        },
        clearLocalSession: () async {
          events.add('local-clear');
        },
      );
      addTearDown(notifier.dispose);
      await notifier.restoredSessionReady;
      events.clear();

      final logout = notifier.logout();
      await _flushAsyncWork();
      token = 'new-token';
      await prefs.setString('access_token', 'new-token');
      await prefs.setString('current_user_id', '9');
      await prefs.setString('current_user_json', '{"id":9}');

      unregisterGate.complete();
      await logout;

      expect(events, contains('token:cleared'));
      expect(events, contains('local-clear'));
      expect(token, isNull);
      expect(prefs.containsKey('access_token'), isFalse);
      expect(prefs.containsKey('current_user_id'), isFalse);
      expect(prefs.containsKey('current_user_json'), isFalse);
    });

    test('stale session cleanup preserves a newly persisted session', () async {
      String? token = 'test-token';
      final unregisterGate = Completer<void>();
      final events = <String>[];
      final pushService = _bindingService(
        hasAuthToken: () => token != null,
        registerDevice: (deviceId) async => true,
        unregisterDevice: (deviceId) async {
          events.add('unregister:$token');
          await unregisterGate.future;
          return true;
        },
      );
      final notifier = AuthNotifier.forTesting(
        prefs,
        pushService: pushService,
        setAppForeground: (foreground) {
          events.add('foreground:$foreground');
        },
        disconnectWebSocket: () async {
          events.add('disconnect');
        },
        setToken: (value, {connectWs = true}) {
          token = value;
          events.add('token:${value == null ? 'cleared' : 'active'}');
        },
        clearLocalSession: () async {
          events.add('local-clear');
        },
      );
      addTearDown(notifier.dispose);
      await notifier.restoredSessionReady;
      events.clear();

      final staleCleanup = notifier.expireSessionForTesting();
      await _flushAsyncWork();
      await prefs.setString('access_token', 'new-token');
      await prefs.setString('current_user_id', '9');
      await prefs.setString('current_user_json', '{"id":9}');

      unregisterGate.complete();
      await staleCleanup;

      expect(events, isNot(contains('token:cleared')));
      expect(events, isNot(contains('local-clear')));
      expect(prefs.getString('access_token'), 'new-token');
      expect(prefs.getString('current_user_id'), '9');
      expect(prefs.getString('current_user_json'), '{"id":9}');
    });
  });
}
