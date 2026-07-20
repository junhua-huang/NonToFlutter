import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWebSocketClient implements WebSocketClientAdapter {
  _FakeWebSocketClient(this.callbacks);

  final WebSocketClientCallbacks callbacks;
  Completer<void>? disconnectGate;

  void emit(String event, Map<String, dynamic> data, {int seq = 1}) {
    callbacks.onMessage?.call(
      <String, dynamic>{'event': event, 'data': data},
      seq,
    );
  }

  void emitMessage({int conversationId = 42, int senderId = 7}) {
    emit('new_message', <String, dynamic>{
      'id': 101,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': 'tail message',
      'message_type': 'text',
      'created_at': '2026-07-18T12:00:00.000Z',
    });
  }

  void emitAck(String clientMsgId, int messageId) {
    callbacks.onAckMessageId?.call(clientMsgId, messageId);
  }

  void emitSendError(String clientMsgId, String error) {
    callbacks.onMessageFailed?.call(clientMsgId, error);
  }

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() => disconnectGate?.future ?? Future<void>.value();

  @override
  Future<void> forceReconnect() async {}

  @override
  Future<String> send(Map<String, dynamic> payload) async => '';

  @override
  void sendRaw(Map<String, dynamic> frame) {}
}

class _EventFixture {
  _EventFixture({
    String? currentUserId = '1',
    bool Function(int conversationId)? isConversationOpen,
  }) {
    service = WebSocketService.forTesting(
      connectionCoordinatorFactory: (callbacks) {
        coordinator = WebSocketConnectionCoordinator.forTesting(
          tokenProvider: () => ApiClient.token,
          uriForToken: (token) => 'ws://test?access_token=$token',
          clientFactory: ({required url, required callbacks}) {
            final client = _FakeWebSocketClient(callbacks);
            clients.add(client);
            return client;
          },
          callbacks: callbacks,
          transportShutdownTimeout: const Duration(milliseconds: 100),
        );
        return coordinator;
      },
      playNotificationSound: () => notificationSounds++,
      playOnlineSound: () => onlineSounds++,
      performLightImpact: () => lightImpacts++,
      currentUserIdProvider: () => currentUserId,
      isConversationOpen: isConversationOpen ?? (_) => false,
    );
  }

  late final WebSocketService service;
  late final WebSocketConnectionCoordinator coordinator;
  final List<_FakeWebSocketClient> clients = <_FakeWebSocketClient>[];
  int notificationSounds = 0;
  int onlineSounds = 0;
  int lightImpacts = 0;

  _FakeWebSocketClient get client => clients.last;

