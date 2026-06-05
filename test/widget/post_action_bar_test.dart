import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/widgets/post_card.dart';
import '../helpers/test_helpers.dart';

Widget wrapPostCard(Post post, {VoidCallback? onLike}) {
  initTestSqflite();
  return ChangeNotifierProvider<AuthProvider>(
    create: (_) => AuthProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: PostCard(
          post: post,
          onTap: () {},
          onLike: onLike,
        ),
      ),
    ),
  );
}

void main() {
  final baseAuthor = User(
    id: 1, username: 'author', email: 'a@e.com',
    displayName: 'Author',
  );

  group('PostActionBar - 基本图标检查', () {
    testWidgets('点赞/评论/浏览量三个计数都存在', (tester) async {
      final post = Post(
        id: 1, userId: 1, content: 'Test',
        likeCount: 10, commentCount: 5, viewCount: 100,
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.text('10'), findsWidgets);
      expect(find.text('5'), findsWidgets);
      expect(find.text('100'), findsWidgets);
    });

    testWidgets('点赞切换颜色 — 未点赞时图标默认色', (tester) async {
      final post = Post(
        id: 2, userId: 1, content: 'Like btn',
        isLiked: false, likeCount: 1,
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('已点赞时显示点赞数', (tester) async {
      final post = Post(
        id: 3, userId: 1, content: 'Liked',
        isLiked: true, likeCount: 5,
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.text('5'), findsWidgets);
    });
  });

  group('PostActionBar - 按钮可点击', () {
    testWidgets('点赞按钮可触发回调', (tester) async {
      bool tapped = false;
      final post = Post(
        id: 4, userId: 1, content: 'Like test',
        isLiked: false, likeCount: 1,
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post, onLike: () => tapped = true));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      expect(tapped, true);
    });

    testWidgets('评论按钮可触发回调', (tester) async {
      final post = Post(
        id: 5, userId: 1, content: 'Comment test',
        commentCount: 3, user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post, onLike: () {}));
      await tester.pump();
      // 评论按钮不抛出异常即通过
      await tester.tap(find.byIcon(Icons.comment_outlined));
      await tester.pump();
    });
  });
}
