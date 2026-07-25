import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/screens/post/create_post_screen.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/enhanced_media_viewer.dart';
import 'package:nonto/widgets/media_viewer.dart';
import 'package:nonto/widgets/post_author_meta_line.dart';
import 'package:nonto/widgets/nonto/nonto_post_action_bar.dart';
import 'package:nonto/widgets/post_share_to_chat_sheet.dart';
import 'package:nonto/widgets/rich_text_content.dart';

class QuoteThreadCard extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback onCurrentTap;
  final VoidCallback? onCurrentLike;
  final VoidCallback? onCurrentLongPress;
  final VoidCallback? onCurrentDelete;
  final VoidCallback? onCurrentComment;
  final List<Post>? feedPosts;
  final EdgeInsetsGeometry padding;

  const QuoteThreadCard({
    super.key,
    required this.post,
    required this.onCurrentTap,
    this.onCurrentLike,
    this.onCurrentLongPress,
    this.onCurrentDelete,
    this.onCurrentComment,
    this.feedPosts,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  @override
  ConsumerState<QuoteThreadCard> createState() => _QuoteThreadCardState();
}

class _QuoteThreadCardState extends ConsumerState<QuoteThreadCard> {
  late Post _currentPost;
  Post? _quotedPost;
  static const int _maxQuotedAncestors = 3;

  @override
  void initState() {
    super.initState();
    _syncPost(widget.post);
  }

  @override
  void didUpdateWidget(covariant QuoteThreadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) _syncPost(widget.post);
  }

  void _syncPost(Post post) {
    _currentPost = post;
    _quotedPost = post.quotedPost;
  }

  void _openPost(Post segmentPost) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          postId: segmentPost.id,
          initialPost: segmentPost,
        ),
      ),
    );
  }

  void _showSegmentStats(Post segmentPost) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('帖子统计',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              _StatRow(label: '浏览量', value: '${segmentPost.viewCount}'),
              _StatRow(label: '点赞数', value: '${segmentPost.likeCount}'),
              _StatRow(label: '评论数', value: '${segmentPost.commentCount}'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _quoteSegment(Post segmentPost) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(quotedPost: segmentPost),
      ),
    );
  }

  void _shareSegment(Post segmentPost) {
    PostShareToChatSheet.show(context, post: segmentPost);
  }

  List<Post> _buildQuoteChain() {
    final chain = <Post>[_currentPost];
    var next = _quotedPost;
    var depth = 0;
    while (next != null && depth < _maxQuotedAncestors) {
      chain.add(next);
      next = next.quotedPost;
      depth += 1;
    }
    return chain;
  }

  List<Post> get _quoteChainPosts => _buildQuoteChain();

  @override
  Widget build(BuildContext context) {
    final quotedUnavailable =
        _currentPost.quotedPostUnavailable || _quotedPost == null;
    final chain = _quoteChainPosts;
    return InkWell(
      onTap: widget.onCurrentTap,
      onLongPress: widget.onCurrentLongPress,
      child: Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < chain.length; i++)
              _QuoteThreadSegment(
                segmentPost: chain[i],
                showConnector: i < chain.length - 1 || quotedUnavailable,
                onTap: i == 0 ? widget.onCurrentTap : () => _openPost(chain[i]),
                onComment: i == 0
                    ? widget.onCurrentComment ?? widget.onCurrentTap
                    : () => _openPost(chain[i]),
                onLike: i == 0
                    ? widget.onCurrentLike ?? () {}
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final wasLiked = chain[i].isLiked == true;
                        final resp = wasLiked
                            ? await PostService().unlikePost(chain[i].id)
                            : await PostService().likePost(chain[i].id);
                        if (!mounted || resp.success) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('操作失败，请重试')),
                        );
                      },
                onView: () => _showSegmentStats(chain[i]),
                onQuote: () => _quoteSegment(chain[i]),
                onShare: () => _shareSegment(chain[i]),
                feedPosts: i == 0 ? widget.feedPosts : const [],
                quoteChainPosts: chain,
              ),
            if (quotedUnavailable) _UnavailableQuotedSegment(),
            Padding(
              padding: const EdgeInsets.only(left: 0, right: 0),
              child: Divider(height: 1, color: AppColors.borderLight),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteThreadSegment extends StatelessWidget {
  final Post segmentPost;
  final bool showConnector;
  final VoidCallback onTap;
  final VoidCallback onComment;
  final VoidCallback onLike;
  final VoidCallback onView;
  final VoidCallback onQuote;
  final VoidCallback onShare;
  final List<Post>? feedPosts;
  final List<Post> quoteChainPosts;

  const _QuoteThreadSegment({
    required this.segmentPost,
    required this.showConnector,
    required this.onTap,
    required this.onComment,
    required this.onLike,
    required this.onView,
    required this.onQuote,
    required this.onShare,
    this.feedPosts,
    required this.quoteChainPosts,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    if (segmentPost.user != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserProfileScreen(user: segmentPost.user!),
                        ),
                      );
                    }
                  },
                  child: ImageUtils.buildAvatar(segmentPost.user, radius: 20),
                ),
                if (showConnector) const Expanded(child: _QuoteConnectorLine()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PostAuthorMetaLine(
                        post: segmentPost,
                        showUsername: false,
                        onTap: onTap,
                      ),
                      if (segmentPost.content != null &&
                          segmentPost.content!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        RichTextContent(
                          text: segmentPost.content!,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.4,
                          ),
                          onTopicTap: (topicName) => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TopicSearchResultsScreen(
                                  topicName: topicName),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildMedia(context),
                NontoPostActionBar(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                  commentCount: segmentPost.commentCount,
                  likeCount: segmentPost.likeCount,
                  viewCount: segmentPost.viewCount,
                  isLiked: segmentPost.isLiked == true,
                  onComment: onComment,
                  onLike: onLike,
                  onView: onView,
                  onQuote: onQuote,
                  onShare: onShare,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Post> _buildQuoteMediaPosts() {
    final seen = <int>{};
    final posts = <Post>[];
    for (final post in quoteChainPosts) {
      if (seen.add(post.id)) posts.add(post);
    }
    for (final post in feedPosts ?? const <Post>[]) {
      if (seen.add(post.id)) posts.add(post);
    }
    return posts;
  }

  List<PostMediaItem> _buildQuoteMediaItems(List<String> images) {
    return _buildQuoteMediaPosts()
        .where((post) => post.hasImage || post.hasVideo)
        .map((post) => PostMediaItem(
              post: post,
              mediaUrls: post.id == segmentPost.id
                  ? images
                  : (post.images ?? const <String>[])
                      .where((url) => url.isNotEmpty)
                      .toList(),
            ))
        .where((item) => item.mediaUrls.isNotEmpty)
        .toList();
  }

  Widget _buildMedia(BuildContext context) {
    final images = (segmentPost.images ?? const <String>[])
        .where((url) => url.isNotEmpty)
        .toList();
    if (images.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: images.length == 1
            ? GestureDetector(
                onTap: () {
                  final items = _buildQuoteMediaItems(images);
                  final initialPostIndex = items
                      .indexWhere((item) => item.post.id == segmentPost.id)
                      .clamp(0, items.length - 1);
                  EnhancedImageViewerScreen.show(
                    context,
                    items,
                    initialPostIndex: initialPostIndex,
                  );
                },
                child: AdaptivePostImageGallery(
                  imageUrls: images,
                  maxHeight: 320,
                  post: null,
                  onTap: () {
                    final items = _buildQuoteMediaItems(images);
                    final initialPostIndex = items
                        .indexWhere((item) => item.post.id == segmentPost.id)
                        .clamp(0, items.length - 1);
                    EnhancedImageViewerScreen.show(
                      context,
                      items,
                      initialPostIndex: initialPostIndex,
                    );
                  },
                ),
              )
            : AdaptivePostImageGallery(
                imageUrls: images,
                maxHeight: 320,
                post: segmentPost,
                feedPosts: _buildQuoteMediaPosts(),
              ),
      );
    }
    if (segmentPost.hasVideo) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Icon(Icons.play_arrow, color: AppColors.textSecondary, size: 40),
      );
    }
    return const SizedBox.shrink();
  }
}

class _QuoteConnectorLine extends StatelessWidget {
  const _QuoteConnectorLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      margin: const EdgeInsets.only(top: 6, bottom: 0),
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _UnavailableQuotedSegment extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surface,
            child: Icon(Icons.lock_outline,
                size: 18, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Text(
              '原帖不可见或已被隐藏',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: AppColors.textPrimary)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
