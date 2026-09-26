import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home feed uses Twitter-style recommended and following tracks', () {
    final notifier =
        File('lib/providers/feed_notifier.dart').readAsStringSync();
    final tab = File('lib/screens/home/home/feed_tab.dart').readAsStringSync();
    final service =
        File('lib/services/api/post_service.dart').readAsStringSync();
    final cacheKeys = File('lib/services/cache_keys.dart').readAsStringSync();

    expect(notifier, isNot(contains('RecommendationService')));
    expect(notifier, isNot(contains('/recommendations/feed')));
    expect(notifier, contains("this.trackKey = 'recommended'"));
    expect(notifier, contains("case 'recommended':"));
    expect(notifier, contains('PostService().getFeed(page: requestPage)'));
    expect(notifier, contains("case 'following':"));
    expect(
        notifier, contains('PostService().getRelatedToMe(page: requestPage)'));
    expect(notifier, contains('final requestTrackKey = state.trackKey;'));
    expect(notifier, contains('state.trackKey != requestTrackKey'));
    expect(notifier, contains('CacheKeys.feedTrackPosts(state.trackKey)'));
    expect(notifier, contains("if (state.trackKey != 'recommended') return;"));

    expect(service, contains("'/posts/related-to-me'"));
    expect(cacheKeys, contains('feedTrackPosts(String trackKey)'));
    expect(cacheKeys, contains(r"'feed:$trackKey:posts'"));

    expect(tab, contains('enum FeedTrackType { recommended, following }'));
    expect(tab,
        contains("FeedTrack(FeedTrackType.recommended, '推荐', 'recommended')"));
    expect(
        tab, contains("FeedTrack(FeedTrackType.following, '关注', 'following')"));
    expect(tab, contains('_TwitterFeedTabBar('));
    expect(tab, contains('AnimatedContainer('));
    expect(tab, contains('switchTrack(track.key)'));
    expect(tab, isNot(contains('ChoiceChip(')));
    expect(tab, isNot(contains('群聊A')));
    expect(tab, isNot(contains('群聊B')));
    expect(tab, isNot(contains('communityChat')));
  });
}
