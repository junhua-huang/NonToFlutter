import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/comment.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/blocking_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/comment_notifier.dart';
import 'package:nonto/providers/comment_state.dart';
import 'package:nonto/providers/feed_notifier.dart';
import 'package:nonto/screens/profile/blocked_users_screen.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/block_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';

Post _post(int id, int userId) => Post(id: id, userId: userId);

Comment _comment(int id, int userId, {List<Comment> replies = const []}) =>
    Comment(
      id: id,
      content: 'comment $id',
      userId: userId,
      postId: 1,
      replies: replies,
      replyCount: replies.length,
    );

User _user(int id) => User(
      id: id,
      username: 'user$id',
      email: 'user$id@example.com',
      displayName: 'User $id',
    );

Conversation _direct(int id, int userId) => Conversation(
      id: id,
      user1Id: 1,
      user2Id: userId,
      otherUser: _user(userId),
    );

Conversation _community(int id) => Conversation(
      id: id,
      user1Id: 0,
      user2Id: 0,
      type: 'community',
      communityId: 88,
      communityName: 'Community',
      otherUser: _user(42),
    );

class _FakeBlockApi implements BlockApi {
  _FakeBlockApi({
    this.blockResponse,
    this.unblockResponse,
    this.listResponse,
  });

  ApiResponse? blockResponse;
  ApiResponse? unblockResponse;
  ApiResponse? listResponse;
  int unblockCalls = 0;

  @override
  Future<ApiResponse> blockUser(int userId) async {
    return blockResponse ?? ApiResponse(success: true);
  }

  @override
  Future<ApiResponse> unblockUser(int userId) async {
    unblockCalls++;
    return unblockResponse ?? ApiResponse(success: true);
  }

  @override
  Future<ApiResponse> getBlockedUsers({int page = 1, int perPage = 20}) async {
    return listResponse ??
        ApiResponse(success: true, data: {'blocked_users': []});
  }
}

