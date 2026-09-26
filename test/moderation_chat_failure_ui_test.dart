import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:reliable_websocket/reliable_websocket.dart';

void main() {
  test(
      'private chat failed message UI separates terminal reason from retry action',
      () {
    final source =
        File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

    expect(source, contains("message.failureMessage?.trim()"));
    expect(source, contains("!message.canRetry"));
    expect(source, contains("label: const Text('重试'"));
    expect(source, contains("reason,"));
  });

  test('private chat retry is gated by persisted retryable metadata', () {
    final source = File('lib/providers/chat_notifiers.dart').readAsStringSync();
    final methodStart = source.indexOf('void retryFailedMessage(int msgId)');
    expect(methodStart, isNonNegative);
    final methodEnd = source.indexOf('/// 重试上传失败的图片消息', methodStart);
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);

    expect(method, contains("failed.status != 'failed' || !failed.canRetry"));
  });

  test('private WebSocket failures expose only safe moderation copy', () {
    final rejected = ChatSendFailure.fromReliable(const SendFailure(
      clientMsgId: 'c1',
      status: 422,
      code: 'CONTENT_REJECTED',
      retryable: true,
      message: 'unsafe backend detail with matched rule',
    ));
    final unavailable = ChatSendFailure.fromReliable(const SendFailure(
      clientMsgId: 'c2',
      status: 503,
      code: 'MODERATION_UNAVAILABLE',
      retryable: false,
      message: 'internal provider timeout',
    ));

    expect(rejected.message, '内容未通过审核');
    expect(rejected.retryable, isFalse);
    expect(unavailable.message, '内容审核服务暂不可用，请稍后重试');
    expect(unavailable.retryable, isTrue);
  });

  test('private media upload retry respects canRetry', () {
    final source =
        File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();
    final notifier =
        File('lib/providers/chat_notifiers.dart').readAsStringSync();

    expect(source, contains('msg.canRetry'));
    expect(source, contains("message.failureMessage?.trim()"));
    expect(notifier, contains('if (msg.status != \'failed\' || !msg.canRetry'));
    expect(notifier, contains('failureMessage: apiFailureMessage('));
  });

  test(
      'community failed message UI hides retry for terminal moderation failures',
      () {
    final source = File('lib/screens/community/community_chat_screen.dart')
        .readAsStringSync();

    expect(source, contains("message['failure_message']"));
    expect(source, contains("message['retryable'] == true"));
    expect(source, contains("if (isMine && isFailed && canRetry)"));
    expect(source, contains("if (isMine && isFailed && !canRetry)"));
    expect(source, contains("status == 'sending' || status == 'failed'"));
    expect(source, contains('quoteMessageId: quoteMessageId'));
  });
}
