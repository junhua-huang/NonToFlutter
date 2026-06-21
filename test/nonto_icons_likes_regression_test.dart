import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('Nonto custom icons and likes', () {
    test('bottom navigation SVG assets use the supplied Nonto path set', () {
      expect(
          read('assets/icons/选中首页.svg'), contains('M10.059 2.593c1.175-.784'));
      expect(read('assets/icons/未选中首页.svg'), contains('M20 9.838c0-.502'));
      expect(read('assets/icons/选中搜索.svg'), contains('M10.25 4.25c-3.314'));
      expect(read('assets/icons/未选中搜索.svg'), contains('M10.25 3.75c-3.59'));
      expect(read('assets/icons/选中消息.svg'), contains('M12.001 1.5c5.858'));
      expect(read('assets/icons/未选中消息.svg'), contains('M20.7 11.7c0-4.48'));
      expect(read('assets/icons/选中个人.svg'), contains('M17.863 13.44c1.477'));
      expect(read('assets/icons/未选中个人.svg'), contains('M5.651 19h12.698'));
    });

    test(
        'post action bar uses supplied SVG path icons and shared like animation',
        () {
      final actionBar = read('lib/widgets/nonto/nonto_post_action_bar.dart');

      expect(actionBar, contains('NontoSvgIcon'));
      expect(actionBar, contains('NontoLikeButton'));
      expect(actionBar, contains('M1.751 10c0-4.42'));
      expect(actionBar, contains('M16.697 5.5c-1.222'));
      expect(actionBar, contains('M20.884 13.19c-1.351'));
      expect(actionBar, contains('M8.75 21V3h2v18h-2z'));
      expect(actionBar, contains('AnimationController'));
    });

    test('discover and topic result posts wire PostCard like callbacks', () {
      final searchTab = read('lib/screens/search/search_tab.dart');
      final topicResults =
          read('lib/screens/search/search_results_screen.dart');

      expect(searchTab, contains('Future<void> _togglePostLike'));
      expect(searchTab, contains('onLike: () => _togglePostLike'));
      expect(topicResults, contains('Future<void> _togglePostLike'));
      expect(topicResults, contains('onLike: () => _togglePostLike'));
    });
  });
}
