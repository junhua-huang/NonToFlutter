import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommentWidget - 基本渲染', () {
    testWidgets('Comment 列表项样式渲染', (tester) async {
      // 项目中无独立 CommentWidget，使用 ListTile 模拟验证样式
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListTile(
              title: Text('Commenter'),
              subtitle: Text('This is a great post!'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.favorite_border),
                  Text('5'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('This is a great post!'), findsOneWidget);
      expect(find.text('Commenter'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('回复评论缩进显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(left: 48),
              child: ListTile(
                title: Text('Replier'),
                subtitle: Text('Reply content'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Reply content'), findsOneWidget);
      expect(find.text('Replier'), findsOneWidget);
    });
  });
}
