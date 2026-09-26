import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/comment_notifier.dart';
import 'package:nonto/providers/feed_notifier.dart';
import 'package:nonto/providers/profile_search_notifiers.dart';
import 'package:nonto/services/api/block_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';

class BlockActionResult {
  final bool success;
  final String? error;
  final List<int> removedConversationIds;

  const BlockActionResult._(
    this.success, {
    this.error,
    this.removedConversationIds = const [],
  });

  const BlockActionResult.success({List<int> removedConversationIds = const []})
      : this._(true, removedConversationIds: removedConversationIds);

  const BlockActionResult.failure(String error) : this._(false, error: error);
}

class BlockCoordinator {
  final BlockApi api;
  final Future<void> Function(int userId) removePosts;
  final void Function(int userId) removeComments;
  final Future<List<int>> Function(int userId) removeConversations;
  final void Function(int conversationId) invalidateConversationMessages;
  final Future<void> Function(int userId) invalidateProfile;
  final Map<int, Future<BlockActionResult>> _inFlightBlocks = {};

  BlockCoordinator({
    required this.api,
    required this.removePosts,
    required this.removeComments,
    required this.removeConversations,
    required this.invalidateConversationMessages,
    required this.invalidateProfile,
  });

  Future<BlockActionResult> blockUser(int userId) {
    final existing = _inFlightBlocks[userId];
    if (existing != null) return existing;

    final operation = _blockUser(userId);
    _inFlightBlocks[userId] = operation;
    operation.whenComplete(() {
      if (identical(_inFlightBlocks[userId], operation)) {
        _inFlightBlocks.remove(userId);
      }
    });
    return operation;
  }

  Future<BlockActionResult> _blockUser(int userId) async {
    try {
      final response = await api.blockUser(userId);
      if (!response.success) {
        return BlockActionResult.failure(response.message ?? '屏蔽失败');
      }
    } catch (_) {
      return const BlockActionResult.failure('网络错误，请稍后重试');
    }

    var cleanupFailed = false;
    Future<void> attempt(FutureOr<void> Function() cleanup) async {
      try {
        await cleanup();
      } catch (_) {
        cleanupFailed = true;
      }
    }

    final removedConversationIds = <int>[];
    await attempt(() => removePosts(userId));
    await attempt(() => removeComments(userId));
    await attempt(() async {
      removedConversationIds.addAll(await removeConversations(userId));
    });
    for (final conversationId in removedConversationIds) {
      await attempt(() => invalidateConversationMessages(conversationId));
    }
    await attempt(() => invalidateProfile(userId));

    if (cleanupFailed) {
      return const BlockActionResult.failure(
        '已屏蔽，但本地内容清理失败，请刷新后重试',
      );
    }
    return BlockActionResult.success(
      removedConversationIds: removedConversationIds,
    );
  }
}

final blockApiProvider = Provider<BlockApi>((ref) => BlockService());

Future<void> invalidateBlockedUserProfileCache(
  int userId, {
  DataLayer? dataLayer,
}) async {
  final cache = dataLayer ?? DataLayer();
  await cache.invalidate(CacheKeys.userProfile(userId));
  await cache.invalidate(CacheKeys.userPosts(userId));
  await cache.invalidate('${CacheKeys.userPosts(userId)}:*');
  await cache.invalidate(CacheKeys.userLiked(userId));
  await cache.invalidate(CacheKeys.userLikeCount(userId));
}

final blockCoordinatorProvider = Provider<BlockCoordinator>((ref) {
  return BlockCoordinator(
    api: ref.watch(blockApiProvider),
    removePosts: ref.read(feedProvider.notifier).removePostsByUser,
    removeComments: CommentNotifier.removeUserFromActiveSections,
    removeConversations: ref
        .read(conversationsProvider.notifier)
        .removeDirectConversationsWithUser,
    invalidateConversationMessages: (conversationId) {
      ref.invalidate(messagesProvider(conversationId));
    },
    invalidateProfile: (userId) async {
      ref.invalidate(profileProvider(userId));
      await invalidateBlockedUserProfileCache(userId);
    },
  );
});

