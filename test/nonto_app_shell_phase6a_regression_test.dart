import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 6A app shell source regressions', () {
    test('home shell uses Nonto-owned wording and keeps tab retention', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('Nonto 主框架页'));
      expect(source, contains('首页、发现、消息与我的'));
      expect(source, contains('IndexedStack'));
      expect(source, contains('late final List<Widget?> _tabCache'));
      expect(source, contains('Widget _buildLazyTab(int index)'));
      expect(source, contains('_tabCache[index] ??= _createTab(index)'));
      expect(
          source, contains('List.generate(_tabCache.length, _buildLazyTab)'));
      expect(source, isNot(contains('late final List<Widget> _tabs = const')));
    });

    test('bottom navigation chrome is extracted and keeps icons only', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('Widget _buildBottomNavigationBar'));
      expect(source,
          contains('List<BottomNavigationBarItem> _buildNavigationItems'));
      expect(source, contains('BottomNavigationBarItem _buildNavItem'));
      expect(source, contains('Widget _buildNavIcon'));
      expect(source, contains('showSelectedLabels: false'));
      expect(source, contains('showUnselectedLabels: false'));
      expect(source, contains("label: ''"));
      expect(source, isNot(contains("label: '首页'")));
      expect(source, isNot(contains("label: '发现'")));
      expect(source, isNot(contains("label: '消息'")));
      expect(source, isNot(contains("label: '我的'")));
    });

    test('compose action remains feed-only and opens create post screen', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(
          source,
          contains(
              'Widget? _buildComposeButton(bool barVisible, int currentIndex)'));
      expect(source, contains('if (currentIndex != 0) return null;'));
      expect(source, contains('const CreatePostScreen()'));
      expect(source, contains('FloatingActionButton'));
    });

    test('unread badges remain provider derived and capped', () {
      final homeSource = read('lib/screens/home/home_screen.dart');
      final messagesSource = read('lib/screens/messages/messages_tab.dart');

      expect(homeSource, contains('unreadMessagesCountProvider'));
      expect(homeSource, isNot(contains('unreadNotificationsCountProvider')));
      expect(homeSource, contains('String _formatBadgeCount(int count)'));
      expect(homeSource, contains("count > 99 ? '99+' : '\$count'"));
      expect(homeSource, contains('Badge('));
      expect(messagesSource, contains('unreadNotificationsCountProvider'));
      expect(messagesSource, contains('unreadNotifications > 99'));
      expect(messagesSource, contains("? '99+'"));
    });

    test('known HomeScreen analyzer noise is removed', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source,
          isNot(contains("import 'package:nonto/config/app_config.dart';")));
      expect(
          source,
          isNot(contains(
              "import 'package:nonto/providers/chat_notifiers.dart';")));
      final shellSource =
          source.substring(0, source.indexOf('Widget _buildDrawer'));
      expect(shellSource,
          isNot(contains('final authState = ref.watch(authProvider);')));
      expect(source, isNot(contains('Widget _buildBadgeIcon')));
      expect(source, isNot(contains('Widget _buildAvatar')));
    });
  });
}
