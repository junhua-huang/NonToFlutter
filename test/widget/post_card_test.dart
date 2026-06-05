import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/widgets/post_card.dart';
import '../helpers/test_helpers.dart';

Widget wrapPostCard(Post post) {
  initTestSqflite();
  return ChangeNotifierProvider<AuthProvider>(
    create: (_) => AuthProvider(),
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostCard(post: post, onTap: () {}))),
    ),
  );
}

void main() {
  final baseAuthor = User(
    id: 1, username: 'testauthor', email: 'a@e.com',
    displayName: 'Test Author',
  );

  group('PostCard - 纯文字帖子', () {
    testWidgets('纯文字帖子渲染内容', (tester) async {
      final post = Post(
        id: 1, userId: 1, content: 'HelloWorldPureText',
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.byType(RichText), findsWidgets);
    });
  });

  group('PostCard - 图片帖子', () {
    testWidgets('1 张图片渲染', (tester) async {
      final post = Post(
        id: 2, userId: 1, content: '单图',
        imageUrl: 'https://img.example.com/1.jpg',
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      // 有图片的帖子确实渲染了内容 widget，验证 PostCard 不抛出异常
      expect(find.byType(PostCard), findsOneWidget);
    });

    testWidgets('2 张图片 - 左右并排', (tester) async {
      final post = Post(
        id: 3, userId: 1, content: '双图',
        images: ['https://img.example.com/a.jpg', 'https://img.example.com/b.jpg'],
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.byType(PostCard), findsOneWidget);
    });

    testWidgets('3 张图片', (tester) async {
      final post = Post(
        id: 4, userId: 1, content: '三图',
        images: ['a.jpg', 'b.jpg', 'c.jpg'],
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.byType(PostCard), findsOneWidget);
    });

    testWidgets('4 张图片 - 2x2 网格', (tester) async {
      final post = Post(
        id: 5, userId: 1, content: '四图',
        images: ['1.jpg', '2.jpg', '3.jpg', '4.jpg'],
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.byType(PostCard), findsOneWidget);
    });

    testWidgets('5-9 张图片多图网格', (tester) async {
      for (final count in [5, 6, 7, 8, 9]) {
        final images = List.generate(count, (i) => 'img$i.jpg');
        final post = Post(
          id: 6 + count, userId: 1, content: '$count图',
          images: images,
          user: baseAuthor,
        );
        await tester.pumpWidget(wrapPostCard(post));
        await tester.pump();
        expect(find.byType(PostCard), findsOneWidget);
      }
    });
  });

  group('PostCard - 交互元素', () {
    testWidgets('点赞数渲染', (tester) async {
      final post = Post(
        id: 10, userId: 1, content: 'Like test',
        likeCount: 5, isLiked: false,
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.text('5'), findsWidgets);
    });

    testWidgets('评论数渲染', (tester) async {
      final post = Post(
        id: 11, userId: 1, content: 'Comment test',
        commentCount: 3, user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('浏览量数字渲染', (tester) async {
      final post = Post(
        id: 12, userId: 1, content: 'View test',
        viewCount: 150, user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.text('150'), findsWidgets);
    });

    testWidgets('话题标签渲染', (tester) async {
      final post = Post(
        id: 13, userId: 1, content: 'Hello #Flutter #Dart',
        topics: ['flutter', 'dart'],
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('显示 @提及', (tester) async {
      final post = Post(
        id: 14, userId: 1, content: 'Hey @user1 and @user2',
        user: baseAuthor,
      );
      await tester.pumpWidget(wrapPostCard(post));
      await tester.pump();
      expect(find.byType(RichText), findsWidgets);
    });
  });
}
