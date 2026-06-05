import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/services/api/comment_service.dart';
import '../../helpers/test_helpers.dart';

void main() {
  late CommentService commentService;

  setUp(() {
    commentService = CommentService();
  });

  tearDown(() {
    tearDownMockDio();
  });

  group('comment_service - createComment', () {
    test('addComment 请求体正确', () async {
      mockSuccess({'id': 300, 'content': 'Nice', 'user_id': 1, 'post_id': 100});
      final resp = await commentService.createComment(100, 'Nice');
      expectSuccess(resp);
    });

    test('replyComment parent_id 传参', () async {
      mockSuccess({
        'id': 301, 'content': 'Reply', 'user_id': 2, 'post_id': 100,
        'parent_id': 200,
      });
      final resp = await commentService.createComment(100, 'Reply', parentId: 200);
      expectSuccess(resp);
    });

    test('createComment 失败返回错误消息', () async {
      mockHttpError(400, 'Content required');
      final resp = await commentService.createComment(100, '');
      expectFailure(resp);
    });
  });

  group('comment_service - getComments', () {
    test('getComments 分页', () async {
      mockSuccess({'items': [], 'page': 1});
      final resp = await commentService.getComments(100, page: 2, perPage: 10);
      expectSuccess(resp);
    });
  });

  group('comment_service - toggleCommentLike', () {
    test('likeComment 调用正确', () async {
      mockSuccess({'is_liked': true, 'like_count': 1});
      final resp = await commentService.likeComment(300);
      expectSuccess(resp);
    });

    test('unlikeComment 调用正确', () async {
      mockSuccess({'is_liked': false, 'like_count': 0});
      final resp = await commentService.unlikeComment(300);
      expectSuccess(resp);
    });
  });

  group('comment_service - other', () {
    test('getComment 正确调用', () async {
      mockSuccess({'id': 300, 'content': 'c', 'user_id': 1, 'post_id': 100});
      final resp = await commentService.getComment(300);
      expectSuccess(resp);
    });

    test('updateComment 正确调用', () async {
      mockSuccess({'id': 300, 'content': 'updated'});
      final resp = await commentService.updateComment(300, 'updated');
      expectSuccess(resp);
    });

    test('deleteComment 正确调用', () async {
      mockSuccess({'message': 'deleted'});
      final resp = await commentService.deleteComment(300);
      expectSuccess(resp);
    });

    test('getReplies 正确调用', () async {
      mockSuccess({'items': []});
      final resp = await commentService.getReplies(100, parentId: 200);
      expectSuccess(resp);
    });
  });
}
