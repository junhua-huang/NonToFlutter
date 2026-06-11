import 'package:cached_network_image/cached_network_image.dart';
import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/widgets/enhanced_media_viewer.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player_ohos/video_player_ohos.dart';
/// 将相对 URL 解析为完整的网络 URL
String resolveUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  return '${AppConfig.baseUrl}/storage/$url';
}

/// 图片放大浏览页（支持多图左右滑动 + 缩放 + 动态页码 + Hero动画）
class ImageViewerScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? heroTag;

  const ImageViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.heroTag,
  });

  static void show(BuildContext context, List<String> urls, {int initialIndex = 0, String? heroTag}) {
    if (urls.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, __) => ImageViewerScreen(imageUrls: urls, initialIndex: initialIndex, heroTag: heroTag),
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.imageUrls.map(resolveUrl).where((u) => u.isNotEmpty).toList();
    if (resolved.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dismiss on tapping background
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.black),
          ),
          // Photo gallery
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(resolved[index]),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained * 0.5,
                maxScale: PhotoViewComputedScale.covered * 4,
                heroAttributes: widget.heroTag != null
                    ? PhotoViewHeroAttributes(tag: widget.heroTag!)
                    : PhotoViewHeroAttributes(tag: 'photo_$index'),
                errorBuilder: (_, __, ___) => const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 48),
                      SizedBox(height: 8),
                      Text('图片加载失败', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                ),
              );
            },
            itemCount: resolved.length,
            loadingBuilder: (context, event) {
              final chunkEvent = event;
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: chunkEvent != null && chunkEvent.expectedTotalBytes != null
                          ? chunkEvent.cumulativeBytesLoaded / chunkEvent.expectedTotalBytes!
                          : null,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      chunkEvent != null && chunkEvent.expectedTotalBytes != null
                          ? '${(chunkEvent.cumulativeBytesLoaded / 1024).toInt()} / ${(chunkEvent.expectedTotalBytes! / 1024).toInt()} KB'
                          : '加载中...',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
            pageController: _pageController,
            onPageChanged: _onPageChanged,
            backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          ),
          // Close button
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
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
          // Page indicator
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
                      '${_currentIndex + 1} / ${resolved.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 多图网格组件（用于帖子中的多图展示）
class ImageGalleryGrid extends StatelessWidget {
  final List<String> imageUrls;
  final Post? post;
  final VoidCallback? onTap;
  final double maxHeight;
  final List<Post>? feedPosts;

