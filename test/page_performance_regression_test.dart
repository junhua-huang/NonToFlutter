import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('page performance regressions', () {
    test('chat service supports paginated conversations', () {
      final source = read('lib/services/api/chat_service.dart');
      expect(source, contains('getConversations({int page = 1, int perPage = 30})'));
      expect(source, contains("'/chat/sessions'"));
      expect(source, contains("'page': page"));
      expect(source, contains("'per_page': perPage"));
    });

    test('chat batch preload documents backend twenty conversation limit', () {
      final source = read('lib/services/api/chat_service.dart');
      expect(source, contains('最多 20 个会话'));
      expect(source, isNot(contains('最多 50 个会话')));
    });

    test('local db preload is bounded and does not fetch every conversation by default', () {
      final source = read('lib/services/local_db_service.dart');
      expect(source, contains('preloadRecentConversationMessages'));
      expect(source, contains('maxConversations'));
      expect(source, isNot(contains('preloadAllConversationMessages({int perPage = 50})')));
      expect(source, isNot(contains('final allConvIds = conversations.map((c) => c.id).toList();')));
    });

    test('profile tab does not duplicate initial post loading through stats loader', () {
      final source = read('lib/screens/profile/profile_tab.dart');
      expect(source, contains('_loadInitialProfileData'));
      expect(source, contains('Future.wait'));
      expect(source, contains('eagerError: false'));
      expect(source, isNot(contains('_loadLikedPosts();\n    _loadUserPosts();')));
      expect(source, isNot(contains('_loadStats();\n    // 并行触发帖子/喜欢列表加载')));
    });

    test('explore/search modules are allowed to settle independently', () {
      final exploreSource = read('lib/providers/explore_notifier.dart');
      final searchTabSource = read('lib/screens/search/search_tab.dart');
      expect(exploreSource + searchTabSource, contains('Future.wait'));
      expect(exploreSource + searchTabSource, contains('eagerError: false'));
    });

    test('comic service list GET requests use dedupe but interactive comments do not', () {
      final source = read('lib/services/comic_service.dart');
      final listSource = source.split('// ==========================================')[0];
      final commentsSource = source.split('// 漫展评论')[1];
      expect(listSource, contains('getDeduped'));
      expect(listSource, isNot(contains('ApiClient().get<')));
      expect(commentsSource, contains('ApiClient().get<Map<String, dynamic>>'));
      expect(commentsSource, isNot(contains('getDeduped<Map<String, dynamic>>')));
    });
  });
}
