import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3B explore/search source regressions', () {
    late String searchTab;
    late String suggestions;

    setUpAll(() {
      searchTab = File('lib/screens/search/search_tab.dart').readAsStringSync();
      suggestions =
          File('lib/widgets/search_suggestions.dart').readAsStringSync();
    });

    test('submitted searches guard against stale async responses', () {
      expect(searchTab, contains('int _searchGeneration = 0;'));
      expect(searchTab, contains('final generation = ++_searchGeneration;'));
      expect(searchTab,
          contains('if (!mounted || generation != _searchGeneration) return;'));
      expect(searchTab,
          contains('if (mounted && generation == _searchGeneration)'));
    });

    test(
        'recommended users view all focuses search instead of firing empty search',
        () {
      expect(searchTab, contains('void _focusSearch()'));
      expect(searchTab, contains("items.add(_DefaultItem.headerWithAction("));
      expect(searchTab, contains("'推荐好友'"));
      expect(searchTab, contains("'查看全部'"));
      expect(searchTab, contains('_focusSearch,'));
      expect(searchTab, isNot(contains("_doSearch('');")));
    });

    test(
        'search suggestions use Nonto themed surface and independent request settling',
        () {
      expect(suggestions, contains('color: AppColors.background'));
      expect(suggestions, isNot(contains('color: Colors.white')));
      expect(suggestions, contains('Future.wait(futures, eagerError: false)'));
      expect(suggestions, contains('.then<dynamic>((value) => value)'));
      expect(suggestions, contains('.catchError((_) => null)'));
      expect(suggestions, contains('userResp != null && userResp.success'));
      expect(suggestions, contains('postResp != null && postResp.success'));
      expect(suggestions, contains('topicResp != null && topicResp.success'));
    });
  });
}
