import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('chat messages do not enter the interaction notification feed', () {
    final notifier = read('lib/providers/notifications_notifier.dart');
    final notificationModel = read('lib/models/notification.dart');
    final chatRouter =
        File('D:/NanTuPy/app/routers/chat.py').readAsStringSync();
    final wsRouter = File('D:/NanTuPy/app/routers/ws.py').readAsStringSync();

    expect(notifier, contains("notificationType == 'message'"));
    expect(notificationModel, contains("case 'message':"));
    expect(notificationModel, contains("case 'community_mention':"));
    expect(notificationModel, contains("case 'community_announcement':"));
    expect(chatRouter, isNot(contains('NotificationService.notify_message')));
    expect(wsRouter, isNot(contains('NotificationService.notify_message')));
  });

  test('private chat renders latest-first data directly from reverse origin',
      () {
    final chat = read('lib/screens/chat/chat_room_screen.dart');
    final messages = read('lib/providers/chat_notifiers.dart');

    expect(chat, contains('reverse: true'));
    expect(chat, contains('final item = grouped[index];'));
    expect(chat, isNot(contains('grouped.length - 1 - index')));
    expect(messages, contains('_compareMessagesForLatestFirst'));
  });
}
