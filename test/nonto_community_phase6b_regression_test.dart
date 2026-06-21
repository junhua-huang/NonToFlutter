import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 6B community UX source regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('community surfaces use Nonto-owned product language', () {
      final list = read('lib/screens/community/community_list_screen.dart');
      final detail = read('lib/screens/community/community_detail_screen.dart');
      final create = read('lib/screens/community/community_create_screen.dart');
      final chat = read('lib/screens/community/community_chat_screen.dart');

      expect(list, contains('Nonto 社群广场'));
      expect(detail, contains('社群动态'));
      expect(create, contains('创建一个有温度的社群'));
      expect(chat, contains('在社群里开始第一句交流'));
      expect('$list$detail$create$chat', isNot(contains('推特')));
      expect('$list$detail$create$chat', isNot(contains('Twitter')));
      expect('$list$detail$create$chat', isNot(contains('X ')));
    });

    test('community discovery and detail keep lazy rendering', () {
      final list = read('lib/screens/community/community_list_screen.dart');
      final detail = read('lib/screens/community/community_detail_screen.dart');
      final chat = read('lib/screens/community/community_chat_screen.dart');

      expect(list, contains('ListView.builder'));
      expect(list, contains('_buildDiscoveryItem'));
      expect(detail, contains('SliverList.builder'));
      expect(detail, isNot(contains('...state.posts.map')));
      expect(chat, contains('ListView.builder'));
      expect(chat, contains('reverse: true'));
    });

    test('community screens have reusable loading empty and action helpers',
        () {
      final list = read('lib/screens/community/community_list_screen.dart');
      final detail = read('lib/screens/community/community_detail_screen.dart');
      final create = read('lib/screens/community/community_create_screen.dart');
      final chat = read('lib/screens/community/community_chat_screen.dart');

      expect(list, contains('_buildHeroHeader'));
      expect(list, contains('_buildEmptyDiscoveryState'));
      expect(detail, contains('_buildCommunityHeader'));
      expect(detail, contains('_buildPostEmptyState'));
      expect(create, contains('_buildStepProgress'));
      expect(chat, contains('_buildComposer'));
      expect(chat, contains('_buildEmptyMessagesState'));
    });
  });
}
