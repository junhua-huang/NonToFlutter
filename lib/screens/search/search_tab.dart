import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/comic_event.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/topic.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:facebook_clone/screens/comic/comic_detail_page.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:facebook_clone/screens/profile/user_profile_screen.dart';
import 'package:facebook_clone/screens/search/search_results_screen.dart';
import 'package:facebook_clone/services/api/recommendation_service.dart';
import 'package:facebook_clone/services/api/search_service.dart';
import 'package:facebook_clone/services/api/topic_service.dart';
import 'package:facebook_clone/services/cache_service.dart';
import 'package:facebook_clone/services/comic_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/add_friend_button.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/post_card.dart';
import 'package:facebook_clone/widgets/search_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// Twitter/X Explore 风格搜索页（带实时搜索建议）
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final RefreshController _refreshController = RefreshController();

  List<String> _searchHistory = [];
  List<Topic> _trendingTopics = [];
  List<Post> _trendingPosts = [];
  List<User> _suggestedUsers = [];
  List<ComicEvent> _recentComicEvents = [];
  List<ComicEvent> _followedComicEvents = [];
  List<User> _userResults = [];
  List<Post> _postResults = [];

  bool _isSearching = false;
  bool _isLoading = false;
  bool _isLoadingDefault = true;
  bool _showSuggestions = false;
  String? _error;
  bool _activated = false;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    TabActivationNotifier.currentTab.addListener(_onTabActivated);
    if (TabActivationNotifier.currentTab.value == 1) {
      _activate();
    }
  }

  @override
  void dispose() {
    TabActivationNotifier.currentTab.removeListener(_onTabActivated);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await _loadDefault();
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

  void _onTabActivated() {
    if (!_activated && TabActivationNotifier.currentTab.value == 1) {
      _activate();
    }
  }

  void _activate() {
    _activated = true;
    _loadDefault();
  }

  Future<void> _loadDefault() async {
    // Try cache first
    final cachedTopics = await CacheService().getList(CacheKeys.trendingTopics());
    final cachedPosts = await CacheService().getList(CacheKeys.trendingPosts());
    final cachedUsers = await CacheService().getList(CacheKeys.suggestedUsers());

    if (cachedTopics != null) {
      _trendingTopics = cachedTopics.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (cachedPosts != null) {
      _trendingPosts = cachedPosts.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (cachedUsers != null) {
      _suggestedUsers = cachedUsers.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
    }

    if (mounted && (cachedTopics != null || cachedPosts != null || cachedUsers != null)) {
      setState(() => _isLoadingDefault = false);
    }

    try {
      final results = await Future.wait([
        SearchService().getHistory(),
        TopicService().getTrending(limit: 8),
        RecommendationService().getTrending(limit: 5),
        RecommendationService().suggestUsers(limit: 5),
        ComicService().getEvents(size: 4),
        ComicService().getMyFollowed(size: 4),
      ]);
      // History
      final histResp = results[0];
      if (histResp.success && histResp.data != null) {
        final data = histResp.data;
        List items = [];
        if (data is List) { items = data; }
        else if (data is Map) { items = data['history'] ?? data['items'] ?? []; }
        _searchHistory = items.map((e) {
          if (e is Map) return e['query']?.toString() ?? e.toString();
          return e.toString();
        }).take(3).toList();
      }
      // Trending topics
      final topicResp = results[1];
      if (topicResp.success && topicResp.data != null) {
        final data = topicResp.data;
        List topicList = [];
        if (data is List) {
          topicList = data;
        } else if (data is Map) {
          topicList = data['topics'] ?? data['items'] ?? [];
        }
        _trendingTopics = topicList
            .map((e) => Topic.fromJson(e as Map<String, dynamic>))
            .toList();
        await CacheService().set(CacheKeys.trendingTopics(), topicList, expireMinutes: 10);
      }
      // Trending posts
      final postResp = results[2];
      if (postResp.success && postResp.data != null) {
        final data = postResp.data as Map<String, dynamic>;
        final list = data['posts'] as List? ?? [];
        _trendingPosts = list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
        await CacheService().set(CacheKeys.trendingPosts(), list, expireMinutes: 5);
      }
      // Suggested users
      final userResp = results[3];
      if (userResp.success && userResp.data != null) {
        final data = userResp.data;
        List userList = [];
        if (data is List) {
          userList = data;
        } else if (data is Map) {
          userList = data['users'] ?? data['items'] ?? [];
        }
        _suggestedUsers = userList
            .map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList();
        await CacheService().set(CacheKeys.suggestedUsers(), userList, expireMinutes: 10);
      }
      // Recent comic events
      final comicResp = results[4];
      if (comicResp.success && comicResp.data != null) {
        final page = comicResp.data as ComicEventsPage;
        _recentComicEvents = page.records;
      }
      // Followed comic events
      final followedComicResp = results[5];
      if (followedComicResp.success && followedComicResp.data != null) {
        final page = followedComicResp.data as ComicEventsPage;
        _followedComicEvents = page.records;
      }
    } catch (e) {
      debugPrint('SearchTab loadDefault error: $e');
    } finally {
      setState(() => _isLoadingDefault = false);
    }
  }

  Future<void> _doSearch(String query) async {
    _focusNode.unfocus();
    setState(() { _showSuggestions = false; });
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _userResults.clear();
        _postResults.clear();
        _error = null;
      });
      return;
    }
    setState(() { _isSearching = true; _isLoading = true; _error = null; });
    _tabController.index = 0;
    try {
      final resp = await SearchService().globalSearch(query);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        setState(() {
          _userResults = (data['users'] as List? ?? [])
              .map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
          _postResults = (data['posts'] as List? ?? [])
              .map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
        });
        SearchService().saveHistory(query, 'global');
      } else {
        setState(() => _error = resp.message ?? '搜索失败');
      }
    } catch (e) {
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
        ValueListenableBuilder<bool>(
          valueListenable: HomeScreen.barVisible,
          builder: (_, visible, child) {
            return AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: visible ? Offset.zero : const Offset(0, -1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: visible ? (kToolbarHeight + MediaQuery.of(context).padding.top) : 0,
                child: visible ? child! : const SizedBox.shrink(),
              ),
            );
          },
          child: AppBar(
            title: const Text('Explore', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            backgroundColor: AppColors.background,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
          ),
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
                      _error = null;
                    });
                    _loadDefault();
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
        // Content
        Expanded(
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notif) {
              if (notif.dragDetails != null) {
                final delta = notif.scrollDelta ?? 0;
                if (delta > 5 && HomeScreen.barVisible.value) {
                  HomeScreen.barVisible.value = false;
                } else if (delta < -5 && !HomeScreen.barVisible.value) {
                  HomeScreen.barVisible.value = true;
                }
              }
              return false;
            },
            child: SmartRefresher(
            controller: _refreshController,
            enablePullDown: true,
            enablePullUp: false,
            onRefresh: _onRefresh,
            header: const WaterDropHeader(
              complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
              waterDropColor: AppColors.primary,
            ),
            child: _isLoadingDefault
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _showSuggestions
                    ? SearchSuggestions(
                        query: _controller.text,
                        onClose: () => setState(() => _showSuggestions = false),
                        onSearch: _doSearch,
                      )
                    : _isSearching
                        ? _buildSearchResults()
                        : _buildDefaultView(),
          ),
        ),
      ),
      ],
    );
  }

  // --- Default View ---

  Widget _buildDefaultView() {
    // Flatten all sections into indexed items for ListView.builder
    final List<_DefaultItem> items = [];

    // 1) Trending Topics (prominent, at top like Twitter/X)
    if (_trendingTopics.isNotEmpty) {
      items.add(_DefaultItem.header('热门话题'));
      for (final topic in _trendingTopics.take(8)) {
        items.add(_DefaultItem.topic(topic));
      }
      items.add(_DefaultItem.divider());
    }

    // 2) Hot / Trending Posts
    if (_trendingPosts.isNotEmpty) {
      items.add(_DefaultItem.header('热门帖子'));
      for (final post in _trendingPosts.take(5)) {
        items.add(_DefaultItem.post(post));
      }
      items.add(_DefaultItem.divider());
    }

    // 3) Recent Comic Events
    if (_recentComicEvents.isNotEmpty) {
      items.add(_DefaultItem.header('近期漫展'));
      for (final event in _recentComicEvents.take(3)) {
        items.add(_DefaultItem.comicEvent(event));
      }
      items.add(_DefaultItem.divider());
    }

    // 5) Followed Comic Events
    if (_followedComicEvents.isNotEmpty) {
      items.add(_DefaultItem.header('我关注的漫展'));
      for (final event in _followedComicEvents.take(3)) {
        items.add(_DefaultItem.comicEvent(event));
      }
      items.add(_DefaultItem.divider());
    }

    // 6) Recommended Users
    if (_suggestedUsers.isNotEmpty) {
      items.add(_DefaultItem.header('推荐好友'));
      items.add(_DefaultItem.friendRow(_suggestedUsers.take(10).toList()));
      items.add(_DefaultItem.divider());
    }

    items.add(_DefaultItem.spacer());

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        switch (item.type) {
          case _DefaultItemType.header:
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Text(item.label!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      _controller.text = item.label ?? '';
                      _doSearch(item.label ?? '');
                    },
                    child: Text('查看全部', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
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
            return const Divider(height: 32);
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
            return _buildComicEventCard(item.comicEvent!);
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

  // --- Search Results ---

  Widget _buildComicEventCard(ComicEvent event) {
    final url = (event.coverImage != null && event.coverImage!.isNotEmpty)
        ? (event.coverImage!.startsWith('http')
            ? event.coverImage!
            : '${AppConfig.baseUrl.replaceFirst('/api', '')}${event.coverImage}')
        : null;
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ComicDetailPage(eventId: event.id),
        ));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (url != null)
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
                child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80, height: 80, color: AppColors.backgroundSecondary,
                    child: const Icon(Icons.event, color: AppColors.textTertiary, size: 28),
                  ),
                ),
              )
            else
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
                ),
                child: const Icon(Icons.event, color: AppColors.textTertiary, size: 28),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(event.cityName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(event.statusText, style: TextStyle(fontSize: 11, color: _statusColor(event.status))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(int status) {
    switch (status) {
      case 1: return AppColors.successGreen;
      case 2: return AppColors.textTertiary;
      default: return const Color(0xFFFFA726);
    }
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

    final hasNoResults = _userResults.isEmpty && _postResults.isEmpty;
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
          const Divider(),
        ],
        if (_postResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('帖子', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
          ),
          ..._postResults.map((p) => _buildPostTile(p)),
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
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 24, color: AppColors.borderLight),
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
  header,
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

  factory _DefaultItem.header(String label) =>
      _DefaultItem._(type: _DefaultItemType.header, label: label);

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
