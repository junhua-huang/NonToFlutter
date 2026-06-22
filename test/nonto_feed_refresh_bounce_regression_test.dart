import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('feed pull-to-refresh bounce regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test(
        'feed completes refresh header before refreshed posts replace the list',
        () {
      final source = read('lib/screens/home/home/feed_tab.dart');
      final refreshStart = source.indexOf('Future<void> _refreshPosts()');
      final toggleStart =
          source.indexOf('Future<void> _toggleLike', refreshStart);

      expect(refreshStart, greaterThanOrEqualTo(0));
      expect(toggleStart, greaterThan(refreshStart));

      final refreshBody = source.substring(refreshStart, toggleStart);
      expect(
          refreshBody,
          contains(
              'final refreshFuture = ref.read(feedProvider.notifier).refreshPosts();'));
      expect(refreshBody, contains('await refreshFuture'));
      expect(refreshBody, contains('_refreshController.refreshCompleted();'));
      expect(
        refreshBody,
        isNot(
            contains('await ref.read(feedProvider.notifier).refreshPosts();')),
        reason:
            'Do not wait for feed data replacement while SmartRefresher header is still expanded.',
      );

      final futureIndex = refreshBody.indexOf('final refreshFuture =');
      final completeIndex = refreshBody.indexOf(
        '_refreshController.refreshCompleted();',
        futureIndex,
      );
      final awaitIndex = refreshBody.indexOf('await refreshFuture');

      expect(futureIndex, greaterThanOrEqualTo(0));
      expect(completeIndex, greaterThan(futureIndex));
      expect(awaitIndex, greaterThan(completeIndex));
    });
  });
}
