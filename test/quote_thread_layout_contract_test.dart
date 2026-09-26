import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('quote thread layout contracts', () {
    test('feed and detail use QuoteThreadCard for quoted posts', () {
      final card = read('lib/widgets/post_card.dart');
      final detail = read('lib/screens/post/post_detail_screen.dart');

      expect(card, contains('quote_thread_card.dart'));
      expect(card, contains('QuoteThreadCard('));
      expect(card, contains('post.quotedPostId != null'));
      expect(detail, contains('quote_thread_card.dart'));
      expect(detail, contains('QuoteThreadCard('));
      expect(detail, contains('post.quotedPostId != null'));
    });

    test(
        'QuoteThreadCard renders reply-style segments with connector and actions',
        () {
      final source = read('lib/widgets/quote_thread_card.dart');

      expect(source, contains('class QuoteThreadCard'));
      expect(source, contains('_QuoteThreadSegment'));
      expect(source, contains('_QuoteConnectorLine'));
      expect(source, contains('NontoPostActionBar('));
      expect(source, contains('_buildCompactMoreButton'));
      expect(source,
          contains('onMore: () => _showPostActions(context, ref, chain[i])'));
      expect(
          source,
          contains(
              'TwitterBottomSheet.show<String>(context, options: options)'));
      expect(source, contains('CreatePostScreen(quotedPost: segmentPost)'));
      expect(source,
          contains('PostShareToChatSheet.show(context, post: segmentPost)'));
      expect(source, isNot(contains('该原帖还引用了另一条内容')));
      expect(source, contains('原帖不可见或已被隐藏'));
      expect(source, contains('_maxQuotedAncestors = 3'));
      expect(source,
          contains('while (next != null && depth < _maxQuotedAncestors)'));
      expect(source, contains('Expanded(child: _QuoteConnectorLine())'));
      expect(source, isNot(contains('suppressNestedQuote')));
    });

    test(
        'composer keeps compact QuotedPostPreview instead of full thread layout',
        () {
      final create = read('lib/screens/post/create_post_screen.dart');

      expect(create, contains('QuotedPostPreview('));
      expect(create, contains('compact: true'));
      expect(create, contains('quotedPostId: widget.quotedPost?.id'));
      expect(create, isNot(contains('QuoteThreadCard(')));
    });
  });
}
