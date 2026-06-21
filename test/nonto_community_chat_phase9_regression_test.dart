import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('community chat conversation integration regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('conversation model preserves community conversation metadata', () {
      final source = read('lib/models/conversation.dart');

      expect(source, contains('final String type;'));
      expect(source, contains('final int? communityId;'));
      expect(source, contains('final String? communityName;'));
      expect(source, contains('final String? communityAvatar;'));
      expect(source, contains("bool get isCommunity => type == 'community'"));
      expect(source, contains("type: json['type']?.toString() ?? 'single'"));
      expect(source, contains("json['community_id'] != null"));
      expect(source,
          contains("communityName: json['community_name']?.toString()"));
      expect(source,
          contains("communityAvatar: json['community_avatar']?.toString()"));
      expect(source, contains("'type': type"));
      expect(source, contains("'community_id': communityId"));
      expect(source, contains("'community_name': communityName"));
      expect(source, contains("'community_avatar': communityAvatar"));
    });

    test('conversation helpers search and preview community sessions', () {
      final source = read('lib/widgets/nonto/nonto_conversation_helpers.dart');

      expect(source, contains('conversation.communityName'));
      expect(
          source, contains("if (conversation.isCommunity && content.isEmpty)"));
      expect(source, contains("'社群群聊'"));
    });

    test('conversation tile renders community name and avatar affordance', () {
      final source = read('lib/widgets/nonto/nonto_conversation_tile.dart');

      expect(source, contains('final isCommunity = conversation.isCommunity;'));
      expect(source, contains('conversation.communityName?.trim()'));
      expect(source, contains("_buildConversationAvatar(conversation)"));
      expect(source, contains('Icons.groups_3_outlined'));
      expect(source, contains('conversation.communityAvatar'));
      expect(source,
          contains('ImageUtils.resolveUrl(conversation.communityAvatar)'));
    });

    test('messages tab opens community sessions in community chat screen', () {
      final source = read('lib/screens/messages/messages_tab.dart');

      expect(
          source,
          contains(
              "import 'package:nonto/screens/community/community_chat_screen.dart';"));
      expect(source,
          contains('if (conv.isCommunity && conv.communityId != null)'));
      expect(source, contains('CommunityChatScreen('));
      expect(source, contains('communityId: conv.communityId!'));
      expect(source, contains('communityName: conv.communityName'));
      expect(source, contains('ChatRoomScreen(conversation: conv)'));
    });

    test('conversation list updates preserve community metadata', () {
      final source = read('lib/providers/chat_notifiers.dart');

      expect(source, contains('type: conv.type'));
      expect(source, contains('communityId: conv.communityId'));
      expect(source, contains('communityName: conv.communityName'));
      expect(source, contains('communityAvatar: conv.communityAvatar'));
    });

    test(
        'local sqlite persistence avoids community metadata loss without migration',
        () {
      final source = read('lib/services/local_db_service.dart');

      expect(source,
          contains('where((conversation) => !conversation.isCommunity)'));
      expect(source, contains('persistableConversations'));
    });

    test('community chat screen aligns by auth user and shows sender profile',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains('extends ConsumerStatefulWidget'));
      expect(source, contains('ConsumerState<CommunityChatScreen>'));
      expect(source,
          contains("import 'package:nonto/providers/auth_notifier.dart';"));
      expect(source,
          contains('final currentUserId = ref.watch(authProvider).user?.id;'));
      expect(source, contains("message['sender_id'] == currentUserId"));
      expect(source, isNot(contains("message['sender_id'] == 0")));
      expect(source, contains("message['sender'] is Map"));
      expect(source, contains("sender['avatar_url']"));
      expect(source, contains("sender['display_name']"));
      expect(source, contains('CachedNetworkImage'));
      expect(source, contains('WebSocketService().messageStream.listen'));
      expect(source, contains('WebSocketService().joinConversation'));
      expect(source, contains('WebSocketService().leaveConversation'));
      expect(source, contains('_appendRealtimeMessage'));
    });
  });
}
