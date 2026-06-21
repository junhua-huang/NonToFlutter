import 'package:cached_network_image/cached_network_image.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/search_service.dart';
import 'package:nonto/services/post_interaction_notifier.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/widgets/comment_section.dart';
import 'package:nonto/widgets/rich_text_content.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolve relative URL to full URL
String _resolveUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  return '${AppConfig.baseUrl}/storage/$url';
}

/// A post-media item for the enhanced viewer
class PostMediaItem {
  final Post post;
  final List<String> mediaUrls; // images + video thumbnails

  const PostMediaItem({required this.post, required this.mediaUrls});
}

/// Enhanced image/video viewer with post info bar, swipe-between-posts, and interactive stats.
class EnhancedImageViewerScreen extends StatefulWidget {
  final List<PostMediaItem> items;
  final int initialPostIndex;
  final int initialMediaIndex;

  const EnhancedImageViewerScreen({
    super.key,
    required this.items,
    this.initialPostIndex = 0,
    this.initialMediaIndex = 0,
  });

  /// Convenience show method
  static void show(
    BuildContext context,
    List<PostMediaItem> items, {
    int initialPostIndex = 0,
    int initialMediaIndex = 0,
  }) {
    if (items.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => EnhancedImageViewerScreen(
          items: items,
          initialPostIndex: initialPostIndex,
          initialMediaIndex: initialMediaIndex,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<EnhancedImageViewerScreen> createState() =>
      _EnhancedImageViewerScreenState();
}

class _EnhancedImageViewerScreenState extends State<EnhancedImageViewerScreen> {
  late PageController _postPageController;
  late int _currentPostIndex;
  late int _currentMediaIndex;

  // Per-post PageController for image gallery
  final Map<int, PageController> _galleryControllers = {};

  // Mutable post states to reflect optimistic updates
  late Map<int, Post> _postStates;

  // Track which posts have been viewed to avoid double-counting
  final Set<int> _viewedPostIds = {};

  // Like debounce
  bool _isLikingPost = false;

  @override
  void initState() {
    super.initState();
    _currentPostIndex =
        widget.initialPostIndex.clamp(0, widget.items.length - 1);
    _currentMediaIndex = widget.initialMediaIndex;
    _postPageController = PageController(initialPage: _currentPostIndex);
    _postStates = {for (final item in widget.items) item.post.id: item.post};

    // Record view for initial post
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordViewIfNeeded(
          _postStates[widget.items[_currentPostIndex].post.id]!);
    });
  }

  @override
  void dispose() {
    _postPageController.dispose();
    for (final c in _galleryControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPostPageChanged(int index) {
    setState(() {
      _currentPostIndex = index;
      _currentMediaIndex = 0; // reset to first media of new post
    });
    _recordViewIfNeeded(_postStates[widget.items[index].post.id]!);
  }

  void _onMediaPageChanged(int postIdx, int mediaIdx) {
    setState(() => _currentMediaIndex = mediaIdx);
  }

  // ── 导航 helper：与 PostDetailScreen / PostCard 行为一致 ──────────

  /// 跳到用户个人主页（要求 [user] 非空）。
  void _navigateToUser(User user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)),
    );
  }

