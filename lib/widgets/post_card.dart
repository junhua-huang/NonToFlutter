import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/services/api/block_service.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/report_service.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/enhanced_media_viewer.dart';
import 'package:nonto/widgets/media_viewer.dart';
import 'package:nonto/widgets/nonto/nonto_post_action_bar.dart';
import 'package:nonto/widgets/rich_text_content.dart';
import 'package:nonto/widgets/twitter_bottom_sheet.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_social_video/flutter_social_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// 统一帖子卡片组件 — 首页 Feed、他人主页、我的主页共用
class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  /// Nearby posts for media viewer vertical swipe (e.g., all posts in feed)
  final List<Post>? feedPosts;

  const PostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.onLike,
    this.onLongPress,
    this.onDelete,
    this.feedPosts,
  });

  Future<void> _showPostStats(BuildContext context, Post post) async {
    try {
      final resp = await PostService().getPostStats(post.id);
      if (!context.mounted) return;
      if (resp.success && resp.data != null) {
        final stats = resp.data as Map<String, dynamic>;
        final colors = Theme.of(context).colorScheme;
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽指示条
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('帖子统计',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  _StatRow(
                    icon: Icons.visibility_outlined,
                    label: '浏览量',
                    value: '${stats['views'] ?? 0}',
                  ),
                  const SizedBox(height: 14),
                  _StatRow(
                    icon: Icons.favorite_border,
                    label: '点赞数',
                    value: '${stats['likes'] ?? post.likeCount}',
                  ),
                  const SizedBox(height: 14),
                  _StatRow(
                    icon: Icons.chat_bubble_outline,
                    label: '评论数',
                    value: '${stats['comments'] ?? post.commentCount}',
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('获取统计失败'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('获取统计失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  static const List<_ReportOption> _reportReasons = [
    _ReportOption('spam', '骚扰信息'),
    _ReportOption('fake', '虚假信息'),
    _ReportOption('violence', '暴力内容'),
    _ReportOption('hate', '仇恨言论'),
    _ReportOption('other', '其他'),
  ];

  Future<void> _showReportDialog(BuildContext context, Post post) async {
    final reason = await TwitterBottomSheet.show<String>(
      context,
      groupLabel: '选择举报原因',
      options: _reportReasons
          .map((r) => TwitterSheetOption(
                icon: Icons.flag_outlined,
                label: r.label,
                value: r.value,
              ))
          .toList(),
    );
    if (reason == null || !context.mounted) return;
    try {
      final resp = await ReportService().reportPost(post.id, reason);
      if (!context.mounted) return;
      if (resp.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('举报已提交'), duration: Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(resp.message ?? '举报失败'),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('举报失败，请稍后重试'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _showBlockConfirmDialog(BuildContext context, Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('屏蔽用户',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
            '确定要屏蔽@${post.user?.username ?? '该用户'} 吗？\n\n屏蔽后你将看不到该用户的动态，对方也不会收到通知。',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认屏蔽'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final resp = await BlockService().blockUser(post.userId);
      if (!context.mounted) return;
      if (resp.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已屏蔽@${post.user?.username ?? '该用户'}'),
              duration: const Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(resp.message ?? '屏蔽失败'),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('屏蔽失败，请稍后重试'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _showDeleteConfirmDialog(BuildContext context, Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除帖子',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('确定要删除这条帖子吗？此操作不可撤销。',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final resp = await PostService().deletePost(post.id);
      if (!context.mounted) return;
      if (resp.success) {
        onDelete?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('帖子已删除'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(resp.message ?? '删除失败'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('删除失败，请重试'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Header ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                GestureDetector(
                  onTap: () {
                    if (post.user != null) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(user: post.user!),
                          ));
                    }
                  },
                  child: ImageUtils.buildAvatar(post.user, radius: 20),
                ),
                const SizedBox(width: 12),
                // Name + username/time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (post.user != null) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UserProfileScreen(user: post.user!),
                                ));
                          }
                        },
                        child: Text(
                          post.user?.displayName ?? '未知用户',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () {
                          if (post.user != null) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UserProfileScreen(user: post.user!),
                                ));
                          }
                        },
                        child: Text(
                          '@${post.user?.username ?? ''}  ·  ${AppDateUtils.formatTimeAgo(post.createdAt)}',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                // More button
                IconButton(
                  icon: Icon(Icons.more_horiz,
                      size: 18, color: AppColors.textSecondary),
                  onPressed: () async {
                    final currentUserId = ProviderScope.containerOf(context)
                        .read(authProvider)
                        .user
                        ?.id;
                    final isOwnPost =
                        currentUserId != null && post.userId == currentUserId;

                    final options = <TwitterSheetOption<String>>[
                      const TwitterSheetOption(
                          icon: Icons.report_outlined,
                          label: '举报帖子',
                          value: 'report'),
                      const TwitterSheetOption(
                          icon: Icons.block_outlined,
                          label: '屏蔽用户',
                          value: 'block'),
                      if (isOwnPost)
                        const TwitterSheetOption(
                            icon: Icons.delete_outline,
                            label: '删除帖子',
                            value: 'delete',
                            isDestructive: true),
                    ];

                    final action = await TwitterBottomSheet.show<String>(
                        context,
                        options: options);
                    if (action == null || !context.mounted) return;
                    switch (action) {
                      case 'report':
                        _showReportDialog(context, post);
                        break;
                      case 'block':
                        _showBlockConfirmDialog(context, post);
                        break;
                      case 'delete':
                        _showDeleteConfirmDialog(context, post);
                        break;
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          // --- Content ---
          if (post.content != null && post.content!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Builder(
                builder: (context) => RichTextContent(
                  text: post.content!,
                  style: TextStyle(
                      fontSize: 15, height: 1.4, color: AppColors.textPrimary),
                  onTopicTap: (topicName) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TopicSearchResultsScreen(topicName: topicName),
                        ));
                  },
                ),
              ),
            ),
          // --- Image ---
          if (post.hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
              child: () {
                final allImages = <String>[];
                if (post.images != null) {
                  for (final u in post.images!) {
                    if (u.isNotEmpty) allImages.add(u);
                  }
                }
                if (allImages.isEmpty) return const SizedBox.shrink();
                if (allImages.length == 1) {
                  return GestureDetector(
                    onTap: () {
                      final items =
                          _buildMediaItems(post, allImages, feedPosts);
                      final index = _indexForPost(items, post.id);
                      EnhancedImageViewerScreen.show(context, items,
                          initialPostIndex: index);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Hero(
                        tag: 'feed_img_${post.id}_0',
                        child: ImageUtils.buildPostImage(
                          allImages[0],
                          fit: BoxFit.fitWidth,
                          width: double.infinity,
                        ),
                      ),
                    ),
                  );
                }
                return ImageGalleryGrid(
                  imageUrls: allImages,
                  maxHeight: 400,
                  post: post,
                  feedPosts: feedPosts,
                );
              }(),
            ),
          // --- Video ---
          if (post.hasVideo && post.videoUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
              child: kIsWeb
                  ? _WebVideoPlayer(
                      videoUrl: post.videoUrl!,
                      coverUrl: post.thumbnailUrl ??
                          (post.images != null && post.images!.isNotEmpty
                              ? post.images![0]
                              : null),
                    )
                  : InlineVideoPlayer(
                      videoUrl: post.videoUrl!,
                      coverUrl: post.thumbnailUrl ??
                          (post.images != null && post.images!.isNotEmpty
                              ? post.images![0]
                              : null),
                      playerPool: videoPlayerPool,
                      pauseWhenHidden: true,
                    ),
            ),
          // --- Actions ---
          NontoPostActionBar(
            commentCount: post.commentCount,
            likeCount: post.likeCount,
            viewCount: post.viewCount,
            isLiked: post.isLiked == true,
            onComment: onTap,
            onLike: onLike ?? () {},
            onView: () => _showPostStats(context, post),
          ),
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: AppColors.borderLight),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 22, color: colors.primary),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 15, color: colors.onSurface)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.onSurface)),
      ],
    );
  }
}

class _ReportOption {
  final String value;
  final String label;
  const _ReportOption(this.value, this.label);
}

/// Build a list of PostMediaItem from current post and nearby posts
int _indexForPost(List<PostMediaItem> items, int postId) {
  for (int i = 0; i < items.length; i++) {
    if (items[i].post.id == postId) return i;
  }
  return 0;
}

List<PostMediaItem> _buildMediaItems(
    Post post, List<String> allImages, List<Post>? feedPosts) {
  final items = <PostMediaItem>[];
  // Helper: extract media URLs from a post
  List<String> mediaUrlsOf(Post p) {
    final urls = <String>[];
    if (p.images != null) {
      for (final u in p.images!) {
        if (u.isNotEmpty) urls.add(u);
      }
    }
    return urls;
  }

  if (feedPosts == null || feedPosts.isEmpty) {
    items.add(PostMediaItem(post: post, mediaUrls: allImages));
    return items;
  }

  // Find current post position
  final currentIdx = feedPosts.indexWhere((p) => p.id == post.id);
  if (currentIdx < 0) {
    items.add(PostMediaItem(post: post, mediaUrls: allImages));
    return items;
  }

  // Collect before/after posts in feed order (only those with media)
  final before = <Post>[];
  final after = <Post>[];
  for (int i = 0; i < feedPosts.length; i++) {
    if (i == currentIdx) continue;
    final p = feedPosts[i];
    if (p.hasImage || p.hasVideo) {
      if (i < currentIdx) {
        before.add(p);
      } else {
        after.add(p);
      }
    }
  }

  // Build items: before (feed order) → current → after (feed order)
  for (final p in before) {
    items.add(PostMediaItem(post: p, mediaUrls: mediaUrlsOf(p)));
  }
  items.add(PostMediaItem(post: post, mediaUrls: allImages));
  for (final p in after) {
    items.add(PostMediaItem(post: p, mediaUrls: mediaUrlsOf(p)));
  }

  return items;
}

/// Web 端视频播放器 — media_kit 不支持 Web，改用 video_player（浏览器原生 <video>）
class _WebVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? coverUrl;
  const _WebVideoPlayer({required this.videoUrl, this.coverUrl});

  @override
  State<_WebVideoPlayer> createState() => _WebVideoPlayerState();
}

class _WebVideoPlayerState extends State<_WebVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (mounted) setState(() => _initialized = true);
    }).catchError((e) {
      debugPrint('Web video init error: $e');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_initialized) return;
    setState(() {
      _isPlaying = !_isPlaying;
      _isPlaying ? _controller.play() : _controller.pause();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cover = widget.coverUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: _initialized ? _controller.value.aspectRatio : 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_initialized) VideoPlayer(_controller),
            if (!_initialized && cover != null)
              Positioned.fill(
                child: Image.network(cover, fit: BoxFit.cover),
              ),
            if (!_initialized && cover == null)
              const ColoredBox(color: Color(0xFF1A1A1A)),
            // Play/Pause overlay
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0x80000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
