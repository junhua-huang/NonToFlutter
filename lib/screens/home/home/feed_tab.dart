import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/providers/feed_notifier.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/widgets/nonto_header_search_bar.dart';
import 'package:nonto/widgets/authenticated_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nonto/services/post_interaction_notifier.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/post_card.dart';
import 'package:nonto/widgets/shimmer_skeletons.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';
import 'package:nonto/utils/bar_scroll_handler.dart';

enum FeedTrackType { recommended, following }

class FeedTrack {
  final FeedTrackType type;
  final String label;
  final String key;

  const FeedTrack(this.type, this.label, this.key);
}

class _TwitterFeedTabBar extends StatelessWidget {
  final List<FeedTrack> tracks;
  final FeedTrack selectedTrack;
  final ValueChanged<FeedTrack> onSelect;

  const _TwitterFeedTabBar({
    required this.tracks,
    required this.selectedTrack,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight),
        ),
      ),
      child: Row(
        children: tracks.map((track) {
          final selected = track.key == selectedTrack.key;
          return Expanded(
            child: InkWell(
              onTap: () => onSelect(track),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        track.label,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: selected ? 28 : 0,
                    height: 4,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class FeedTab extends ConsumerStatefulWidget {
  const FeedTab({super.key});

  /// Notifier for optimistic post updates (e.g. after creating a post)
  static final ValueNotifier<Post?> newPostNotifier = ValueNotifier(null);

  @override
  ConsumerState<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<FeedTab> {
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);

  /// 刷新节流锁：防止连续下拉触发多次 refreshPosts()，
  /// 否则 SmartRefresher 状态机会错乱，表现为列表无法滑动。
  bool _isRefreshing = false;
  FeedTrack _selectedTrack =
      const FeedTrack(FeedTrackType.recommended, '推荐', 'recommended');
  final List<FeedTrack> _tracks = const [
    FeedTrack(FeedTrackType.recommended, '推荐', 'recommended'),
    FeedTrack(FeedTrackType.following, '关注', 'following'),
  ];

  StreamSubscription<PostLikeEvent>? _likeSub;
  StreamSubscription<PostViewEvent>? _viewSub;

  void _onPostLikeEvent(PostLikeEvent event) {
    ref.read(feedProvider.notifier).updatePost(
          event.postId,
          (p) => p.copyWith(isLiked: event.isLiked, likeCount: event.likeCount),
        );
  }

  void _onPostViewEvent(PostViewEvent event) {
    ref.read(feedProvider.notifier).updatePost(
          event.postId,
          (p) => p.copyWith(viewCount: event.viewCount),
        );
  }

  @override
  void initState() {
    super.initState();
    FeedTab.newPostNotifier.addListener(_onNewPost);
    _likeSub = PostInteractionNotifier().onLikeChanged.listen(_onPostLikeEvent);
    _viewSub = PostInteractionNotifier().onViewChanged.listen(_onPostViewEvent);
  }

  @override
  void dispose() {
    FeedTab.newPostNotifier.removeListener(_onNewPost);
    _likeSub?.cancel();
    _viewSub?.cancel();
    _refreshController.dispose();
    super.dispose();
  }

  void _onNewPost() {
    final post = FeedTab.newPostNotifier.value;
    if (post != null && mounted) {
      ref.read(feedProvider.notifier).insertNewPost(post);
      FeedTab.newPostNotifier.value = null;
      if (_refreshController.isRefresh) {
        _refreshController.refreshCompleted();
      }
    }
  }

  Widget _buildFeedTrackRail() {
    return _TwitterFeedTabBar(
      tracks: _tracks,
      selectedTrack: _selectedTrack,
      onSelect: (track) {
        if (track.key == _selectedTrack.key) return;
        setState(() => _selectedTrack = track);
        ref.read(feedProvider.notifier).switchTrack(track.key);
      },
    );
  }

  /// 构建帖子列表内容 —— 始终返回 ListView.builder，避免 SmartRefresher ScrollController 失联
  ListView _buildFeedContent(FeedState feedState) {
    // 首次加载 + 无数据 → 显示骨架屏
    if (feedState.isInitialLoading && feedState.posts.isEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1,
        itemBuilder: (_, __) => const FeedSkeleton(),
      );
    }
    // 错误 + 无数据
    if (feedState.error != null && feedState.posts.isEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1,
        itemBuilder: (_, __) => Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            ErrorStateWidget(
              message: feedState.error!,
              onRetry: _refreshPosts,
            ),
          ],
        ),
      );
    }
    // 空列表
    if (feedState.posts.isEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1,
        itemBuilder: (_, __) => Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const EmptyStateWidget(
              icon: Icons.newspaper,
              title: '暂无动态',
              subtitle: '关注更多人后可查看更多内容',
            ),
          ],
        ),
      );
    }
    // 正常帖子列表
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: feedState.posts.length,
      itemBuilder: (_, i) => PostCard(
        post: feedState.posts[i],
        feedPosts: feedState.posts,
        onLike: () => _toggleLike(feedState.posts[i]),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(
              postId: feedState.posts[i].id,
              initialPost: feedState.posts[i],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadPosts() async {
    await ref.read(feedProvider.notifier).loadPosts();
    if (!mounted) return;
    final feedState = ref.read(feedProvider);
    if (feedState.hasMore) {
      _refreshController.loadComplete();
    } else {
      _refreshController.loadNoData();
    }
  }

  Future<void> _refreshPosts() async {
    // 先释放 SmartRefresher 的 header，避免网络刷新期间接管滚动手势。
    if (_isRefreshing) return;
    _isRefreshing = true;
    _refreshController.refreshCompleted(resetFooterState: true);
    unawaited(_refreshPostsInBackground());
  }

  Future<void> _refreshPostsInBackground() async {
    try {
      await ref.read(feedProvider.notifier).refreshPosts();
    } catch (e) {
      debugPrint('Feed refresh error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('刷新失败，请重试')),
        );
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _toggleLike(Post post) async {
    HapticFeedback.lightImpact();
    // Guard: login check
    final authState = ref.read(authProvider);
    if (!authState.isLoggedIn || authState.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先登录后再点赞'), duration: Duration(seconds: 2)),
      );
      return;
    }
    await ref.read(feedProvider.notifier).toggleLike(post.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 仅 AnimatedSlide 依赖 barVisibleProvider，局部 Consumer 避免全树重建
        Consumer(
          builder: (context, ref, _) {
            final barVisible = ref.watch(barVisibleProvider);
            final authState = ref.watch(authProvider);
            return AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: barVisible ? Offset.zero : const Offset(0, -1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: barVisible
                    ? (kToolbarHeight + MediaQuery.of(context).padding.top)
                    : 0,
                child: barVisible
                    ? AppBar(
                        leading: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: NontoHeaderAvatar(
                            user: authState.user,
                            radius: 18,
                            onTap: WideShellScope.isWideOf(context)
                                ? null
                                : () => Scaffold.of(context).openDrawer(),
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
                      )
                    : const SizedBox.shrink(),
              ),
            );
          },
        ),
        _buildFeedTrackRail(),
        Consumer(
          builder: (context, ref, _) {
            final feedState = ref.watch(feedProvider);
            return Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notif) {
                  if (_refreshController.isRefresh || feedState.isRefreshing) {
                    return false;
                  }
                  handleBarScrollNotification(notif, ref);
                  return false;
                },
                child: SmartRefresher(
                  controller: _refreshController,
                  enablePullDown: true,
                  enablePullUp: !feedState.isRefreshing && feedState.hasMore,
                  onRefresh: _refreshPosts,
                  onLoading: _loadPosts,
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
                  footer: CustomFooter(
                    builder: (context, mode) {
                      Widget body;
                      if (mode == LoadStatus.idle) {
                        body = Text('上拉加载更多',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13));
                      } else if (mode == LoadStatus.loading) {
                        body = const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                        );
                      } else if (mode == LoadStatus.failed) {
                        body = Text('加载失败，点击重试',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13));
                      } else if (mode == LoadStatus.canLoading) {
                        body = Text('松开加载更多',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13));
                      } else {
                        final doneText = feedState.feedStatus == 'fallback'
                            ? '下面是更早一些的动态'
                            : '你已经看完最近动态';
                        body = Text(doneText,
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13));
                      }
                      return Container(
                        height: 55,
                        alignment: Alignment.center,
                        child: body,
                      );
                    },
                  ),
                  // SmartRefresher 的 child 必须始终是 ListView，
                  // 否则下拉刷新后 widget 树替换会导致 ScrollController 失联，
                  // 造成列表无法滑动。
                  child: _buildFeedContent(feedState),
                ), // SmartRefresher
              ), // NotificationListener
            ); // return Expanded
          }, // Consumer builder
        ), // Consumer
      ], // Column children
    ); // Column
  } // build
} // class _FeedTabState
