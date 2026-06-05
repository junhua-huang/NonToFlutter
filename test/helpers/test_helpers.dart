import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/comment.dart';
import 'package:facebook_clone/models/notification.dart';
import 'package:facebook_clone/models/message.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/comic_event.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/services/api/api_client.dart';

// ═══════════════════════════════════════════
// JSON 解析快捷方法
// ═══════════════════════════════════════════

User userFromJson(String jsonStr) =>
    User.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

Post postFromJson(String jsonStr) =>
    Post.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

Comment commentFromJson(String jsonStr) =>
    Comment.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

AppNotification notificationFromJson(String jsonStr) =>
    AppNotification.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

Message messageFromJson(String jsonStr) =>
    Message.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

Conversation conversationFromJson(String jsonStr) =>
    Conversation.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

ComicEvent comicEventFromJson(String jsonStr) =>
    ComicEvent.fromListJson(jsonDecode(jsonStr) as Map<String, dynamic>);

// ═══════════════════════════════════════════
// 快速构造器
// ═══════════════════════════════════════════

User makeUser({
  int id = 1,
  String username = 'testuser',
  String email = 'test@example.com',
  String? displayName = 'Test User',
  String? bio,
  String? avatarUrl,
  String? coverPhotoUrl,
}) =>
    User(
      id: id,
      username: username,
      email: email,
      displayName: displayName,
      bio: bio,
      avatarUrl: avatarUrl,
      coverPhotoUrl: coverPhotoUrl,
    );

Post makePost({
  int id = 1,
  String? content = 'Hello test',
  int userId = 1,
  int likeCount = 0,
  int commentCount = 0,
  int viewCount = 0,
  bool isLiked = false,
  List<String>? images,
  User? user,
}) =>
    Post(
      id: id,
      content: content,
      userId: userId,
      likeCount: likeCount,
      commentCount: commentCount,
      viewCount: viewCount,
      isLiked: isLiked,
      images: images,
      user: user ?? makeUser(),
      createdAt: DateTime(2024, 3, 10),
    );

Comment makeComment({
  int id = 1,
  String content = 'Test comment',
  int userId = 1,
  int postId = 1,
  int likeCount = 0,
  int replyCount = 0,
  bool isLiked = false,
  List<Comment> replies = const [],
  User? user,
}) =>
    Comment(
      id: id,
      content: content,
      userId: userId,
      postId: postId,
      likeCount: likeCount,
      replyCount: replyCount,
      isLiked: isLiked,
      replies: replies,
      user: user ?? makeUser(),
      createdAt: DateTime(2024, 3, 10),
    );

// ═══════════════════════════════════════════
// 断言快捷
// ═══════════════════════════════════════════

void expectSuccess(ApiResponse resp, {String? context}) {
  expect(resp.success, isTrue, reason: context ?? 'Expected success');
}

void expectFailure(ApiResponse resp, {String? context}) {
  expect(resp.success, isFalse, reason: context ?? 'Expected failure');
}

// ═══════════════════════════════════════════
// Widget 测试辅助
// ═══════════════════════════════════════════

Future<void> initTestPrefs() async {
  SharedPreferences.setMockInitialValues({});
}

/// 初始化 sqflite 测试环境（解决 "databaseFactory not initialized" 错误）
void initTestSqflite() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<void> pumpApp(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
}

// ═══════════════════════════════════════════
// Mock Dio HTTP Adapter（服务层测试核心）
// ═══════════════════════════════════════════
//
// 用法：
//   setupMockDio(statusCode: 200, body: jsonEncode({...}));
//   // 然后调用 Service 方法即可得到 mock 响应
//
// 注意：需要先调用 setupMockDio() 来替换 ApiClient 单例的 Dio adapter。
// 测试结束后调用 tearDownMockDio() 恢复。

HttpClientAdapter? _originalAdapter;

/// 设置 Mock HTTP 适配器。所有请求返回统一的 statusCode + body。
void setupMockDio({required int statusCode, required String body}) {
  final client = ApiClient();
  _originalAdapter = client.dio.httpClientAdapter;
  client.dio.httpClientAdapter = _MockAdapter(
    statusCode: statusCode,
    body: body,
  );
}

/// 恢复 Dio 原始适配器
void tearDownMockDio() {
  if (_originalAdapter != null) {
    ApiClient().dio.httpClientAdapter = _originalAdapter!;
    _originalAdapter = null;
  }
}

class _MockAdapter implements HttpClientAdapter {
  final int statusCode;
  final String body;

  _MockAdapter({required this.statusCode, required this.body});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future? cancelFuture,
  ) async {
    final bytes = utf8.encode(body);
    return ResponseBody(
      Stream.fromIterable([bytes]),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ═══════════════════════════════════════════
// 通用 Mock 响应体工厂
// ═══════════════════════════════════════════

/// 构造成功的 API 响应体
String mockSuccessBody(Map<String, dynamic> data) =>
    jsonEncode(data);

/// 构造带 token+user 的登录/注册成功体
String mockAuthBody(String token, Map<String, dynamic> userJson) =>
    jsonEncode({'access_token': token, 'user': userJson});

/// 构造失败响应
String mockErrorBody(String message) =>
    jsonEncode({'message': message});

/// 构造分页列表响应
String mockPaginatedBody(String key, List<dynamic> items,
    {int page = 1, int pages = 1, int total = 0}) {
  return jsonEncode({
    key: items,
    'page': page,
    'pages': pages,
    'total': total,
    'has_more': page < pages,
  });
}

/// 通用 setup：200 + 给定 data
void mockSuccess(Map<String, dynamic> data) {
  setupMockDio(statusCode: 200, body: mockSuccessBody(data));
}

/// 通用 setup：200 + auth 响应
void mockAuthSuccess(String token, Map<String, dynamic> userJson) {
  setupMockDio(statusCode: 200, body: mockAuthBody(token, userJson));
}

/// 通用 setup：400 + message
void mockHttpError(int code, String msg) {
  setupMockDio(statusCode: code, body: mockErrorBody(msg));
}
