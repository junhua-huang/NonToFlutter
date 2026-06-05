import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/comment.dart';

void main() {
  group('Comment.fromJson', () {
    test('基本字段 fromJson', () {
      const json = '''
      {
        "id": 200, "content": "Great!", "user_id": 2, "post_id": 100,
        "like_count": 3, "reply_count": 1, "is_liked": false,
        "created_at": "2024-03-10T09:00:00.000Z",
        "author": {"id": 2, "username": "u2", "email": "e@e.com"}
      }
      ''';
      final c = Comment.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(c.id, 200);
      expect(c.content, 'Great!');
      expect(c.userId, 2);
      expect(c.postId, 100);
      expect(c.parentId, isNull);
      expect(c.likeCount, 3);
      expect(c.replyCount, 1);
      expect(c.isLiked, false);
      expect(c.createdAt, DateTime.utc(2024, 3, 10, 9));
      expect(c.user, isNotNull);
      expect(c.user!.id, 2);
    });

    test('嵌套回复评论解析', () {
      const json = '''
      {
        "id": 202, "content": "Root", "user_id": 1, "post_id": 100,
        "like_count": 5, "reply_count": 2, "is_liked": true,
        "author": {"id": 1, "username": "u1", "email": "e@e.com"},
        "replies": [
          {"id": 203, "content": "Reply1", "user_id": 2, "post_id": 100,
           "parent_id": 202, "reply_to_user_id": 1,
           "like_count": 0, "reply_count": 0, "is_liked": false,
           "author": {"id": 2, "username": "u2", "email": "e@e.com"}},
          {"id": 204, "content": "Reply2", "user_id": 3, "post_id": 100,
           "parent_id": 202, "reply_to_user_id": 1,
           "like_count": 0, "reply_count": 0, "is_liked": false,
           "author": {"id": 3, "username": "u3", "email": "e@e.com"}}
        ]
      }
      ''';
      final c = Comment.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(c.replies.length, 2);
      expect(c.replies[0].id, 203);
      expect(c.replies[0].parentId, 202);
      expect(c.replies[0].replyToUserId, 1);
      expect(c.replies[1].id, 204);
      expect(c.replies[1].content, 'Reply2');
    });

    test('reply_to_user 解析', () {
      const json = '''
      {
        "id": 201, "content": "Reply", "user_id": 2, "post_id": 100,
        "parent_id": 200, "reply_to_user_id": 1,
        "like_count": 0, "reply_count": 0, "is_liked": false,
        "author": {"id": 2, "username": "u2", "email": "e@e.com"},
        "reply_to_user": {"id": 1, "username": "u1", "email": "e@e.com"}
      }
      ''';
      final c = Comment.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(c.replyToUser, isNotNull);
      expect(c.replyToUser!.id, 1);
      expect(c.replyToUserId, 1);
    });

    test('is_liked 正确处理布尔值', () {
      final likedJson = {'id': 1, 'content': 'c', 'user_id': 1, 'post_id': 1, 'is_liked': true};
      final liked = Comment.fromJson(likedJson);
      expect(liked.isLiked, true);

      final notLikedJson = {'id': 2, 'content': 'c', 'user_id': 1, 'post_id': 1, 'is_liked': false};
      final notLiked = Comment.fromJson(notLikedJson);
      expect(notLiked.isLiked, false);
    });
  });

  group('Comment.toJson', () {
    test('toJson 往返一致', () {
      const originalJson = '''
      {
        "id": 300, "content": "Nice", "user_id": 1, "post_id": 100,
        "like_count": 2, "reply_count": 0, "is_liked": true
      }
      ''';
      final c = Comment.fromJson(jsonDecode(originalJson) as Map<String, dynamic>);
      final output = c.toJson();
      expect(output['id'], 300);
      expect(output['content'], 'Nice');
      expect(output['user_id'], 1);
      expect(output['post_id'], 100);
      expect(output['like_count'], 2);
      expect(output['is_liked'], true);
    });
  });

  group('Comment.copyWith', () {
    test('更新 likeCount 保留原有字段', () {
      final original = Comment(
        id: 1, content: 'c', userId: 1, postId: 1,
        likeCount: 0, isLiked: false,
      );
      final updated = original.copyWith(likeCount: 1, isLiked: true);
      expect(updated.likeCount, 1);
      expect(updated.isLiked, true);
      expect(updated.content, 'c');
      expect(updated.postId, 1);
    });
  });
}
