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
