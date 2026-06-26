import 'package:nonto/models/community.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/api/friend_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';

enum PostShareTargetType { friend, community }

class PostShareTarget {
  final PostShareTargetType type;
  final User? friend;
  final Community? community;
  final int fallbackIndex;

  const PostShareTarget._({
    required this.type,
    required this.fallbackIndex,
    this.friend,
    this.community,
  });

  factory PostShareTarget.friend(User friend, {required int fallbackIndex}) {
    return PostShareTarget._(
      type: PostShareTargetType.friend,
      friend: friend,
      fallbackIndex: fallbackIndex,
    );
  }

  factory PostShareTarget.community(Community community,
      {required int fallbackIndex}) {
    return PostShareTarget._(
      type: PostShareTargetType.community,
      community: community,
      fallbackIndex: fallbackIndex,
    );
  }

  String get stableKey {
    switch (type) {
      case PostShareTargetType.friend:
        return 'friend:${friend?.id ?? 0}';
      case PostShareTargetType.community:
        return 'community:${community?.id ?? 0}';
    }
  }

  String get title {
    switch (type) {
      case PostShareTargetType.friend:
        return friend?.displayName ?? friend?.username ?? '未知好友';
      case PostShareTargetType.community:
        return community?.name ?? '未知社群';
    }
  }

  String get subtitle {
    switch (type) {
      case PostShareTargetType.friend:
        return '好友 · 发送帖子卡片';
      case PostShareTargetType.community:
        return '社群 · 发送帖子卡片';
    }
  }
}

List<User> parsePostShareFriends(dynamic data) {
  final items = _extractPostShareItems(data, const [
    'friends',
    'users',
    'items',
    'data',
  ]);
  return items
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .map(User.fromJson)
      .where((user) => user.id > 0)
      .toList();
}

List<Community> parsePostShareCommunities(dynamic data) {
  final items = _extractPostShareItems(data, const [
    'communities',
    'items',
    'data',
  ]);
  return items
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .map(Community.fromJson)
      .where((community) => community.id > 0)
      .toList();
}

List<dynamic> _extractPostShareItems(dynamic data, List<String> keys) {
  if (data is List) return data;
  if (data is Map) {
    for (final key in keys) {
      final value = data[key];
      if (value is List) return value;
      if (value is Map) {
        final nested = _extractPostShareItems(value, keys);
        if (nested.isNotEmpty) return nested;
      }
    }
  }
  return const [];
}

List<PostShareTarget> sortPostShareTargetsByConversationOrder({
  required List<PostShareTarget> targets,
  required List<Conversation> conversations,
}) {
  final order = <String, int>{};
  for (var i = 0; i < conversations.length; i++) {
    final conversation = conversations[i];
    if (conversation.isCommunity && conversation.communityId != null) {
      order.putIfAbsent('community:${conversation.communityId}', () => i);
      continue;
    }
    final otherUserId = conversation.otherUser?.id;
    if (otherUserId != null && otherUserId > 0) {
      order.putIfAbsent('friend:$otherUserId', () => i);
    }
  }

  final sorted = List<PostShareTarget>.from(targets);
  sorted.sort((a, b) {
    final aOrder = order[a.stableKey];
    final bOrder = order[b.stableKey];
    if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
    if (aOrder != null) return -1;
    if (bOrder != null) return 1;
    return a.fallbackIndex.compareTo(b.fallbackIndex);
  });
  return sorted;
}

class PostShareTargetResolver {
  Future<List<PostShareTarget>> loadTargets() async {
    final results = await Future.wait([
      _loadFriends(),
      _loadCommunities(),
      _loadConversations(),
    ]);
    final friends = results[0] as List<User>;
    final communities = results[1] as List<Community>;
    final conversations = results[2] as List<Conversation>;

    final targets = <PostShareTarget>[
      for (var i = 0; i < friends.length; i++)
        PostShareTarget.friend(friends[i], fallbackIndex: i),
      for (var i = 0; i < communities.length; i++)
        PostShareTarget.community(
          communities[i],
          fallbackIndex: friends.length + i,
        ),
    ];

    return sortPostShareTargetsByConversationOrder(
      targets: targets,
      conversations: conversations,
    );
  }

  Future<List<User>> _loadFriends() async {
    final cached = await DataLayer().query(CacheKeys.friendList, () async => null);
    final cachedFriends = parsePostShareFriends(cached.data);
    if (cachedFriends.isNotEmpty) return cachedFriends;

    try {
      final response = await FriendService().getFriends();
      if (response.success == true) {
        final friends = parsePostShareFriends(response.data);
        if (friends.isNotEmpty) {
          await DataLayer().write(
            CacheKeys.friendList,
            friends.map((friend) => friend.toJson()).toList(),
            ttlSeconds: 300,
          );
        }
        return friends;
      }
    } catch (_) {}
    return const [];
  }

  Future<List<Community>> _loadCommunities() async {
    final cached =
        await DataLayer().query(CacheKeys.communityMyList, () async => null);
    final cachedCommunities = parsePostShareCommunities(cached.data);
    if (cachedCommunities.isNotEmpty) return cachedCommunities;

    try {
      final response = await CommunityApiService().getMy();
      if (response.success == true) {
        final communities = parsePostShareCommunities(response.data);
        if (communities.isNotEmpty) {
          await DataLayer().write(
            CacheKeys.communityMyList,
            communities.map((community) => community.toJson()).toList(),
            ttlSeconds: 300,
          );
        }
        return communities;
      }
    } catch (_) {}
    return const [];
  }

  Future<List<Conversation>> _loadConversations() async {
    final cached =
        await DataLayer().query(CacheKeys.convFullList, () async => null);
    final data = cached.data;
    if (data is List && data.isNotEmpty) {
      return data
          .whereType<Map>()
          .map((item) => Conversation.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    return DataLayer().loadConversationsFromDb();
  }
}
