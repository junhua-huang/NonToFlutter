import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 全屏图片浏览模式
///
/// 功能：
/// - 左右滑动在当前帖子图片之间切换
/// - 双指放大 / 双击恢复原始尺寸
/// - 上下滑动切换图片（原始尺寸时）
/// - 底部显示作者信息和帖子文字
/// - 点击空白区域切换底部信息栏显示/隐藏
class ImageViewerScreen extends StatefulWidget {
  /// 图片 URL 列表
  final List<String> imageUrls;

  /// 初始展示索引
  final int initialIndex;

  /// 帖子作者
  final User? author;

  /// 帖子文字内容
  final String? postContent;

  /// 发布时间
  final DateTime? createdAt;

  /// Hero 动画 tag
  final String? heroTag;

  const ImageViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.author,
    this.postContent,
    this.createdAt,
    this.heroTag,
  });

  /// 从 Post 对象快速创建
  factory ImageViewerScreen.fromPost(
    Post post, {
    int initialIndex = 0,
    String? heroTag,
  }) {
    final urls = <String>[];
    if (post.images != null) {
      for (final img in post.images!) {
        if (img.isNotEmpty) urls.add(img);
      }
    }
    return ImageViewerScreen(
      imageUrls: urls,
      initialIndex: initialIndex,
      author: post.user,
      postContent: post.content,
      createdAt: post.createdAt,
      heroTag: heroTag,
    );
  }

  /// 显示全屏浏览器
  static void show(
    BuildContext context,
    List<String> urls, {
    int initialIndex = 0,
    String? heroTag,
    User? author,
    String? postContent,
    DateTime? createdAt,
  }) {
    if (urls.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, __) => ImageViewerScreen(
          imageUrls: urls,
          initialIndex: initialIndex,
          heroTag: heroTag,
          author: author,
          postContent: postContent,
          createdAt: createdAt,
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showInfoBar = true;

  // 图片缩放状态追踪：记录每张图片是否被放大
  final Map<int, bool> _isZoomedMap = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, max(0, widget.imageUrls.length - 1));
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleInfoBar() {
    setState(() => _showInfoBar = !_showInfoBar);
  }

  void _goToNext() {
    if (_currentIndex < widget.imageUrls.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onZoomStateChanged(int index, bool isZoomed) {
    _isZoomedMap[index] = isZoomed;
  }

  bool _isCurrentZoomed() {
    return _isZoomedMap[_currentIndex] ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.imageUrls
        .map((u) => _resolveUrl(u))
        .where((u) => u.isNotEmpty)
        .toList();

    if (resolved.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    // 确保 currentIndex 在有效范围
    final safeIndex = _currentIndex.clamp(0, resolved.length - 1);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleInfoBar,
        child: Stack(
          children: [
            // 主图片区域 —— PageView 左右滑动 + 上下滑动导航
            _buildImagePages(resolved, safeIndex),

            // 关闭按钮（顶部左上角，始终显示）
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
            ),

            // 页码指示器（多图时显示）
            if (resolved.length > 1)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${safeIndex + 1} / ${resolved.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 底部信息栏（可切换显示/隐藏）
            if (widget.author != null || (widget.postContent != null && widget.postContent!.isNotEmpty))
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: 0,
                right: 0,
                bottom: _showInfoBar ? 0 : -200,
                child: _buildInfoBar(),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建图片滑动页（PageView + 上下滑动导航）— Web 端支持鼠标/触控板拖拽
  Widget _buildImagePages(List<String> resolved, int safeIndex) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => false,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: PageView.builder(
        controller: _pageController,
        itemCount: resolved.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          return _ZoomableImage(
            imageUrl: resolved[index],
            heroTag: widget.heroTag ?? 'photo_$index',
            isCurrentPage: index == safeIndex,
            canSwipeVertically: !(_isZoomedMap[index] ?? false),
            onSwipeUp: (index > 0) ? _goToPrevious : null,
            onSwipeDown: (index < resolved.length - 1) ? _goToNext : null,
            onZoomChanged: (zoomed) => _onZoomStateChanged(index, zoomed),
            onTap: _toggleInfoBar,
          );
        },
      ),
    ),
    );
  }

  /// 底部信息栏
  Widget _buildInfoBar() {
    final author = widget.author;
    final content = widget.postContent;
    final createdAt = widget.createdAt;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
        ),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 32,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者行
          if (author != null) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey[800],
                  backgroundImage: author.avatarUrl != null && author.avatarUrl!.isNotEmpty
                      ? NetworkImage(author.avatarUrl!)
                      : null,
                  child: author.avatarUrl == null || author.avatarUrl!.isEmpty
                      ? Text(
                          author.initials,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author.displayName ?? author.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          _formatRelativeTime(createdAt),
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          // 帖子文字（默认折叠 2 行，可展开）
          if (content != null && content.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ExpandablePostContent(content: content),
          ],
        ],
      ),
    );
  }

  // URL 解析
  String _resolveUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return '${_baseUrl()}/storage/$url';
  }

  String _baseUrl() {
    try {
      // 简化版：从环境获取或默认
      return 'http://127.0.0.1:8000';
    } catch (_) {
      return '';
    }
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// 可缩放图片组件（单张图片支持 InteractiveViewer）
///
/// 支持：
/// - 双指缩放
/// - 双击恢复原始尺寸
/// - 原始尺寸时可上下滑动切换图片
class _ZoomableImage extends StatefulWidget {
  final String imageUrl;
  final String heroTag;
  final bool isCurrentPage;
  final bool canSwipeVertically;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTap;

  const _ZoomableImage({
    required this.imageUrl,
    required this.heroTag,
    required this.isCurrentPage,
    required this.canSwipeVertically,
    this.onSwipeUp,
    this.onSwipeDown,
    required this.onZoomChanged,
    required this.onTap,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _transformController = TransformationController();
  bool _isZoomed = false;
  double _verticalDragOffset = 0;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant _ZoomableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isCurrentPage && _isZoomed) {
      // 页面切换时重置缩放
      _resetZoom(animate: false);
    }
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final wasZoomed = _isZoomed;
    _isZoomed = scale > 1.01;

    if (wasZoomed != _isZoomed) {
      widget.onZoomChanged(_isZoomed);
    }
  }

  void _resetZoom({bool animate = true}) {
    if (animate) {
      _transformController.value = Matrix4.identity();
    } else {
      _transformController.value = Matrix4.identity();
    }
    if (_isZoomed) {
      _isZoomed = false;
      widget.onZoomChanged(false);
    }
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _resetZoom(animate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      onTap: widget.onTap,
      // 原始尺寸时的上下滑动 → 切换图片
      onVerticalDragUpdate: (!_isZoomed && widget.canSwipeVertically)
          ? (details) {
              _verticalDragOffset += details.primaryDelta ?? 0;
            }
          : null,
      onVerticalDragEnd: (!_isZoomed && widget.canSwipeVertically)
          ? (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < -300) {
                  // 向上滑动 → 下一张
                  widget.onSwipeDown?.call();
                } else if (details.primaryVelocity! > 300) {
                  // 向下滑动 → 上一张
                  widget.onSwipeUp?.call();
                }
              }
              _verticalDragOffset = 0;
            }
          : null,
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 0.5,
        maxScale: 4.0,
        panEnabled: _isZoomed, // 仅在缩放时允许平移
        scaleEnabled: true,    // 始终允许缩放
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    return Hero(
      tag: widget.heroTag,
      child: CachedNetworkImage(
        imageUrl: widget.imageUrl,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => const Center(
          child: CircularProgressIndicator(color: Colors.white30),
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 48),
              SizedBox(height: 8),
              Text('图片加载失败', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 可折叠的帖子文字内容
class _ExpandablePostContent extends StatefulWidget {
  final String content;

  const _ExpandablePostContent({required this.content});

  @override
  State<_ExpandablePostContent> createState() => _ExpandablePostContentState();
}

class _ExpandablePostContentState extends State<_ExpandablePostContent> {
  bool _expanded = false;
  bool _needsExpand = false;

  @override
  void initState() {
    super.initState();
    // 粗略判断是否需要展开按钮（> 80 字符约等于 > 2 行）
    _needsExpand = widget.content.length > 80;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _needsExpand
          ? () => setState(() => _expanded = !_expanded)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: Text(
              widget.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            secondChild: Text(
              widget.content,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
          ),
          if (_needsExpand)
            Text(
              _expanded ? '收起' : '展开全文',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
