import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('permission and unread synchronization regressions', () {
    test(
        'Android declares notification permission without broad storage access',
        () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final pubspec = read('pubspec.yaml');

      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest,
          isNot(contains('android.permission.MANAGE_EXTERNAL_STORAGE')));
      expect(pubspec, isNot(contains('file_picker:')));
      expect(pubspec, isNot(contains('permission_handler:')));
    });

    test('vendor push and notification test support start from app bootstrap',
        () {
      final main = read('lib/main.dart');
      final home = read('lib/screens/home/home_screen.dart');
      final localNotification =
          read('lib/services/local_notification_service.dart');

      expect(main, contains('LocalNotificationService().init()'));
      expect(main, contains('AliyunPushService().init()'));
      expect(main, contains('AppLifecycleKeepAliveService().start()'));
      final compactMain = main.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        compactMain,
        contains('notification permission and explicit diagnostic test'),
      );
      expect(compactMain, contains('foreground-only Flutter WebSocket'));
      expect(localNotification, contains('requestNotificationsPermission'));
      expect(localNotification, contains('showTestNotification'));
      expect(localNotification, isNot(contains('showMessageNotification')));
      expect(localNotification, isNot(contains('showInteractionNotification')));
      expect(home, isNot(contains("services/push_service.dart")));
      expect(home, isNot(contains('PushService().requestPermission()')));
    });

    test('picker failures show user-facing permission guidance', () {
      final helper = read('lib/utils/picker_error_utils.dart');
      final postCreate = read('lib/screens/post/create_post_screen.dart');
      final chatRoom = read('lib/screens/chat/chat_room_screen.dart');
      final communityChat =
          read('lib/screens/community/community_chat_screen.dart');
      final communityCreate =
          read('lib/screens/community/community_create_screen.dart');
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

      final compact = notifier.replaceAll(RegExp(r'\s+'), '');
      expect(
        compact,
        contains(
          'finalmergedNotifications=(refresh?list:[...state.notifications,...list]).where((n)=>n.notificationType!=\'message\').toList();',
        ),
      );
      expect(
        compact,
        contains(
          'finallocalUnread=mergedNotifications.where((n)=>!n.isRead).length;',
        ),
      );
      expect(compact, contains('finalunreadCount=serverUnread??localUnread;'));
      expect(
        compact,
        isNot(contains('finalunreadCount=serverUnread??state.unreadCount;')),
      );
    });

    test('notifications tab refreshes stale unread badges without unread rows',
        () {
      final tab = read('lib/screens/notifications/notifications_tab.dart');

      expect(tab, contains('final hasUnreadInList ='));
      expect(tab, contains('state.unreadCount > 0 && !hasUnreadInList'));
      expect(tab, contains('loadNotifications(refresh: true)'));
    });

    test('notification deep links land on the correct home tabs', () {
      final routes = read('lib/routes/route_generator.dart');

      expect(routes, contains('case AppRoutes.chat:'));
      expect(routes, contains('case AppRoutes.chat:'));
      expect(
          routes, contains('builder: (_) => const HomeScreen(initialTab: 2)'));
      expect(routes, contains('settings: settings,'));
      expect(routes, contains('case AppRoutes.notifications:'));
      expect(routes, contains('builder: (_) => const NotificationsTab()'));
      expect(routes, contains('settings: settings,'));
      expect(routes, contains('case AppRoutes.search:'));
      expect(
          routes, contains('builder: (_) => const HomeScreen(initialTab: 1)'));
      expect(routes, contains('settings: settings,'));
      expect(routes, contains('return const HomeScreen(initialTab: 2);'));
    });

    test('lifecycle keeps Flutter WebSocket foreground-only', () {
      final home = read('lib/screens/home/home_screen.dart');
      final lifecycle =
          read('lib/services/app_lifecycle_keepalive_service.dart');

      expect(home, isNot(contains('PushService().reportAppState')));
      expect(lifecycle, contains('foreground-only Flutter WebSocket'));
      expect(lifecycle, contains('_setAppForeground(foreground)'));
      expect(lifecycle, contains('await _forceReconnect()'));
      expect(lifecycle, contains('await _disconnect()'));
      expect(
          lifecycle, contains('AliyunPushService().updateBackendDeviceState'));
      expect(lifecycle, isNot(contains('ForegroundServiceManager')));
      expect(lifecycle, isNot(contains('startMessageKeepAlive')));
      expect(lifecycle, isNot(contains('native_ws_')));
    });

    test('Android vendor push wiring uses Aliyun without legacy vendor files',
        () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final gradle = read('android/app/build.gradle.kts');
      final rootGradle = read('android/build.gradle.kts');
      final pubspec = read('pubspec.yaml');

      expect(pubspec, contains('aliyun_push_flutter:'));
      expect(
          rootGradle,
          contains(
              'https://maven.aliyun.com/nexus/content/repositories/releases/'));
      expect(rootGradle, contains('https://developer.huawei.com/repo/'));
      expect(manifest, contains('com.alibaba.app.appkey'));
      expect(manifest, contains('com.alibaba.app.appsecret'));
      expect(manifest, contains('.NontoAliyunPushMessageReceiver'));
      expect(manifest, contains('com.aliyun.ams.push.PushPopupActivity'));
      expect(manifest, contains('com.alibaba.sdk.android.push.RECEIVE'));
      expect(manifest, contains('com.huawei.hms.client.appid'));
      expect(manifest, contains('com.oppo.push.key'));
      expect(manifest, contains('com.vivo.push.app_id'));
      expect(gradle, contains('aliyunPushProperty("aliyun.push.appKey")'));
      expect(gradle, contains('"ALIYUN_PUSH_APP_KEY" to aliyunPushAppKey'));
      expect(gradle, contains('"HUAWEI_PUSH_APP_ID" to'));
      expect(gradle, contains(r'appid=$huaweiPushAppId'));
      expect(manifest, isNot(contains('JPUSH_')));
      expect(gradle, isNot(contains('manifestPlaceholders["HUAWEI_APPID"]')));
      expect(gradle, isNot(contains('apply(plugin = "com.huawei.agconnect")')));
      expect(
          gradle,
          isNot(contains(
              'implementation("com.huawei.agconnect:agconnect-core:')));
    });

    test(
        'settings expose vendor notification guidance without keepalive claims',
        () {
      final settings = read('lib/screens/profile/settings_screen.dart');
      final guide =
          read('lib/screens/profile/background_permission_guide_screen.dart');

      expect(settings, contains('厂商推送通知设置'));
      expect(settings, contains('影响后台和应用被结束后的厂商推送送达'));
      expect(settings, isNot(contains('foreground_keepalive_enabled')));
      expect(settings, isNot(contains('后台消息保活')));
      expect(settings, isNot(contains('_keepaliveEnabled')));
      expect(guide, contains('厂商推送'));
      expect(guide, contains('不用于维持 WebSocket 连接'));
      expect(guide, isNot(contains('关闭电池优化')));
      expect(guide, isNot(contains('后台 WebSocket')));
      expect(guide, isNot(contains('保持 WebSocket')));
    });
  });
}
