import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/screens/profile/user_profile_screen.dart';
import 'package:facebook_clone/screens/search/search_results_screen.dart';
import 'package:facebook_clone/services/api/block_service.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/report_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/enhanced_media_viewer.dart';
import 'package:facebook_clone/widgets/media_viewer.dart';
import 'package:facebook_clone/widgets/rich_text_content.dart';
import 'package:facebook_clone/widgets/video_player_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('帖子统计'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('浏览量: ${stats['views'] ?? 0}'),
                Text('点赞数: ${stats['likes'] ?? post.likeCount}'),
                Text('评论数: ${stats['comments'] ?? post.commentCount}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取统计失败'), duration: Duration(seconds: 2)),
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
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择举报原因', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1),
            ..._reportReasons.map((r) => ListTile(
                  title: Text(r.label),
                  onTap: () => Navigator.pop(ctx, r.value),
                )),
            const Divider(height: 1),
            ListTile(
              title: const Text('取消', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      final resp = await ReportService().reportPost(post.id, reason);
      if (!context.mounted) return;
      if (resp.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('举报已提交'), duration: Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.message ?? '举报失败'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('举报失败，请稍后重试'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _showBlockConfirmDialog(BuildContext context, Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('屏蔽用户'),
        content: Text('确定要屏蔽 @${post.user?.username ?? '该用户'} 吗？\n\n屏蔽后你将看不到该用户的动态，对方也不会收到通知。'),
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
          SnackBar(content: Text('已屏蔽 @${post.user?.username ?? '该用户'}'), duration: const Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.message ?? '屏蔽失败'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('屏蔽失败，请稍后重试'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _showDeleteConfirmDialog(BuildContext context, Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除帖子'),
        content: const Text('确定要删除这条帖子吗？此操作不可撤销。'),
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
          const SnackBar(content: Text('帖子已删除'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.message ?? '删除失败'), backgroundColor: Colors.red, duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，请重试'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
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
                      Navigator.push(context, MaterialPageRoute(
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
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => UserProfileScreen(user: post.user!),
                            ));
                          }
                        },
                        child: Text(
                          post.user?.displayName ?? '未知用户',
                          style: const TextStyle(
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
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => UserProfileScreen(user: post.user!),
                            ));
                          }
                        },
                        child: Text(
                          '@${post.user?.username ?? ''}  ·  ${AppDateUtils.formatTimeAgo(post.createdAt)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                // More button
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    final currentUserId = context.read<AuthProvider>().user?.id;
                    final isOwnPost = currentUserId != null && post.userId == currentUserId;
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.report_outlined),
                              title: const Text('举报帖子'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _showReportDialog(context, post);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.block_outlined),
                              title: const Text('屏蔽用户'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _showBlockConfirmDialog(context, post);
                              },
                            ),
                            if (isOwnPost)
                              ListTile(
                                leading: const Icon(Icons.delete_outline, color: Colors.red),
                                title: const Text('删除帖子', style: TextStyle(color: Colors.red)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showDeleteConfirmDialog(context, post);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                  style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textPrimary),
                  onTopicTap: (topicName) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => TopicSearchResultsScreen(topicName: topicName),
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
                      final items = _buildMediaItems(post, allImages, feedPosts);
                      EnhancedImageViewerScreen.show(context, items);
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
          if (post.hasVideo)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
              child: VideoPlayerWidget(
                videoUrl: post.videoUrl,
                thumbnailUrl: (post.images != null && post.images!.isNotEmpty) ? post.images![0] : null,
                height: 200,
                width: double.infinity,
              ),
            ),
          // --- Actions ---
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
            child: Row(
              children: [
                _ActionIcon(icon: Icons.comment_outlined, count: post.commentCount, onTap: onTap),
                _ActionIcon(
                  icon: post.isLiked == true ? Icons.favorite : Icons.favorite_border,
                  count: post.likeCount,
                  color: post.isLiked == true ? const Color(0xFFF91880) : null,
                  onTap: onLike ?? () {},
                ),
                _ActionIcon(icon: Icons.bar_chart, count: post.viewCount, onTap: () => _showPostStats(context, post)),
              ],
            ),
          ),
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Divider(height: 1, color: AppColors.borderLight),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    this.count = 0,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}K' : '$count',
                style: TextStyle(color: color ?? AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportOption {
  final String value;
  final String label;
  const _ReportOption(this.value, this.label);
}

/// Build a list of PostMediaItem from current post and nearby posts
List<PostMediaItem> _buildMediaItems(Post post, List<String> allImages, List<Post>? feedPosts) {
  final items = <PostMediaItem>[];
  // Current post's media
  items.add(PostMediaItem(post: post, mediaUrls: allImages));
  // Nearby posts with media
  if (feedPosts != null) {
    for (final p in feedPosts) {
      if (p.id == post.id) continue;
      final urls = <String>[];
      if (p.images != null) {
        for (final u in p.images!) {
          if (u.isNotEmpty) urls.add(u);
        }
      }
      if (urls.isNotEmpty) {
        items.add(PostMediaItem(post: p, mediaUrls: urls));
      }
    }
  }
  return items;
}
