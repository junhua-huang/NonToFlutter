import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('app shell avatar and compose polish regressions', () {
    test('shared header avatar exposes tap callback for drawer opening', () {
      final header = read('lib/widgets/nonto_header_search_bar.dart');
      final search = read('lib/screens/search/search_tab.dart');
      final messages = read('lib/screens/messages/messages_tab.dart');

      expect(header, contains('final VoidCallback? onAvatarTap;'));
      expect(header, contains('this.onAvatarTap'));
      expect(header, contains('InkWell('));
      expect(header, contains('onTap: widget.onAvatarTap'));
      expect(search, contains('onAvatarTap:'));
      expect(search, contains('Scaffold.of(context).openDrawer()'));
      expect(messages, contains('final homeScaffoldContext = context;'));
      expect(messages, contains('onAvatarTap:'));
      expect(
          messages, contains('Scaffold.of(homeScaffoldContext).openDrawer()'));
    });

    test('home feed header uses shared avatar builder for drawer avatar', () {
      final source = read('lib/screens/home/home/feed_tab.dart');

      expect(source, contains('NontoHeaderAvatar('));
      expect(
          source, contains('onTap: () => Scaffold.of(context).openDrawer()'));
    });

    test('user json preserves avatar and cover cache bust timestamps', () {
      final source = read('lib/models/user.dart');

      expect(source, contains("'avatar_cache_ts': avatarCacheTs"));
      expect(source, contains("'cover_cache_ts': coverCacheTs"));
    });

    test('compose route and fab use bottom-up transition to create post screen',
        () {
      final home = read('lib/screens/home/home_screen.dart');
      final routes = read('lib/routes/route_generator.dart');
      final transitions = read('lib/utils/app_transitions.dart');

      expect(home, contains('AppTransitions.pushBottom'));
      expect(routes, contains('CreatePostScreen'));
      expect(routes, contains('case AppRoutes.createPost:'));
      expect(
          routes,
          isNot(contains(
              'case AppRoutes.createPost:\n        return _authGuard(builder: (_) => const HomeScreen(initialTab: 0));')));
      expect(transitions, contains('Offset('));
      expect(transitions, contains('MediaQuery.of(context).size.height'));
    });

    test('create post publish button is padded and dark-mode adaptive', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('padding: const EdgeInsets.only(right: 12)'));
      expect(source,
          contains('disabledBackgroundColor: AppColors.backgroundSecondary'));
      expect(source, isNot(contains('Colors.grey[300]')));
    });

    test('bottom navigation keeps icons only without semantic labels', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('showSelectedLabels: false'));
      expect(source, contains('showUnselectedLabels: false'));
      expect(source, contains("label: ''"));
      expect(source, contains('ExcludeSemantics('));
      expect(source, isNot(contains("label: '首页'")));
      expect(source, isNot(contains("label: '发现'")));
      expect(source, isNot(contains("label: '消息'")));
      expect(source, isNot(contains("label: '我的'")));
    });
  });
}
