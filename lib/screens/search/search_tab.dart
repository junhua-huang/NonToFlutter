import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/comic_event.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/topic.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/widgets/comic_event_card.dart';
import 'package:nonto/screens/comic/comic_timeline_page.dart';
import 'package:nonto/screens/comic/comic_my_events_page.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/search_service.dart';
import 'package:nonto/services/api/topic_service.dart';
import 'package:nonto/services/post_interaction_notifier.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/explore_notifier.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/add_friend_button.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/nonto_header_search_bar.dart';
import 'package:nonto/widgets/post_card.dart';
import 'package:nonto/widgets/search_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';
import 'package:nonto/utils/bar_scroll_handler.dart';

/// Nonto 发现页：融合探索内容、搜索记录、实时建议与结果页。
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});
  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _refreshController = RefreshController(initialRefresh: false);
  final _textNotEmpty = ValueNotifier<bool>(false);
  int _searchGeneration = 0;

  List<String> _searchHistory = [];
  List<User> _userResults = [];
  List<Post> _postResults = [];
  List<ComicEvent> _comicEventResults = [];

  /// 是否处于搜索态（焦点驱动）：隐藏标题栏、展开搜索记录/建议、右侧显示按钮
  bool _inSearchMode = false;

  /// 是否已发起过搜索（显示结果页）
  bool _isSearching = false;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;

  late final TabController _tabController;

  /// 派生：是否显示实时建议（搜索态 + 有文字 + 未在加载）
  bool get _showSuggestions =>
      _inSearchMode && _controller.text.isNotEmpty && !_isLoading;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _controller.addListener(_onTextChanged);
    _controller
        .addListener(() => _textNotEmpty.value = _controller.text.isNotEmpty);
    _focusNode.addListener(_onFocusChanged);
    _loadSearchHistory();
    // Explorer data auto-loads via exploreProvider constructor — no _activate needed
  }

  Future<void> _loadSearchHistory() async {
    try {
      final resp = await SearchService().getHistory();
      if (resp.success && resp.data != null) {
        final data = resp.data;
        List list = [];
        if (data is List) {
          list = data;
        } else if (data is Map) {
          list = data['history'] ?? data['items'] ?? [];
        }
        if (mounted) {
          setState(() {
            _searchHistory = list.map((e) {
              if (e is String) return e;
              if (e is Map) return e['query']?.toString() ?? e.toString();
              return e.toString();
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Load search history error: $e');
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    _refreshController.dispose();
    _textNotEmpty.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await ref.read(exploreProvider.notifier).loadDefault(forceRefresh: true);
    } catch (_) {}
    if (mounted) {
      // 先完成刷新动画，再 setState 重建内容。
      // 反过来（先 setState 再 refreshCompleted）会让 SmartRefresher 的收起
      // 动画基于旧内容高度，而此时内容已重建出新高度，导致列表做一次补偿性
      // 回弹（表现为"自动上拉一下"）。
      _refreshController.refreshCompleted();
      setState(() => _isRefreshing = false);
    }
  }

  void _onTextChanged() {
    // 文字变化时刷新 UI（按钮形态、建议显隐由 build 中的 AnimatedSwitcher 自动处理）
    setState(() {});
  }

  void _onFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus) {
      // 获焦 → 进入搜索态
      if (!_inSearchMode) setState(() => _inSearchMode = true);
    } else {
      // 失焦：仅在未显示搜索结果时退出搜索态（有结果时保留，方便查看）
      if (_inSearchMode && !_isSearching) {
        setState(() => _inSearchMode = false);
      }
    }
  }

  /// 退出搜索态：清空输入、失焦、收起记录、恢复标题栏。
  /// 保留 _isSearching 结果页由调用方决定是否清除。
  void _exitSearchMode({bool clearResults = true}) {
    _controller.clear();
    _textNotEmpty.value = false;
    _focusNode.unfocus();
    // 退出搜索态时强制把全局 bar 恢复显示：用户在搜索态期间标题栏被隐藏，
    // 但 barVisibleProvider 的值是按上次滚动决定的，可能仍为 false，
    // 导致退出后看似"标题栏没回来"。
    ref.read(barVisibleProvider.notifier).state = true;
    setState(() {
      _inSearchMode = false;
      if (clearResults) {
        _isSearching = false;
        _userResults.clear();
        _postResults.clear();
        _comicEventResults.clear();
        _error = null;
      }
    });
  }

  void _focusSearch() {
    ref.read(barVisibleProvider.notifier).state = true;
    setState(() => _inSearchMode = true);
    _focusNode.requestFocus();
  }

  Future<void> _doSearch(String query) async {
    final generation = ++_searchGeneration;
    _focusNode.unfocus();
    setState(() {
      _isSearching = true;
      _isLoading = true;
      _error = null;
      // 触发搜索后退出搜索态（收起记录/建议、恢复标题栏），但保留结果页
      _inSearchMode = false;
    });
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
    // 关键词不足2字符时直接提示，不发起请求
    if (query.trim().length < 2) {
      setState(() {
        _isSearching = true;
        _isLoading = false;
        _error = '搜索关键词至少需要2个字符';
        _userResults.clear();
        _postResults.clear();
        _comicEventResults.clear();
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _isLoading = true;
      _error = null;
    });
    try {
      final resp = await SearchService().globalSearch(query);
      if (!mounted || generation != _searchGeneration) return;
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
              .map((e) => User.fromJson(
                  e is Map<String, dynamic> ? e : <String, dynamic>{}))
              .toList();
          final dynamic postsRaw = data['posts'];
          _postResults = (postsRaw is List ? postsRaw : const <dynamic>[])
              .map((e) => Post.fromJson(
                  e is Map<String, dynamic> ? e : <String, dynamic>{}))
              .toList();
          final dynamic eventsRaw = data['events'];
          _comicEventResults =
              (eventsRaw is List ? eventsRaw : const <dynamic>[])
                  .map((e) => ComicEvent.fromListJson(
                      e is Map<String, dynamic> ? e : <String, dynamic>{}))
                  .toList();
        });
        // 根据搜索结果类型自动切到对应 Tab（无动画，直接跳到目标 Tab）
        final specialType = data['type'] as String?;
        if (specialType == 'hot_posts' || specialType == 'trending_topics') {
          _tabController.index = 3; // 帖子
        } else if (specialType == 'comic_events') {
          _tabController.index = 2; // 漫展
        } else {
          _tabController.index = 0; // 全部
        }
        SearchService().saveHistory(query, 'global');
      } else {
        final msg = resp.message ?? '搜索失败';
        debugPrint(
            '[Search] globalSearch failed: $msg, statusCode=${resp.statusCode}');
        setState(
            () => _error = (resp.statusCode == 422) ? '搜索关键词至少需要2个字符' : msg);
      }
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      debugPrint('[Search] globalSearch exception for query="$query": $e');
      setState(() => _error = '搜索失败，请重试');
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _togglePostLike(Post post) async {
    final wasLiked = post.isLiked == true;
    final originalCount = post.likeCount;
    final nextCount = wasLiked ? originalCount - 1 : originalCount + 1;

    void apply(bool isLiked, int likeCount) {
      final idx = _postResults.indexWhere((item) => item.id == post.id);
      if (idx != -1) {
        _postResults[idx] = _postResults[idx].copyWith(
          isLiked: isLiked,
          likeCount: likeCount,
        );
      }
      ref
          .read(exploreProvider.notifier)
          .updatePostLike(post.id, isLiked, likeCount);
    }

    setState(() => apply(!wasLiked, nextCount));

    try {
      if (wasLiked) {
        await PostService().unlikePost(post.id);
      } else {
        await PostService().likePost(post.id);
      }
      PostInteractionNotifier()
          .notifyLikeChanged(post.id, !wasLiked, nextCount);
    } catch (_) {
      if (!mounted) return;
      setState(() => apply(wasLiked, originalCount));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败'), duration: Duration(seconds: 2)),
      );
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
    final topPadding = MediaQuery.of(context).padding.top;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_focusNode.hasFocus) _focusNode.unfocus();
      },
      child: Column(
        children: [
          // 标题栏：头像 + 搜索框。搜索框聚焦时头像收起，输入框向左扩展。
          Consumer(
            builder: (context, ref, _) {
              final barVisible = ref.watch(barVisibleProvider);
              final hideHeader = !_inSearchMode && !barVisible;
              return AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height:
                      hideHeader ? topPadding : (kToolbarHeight + topPadding),
                  child: hideHeader
                      ? const SizedBox.shrink()
                      : Material(
                          color: AppColors.background,
                          child: NontoHeaderSearchBar(
                            controller: _controller,
                            focusNode: _focusNode,
                            user: ref.watch(authProvider).user,
                            hintText: '搜索',
                            onChanged: (_) => _onTextChanged(),
                            onSubmitted: _doSearch,
                            suffixIcon: ValueListenableBuilder<bool>(
                              valueListenable: _textNotEmpty,
                              builder: (_, notEmpty, __) {
                                if (!notEmpty) return const SizedBox.shrink();
                                return IconButton(
                                  icon: Icon(Icons.close,
                                      size: 18, color: AppColors.textSecondary),
                                  onPressed: () {
                                    _controller.clear();
                                    _textNotEmpty.value = false;
                                  },
                                );
                              },
                            ),
                            trailing: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SizeTransition(
                                  sizeFactor: anim,
                                  axisAlignment: -1,
                                  child: child,
                                ),
                              ),
                              child: _buildRightButton(),
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
          // 内容区：默认视图 / 搜索记录 / 实时建议 / 结果，淡入淡出切换
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              // 默认 layoutBuilder 用 Stack(alignment: center)，会把不撑满
              // 的子组件（如 SearchSuggestions 的 shrinkWrap ListView、结果页
              // 的 Center loading）垂直居中，导致搜索框下方出现一大段空白、
              // "搜索 xxx" 行被推到屏幕中间。改用 topCenter 让所有子态顶端对齐。
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: _buildContentArea(),
            ),
          ),
        ],
      ),
    );
  }

  /// 右侧按钮形态：
  /// - 非搜索态：无按钮
  /// - 搜索态 + 无文字：取消（退出搜索态）
  /// - 搜索态 + 有文字：搜索（触发搜索）
  Widget _buildRightButton() {
    if (!_inSearchMode) return const SizedBox.shrink(key: ValueKey('none'));
    if (_controller.text.isEmpty) {
      return TextButton(
        key: const ValueKey('cancel'),
        onPressed: () => _exitSearchMode(),
        child: const Text('取消',
            style: TextStyle(color: AppColors.primary, fontSize: 14)),
      );
    }
    return TextButton(
      key: const ValueKey('search'),
      onPressed: () => _doSearch(_controller.text),
      child: const Text('搜索',
          style: TextStyle(color: AppColors.primary, fontSize: 14)),
    );
  }

  bool _hasExploreContent(ExploreState s) {
    return s.trendingTopics.isNotEmpty ||
        s.trendingPosts.isNotEmpty ||
        s.recentComicEvents.isNotEmpty ||
        s.followedComicEvents.isNotEmpty ||
        s.suggestedUsers.isNotEmpty;
  }

  /// 内容区四态切换：
  /// 1. 搜索结果页（_isSearching）
  /// 2. 搜索态 + 有文字：实时建议
  /// 3. 搜索态 + 无文字：搜索记录（占满）
  /// 4. 默认视图（推荐内容 + 下拉刷新）
  Widget _buildContentArea() {
    // 已发起搜索 → 结果页
    if (_isSearching) {
      return KeyedSubtree(
        key: const ValueKey('results'),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _buildSearchResults(),
      );
    }
    // 搜索态 + 有文字 → 实时建议
    if (_showSuggestions) {
      return KeyedSubtree(
        key: const ValueKey('suggestions'),
        child: SearchSuggestions(
          query: _controller.text,
          onClose: () => _exitSearchMode(),
          onSearch: _doSearch,
        ),
      );
    }
    // 搜索态 + 无文字 → 搜索记录占满
    if (_inSearchMode) {
      return KeyedSubtree(
        key: const ValueKey('history'),
        child: _buildSearchHistoryFull(),
      );
    }
    // 默认视图
    return KeyedSubtree(
      key: const ValueKey('default'),
      child: Consumer(
        builder: (context, ref, _) {
          final exploreState = ref.watch(exploreProvider);
          return NotificationListener<ScrollUpdateNotification>(
            onNotification: (notif) {
              handleBarScrollNotification(notif, ref);
              return false;
            },
            child: SmartRefresher(
              controller: _refreshController,
              enablePullDown: true,
              onRefresh: _onRefresh,
              header: const ClassicHeader(
                refreshingText: '刷新中...',
                completeText: '刷新成功',
                failedText: '刷新失败',
                idleText: '',
                refreshingIcon: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2)),
                completeIcon: Icon(Icons.check_circle,
                    color: AppColors.primary, size: 16),
                failedIcon:
                    Icon(Icons.error_outline, color: Colors.red, size: 16),
                height: 44,
              ),
              child: exploreState.isLoading &&
                      !_hasExploreContent(exploreState) &&
                      !_isRefreshing
                  ? _buildExploreLoadingState()
                  : !_hasExploreContent(exploreState)
                      ? _buildExploreEmptyState()
                      : _buildDefaultView(exploreState),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExploreLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildExploreEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.travel_explore_outlined,
              size: 52,
              color: AppColors.textTertiary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 14),
            Text(
              '暂时没有发现内容',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '下拉刷新，或试试搜索你感兴趣的话题、帖子和漫展。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 占满剩余屏幕的搜索记录视图
  Widget _buildSearchHistoryFull() {
    if (_searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history,
                size: 48, color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('暂无搜索记录',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text('最近搜索',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary)),
              const Spacer(),
              GestureDetector(
                onTap: _clearHistory,
                child: const Text('清除全部',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.borderLight),
        // 记录列表占满剩余空间
        Expanded(
          child: ListView.builder(
            itemCount: _searchHistory.length,
            itemBuilder: (_, i) => _buildCompactHistoryItem(i),
          ),
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
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ComicTimelinePage()));
      }));
      for (final event in s.recentComicEvents.take(3)) {
        items.add(_DefaultItem.comicEvent(event));
      }
      items.add(_DefaultItem.divider());
    }

    // 4) Followed Comic Events → navigation to my events
    if (s.followedComicEvents.isNotEmpty) {
      items.add(_DefaultItem.headerWithAction('我关注的漫展', '查看全部', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ComicMyEventsPage()));
      }));
      for (final event in s.followedComicEvents.take(3)) {
        items.add(_DefaultItem.comicEvent(event));
      }
      items.add(_DefaultItem.divider());
    }

    // 5) Recommended Users
    if (s.suggestedUsers.isNotEmpty) {
      items.add(_DefaultItem.headerWithAction(
        '推荐好友',
        '查看全部',
        _focusSearch,
      ));
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
                  Text(item.label!,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: item.onAction,
                    child: Text(item.actionLabel!,
                        style:
                            TextStyle(color: AppColors.primary, fontSize: 13)),
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
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: AppColors.borderLight),
            );
          case _DefaultItemType.postItem:
            return PostCard(
              post: item.post!,
              onLike: () => _togglePostLike(item.post!),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(
                        postId: item.post!.id, initialPost: item.post),
                  )),
            );
          case _DefaultItemType.topicItem:
            return _buildTopicItem(item.topic!);
          case _DefaultItemType.comicEventItem:
            return ComicEventCard(event: item.comicEvent!);
          case _DefaultItemType.spacer:
            return const SizedBox(height: 60);
        }
      },
    );
  }

  Widget _buildFriendCard(User user) {
    return _FriendCard(user: user);
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
              Icon(Icons.history, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_searchHistory[index],
                    style:
                        TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopicItem(Topic topic) {
    return InkWell(
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
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
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary)),
                  if (topic.description != null &&
                      topic.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(topic.description!,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                  const SizedBox(height: 2),
                  Text('${topic.postCount} 条帖子 · ${topic.followerCount} 人关注',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 12)),
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
              color: isFollowing
                  ? AppColors.backgroundSecondary
                  : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: Text(
              isFollowing ? '已关注' : '关注',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    isFollowing ? AppColors.textSecondary : AppColors.primary,
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

    final hasNoResults = _userResults.isEmpty &&
        _postResults.isEmpty &&
        _comicEventResults.isEmpty;
    if (hasNoResults) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: AppColors.borderLight),
            const SizedBox(height: 16),
            Text('未找到相关结果',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 6),
            Text('试试其他关键词',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tabs
        Container(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 3,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('用户',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
          ),
          ..._userResults.map((u) => _buildUserTile(u)),
          Divider(height: 1, color: AppColors.borderLight),
        ],
        if (_postResults.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('帖子',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
          ),
          ..._postResults.map((p) => _buildPostTile(p)),
        ],
        if (_comicEventResults.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('漫展',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
          ),
          ..._comicEventResults.map((e) => ComicEventCard(event: e)),
        ],
      ],
    );
  }

  Widget _buildUsersList() {
    if (_userResults.isEmpty) {
      return Center(
          child: Text('没有匹配的用户',
              style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: _userResults.length,
      itemBuilder: (_, i) => _buildUserTile(_userResults[i]),
    );
  }

  Widget _buildPostsList() {
    if (_postResults.isEmpty) {
      return Center(
          child: Text('没有匹配的帖子',
              style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: _postResults.length,
      itemBuilder: (_, i) => _buildPostTile(_postResults[i]),
    );
  }

  Widget _buildComicEventsList() {
    if (_comicEventResults.isEmpty) {
      return Center(
          child: Text('没有匹配的漫展',
              style: TextStyle(color: AppColors.textSecondary)));
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
    return PostCard(
      post: post,
      feedPosts: _postResults,
      onLike: () => _togglePostLike(post),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
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
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '@${user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
        Navigator.push(
            context,
            MaterialPageRoute(
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
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('@${user.username}',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(user.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
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

// --- Default View Item Types for ListView.builder ---

enum _DefaultItemType {
  headerWithAction,
  friendRow,
  divider,
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
  final Post? post;
  final Topic? topic;
  final ComicEvent? comicEvent;

  _DefaultItem._({
    required this.type,
    this.label,
    this.actionLabel,
    this.onAction,
    this.friends,
    this.post,
    this.topic,
    this.comicEvent,
  });

  factory _DefaultItem.headerWithAction(
          String label, String actionLabel, VoidCallback onAction) =>
      _DefaultItem._(
          type: _DefaultItemType.headerWithAction,
          label: label,
          actionLabel: actionLabel,
          onAction: onAction);

  factory _DefaultItem.friendRow(List<User> friends) =>
      _DefaultItem._(type: _DefaultItemType.friendRow, friends: friends);

  factory _DefaultItem.divider() =>
      _DefaultItem._(type: _DefaultItemType.divider);

  factory _DefaultItem.post(Post post) =>
      _DefaultItem._(type: _DefaultItemType.postItem, post: post);

  factory _DefaultItem.topic(Topic topic) =>
      _DefaultItem._(type: _DefaultItemType.topicItem, topic: topic);

  factory _DefaultItem.comicEvent(ComicEvent event) =>
      _DefaultItem._(type: _DefaultItemType.comicEventItem, comicEvent: event);

  factory _DefaultItem.spacer() =>
      _DefaultItem._(type: _DefaultItemType.spacer);
}
