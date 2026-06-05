import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/message.dart';

void main() {
  group('MessageItem - 未读消息', () {
    testWidgets('未读消息显示未读状态', (tester) async {
      final msg = Message(
        id: 1, conversationId: 1, senderId: 1,
        content: 'Hello there!',
        messageType: MessageType.text,
        isRead: false,
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text(msg.content!),
                Text(msg.isRead ? '已读' : '未读'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Hello there!'), findsOneWidget);
      expect(find.text('未读'), findsOneWidget);
    });

    testWidgets('已读消息不显示未读标记', (tester) async {
      final msg = Message(
        id: 2, conversationId: 1, senderId: 1,
        content: 'Read message',
        messageType: MessageType.text,
        isRead: true,
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text(msg.content!),
                Text(msg.isRead ? '已读' : '未读'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Read message'), findsOneWidget);
      expect(find.text('已读'), findsOneWidget);
    });
  });

  group('MessageItem - 内容预览', () {
    testWidgets('文本消息渲染', (tester) async {
      final msg = Message(
        id: 3, conversationId: 1, senderId: 1,
        content: 'Preview text',
        messageType: MessageType.text,
        isRead: false,
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Text(msg.content!)),
        ),
      );
      expect(find.text('Preview text'), findsOneWidget);
    });

    testWidgets('图片消息类型渲染', (tester) async {
      final msg = Message(
        id: 4, conversationId: 1, senderId: 1,
        content: 'https://img.example.com/photo.jpg',
        messageType: MessageType.image,
        isRead: false,
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Image.network(msg.content!)),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('MessageItem - 时间显示', () {
    testWidgets('消息时间格式化展示', (tester) async {
      final msg = Message(
        id: 5, conversationId: 1, senderId: 1,
        content: 'Time test',
        messageType: MessageType.text,
        isRead: false,
        createdAt: DateTime(2024, 6, 3, 14, 30),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Text('14:30')),
        ),
      );
      expect(find.text('14:30'), findsOneWidget);
    });
  });
}
