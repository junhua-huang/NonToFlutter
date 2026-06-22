import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('local chat database regressions', () {
    test('raw SQL uses generated Drift table names', () {
      final source = read('lib/services/database/app_database.dart');

      expect(source, isNot(contains(' ON messages (')));
      expect(source, isNot(contains('UPDATE conversations SET')));
      expect(source, isNot(contains('FROM messages WHERE')));
      expect(source, isNot(contains('DELETE FROM messages WHERE')));
      expect(source, contains('messages_table'));
      expect(source, contains('conversations_table'));
    });
  });

  group('chat send queue regressions', () {
    test('message notifier cancels ack subscription on dispose', () {
      final source = read('lib/providers/chat_notifiers.dart');

      expect(source, contains('StreamSubscription? _wsAckSub;'));
      expect(source, contains('_wsAckSub = _ws.ackMessageIdStream.listen(_onAckMessageId);'));
      expect(source, contains('_wsAckSub?.cancel();'));
    });

    test('websocket service surfaces reliable sender failures to queue', () {
      final source = read('lib/services/websocket_service.dart');

      expect(source, contains('onMessageFailed:'));
      expect(source, contains('_sendErrorController.add'));
    });

    test('queue ack timeout does not resend with a new client message id', () {
      final source = read('lib/services/chat_send_queue.dart');
      final timerStart = source.indexOf('void _startAckTimer');
      final retryStart = source.indexOf('Future<void> _retryOrFail');
      expect(timerStart, greaterThanOrEqualTo(0));
      expect(retryStart, greaterThan(timerStart));
      final startAckTimerBody = source.substring(timerStart, retryStart);

      expect(startAckTimerBody, isNot(contains('_retryOrFail(entry)')));
      expect(
        startAckTimerBody,
        contains('ReliableSender'),
        reason: 'The queue should document that protocol retry owns retransmission.',
      );
    });

    test('websocket new message notification sound excludes own echoes', () {
      final source = read('lib/services/websocket_service.dart');

      final ownCheck = source.indexOf('final isOwn = senderId != null');
      final gate = source.indexOf('if (!isConvOpen && !isOwn && token != null && token.isNotEmpty)');
      final soundCall = source.indexOf('SoundService().playNotificationSound()', gate);

      expect(source, contains('ChatRoomState.isOpen(convIdInt)'));
      expect(source, contains("final senderId = normalized['sender_id'];"));
      expect(source, contains('final myId = LocalDbService().currentUserId;'));
      expect(ownCheck, greaterThanOrEqualTo(0));
      expect(gate, greaterThan(ownCheck));
      expect(soundCall, greaterThan(gate));
    });
  });
}
