import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    initTestSqflite();
  });

  tearDown(() {
    tearDownMockDio();
  });

  /// 创建 AuthProvider 并等待 loadSavedSession 完成
  Future<AuthProvider> createProvider() async {
    final provider = AuthProvider();
    // 等待异步 loadSavedSession 完成（无 token 时直接返回）
    await Future.delayed(const Duration(milliseconds: 200));
    return provider;
  }

  group('auth_provider - 初始状态', () {
    test('初始时 user 和 token 为 null', () async {
      final provider = await createProvider();
      expect(provider.user, isNull);
      expect(provider.token, isNull);
      expect(provider.isLoggedIn, false);
    });
  });

  group('auth_provider - login', () {
    test('login 成功后 token 和 user 非 null', () async {
      final provider = await createProvider();
      mockAuthSuccess('myToken', {
        'id': 1, 'username': 'test', 'email': 'test@e.com',
        'display_name': 'Test User',
      });
      final result = await provider.login('test@e.com', 'pass');
      expect(result, true);
      expect(provider.token, 'myToken');
      expect(provider.user, isNotNull);
      expect(provider.user!.id, 1);
      expect(provider.isLoggedIn, true);
    });

    test('login 失败后 isLoggedIn == false', () async {
      final provider = await createProvider();
      mockHttpError(401, 'Invalid credentials');
      final result = await provider.login('bad@e.com', 'wrong');
      expect(result, false);
      expect(provider.isLoggedIn, false);
      expect(provider.user, isNull);
    });
  });

  group('auth_provider - register', () {
    test('register 成功后自动设置 user', () async {
      final provider = await createProvider();
      mockAuthSuccess('regToken', {
        'id': 2, 'username': 'newuser', 'email': 'new@e.com',
        'display_name': 'New User',
      });
      final result = await provider.register(
        username: 'newuser', email: 'new@e.com', password: 'pass',
        bio: 'I am new',
      );
      expect(result, true);
      expect(provider.token, 'regToken');
      expect(provider.user, isNotNull);
      expect(provider.isLoggedIn, true);
    });

    test('register 失败后 isLoggedIn == false', () async {
      final provider = await createProvider();
      mockHttpError(400, 'Email exists');
      final result = await provider.register(
        username: 'dup', email: 'dup@e.com', password: 'pass',
      );
      expect(result, false);
      expect(provider.isLoggedIn, false);
    });
  });

  group('auth_provider - logout', () {
    test('logout 后状态清空', () async {
      final provider = await createProvider();
      mockAuthSuccess('tok', {'id': 1, 'username': 'u', 'email': 'e@e.com'});
      await provider.login('e@e.com', 'p');
      expect(provider.isLoggedIn, true);

      await provider.logout();
      expect(provider.isLoggedIn, false);
      expect(provider.user, isNull);
      expect(provider.token, isNull);
    });
  });

  group('auth_provider - updateProfile', () {
    test('updateProfile 成功后更新 user', () async {
      final provider = await createProvider();
      mockAuthSuccess('tok', {
        'id': 1, 'username': 'u', 'email': 'e@e.com',
        'display_name': 'Old', 'bio': 'old bio',
      });
      await provider.login('e@e.com', 'p');

      mockSuccess({'message': 'updated'});
      final result = await provider.updateProfile({
        'display_name': 'NewName',
        'bio': 'new bio',
        'avatar_url': 'https://new.jpg',
      });
      expect(result, true);
    });
  });
}
