import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/widgets/nonto/nonto_post_action_bar.dart';

String readSource(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('Nonto post action bar', () {
    test('formats compact counts consistently', () {
      expect(formatNontoCompactCount(0), '');
      expect(formatNontoCompactCount(9), '9');
      expect(formatNontoCompactCount(999), '999');
      expect(formatNontoCompactCount(1000), '1K');
      expect(formatNontoCompactCount(1200), '1.2K');
      expect(formatNontoCompactCount(10000), '1万');
      expect(formatNontoCompactCount(34500), '3.4万');
    });

    test('post feed and detail use the shared action bar', () {
      final feedCard = readSource('lib/widgets/post_card.dart');
      final detail = readSource('lib/screens/post/post_detail_screen.dart');
      expect(feedCard, contains('NontoPostActionBar'));
      expect(detail, contains('NontoPostActionBar'));
    });
  });

  group('feed service tracks', () {
    test(
        'post service exposes timeline and related-to-me feeds without recommendation cursor',
        () {
      final source = readSource('lib/services/api/post_service.dart');
      expect(source, contains('getFeed({int page = 1, int perPage = 20})'));
      expect(
          source, contains('getRelatedToMe({int page = 1, int perPage = 20})'));
      expect(source, contains("'/posts/related-to-me'"));
    });
  });

  group('cursor feed notifier', () {
    test('feed state tracks cursor and separated loading states', () {
      final source = readSource('lib/providers/feed_notifier.dart');
      expect(source, contains('final String? nextCursor;'));
      expect(source, contains('final String? feedStatus;'));
      expect(source, contains('final bool isInitialLoading;'));
      expect(source, contains('final bool isRefreshing;'));
      expect(source, contains('final bool isLoadingMore;'));
    });

    test(
        'feed notifier switches recommended and following tracks and deduplicates appended posts',
        () {
      final source = readSource('lib/providers/feed_notifier.dart');
      expect(source, contains('_mergeUniquePosts'));
      expect(source, contains("case 'recommended':"));
      expect(source, contains("case 'following':"));
      expect(source, contains('PostService().getFeed(page: requestPage)'));
      expect(
          source, contains('PostService().getRelatedToMe(page: requestPage)'));
      expect(source, contains("data['next_cursor'] as String?"));
      expect(source, contains("data['feed_status'] as String?"));
    });
  });

  group('feed tab cursor UX', () {
    test('feed tab uses initial loading and friendly exhausted copy', () {
      final source = readSource('lib/screens/home/home/feed_tab.dart');
      expect(source, contains('feedState.isInitialLoading'));
      expect(source, contains('你已经看完最近动态'));
      expect(source, contains('下面是更早一些的动态'));
    });
  });
}
