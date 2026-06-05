import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/recommendation_service.dart';
import 'package:facebook_clone/services/cache_service.dart';
import 'package:facebook_clone/services/post_interaction_notifier.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/post_card.dart';
import 'package:facebook_clone/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  /// Notifier for optimistic post updates (e.g. after creating a post)
  static final ValueNotifier<Post?> newPostNotifier = ValueNotifier(null);

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final List<Post> _posts = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  String? _error;
  bool _activated = false;

  // Like debounce set to prevent concurrent requests
  final Set<int> _likingPostIds = {};

  void _onPostLikeEvent(PostLikeEvent event) {
    if (!mounted) return;
    final idx = _posts.indexWhere((p) => p.id == event.postId);
    if (idx == -1) return;
    setState(() {
      _posts[idx] = _posts[idx].copyWith(
        isLiked: event.isLiked,
        likeCount: event.likeCount,
      );
    });
  }

  void _onPostViewEvent(PostViewEvent event) {
    if (!mounted) return;
    final idx = _posts.indexWhere((p) => p.id == event.postId);
    if (idx == -1) return;
    setState(() {
      _posts[idx] = _posts[idx].copyWith(viewCount: event.viewCount);
    });
  }

  @override
  void initState() {
    super.initState();
    FeedTab.newPostNotifier.addListener(_onNewPost);
    TabActivationNotifier.currentTab.addListener(_onTabActivated);
    PostInteractionNotifier().onLikeChanged.listen(_onPostLikeEvent);
    PostInteractionNotifier().onViewChanged.listen(_onPostViewEvent);
    // Trigger load if already active (IndexedStack may have built this tab before notifier fired)
    if (TabActivationNotifier.currentTab.value == 0) {
      _activate();
    }
  }

  @override
  void dispose() {
    TabActivationNotifier.currentTab.removeListener(_onTabActivated);
    FeedTab.newPostNotifier.removeListener(_onNewPost);
    _refreshController.dispose();
    super.dispose();
  }

  void _onTabActivated() {
    if (!_activated && TabActivationNotifier.currentTab.value == 0) {
      _activate();
    }
  }

  void _activate() {
    _activated = true;
    _refreshPosts();
  }

  void _onNewPost() {
    final post = FeedTab.newPostNotifier.value;
    if (post != null && mounted) {
      setState(() {
        // Insert at top if not already present
        if (!_posts.any((p) => p.id == post.id)) {
          _posts.insert(0, post);
        }
      });
      FeedTab.newPostNotifier.value = null;
      // 如果 SmartRefresher 正处于刷新状态，结束刷新，避免页面冻结
      if (_refreshController.isRefresh) {
        _refreshController.refreshCompleted();
      }
    }
  }

  Future<void> _loadPosts() async {
    if (_isLoading) return;
    _isLoading = true;

    // Try cache first for page 1
    if (_page == 1) {
      final cached = await CacheService().getList(CacheKeys.feed(_page));
      if (cached != null && cached.isNotEmpty && mounted) {
        // Only show cache if list is currently empty (initial load)
        if (_posts.isEmpty) {
          setState(() {
            _posts.addAll(cached.map((e) => Post.fromJson(e as Map<String, dynamic>)));
          });
        }
      }
    }

    try {
      final resp = await RecommendationService().getFeed(page: _page);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final List postsJson = data['posts'] ?? data['items'] ?? [];
        final posts = postsJson.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
        setState(() {
          if (_page == 1) _posts.clear();
          _posts.addAll(posts);
          _hasMore = data['has_more'] == true || posts.length >= 20;
          _page++;
        });
        // Cache page 1
        if (_page <= 2) {
          await CacheService().set(CacheKeys.feed(1), postsJson, expireMinutes: 3);
        }
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      debugPrint('FeedTab loadPosts error: $e');
      // fallback to basic feed
      try {
        final resp = await PostService().getFeed(page: _page);
        if (resp.success && resp.data != null) {
          final data = resp.data as Map<String, dynamic>;
          final List postsJson = data['posts'] ?? data['items'] ?? [];
          final posts = postsJson.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
          setState(() {
            if (_page == 1) _posts.clear();
            _posts.addAll(posts);
            _hasMore = data['has_more'] == true;
            _page++;
          });
          if (_page <= 2) {
            await CacheService().set(CacheKeys.feed(1), postsJson, expireMinutes: 3);
          }
        } else {
          setState(() => _hasMore = false);
        }
      } catch (e2) {
        debugPrint('FeedTab fallback error: $e2');
        setState(() => _hasMore = false);
        if (_posts.isEmpty && mounted) setState(() => _error = '加载失败');
      }
    } finally {
      _isLoading = false;
      _refreshController.loadComplete();
    }
  }

  Future<void> _refreshPosts() async {
    _page = 1;
    _hasMore = true;
    _error = null;
    await CacheService().remove(CacheKeys.feed(1));
    await _loadPosts();
    _refreshController.refreshCompleted();
  }

  Future<void> _toggleLike(Post post, int index) async {
    // Guard: prevent concurrent requests
    if (_likingPostIds.contains(post.id)) return;

    // Guard: login check
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再点赞'), duration: Duration(seconds: 2)),
      );
      return;
    }

    _likingPostIds.add(post.id);
    final wasLiked = post.isLiked ?? false;
    setState(() {
      _posts[index] = post.copyWith(
        isLiked: !wasLiked,
        likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
      );
    });
    try {
      if (wasLiked) {
        await PostService().unlikePost(post.id);
      } else {
        await PostService().likePost(post.id);
      }
      PostInteractionNotifier().notifyLikeChanged(post.id, !wasLiked, wasLiked ? post.likeCount - 1 : post.likeCount + 1);
    } catch (e) {
      if (!mounted) return;
      setState(() { _posts[index] = post; });
    } finally {
      _likingPostIds.remove(post.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
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
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: GestureDetector(
                onTap: () => Scaffold.of(context).openDrawer(),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary,
                  backgroundImage: auth.user?.avatarUrl != null && auth.user!.avatarUrl!.isNotEmpty
                      ? NetworkImage(
                          auth.user!.avatarUrl!.startsWith('http')
                              ? auth.user!.avatarUrl!
                              : '${AppConfig.baseUrl.replaceFirst('/api', '')}${auth.user!.avatarUrl}',
                        )
                      : null,
                  child: (auth.user?.avatarUrl == null || auth.user!.avatarUrl!.isEmpty)
                      ? Text(
                          auth.user?.initials ?? '?',
                          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
            ),
            title: Text(
              'NonTo',
              style: GoogleFonts.nunito(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            centerTitle: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
          ),
        ),
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
      enablePullUp: _hasMore,
      onRefresh: _refreshPosts,
      onLoading: _loadPosts,
      header: const WaterDropHeader(
        complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
        waterDropColor: AppColors.primary,
      ),
      footer: CustomFooter(
        builder: (context, mode) {
          Widget body;
          if (mode == LoadStatus.idle) {
            body = const Text('上拉加载更多', style: TextStyle(color: AppColors.textSecondary, fontSize: 13));
          } else if (mode == LoadStatus.loading) {
            body = const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
            );
          } else if (mode == LoadStatus.failed) {
            body = const Text('加载失败，点击重试', style: TextStyle(color: AppColors.textSecondary, fontSize: 13));
          } else if (mode == LoadStatus.canLoading) {
            body = const Text('松开加载更多', style: TextStyle(color: AppColors.textSecondary, fontSize: 13));
          } else {
            body = const Text('没有更多了', style: TextStyle(color: AppColors.textSecondary, fontSize: 13));
          }
          return Container(
            height: 55,
            alignment: Alignment.center,
            child: body,
          );
        },
      ),
      child: _isLoading && _posts.isEmpty
          ? const FeedSkeleton()
          : _error != null && _posts.isEmpty
          ? ErrorStateWidget(
              message: _error!,
              onRetry: () {
                setState(() { _error = null; });
                _refreshPosts();
              },
            )
          : _posts.isEmpty
          ? const EmptyStateWidget(
              icon: Icons.newspaper,
              title: '暂无动态',
              subtitle: '关注更多人后可查看更多内容',
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _posts.length,
              itemBuilder: (_, i) => PostCard(
                post: _posts[i],
                feedPosts: _posts,
                onLike: () => _toggleLike(_posts[i], i),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PostDetailScreen(postId: _posts[i].id, initialPost: _posts[i])),
                ),
              ),
            ),
    ),
          ),
        ),
      ],
    );
  }
}
