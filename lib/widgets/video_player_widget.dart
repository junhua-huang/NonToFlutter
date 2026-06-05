import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 将相对 URL 解析为完整的网络 URL
String _resolveVideoUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  return '${AppConfig.baseUrl}/storage/$url';
}

/// 自定义视频播放器组件
///
/// 功能：
/// - 使用 video_thumbnail 提取视频首帧作为封面
/// - 单击视频区域切换播放/暂停（无独立播放按钮）
/// - 视频下方圆角全屏按钮（100x44, radius 22）
/// - 全屏沉浸模式，单击切换播放/暂停，顶部返回按钮，暂停时显示半透明播放指示图标
/// - dispose 时自动释放播放器资源
/// - onPlayStart / onPlayPause 回调
class VideoPlayerWidget extends StatefulWidget {
  final String? videoUrl;
  final String? thumbnailUrl;
  final double? height;
  final double? width;
  final BoxFit? boxFit;
  final VoidCallback? onPlayStart;
  final void Function(bool isPlaying)? onPlayPause;

  const VideoPlayerWidget({
    super.key,
    this.videoUrl,
    this.thumbnailUrl,
    this.height,
    this.width,
    this.boxFit,
    this.onPlayStart,
    this.onPlayPause,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  Uint8List? _thumbnailBytes;
  bool _thumbnailAttempted = false;

  String get _resolvedVideo => _resolveVideoUrl(widget.videoUrl);

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  /// 使用 video_thumbnail 提取第 0 毫秒首帧
  Future<void> _loadThumbnail() async {
    if (_resolvedVideo.isEmpty) {
      setState(() => _thumbnailAttempted = true);
      return;
    }
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: _resolvedVideo,
        imageFormat: ImageFormat.JPEG,
        timeMs: 0,
        quality: 75,
        maxWidth: 480,
      );
      if (mounted) {
        setState(() {
          _thumbnailBytes = data;
          _thumbnailAttempted = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _thumbnailAttempted = true);
      }
    }
  }

  /// 初始化播放器（未初始化时）或切换播放/暂停（已初始化时）
  Future<void> _handleTap() async {
    if (_resolvedVideo.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = '视频地址无效';
      });
      return;
    }

    if (_isInitialized) {
      _togglePlayPause();
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(_resolvedVideo));
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
      _controller!.play();
      _controller!.setLooping(true);
      _controller!.addListener(_onPlayerUpdate);
      widget.onPlayStart?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = '视频加载失败';
      });
    }
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    final wasPlaying = _controller!.value.isPlaying;
    if (wasPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    widget.onPlayPause?.call(!wasPlaying);
  }

  void _enterFullscreen() {
    if (_resolvedVideo.isEmpty) return;
    final wasPlaying = _controller?.value.isPlaying ?? false;
    _controller?.pause();
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPlayer(
          videoUrl: _resolvedVideo,
          onPlayPause: widget.onPlayPause,
        ),
      ),
    ).then((_) {
      if (wasPlaying) {
        _controller?.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height ?? 200;
    final effectiveWidth = widget.width ?? double.infinity;
    final fit = widget.boxFit ?? BoxFit.cover;

    // --- 错误态 ---
    if (_hasError) {
      return Container(
        height: effectiveHeight,
        width: effectiveWidth,
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 32, color: Colors.white54),
              const SizedBox(height: 8),
              Text(_errorMessage,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _handleTap,
                child: const Text('重试',
                    style:
                        TextStyle(color: AppColors.primary, fontSize: 13)),
              ),
            ],
          ),
        ),
      );
    }

    // --- 加载态 ---
    if (_isLoading) {
      return Container(
        height: effectiveHeight,
        width: effectiveWidth,
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
        ),
      );
    }

    // --- 播放态 ---
    if (_isInitialized && _controller != null) {
      return Container(
        width: effectiveWidth,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 视频画面 — 单击切换播放/暂停
            GestureDetector(
              onTap: _togglePlayPause,
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
            // 圆角全屏按钮 (100x44, radius 22)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: const Color(0xFF1A1A1A),
              child: Center(
                child: GestureDetector(
                  onTap: _enterFullscreen,
                  child: Container(
                    width: 100,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.fullscreen,
                        color: Colors.white70, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // --- 初始态：封面或占位符 ---
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        height: effectiveHeight,
        width: effectiveWidth,
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildCover(fit),
      ),
    );
  }

  /// 构建封面：优先 video_thumbnail 首帧 → thumbnailUrl → 占位图标
  Widget _buildCover(BoxFit fit) {
    if (_thumbnailBytes != null) {
      return Image.memory(_thumbnailBytes!, fit: fit);
    }
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _resolveVideoUrl(widget.thumbnailUrl),
        fit: fit,
        placeholder: (_, __) =>
            Container(color: AppColors.textPrimary.withValues(alpha: 0.8)),
        errorWidget: (_, __, ___) =>
            const Icon(Icons.videocam, size: 48, color: Colors.white30),
      );
    }
    return const Center(
      child: Icon(Icons.videocam, size: 48, color: Colors.white30),
    );
  }
}

// ================================================================
// 全屏视频播放器（内部私有）
// ================================================================

class _FullscreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final void Function(bool isPlaying)? onPlayPause;

  const _FullscreenVideoPlayer({
    required this.videoUrl,
    this.onPlayPause,
  });

  @override
  State<_FullscreenVideoPlayer> createState() =>
      _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _initVideo();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  void _initVideo() {
    try {
      _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl));
      _controller!.initialize().then((_) {
        if (!mounted) return;
        setState(() => _isInitialized = true);
        _controller!.play();
        _controller!.setLooping(true);
      }).catchError((_) {
        if (mounted) setState(() => _hasError = true);
      });
      _controller!.addListener(() {
        if (mounted && !_hasError) setState(() {});
      });
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    final wasPlaying = _controller!.value.isPlaying;
    if (wasPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    widget.onPlayPause?.call(!wasPlaying);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _hasError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.white54),
                  const SizedBox(height: 12),
                  const Text('视频加载失败',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _isInitialized = false;
                      });
                      _initVideo();
                    },
                    child: const Text('重试',
                        style: TextStyle(
                            color: AppColors.primary, fontSize: 16)),
                  ),
                ],
              ),
            )
          : _isInitialized && _controller != null
              ? GestureDetector(
                  onTap: _togglePlayPause,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                      // 顶部返回按钮
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: GestureDetector(
                              onTap: () {
                                SystemChrome.setEnabledSystemUIMode(
                                    SystemUiMode.edgeToEdge);
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.arrow_back,
                                    color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 暂停时屏幕中央显示半透明播放指示图标
                      if (!_controller!.value.isPlaying)
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow,
                              size: 36, color: Colors.white70),
                        ),
                    ],
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                ),
    );
  }
}
