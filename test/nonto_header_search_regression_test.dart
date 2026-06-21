import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('header search transition regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('shared header search animates avatar and field focus state', () {
      final source = read('lib/widgets/nonto_header_search_bar.dart');

      expect(source, contains('class NontoHeaderSearchBar'));
      expect(source, contains('AnimatedSize'));
      expect(source, contains('AnimatedOpacity'));
      expect(source, contains('FocusNode'));
      expect(source, contains('ImageUtils.buildAvatar'));
      expect(source, contains('onTapOutside'));
      expect(source, contains('showAvatar'));
    });

    test('messages search lives in the app bar and title text is removed', () {
      final source = read('lib/screens/messages/messages_tab.dart');

      expect(source, contains('NontoHeaderSearchBar('));
      expect(source, contains("hintText: '搜索会话'"));
      expect(source, isNot(contains("title: const Text('消息'")));
      expect(source, isNot(contains('Widget _buildSearchBox()')));
      expect(
          source, isNot(contains('if (index == 2) return _buildSearchBox();')));
      expect(source,
          contains('filterNontoConversations(conversations, _searchQuery)'));
      expect(source, contains('return ListView.builder('));
    });

    test('discover search lives in the header and keeps existing search flow',
        () {
      final source = read('lib/screens/search/search_tab.dart');

      expect(source, contains('NontoHeaderSearchBar('));
      expect(source, contains("hintText: '搜索'"));
      expect(source, isNot(contains("title: Text('发现'")));
      expect(source, contains('_buildRightButton()'));
      expect(source, contains('_showSuggestions'));
      expect(source, contains('onSubmitted: _doSearch'));
      expect(source, contains('return ListView.builder('));
    });
  });
}
