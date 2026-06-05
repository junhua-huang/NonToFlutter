import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/post.dart';

void main() {
  group('Post.fromJson', () {
    test('完整字段解析 (含 images、topics、view_count)', () {
      const json = '''
      {
        "id": 100,
        "content": "Hello Flutter!",
        "image_url": "https://example.com/img.jpg",
        "video_url": "https://example.com/vid.mp4",
        "post_type": "image",
        "user_id": 1,
        "visibility": "public",
        "is_public": true,
        "like_count": 15,
        "comment_count": 3,
        "view_count": 200,
        "is_liked": true,
        "created_at": "2024-03-10T08:00:00.000Z",
        "updated_at": "2024-03-10T09:00:00.000Z",
        "topics": [{"name": "flutter"}, {"name": "dart"}],
        "images": ["https://a.jpg", "https://b.jpg"],
        "author": {"id": 1, "username": "u", "email": "e@e.com"}
      }
      ''';
      final post = Post.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(post.id, 100);
      expect(post.content, 'Hello Flutter!');
      expect(post.imageUrl, 'https://example.com/img.jpg');
      expect(post.videoUrl, 'https://example.com/vid.mp4');
      expect(post.postType, 'image');
      expect(post.userId, 1);
      expect(post.visibility, 'public');
      expect(post.isPublic, true);
      expect(post.likeCount, 15);
      expect(post.commentCount, 3);
      expect(post.viewCount, 200);
      expect(post.isLiked, true);
      expect(post.createdAt, DateTime.utc(2024, 3, 10, 8));
      expect(post.updatedAt, DateTime.utc(2024, 3, 10, 9));
      expect(post.topics, ['flutter', 'dart']);
      expect(post.images, ['https://a.jpg', 'https://b.jpg']);
      expect(post.user, isNotNull);
      expect(post.user!.username, 'u');
    });

    test('1 张图片场景', () {
      const json = '''
      {"id": 1, "user_id": 1, "images": ["https://single.jpg"]}
      ''';
      final post = Post.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(post.images, ['https://single.jpg']);
      expect(post.hasImage, isFalse); // imageUrl is null
    });

    test('4 张图片场景', () {
      final json = {
        'id': 2, 'user_id': 1,
        'images': ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg'],
      };
      final post = Post.fromJson(json);
      expect(post.images!.length, 4);
    });

    test('9 张图片场景', () {
      final images = List.generate(9, (i) => 'img$i.jpg');
      final json = {'id': 3, 'user_id': 1, 'images': images};
      final post = Post.fromJson(json);
      expect(post.images!.length, 9);
    });

    test('空 images 数组降级', () {
      const json = '''
      {"id": 4, "user_id": 1, "images": []}
      ''';
      final post = Post.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(post.images, isEmpty);
    });

    test('images 为 null 时返回 null', () {
      const json = '{"id": 5, "user_id": 1}';
      final post = Post.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(post.images, isNull);
    });

    test('从 image_urls 字段读取图片', () {
      const json = '''
      {"id": 6, "user_id": 1, "image_urls": ["x.jpg", "y.jpg"]}
      ''';
      final post = Post.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(post.images, ['x.jpg', 'y.jpg']);
    });

    test('兼容 author 和 user 字段', () {
      const userJson = '{"id": 1, "user_id": 1, "user": {"id": 2, "username": "u2", "email": "e@e.com"}}';
      final post = Post.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      expect(post.user, isNotNull);
      expect(post.user!.id, 2);

      const authorJson = '{"id": 2, "user_id": 1, "author": {"id": 3, "username": "u3", "email": "e@e.com"}}';
      final post2 = Post.fromJson(jsonDecode(authorJson) as Map<String, dynamic>);
      expect(post2.user, isNotNull);
      expect(post2.user!.id, 3);
    });

    test('createdAt 时间解析', () {
      const json = '''
      {"id": 1, "user_id": 1, "created_at": "2024-06-15T12:30:45.000Z"}
      ''';
      final post = Post.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(post.createdAt, DateTime.utc(2024, 6, 15, 12, 30, 45));
    });

    test('createdAt 为 null 时返回 null', () {
      const json = '{"id": 1, "user_id": 1}';
      final post = Post.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(post.createdAt, isNull);
    });

    test('hasImage 和 hasVideo 和 hasMedia', () {
      final imgPost = Post(id: 1, userId: 1, imageUrl: 'img.jpg');
      expect(imgPost.hasImage, true);
      expect(imgPost.hasVideo, false);
      expect(imgPost.hasMedia, true);

      final vidPost = Post(id: 2, userId: 1, videoUrl: 'vid.mp4');
      expect(vidPost.hasImage, false);
      expect(vidPost.hasVideo, true);
      expect(vidPost.hasMedia, true);

      final textPost = Post(id: 3, userId: 1);
      expect(textPost.hasMedia, false);
    });
  });

  group('Post.toJson', () {
    test('toJson 输出包含关键字段', () {
      final post = Post(
        id: 1, content: 'Hello', userId: 1,
        likeCount: 3, commentCount: 2, viewCount: 10,
        isLiked: true, topics: ['dart'],
        images: ['a.jpg'], imageUrl: 'a.jpg',
      );
      final json = post.toJson();
      expect(json['id'], 1);
      expect(json['content'], 'Hello');
      expect(json['like_count'], 3);
      expect(json['comment_count'], 2);
      expect(json['topics'], ['dart']);
      expect(json['images'], ['a.jpg']);
      expect(json['image_urls'], ['a.jpg']);
    });
  });

  group('Post.copyWith', () {
    test('更新 content 保留其余字段', () {
      final original = Post(id: 1, userId: 1, content: 'old', likeCount: 5, isLiked: false);
      final updated = original.copyWith(content: 'new');
      expect(updated.content, 'new');
      expect(updated.likeCount, 5);
      expect(updated.isLiked, false);
    });

    test('更新 isLiked 切换状态', () {
      final original = Post(id: 1, userId: 1, isLiked: false, likeCount: 0);
      final liked = original.copyWith(isLiked: true, likeCount: 1);
      expect(liked.isLiked, true);
      expect(liked.likeCount, 1);
    });
  });
}
