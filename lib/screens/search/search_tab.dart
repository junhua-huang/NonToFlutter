import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/comic_event.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/topic.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/widgets/comic_event_card.dart';
import 'package:nonto/screens/comic/comic_timeline_page.dart';
import 'package:nonto/screens/comic/comic_my_events_page.dart';
import 'package:nonto/screens/comic/comic_detail_page.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/services/api/recommendation_service.dart';
import 'package:nonto/services/api/search_service.dart';
import 'package:nonto/services/api/topic_service.dart';
import 'package:nonto/providers/explore_notifier.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/add_friend_button.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/post_card.dart';
import 'package:nonto/widgets/search_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// Twitter/X Explore 风格搜索页（带实时搜索建议）
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});
  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final RefreshController _refreshController = RefreshController();

  List<String> _searchHistory = [];
  List<User> _userResults = [];
  List<Post> _postResults = [];
  List<ComicEvent> _comicEventResults = [];

  bool _isSearching = false;
  bool _isLoading = false;
  bool _showSuggestions = false;
  String? _error;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    // Explorer data auto-loads via exploreProvider constructor — no _activate needed
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    try {
      await ref.read(exploreProvider.notifier).loadDefault(forceRefresh: true);
    } catch (_) {}
    _refreshController.refreshCompleted();
  }

  void _onTextChanged() {
    final text = _controller.text;
    setState(() {
      _showSuggestions = text.isNotEmpty && _focusNode.hasFocus;
    });
  }

  void _onFocusChanged() {
    setState(() {}); // rebuild to show/hide search history
  }

  Future<void> _doSearch(String query) async {
    _focusNode.unfocus();
    setState(() { _showSuggestions = false; });
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _userResults.clear();
        _postResults.clear();
        _comicEventResults.clear();
        _error = null;
      });
      return;
    }
    setState(() { _isSearching = true; _isLoading = true; _error = null; });
    try {
      final resp = await SearchService().globalSearch(query);
      if (resp.success && resp.data != null) {
        final dynamic rawData = resp.data;
        if (rawData is! Map) {
          setState(() => _error = '搜索结果格式异常');
          return;
        }
        final data = rawData as Map<String, dynamic>;
        setState(() {
          final dynamic usersRaw = data['users'];
          _userResults = (usersRaw is List ? usersRaw : const <dynamic>[])
              .map((e) => User.fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}))
              .toList();
          final dynamic postsRaw = data['posts'];
          _postResults = (postsRaw is List ? postsRaw : const <dynamic>[])
              .map((e) => Post.fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}))
              .toList();
          final dynamic eventsRaw = data['events'];
          _comicEventResults = (eventsRaw is List ? eventsRaw : const <dynamic>[])
              .map((e) => ComicEvent.fromListJson(e is Map<String, dynamic> ? e : <String, dynamic>{}))
              .toList();
        });
        // 根据搜索结果类型自动切到对应 Tab（无动画，直接跳到目标 Tab）
        final specialType = data['type'] as String?;
        if (specialType == 'hot_posts' || specialType == 'trending_topics') {
          _tabController.index = 1; // 帖子
        } else if (specialType == 'comic_events') {
          _tabController.index = 3; // 漫展
        } else {
          _tabController.index = 0; // 默认用户
        }
        SearchService().saveHistory(query, 'global');
      } else {
        final msg = resp.message ?? '搜索失败';
        debugPrint('[Search] globalSearch failed: $msg, statusCode=${resp.statusCode}');
        setState(() => _error = (resp.statusCode == 422) ? '搜索关键词至少需要2个字符' : msg);
      }
    } catch (e) {
      debugPrint('[Search] globalSearch exception for query="$query": $e');
      setState(() => _error = '搜索失败，请重试');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _clearHistory() async {
    await SearchService().clearHistory();
    setState(() => _searchHistory.clear());
  }

  void _removeHistoryItem(int index) {
    setState(() => _searchHistory.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 仅 AppBar 动画依赖 barVisibleProvider，独立 Consumer
        Consumer(
          builder: (context, ref, _) {
            final barVisible = ref.watch(barVisibleProvider);
            return AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: barVisible ? Offset.zero : const Offset(0, -1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: barVisible ? (kToolbarHeight + MediaQuery.of(context).padding.top) : 0,
                child: barVisible ? AppBar(
            title: const Text('Explore', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            backgroundColor: AppColors.background,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            ) : const SizedBox.shrink(),
          ),
        );
          },
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '搜索',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _isSearching = false;
                                _showSuggestions = false;
                                _userResults.clear();
                                _postResults.clear();
                                _comicEventResults.clear();
                                _error = null;
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _doSearch,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_isSearching)
                TextButton(
                  onPressed: () {
                    _controller.clear();
                    _focusNode.unfocus();
                    setState(() {
                      _isSearching = false;
                      _showSuggestions = false;
                      _userResults.clear();
                      _postResults.clear();
                      _comicEventResults.clear();
                      _error = null;
                    });
                    ref.read(exploreProvider.notifier).loadDefault();
                  },
                  child: const Text('取消', style: TextStyle(color: AppColors.primary, fontSize: 14)),
                ),
            ],
          ),
        ),
        // Search history — displayed directly below search bar
        if (_searchHistory.isNotEmpty && _focusNode.hasFocus && _controller.text.isEmpty && !_isSearching)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 2),
                  child: Row(
                    children: [
                      const Text('最近搜索',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
                      const Spacer(),
                      GestureDetector(
                        onTap: _clearHistory,
                        child: const Text('清除全部',
                          style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchHistory.length.clamp(0, 8),
                    itemBuilder: (_, i) => _buildCompactHistoryItem(i),
                  ),
                ),
              ],
            ),
          ),
        Consumer(
          builder: (context, ref, _) {
            final exploreState = ref.watch(exploreProvider);
            return Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notif) {
                  final delta = notif.scrollDelta ?? 0;
                  final barVisible = ref.read(barVisibleProvider);
                  if (notif.metrics.pixels <= 0 && !barVisible) {
                    ref.read(barVisibleProvider.notifier).state = true;
                    return false;
                  }
                  if (delta > 3 && barVisible) {
                    ref.read(barVisibleProvider.notifier).state = false;
                  } else if (delta < -3 && !barVisible) {
                    ref.read(barVisibleProvider.notifier).state = true;
                  }
                  return false;
                },
                child: SmartRefresher(
            controller: _refreshController,
            enablePullDown: !_isSearching && !_showSuggestions,
            enablePullUp: false,
            onRefresh: _onRefresh,
            header: const WaterDropHeader(
              complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
              waterDropColor: AppColors.primary,
            ),
            child: exploreState.isLoading && exploreState.trendingTopics.isEmpty && exploreState.trendingPosts.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _showSuggestions
                    ? SearchSuggestions(
                        query: _controller.text,
                        onClose: () => setState(() => _showSuggestions = false),
                        onSearch: _doSearch,
                      )
                    : _isSearching
                        ? _buildSearchResults()
                        : _buildDefaultView(exploreState),
          ),
        ),
        );
          },
        ),
      ],
    );
  }

  // --- Default View ---

  Widget _buildDefaultView(ExploreState s) {
    // Flatten all sections into indexed items for ListView.builder
    final List<_DefaultItem> items = [];

    // 1) Trending Topics
    if (s.trendingTopics.isNotEmpty) {
      items.add(_DefaultItem.headerWithAction('热门话题', '查看全部', () {
        _controller.text = '热门话题';
        _doSearch('热门话题');
      }));
      for (final topic in s.trendingTopics.take(8)) {
        items.add(_DefaultItem.topic(topic));
      }
      items.add(_DefaultItem.divider());
    }

    // 2) Hot Posts → global search
    if (s.trendingPosts.isNotEmpty) {
      items.add(_DefaultItem.headerWithAction('热门帖子', '查看全部', () {
        _controller.text = '热门帖子';
        _doSearch('热门帖子');
      }));
      for (final post in s.trendingPosts.take(5)) {
        items.add(_DefaultItem.post(post));
      }
      items.add(_DefaultItem.divider());
    }

    // 3) Recent Comic Events → navigation to timeline
    if (s.recentComicEvents.isNotEmpty) {
      items.add(_DefaultItem.headerWithAction('近期漫展', '查看全部', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ComicTimelinePage()));
      }));
      for (final event in s.recentComicEvents.take(3)) {
        items.add(_DefaultItem.comicEvent(event));
      }
      items.add(_DefaultItem.divider());
    }

    // 4) Followed Comic Events → navigation to my events
    if (s.followedComicEvents.isNotEmpty) {
      items.add(_DefaultItem.headerWithAction('我关注的漫展', '查看全部', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ComicMyEventsPage()));
      }));
      for (final event in s.followedComicEvents.take(3)) {
        items.add(_DefaultItem.comicEvent(event));
      }
      items.add(_DefaultItem.divider());
    }

    // 5) Recommended Users
    if (s.suggestedUsers.isNotEmpty) {
      items.add(_DefaultItem.headerWithAction('推荐好友', '查看全部', () {
        _controller.text = '';
        _doSearch('');
      }));
      items.add(_DefaultItem.friendRow(s.suggestedUsers.take(10).toList()));
      items.add(_DefaultItem.divider());
    }

    items.add(_DefaultItem.spacer());

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        switch (item.type) {
          case _DefaultItemType.headerWithAction:
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(item.label!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: item.onAction,
                    child: Text(item.actionLabel!, style: TextStyle(color: AppColors.primary, fontSize: 13)),
                  ),
                ],
              ),
            );
          case _DefaultItemType.friendRow:
            return SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: item.friends!.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _buildFriendCard(item.friends![i]),
              ),
            );
          case _DefaultItemType.divider:
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: AppColors.borderLight),
            );
          case _DefaultItemType.historyItem:
            return _buildCompactHistoryItem(item.historyIndex!);
          case _DefaultItemType.postItem:
            return PostCard(
              post: item.post!,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PostDetailScreen(postId: item.post!.id, initialPost: item.post),
              )),
            );
          case _DefaultItemType.topicItem:
            return _buildTopicItem(item.topic!);
          case _DefaultItemType.comicEventItem:
            return ComicEventCard(event: item.comicEvent!);
          case _DefaultItemType.friendRow:
            return _buildFriendRow(item.friends!);
          case _DefaultItemType.spacer:
            return const SizedBox(height: 60);
        }
      },
    );
  }

  Widget _buildFriendCard(User user) {
    return _FriendCard(user: user);
  }

  Widget _buildFriendRow(List<User> friends) {
    return SizedBox(
      height: 170,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: friends.length,
        itemBuilder: (context, index) {
          final user = friends[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => UserProfileScreen(user: user),
                ));
              },
              child: _FriendCard(user: user),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactHistoryItem(int index) {
    return Dismissible(
      key: ValueKey(_searchHistory[index]),
      direction: DismissDirection.endToStart,
      background: const SizedBox(),
      onDismissed: (_) => _removeHistoryItem(index),
      child: InkWell(
        onTap: () {
          _controller.text = _searchHistory[index];
          _doSearch(_searchHistory[index]);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_searchHistory[index], style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingPostCard(Post post) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
      )),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  ImageUtils.buildAvatar(post.user, radius: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.user?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                        Text('@${post.user?.username ?? ''}  ·  ${AppDateUtils.formatTimeAgo(post.createdAt)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Content
            if (post.content != null && post.content!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Text(post.content!, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.3, color: AppColors.textPrimary)),
              ),
            // Image
            if (post.hasImage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ImageUtils.buildPostImage(post.images != null && post.images!.isNotEmpty ? post.images![0] : null, width: double.infinity),
                  ),
                ),
              ),
            // Stats row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  _SmallIcon(icon: Icons.comment_outlined, count: post.commentCount),
                  const SizedBox(width: 28),
                  _SmallIcon(icon: Icons.favorite_border, count: post.likeCount),
                  const SizedBox(width: 28),
                  if (post.viewCount > 0) _SmallIcon(icon: Icons.visibility_outlined, count: post.viewCount),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicItem(Topic topic) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => TopicSearchResultsScreen(topicName: topic.name),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${topic.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  if (topic.description != null && topic.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(topic.description!,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                  const SizedBox(height: 2),
                  Text('${topic.postCount} 条帖子 · ${topic.followerCount} 人关注',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
              ),
            ),
            _buildTopicFollowButton(topic),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicFollowButton(Topic topic) {
    return StatefulBuilder(
      builder: (context, setState) {
        final isFollowing = topic.isFollowing;
        return GestureDetector(
          onTap: () async {
            try {
              if (isFollowing) {
                final resp = await TopicService().unfollowTopic(topic.id);
                if (resp.success) {
                  setState(() => topic = topic.copyWith(isFollowing: false));
                }
              } else {
                final resp = await TopicService().followTopic(topic.id);
                if (resp.success) {
                  setState(() => topic = topic.copyWith(isFollowing: true));
                }
              }
            } catch (_) {
              // ignore network errors silently
            }
          },
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isFollowing ? AppColors.borderLight : AppColors.primary,
                width: 1.2,
              ),
              color: isFollowing ? AppColors.backgroundSecondary : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: Text(
              isFollowing ? '已关注' : '关注',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isFollowing ? AppColors.textSecondary : AppColors.primary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return ErrorStateWidget(
        message: _error!,
        onRetry: () => _doSearch(_controller.text),
      );
    }

    final hasNoResults = _userResults.isEmpty && _postResults.isEmpty && _comicEventResults.isEmpty;
    if (hasNoResults) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56, color: AppColors.borderLight),
            const SizedBox(height: 16),
            Text('未找到相关结果', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('试试其他关键词', style: TextStyle(color: AppColors.textTertiary, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tabs
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            unselectedLabelStyle: const TextStyle(fontSize: 15),
            tabs: const [
              Tab(text: '全部'),
              Tab(text: '用户'),
              Tab(text: '漫展'),
              Tab(text: '帖子'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAllResults(),
              _buildUsersList(),
              _buildComicEventsList(),
              _buildPostsList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAllResults() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (_userResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('用户', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
          ),
          ..._userResults.map((u) => _buildUserTile(u)),
          const Divider(height: 1, color: AppColors.borderLight),
        ],
        if (_postResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('帖子', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
          ),
          ..._postResults.map((p) => _buildPostTile(p)),
        ],
        if (_comicEventResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('漫展', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
          ),
          ..._comicEventResults.map((e) => ComicEventCard(event: e)),
        ],
      ],
    );
  }

  Widget _buildUsersList() {
    if (_userResults.isEmpty) {
      return const Center(child: Text('没有匹配的用户', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: _userResults.length,
      itemBuilder: (_, i) => _buildUserTile(_userResults[i]),
    );
  }

  Widget _buildPostsList() {
    if (_postResults.isEmpty) {
      return const Center(child: Text('没有匹配的帖子', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: _postResults.length,
      itemBuilder: (_, i) => _buildPostTile(_postResults[i]),
    );
  }

  Widget _buildComicEventsList() {
    if (_comicEventResults.isEmpty) {
      return const Center(child: Text('没有匹配的漫展', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: _comicEventResults.length,
      itemBuilder: (_, i) => ComicEventCard(event: _comicEventResults[i]),
    );
  }

  Widget _buildUserTile(User user) {
    return _UserTile(user: user);
  }

  Widget _buildPostTile(Post post) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            Row(
              children: [
                ImageUtils.buildAvatar(post.user, radius: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.user?.displayName ?? '未知用户',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                      Text(AppDateUtils.formatTimeAgo(post.createdAt),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(post.content ?? '', maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary)),
            if (post.hasImage) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ImageUtils.buildPostImage(post.images != null && post.images!.isNotEmpty ? post.images![0] : null, width: double.infinity),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _SmallIcon(icon: Icons.comment_outlined, count: post.commentCount),
                const SizedBox(width: 28),
                _SmallIcon(icon: Icons.favorite_border, count: post.likeCount),
                const SizedBox(width: 28),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(height: 1, color: AppColors.borderLight),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final User user;
  const _FriendCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final user = this.user;
    return Container(
      width: 120,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ImageUtils.buildAvatar(user, radius: 30),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              user.displayName ?? user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '@${user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AddFriendButton(userId: user.id, height: 28),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final user = this.user;
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => UserProfileScreen(user: user),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ImageUtils.buildAvatar(user, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName ?? user.username,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('@${user.username}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(user.bio!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ],
              ),
            ),
            AddFriendButton(userId: user.id),
          ],
        ),
      ),
    );
  }
}

class _SmallIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const _SmallIcon({required this.icon, this.count = 0});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        if (count > 0) ...[
          const SizedBox(width: 3),
          Text('$count', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ],
    );
  }
}

// --- Default View Item Types for ListView.builder ---

enum _DefaultItemType {
  headerWithAction,
  friendRow,
  divider,
  historyItem,
  postItem,
  topicItem,
  comicEventItem,
  spacer,
}

class _DefaultItem {
  final _DefaultItemType type;
  final String? label;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<User>? friends;
  final int? historyIndex;
  final Post? post;
  final Topic? topic;
  final ComicEvent? comicEvent;

  _DefaultItem._({
    required this.type,
    this.label,
    this.actionLabel,
    this.onAction,
    this.friends,
    this.historyIndex,
    this.post,
    this.topic,
    this.comicEvent,
  });

  factory _DefaultItem.headerWithAction(String label, String actionLabel, VoidCallback onAction) =>
      _DefaultItem._(type: _DefaultItemType.headerWithAction, label: label, actionLabel: actionLabel, onAction: onAction);

  factory _DefaultItem.friendRow(List<User> friends) =>
      _DefaultItem._(type: _DefaultItemType.friendRow, friends: friends);

  factory _DefaultItem.divider() =>
      _DefaultItem._(type: _DefaultItemType.divider);

  factory _DefaultItem.history(int index) =>
      _DefaultItem._(type: _DefaultItemType.historyItem, historyIndex: index);

  factory _DefaultItem.post(Post post) =>
      _DefaultItem._(type: _DefaultItemType.postItem, post: post);

  factory _DefaultItem.topic(Topic topic) =>
      _DefaultItem._(type: _DefaultItemType.topicItem, topic: topic);

  factory _DefaultItem.comicEvent(ComicEvent event) =>
      _DefaultItem._(type: _DefaultItemType.comicEventItem, comicEvent: event);

  factory _DefaultItem.spacer() =>
      _DefaultItem._(type: _DefaultItemType.spacer);
}
