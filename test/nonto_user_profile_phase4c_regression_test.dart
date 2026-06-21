import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4C user profile source regressions', () {
    test('other-user profile uses Nonto-owned wording', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('Nonto 他人资料页'));
      expect(source, isNot(contains('Facebook 风格')));
      expect(source, isNot(contains('Twitter/X')));
      expect(source, isNot(contains('X-style')));
    });

    test('other-user profile has reusable loading and empty states', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('_buildProfileLoadingState()'));
      expect(source, contains('_buildProfileEmptyState('));
      expect(source, contains('还没有发布帖子'));
      expect(source, contains('还没有喜欢的帖子'));
    });

    test('other-user profile keeps lazy rendering and tab structure', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('CustomScrollView'));
      expect(source, contains('SliverPersistentHeader'));
      expect(source, contains('TabBarView'));
      expect(source, contains('ListView.builder'));
      expect(source, contains('_tabController.index == 1'));
      expect(source, contains('_loadLikedPosts()'));
    });

    test('other-user profile keeps relationship actions and chat behavior', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('FriendService().sendRequest'));
      expect(source, contains('FriendService().acceptRequest'));
      expect(source, contains('FriendService().deleteFriend'));
      expect(source, contains('ChatService().getOrCreateConversation'));
      expect(source, contains('ChatRoomScreen(conversation: conversation)'));
    });

    test('profile side effects avoid context reads after async gaps', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, isNot(contains('ProviderScope.containerOf(context)')));
      expect(source, contains('ref.read(conversationsProvider.notifier)'));
      expect(source, contains('read(notificationsProvider.notifier)'));
    });

    test('online indicator remains friends-only for privacy', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(
        source,
        contains('_statusLoaded && _friendStatus == _FriendStatus.friends'),
      );
      expect(source, contains('user.isOnline == true'));
    });
  });
}
