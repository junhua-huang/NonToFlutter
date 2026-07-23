import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/services/chat_send_queue.dart';
import 'package:nonto/services/websocket_service.dart';

const rejected = ChatSendFailure(
  clientMsgId: 'c1',
  code: 'CONTENT_REJECTED',
  message: '内容未通过审核',
  retryable: false,
);
const unavailable = ChatSendFailure(
  clientMsgId: 'c1',
  code: 'MODERATION_UNAVAILABLE',
  message: '内容审核服务暂不可用，请稍后重试',
  retryable: true,
);

void main() {
  test('failed ACK settles only matching id and drains next message', () async {
    final harness = _ChatQueueHarness(twoMessages: true);

    await harness.start();
    expect(harness.queue.handleSendFailure(rejected), isTrue);
    await harness.pump();

    expect(harness.queue.handleProtocolAck('c1', 999), isTrue);
    expect(harness.first.status, 'failed');
    expect(harness.first.failureCode, 'CONTENT_REJECTED');
    expect(harness.first.canRetry, isFalse);
    expect(harness.failures.single.$1, harness.first.id);
    expect(harness.failures.single.$2.code, 'CONTENT_REJECTED');
    expect(harness.failures.single.$2.retryable, isFalse);
    expect(harness.second.status, 'sending');
    expect(harness.second.clientMsgId, 'c2');
    expect(harness.sendCalls, 2);
  });

  test('moderation unavailable permits manual retry but never automatic resend',
      () async {
    final harness = _ChatQueueHarness();

    await harness.start();
    expect(harness.queue.handleSendFailure(unavailable), isTrue);
    await harness.elapseNetworkTimers();

    expect(harness.sendCalls, 1);
    expect(harness.first.status, 'failed');
    expect(harness.first.canRetry, isTrue);
    expect(harness.first.failureMessage, '内容审核服务暂不可用，请稍后重试');
    expect(harness.failures.single.$2.retryable, isTrue);
    expect(harness.failures.single.$2.code, 'MODERATION_UNAVAILABLE');
  });

  test('failed ACK arriving before client id assignment is buffered', () async {
    final harness = _ChatQueueHarness(delaySendResult: true);

    await harness.start(pumpAfterEnqueue: false);
    expect(
      harness.queue.handleSendFailure(const ChatSendFailure(
        clientMsgId: 'early',
        code: 'CONTENT_REJECTED',
        message: '内容未通过审核',
        retryable: false,
      )),
      isTrue,
    );
    harness.completeSendResult('early');
    await harness.pump();

    expect(harness.first.status, 'failed');
    expect(harness.failures.single.$2.code, 'CONTENT_REJECTED');
    expect(harness.queue.pendingCount, 0);
  });
}

class _ChatQueueHarness {
  _ChatQueueHarness({
    this.twoMessages = false,
    this.delaySendResult = false,
  })  : ws = _FakeWebSocketService(),
        first = _message(1),
        second = _message(2) {
    queue = ChatSendQueue(
      conversationId: 42,
      senderId: 7,
      ws: ws,
    );
    queue.onFailed = (optimisticMsgId, failure) {
      failures.add((optimisticMsgId, failure));
    };
    ws.sendResults.addAll(<String>['c1', 'c2']);
    if (delaySendResult) {
      ws.delayNextSend();
    }
  }

  final bool twoMessages;
  final bool delaySendResult;
  final _FakeWebSocketService ws;
  final Message first;
  final Message second;
  late final ChatSendQueue queue;
  final List<(int, ChatSendFailure)> failures = <(int, ChatSendFailure)>[];

  int get sendCalls => ws.sendCalls;

  Future<void> start({bool pumpAfterEnqueue = true}) async {
    queue.enqueue(first);
    if (twoMessages) queue.enqueue(second);
    if (pumpAfterEnqueue) await pump();
  }

  void completeSendResult(String clientMsgId) {
    ws.completeDelayedSend(clientMsgId);
  }

  Future<void> elapseNetworkTimers() async {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

Message _message(int id) => Message(
      id: 1000000000000 + id,
      conversationId: 42,
      senderId: 7,
      content: 'hello $id',
      status: 'sending',
      createdAt: DateTime(2026, 7, 21, 12, 0, id),
    );

class _FakeWebSocketService extends WebSocketService {
  _FakeWebSocketService()
      : super.forTesting(
          connectionCoordinator: WebSocketConnectionCoordinator.forTesting(
            tokenProvider: () => 'token',
            uriForToken: (_) => 'ws://test',
            clientFactory: ({required url, required callbacks}) =>
                _NoopWebSocketClient(),
            callbacks: const WebSocketClientCallbacks(),
          ),
        );

  final Queue<String> sendResults = Queue<String>();
  final _connectionController = StreamController<bool>.broadcast();
  Completer<String>? _delayedSend;
  int sendCalls = 0;

  void delayNextSend() {
    _delayedSend = Completer<String>();
  }

  void completeDelayedSend(String clientMsgId) {
    _delayedSend?.complete(clientMsgId);
    _delayedSend = null;
  }

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStream => _connectionController.stream;

  @override
  Future<String> sendMessage(
    int conversationId,
    String content, {
    String messageType = 'text',
    String? mediaUrl,
    int? relatedId,
    String? receiverId,
    int? quoteMessageId,
    String? quotePreview,
  }) {
    sendCalls++;
    final delayed = _delayedSend;
    if (delayed != null) return delayed.future;
    return Future<String>.value(sendResults.removeFirst());
  }
}

class _NoopWebSocketClient implements WebSocketClientAdapter {
  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> forceReconnect() async {}

  @override
  Future<String> send(Map<String, dynamic> payload) async => '';

  @override
  void sendRaw(Map<String, dynamic> frame) {}
}
