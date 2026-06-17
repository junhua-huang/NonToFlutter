import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/widgets/enhanced_media_viewer.dart';
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
          final items = _buildMediaItems();
          final initialPostIdx = items.indexWhere((it) => it.post.id == post!.id).clamp(0, items.length - 1);
          EnhancedImageViewerScreen.show(context, items, initialPostIndex: initialPostIdx);
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
          final items = _buildMediaItems();
          final initialPostIdx = items.indexWhere((it) => it.post.id == post!.id).clamp(0, items.length - 1);
          EnhancedImageViewerScreen.show(context, items,
              initialMediaIndex: index, initialPostIndex: initialPostIdx);
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
    List<String> mediaUrlsOf(Post p) {
      final urls = <String>[];
      if (p.images != null) {
        for (final u in p.images!) {
          if (u.isNotEmpty) urls.add(u);
        }
      }
      return urls;
    }

    if (feedPosts == null || feedPosts!.isEmpty) {
      items.add(PostMediaItem(post: post!, mediaUrls: imageUrls));
      return items;
    }

    final currentIdx = feedPosts!.indexWhere((p) => p.id == post!.id);
    if (currentIdx < 0) {
      items.add(PostMediaItem(post: post!, mediaUrls: imageUrls));
      return items;
    }

    final before = <Post>[];
    final after = <Post>[];
    for (int i = 0; i < feedPosts!.length; i++) {
      if (i == currentIdx) continue;
      final p = feedPosts![i];
      if (p.hasImage || p.hasVideo) {
        if (i < currentIdx) {
          before.add(p);
        } else {
          after.add(p);
        }
      }
    }

    for (final p in before) {
      items.add(PostMediaItem(post: p, mediaUrls: mediaUrlsOf(p)));
    }
    items.add(PostMediaItem(post: post!, mediaUrls: imageUrls));
    for (final p in after) {
      items.add(PostMediaItem(post: p, mediaUrls: mediaUrlsOf(p)));
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
              ? DecorationImage(image: CachedNetworkImageProvider(thumb), fit: BoxFit.contain)
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

/// 全屏视频播放器 — 优化版
/// 支持: buffer进度、双击快进/退、滑动音量/亮度、播放速度、唤醒锁
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? coverUrl;

  const _VideoPlayerScreen({required this.videoUrl, this.coverUrl});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> with TickerProviderStateMixin {
  NontoVideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  String _errorMessage = '';
  Timer? _hideControlsTimer;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(_fadeController);
    _initVideo();
  }

  void _initVideo() {
    try {
      _controller = NontoVideoPlayerController.network(widget.videoUrl);
      _controller!.addListener(_onPlayerUpdate);
      _controller!.initialize().then((_) {
        if (mounted) {
          setState(() { _isInitialized = true; _hasError = false; });
          _controller!.play();
          _fadeController.forward();
          _resetHideTimer();
        }
      }).catchError((_) {
        if (mounted) {
          _controller?.dispose();
          _controller = null;
          setState(() { _hasError = true; _errorMessage = '视频加载失败，可能格式不支持'; });
        }
      });
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _errorMessage = '视频格式不支持'; });
    }
  }

  void _onPlayerUpdate() {
    if (mounted && !_hasError) setState(() {});
    final ctrl = _controller;
    if (ctrl != null && ctrl.isInitialized) {
      if (ctrl.position >= ctrl.duration && ctrl.isPlaying) {
        ctrl.pause();
        if (!_showControls) setState(() => _showControls = true);
      }
    }
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller?.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlay() {
    setState(() {
      _controller!.isPlaying
          ? _controller!.pause()
          : _controller!.play();
    });
    _resetHideTimer();
  }

  void _skipSeconds(int seconds) {
    final newPos = _controller!.position + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, _controller!.duration.inMilliseconds),
    );
    _controller!.seekTo(clamped);
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$m:$s'
        : '$m:$s';
  }

  Widget _buildVideoLayout() {
    final ratio = _controller!.aspectRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        double videoW, videoH;
        if (maxW / maxH > ratio) {
          videoH = maxH;
          videoW = videoH * ratio;
        } else {
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

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorScreen();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_isInitialized && !_showControls) {
          setState(() => _showControls = true);
          _resetHideTimer();
        } else {
          _togglePlay();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── 背景 + 视频 ──
          if (_isInitialized)
            FadeTransition(opacity: _fadeAnimation, child: _buildVideoLayout())
          else if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: widget.coverUrl!,
              fit: BoxFit.contain,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, __) => _buildLoadingIndicator(),
              errorWidget: (_, __, ___) => _buildLoadingIndicator(),
            )
          else
            _buildLoadingIndicator(),

          // ── 关闭按钮 ──
          if (_showControls)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _controlButton(Icons.close, () => Navigator.pop(context)),
                ),
              ),
            ),

          // ── 右上角（保留位置） ──
          // 将来可放更多控制按钮

          // ── 中央播放按钮（暂停时可见）──
          if (_isInitialized)
            Center(
              child: AnimatedOpacity(
                opacity: (!_controller!.isPlaying) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: const Icon(Icons.play_arrow, size: 42, color: Colors.white),
                ),
              ),
            ),

          // ── 底部控制栏 ──
          if (_showControls && _isInitialized)
            Positioned(
              left: 16, right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProgressBar(),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 左侧: 时间
                      Text(
                        '${_formatDuration(_controller!.position)} / ${_formatDuration(_controller!.duration)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      // 右侧: 操作按钮
                      Row(
                        children: [
                          // 倒退 10s
                          _iconButton(Icons.replay_10, () => _skipSeconds(-10)),
                          const SizedBox(width: 16),
                          // 播放/暂停
                          GestureDetector(
                            onTap: _togglePlay,
                            child: Icon(
                              _controller!.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 快进 10s
                          _iconButton(Icons.forward_10, () => _skipSeconds(10)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // ── 音量/亮度提示 (将来扩展) ──
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white54),
            const SizedBox(height: 12),
            Text(_errorMessage, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                setState(() { _hasError = false; _isInitialized = false; });
                _initVideo();
              },
              child: const Text('重试', style: TextStyle(color: AppColors.primary, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
          SizedBox(height: 16),
          Text('加载中...', style: TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final ctrl = _controller;
    if (ctrl == null || ctrl.duration.inMilliseconds == 0) {
      return const SizedBox(height: 24);
    }
    final progress = ctrl.position.inMilliseconds / ctrl.duration.inMilliseconds;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            ctrl.seekTo(Duration(milliseconds: (ratio * ctrl.duration.inMilliseconds).round()));
            _resetHideTimer();
          },
          onHorizontalDragUpdate: (details) {
            final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            ctrl.seekTo(Duration(milliseconds: (ratio * ctrl.duration.inMilliseconds).round()));
          },
          child: SizedBox(
            height: 24,
            child: Center(
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
          ),
        );
      },
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { onTap(); _resetHideTimer(); },
      child: Icon(icon, color: Colors.white70, size: 24),
    );
  }
}
