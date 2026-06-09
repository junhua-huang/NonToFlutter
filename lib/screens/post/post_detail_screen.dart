import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/screens/profile/user_profile_screen.dart';
import 'package:facebook_clone/screens/search/search_results_screen.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/report_service.dart';
import 'package:facebook_clone/services/api/search_service.dart';
import 'package:facebook_clone/services/post_interaction_notifier.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/comment_section.dart';
import 'package:facebook_clone/widgets/media_viewer.dart';
import 'package:facebook_clone/widgets/rich_text_content.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_social_video/flutter_social_video.dart';
import 'package:video_player/video_player.dart';

/// 帖子详情页 — 顶部展示帖子内容，下方集成统一评论区
class PostDetailScreen extends ConsumerStatefulWidget {
  final int postId;
  final Post? initialPost;

  const PostDetailScreen({super.key, required this.postId, this.initialPost});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  Post? _post;
  bool _hasFreshData = false;
  bool _isLoading = true;
  bool _isLikingPost = false;

  final ScrollController _scrollController = ScrollController();

  Color get _xBlack => AppColors.textPrimary;
  Color get _xDarkGrey => AppColors.textSecondary;
  Color get _xBlue => AppColors.primary;
  Color get _xLightGrey => AppColors.borderLight;
  static const Color _xLikeRed = Color(0xFFF91880);

