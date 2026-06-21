import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dark mode and search post card parity regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('AppColors semantic tokens are runtime adaptive', () {
      final theme = read('lib/config/app_theme.dart');
      final main = read('lib/main.dart');
      final notifier = read('lib/providers/theme_notifier.dart');

      expect(theme, contains('syncThemeMode'));
      expect(theme, contains('platformDispatcher.platformBrightness'));
      expect(theme, contains('static Color get background'));
      expect(theme, contains('static Color get textPrimary'));
      expect(theme, isNot(contains('static const Color background =')));
      expect(theme, isNot(contains('static const Color textPrimary =')));
      expect(main, contains('AppColors.syncThemeMode(themeMode)'));
      expect(notifier, contains('null => ThemeMode.system'));
    });

    test('search result posts reuse the home feed PostCard', () {
      final searchTab = read('lib/screens/search/search_tab.dart');
      final topicResults =
          read('lib/screens/search/search_results_screen.dart');

      expect(searchTab, contains('Widget _buildPostTile(Post post)'));
      expect(searchTab, contains('return PostCard('));
      expect(searchTab, contains('feedPosts: _postResults'));
      expect(searchTab, isNot(contains('class _SmallIcon')));

      expect(topicResults, contains("package:nonto/widgets/post_card.dart"));
      expect(topicResults, contains('PostCard('));
      expect(topicResults, contains('feedPosts: _posts'));
      expect(topicResults, isNot(contains('class _PostTile')));
    });

    test('high-impact normal surfaces avoid light-only hardcoded colors', () {
      final login = read('lib/screens/auth/login_screen.dart');
      final communityChat = read('lib/screens/community/community_chat_screen.dart');
      final splash = read('lib/screens/splash/splash_screen.dart');
      final mentionPicker = read('lib/widgets/mention_topic_picker.dart');
      final comicEventCard = read('lib/widgets/comic_event_card.dart');

      expect(login, contains('backgroundColor: AppColors.background'));
      expect(login, isNot(contains('backgroundColor: Colors.white')));
      expect(login, isNot(contains('Color(0xFF0F1419)')));
      expect(login, isNot(contains('Color(0xFF536471)')));
      expect(login, isNot(contains('Color(0xFFEFF3F4)')));
      expect(login, isNot(contains('Color(0xFF8899A6)')));

      expect(communityChat, contains('AppColors.surface'));
      expect(communityChat, isNot(contains('Colors.grey[200]')));
      expect(communityChat, isNot(contains('Colors.black87')));

      expect(splash, contains('foregroundColor: AppColors.background'));
      expect(splash, contains('color: AppColors.dragHandle'));

      expect(mentionPicker, isNot(contains('color: Colors.white')));
      expect(mentionPicker, contains('color: AppColors.background'));

      expect(
        comicEventCard,
        contains('_isFollowed ? AppColors.textPrimary : AppColors.background'),
      );
    });
  });
}