void main() {
  group('blocking state filters', () {
    test('feed removes only target posts and persists an empty result',
        () async {
      final dataLayer = DataLayer();
      await dataLayer.write(CacheKeys.feedPosts, [
        _post(1, 42).toJson(),
        _post(2, 7).toJson(),
      ]);
      final notifier = FeedNotifier(
        initialState: FeedState(
          posts: [_post(1, 42), _post(2, 7)],
          isInitialLoading: false,
        ),
        dataLayer: dataLayer,
        loadOnInit: false,
      );

      await notifier.removePostsByUser(42);

      expect(notifier.state.posts.map((post) => post.id), [2]);
      await notifier.removePostsByUser(7);
      final cached =
          await dataLayer.query(CacheKeys.feedPosts, () async => null);
      expect(notifier.state.posts, isEmpty);
      expect(cached.data, isA<List>());
      expect(cached.data as List, isEmpty,
          reason:
              'the old non-empty feed cache must not rehydrate blocked posts');
    });

    test('comments remove target parents and target replies recursively', () {
      final notifier = CommentNotifier(
        const CommentSectionKey(targetType: 'post', targetId: 1),
        initialState: CommentState(
          isLoading: false,
          comments: [
            _comment(1, 42, replies: [_comment(11, 7)]),
            _comment(2, 7, replies: [
              _comment(21, 42),
              _comment(22, 8, replies: [_comment(221, 42)]),
            ]),
          ],
        ),
        loadOnInit: false,
      );

      notifier.removeCommentsByUser(42);

      expect(notifier.state.comments.map((comment) => comment.id), [2]);
      expect(notifier.state.comments.single.replies.map((reply) => reply.id),
          [22]);
      expect(notifier.state.comments.single.replies.single.replies, isEmpty);
      expect(notifier.state.comments.single.replyCount, 1);
      notifier.dispose();
    });

    test('conversation removal affects matching direct chats only', () async {
      final notifier = ConversationsNotifier(
        initialState: ConversationsState(
          isLoading: false,
          conversations: [
            _direct(10, 42),
            _direct(11, 7),
            _community(12),
          ],
        ),
        loadOnInit: false,
      );

      final removed = await notifier.removeDirectConversationsWithUser(42);

      expect(removed, [10]);
      expect(
          notifier.state.conversations.map((conversation) => conversation.id),
          [11, 12]);
      notifier.dispose();
    });

    test('conversation removal invalidates the user-scoped message cache',
        () async {
      const conversationId = 1010;
      final userScopedKey =
          CacheKeys.msgRecentByUser(conversationId, 'current-user');
      await DataLayer().write(userScopedKey, const ['stale message']);
      final notifier = ConversationsNotifier(
        initialState: ConversationsState(
          isLoading: false,
          conversations: [_direct(conversationId, 42)],
        ),
        loadOnInit: false,
      );

      await notifier.removeDirectConversationsWithUser(42);

      final cached = await DataLayer().query(userScopedKey, () async => null);
      expect(cached.data, isNull,
          reason: 'a removed direct chat must not survive in user cache');
      notifier.dispose();
    });
  });

  group('block coordinator', () {
    test('API failure does not run any destructive client side effect',
        () async {
      final api = _FakeBlockApi(
        blockResponse: ApiResponse(success: false, message: 'server rejected'),
      );
      var sideEffectCalls = 0;
      final coordinator = BlockCoordinator(
        api: api,
        removePosts: (_) async => sideEffectCalls++,
        removeComments: (_) => sideEffectCalls++,
        removeConversations: (_) async {
          sideEffectCalls++;
          return [10];
        },
        invalidateConversationMessages: (_) => sideEffectCalls++,
        invalidateProfile: (_) async => sideEffectCalls++,
      );

      final result = await coordinator.blockUser(42);

      expect(result.success, isFalse);
      expect(result.error, 'server rejected');
      expect(sideEffectCalls, 0);
    });

    test('concurrent blocks for the same user share one operation', () async {
      final response = Completer<ApiResponse>();
      final api = _PendingBlockApi(response.future);
      final cleanupCalls = <String>[];
      final coordinator = BlockCoordinator(
        api: api,
        removePosts: (id) async => cleanupCalls.add('posts:$id'),
        removeComments: (id) => cleanupCalls.add('comments:$id'),
        removeConversations: (id) async {
          cleanupCalls.add('conversations:$id');
          return [10];
        },
        invalidateConversationMessages: (id) =>
            cleanupCalls.add('messages:$id'),
        invalidateProfile: (id) async => cleanupCalls.add('profile:$id'),
      );

      final first = coordinator.blockUser(42);
      final second = coordinator.blockUser(42);

      expect(api.blockCalls, 1);
      expect(cleanupCalls, isEmpty);

      response.complete(ApiResponse(success: true));
      final results = await Future.wait([first, second]);

      expect(results.every((result) => result.success), isTrue);
      expect(identical(results.first, results.last), isTrue);
      expect(cleanupCalls, [
        'posts:42',
        'comments:42',
        'conversations:42',
        'messages:10',
        'profile:42',
      ]);
    });

    test('success centralizes all state removal and invalidation', () async {
      final calls = <String>[];
      final coordinator = BlockCoordinator(
        api: _FakeBlockApi(),
        removePosts: (id) async => calls.add('posts:$id'),
        removeComments: (id) => calls.add('comments:$id'),
        removeConversations: (id) async {
          calls.add('conversations:$id');
          return [10, 11];
        },
        invalidateConversationMessages: (id) => calls.add('messages:$id'),
        invalidateProfile: (id) async => calls.add('profile:$id'),
      );

      final result = await coordinator.blockUser(42);

      expect(result.success, isTrue);
      expect(result.removedConversationIds, [10, 11]);
      expect(calls, [
        'posts:42',
        'comments:42',
        'conversations:42',
        'messages:10',
        'messages:11',
        'profile:42',
      ]);
    });

    test('cleanup failures are contained and all reachable cleanup continues',
        () async {
      final calls = <String>[];
      final coordinator = BlockCoordinator(
        api: _FakeBlockApi(),
        removePosts: (id) async {
          calls.add('posts:$id');
          throw StateError('posts cleanup failed');
        },
        removeComments: (id) {
          calls.add('comments:$id');
          throw StateError('comments cleanup failed');
        },
        removeConversations: (id) async {
          calls.add('conversations:$id');
          return [10, 11];
        },
        invalidateConversationMessages: (id) {
          calls.add('messages:$id');
          throw StateError('message cleanup failed');
        },
        invalidateProfile: (id) async {
          calls.add('profile:$id');
          throw StateError('profile cleanup failed');
        },
      );

      final result = await coordinator.blockUser(42);

      expect(result.success, isFalse);
      expect(result.error, '已屏蔽，但本地内容清理失败，请刷新后重试');
      expect(calls, [
        'posts:42',
        'comments:42',
        'conversations:42',
        'messages:10',
        'messages:11',
        'profile:42',
      ]);
    });

    test('profile invalidation clears the cache consumed by loadLikes',
        () async {
      const userId = 424242;
      final dataLayer = DataLayer();
      final likedCacheKey = CacheKeys.userLikeCount(userId);
      await dataLayer.write(likedCacheKey, 99);

      await invalidateBlockedUserProfileCache(userId, dataLayer: dataLayer);

      final cached = await dataLayer.query(likedCacheKey, () async => null);
      expect(likedCacheKey, 'user:$userId:likes');
      expect(cached.data, isNull);
    });

    test('profile cleanup still runs when conversation cleanup throws',
        () async {
      var profileAttempted = false;
      final coordinator = BlockCoordinator(
        api: _FakeBlockApi(),
        removePosts: (_) async {},
        removeComments: (_) {},
        removeConversations: (_) async => throw StateError('db failed'),
        invalidateConversationMessages: (_) {},
        invalidateProfile: (_) async => profileAttempted = true,
      );

      final result = await coordinator.blockUser(42);

      expect(result.success, isFalse);
      expect(result.error, '已屏蔽，但本地内容清理失败，请刷新后重试');
      expect(profileAttempted, isTrue);
    });
  });

  group('blocked users state', () {
    test('loads blocked users and successful unblock removes the row',
        () async {
      final api = _FakeBlockApi(
        listResponse: ApiResponse(success: true, data: {
          'blocked_users': [_user(42).toJson(), _user(7).toJson()],
        }),
      );
      final notifier = BlockedUsersNotifier(api, loadOnInit: false);
      await notifier.load();

      final result = await notifier.unblock(42);

      expect(result.success, isTrue);
      expect(notifier.state.users.map((user) => user.id), [7]);
      expect(api.unblockCalls, 1);
    });

    test('failed unblock preserves row and exposes an error', () async {
      final api = _FakeBlockApi(
        listResponse: ApiResponse(success: true, data: {
          'blocked_users': [_user(42).toJson()],
        }),
        unblockResponse: ApiResponse(success: false, message: 'cannot unblock'),
      );
      final notifier = BlockedUsersNotifier(api, loadOnInit: false);
      await notifier.load();

      final result = await notifier.unblock(42);

      expect(result.success, isFalse);
      expect(result.error, 'cannot unblock');
      expect(notifier.state.users.map((user) => user.id), [42]);
      expect(notifier.state.actionError, 'cannot unblock');
    });

    test('late pre-unblock load cannot resurrect a successful unblock',
        () async {
      final pendingLoad = Completer<ApiResponse>();
      final api = _PendingBlockedUsersApi([pendingLoad.future]);
      final notifier = BlockedUsersNotifier(
        api,
        initialState: BlockedUsersState(users: [_user(42)], isLoading: false),
        loadOnInit: false,
      );

      final load = notifier.load();
      final unblock = await notifier.unblock(42);
      pendingLoad.complete(ApiResponse(success: true, data: {
        'blocked_users': [_user(42).toJson()],
      }));
      await load;

      expect(unblock.success, isTrue);
      expect(notifier.state.users, isEmpty);
    });

    test('older concurrent load cannot overwrite a newer load result',
        () async {
      final older = Completer<ApiResponse>();
      final newer = Completer<ApiResponse>();
      final api = _PendingBlockedUsersApi([older.future, newer.future]);
      final notifier = BlockedUsersNotifier(api, loadOnInit: false);

      final olderLoad = notifier.load();
      final newerLoad = notifier.load();
      newer.complete(ApiResponse(success: true, data: {
        'blocked_users': [_user(7).toJson()],
      }));
      await newerLoad;
      older.complete(ApiResponse(success: true, data: {
        'blocked_users': [_user(42).toJson()],
      }));
      await olderLoad;

      expect(notifier.state.users.map((user) => user.id), [7]);
    });

    test('suppresses repeated unblock taps while request is pending', () async {
      final completer = Completer<ApiResponse>();
      final api = _PendingUnblockApi(completer.future);
      final notifier = BlockedUsersNotifier(
        api,
        initialState: BlockedUsersState(users: [_user(42)], isLoading: false),
        loadOnInit: false,
      );

      final first = notifier.unblock(42);
      final second = await notifier.unblock(42);
      completer.complete(ApiResponse(success: true));
      await first;

      expect(second.success, isFalse);
      expect(api.unblockCalls, 1);
    });
  });

  group('blocked users widget', () {
    testWidgets('successful unblock removes the visible row', (tester) async {
      final notifier = BlockedUsersNotifier(
        _FakeBlockApi(),
        initialState: BlockedUsersState(
          users: [_user(42), _user(7)],
          isLoading: false,
        ),
        loadOnInit: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blockedUsersProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(home: BlockedUsersScreen()),
        ),
      );

      expect(find.text('User 42'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '取消屏蔽').first);
      await tester.pumpAndSettle();

      expect(find.text('User 42'), findsNothing);
      expect(find.text('User 7'), findsOneWidget);
      expect(find.text('已取消屏蔽 User 42'), findsOneWidget);
    });

    testWidgets('failed unblock keeps the visible row and shows the error',
        (tester) async {
      final notifier = BlockedUsersNotifier(
        _FakeBlockApi(
          unblockResponse: ApiResponse(
            success: false,
            message: 'cannot unblock',
          ),
        ),
        initialState: BlockedUsersState(
          users: [_user(42)],
          isLoading: false,
        ),
        loadOnInit: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blockedUsersProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(home: BlockedUsersScreen()),
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '取消屏蔽'));
      await tester.pumpAndSettle();

      expect(find.text('User 42'), findsOneWidget);
      expect(find.text('cannot unblock'), findsOneWidget);
    });
  });

  test('settings, route, profile and chat keep the block result contract', () {
    final root = Directory.current.path;
    String read(String path) => File('$root/$path').readAsStringSync();
    final settings = read('lib/screens/profile/settings_screen.dart');
    final routes = read('lib/routes/app_routes.dart');
    final generator = read('lib/routes/route_generator.dart');
    final profile = read('lib/screens/profile/user_profile_screen.dart');
    final chat = read('lib/screens/chat/chat_room_screen.dart');
    final postCard = read('lib/widgets/post_card.dart');

    expect(settings, contains('AppRoutes.blockedUsers'));
    expect(routes, contains("blockedUsers = '/blocked-users'"));
    expect(generator, contains('BlockedUsersScreen'));
    expect(profile, contains('UserProfileResult.blocked'));
    expect(profile, contains('blockCoordinatorProvider'));
    expect(chat, contains('await Navigator.push<UserProfileResult>'));
    expect(chat, contains('result == UserProfileResult.blocked'));
    expect(postCard, contains('blockCoordinatorProvider'));
  });
}

class _PendingBlockApi extends _FakeBlockApi {
  _PendingBlockApi(this.pending);

  final Future<ApiResponse> pending;
  int blockCalls = 0;

  @override
  Future<ApiResponse> blockUser(int userId) {
    blockCalls++;
    return pending;
  }
}

class _PendingBlockedUsersApi extends _FakeBlockApi {
  _PendingBlockedUsersApi(this.pendingLoads);

  final List<Future<ApiResponse>> pendingLoads;
  int loadCalls = 0;

  @override
  Future<ApiResponse> getBlockedUsers({int page = 1, int perPage = 20}) {
    return pendingLoads[loadCalls++];
  }
}

class _PendingUnblockApi extends _FakeBlockApi {
  _PendingUnblockApi(this.pending);

  final Future<ApiResponse> pending;

  @override
  Future<ApiResponse> unblockUser(int userId) {
    unblockCalls++;
    return pending;
  }
}
