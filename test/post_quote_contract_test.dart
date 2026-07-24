import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/services/api/post_service.dart';

void main() {
  test('Post preserves quoted post snapshot through fromJson and toJson', () {
    final post = Post.fromJson(<String, dynamic>{
      'id': 100,
      'content': '引用正文',
      'user_id': 1,
      'quoted_post_id': 55,
      'quoted_post': <String, dynamic>{
        'id': 55,
        'content': '原帖正文',
        'user_id': 2,
        'author': <String, dynamic>{'id': 2, 'username': 'origin'},
        'images': <String>['https://example.com/original.jpg'],
      },
    });

    final json = post.toJson();

    expect(json['quoted_post_id'], 55);
    expect(json['quoted_post'], isA<Map<String, dynamic>>());
    expect((json['quoted_post'] as Map<String, dynamic>)['content'], '原帖正文');
  });

  test('Post preserves quoted unavailable state', () {
    final post = Post.fromJson(<String, dynamic>{
      'id': 101,
      'content': '引用正文',
      'user_id': 1,
      'quoted_post_id': 56,
      'quoted_post': <String, dynamic>{'id': 56, 'unavailable': true},
    });

    final json = post.toJson();

    expect(json['quoted_post_id'], 56);
    expect(json['quoted_post_unavailable'], isTrue);
  });

  test('Post restores quoted unavailable state from cache json', () {
    final post = Post.fromJson(<String, dynamic>{
      'id': 101,
      'content': '引用正文',
      'user_id': 1,
      'quoted_post_id': 56,
      'quoted_post_unavailable': true,
    });

    expect(post.toJson()['quoted_post_unavailable'], isTrue);
  });

  test(
      'Post mergeJson preserves absent quote fields and clears explicit null quote',
      () {
    final post = Post.fromJson(<String, dynamic>{
      'id': 102,
      'content': '引用正文',
      'user_id': 1,
      'quoted_post_id': 57,
      'quoted_post': <String, dynamic>{'id': 57, 'content': '原帖', 'user_id': 2},
    });

    final preserved = post.mergeJson(<String, dynamic>{'content': '更新正文'});
    expect(preserved.toJson()['quoted_post_id'], 57);
    expect(preserved.toJson()['quoted_post'], isA<Map<String, dynamic>>());

    final cleared = post.mergeJson(<String, dynamic>{
      'quoted_post_id': null,
      'quoted_post': null,
    });
    expect(cleared.toJson()['quoted_post_id'], isNull);
    expect(cleared.toJson()['quoted_post'], isNull);
  });

  test(
      'PostService mutation payload includes quoted_post_id without legacy fields',
      () {
    final payload = PostService.buildMutationData(
      content: '',
      visibility: 'public',
      quotedPostId: 88,
    );

    expect(payload['quoted_post_id'], 88);
    expect(payload, isNot(contains('is_public')));
    expect(payload, isNot(contains('visible_user_ids')));
    expect(payload, isNot(contains('content_category')));
  });

  test('quote-post UI wiring is present in composer card and detail', () {
    final createSource =
        File('lib/screens/post/create_post_screen.dart').readAsStringSync();
    final cardSource = File('lib/widgets/post_card.dart').readAsStringSync();
    final detailSource =
        File('lib/screens/post/post_detail_screen.dart').readAsStringSync();
    final actionBarSource =
        File('lib/widgets/nonto/nonto_post_action_bar.dart').readAsStringSync();

    expect(createSource, contains('quotedPost'));
    expect(createSource, contains('quotedPostId: widget.quotedPost?.id'));
    expect(createSource, contains('QuotedPostPreview'));
    expect(cardSource, contains('QuotedPostPreview'));
    expect(detailSource, contains('QuotedPostPreview'));
    expect(actionBarSource, contains('onQuote'));
  });
}