  Future<void> connect() => coordinator.connect();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.token = 'token';
  });

  tearDown(() {
    ApiClient.token = null;
  });

  test(
      'background retiring transport emits tail events and ACK without local effects',
      () async {
    final fixture = _EventFixture();
    addTearDown(fixture.service.dispose);
    await fixture.connect();
    final retiringClient = fixture.client;
    final disconnectGate = Completer<void>();
    retiringClient.disconnectGate = disconnectGate;
    fixture.service.setAppForeground(false);
    final disconnecting = fixture.service.disconnect();
    await Future<void>.delayed(Duration.zero);
    final message = fixture.service.messageStream.first;
    final notification = fixture.service.notificationStream.first;
    final presence = fixture.service.friendOnlineStream.first;
    final ack = fixture.service.ackMessageIdStream.first;
    final sendError = fixture.service.sendErrorStream.first;

    retiringClient.emitMessage();
    retiringClient.emit('new_notification', <String, dynamic>{
      'notification': <String, dynamic>{'id': 202, 'type': 'like'},
      'unread_count': 9,
    });
    retiringClient.emit('friend_online', <String, dynamic>{'friend_id': 303});
    retiringClient.emitAck('client-1', 404);
    retiringClient.emitSendError('client-2', 'delivery failed');

    expect((await message)['event'], 'new_message');
    expect(
      await notification,
      containsPair('unread_count', 9),
      reason: 'the production callback path must retain unread_count',
    );
    expect(await presence, containsPair('friend_id', 303));
    expect(
      await ack,
      <String, dynamic>{'clientMsgId': 'client-1', 'message_id': 404},
    );
    expect(
      await sendError,
      <String, dynamic>{
        'clientMsgId': 'client-2',
        'error': 'delivery failed',
      },
    );
    expect(fixture.notificationSounds, 0);
    expect(fixture.onlineSounds, 0);
    expect(fixture.lightImpacts, 0);

    disconnectGate.complete();
    await disconnecting;
  });

  test('replaced and disposed clients cannot emit inbound callbacks', () async {
    final fixture = _EventFixture();
    await fixture.connect();
    final staleClient = fixture.client;
    final messages = <Map<String, dynamic>>[];
    final acknowledgements = <Map<String, dynamic>>[];
    final sendErrors = <Map<String, dynamic>>[];
    fixture.service.messageStream.listen(messages.add);
    fixture.service.ackMessageIdStream.listen(acknowledgements.add);
    fixture.service.sendErrorStream.listen(sendErrors.add);

    ApiClient.token = 'replacement-token';
    await fixture.coordinator.forceReconnect();
    expect(fixture.clients, hasLength(2));

    staleClient.emitMessage();
    staleClient.emitAck('stale-client', 405);
    staleClient.emitSendError('stale-client', 'stale failure');
    await Future<void>.delayed(Duration.zero);

    expect(messages, isEmpty);
    expect(acknowledgements, isEmpty);
    expect(sendErrors, isEmpty);

    final disposedClient = fixture.client;
    await fixture.service.dispose();
    disposedClient.emitMessage();
    disposedClient.emitAck('disposed-client', 406);
    disposedClient.emitSendError('disposed-client', 'disposed failure');
    await Future<void>.delayed(Duration.zero);

    expect(messages, isEmpty);
    expect(acknowledgements, isEmpty);
    expect(sendErrors, isEmpty);
  });

  test('foreground business events emit and alert exactly once', () async {
    final fixture = _EventFixture();
    addTearDown(fixture.service.dispose);
    await fixture.connect();
    final message = fixture.service.messageStream.first;
    final notification = fixture.service.notificationStream.first;
    final presence = fixture.service.friendOnlineStream.first;

    fixture.client.emitMessage();
    expect((await message)['event'], 'new_message');
    expect(fixture.notificationSounds, 1);
    expect(fixture.lightImpacts, 1);

    fixture.client.emit('new_notification', <String, dynamic>{
      'notification': <String, dynamic>{'id': 202, 'type': 'like'},
    });
    expect((await notification)['event'], 'new_notification');
    expect(fixture.notificationSounds, 2);
    expect(fixture.lightImpacts, 1);

    fixture.client.emit(
      'friend_online',
      <String, dynamic>{'friend_id': 303},
    );
    expect(await presence, containsPair('friend_id', 303));
    expect(fixture.onlineSounds, 1);
    expect(fixture.notificationSounds, 2);
    expect(fixture.lightImpacts, 1);
  });

  test('open-conversation messages still emit without message effects',
      () async {
    final fixture = _EventFixture(
      isConversationOpen: (conversationId) => conversationId == 42,
    );
    addTearDown(fixture.service.dispose);
    await fixture.connect();
    final message = fixture.service.messageStream.first;

    fixture.client.emitMessage();

    expect((await message)['event'], 'new_message');
    expect(fixture.notificationSounds, 0);
    expect(fixture.lightImpacts, 0);
  });

  test('self messages still emit without message effects', () async {
    final fixture = _EventFixture(currentUserId: '7');
    addTearDown(fixture.service.dispose);
    await fixture.connect();
    final message = fixture.service.messageStream.first;

    fixture.client.emitMessage(senderId: 7);

    expect((await message)['event'], 'new_message');
    expect(fixture.notificationSounds, 0);
    expect(fixture.lightImpacts, 0);
  });

  test('messages without an auth token still emit without message effects',
      () async {
    final fixture = _EventFixture();
    addTearDown(fixture.service.dispose);
    await fixture.connect();
    ApiClient.token = null;
    final message = fixture.service.messageStream.first;

    fixture.client.emitMessage();

    expect((await message)['event'], 'new_message');
    expect(fixture.notificationSounds, 0);
    expect(fixture.lightImpacts, 0);
  });
}
