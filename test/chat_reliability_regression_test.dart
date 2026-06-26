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

  group('chat composer and retry regressions', () {
    test(
        'private chat composer keeps send button available while messages are sending',
        () {
      final source = read('lib/screens/chat/chat_room_screen.dart');
      final inputStart = source.indexOf('Widget _buildInputBar(');
      final attachmentStart =
          source.indexOf('void _showAttachmentOptions', inputStart);
      expect(inputStart, greaterThanOrEqualTo(0));
      expect(attachmentStart, greaterThan(inputStart));
      final inputSource = source.substring(inputStart, attachmentStart);

      expect(inputSource, isNot(contains('chat-send-progress')));
      expect(inputSource, isNot(contains('CircularProgressIndicator')));
      expect(inputSource, isNot(contains('child: isSending')));
      expect(inputSource, contains('onPressed: _sendMessage'));
    });

    test('private failed outgoing messages expose a retry button on the bubble',
        () {
      final room = read('lib/screens/chat/chat_room_screen.dart');
      final notifier = read('lib/providers/chat_notifiers.dart');

      expect(room, contains('_retryFailedMessage'));
      expect(room, contains('Icons.refresh_rounded'));
      expect(room, contains("msg.status == 'failed'"));
      expect(room, contains('重试'));
      expect(notifier, contains('void retryFailedMessage(int msgId)'));
    });

    test('community chat composer keeps send button available while sending',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');
      final sendStart = source.indexOf('Future<void> _sendMessage()');
      final optimisticStart = source.indexOf(
          'Map<String, dynamic> _buildOptimisticMessage', sendStart);
      final composerStart = source.indexOf('Widget _buildComposer()');
      final emojiStart =
          source.indexOf('Widget _buildEmojiPicker()', composerStart);
      expect(sendStart, greaterThanOrEqualTo(0));
      expect(optimisticStart, greaterThan(sendStart));
      expect(composerStart, greaterThan(optimisticStart));
      expect(emojiStart, greaterThan(composerStart));
      final sendSource = source.substring(sendStart, optimisticStart);
      final composerSource = source.substring(composerStart, emojiStart);

      expect(sendSource, isNot(contains('content.isEmpty || _isSending')));
      expect(composerSource, isNot(contains('CircularProgressIndicator')));
      expect(composerSource,
          isNot(contains('onPressed: _isSending ? null : _sendMessage')));
      expect(composerSource, contains('onPressed: _sendMessage'));
    });

    test(
        'community failed outgoing messages expose a retry button on the bubble',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(
          source, contains('void _retryMessage(Map<String, dynamic> message)'));
      expect(source, contains('final bool isFailed'));
      expect(source, contains('onRetry'));
      expect(source, contains('Icons.refresh_rounded'));
      expect(source, contains('重试'));
    });
  });

  group('chat send queue regressions', () {
    test('message notifier cancels ack subscription on dispose', () {
      final source = read('lib/providers/chat_notifiers.dart');

      expect(source, contains('StreamSubscription? _wsAckSub;'));
      expect(
          source,
          contains(
              '_wsAckSub = _ws.ackMessageIdStream.listen(_onAckMessageId);'));
      expect(source, contains('_wsAckSub?.cancel();'));
    });

    test('websocket service surfaces reliable sender failures to queue', () {
      final source = read('lib/services/websocket_service.dart');

      expect(source, contains('onMessageFailed:'));
      expect(source, contains('_sendErrorController.add'));
    });

    test('generic websocket errors are not shown as send failures', () {
      final service = read('lib/services/websocket_service.dart');
      final notifier = read('lib/providers/chat_notifiers.dart');
      final room = read('lib/screens/chat/chat_room_screen.dart');

      final onErrorStart = service.indexOf('onError: (message, clientMsgId)');
      final onAuthFailedStart = service.indexOf('onAuthFailed:', onErrorStart);
      expect(onErrorStart, greaterThanOrEqualTo(0));
      expect(onAuthFailedStart, greaterThan(onErrorStart));
      final onErrorBody = service.substring(onErrorStart, onAuthFailedStart);

      expect(onErrorBody, contains('if (clientMsgId != null && clientMsgId.isNotEmpty)'));
      expect(onErrorBody, isNot(contains('_errorController.add(message)')));
      expect(notifier, isNot(contains(r"state = state.copyWith(isSending: false, error: '发送失败: $error')")));
      expect(room, isNot(contains(r"content: Text('发送失败: $error')")));
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
        reason:
            'The queue should document that protocol retry owns retransmission.',
      );
    });

    test('websocket new message notification sound excludes own echoes', () {
      final source = read('lib/services/websocket_service.dart');

      final ownCheck = source.indexOf('final isOwn = senderId != null');
      final gate = source.indexOf(
          'if (!isConvOpen && !isOwn && token != null && token.isNotEmpty)');
      final soundCall =
          source.indexOf('SoundService().playNotificationSound()', gate);

      expect(source, contains('ChatRoomState.isOpen(convIdInt)'));
      expect(source, contains("final senderId = normalized['sender_id'];"));
      expect(source, contains('final myId = LocalDbService().currentUserId;'));
      expect(ownCheck, greaterThanOrEqualTo(0));
      expect(gate, greaterThan(ownCheck));
      expect(soundCall, greaterThan(gate));
    });
  });
}
