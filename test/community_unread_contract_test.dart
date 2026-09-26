import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('community unread synchronization', () {
    test('community chat marks the resolved conversation as read when opened',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains("package:nonto/services/api/chat_service.dart"));
      expect(source, contains('Future<void> _markConversationRead() async'));
      expect(
          source,
          contains(
              'WebSocketService().markConversationRead(_conversationId!)'));
      expect(source, contains('ChatService().markRead(_conversationId!)'));
      final compactSource = source.replaceAll(RegExp(r'\s+'), '');
      expect(
        compactSource,
        contains(
            'ref.read(conversationsProvider.notifier).clearConversationUnread(_conversationId!)'
                .replaceAll(RegExp(r'\s+'), '')),
      );
    });

    test(
        'community chat marks read immediately after joining conversation room',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');
      final loadMessages = source
          .split('Future<void> _loadMessages() async')[1]
          .split('Future<void> _loadCachedMessages() async')[0];

      final joinIndex = loadMessages
          .indexOf('WebSocketService().joinConversation(_conversationId!)');
      final setOpenIndex = loadMessages
          .indexOf('ChatRoomState.setConversation(_conversationId)');
      final markReadIndex =
          loadMessages.indexOf('await _markConversationRead()');

      expect(joinIndex, isNonNegative);
      expect(setOpenIndex, greaterThan(joinIndex));
      expect(markReadIndex, greaterThan(setOpenIndex));
    });
  });
}
