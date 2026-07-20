import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:reliable_websocket/reliable_websocket.dart';

class _ControllableShutdownCoordinator extends WebSocketConnectionCoordinator {
  _ControllableShutdownCoordinator()
      : super.forTesting(
          tokenProvider: () => 'token',
          uriForToken: (token) => 'ws://test?access_token=$token',
          clientFactory: ({required url, required callbacks}) =>
              _FakeWebSocketClient(callbacks),
          callbacks: const WebSocketClientCallbacks(),
          transportShutdownTimeout: const Duration(milliseconds: 10),
        );

  Completer<void>? disconnectGate;
  Object? disconnectError;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int forceReconnectCalls = 0;

  @override
  Future<void> connect() {
    connectCalls++;
    return Future<void>.value();
  }

  @override
  Future<void> forceReconnect() {
    forceReconnectCalls++;
    return Future<void>.value();
  }

  @override
  Future<void> disconnect() {
    disconnectCalls++;
    final error = disconnectError;
    if (error != null) return Future<void>.error(error);
    return disconnectGate?.future ?? Future<void>.value();
  }
}

class _FakeWebSocketClient implements WebSocketClientAdapter {
  _FakeWebSocketClient(this.callbacks);

  final WebSocketClientCallbacks callbacks;
  Completer<void>? connectGate;
  Completer<void>? disconnectGate;
  Completer<void>? forceReconnectGate;
  Object? forceReconnectError;
  Object? disconnectError;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int forceReconnectCalls = 0;

  void emit(ConnectionState state) {
    callbacks.onConnectionStateChange?.call(state);
  }

  void emitMessage(Map<String, dynamic> payload, int seq) {
    callbacks.onMessage?.call(payload, seq);
  }

  void emitAck(String clientMsgId, int messageId) {
    callbacks.onAckMessageId?.call(clientMsgId, messageId);
  }

  void emitSendError(String clientMsgId, String error) {
    callbacks.onMessageFailed?.call(clientMsgId, error);
  }

  void emitError(String message, String? clientMsgId) {
    callbacks.onError?.call(message, clientMsgId);
  }

  void emitAuthFailed(String? error) {
    callbacks.onAuthFailed?.call(error);
  }

  @override
  Future<void> connect() {
    connectCalls++;
    return connectGate?.future ?? Future<void>.value();
  }

  @override
  Future<void> disconnect() {
    disconnectCalls++;
    final error = disconnectError;
    if (error != null) return Future<void>.error(error);
    return disconnectGate?.future ?? Future<void>.value();
  }

  @override
  Future<void> forceReconnect() {
    forceReconnectCalls++;
    final error = forceReconnectError;
    if (error != null) return Future<void>.error(error);
    return forceReconnectGate?.future ?? Future<void>.value();
  }

  @override
  Future<String> send(Map<String, dynamic> payload) async => '';

  @override
  void sendRaw(Map<String, dynamic> frame) {}
}

