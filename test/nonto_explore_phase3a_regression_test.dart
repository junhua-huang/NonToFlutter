import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3A explore/search source regressions', () {
    late String source;

    setUpAll(() {
      source = File('lib/screens/search/search_tab.dart').readAsStringSync();
    });

    test('uses Nonto-owned discovery language instead of Twitter/X labels', () {
      expect(source, isNot(contains('Twitter/X Explore')));
      expect(source, contains('Nonto 发现'));
      expect(source, contains("title: Text('发现'"));
    });

    test('default discovery state has explicit loading and empty helpers', () {
      expect(source, contains('bool _hasExploreContent(ExploreState s)'));
      expect(source, contains('Widget _buildExploreLoadingState()'));
      expect(source, contains('Widget _buildExploreEmptyState()'));
      expect(source, contains('_buildExploreLoadingState()'));
      expect(source, contains('_buildExploreEmptyState()'));
    });

    test('special search result tab routing matches actual tab order', () {
      expect(source, contains('_tabController.index = 3; // 帖子'));
      expect(source, contains('_tabController.index = 2; // 漫展'));
      expect(source, contains('_tabController.index = 0; // 全部'));
      expect(source, isNot(contains('_tabController.index = 1; // 帖子')));
      expect(source, isNot(contains('_tabController.index = 3; // 漫展')));
    });

    test('keeps lazy rendering for discovery and result lists', () {
      expect(source, contains('return ListView.builder('));
      expect(source, contains('Widget _buildUsersList()'));
      expect(source, contains('Widget _buildPostsList()'));
      expect(source, contains('Widget _buildComicEventsList()'));
    });

    test('removes known dead search-tab source noise', () {
      expect(source, isNot(contains("package:nonto/config/app_config.dart")));
      expect(
          source,
          isNot(
              contains("package:nonto/screens/comic/comic_detail_page.dart")));
      expect(
          source,
          isNot(contains(
              "package:nonto/services/api/recommendation_service.dart")));
      expect(source, isNot(contains('Widget _buildFriendRow')));
      expect(source, isNot(contains('Widget _buildTrendingPostCard')));
      expect(source, isNot(contains('_DefaultItemType.historyItem')));
      expect(source, isNot(contains('factory _DefaultItem.history')));
    });
  });
}
