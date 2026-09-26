import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  group('chat opening UX regressions', () {
    test('private chat renders the latest messages from reverse list origin',
        () {
      final source = read('lib/screens/chat/chat_room_screen.dart');

      expect(source, contains('reverse: true'));
      expect(source, contains('final item = grouped[index];'));
      expect(source, isNot(contains('grouped.length - 1 - index')));
      expect(source, contains('void _scrollToLatest'));
      expect(source, contains('_scrollController.jumpTo(0)'));
      expect(source, isNot(contains('_didInitialScrollToLatest')));
      expect(source,
          isNot(contains('_scrollToBottom(animate: false, force: true)')));
    });

    test('chat opening prefetch writes recent private and community caches',
        () {
      final service = read('lib/services/chat_prefetch_service.dart');

      expect(service, contains('class ChatPrefetchService'));
      expect(service, contains('prefetchPrivateConversation'));
      expect(service, contains('prefetchCommunityChat'));
      expect(service, contains('CacheKeys.msgRecent'));
      expect(service, contains('CacheKeys.communityChatRecent'));
      expect(service, contains('DataLayer().write'));
    });

    test('conversation entry points start prefetch without awaiting navigation',
        () {
      final messages = read('lib/screens/messages/messages_tab.dart');
      final legacy = read('lib/screens/chat/conversations_tab.dart');
      final profile = read('lib/screens/profile/user_profile_screen.dart');
      final notifications =
          read('lib/screens/notifications/notifications_tab.dart');
      final detail = read('lib/screens/community/community_detail_screen.dart');

      for (final source in [messages, legacy, profile, notifications, detail]) {
        expect(source, contains('ChatPrefetchService'));
        expect(source, contains('unawaited('));
      }
      expect(messages, contains('prefetchPrivateConversation(conv.id)'));
      expect(messages, contains('prefetchCommunityChat(conv.communityId!)'));
      expect(detail, contains('prefetchCommunityChat(community.id)'));
    });

    test(
        'empty chat loading keeps the composer outside the message loading view',
        () {
      final privateChat = read('lib/screens/chat/chat_room_screen.dart');
      final communityChat =
          read('lib/screens/community/community_chat_screen.dart');

      expect(privateChat, contains('_buildLoadingMessages()'));
      expect(communityChat, contains('_buildLoadingMessages()'));
      expect(privateChat, contains('_buildInputBar()'));
      expect(communityChat, contains('_buildComposer()'));
    });

    test('private chat only follows sends and updates when already near latest',
        () {
      final source = read('lib/screens/chat/chat_room_screen.dart');

      expect(source, contains('bool _isNearLatest()'));
      expect(source, contains('void _followLatestIfNeeded(bool shouldFollow)'));
      expect(source, contains('final shouldFollowLatest = _isNearLatest();'));
      expect(source, contains('_followLatestIfNeeded(shouldFollowLatest)'));
      expect(source, isNot(contains('_scrollToLatest(animate: false);')));
      expect(source, contains('msgCount > _lastObservedMsgCount'));
      expect(
          source, isNot(contains('latestMsgId != _lastObservedLatestMsgId')));
    });

    test('private prefetch preserves hasMore metadata for older history', () {
      final service = read('lib/services/chat_prefetch_service.dart');
      final notifier = read('lib/providers/chat_notifiers.dart');

      expect(service, contains("'has_more': hasMore"));
      expect(
          service, contains('final hasMore = _extractHasMore(response.data,'));
      expect(service, contains('ApiClient.token'));
      expect(service, contains('if (tokenAtStart != ApiClient.token) return;'));
      expect(notifier, contains('_cachedMessagePayload'));
      expect(notifier, contains('hasMoreFromWarmup'));
      expect(notifier, contains('hasMore: hasMoreFromLoad'));
    });
  });
}