  static const List<String> _reportReasons = [
    '垃圾信息', '骚扰', '仇恨言论', '暴力内容', '其他'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null) {
      _post = widget.initialPost;
      _isLoading = false;
    }
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final postResp = await PostService().getPost(widget.postId);
      if (postResp.success && postResp.data != null) {
        final data = postResp.data as Map<String, dynamic>;
        final postJson = data['post'] ?? data;
        setState(() {
          _post = Post.fromJson(postJson as Map<String, dynamic>);
          _hasFreshData = true;
        });
        // 记录浏览
        try {
          await PostService().recordView(widget.postId);
          if (mounted) {
            setState(() {
              _post = _post!.copyWith(viewCount: _post!.viewCount + 1);
            });
            PostInteractionNotifier().notifyViewChanged(widget.postId, _post!.viewCount);
          }
        } catch (e) {
          debugPrint('Record view error: $e');
        }
      }
    } catch (e) {
      debugPrint('PostDetail load error: $e');
    } finally {
      if (!_hasFreshData) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 乐观点赞
  Future<void> _toggleLike() async {
    if (_post == null) return;
    if (_isLikingPost) return;

    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || auth.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再点赞'), duration: Duration(seconds: 2)),
      );
      return;
    }

    _isLikingPost = true;
    final wasLiked = _post!.isLiked ?? false;
    final oldPost = _post!;

    setState(() {
      _post = _post!.copyWith(
        isLiked: !wasLiked,
        likeCount: wasLiked ? _post!.likeCount - 1 : _post!.likeCount + 1,
      );
    });
    try {
      if (wasLiked) {
        await PostService().unlikePost(_post!.id);
      } else {
        await PostService().likePost(_post!.id);
      }
      PostInteractionNotifier().notifyLikeChanged(_post!.id, !wasLiked, _post!.likeCount);
    } catch (e) {
      setState(() => _post = oldPost);
    } finally {
      _isLikingPost = false;
    }
  }

  Future<void> _showPostStatsDetail(Post post) async {
    try {
      final resp = await PostService().getPostStats(post.id);
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('获取统计失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _navigateToTopic(String topicName) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TopicSearchResultsScreen(topicName: topicName),
    ));
  }

  void _navigateToProfile(String username) {
    _searchAndNavigateToUser(username);
  }

  Future<void> _searchAndNavigateToUser(String username) async {
    try {
      final resp = await SearchService().searchUsers(username, page: 1);
      if (resp.success && resp.data != null) {
        final data = resp.data;
        List userList = [];
        if (data is List) {
          userList = data;
        } else if (data is Map) {
          userList = data['users'] ?? data['items'] ?? [];
        }
        if (userList.isNotEmpty) {
          final userJson = userList.firstWhere(
            (u) => (u['username'] ?? '').toString().toLowerCase() == username.toLowerCase(),
            orElse: () => userList.first,
          ) as Map<String, dynamic>;
          final user = User.fromJson(userJson);
          if (!mounted) return;
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => UserProfileScreen(user: user),
          ));
        }
      }
    } catch (e) {
      debugPrint('Search user error: $e');
    }
  }

  /// 删除帖子
  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除帖子'),
        content: const Text('确定要删除这条帖子吗？此操作不可撤销'),
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
    if (confirmed == true && mounted) {
      try {
        final resp = await PostService().deletePost(widget.postId);
        if (resp.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('帖子已删除'), backgroundColor: Colors.green),
            );
            Navigator.of(context).pop();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message ?? '删除失败'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 举报帖子
  Future<void> _reportPost() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('举报帖子'),
        children: [
          ..._reportReasons.map((r) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Text(r),
          )),
        ],
      ),
    );
    if (reason != null && mounted) {
      try {
        final resp = await ReportService().reportPost(widget.postId, reason);
        if (resp.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('举报已提交'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message ?? '举报失败'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('举报失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _xBlack),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('帖子', style: TextStyle(color: _xBlack, fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _xBlue))
          : _post == null
              ? Center(child: Text('帖子不存在', style: TextStyle(color: _xDarkGrey)))
              : Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(child: _buildPostCard()),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Divider(height: 1, color: _xLightGrey),
                            ),
                          ),
                          SliverFillRemaining(
                            hasScrollBody: true,
                            child: CommentSection(
                              targetType: 'post',
                              targetId: widget.postId,
                              onCommentCountChanged: (count) {
                                if (mounted) {
                                  setState(() => _post = _post!.copyWith(commentCount: count));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPostCard() {
    final post = _post!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Author
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
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
                child: ImageUtils.buildAvatar(post.user, radius: 20),
              ),
              const SizedBox(width: 12),
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
                      child: Text(post.user?.displayName ?? '未知用户',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _xBlack)),
                    ),
                    SizedBox(height: 2),
                    GestureDetector(
                      onTap: () {
                        if (post.user != null) {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => UserProfileScreen(user: post.user!),
                          ));
                        }
                      },
                      child: Text('@${post.user?.username ?? ''}  ·  ${AppDateUtils.formatTimeAgo(post.createdAt)}',
                        style: TextStyle(color: _xDarkGrey, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (ctx) {
                  final auth = ref.read(authProvider);
                  final isOwner = post.userId == auth.user?.id;
                  return PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, size: 18, color: _xDarkGrey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deletePost();
                      } else if (value == 'report') {
                        _reportPost();
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (isOwner)
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      const PopupMenuItem(value: 'report', child: Text('举报')),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        // Content - RichText with #topic and @mention highlighting
        if (post.content != null && post.content!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: RichTextContent(
              text: post.content!,
              style: TextStyle(fontSize: 15, height: 1.45, color: _xBlack),
              onTopicTap: _navigateToTopic,
              onMentionTap: _navigateToProfile,
            ),
          ),
        // Image (tap to zoom) - single or gallery
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
                  onTap: () => ImageViewerScreen.show(context, allImages, heroTag: 'detail_img_${post.id}_0'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Hero(
                      tag: 'detail_img_${post.id}_0',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ImageUtils.buildPostImage(allImages[0], width: double.infinity),
                      ),
                    ),
                  ),
                );
              }
              return ImageGalleryGrid(imageUrls: allImages, maxHeight: 300, post: post);
            }(),
          ),
        // Video
        if (post.hasVideo)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
            child: kIsWeb
                ? _WebVideoPlayer(
                    videoUrl: post.videoUrl!,
                    coverUrl: post.thumbnailUrl
                        ?? (post.images != null && post.images!.isNotEmpty
                            ? post.images![0]
                            : null),
                  )
                : InlineVideoPlayer(
                    videoUrl: post.videoUrl!,
                    coverUrl: post.thumbnailUrl
                        ?? (post.images != null && post.images!.isNotEmpty
                            ? post.images![0]
                            : null),
                    aspectRatio: 16 / 9,
                    pauseWhenHidden: true,
                  ),
          ),
        // Actions
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 16, 12),
          child: Row(
            children: [
              _Action(icon: Icons.comment_outlined, count: post.commentCount, onTap: () {
                // Scroll to comment section
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              }),
              const SizedBox(width: 8),
              _Action(
                icon: post.isLiked == true ? Icons.favorite : Icons.favorite_border,
                count: post.likeCount,
                color: post.isLiked == true ? _xLikeRed : null,
                onTap: _toggleLike,
              ),
              const SizedBox(width: 8),
              _Action(icon: Icons.bar_chart, count: post.viewCount, onTap: () => _showPostStatsDetail(post)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const _Action({required this.icon, this.count = 0, this.color, required this.onTap});

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
              Text(count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}K' : '$count',
                style: TextStyle(color: color ?? AppColors.textSecondary, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Web 视频回退：HTML5 <video>，media_kit 不支持 Web ──
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
              Positioned.fill(child: Image.network(cover, fit: BoxFit.cover)),
            if (!_initialized && cover == null)
              const ColoredBox(color: Color(0xFF1A1A1A)),
            GestureDetector(
              onTap: _togglePlay,
              child: AnimatedOpacity(
                opacity: _isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x99000000),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
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