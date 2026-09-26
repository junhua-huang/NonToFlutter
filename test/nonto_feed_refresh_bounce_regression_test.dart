import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('feed pull-to-refresh bounce regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('feed releases refresh header immediately and refreshes in background', () {
      final source = read('lib/screens/home/home/feed_tab.dart');
      final refreshStart = source.indexOf('Future<void> _refreshPosts()');
      final toggleStart =
          source.indexOf('Future<void> _toggleLike', refreshStart);

      expect(refreshStart, greaterThanOrEqualTo(0));
      expect(toggleStart, greaterThan(refreshStart));

      final backgroundStart =
          source.indexOf('Future<void> _refreshPostsInBackground() async', refreshStart);
      expect(backgroundStart, greaterThan(refreshStart));

      final refreshBody = source.substring(refreshStart, backgroundStart);
      expect(refreshBody, contains('unawaited(_refreshPostsInBackground())'));
      expect(refreshBody, contains('refreshCompleted(resetFooterState: true)'));
      expect(refreshBody, isNot(contains('await ref.read(feedProvider.notifier).refreshPosts();')));
      expect(refreshBody, isNot(contains('_refreshController.refreshFailed();')));
      expect(source, contains('Future<void> _refreshPostsInBackground() async'));
      expect(source, contains('await ref.read(feedProvider.notifier).refreshPosts();'));
    });

    test('feed avoids refresh re-entry, pull-up changes, and bar toggle jitter', () {
      final feedTab = read('lib/screens/home/home/feed_tab.dart');
      final notifier = read('lib/providers/feed_notifier.dart');

      expect(feedTab, contains('if (_isRefreshing) return;'));
      expect(feedTab, contains('enablePullUp: !feedState.isRefreshing && feedState.hasMore'));
      expect(feedTab, contains('if (_refreshController.isRefresh || feedState.isRefreshing)'));
      expect(notifier, contains('finally {'));
      expect(notifier, contains('_loadInProgress = false;'));
    });
  });
}
