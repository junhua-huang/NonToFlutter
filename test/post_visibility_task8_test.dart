import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/request_manager.dart';

void main() {
  group('Task 8 post visibility behavior', () {
    test('post visibility exposes exactly public and friends', () {
      expect(
        PostVisibility.values.map((value) => value.name),
        <String>['public', 'friends'],
      );
      expect(
        postVisibilityOptions
            .map((option) => (option.value, option.label))
            .toList(),
        <(String, String)>[
          ('public', '公开'),
          ('friends', '仅好友'),
        ],
      );
    });

    test('saved post defaults normalize aliases and fail safe to public', () {
      expect(normalizeDefaultPostVisibility('public'), 'public');
      expect(normalizeDefaultPostVisibility('friends'), 'friends');
      expect(normalizeDefaultPostVisibility('friends_only'), 'friends');
      expect(normalizeDefaultPostVisibility('private'), 'public');
      expect(normalizeDefaultPostVisibility('custom'), 'public');
      expect(normalizeDefaultPostVisibility('unexpected'), 'public');
      expect(normalizeDefaultPostVisibility(null), 'public');
    });

    test('legacy nonpublic posts edit as friends without broadening', () {
      expect(normalizePostVisibilityForEdit('public'), 'public');
      expect(normalizePostVisibilityForEdit('friends'), 'friends');
      expect(normalizePostVisibilityForEdit('friends_only'), 'friends');
      expect(normalizePostVisibilityForEdit('private'), 'friends');
      expect(normalizePostVisibilityForEdit('custom'), 'friends');
      expect(normalizePostVisibilityForEdit('unexpected'), 'friends');
      expect(normalizePostVisibilityForEdit(null), 'public');
      expect(
        normalizePostVisibilityForEdit(null, legacyIsPublic: false),
        'friends',
      );
    });

    test('create and update payloads omit category and custom audience fields',
        () {
      final createPayload = PostService.buildMutationData(
        content: 'hello',
        visibility: 'friends',
        imageUrls: const <String>['https://example.com/image.jpg'],
        displayRoleType: 'coser',
      );
      final updatePayload = PostService.buildMutationData(
        content: 'updated',
        visibility: 'public',
      );

      for (final payload in <Map<String, dynamic>>[
        createPayload,
        updatePayload,
      ]) {
        expect(payload, isNot(contains('content_category')));
        expect(payload, isNot(contains('visible_user_ids')));
        expect(payload, isNot(contains('is_public')));
      }
      expect(createPayload['visibility'], 'friends');
      expect(updatePayload['visibility'], 'public');
    });
  });

  group('Task 8 completed-result cache invalidation behavior', () {
    test('invalidating a completed key forces the next read to execute',
        () async {
      final manager = RequestManager(ttl: const Duration(minutes: 1));
      var executions = 0;

      Future<int> read() => manager.execute(
            key: 'GET:/auth/privacy',
            task: () async => ++executions,
          );

      expect(await read(), 1);
      expect(await read(), 1);
      manager.invalidate('GET:/auth/privacy');

      expect(await read(), 2);
    });

    test('old TTL cleanup cannot evict a replacement after invalidation',
        () async {
      final manager = RequestManager(ttl: const Duration(milliseconds: 300));
      var executions = 0;

      Future<int> read() => manager.execute(
            key: 'GET:/posts/42',
            task: () async => ++executions,
          );

      expect(await read(), 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      manager.invalidate('GET:/posts/42');
      expect(await read(), 2);

      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(await read(), 2);
    });

    test('invalidating post read prefixes preserves unrelated caches',
        () async {
      final manager = RequestManager(ttl: const Duration(minutes: 1));
      var detailExecutions = 0;
      var feedExecutions = 0;
      var privacyExecutions = 0;

      Future<int> read(String key, int Function() increment) => manager.execute(
            key: key,
            task: () async => increment(),
          );

      expect(
        await read('GET:/posts/42', () => ++detailExecutions),
        1,
      );
      expect(
        await read('GET:/posts/?page=1&per_page=20', () => ++feedExecutions),
        1,
      );
      expect(
        await read('GET:/auth/privacy', () => ++privacyExecutions),
        1,
      );

      manager.invalidateWhere(
        (key) => key == 'GET:/posts/42' || key.startsWith('GET:/posts/?'),
      );

      expect(
        await read('GET:/posts/42', () => ++detailExecutions),
        2,
      );
      expect(
        await read('GET:/posts/?page=1&per_page=20', () => ++feedExecutions),
        2,
      );
      expect(
        await read('GET:/auth/privacy', () => ++privacyExecutions),
        1,
      );
    });
  });

  group('Task 8 partial edit response merge behavior', () {
    late Post original;

    setUp(() {
      original = Post(
        id: 42,
        content: 'before',
        videoUrl: 'https://example.com/video.mp4',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        postType: 'video',
        displayRoleType: 'coser',
        displayRoleLabel: 'Coser',
        userId: 7,
        visibility: 'friends',
        isPublic: false,
        user: User(
          id: 7,
          username: 'owner',
          email: 'owner@example.com',
        ),
        likeCount: 3,
        commentCount: 4,
        viewCount: 5,
        isLiked: true,
        createdAt: DateTime.parse('2026-01-02T03:04:05Z'),
        updatedAt: DateTime.parse('2026-01-03T03:04:05Z'),
        topics: const <String>['flutter'],
        images: const <String>['https://example.com/image.jpg'],
        communityId: 9,
        communityOnly: true,
      );
    });

    test('absent edit response fields preserve the original post', () {
      final merged = original.mergeJson(<String, dynamic>{
        'id': 42,
        'content': 'after',
        'visibility': 'public',
      });

      expect(merged.content, 'after');
      expect(merged.visibility, 'public');
      expect(merged.userId, original.userId);
      expect(merged.user, same(original.user));
      expect(merged.viewCount, original.viewCount);
      expect(merged.images, original.images);
      expect(merged.videoUrl, original.videoUrl);
      expect(merged.thumbnailUrl, original.thumbnailUrl);
      expect(merged.createdAt, original.createdAt);
      expect(merged.communityId, original.communityId);
    });

    test('explicit null clears nullable fields while absence preserves them',
        () {
      final merged = original.mergeJson(<String, dynamic>{
        'id': 42,
        'video_url': null,
        'images': null,
        'author': null,
        'community_id': null,
      });

      expect(merged.videoUrl, isNull);
      expect(merged.images, isNull);
      expect(merged.user, isNull);
      expect(merged.communityId, isNull);
      expect(merged.thumbnailUrl, original.thumbnailUrl);
      expect(merged.createdAt, original.createdAt);
    });
  });

  group('Task 8 post and settings source behavior', () {
    final projectRoot = Directory.current.path;
    String read(String relativePath) =>
        File('$projectRoot/$relativePath').readAsStringSync();

    test('post composer has canonical visibility and no category selector', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('postVisibilityOptions'));
      expect(source, contains('normalizeDefaultPostVisibility'));
      expect(source, contains('normalizePostVisibilityForEdit'));
      expect(source, contains('post_default_visibility'));
      expect(source, contains('visibility: _selectedVisibility'));
      final canSubmitStart = source.indexOf('bool get _canSubmitPost =>');
      final canSubmitEnd = source.indexOf('bool get _isEditing', canSubmitStart);
      expect(canSubmitStart, greaterThanOrEqualTo(0));
      expect(canSubmitEnd, greaterThan(canSubmitStart));
      expect(
        source.substring(canSubmitStart, canSubmitEnd),
        isNot(contains('_isDefaultVisibilityLoading')),
      );
      expect(source, isNot(contains('_contentCategories')));
      expect(source, isNot(contains('_selectedContentCategory')));
      expect(source, isNot(contains('contentCategory:')));
      expect(source, isNot(contains('visibleUserIds')));
      expect(source, isNot(contains('visible_user_ids')));
    });

    test('post create and edit screens contain no category labels or filter',
        () {
      final postScreenDirectory = Directory('$projectRoot/lib/screens/post');
      final source = postScreenDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(source, isNot(contains("'作品'")));
      expect(source, isNot(contains("'日常'")));
      expect(source, isNot(contains("'Cosplay'")));
      expect(source, isNot(contains("'活动'")));
      expect(source, isNot(contains('content_category')));
      expect(source, isNot(contains('contentCategory')));
    });

    test('post service signatures have no category or custom audience inputs',
        () {
      final source = read('lib/services/api/post_service.dart');

      expect(source, isNot(contains('contentCategory')));
      expect(source, isNot(contains('content_category')));
      expect(source, isNot(contains('visibleUserIds')));
      expect(source, isNot(contains('visible_user_ids')));
      expect(source, isNot(contains('is_public')));
      expect(source, contains('required String visibility'));
    });

    test('default post settings picker uses canonical public and friends only',
        () {
      final source = read('lib/screens/profile/settings_screen.dart');
      final postSettingsStart = source.indexOf("_buildSettingsSection('帖子'");
      final socialSettingsStart = source.indexOf(
        "_buildSettingsSection('社交'",
        postSettingsStart,
      );
      expect(postSettingsStart, greaterThanOrEqualTo(0));
      expect(socialSettingsStart, greaterThan(postSettingsStart));

      final postSettings = source.substring(
        postSettingsStart,
        socialSettingsStart,
      );
      expect(postSettings, contains("_Option('public', '公开'"));
      expect(postSettings, contains("_Option('friends', '仅好友'"));
      expect(postSettings, isNot(contains('friends_only')));
      expect(postSettings, isNot(contains("_Option('private'")));
      expect(postSettings, isNot(contains("_Option('custom'")));
      expect(source, contains('normalizeDefaultPostVisibility'));
    });

    test('edit action opens composer and only saves on explicit submit', () {
      final detailSource = read('lib/screens/post/post_detail_screen.dart');
      final composerSource = read('lib/screens/post/create_post_screen.dart');

      expect(detailSource, contains("label: '编辑'"));
      expect(detailSource, contains('CreatePostScreen(post: post)'));
      expect(composerSource, contains('widget.post != null'));
      expect(composerSource, contains('PostService().updatePost('));
      final initStateStart = composerSource.indexOf('void initState()');
      final disposeStart =
          composerSource.indexOf('void dispose()', initStateStart);
      expect(initStateStart, greaterThanOrEqualTo(0));
      expect(disposeStart, greaterThan(initStateStart));
      expect(
        composerSource.substring(initStateStart, disposeStart),
        isNot(contains('updatePost(')),
      );
    });

    test('successful mutations invalidate their completed GET cache domains',
        () {
      final authSource = read('lib/services/api/auth_service.dart');
      final postSource = read('lib/services/api/post_service.dart');

      expect(authSource, contains("_api.cancelGet('/auth/privacy')"));
      expect(postSource, contains("_api.cancelGet('/posts/\$postId')"));
      expect(postSource, contains("key.startsWith('GET:/posts/?')"));
      expect(
        postSource,
        contains("key.startsWith('GET:/posts/user/')"),
      );
      expect(
        postSource,
        contains("key.startsWith('GET:/recommendations/feed?')"),
      );
    });

    test('edit screen merges partial response over the original post', () {
      final source = read('lib/screens/post/create_post_screen.dart');
      final updateStart = source.indexOf('Future<void> _updatePost');
      final extractUrlStart =
          source.indexOf('String? _extractUrl', updateStart);
      expect(updateStart, greaterThanOrEqualTo(0));
      expect(extractUrlStart, greaterThan(updateStart));

      final updateSource = source.substring(updateStart, extractUrlStart);
      expect(updateSource, contains('widget.post!.mergeJson('));
      expect(updateSource, isNot(contains('Post.fromJson(')));
    });
  });
}
