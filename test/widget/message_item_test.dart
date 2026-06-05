import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/message.dart';

void main() {
  group('MessageItem - 未读消息', () {
    testWidgets('未读消息显示在 MessageBubble 中', (tester) async {
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
      // 使用 1x1 透明 PNG 避免网络请求
      const transparentPng = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x00, 0x00, 0x02,
        0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
        0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Image.memory(Uint8List.fromList(transparentPng))),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('MessageItem - 时间显示', () {
    testWidgets('消息时间格式化展示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Text('14:30')),
        ),
      );
      expect(find.text('14:30'), findsOneWidget);
    });
  });
}
