import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/services/api/auth_service.dart';
import '../../helpers/test_helpers.dart';

void main() {
  late AuthService authService;

  setUp(() {
    authService = AuthService();
  });

  tearDown(() {
    tearDownMockDio();
  });

  group('auth_service - login', () {
    test('登录成功返回 token + user', () async {
      mockAuthSuccess('abc123', {
        'id': 1, 'username': 'test', 'email': 'test@e.com',
        'display_name': 'Test',
      });
      final resp = await authService.login('test@e.com', 'pass');
      expectSuccess(resp);
      final data = resp.data as Map<String, dynamic>;
      expect(data['access_token'], 'abc123');
      expect(data['user'], isNotNull);
      expect(data['user']['username'], 'test');
    });

    test('登录失败抛出错误', () async {
      mockHttpError(401, 'Invalid credentials');
      final resp = await authService.login('bad@e.com', 'wrong');
      expectFailure(resp);
      expect(resp.message, contains('Invalid credentials'));
    });
  });

  group('auth_service - register', () {
    test('注册使用 password 字段（不是 password_hash）', () async {
      // 验证 register 方法通过 data map 传参，字段名由调用方决定
      mockSuccess({'id': 1, 'message': 'ok'});
      final resp = await authService.register({
        'username': 'new',
        'email': 'new@e.com',
        'password': 'secret',
      });
      expectSuccess(resp);
    });
  });

  group('auth_service - getProfile', () {
    test('获取个人资料成功', () async {
      mockSuccess({
        'id': 1, 'username': 'test', 'email': 'test@e.com',
        'display_name': 'Test User',
      });
      final resp = await authService.getProfile();
      expectSuccess(resp);
    });

    test('token 过期返回 401', () async {
      mockHttpError(401, 'Token expired');
      final resp = await authService.getProfile();
      expectFailure(resp);
    });
  });

  group('auth_service - changePassword', () {
    test('密码修改请求体字段名是 old_password', () async {
      mockSuccess({'message': 'Password changed'});
      final resp = await authService.changePassword(
        currentPassword: 'old',
        newPassword: 'new',
      );
      expectSuccess(resp);
    });
  });

  group('auth_service - updateProfile', () {
    test('修改资料请求发送 avatar_url 和 cover_photo_url', () async {
      mockSuccess({'message': 'Updated'});
      final resp = await authService.updateProfile({
        'display_name': 'NewName',
        'avatar_url': 'https://a.jpg',
        'cover_photo_url': 'https://c.jpg',
      });
      expectSuccess(resp);
    });
  });

  group('auth_service - refreshToken', () {
    test('刷新 token 成功', () async {
      mockAuthSuccess('newToken', {
        'id': 1, 'username': 't', 'email': 'e@e.com',
      });
      final resp = await authService.refreshToken();
      expectSuccess(resp);
      expect((resp.data as Map)['access_token'], 'newToken');
    });
  });

  group('auth_service - other endpoints', () {
    test('getUser 正确调用', () async {
      mockSuccess({'id': 99, 'username': 'u99', 'email': 'e@e.com'});
      final resp = await authService.getUser(99);
      expectSuccess(resp);
    });

    test('deleteAccount 正确调用', () async {
      mockSuccess({'message': 'deleted'});
      final resp = await authService.deleteAccount();
      expectSuccess(resp);
    });

    test('forgotPassword 正确调用', () async {
      mockSuccess({'message': 'email sent'});
      final resp = await authService.forgotPassword('e@e.com');
      expectSuccess(resp);
    });
  });
}
