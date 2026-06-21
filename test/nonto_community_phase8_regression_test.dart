import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('community dynamic publishing and post loading regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('create post screen accepts community context and submits it', () {
      final screen = read('lib/screens/post/create_post_screen.dart');
      final service = read('lib/services/api/post_service.dart');

      expect(screen, contains('final int? communityId;'));
      expect(screen, contains('final String? communityName;'));
      expect(
        screen,
        contains(
          'const CreatePostScreen({super.key, this.communityId, this.communityName});',
        ),
      );
      expect(screen, contains('communityId: widget.communityId'));
      expect(screen, contains('if (widget.communityName != null)'));
      expect(screen, contains(r'发布到 ${widget.communityName}'));

      expect(service, contains('int? communityId,'));
      expect(service,
          contains("if (communityId != null) 'community_id': communityId"));
    });

    test('create post route passes community arguments into composer', () {
      final routes = read('lib/routes/route_generator.dart');

      expect(routes, contains('final createPostArgs = args is Map'));
      expect(routes, contains('CreatePostScreen('));
      expect(routes,
          contains("communityId: createPostArgs?['community_id'] as int?"));
      expect(
        routes,
        contains("communityName: createPostArgs?['community_name'] as String?"),
      );
    });

    test('community detail publishes dynamics then refreshes community posts',
        () {
      final detail = read('lib/screens/community/community_detail_screen.dart');

      expect(detail, contains('Future<void> _navigateToCreatePost'));
      expect(detail, contains('final didPublish = await Navigator.pushNamed'));
      expect(detail, contains("'community_id': community.id"));
      expect(detail, contains("'community_name': community.name"));
      expect(detail, contains('if (didPublish == true)'));
      expect(detail, contains('.loadPosts(widget.communityId'));
    });

    test('latest and hot switching uses posts-only loading state', () {
      final notifier = read('lib/providers/community_notifier.dart');
      final detailStart = notifier.indexOf('class CommunityDetailState');
      final chatStart = notifier.indexOf('class CommunityChatState');
      final detailSource = notifier.substring(detailStart, chatStart);

      expect(detailSource, contains('final bool isPostsLoading;'));
      expect(detailSource, contains('this.isPostsLoading = false,'));
      expect(detailSource, contains('bool? isPostsLoading,'));
      expect(
        detailSource,
        contains('isPostsLoading: isPostsLoading ?? this.isPostsLoading,'),
      );
      expect(detailSource, contains('isPostsLoading: true'));
      expect(detailSource, contains('isPostsLoading: false'));
      expect(detailSource, isNot(contains('state = CommunityDetailState(')));
      expect(
          detailSource,
          isNot(contains(
              'state = state.copyWith(isLoading: true, sortBy: sortBy)')));
    });

    test(
        'community detail keeps current posts visible during latest hot switching',
        () {
      final detail = read('lib/screens/community/community_detail_screen.dart');

      expect(detail, contains('if (state.isPostsLoading)'));
      expect(detail, contains('_buildPostsLoadingIndicator'));
      expect(detail, contains('LinearProgressIndicator'));
      expect(
          detail, isNot(contains('state.isLoading || state.isPostsLoading')));
    });
  });
}
