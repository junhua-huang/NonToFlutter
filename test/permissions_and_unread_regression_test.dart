import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('permission and unread synchronization regressions', () {
    test('Android declares notification permission without broad storage access', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final pubspec = read('pubspec.yaml');

      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, isNot(contains('android.permission.MANAGE_EXTERNAL_STORAGE')));
      expect(pubspec, isNot(contains('file_picker:')));
      expect(pubspec, isNot(contains('permission_handler:')));
    });

    test('push notification permission is requested from the home shell once', () {
      final push = read('lib/services/push_service.dart');
      final home = read('lib/screens/home/home_screen.dart');

      expect(push, contains('bool _permissionRequested = false;'));
      expect(push, contains('if (!_supported || !_initialized || _permissionRequested) return;'));
      expect(push, contains('_permissionRequested = true;'));
      expect(push, contains('_jpush.requestRequiredPermission();'));
      expect(home, contains("import 'package:nonto/services/push_service.dart';"));
      expect(home, contains('addPostFrameCallback'));
      expect(home, contains('PushService().requestPermission()'));
    });

    test('picker failures show user-facing permission guidance', () {
      final helper = read('lib/utils/picker_error_utils.dart');
      final postCreate = read('lib/screens/post/create_post_screen.dart');
      final chatRoom = read('lib/screens/chat/chat_room_screen.dart');
      final communityChat = read('lib/screens/community/community_chat_screen.dart');
      final communityCreate = read('lib/screens/community/community_create_screen.dart');
      final comicUpload = read('lib/screens/comic/comic_upload_page.dart');
      final editProfile = read('lib/screens/profile/edit_profile_screen.dart');
      final profileTab = read('lib/screens/profile/profile_tab.dart');

      expect(helper, contains('String pickerErrorMessage(Object error'));
      expect(helper, contains('无法访问'));
      expect(helper, contains('系统设置'));
      for (final source in [
        postCreate,
        chatRoom,
        communityChat,
        communityCreate,
        comicUpload,
        editProfile,
        profileTab,
      ]) {
        expect(source, contains("package:nonto/utils/picker_error_utils.dart"));
        expect(source, contains('showPickerErrorSnackBar('));
      }
      expect(chatRoom, contains('if (source == ImageSource.camera)'));
      expect(chatRoom, contains('pickImage('));
    });

    test('cached notification pages derive unread count from local list', () {
      final notifier = read('lib/providers/notifications_notifier.dart');

      expect(notifier, contains('final mergedNotifications = refresh'));
      expect(notifier, contains('final localUnread ='));
      expect(notifier, contains('mergedNotifications.where((n) => !n.isRead).length'));
      expect(notifier, contains('final unreadCount = serverUnread ?? localUnread;'));
      expect(notifier, isNot(contains('final unreadCount = serverUnread ?? state.unreadCount;')));
    });

    test('notifications tab refreshes stale unread badges without unread rows', () {
      final tab = read('lib/screens/notifications/notifications_tab.dart');

      expect(tab, contains('final hasUnreadInList ='));
      expect(tab, contains('state.unreadCount > 0 && !hasUnreadInList'));
      expect(tab, contains('loadNotifications(refresh: true)'));
    });

    test('push service reports app foreground and background state', () {
      final push = read('lib/services/push_service.dart');
      final home = read('lib/screens/home/home_screen.dart');

      expect(push, contains('Future<void> reportAppState(String appState)'));
      expect(push, contains("'/push/device-state'"));
      expect(push, contains("'registration_id': registrationId"));
      expect(push, contains("'app_state': appState"));
      expect(push, contains('String? _lastReportedAppState;'));
      expect(push, contains('if (_lastReportedAppState == appState) return;'));
      expect(home, contains("PushService().reportAppState('foreground')"));
      expect(home, contains("PushService().reportAppState('background')"));
    });

    test('push registration upload has bounded retry state', () {
      final push = read('lib/services/push_service.dart');

      expect(push, contains('bool _registerRetryScheduled = false;'));
      expect(push, contains('static const List<Duration> _registerRetryDelays'));
      expect(push, contains('Future<bool> _uploadRegistrationId()'));
      expect(push, contains('_scheduleRegisterRetry()'));
      expect(push, contains('Timer? _registerRetryTimer;'));
      expect(push, contains('_registerRetryTimer?.cancel();'));
      expect(push, contains('Duration(seconds: 5)'));
      expect(push, contains('Duration(seconds: 15)'));
      expect(push, contains('Duration(seconds: 60)'));
    });
  });
}
