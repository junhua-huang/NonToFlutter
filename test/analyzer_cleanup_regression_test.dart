import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('analyzer cleanup regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('explore notifier keeps comic fallback responses strongly typed', () {
      final source = read('lib/providers/explore_notifier.dart');

      expect(source, contains('ApiResponse<ComicEventsPage>(success: false)'));
      expect(
        'ApiResponse<ComicEventsPage>(success: false)'
            .allMatches(source)
            .length,
        2,
      );
      expect(source, isNot(contains('_parseComicEvents')));
    });

    test('low-risk analyzer cleanup removes stale imports and redundant casts',
        () {
      final communityNotifier = read('lib/providers/community_notifier.dart');
      final postModel = read('lib/models/post.dart');
      final comicDetail = read('lib/screens/comic/comic_detail_page.dart');
      final comicMyEvents = read('lib/screens/comic/comic_my_events_page.dart');
      final comicTimeline = read('lib/screens/comic/comic_timeline_page.dart');
      final comicUpload = read('lib/screens/comic/comic_upload_page.dart');
      final communityDetail =
          read('lib/screens/community/community_detail_screen.dart');

      expect(communityNotifier,
          isNot(contains("import 'package:flutter/foundation.dart';")));
      expect(postModel, isNot(contains('userJson as Map<String, dynamic>')));
      expect(
          comicDetail,
          isNot(contains(
              "import 'package:nonto/providers/auth_notifier.dart';")));
      expect(
          comicDetail,
          isNot(contains(
              "import 'package:flutter_riverpod/flutter_riverpod.dart';")));
      expect(comicMyEvents,
          isNot(contains("import 'package:nonto/config/app_config.dart';")));
      expect(comicTimeline,
          isNot(contains("import 'package:nonto/config/app_config.dart';")));
      expect(
          comicTimeline,
          isNot(contains(
              "import 'package:nonto/screens/comic/comic_detail_page.dart';")));
      expect(comicUpload,
          isNot(contains("import 'package:cross_file/cross_file.dart';")));
      expect(comicUpload,
          isNot(contains("import 'package:nonto/config/app_config.dart';")));
      expect(comicUpload,
          isNot(contains("import 'package:nonto/utils/image_utils.dart';")));
      expect(communityDetail, isNot(contains('_handleMenuAction(v, c!)')));
      expect(communityDetail, isNot(contains('_buildMenuItems(c!)')));
    });

    test('second cleanup slice removes obvious lints without behavior changes',
        () {
      final themeNotifier = read('lib/providers/theme_notifier.dart');
      final profileSearch = read('lib/providers/profile_search_notifiers.dart');
      final topics = read('lib/screens/topics/my_topics_screen.dart');
      final uploadService = read('lib/services/api/upload_service.dart');
      final appTransitions = read('lib/utils/app_transitions.dart');
      final imageUtils = read('lib/utils/image_utils.dart');
      final imageCompressor = read('lib/utils/image_compressor.dart');
      final chatSendQueue = read('lib/services/chat_send_queue.dart');
      final communityChat =
          read('lib/screens/community/community_chat_screen.dart');

      expect(themeNotifier,
          isNot(contains('ThemeMode.system  => ThemeMode.light')));
      final searchNotifierSource = profileSearch.substring(
        profileSearch.indexOf('class SearchNotifier'),
      );
      expect(searchNotifierSource, isNot(contains('void dispose()')));
      expect(topics, isNot(contains('topic.postCount ?? 0')));
      expect(topics, isNot(contains('topic.followerCount ?? 0')));
      expect(uploadService, isNot(contains("import 'dart:typed_data';")));
      expect(appTransitions,
          isNot(contains("import 'package:flutter/foundation.dart';")));
      expect(imageCompressor, isNot(contains("import 'dart:typed_data';")));
      expect(imageUtils, isNot(contains('user.initials ??')));
      expect(imageUtils, isNot(contains(r"'${url}${sep}t=$cacheTs'")));
      expect(chatSendQueue, isNot(contains(r"${entry.retries}/${maxRetries}")));
      expect(chatSendQueue, isNot(contains('{this.retries = 0}')));
      expect(
          communityChat,
          isNot(contains(
              'if (mounted) ScaffoldMessenger.of(context).showSnackBar')));
    });

    test('community cleanup slice removes local analyzer-only issues', () {
      final communityList =
          read('lib/screens/community/community_list_screen.dart');
      final communityManage =
          read('lib/screens/community/community_manage_screen.dart');

      expect(communityList, isNot(contains('Widget _MyCommunityCard')));
      expect(communityList, contains('Widget _buildMyCommunityCard'));
      expect(
          communityList, isNot(contains('final theme = Theme.of(context);')));
      expect(communityList,
          isNot(contains('child: Container(\n        width: 80')));
      expect(communityManage,
          isNot(contains('if (ctx.mounted) ScaffoldMessenger.of(ctx)')));
      expect(communityManage,
          isNot(contains('if (_loadingRequests)\n      return')));
      expect(communityManage, isNot(contains("if (_requests.isEmpty) return")));
      expect(communityManage,
          isNot(contains('if (_loadingMembers)\n      return')));
      expect(
          communityManage,
          isNot(
              contains('if (mounted)\n        ScaffoldMessenger.of(context)')));
      expect(communityManage, isNot(contains('if (dt == null) return')));
    });

    test('app-owned service cleanup removes remaining simple analyzer issues',
        () {
      final pubspec = read('pubspec.yaml');
      final directDependencies = pubspec.substring(
        pubspec.indexOf('dependencies:'),
        pubspec.indexOf('dependency_overrides:'),
      );
      final appDatabase = read('lib/services/database/app_database.dart');
      final localDb = read('lib/services/local_db_service.dart');

      expect(directDependencies, contains('  path: ^1.9.1'));
      expect(directDependencies, contains('  google_fonts: ^6.2.1'));
      expect(directDependencies, contains('  audioplayers: ^5.2.1'));
      expect(directDependencies, contains('  path_provider:'));
      expect(directDependencies, contains('  flutter_social_video:'));
      expect(appDatabase, contains('AppDatabase._(super.e);'));
      expect(localDb, isNot(contains('print(')));
      expect(localDb, isNot(contains('_preloadSingleConversation')));
    });

    test('web-only implementations keep scoped analyzer ignores explicit', () {
      final soundPlayerWeb = read('lib/services/sound_player_web.dart');
      final webUtilsWeb = read('lib/services/web_utils_web.dart');

      expect(soundPlayerWeb, contains("import 'dart:html' as html;"));
      expect(webUtilsWeb, contains("import 'dart:html' as html;"));
      expect(
        soundPlayerWeb,
        contains(
          '// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use',
        ),
      );
      expect(
        webUtilsWeb,
        contains(
          '// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use',
        ),
      );
    });

    test('local package cleanup removes remaining analyzer-only noise', () {
      final imageCropper =
          read('packages/image_cropper_plus/lib/image_cropper_plus.dart');
      final cropPage =
          read('packages/image_cropper_plus/lib/src/crop_page.dart');
      final reliableWebsocket =
          read('packages/reliable_websocket/lib/reliable_websocket.dart');
      final protocolMessage =
          read('packages/reliable_websocket/lib/src/protocol/message.dart');
      final reliableReceiver = read(
          'packages/reliable_websocket/lib/src/receiver/reliable_receiver.dart');
      final sharePlus =
          read('packages/share_plus_ohos/lib/share_plus_ohos.dart');
      final videoCompress =
          read('packages/video_compress_ohos/lib/video_compress_ohos.dart');
      final videoPlayer =
          read('packages/video_player_ohos/lib/video_player_ohos.dart');
      final videoPlatform =
          read('packages/video_player_ohos/lib/src/platform_interface.dart');
      final videoPlatformNative =
          read('packages/video_player_ohos/lib/src/platform_native.dart');
      final videoPlatformStub =
          read('packages/video_player_ohos/lib/src/platform_stub.dart');
      final videoThumbnail =
          read('packages/video_thumbnail_ohos/lib/video_thumbnail_ohos.dart');

      expect(imageCropper, contains('library;'));
      expect(imageCropper, isNot(contains('library image_cropper_plus')));
      expect(cropPage, isNot(contains("import 'dart:typed_data';")));
      expect(cropPage, isNot(contains('_activePointerId')));
      expect(reliableWebsocket, contains('library;'));
      expect(reliableWebsocket, isNot(contains('library reliable_websocket')));
      expect(protocolMessage, contains('payload ??='));
      expect(reliableReceiver, contains('// ignore: unused_element'));
      expect(sharePlus, contains('library;'));
      expect(videoCompress, contains('library;'));
      expect(videoPlayer, contains('library;'));
      expect(videoPlatform, isNot(contains('_textureId')));
      expect(videoPlatformNative, isNot(contains('/// 原生平台实现')));
      expect(videoPlatformStub, isNot(contains('/// 平台桩')));
      expect(videoThumbnail, contains('library;'));
      expect(videoThumbnail, isNot(contains("import 'dart:typed_data';")));
    });
  });
}
