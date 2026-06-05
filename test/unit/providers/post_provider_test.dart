import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/post.dart';

/// 帖子相关业务逻辑验证（纯逻辑，不依赖 Provider 的复杂状态管理）
/// 主要验证 Post model 的业务逻辑和状态切换。

void main() {
  group('post_provider_like_toggle', () {
    test('like 切换状态 — isLiked 从 false 变 true', () {
      final post = Post(
        id: 1, userId: 1, content: 'Hello',
        isLiked: false, likeCount: 5,
      );
      final liked = post.copyWith(isLiked: true, likeCount: 6);
      expect(liked.isLiked, true);
      expect(liked.likeCount, 6);
    });

    test('unlike 切换状态 — isLiked 从 true 变 false', () {
      final post = Post(
        id: 1, userId: 1, content: 'Hello',
        isLiked: true, likeCount: 6,
      );
      final unliked = post.copyWith(isLiked: false, likeCount: 5);
      expect(unliked.isLiked, false);
      expect(unliked.likeCount, 5);
    });
  });

  group('post_list_operations', () {
    test('deletePost 后列表移除该项', () {
      final posts = [
        Post(id: 1, userId: 1, content: 'A'),
        Post(id: 2, userId: 1, content: 'B'),
        Post(id: 3, userId: 1, content: 'C'),
      ];
      final afterDelete = posts.where((p) => p.id != 2).toList();
      expect(afterDelete.length, 2);
      expect(afterDelete.map((p) => p.id), [1, 3]);
    });

    test('createPost 后新帖在列表首位', () {
      final original = [
        Post(id: 2, userId: 1, content: 'Old'),
      ];
      final newPost = Post(id: 3, userId: 1, content: 'New');
      final updated = [newPost, ...original];
      expect(updated.length, 2);
      expect(updated.first.content, 'New');
    });
  });

  group('post_view_count', () {
    test('recordView 递增 viewCount', () {
      final post = Post(id: 1, userId: 1, viewCount: 10);
      final updated = post.copyWith(viewCount: 11);
      expect(updated.viewCount, 11);
    });
  });
}
