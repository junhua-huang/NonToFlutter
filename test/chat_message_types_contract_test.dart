import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/post_share_target_resolver.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_helpers.dart';

void main() {
  group('chat message type contracts', () {
    test('MessageType only exposes supported product types', () {
      expect(MessageType.values.map((e) => e.name),
          ['text', 'image', 'video', 'post', 'system']);
    });

    test('Message parses message type and media url compatibility fields', () {
      final fromFileUrl = Message.fromJson({
        'id': 1,
        'conversation_id': 2,
        'sender_id': 3,
        'message_type': 'image',
        'file_url': 'https://cdn.example/a.jpg',
      });
      expect(fromFileUrl.messageType, MessageType.image);
      expect(fromFileUrl.mediaUrl, 'https://cdn.example/a.jpg');

      final fromLegacyType = Message.fromJson({
        'id': 2,
        'conversation_id': 2,
        'sender_id': 3,
        'type': 'video',
        'media_url': 'https://cdn.example/v.mp4',
      });
      expect(fromLegacyType.messageType, MessageType.video);
    });

    test('unknown legacy file and comment message types fall back to text', () {
      final file = Message.fromJson({
        'id': 1,
        'conversation_id': 2,
        'sender_id': 3,
        'message_type': 'file',
      });
      final comment = Message.fromJson({
        'id': 2,
        'conversation_id': 2,
        'sender_id': 3,
        'message_type': 'comment',
      });

      expect(file.messageType, MessageType.text);
      expect(comment.messageType, MessageType.text);
    });

    test('conversation preview labels media post and system messages', () {
      Conversation convWith(Message message) => Conversation(
            id: 1,
            user1Id: 1,
            user2Id: 2,
            lastMessage: message,
          );

      expect(
          nontoConversationPreview(convWith(Message(
            id: 1,
            conversationId: 1,
            senderId: 1,
            content: 'https://cdn.example/a.jpg',
            messageType: MessageType.image,
          ))),
          '[图片]');
      expect(
          nontoConversationPreview(convWith(Message(
            id: 2,
            conversationId: 1,
            senderId: 1,
            content: 'https://cdn.example/v.mp4',
            messageType: MessageType.video,
          ))),
          '[视频]');
      expect(
          nontoConversationPreview(convWith(Message(
            id: 3,
            conversationId: 1,
            senderId: 1,
            content: '帖子摘要',
            messageType: MessageType.post,
          ))),
          '[帖子] 帖子摘要');
      expect(
          nontoConversationPreview(convWith(Message(
            id: 4,
            conversationId: 1,
            senderId: 1,
            content: '欢迎加入',
            messageType: MessageType.system,
          ))),
          '欢迎加入');
    });

    test('private chat source contains video send and post/system render hooks',
        () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();
      expect(source, contains('sendVideoMessage'));
      expect(source, contains('_buildPostCardBubble'));
      expect(source, contains('_buildSystemMessage'));
    });

    test('community chat source contains post/system render hooks', () {
      final source = File('lib/screens/community/community_chat_screen.dart')
          .readAsStringSync();
      expect(source, contains('_buildPostCard'));
      expect(source, contains('_buildSystemMessage'));
    });

    test('websocket service exposes community presence stream', () {
      final source =
          File('lib/services/websocket_service.dart').readAsStringSync();
      expect(source, contains('_communityPresenceController'));
      expect(source, contains('communityPresenceStream'));
      expect(source, contains("case 'community_member_presence':"));
      expect(source, contains('_communityPresenceController.add'));
    });

    test(
        'community chat subscribes to presence and updates member online state',
        () {
      final source = File('lib/screens/community/community_chat_screen.dart')
          .readAsStringSync();
      expect(source, contains('_presenceSub'));
      expect(source, matches(RegExp(r'communityPresenceStream\s*\.listen')));
      expect(source, contains('_applyCommunityPresence'));
      expect(source, contains("event['community_id']"));
      expect(source, contains('widget.communityId'));
      expect(source, contains('copyWith(isOnline: isOnline)'));
      expect(source, contains('_presenceSub?.cancel'));
    });

    test('community member supports copyWith for nested user updates', () {
      final source = File('lib/models/community.dart').readAsStringSync();
      expect(source, contains('CommunityMember copyWith'));
      expect(source, contains('user: user ?? this.user'));
    });

    test('send queue passes relatedId to websocket', () {
      final source =
          File('lib/services/chat_send_queue.dart').readAsStringSync();
      expect(source, contains('relatedId: msg.relatedId'));
    });

    test('local database schema stores full chat message metadata', () {
      final schema =
          File('lib/services/database/app_database.dart').readAsStringSync();
      expect(schema, contains('IntColumn get relatedId'));
      expect(schema, contains('TextColumn get clientMsgId'));
      expect(schema, contains('IntColumn get quoteMessageId'));
      expect(schema, contains('TextColumn get quotePreview'));
      expect(schema, contains('BoolColumn get isRecalled'));
      expect(schema, contains('RealColumn get uploadProgress'));
      expect(schema, contains('TextColumn get lastMessageType'));
      expect(schema, contains('TextColumn get lastMessageMediaUrl'));
      expect(schema, contains('IntColumn get lastMessageRelatedId'));
      expect(schema, contains('BoolColumn get lastMessageIsRecalled'));
    });

    test('local database persistence maps full message metadata', () {
      final source =
          File('lib/services/local_db_service.dart').readAsStringSync();
      expect(source, contains('relatedId: Value(msg.relatedId)'));
      expect(source, contains('clientMsgId: Value(msg.clientMsgId)'));
      expect(source, contains('quoteMessageId: Value(msg.quoteMessageId)'));
      expect(source, contains('quotePreview: Value(msg.quotePreview)'));
      expect(source, contains('isRecalled: Value(msg.isRecalled)'));
      expect(source, contains('uploadProgress: Value(msg.uploadProgress)'));
      expect(
          source,
          contains(
              'lastMessageType: Value(conv.lastMessage?.messageType.name ?? MessageType.text.name)'));
      expect(source,
          contains('lastMessageMediaUrl: Value(conv.lastMessage?.mediaUrl)'));
      expect(source,
          contains('lastMessageRelatedId: Value(conv.lastMessage?.relatedId)'));
      expect(
          source,
          contains(
              'lastMessageIsRecalled: Value(conv.lastMessage?.isRecalled ?? false)'));
    });

    test('post share to chat UI entry points exist', () {
      final sheet = File('lib/widgets/post_share_to_chat_sheet.dart');
      expect(sheet.existsSync(), isTrue);
      final sheetSource = sheet.readAsStringSync();
      expect(sheetSource, contains('class PostShareToChatSheet'));
      expect(sheetSource, contains("messageType: 'post'"));
      expect(sheetSource, contains('relatedId: post.id'));

      final detailSource =
          File('lib/screens/post/post_detail_screen.dart').readAsStringSync();
      expect(detailSource, contains('PostShareToChatSheet.show'));

      final cardSource = File('lib/widgets/post_card.dart').readAsStringSync();
      expect(cardSource, contains('PostShareToChatSheet.show'));
    });

    test('post share sheet parses friend API responses into share targets', () {
      final friends = parsePostShareFriends({
        'friends': [
          {'id': '42', 'username': 'alice', 'display_name': 'Alice'},
          {'id': 0, 'username': 'invalid'},
        ],
      });

      expect(friends, isA<List<User>>());
      expect(friends.map((friend) => friend.id), [42]);
      expect(friends.single.displayName, 'Alice');
    });

    test('post share sheet parses nested friends payloads', () {
      final friends = parsePostShareFriends({
        'data': {
          'users': [
            {'id': 7, 'username': 'bob'},
          ],
        },
      });

      expect(friends.map((friend) => friend.username), ['bob']);
    });

    test(
        'post share sheet keeps all communities returned by my communities API',
        () {
      final communities = parsePostShareCommunities({
        'communities': [
          {
            'id': '5',
            'name': 'Joined Group',
            'my_role': 'member',
            'my_status': 'active'
          },
          {'id': 6, 'name': 'Legacy Payload Without Membership'},
        ],
      });

      expect(communities, isA<List<Community>>());
      expect(communities.map((community) => community.name), [
        'Joined Group',
        'Legacy Payload Without Membership',
      ]);
      expect(communities.first.isMember, isTrue);
      expect(communities.last.isMember, isFalse);
    });

    test(
        'post share sheet loads friends and creates private conversation before sending',
        () {
      final sheetSource =
          File('lib/widgets/post_share_to_chat_sheet.dart').readAsStringSync();
      expect(sheetSource, contains('PostShareTargetResolver().loadTargets()'));
      expect(sheetSource,
          contains('ChatService().getOrCreateConversation(target.friend!.id)'));
      expect(sheetSource, contains("messageType: 'post'"));
      expect(sheetSource, contains('relatedId: post.id'));
      expect(sheetSource, contains('PostShareTargetType.friend'));
      expect(sheetSource, contains('PostShareTargetType.community'));
      expect(sheetSource, isNot(contains('Future.wait([')));
      expect(sheetSource,
          isNot(contains('.where((community) => community.isMember)')));
    });

    test('post share target cache keys and resolver contracts exist', () {
      expect(CacheKeys.friendList, 'friend:list');
      expect(CacheKeys.communityMyList, 'community:my:list');
      expect(PostShareTargetType.values.map((type) => type.name), [
        'friend',
        'community',
      ]);
    });

    test('post share target resolver falls back to SQLite conversations', () {
      final source =
          File('lib/services/post_share_target_resolver.dart').readAsStringSync();
      final cacheIndex = source.indexOf('CacheKeys.convFullList');
      final dbFallbackIndex =
          source.indexOf('DataLayer().loadConversationsFromDb()');

      expect(cacheIndex, greaterThanOrEqualTo(0));
      expect(dbFallbackIndex, greaterThan(cacheIndex),
          reason: 'Missing/empty convFullList cache should use SQLite history.');
      expect(source, contains('data.isNotEmpty'));
    });

    test('post share targets are mixed by conversation list order', () {
      final alice = User(id: 1, username: 'alice', email: 'a@example.com');
      final bob = User(id: 2, username: 'bob', email: 'b@example.com');
      const groupA = Community(id: 10, name: 'Group A', ownerId: 1);
      const groupB = Community(id: 20, name: 'Group B', ownerId: 1);

      final targets = [
        PostShareTarget.friend(alice, fallbackIndex: 0),
        PostShareTarget.friend(bob, fallbackIndex: 1),
        PostShareTarget.community(groupA, fallbackIndex: 2),
        PostShareTarget.community(groupB, fallbackIndex: 3),
      ];
      final conversations = [
        Conversation(
          id: 100,
          user1Id: 1,
          user2Id: 2,
          type: 'community',
          communityId: groupB.id,
          communityName: groupB.name,
        ),
        Conversation(
          id: 101,
          user1Id: 1,
          user2Id: 2,
          otherUser: bob,
        ),
      ];

      final sorted = sortPostShareTargetsByConversationOrder(
        targets: targets,
        conversations: conversations,
      );

      expect(sorted.map((target) => target.stableKey), [
        'community:20',
        'friend:2',
        'friend:1',
        'community:10',
      ]);
    });

    test('post share community list cache is registered in manifest', () {
      final source = File('lib/services/cache_manifest.dart').readAsStringSync();
      expect(source, contains('community:my:list'));
      expect(source, contains("domain: 'community'"));
      expect(source, contains('我的社群列表'));
    });
  });
}
