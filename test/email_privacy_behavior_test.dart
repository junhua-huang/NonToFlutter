import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/services/aliyun_push_service.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

AliyunPushService _pushService() {
  return AliyunPushService.forTesting(
    hasAuthToken: () => true,
    deviceIdProvider: () async => 'device-1',
    registerDevice: (_) async => true,
    unregisterDevice: (_) async => true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('User email privacy model', () {
    test('parses and serializes show_email true', () {
      final dynamic user = User.fromJson(<String, dynamic>{
        'id': 1,
        'username': 'alice',
        'email': 'alice@example.test',
        'show_email': true,
      });

      expect(user.showEmail, isTrue);
      expect(user.toJson()['show_email'], isTrue);
    });

    test('parses and serializes show_email false', () {
      final dynamic user = User.fromJson(<String, dynamic>{
        'id': 2,
        'username': 'bob',
        'email': 'bob@example.test',
        'show_email': false,
      });

      expect(user.showEmail, isFalse);
      expect(user.toJson()['show_email'], isFalse);
    });

    test('does not invent show_email when absent', () {
      final dynamic user = User.fromJson(<String, dynamic>{
        'id': 3,
        'username': 'carol',
        'email': 'carol@example.test',
      });

      expect(user.showEmail, isNull);
      expect(user.toJson(), isNot(contains('show_email')));
    });

    test('copyWith preserves, sets, and explicitly clears showEmail', () {
      final dynamic original = User.fromJson(<String, dynamic>{
        'id': 4,
        'username': 'dana',
        'email': 'dana@example.test',
        'show_email': true,
      });

      expect(original.copyWith().showEmail, isTrue);
      expect(original.copyWith(showEmail: false).showEmail, isFalse);
      expect(original.copyWith(clearShowEmail: true).showEmail, isNull);
    });
  });

  group('Email display policy', () {
    test('own email follows the same showEmail switch as public profile', () {
      User userWith(bool showEmail) => User.fromJson(<String, dynamic>{
            'id': 1,
            'username': 'alice',
            'email': 'alice@example.test',
            'show_email': showEmail,
          });

      expect(profileEmailFor(userWith(true), isOwnProfile: true),
          'alice@example.test');
      expect(profileEmailFor(userWith(false), isOwnProfile: true), isNull);
    });

    test('empty email is never visible', () {
      final user = User.fromJson(<String, dynamic>{
        'id': 1,
        'username': 'alice',
        'email': '',
        'show_email': true,
      });

      expect(profileEmailFor(user, isOwnProfile: true), isNull);
      expect(profileEmailFor(user, isOwnProfile: false), isNull);
    });

    test('other email is visible only when showEmail is strictly true', () {
      User userWith(dynamic showEmail) => User.fromJson(<String, dynamic>{
            'id': 2,
            'username': 'bob',
            'email': 'bob@example.test',
            if (showEmail != null) 'show_email': showEmail,
          });

      expect(profileEmailFor(userWith(true), isOwnProfile: false),
          'bob@example.test');
      expect(profileEmailFor(userWith(false), isOwnProfile: false), isNull);
      expect(profileEmailFor(userWith(null), isOwnProfile: false), isNull);
    });
  });

  group('Authoritative user detail replacement', () {
    test('only the latest detail request may replace profile state', () {
      final gate = UserDetailRequestGate();
      final older = gate.begin();
      final newer = gate.begin();

      expect(gate.accepts(older), isFalse);
      expect(gate.accepts(newer), isTrue);
    });

    test('force refresh user detail bypasses the managed response cache', () {
      final source = File(
        '${Directory.current.path}/lib/services/api/auth_service.dart',
      ).readAsStringSync();

      expect(
          source, contains('getUser(int userId, {bool forceRefresh = false})'));
      expect(source, contains("final path = '/auth/users/\$userId'"));
      expect(source, contains('_api.cancelGet(path)'));
      expect(source, contains('bypassManager: forceRefresh'));
    });

    test('public profile initialization removes stale card email and flag', () {
      final staleCard = User.fromJson(<String, dynamic>{
        'id': 7,
        'username': 'stale',
        'email': 'stale@example.test',
        'show_email': true,
      });

      final sanitized = failClosedPublicUser(staleCard);

      expect(sanitized.email, isEmpty);
      expect(sanitized.showEmail, isNull);
      expect(profileEmailFor(sanitized, isOwnProfile: false), isNull);
    });

    test('unwraps user envelope and replaces lightweight user', () {
      final lightweight = User.fromJson(<String, dynamic>{
        'id': 8,
        'username': 'lightweight',
      });

      final detail = userFromDetailResponse(<String, dynamic>{
        'user': <String, dynamic>{
          'id': 8,
          'username': 'authoritative',
          'email': 'detail@example.test',
          'show_email': true,
        },
      });

      expect(profileEmailFor(lightweight, isOwnProfile: false), isNull);
      expect(detail.username, 'authoritative');
      expect(detail.email, 'detail@example.test');
      expect(detail.showEmail, isTrue);
    });

    test('refresh replacement hides email when detail changes flag to false',
        () {
      final detail = userFromDetailResponse(<String, dynamic>{
        'id': 9,
        'username': 'refreshed',
        'email': 'detail@example.test',
        'show_email': false,
      });

      expect(profileEmailFor(detail, isOwnProfile: false), isNull);
    });
  });

  group('Privacy save synchronization', () {
    test(
        'privacy controls are disabled while saving and async load checks mounted',
        () {
      final source = File(
        '${Directory.current.path}/lib/screens/profile/settings_screen.dart',
      ).readAsStringSync();

      expect(source, contains('AbsorbPointer('));
      expect(source, contains('absorbing: _isSaving'));
      expect(source, contains('if (_isLoading || _isSaving) return;'));
      expect(source, contains('onPressed: _isLoading || _isSaving'));
      expect(source, contains('if (!mounted) return;'));
    });
    late SharedPreferences prefs;
    late AuthNotifier notifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'access_token': 'test-token',
        'current_user_id': '10',
        'current_user_json': jsonEncode(<String, Object>{
          'id': 10,
          'username': 'owner',
          'email': 'owner@example.test',
          'show_email': false,
        }),
      });
      prefs = await SharedPreferences.getInstance();
      notifier = AuthNotifier.forTesting(
        prefs,
        pushService: _pushService(),
      );
      await notifier.restoredSessionReady;
    });

    tearDown(() => notifier.dispose());

    test('successful PUT updates authenticated user and persisted cache',
        () async {
      final response = await savePrivacyAndSynchronizeEmail(
        data: <String, dynamic>{'show_email': true},
        updatePrivacy: (_) async => ApiResponse<void>(success: true),
        synchronizeShowEmail: notifier.synchronizeShowEmail,
      );

      expect(response.success, isTrue);
      expect(notifier.state.user!.showEmail, isTrue);
      final cached = jsonDecode(prefs.getString('current_user_json')!)
          as Map<String, dynamic>;
      expect(cached['show_email'], isTrue);
    });

    test('failed PUT leaves authenticated user and cache unchanged', () async {
      final beforeCache = prefs.getString('current_user_json');

      final response = await savePrivacyAndSynchronizeEmail(
        data: <String, dynamic>{'show_email': true},
        updatePrivacy: (_) async =>
            ApiResponse<void>(success: false, message: 'failed'),
        synchronizeShowEmail: notifier.synchronizeShowEmail,
      );

      expect(response.success, isFalse);
      expect(notifier.state.user!.showEmail, isFalse);
      expect(prefs.getString('current_user_json'), beforeCache);
    });
  });

  group('Auth show_email propagation and cache', () {
    test('manual auth payload extraction propagates show_email', () {
      final dynamic user = userFromAuthPayload(<String, dynamic>{
        'id': 6,
        'username': 'manual-user',
        'email': 'manual@example.test',
        'show_email': false,
      });

      expect(user.showEmail, isFalse);
    });

    test('cached auth user restores showEmail without normalization loss',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'access_token': 'test-token',
        'current_user_id': '7',
        'current_user_json': jsonEncode(<String, Object>{
          'id': 7,
          'username': 'cached-user',
          'email': 'cached@example.test',
          'show_email': true,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = AuthNotifier.forTesting(
        prefs,
        pushService: _pushService(),
      );
      addTearDown(notifier.dispose);

      await notifier.restoredSessionReady;

      final dynamic restored = notifier.state.user;
      expect(restored.showEmail, isTrue);
    });
  });
}
