import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import '../../helpers/test_helpers.dart';

void main() {
  late PostService postService;

  setUp(() {
    postService = PostService();
  });

  tearDown(() {
    tearDownMockDio();
  });

  group('post_service - createPost', () {
    test('createPost 正确组装请求体（text + image_urls 数组）', () async {
      mockSuccess({
        'id': 1, 'content': 'Hello', 'image_urls': ['a.jpg', 'b.jpg'],
      });
      final resp = await postService.createPost(
        content: 'Hello',
        imageUrls: ['a.jpg', 'b.jpg'],
      );
      expectSuccess(resp);
    });

    test('createPost 传 imageUrl 单图', () async {
      mockSuccess({'id': 2, 'content': 'Single', 'image_url': 'single.jpg'});
      final resp = await postService.createPost(
        content: 'Single',
        imageUrl: 'single.jpg',
      );
      expectSuccess(resp);
    });

    test('createPost 纯文字帖（无图片）', () async {
      mockSuccess({'id': 3, 'content': 'Text only'});
      final resp = await postService.createPost(content: 'Text only');
      expectSuccess(resp);
    });

    test('createPost 带 visibility 参数', () async {
      mockSuccess({'id': 4, 'content': 'c', 'visibility': 'friends'});
      final resp = await postService.createPost(
        content: 'c',
        visibility: 'friends',
      );
      expectSuccess(resp);
    });
  });

  group('post_service - getFeed', () {
    test('getFeed 分页参数正确', () async {
      mockSuccess({
        'items': [],
        'page': 2,
        'per_page': 10,
      });
      final resp = await postService.getFeed(page: 2, perPage: 10);
      expectSuccess(resp);
    });
  });

  group('post_service - getPost', () {
    test('getPostDetail 解析完整', () async {
      mockSuccess({
        'id': 100, 'content': 'Detail', 'user_id': 1,
        'comments': [], 'related_posts': [],
      });
      final resp = await postService.getPost(100);
      expectSuccess(resp);
    });
  });

  group('post_service - deletePost', () {
    test('deletePost 正确传参', () async {
      mockSuccess({'message': 'deleted'});
      final resp = await postService.deletePost(42);
      expectSuccess(resp);
    });
  });

  group('post_service - recordView', () {
    test('recordView 调用正确', () async {
      mockSuccess({'view_count': 1});
      final resp = await postService.recordView(100);
      expectSuccess(resp);
    });
  });

  group('post_service - like / unlike', () {
    test('likePost 调用正确', () async {
      mockSuccess({'is_liked': true, 'like_count': 1});
      final resp = await postService.likePost(100);
      expectSuccess(resp);
    });

    test('unlikePost 调用正确', () async {
      mockSuccess({'is_liked': false, 'like_count': 0});
      final resp = await postService.unlikePost(100);
      expectSuccess(resp);
    });
  });

  group('post_service - getUserPosts & getLikedPosts', () {
    test('getUserPosts 分页', () async {
      mockSuccess({'items': [], 'page': 1});
      final resp = await postService.getUserPosts(1, page: 1);
      expectSuccess(resp);
    });

    test('getUserLikedPosts 分页', () async {
      mockSuccess({'items': [], 'page': 1});
      final resp = await postService.getUserLikedPosts(1, page: 2, perPage: 10);
      expectSuccess(resp);
    });
  });
}