void main() {
  late String? token;
  late List<_FakeWebSocketClient> clients;
  late List<ConnectionState> states;
  late List<Map<String, dynamic>> messages;
  late List<Map<String, Object>> acknowledgements;
  late List<Map<String, String>> sendErrors;
  late List<Map<String, String?>> errors;
  late List<String?> authFailures;
  late Completer<void>? nextConnectGate;
  late WebSocketConnectionCoordinator coordinator;

  setUp(() {
    token = 'token';
    clients = <_FakeWebSocketClient>[];
    states = <ConnectionState>[];
    messages = <Map<String, dynamic>>[];
    acknowledgements = <Map<String, Object>>[];
    sendErrors = <Map<String, String>>[];
    errors = <Map<String, String?>>[];
    authFailures = <String?>[];
    nextConnectGate = null;
    coordinator = WebSocketConnectionCoordinator.forTesting(
      tokenProvider: () => token,
      uriForToken: (value) => 'ws://test?access_token=$value',
      clientFactory: ({required url, required callbacks}) {
        final client = _FakeWebSocketClient(callbacks)
          ..connectGate = nextConnectGate;
        nextConnectGate = null;
        clients.add(client);
        return client;
      },
      callbacks: WebSocketClientCallbacks(
        onMessage: (payload, seq) => messages.add(payload),
        onAckMessageId: (clientMsgId, messageId) => acknowledgements.add(
          <String, Object>{
            'clientMsgId': clientMsgId,
            'messageId': messageId,
          },
        ),
        onMessageFailed: (clientMsgId, error) => sendErrors.add(
          <String, String>{'clientMsgId': clientMsgId, 'error': error},
        ),
        onConnectionStateChange: states.add,
        onError: (message, clientMsgId) => errors.add(
          <String, String?>{
            'message': message,
            'clientMsgId': clientMsgId,
          },
        ),
        onAuthFailed: authFailures.add,
      ),
      transportShutdownTimeout: const Duration(milliseconds: 10),
    );
  });

  group('WebSocket connection desired state', () {
    test('background invalidates an in-flight connect before it activates',
        () async {
      final gate = Completer<void>();
      nextConnectGate = gate;
      final connecting = coordinator.connect();
      await Future<void>.delayed(Duration.zero);
      expect(clients, hasLength(1));

      coordinator.setAppForeground(false);
      clients.single.emit(ConnectionState.authenticated);
      gate.complete();
      await connecting;

      expect(coordinator.isConnected, isFalse);
      expect(states, isNot(contains(ConnectionState.authenticated)));
      expect(clients.single.disconnectCalls, 1);
    });

    test('background gates connect reconnect connectivity and health paths',
        () async {
      coordinator.setAppForeground(false);

      await coordinator.connect();
      await coordinator.forceReconnect();
      await coordinator.onConnectivityChanged(true);
      await coordinator.runHealthCheck(
        online: true,
        now: DateTime(2026, 7, 18, 12),
      );

      expect(clients, isEmpty);
      expect(coordinator.isConnected, isFalse);
    });

    test('missing token gates connect and force reconnect', () async {
      token = '   ';

      await coordinator.connect();
      await coordinator.forceReconnect();

      expect(clients, isEmpty);
    });

    test('a changed token rejects old-client data during retirement', () async {
      await coordinator.connect();
      final staleClient = clients.single;
      staleClient.disconnectGate = Completer<void>();
      token = 'replacement-token';

      final reconnecting = coordinator.forceReconnect();
      await Future<void>.delayed(Duration.zero);
      staleClient.emitMessage(<String, dynamic>{'event': 'stale'}, 5);
      staleClient.emitAck('stale-client', 90);
      staleClient.emitSendError('stale-client', 'stale failure');
      staleClient.emit(ConnectionState.authenticated);

      expect(messages, isEmpty);
      expect(acknowledgements, isEmpty);
      expect(sendErrors, isEmpty);
      expect(states, isNot(contains(ConnectionState.authenticated)));

      staleClient.disconnectGate!.complete();
      await reconnecting;
      expect(clients, hasLength(2));
      expect(staleClient.disconnectCalls, 1);
      clients.last.emit(ConnectionState.authenticated);
      expect(coordinator.isConnected, isTrue);
    });

    test(
        'background-retiring client accepts inbound data but gates transport callbacks',
        () async {
      await coordinator.connect();
      final retiringClient = clients.single;
      final disconnectGate = Completer<void>();
      retiringClient.disconnectGate = disconnectGate;

      coordinator.setAppForeground(false);
      final disconnecting = coordinator.disconnect();
      await Future<void>.delayed(Duration.zero);

      retiringClient.emitMessage(<String, dynamic>{'event': 'tail'}, 7);
      retiringClient.emitAck('client-1', 91);
      retiringClient.emitSendError('client-2', 'send failed');
      retiringClient.emitError('server failed', 'client-3');
      retiringClient.emitAuthFailed('expired');
      retiringClient.emit(ConnectionState.authenticated);

      expect(messages, <Map<String, dynamic>>[
        <String, dynamic>{'event': 'tail'},
      ]);
      expect(acknowledgements, <Map<String, Object>>[
        <String, Object>{'clientMsgId': 'client-1', 'messageId': 91},
      ]);
      expect(sendErrors, <Map<String, String>>[
        <String, String>{
          'clientMsgId': 'client-2',
          'error': 'send failed',
        },
      ]);
      expect(errors, isEmpty);
      expect(authFailures, isEmpty);
      expect(states, isNot(contains(ConnectionState.authenticated)));

      disconnectGate.complete();
      await disconnecting;
      retiringClient.emitMessage(<String, dynamic>{'event': 'stale'}, 8);
      retiringClient.emitAck('stale-client', 92);
      retiringClient.emitSendError('stale-client', 'stale error');

      expect(messages, hasLength(1));
      expect(acknowledgements, hasLength(1));
      expect(sendErrors, hasLength(1));
    });

    test('token change invalidates a background-retiring client immediately',
        () async {
      await coordinator.connect();
      final retiringClient = clients.single;
      final disconnectGate = Completer<void>();
      retiringClient.disconnectGate = disconnectGate;

      coordinator.setAppForeground(false);
      final disconnecting = coordinator.disconnect();
      await Future<void>.delayed(Duration.zero);
      token = 'replacement-token';

      retiringClient.emitMessage(<String, dynamic>{'event': 'stale'}, 8);
      retiringClient.emitAck('stale-client', 92);
      retiringClient.emitSendError('stale-client', 'stale error');

      expect(messages, isEmpty);
      expect(acknowledgements, isEmpty);
      expect(sendErrors, isEmpty);

      disconnectGate.complete();
      await disconnecting;
    });

    test('callbacks from a disconnected client cannot change global state',
        () async {
      await coordinator.connect();
      final staleClient = clients.single;

      await coordinator.disconnect();
      staleClient.emit(ConnectionState.authenticated);

      expect(coordinator.isConnected, isFalse);
      expect(states, isNot(contains(ConnectionState.authenticated)));
    });

    test('disconnect invalidates and disposes pending connection work',
        () async {
      final gate = Completer<void>();
      nextConnectGate = gate;
      final connecting = coordinator.connect();
      await Future<void>.delayed(Duration.zero);
      final pendingClient = clients.single;

      final disconnecting = coordinator.disconnect();
      await Future<void>.delayed(Duration.zero);
      expect(
        pendingClient.disconnectCalls,
        0,
        reason: 'the final disconnect must run after the pending connect',
      );
      pendingClient.emit(ConnectionState.authenticated);
      gate.complete();
      await Future.wait(<Future<void>>[connecting, disconnecting]);

      expect(coordinator.isConnected, isFalse);
      expect(pendingClient.disconnectCalls, 1);
      expect(states, isNot(contains(ConnectionState.authenticated)));
    });

    test('foreground reconnect does not coalesce onto invalidated connect work',
        () async {
      final gate = Completer<void>();
      nextConnectGate = gate;
      final staleConnect = coordinator.connect();
      await Future<void>.delayed(Duration.zero);

      coordinator.setAppForeground(false);
      coordinator.setAppForeground(true);
      final currentConnect = coordinator.forceReconnect();
      gate.complete();
      await Future.wait(<Future<void>>[staleConnect, currentConnect]);

      expect(clients, hasLength(2));
      expect(clients.first.disconnectCalls, 1);
      clients.last.emit(ConnectionState.authenticated);
      expect(coordinator.isConnected, isTrue);
    });

    test('disconnect waits for pending force reconnect then closes transport',
        () async {
      await coordinator.connect();
      final client = clients.single;
      final gate = Completer<void>();
      client.forceReconnectGate = gate;

      final reconnecting = coordinator.forceReconnect();
      await Future<void>.delayed(Duration.zero);
      final disconnecting = coordinator.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(client.disconnectCalls, 0);
      gate.complete();
      await Future.wait(<Future<void>>[reconnecting, disconnecting]);
      expect(client.disconnectCalls, 1);
      expect(coordinator.isConnected, isFalse);
    });

    test('disconnect bounds a never-completing pending connect', () async {
      final gate = Completer<void>();
      nextConnectGate = gate;
      final connecting = coordinator.connect();
      await Future<void>.delayed(Duration.zero);
      final client = clients.single;

      await expectLater(
        coordinator.disconnect().timeout(const Duration(milliseconds: 100)),
        completes,
      );

      expect(client.disconnectCalls, 1);
      expect(coordinator.isConnected, isFalse);
      client.emit(ConnectionState.authenticated);
      expect(states, isNot(contains(ConnectionState.authenticated)));

      gate.complete();
      await connecting;
      expect(coordinator.isConnected, isFalse);
      expect(client.disconnectCalls, 1);
    });

    test('disconnect bounds a never-completing transport disconnect', () async {
      await coordinator.connect();
      final client = clients.single;
      client.disconnectGate = Completer<void>();

      await expectLater(
        coordinator.disconnect().timeout(const Duration(milliseconds: 100)),
        completes,
      );

      expect(client.disconnectCalls, 1);
      expect(coordinator.isConnected, isFalse);
    });

    test('disconnect contains a throwing transport disconnect', () async {
      await coordinator.connect();
      final client = clients.single;
      client.disconnectError = StateError('disconnect failed');

      await expectLater(coordinator.disconnect(), completes);

      expect(client.disconnectCalls, 1);
      expect(coordinator.isConnected, isFalse);
    });

    test('connectivity reconnect errors are handled locally', () async {
      await coordinator.connect();
      final client = clients.single;
      client.forceReconnectError = StateError('connectivity reconnect failed');

      await expectLater(
        coordinator.onConnectivityChanged(true),
        completes,
      );

      expect(client.forceReconnectCalls, 1);
    });

    test('health reconnect errors are handled locally', () async {
      await coordinator.connect();
      final client = clients.single;
      client.emit(ConnectionState.authenticated);
      client.forceReconnectError = StateError('health reconnect failed');
      final now = DateTime(2026, 7, 18, 12);
      coordinator.markFrameReceived(now.subtract(const Duration(seconds: 91)));

      await expectLater(
        coordinator.runHealthCheck(online: true, now: now),
        completes,
      );

      expect(client.forceReconnectCalls, 1);
    });
  });

  group('WebSocketService disposal', () {
    test('dispose is bounded, idempotent, gates work, and closes all streams',
        () async {
      final shutdown = _ControllableShutdownCoordinator()
        ..disconnectGate = Completer<void>();
      final service = WebSocketService.forTesting(
        connectionCoordinator: shutdown,
        shutdownTimeout: const Duration(milliseconds: 10),
      );
      final streams = <Stream<Object?>>[
        service.messageStream,
        service.notificationStream,
        service.typingStream,
        service.connectionStream,
        service.sessionListStream,
        service.errorStream,
        service.authExpiredStream,
        service.friendOnlineStream,
        service.friendOfflineStream,
        service.onlineFriendsStream,
        service.communityPresenceStream,
        service.ackMessageIdStream,
        service.sendErrorStream,
      ];
      final done = streams.map((stream) {
        final completed = Completer<void>();
        stream.listen(null, onDone: completed.complete);
        return completed.future;
      }).toList();

      final firstDispose = service.dispose();
      final secondDispose = service.dispose();
      await service.connect();
      await service.forceReconnect();
      service.setAppForeground(true);

      expect(identical(firstDispose, secondDispose), isTrue);
      expect(shutdown.connectCalls, 0);
      expect(shutdown.forceReconnectCalls, 0);
      expect(shutdown.isAppInForeground, isFalse);
      await expectLater(
        firstDispose.timeout(const Duration(milliseconds: 100)),
        completes,
      );
      await Future.wait(done);
      expect(shutdown.disconnectCalls, 1);
    });

    test('dispose closes all streams when disconnect throws', () async {
      final shutdown = _ControllableShutdownCoordinator()
        ..disconnectError = StateError('disconnect failed');
      final service = WebSocketService.forTesting(
        connectionCoordinator: shutdown,
        shutdownTimeout: const Duration(milliseconds: 10),
      );
      final streams = <Stream<Object?>>[
        service.messageStream,
        service.notificationStream,
        service.typingStream,
        service.connectionStream,
        service.sessionListStream,
        service.errorStream,
        service.authExpiredStream,
        service.friendOnlineStream,
        service.friendOfflineStream,
        service.onlineFriendsStream,
        service.communityPresenceStream,
        service.ackMessageIdStream,
        service.sendErrorStream,
      ];
      final done = streams.map((stream) {
        final completed = Completer<void>();
        stream.listen(null, onDone: completed.complete);
        return completed.future;
      }).toList();

      await expectLater(service.dispose(), completes);
      await Future.wait(done);
      expect(shutdown.disconnectCalls, 1);
    });
  });
}
