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
      expect(source, contains('FeedTab()'));
      expect(source, contains('SearchTab()'));
      expect(source, contains('MessagesTab()'));
      expect(source, contains('ProfileTab()'));
    });

    test('bottom navigation chrome is extracted and keeps stable labels', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('Widget _buildBottomNavigationBar'));
      expect(source,
          contains('List<BottomNavigationBarItem> _buildNavigationItems'));
      expect(source, contains('BottomNavigationBarItem _buildNavItem'));
      expect(source, contains('Widget _buildNavIcon'));
      expect(source, contains("label: '首页'"));
      expect(source, contains("label: '发现'"));
      expect(source, contains("label: '消息'"));
      expect(source, contains("label: '我的'"));
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

    test('unread badge remains provider derived and capped', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('unreadNotificationsCountProvider'));
      expect(source, contains('unreadMessagesCountProvider'));
      expect(source, contains('String _formatBadgeCount(int count)'));
      expect(source, contains("count > 99 ? '99+' : '\$count'"));
      expect(source, contains('Badge('));
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
