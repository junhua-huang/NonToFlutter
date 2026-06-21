import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/models/post.dart';

// ============================================================
// 社群列表状态
// ============================================================

class CommunityListState {
  final List<Community> myCommunities;
  final List<Community> discovered;
  final bool isLoading;
  final String? error;
  final bool hasMore;
  final int offset;

  const CommunityListState({
    this.myCommunities = const [],
    this.discovered = const [],
    this.isLoading = false,
    this.error,
    this.hasMore = true,
    this.offset = 0,
  });

  CommunityListState copyWith({
    List<Community>? myCommunities,
    List<Community>? discovered,
    bool? isLoading,
    String? error,
    bool? hasMore,
    int? offset,
  }) {
    return CommunityListState(
      myCommunities: myCommunities ?? this.myCommunities,
      discovered: discovered ?? this.discovered,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
    );
  }
}

class CommunityListNotifier extends StateNotifier<CommunityListState> {
  final CommunityApiService _api = CommunityApiService();

  CommunityListNotifier() : super(const CommunityListState());

  Future<void> loadInitial() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final myResp = await _api.getMy();
      final discoverResp = await _api.list(limit: 20, offset: 0);
      final myList = (myResp.data is List)
          ? (myResp.data as List).map((e) => Community.fromJson(e)).toList()
          : <Community>[];
      final discoList =
          (discoverResp.data is Map && discoverResp.data['communities'] is List)
              ? (discoverResp.data['communities'] as List)
                  .map((e) => Community.fromJson(e))
                  .toList()
              : <Community>[];
      state = CommunityListState(
        myCommunities: myList,
        discovered: discoList,
        isLoading: false,
        hasMore: discoList.length >= 20,
        offset: discoList.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> search(String keyword) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _api.list(keyword: keyword, limit: 50, offset: 0);
      final list = (resp.data is Map && resp.data['communities'] is List)
          ? (resp.data['communities'] as List)
              .map((e) => Community.fromJson(e))
              .toList()
          : <Community>[];
      state = state.copyWith(
          discovered: list, isLoading: false, hasMore: false, offset: 0);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void refreshMy() {
    loadInitial();
  }
}

// ============================================================
// 社群详情状态
// ============================================================

class CommunityDetailState {
  final Community? community;
  final List<CommunityMember> members;
  final List<Post> posts;
  final bool isLoading;
  final String? error;
  final String sortBy; // 'latest' or 'hot'

  const CommunityDetailState({
    this.community,
    this.members = const [],
    this.posts = const [],
    this.isLoading = false,
    this.error,
    this.sortBy = 'latest',
  });

  CommunityDetailState copyWith({
    Community? community,
    List<CommunityMember>? members,
    List<Post>? posts,
    bool? isLoading,
    String? error,
    String? sortBy,
  }) {
    return CommunityDetailState(
      community: community ?? this.community,
      members: members ?? this.members,
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

class CommunityDetailNotifier extends StateNotifier<CommunityDetailState> {
  final CommunityApiService _api = CommunityApiService();

  CommunityDetailNotifier() : super(const CommunityDetailState());

  Future<void> load(int communityId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final detailResp = await _api.getDetail(communityId);
      final membersResp = await _api.getMembers(communityId, limit: 10);

      final community = detailResp.data is Map
          ? Community.fromJson(detailResp.data['community'] ?? detailResp.data)
          : Community(id: communityId, name: '', ownerId: 0);
      final members =
          (membersResp.data is Map && membersResp.data['members'] is List)
              ? (membersResp.data['members'] as List)
                  .map((e) => CommunityMember.fromJson(e))
                  .toList()
              : <CommunityMember>[];

      // 加载帖子
      await _loadPosts(communityId);

      state = CommunityDetailState(
        community: community,
        members: members,
        isLoading: false,
        sortBy: state.sortBy,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadPosts(int communityId, {bool hot = false}) async {
    final sortBy = hot ? 'hot' : 'latest';
    state = state.copyWith(isLoading: true, sortBy: sortBy);
    await _loadPosts(communityId);
  }

  Future<void> _loadPosts(int communityId) async {
    try {
      if (state.sortBy == 'hot') {
        final resp = await _api.getHotPosts(communityId);
        state =
            state.copyWith(posts: _extractPosts(resp.data), isLoading: false);
      } else {
        // 社群帖子流：用 _api.get (来自 ApiClient)
        final resp = await ApiClient().get('/posts/',
            params: {'community_id': communityId, 'page': 1, 'per_page': 20});
        state =
            state.copyWith(posts: _extractPosts(resp.data), isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  List<Post> _extractPosts(dynamic data) {
    if (data is List) {
      return data
          .map((e) =>
              Post.fromJson(e is Map ? Map<String, dynamic>.from(e) : {}))
          .toList();
    }
    if (data is Map && data['posts'] is List) {
      return (data['posts'] as List)
          .map((e) =>
              Post.fromJson(e is Map ? Map<String, dynamic>.from(e) : {}))
          .toList();
    }
    return [];
  }
}

// ── Provider 定义 ──

final communityListProvider =
    StateNotifierProvider<CommunityListNotifier, CommunityListState>(
  (ref) => CommunityListNotifier(),
);

final communityDetailProvider = StateNotifierProvider.autoDispose<
    CommunityDetailNotifier, CommunityDetailState>(
  (ref) => CommunityDetailNotifier(),
);

class CommunityChatState {
  final int? conversationId;
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final String? error;

  const CommunityChatState({
    this.conversationId,
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  CommunityChatState copyWith({
    int? conversationId,
    List<Map<String, dynamic>>? messages,
    bool? isLoading,
    String? error,
  }) {
    return CommunityChatState(
      conversationId: conversationId ?? this.conversationId,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  void addMessage(Map<String, dynamic> msg) {
    // 此方法仅用于 copyWith 外部管理，不直接修改 state
  }
}

class CommunityChatNotifier extends StateNotifier<CommunityChatState> {
  final CommunityApiService _api = CommunityApiService();

  CommunityChatNotifier() : super(const CommunityChatState());

  Future<void> load(int communityId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _api.getChat(communityId, limit: 50);
      final data = resp.data is Map
          ? resp.data as Map<String, dynamic>
          : <String, dynamic>{};
      final conv = data['conversation'];
      final rawMessages =
          data['messages'] is List ? data['messages'] as List : [];

      state = CommunityChatState(
        conversationId: conv is Map ? conv['id'] : null,
        messages: rawMessages
            .map((e) =>
                e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> sendMessage(int communityId, String content,
      {List<int>? mentions}) async {
    try {
      final resp = await _api.sendMessage(communityId,
          content: content, mentionUserIds: mentions);
      if (resp.data is Map) {
        final msg =
            Map<String, dynamic>.from(resp.data['message'] ?? resp.data);
        state = state.copyWith(messages: [...state.messages, msg]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> recallMessage(int communityId, int messageId) async {
    try {
      await _api.recallMessage(communityId, messageId);
      return true;
    } catch (_) {
      return false;
    }
  }

  void addWsMessage(Map<String, dynamic> msg) {
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  void removeMessage(int messageId) {
    state = state.copyWith(
        messages: state.messages.where((m) => m['id'] != messageId).toList());
  }
}