  /// 跳到话题搜索结果页。
  void _navigateToTopic(String topicName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicSearchResultsScreen(topicName: topicName),
      ),
    );
  }

  /// 通过用户名搜索后跳到个人主页（@提及点击使用，没有现成 user 对象时的兜底）。
  Future<void> _navigateToProfileByUsername(String username) async {
    try {
      final resp = await SearchService().searchUsers(username, page: 1);
      if (!mounted) return;
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
            (u) =>
                (u['username'] ?? '').toString().toLowerCase() ==
                username.toLowerCase(),
            orElse: () => userList.first,
          ) as Map<String, dynamic>;
          final user = User.fromJson(userJson);
          if (!mounted) return;
          _navigateToUser(user);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('未找到用户 @$username'),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint('Search user error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _postPageController,
            itemCount: widget.items.length,
            onPageChanged: _onPostPageChanged,
            itemBuilder: (context, postIdx) {
              return _buildPostPage(widget.items[postIdx], postIdx);
            },
          ),
          // Top bar: close button + media index indicator on same line
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  const Spacer(),
                  // Media index indicator: "2 / 5"
                  _buildMediaIndicator(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaIndicator() {
    final currentItem = widget.items[_currentPostIndex];
    final mediaUrls = currentItem.mediaUrls
        .map(_resolveUrl)
        .where((u) => u.isNotEmpty)
        .toList();
    if (mediaUrls.length <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${_currentMediaIndex + 1} / ${mediaUrls.length}',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _buildPostPage(PostMediaItem item, int postIdx) {
    final post = item.post;
    final currentPost = _postStates[post.id] ?? post;
    final mediaUrls =
        item.mediaUrls.map(_resolveUrl).where((u) => u.isNotEmpty).toList();

    if (!_galleryControllers.containsKey(postIdx)) {
      _galleryControllers[postIdx] = PageController(
        initialPage: postIdx == _currentPostIndex ? _currentMediaIndex : 0,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Image/Video Gallery – full screen
        if (mediaUrls.isNotEmpty)
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(mediaUrls[index]),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained * 0.5,
                maxScale: PhotoViewComputedScale.covered * 4,
                heroAttributes: PhotoViewHeroAttributes(
                    tag: 'enhanced_media_${post.id}_$index'),
                errorBuilder: (_, __, ___) => const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 48),
                      SizedBox(height: 8),
                      Text('图片加载失败',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                ),
              );
            },
            itemCount: mediaUrls.length,
            loadingBuilder: (context, event) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              );
            },
            pageController: _galleryControllers[postIdx],
            onPageChanged: (i) => _onMediaPageChanged(postIdx, i),
            backgroundDecoration:
                const BoxDecoration(color: Colors.transparent),
          )
        else
          const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),

        // Bottom-left: author name + short time
        Positioned(
          left: 16,
          right: 80,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Author name — 点击跳转到个人主页
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final u = currentPost.user;
                  if (u != null) _navigateToUser(u);
                },
                child: Text(
                  currentPost.user?.displayName ??
                      currentPost.user?.username ??
                      '未知用户',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Content text (rich text with #/@ highlights)
              if (currentPost.content != null &&
                  currentPost.content!.isNotEmpty)
                _PostContentText(
                  content: currentPost.content!,
                  onTopicTap: _navigateToTopic,
                  onMentionTap: _navigateToProfileByUsername,
                ),
              if (currentPost.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  AppDateUtils.formatTimeAgo(currentPost.createdAt!),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
        ),

        // Right-side vertical stats bar (Instagram style)
        Positioned(
          right: 12,
          bottom: MediaQuery.of(context).padding.bottom + 20,
          child: _buildVerticalStatsBar(currentPost),
        ),
      ],
    );
  }

  /// Instagram-style vertical stats bar on the right side
  Widget _buildVerticalStatsBar(Post post) {
    final user = post.user;
    final authorAvatar = user?.avatarUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Author avatar — 点击跳转到个人主页
        GestureDetector(
          onTap: () {
            if (user != null) _navigateToUser(user);
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 1.5),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white24,
              backgroundImage: authorAvatar != null && authorAvatar.isNotEmpty
                  ? CachedNetworkImageProvider(_resolveUrl(authorAvatar))
                  : null,
              child: authorAvatar == null || authorAvatar.isEmpty
                  ? const Icon(Icons.person, size: 20, color: Colors.white54)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Like button
        _VerticalStatButton(
          icon: post.isLiked == true ? Icons.favorite : Icons.favorite_border,
          iconColor: post.isLiked == true ? Colors.red : Colors.white,
          count: post.likeCount,
          onTap: () => _toggleLike(post),
        ),
        const SizedBox(height: 14),
        // Comment button
        _VerticalStatButton(
          icon: Icons.chat_bubble_outline,
          iconColor: Colors.white,
          count: post.commentCount,
          onTap: () => _openComments(post),
        ),
        const SizedBox(height: 14),
        // View / Share button
        _VerticalStatButton(
          icon: Icons.visibility_outlined,
          iconColor: Colors.white,
          count: post.viewCount,
          onTap: () {},
        ),
      ],
    );
  }

  /// Instagram-style comment bottom sheet with input pinned at bottom
  void _openComments(Post post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderDivider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('评论',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  // Comment section (takes remaining space)
                  Expanded(
                    child: CommentSection(
                      targetType: 'post',
                      targetId: post.id,
                      scrollController: scrollController,
                      onCommentCountChanged: (count) {
                        setState(() {
                          _postStates[post.id] = _postStates[post.id]!
                              .copyWith(commentCount: count);
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _recordViewIfNeeded(Post post) async {
    if (_viewedPostIds.contains(post.id)) return;
    _viewedPostIds.add(post.id);

    try {
      await PostService().recordView(post.id);
      if (mounted) {
        setState(() {
          _postStates[post.id] = _postStates[post.id]!.copyWith(
            viewCount: _postStates[post.id]!.viewCount + 1,
          );
        });
        PostInteractionNotifier().notifyViewChanged(
          post.id,
          _postStates[post.id]!.viewCount,
        );
      }
    } catch (e) {
      debugPrint('Record view error: $e');
    }
  }

  Future<void> _toggleLike(Post post) async {
    if (_isLikingPost) return;

    final auth = ProviderScope.containerOf(context).read(authProvider);
    if (!auth.isLoggedIn || auth.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先登录后再点赞'), duration: Duration(seconds: 2)),
      );
      return;
    }

    _isLikingPost = true;
    final wasLiked = post.isLiked ?? false;
    final oldPost = post;

    setState(() {
      _postStates[post.id] = post.copyWith(
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
      PostInteractionNotifier().notifyLikeChanged(
        post.id,
        !wasLiked,
        _postStates[post.id]!.likeCount,
      );
    } catch (e) {
      setState(() => _postStates[post.id] = oldPost); // Rollback
    } finally {
      _isLikingPost = false;
    }
  }
}

/// Collapsible post content text with rich text (#话题 / @用户) support
///
/// 点击行为按区域分发：
///   - 命中 `#话题` → 调用 [onTopicTap]
///   - 命中 `@用户` → 调用 [onMentionTap]
///   - 命中纯文本 → 切换展开/收起（依赖 RichTextContent 内部 TapGestureRecognizer
///     仅命中高亮区域，外层 GestureDetector 处理剩余区域）
class _PostContentText extends StatefulWidget {
  final String content;
  final void Function(String topic)? onTopicTap;
  final void Function(String username)? onMentionTap;

  const _PostContentText({
    required this.content,
    this.onTopicTap,
    this.onMentionTap,
  });

  @override
  State<_PostContentText> createState() => _PostContentTextState();
}

class _PostContentTextState extends State<_PostContentText> {
  bool _expanded = false;
  static const int _maxLines = 3;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(color: Colors.white, fontSize: 13, height: 1.4);
    const linkStyle = TextStyle(
      color: Color(0xFF4FC3F7),
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w500,
    );

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: RichTextContent(
              text: widget.content,
              style: baseStyle,
              highlightStyle: linkStyle,
              maxLines: _maxLines,
              overflow: TextOverflow.ellipsis,
              onTopicTap: widget.onTopicTap,
              onMentionTap: widget.onMentionTap,
            ),
            secondChild: RichTextContent(
              text: widget.content,
              style: baseStyle,
              highlightStyle: linkStyle,
              onTopicTap: widget.onTopicTap,
              onMentionTap: widget.onMentionTap,
            ),
          ),
          if (_needsExpand)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _expanded ? '收起' : '展开更多',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  bool get _needsExpand => widget.content.length > 100;
}

/// Vertical stat button (Instagram style) – icon on top, count below
class _VerticalStatButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final int count;
  final VoidCallback? onTap;

  const _VerticalStatButton({
    required this.icon,
    required this.iconColor,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 2),
          Text(
            _formatCount(count),
            style: TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}