class BlockedUsersState {
  final List<User> users;
  final bool isLoading;
  final String? error;
  final Set<int> unblockingUserIds;
  final String? actionError;

  const BlockedUsersState({
    this.users = const [],
    this.isLoading = true,
    this.error,
    this.unblockingUserIds = const {},
    this.actionError,
  });

  BlockedUsersState copyWith({
    List<User>? users,
    bool? isLoading,
    String? error,
    bool clearError = false,
    Set<int>? unblockingUserIds,
    String? actionError,
    bool clearActionError = false,
  }) {
    return BlockedUsersState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      unblockingUserIds: unblockingUserIds ?? this.unblockingUserIds,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }
}

class BlockedUsersNotifier extends StateNotifier<BlockedUsersState> {
  final BlockApi _api;
  int _loadGeneration = 0;
  int _successfulUnblockVersion = 0;
  final Map<int, int> _unblockedAtVersion = {};

  BlockedUsersNotifier(
    this._api, {
    BlockedUsersState initialState = const BlockedUsersState(),
    bool loadOnInit = true,
  }) : super(initialState) {
    if (loadOnInit) load();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final unblockVersionAtStart = _successfulUnblockVersion;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearActionError: true,
    );
    try {
      final response = await _api.getBlockedUsers(page: 1, perPage: 100);
      if (generation != _loadGeneration) return;
      if (!response.success) {
        state = state.copyWith(
          isLoading: false,
          error: response.message ?? '加载失败',
        );
        return;
      }
      final rawData = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final rawList = rawData is List
          ? rawData
          : rawData is Map
              ? (rawData['blocked_users'] ??
                  rawData['blocks'] ??
                  rawData['users'] ??
                  const [])
              : const [];
      final users = (rawList as List).whereType<Map>().map((entry) {
        final map = Map<String, dynamic>.from(entry);
        final user = map['user'];
        return User.fromJson(
          user is Map ? Map<String, dynamic>.from(user) : map,
        );
      }).where((user) {
        final unblockedAtVersion = _unblockedAtVersion[user.id];
        return unblockedAtVersion == null ||
            unblockedAtVersion <= unblockVersionAtStart;
      }).toList();
      state = state.copyWith(users: users, isLoading: false, clearError: true);
    } catch (_) {
      if (generation == _loadGeneration) {
        state = state.copyWith(isLoading: false, error: '网络错误，请稍后重试');
      }
    }
  }

  Future<BlockActionResult> unblock(int userId) async {
    if (state.unblockingUserIds.contains(userId)) {
      return const BlockActionResult.failure('操作进行中');
    }
    state = state.copyWith(
      unblockingUserIds: {...state.unblockingUserIds, userId},
      clearActionError: true,
    );
    try {
      final response = await _api.unblockUser(userId);
      if (!response.success) {
        final error = response.message ?? '取消屏蔽失败';
        state = state.copyWith(actionError: error);
        return BlockActionResult.failure(error);
      }
      _successfulUnblockVersion++;
      _unblockedAtVersion[userId] = _successfulUnblockVersion;
      state = state.copyWith(
        users: state.users.where((user) => user.id != userId).toList(),
      );
      return const BlockActionResult.success();
    } catch (_) {
      const error = '网络错误，请稍后重试';
      state = state.copyWith(actionError: error);
      return const BlockActionResult.failure(error);
    } finally {
      state = state.copyWith(
        unblockingUserIds: {...state.unblockingUserIds}..remove(userId),
      );
    }
  }
}

final blockedUsersProvider =
    StateNotifierProvider<BlockedUsersNotifier, BlockedUsersState>((ref) {
  return BlockedUsersNotifier(ref.watch(blockApiProvider));
});
