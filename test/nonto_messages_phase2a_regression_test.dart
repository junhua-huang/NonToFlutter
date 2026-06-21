import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_helpers.dart';

void main() {
  group('Phase 2A conversation filtering', () {
    test('matches display name, username, and last message content', () {
      final conversations = [
        _conversation(
          id: 1,
          displayName: '林小南',
          username: 'lin_nan',
          message: '今天去看展吗',
        ),
        _conversation(
          id: 2,
          displayName: 'Ocean Studio',
          username: 'ocean_daily',
          message: '新的摄影路线发你了',
        ),
        _conversation(
          id: 3,
          displayName: null,
          username: 'quiet_reader',
          message: '晚点回复',
        ),
      ];

      expect(filterNontoConversations(conversations, '小南'), [conversations[0]]);
      expect(
          filterNontoConversations(conversations, 'ocean'), [conversations[1]]);
      expect(filterNontoConversations(conversations, '摄影'), [conversations[1]]);
      expect(filterNontoConversations(conversations, 'reader'),
          [conversations[2]]);
    });

    test('empty or whitespace query returns the original conversation order',
        () {
      final conversations = [
        _conversation(id: 1, displayName: 'A', username: 'a', message: 'one'),
        _conversation(id: 2, displayName: 'B', username: 'b', message: 'two'),
      ];

      expect(filterNontoConversations(conversations, ''), conversations);
      expect(filterNontoConversations(conversations, '   '), conversations);
    });

    test('conversation preview handles recalled and empty messages', () {
      expect(
          nontoConversationPreview(_conversation(message: 'hello')), 'hello');
      expect(
        nontoConversationPreview(
            _conversation(message: 'removed', isRecalled: true)),
        '消息已撤回',
      );
      expect(nontoConversationPreview(_conversation(message: '')), '暂无消息');
    });
  });

  group('Phase 2A MessagesTab source regressions', () {
    test('messages tab uses builder rendering and local search state', () {
      final source =
          File('lib/screens/messages/messages_tab.dart').readAsStringSync();

      expect(source, contains('TextEditingController'));
      expect(source, contains('filterNontoConversations'));
      expect(source, contains('ListView.builder'));
      expect(source,
          isNot(contains('...conversations.map(_buildConversationItem)')));
    });

    test('shared conversation tile uses cached safe avatar rendering', () {
      final source = File('lib/widgets/nonto/nonto_conversation_tile.dart')
          .readAsStringSync();

      expect(source, contains('class NontoConversationTile'));
      expect(source, contains('ImageUtils.buildAvatar'));
      expect(source, isNot(contains('NetworkImage')));
    });
  });
}

Conversation _conversation({
  int id = 1,
  String? displayName = 'User',
  String username = 'user',
  String? message = 'hello',
  bool isRecalled = false,
}) {
  return Conversation(
    id: id,
    user1Id: 1,
    user2Id: 2,
    lastMessageAt: DateTime(2026, 6, 20, 12),
    otherUser: User(
      id: id,
      username: username,
      email: '$username@example.com',
      displayName: displayName,
    ),
    lastMessage: Message(
      id: id,
      conversationId: id,
      senderId: 2,
      content: message,
      isRecalled: isRecalled,
    ),
  );
}
