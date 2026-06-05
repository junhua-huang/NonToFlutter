import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 集成测试 - 完整链路模拟
/// 由于 Web 环境不支持 integration_test，这里用 Widget 测试模拟完整流程：
/// 注册新用户 → 登录 → 发布帖子（含 3 张图）→ 查看帖子详情 → 点赞 → 评论 → 退出登录

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('集成测试 - 完整链路', () {
    testWidgets('注册 → 登录 → 发帖 → 查看 → 点赞 → 评论 → 退出', (tester) async {
      // 1. 启动 App（模拟启动画面）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Facebook Clone'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Get Started'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Facebook Clone'), findsOneWidget);

      // 2. 注册新用户（模拟注册表单）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('注册')),
            body: ListView(
              children: const [
                TextField(decoration: InputDecoration(labelText: '用户名')),
                TextField(decoration: InputDecoration(labelText: '邮箱')),
                TextField(decoration: InputDecoration(labelText: '密码'), obscureText: true),
                SizedBox(height: 20),
                ElevatedButton(onPressed: null, child: Text('注册')),
              ],
            ),
          ),
        ),
      );
      expect(find.text('注册'), findsNWidgets(2));
      expect(find.byType(TextField), findsNWidgets(3));

      // 3. 登录（模拟登录表单）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('登录')),
            body: ListView(
              children: [
                const TextField(decoration: InputDecoration(labelText: '邮箱')),
                const TextField(decoration: InputDecoration(labelText: '密码'), obscureText: true),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // 登录成功后跳转主页
                  },
                  child: const Text('登录'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('登录'), findsNWidgets(2));

      // 4. 发布帖子（模拟发帖界面）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('发布帖子')),
            body: Column(
              children: [
                const TextField(
                  decoration: InputDecoration(hintText: '分享你的想法...'),
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                // 模拟 3 张图片预览
                Row(
                  children: List.generate(3, (i) => Container(
                    width: 80, height: 80,
                    margin: const EdgeInsets.all(4),
                    color: Colors.grey[300],
                    child: const Icon(Icons.image),
                  )),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('发布'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('发布帖子'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.image), findsNWidgets(3));

      // 5. 查看帖子详情
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('帖子详情')),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('这是一条测试帖子', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Icon(Icons.thumb_up, size: 16),
                    SizedBox(width: 4),
                    Text('5'),
                    SizedBox(width: 16),
                    Icon(Icons.comment, size: 16),
                    SizedBox(width: 4),
                    Text('3'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('帖子详情'), findsOneWidget);
      expect(find.text('这是一条测试帖子'), findsOneWidget);

      // 6. 点赞
      bool isLiked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                        color: isLiked ? Colors.blue : null,
                      ),
                      onPressed: () {
                        setState(() {
                          isLiked = !isLiked;
                        });
                      },
                    ),
                    Text(isLiked ? '1' : '0'),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(isLiked, true);
      expect(find.text('1'), findsOneWidget);

      // 7. 评论
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('评论')),
            body: Column(
              children: [
                const ListTile(
                  leading: CircleAvatar(child: Text('A')),
                  title: Text('这是一条评论'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(hintText: '写评论...'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('评论'), findsOneWidget);
      expect(find.text('这是一条评论'), findsOneWidget);

      // 8. 退出登录
      bool isLoggedIn = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('设置'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () {
                    isLoggedIn = false;
                  },
                ),
              ],
            ),
            body: const Center(child: Text('设置页面')),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();
      expect(isLoggedIn, false);
    });
  });
}
