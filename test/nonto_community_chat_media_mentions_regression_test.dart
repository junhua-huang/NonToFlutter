import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('community chat media mentions regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('messages tab refreshes conversations after returning from chats', () {
      final source = read('lib/screens/messages/messages_tab.dart');

      expect(source, contains('Future<void> _openConversation'));
      expect(source, contains('await Navigator.push'));
      expect(source,
          contains('ref.read(conversationsProvider.notifier).loadConversations()'));
    });

    test('community service sends message type and media url', () {
      final source = read('lib/services/api/community_service.dart');

      expect(source, contains("String messageType = 'text'"));
      expect(source, contains('String? mediaUrl'));
      expect(source, contains("'message_type': messageType"));
      expect(source, contains("data['media_url'] = mediaUrl"));
      expect(source, contains("data['mention_user_ids'] = mentionUserIds"));
    });

    test('conversation notifier exposes community preview update hook', () {
      final source = read('lib/providers/chat_notifiers.dart');

      expect(source, contains('void upsertCommunityConversationPreview'));
      expect(source, contains("msgType == 'image'"));
      expect(source, contains("msgType == 'video'"));
      expect(source, contains('communityId: conv.communityId'));
      expect(source, contains('loadConversations();'));
    });

    test('community chat composer has emoji media and mention member affordances',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains("import 'package:nonto/data/emoji_data.dart';"));
      expect(source, contains("import 'package:image_picker/image_picker.dart';"));
      expect(source, contains('bool _showEmojiPicker = false;'));
      expect(source, contains('final FocusNode _msgFocusNode = FocusNode();'));
      expect(source, contains('_toggleEmojiPicker'));
      expect(source, contains('_buildEmojiPicker'));
      expect(source, contains('Icons.emoji_emotions_outlined'));
      expect(source, contains('Icons.image_outlined'));
      expect(source, contains('_showMediaPicker'));
      expect(source, contains('_showMentionMemberPicker'));
      expect(source, contains('_onTextChanged'));
    });

    test('community chat sends real image and video messages', () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains('_pickAndSendImage'));
      expect(source, contains('_pickAndSendVideo'));
      expect(source, contains('UploadService().uploadImage'));
      expect(source, contains('UploadService().uploadVideo'));
      expect(source, contains("messageType: 'image'"));
      expect(source, contains("messageType: 'video'"));
      expect(source, contains('mediaUrl: url'));
    });

    test('community chat mentions members from typed at and avatar long press',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains('final Set<int> _mentionUserIds = {};'));
      expect(source, contains('List<CommunityMember> _members = [];'));
      expect(source, contains('CommunityApiService().getMembers'));
      expect(source, contains('_insertMention(CommunityMember member)'));
      expect(source, contains('onAvatarLongPress'));
      expect(source, contains('mentionUserIds: _mentionUserIds.toList()'));
    });

    test('community chat renders image and video messages', () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains("message['message_type']?.toString()"));
      expect(source, contains("messageType == 'image'"));
      expect(source, contains("messageType == 'video'"));
      expect(source, contains('_buildImageMessage'));
      expect(source, contains('_buildVideoMessage'));
      expect(source, contains('Icons.play_circle_fill'));
    });
  });
}