  const ImageGalleryGrid({
    super.key,
    required this.imageUrls,
    this.post,
    this.onTap,
    this.maxHeight = 300,
    this.feedPosts,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    // Single image
    if (imageUrls.length == 1) {
      return _buildSingleImage(imageUrls[0], context);
    }

    // Two images: side by side
    if (imageUrls.length == 2) {
      return SizedBox(
        height: maxHeight * 0.8,
        child: Row(
          children: [
            Expanded(child: _buildGridImage(imageUrls[0], 0, context)),
            const SizedBox(width: 4),
            Expanded(child: _buildGridImage(imageUrls[1], 1, context)),
          ],
        ),
      );
    }

    // Three images: one large + two small
    if (imageUrls.length == 3) {
      return SizedBox(
        height: maxHeight,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: _buildGridImage(imageUrls[0], 0, context),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(child: _buildGridImage(imageUrls[1], 1, context)),
                  const SizedBox(height: 4),
                  Expanded(child: _buildGridImage(imageUrls[2], 2, context)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4+ images: 2x2 grid with "+N" overlay on last
    final displayCount = imageUrls.length > 4 ? 3 : imageUrls.length;
    final extraCount = imageUrls.length - displayCount;

    return SizedBox(
      height: maxHeight,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildGridImage(imageUrls[0], 0, context)),
                const SizedBox(width: 4),
                Expanded(child: _buildGridImage(imageUrls[1], 1, context)),
              ],
            ),
          ),
          if (displayCount >= 3) ...[
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildGridImage(imageUrls[2], 2, context, overlay: extraCount > 0 ? '+$extraCount' : null)),
                  if (displayCount >= 4) ...[
                    const SizedBox(width: 4),
                    Expanded(child: _buildGridImage(imageUrls[3], 3, context)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleImage(String url, BuildContext context) {
    final resolved = resolveUrl(url);
    return GestureDetector(
      onTap: () {
        if (post != null) {
          EnhancedImageViewerScreen.show(context, _buildMediaItems());
        } else {
          ImageViewerScreen.show(context, imageUrls);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: resolved,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          fadeInDuration: const Duration(milliseconds: 300),
          fadeInCurve: Curves.easeInOut,
          placeholder: (_, __) => AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              color: AppColors.surface,
              child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ),
          ),
          errorWidget: (_, __, ___) => AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              color: AppColors.surface,
              child: const Center(
                child: Icon(Icons.broken_image, size: 40, color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridImage(String url, int index, BuildContext context, {String? overlay}) {
    final resolved = resolveUrl(url);
    return GestureDetector(
      onTap: () {
        if (post != null) {
          EnhancedImageViewerScreen.show(context, _buildMediaItems(), initialMediaIndex: index);
        } else {
          ImageViewerScreen.show(context, imageUrls, initialIndex: index);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: resolved,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              fadeInCurve: Curves.easeInOut,
              placeholder: (_, __) => Container(color: AppColors.surface),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.surface,
                child: const Center(child: Icon(Icons.broken_image, size: 24, color: AppColors.textSecondary)),
              ),
            ),
            if (overlay != null)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Text(overlay, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<PostMediaItem> _buildMediaItems() {
    final items = <PostMediaItem>[];
    items.add(PostMediaItem(post: post!, mediaUrls: imageUrls));
    if (feedPosts != null) {
      for (final p in feedPosts!) {
        if (p.id == post!.id) continue;
        final urls = <String>[];
        if (p.images != null) {
          for (final u in p.images!) {
            if (u.isNotEmpty) urls.add(u);
          }
        }
        if (urls.isNotEmpty) items.add(PostMediaItem(post: p, mediaUrls: urls));
      }
    }
    return items;
  }
}

/// 视频播放组件（带缩略图、播放按钮、错误处理）
class VideoPlayerPlaceholder extends StatefulWidget {
  final String? videoUrl;
  final String? thumbnailUrl;
  final double? height;
  final double? width;

  const VideoPlayerPlaceholder({
    super.key,
    this.videoUrl,
    this.thumbnailUrl,
    this.height,
    this.width,
  });

  @override
  State<VideoPlayerPlaceholder> createState() => _VideoPlayerPlaceholderState();
}

class _VideoPlayerPlaceholderState extends State<VideoPlayerPlaceholder> {
  void _openVideoPlayer() {
    final video = resolveUrl(widget.videoUrl);
    if (video.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, __) => _VideoPlayerScreen(videoUrl: video, coverUrl: resolveUrl(widget.thumbnailUrl)),
        transitionsBuilder: (context, animation, _, child) {
          return ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)), child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumb = resolveUrl(widget.thumbnailUrl);
    final hasError = widget.videoUrl == null || widget.videoUrl!.isEmpty;

    return GestureDetector(
      onTap: hasError ? null : _openVideoPlayer,
      child: Container(
        height: widget.height ?? 200,
        width: widget.width ?? double.infinity,
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(16),
          image: thumb.isNotEmpty
              ? DecorationImage(image: CachedNetworkImageProvider(thumb), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumb.isEmpty && !hasError)
              const Icon(Icons.videocam, size: 48, color: Colors.white30),
            if (hasError)
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off, size: 32, color: Colors.white54),
                  SizedBox(height: 4),
                  Text('视频不可用', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            if (!hasError)
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.play_arrow, size: 32, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

/// 全屏视频播放器（带完整控件、封面、错误处理）
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? coverUrl;

  const _VideoPlayerScreen({required this.videoUrl, this.coverUrl});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  NontoVideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  void _initVideo() {
    try {
      _controller = NontoVideoPlayerController.network(widget.videoUrl);
      _controller!.addListener(_onPlayerUpdate);
      _controller!.initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _hasError = false;
          });
          _controller!.play();
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = '视频加载失败';
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = '视频格式不支持';
        });
      }
    }
  }

  void _onPlayerUpdate() {
    if (mounted && !_hasError) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// 视频画面布局：根据屏幕尺寸和视频宽高比，自动计算最佳显示尺寸
  Widget _buildVideoLayout() {
    final ratio = _controller!.aspectRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        double videoW, videoH;
        if (maxW / maxH > ratio) {
          // 屏幕比视频更宽 → 以高度为准
          videoH = maxH;
          videoW = videoH * ratio;
        } else {
          // 屏幕比视频更高 → 以宽度为准
          videoW = maxW;
          videoH = videoW / ratio;
        }

        return Center(
          child: SizedBox(
            width: videoW,
            height: videoH,
            child: NontoVideoPlayer(controller: _controller!),
          ),
        );
      },
    );
  }

  /// 加载中指示器
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white70),
          SizedBox(height: 12),
          Text('加载视频中...', style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _hasError
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.white54),
                  const SizedBox(height: 12),
                  Text(_errorMessage, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _isInitialized = false;
                      });
                      _initVideo();
                    },
                    child: const Text('重试', style: TextStyle(color: AppColors.primary, fontSize: 16)),
                  ),
                ],
              ),
            )
          : GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Video / Cover / Loading
                  if (_isInitialized)
                    _buildVideoLayout()
                  else if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty)
                    // Show cover while video initializes
                    Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: widget.coverUrl!,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        ),
                        errorWidget: (_, __, ___) => _buildLoadingIndicator(),
                      ),
                    )
                  else
                    _buildLoadingIndicator(),

                  // Close button
                  if (_showControls)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Center play/pause button
                  if (_showControls && _isInitialized)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _controller!.isPlaying ? _controller!.pause() : _controller!.play();
                        });
                      },
                      child: AnimatedOpacity(
                        opacity: _controller!.isPlaying ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: const Icon(Icons.play_arrow, size: 36, color: Colors.white),
                        ),
                      ),
                    ),

                  // Bottom controls
                  if (_showControls && _isInitialized)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Progress bar（自定义，替代 video_player 的 VideoProgressIndicator）
                          _buildProgressBar(),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_formatDuration(_controller!.position)} / ${_formatDuration(_controller!.duration)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Row(
                                children: [
                                  // Play/Pause
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _controller!.isPlaying ? _controller!.pause() : _controller!.play();
                                      });
                                    },
                                    child: Icon(
                                      _controller!.isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white70,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  // Fullscreen (placeholder)
                                  const Icon(Icons.fullscreen, color: Colors.white70, size: 22),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildProgressBar() {
    final ctrl = _controller;
    if (ctrl == null || ctrl.duration.inMilliseconds == 0) {
      return const SizedBox(height: 20);
    }
    final progress = ctrl.position.inMilliseconds / ctrl.duration.inMilliseconds;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final ratio = details.localPosition.dx / constraints.maxWidth;
            final pos = Duration(milliseconds: (ratio * ctrl.duration.inMilliseconds).round());
            ctrl.seekTo(pos);
          },
          onHorizontalDragUpdate: (details) {
            final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            final pos = Duration(milliseconds: (ratio * ctrl.duration.inMilliseconds).round());
            ctrl.seekTo(pos);
          },
          child: Container(
            height: 20,
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 4,
              ),
            ),
          ),
        );
      },
    );
  }
}
