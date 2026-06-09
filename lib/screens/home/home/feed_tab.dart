import 'dart:async';

import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/providers/core_providers.dart';
import 'package:facebook_clone/providers/feed_notifier.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:facebook_clone/services/post_interaction_notifier.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/post_card.dart';
import 'package:facebook_clone/widgets/shimmer_skeletons.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

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

  Future<void> _loadPosts() async {
    await ref.read(feedProvider.notifier).loadPosts();
    _refreshController.loadComplete();
  }

  Future<void> _refreshPosts() async {
    await ref.read(feedProvider.notifier).refreshPosts();
    _refreshController.refreshCompleted();
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
                          child: GestureDetector(
                            onTap: () => Scaffold.of(context).openDrawer(),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.primary,
                              backgroundImage: authState.user?.avatarUrl != null &&
                                      authState.user!.avatarUrl!.isNotEmpty
                                  ? NetworkImage(
                                      ImageUtils.resolveUrl(authState.user!.avatarUrl),
                                    )
                                  : null,
                              child: (authState.user?.avatarUrl == null ||
                                      authState.user!.avatarUrl!.isEmpty)
                                  ? Text(
                                      authState.user?.initials ?? '?',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
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
                      )
                    : const SizedBox.shrink(),
              ),
            );
          },
        ),
        Consumer(
          builder: (context, ref, _) {
            final feedState = ref.watch(feedProvider);
            return Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notif) {
                  if (notif.dragDetails != null) {
                    final delta = notif.scrollDelta ?? 0;
                    final barVisible = ref.read(barVisibleProvider);
                    if (delta > 5 && barVisible) {
                      ref.read(barVisibleProvider.notifier).state = false;
                    } else if (delta < -5 && !barVisible) {
                      ref.read(barVisibleProvider.notifier).state = true;
                    }
                  }
                  return false;
                },
                child: SmartRefresher(
              controller: _refreshController,
              enablePullDown: true,
              enablePullUp: feedState.hasMore,
              onRefresh: _refreshPosts,
              onLoading: _loadPosts,
              header: const WaterDropHeader(
                complete:
                    Text('刷新成功', style: TextStyle(color: AppColors.primary)),
                waterDropColor: AppColors.primary,
              ),
              footer: CustomFooter(
                builder: (context, mode) {
                  Widget body;
                  if (mode == LoadStatus.idle) {
                    body = const Text('上拉加载更多',
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
                    body = const Text('加载失败，点击重试',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13));
                  } else if (mode == LoadStatus.canLoading) {
                    body = const Text('松开加载更多',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13));
                  } else {
                    body = const Text('没有更多了',
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
              child: feedState.isLoading && feedState.posts.isEmpty
                  ? const FeedSkeleton()
                  : feedState.error != null && feedState.posts.isEmpty
                      ? ErrorStateWidget(
                          message: feedState.error!,
                          onRetry: _refreshPosts,
                        )
                      : feedState.posts.isEmpty
                          ? const EmptyStateWidget(
                              icon: Icons.newspaper,
                              title: '暂无动态',
                              subtitle: '关注更多人后可查看更多内容',
                            )
                          : ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              itemCount: feedState.posts.length,
                              itemBuilder: (_, i) => PostCard(
                                post: feedState.posts[i],
                                feedPosts: feedState.posts,
                                onLike: () =>
                                    _toggleLike(feedState.posts[i]),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => PostDetailScreen(
                                          postId: feedState.posts[i].id,
                                          initialPost:
                                              feedState.posts[i])),
                                ),
                              ),
                            ),
            ), // SmartRefresher
          ), // NotificationListener
        ); // return Expanded
      }, // Consumer builder
    ), // Consumer
      ], // Column children
    ); // Column
  } // build
} // class _FeedTabState
