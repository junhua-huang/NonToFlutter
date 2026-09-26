import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('post Twitter layout and media regressions', () {
    test('post and quote headers render one-line name identity and time', () {
      final postCard = read('lib/widgets/post_card.dart');
      final quoteThread = read('lib/widgets/quote_thread_card.dart');

      expect(postCard, contains('PostAuthorMetaLine('));
      expect(quoteThread, contains('PostAuthorMetaLine('));
      expect(postCard, contains('showUsername: false'));
      expect(quoteThread, contains('showUsername: false'));
      expect(
          postCard,
          isNot(contains(
              "'@\${post.user?.username ?? ''}  ·  \${AppDateUtils.formatTimeAgo(post.createdAt)}'")));
      expect(
          quoteThread,
          isNot(contains(
              "'@\${segmentPost.user?.username ?? ''}  ·  \${AppDateUtils.formatTimeAgo(segmentPost.createdAt)}'")));
    });

    test('image gallery uses adaptive Twitter-style aspect ratios by count',
        () {
      final mediaViewer = read('lib/widgets/media_viewer.dart');
      final postCard = read('lib/widgets/post_card.dart');
      final quoteThread = read('lib/widgets/quote_thread_card.dart');

      expect(mediaViewer, contains('class AdaptivePostImageGallery'));
      expect(mediaViewer, contains('_singleImageAspectRatio'));
      expect(mediaViewer, contains('_twoImageAspectRatio'));
      expect(mediaViewer, contains('_multiImageAspectRatio'));
      expect(mediaViewer, contains('imageUrls.take(4).toList()'));
      expect(mediaViewer, contains("'+\$extraCount'"));
      expect(postCard, contains('AdaptivePostImageGallery('));
      expect(quoteThread, contains('AdaptivePostImageGallery('));
    });

    test('quote thread image viewer opens with the full quote chain context',
        () {
      final quoteThread = read('lib/widgets/quote_thread_card.dart');

      expect(quoteThread, contains('_buildQuoteMediaItems('));
      expect(quoteThread, contains('_quoteChainPosts'));
      expect(quoteThread, contains('initialPostIndex: initialPostIndex'));
      expect(
          quoteThread,
          isNot(contains(
              '[PostMediaItem(post: segmentPost, mediaUrls: images)]')));
    });

    test(
        'normal feed posts keep text media and actions inside the avatar content column',
        () {
      final postCard = read('lib/widgets/post_card.dart');

      expect(postCard, contains('_buildNormalPostContentColumn('));
      expect(postCard, contains('_buildCompactMoreButton('));
      expect(postCard, contains('const SizedBox(height: 2)'));
      expect(postCard,
          contains('padding: const EdgeInsets.fromLTRB(0, 6, 0, 10)'));
      expect(
          postCard,
          isNot(contains(
              'constraints: const BoxConstraints(minWidth: 32, minHeight: 32)')));
      expect(postCard,
          isNot(contains('padding: const EdgeInsets.fromLTRB(72, 12, 16, 0)')));
      expect(
          postCard,
          isNot(contains(
              'padding: const EdgeInsets.only(top: 10, left: 72, right: 16)')));
    });

    test(
        'post detail uses Twitter-style detail layout with shared header and media widgets',
        () {
      final detail = read('lib/screens/post/post_detail_screen.dart');

      expect(detail, contains('PostAuthorMetaLine('));
      expect(detail, contains('AdaptivePostImageGallery('));
      expect(detail, contains('_buildTwitterDetailPostCard()'));
      expect(detail, contains('_buildDetailActionBar('));
      expect(detail,
          contains('padding: const EdgeInsets.fromLTRB(16, 10, 16, 10)'));
      expect(
          detail,
          isNot(contains(
              "'@\${post.user?.username ?? ''}  ·  \${AppDateUtils.formatTimeAgo(post.createdAt)}'")));
    });
  });

  group('profile scroll and overlay regressions', () {
    test(
        'other-user profile uses compact overlay buttons and a single sliver scroll chain',
        () {
      final profile = read('lib/screens/profile/user_profile_screen.dart');

      expect(profile, contains('_buildCompactOverlayButton('));
      expect(profile, contains('width: 36'));
      expect(profile, contains('height: 36'));
      expect(profile, contains('_buildCurrentTabSlivers('));
      expect(profile, contains('_buildPostSlivers('));
      expect(profile,
          isNot(contains('height: MediaQuery.of(context).size.height - 200')));
      expect(profile, isNot(contains('TabBarView(')));
    });
  });

  group('chat room provider timing regressions', () {
    test(
        'chat room clears unread after the first frame instead of synchronously in initState',
        () {
      final chatRoom = read('lib/screens/chat/chat_room_screen.dart');
      final initStart = chatRoom.indexOf('void initState()');
      final disposeStart = chatRoom.indexOf('void dispose()', initStart);

      expect(initStart, greaterThanOrEqualTo(0));
      expect(disposeStart, greaterThan(initStart));

      final initBody = chatRoom.substring(initStart, disposeStart);
      expect(
          initBody, contains('WidgetsBinding.instance.addPostFrameCallback'));
      expect(initBody, contains('_clearConversationUnreadAfterBuild'));
      expect(chatRoom, contains('void _clearConversationUnreadAfterBuild()'));
    });
  });
}
