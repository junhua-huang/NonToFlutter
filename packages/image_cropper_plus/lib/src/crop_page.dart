import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'crop_config.dart';

/// 纯 Dart 图片裁剪页面
///
/// 支持手势拖拽缩放裁剪框，Pinch 缩放图片，裁剪完成后返回 Uint8List。
///
/// 使用方式：
/// ```dart
/// final result = await showModalBottomSheet<Uint8List>(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => CropPage(
///     imageBytes: bytes,
///     config: const CropConfig(aspectRatio: 1.0),
///   ),
/// );
/// ```
class CropPage extends StatefulWidget {
  final Uint8List imageBytes;
  final CropConfig config;

  const CropPage({
    super.key,
    required this.imageBytes,
    this.config = const CropConfig(),
  });

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  ui.Image? _image;
  bool _loading = true;
  String? _error;

  // 图片变换
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // 裁剪框
  late Rect _cropRect;

  // 触摸状态
  int? _activePointerId;
  _DragMode _dragMode = _DragMode.none;
  Offset _lastFocalPoint = Offset.zero;
  double _lastScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      _image = frame.image;
      _initCropRect();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _initCropRect() {
    final imageW = _image!.width.toDouble();
    final imageH = _image!.height.toDouble();
    final ratio = widget.config.aspectRatio;

    double cropW, cropH;
    if (ratio != null) {
      if (imageW / imageH > ratio) {
        cropH = imageH * 0.8;
        cropW = cropH * ratio;
      } else {
        cropW = imageW * 0.8;
        cropH = cropW / ratio;
      }
    } else {
      cropW = imageW * 0.8;
      cropH = imageH * 0.8;
    }

    _cropRect = Rect.fromCenter(
      center: Offset(imageW / 2, imageH / 2),
      width: cropW,
      height: cropH,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 400,
        child: Center(child: Text('图片加载失败: $_error')),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildCropArea()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.white)),
          ),
          const Text('裁剪图片', style: TextStyle(color: Colors.white, fontSize: 16)),
          TextButton(
            onPressed: _doCrop,
            child: const Text('确定', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildCropArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imgW = _image!.width.toDouble();
        final imgH = _image!.height.toDouble();
        final fitScale = min(constraints.maxWidth / imgW, constraints.maxHeight / imgH);
        final displayW = imgW * fitScale;
        final displayH = imgH * fitScale;
        final dx = (constraints.maxWidth - displayW) / 2;
        final dy = (constraints.maxHeight - displayH) / 2;
        final imageRect = Offset(dx, dy) & Size(displayW, displayH);

        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: ClipRect(
            child: CustomPaint(
              painter: _CropPainter(
                image: _image!,
                imageRect: imageRect,
                cropRect: _cropRect,
                scale: _scale,
                offset: _offset,
                config: widget.config,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            ),
          ),
        );
      },
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _activePointerId = details.pointerCount > 1 ? 1 : details.pointerCount;
    _lastFocalPoint = details.focalPoint;
    _lastScale = _scale;

    // 判断操作模式
    final localPos = details.localFocalPoint;
    if (_cropRect.contains(localPos)) {
      _dragMode = _DragMode.image;
    } else {
      _dragMode = _DragMode.crop;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_dragMode == _DragMode.image) {
      // 图片缩放/平移
      setState(() {
        _scale = (_lastScale * details.scale).clamp(0.5, 3.0);
        _offset += details.focalPoint - _lastFocalPoint;
        _lastFocalPoint = details.focalPoint;
      });
    } else if (_dragMode == _DragMode.crop) {
      // 拖动裁剪框
      setState(() {
        final delta = details.focalPoint - _lastFocalPoint;
        _cropRect = _cropRect.translate(delta.dx, delta.dy);
        _lastFocalPoint = details.focalPoint;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _dragMode = _DragMode.none;
    _activePointerId = null;
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.config.allowRotation)
            IconButton(
              icon: const Icon(Icons.rotate_left, color: Colors.white),
              tooltip: '旋转',
              onPressed: _rotateClockwise,
            ),
          const Spacer(),
          Text(
            _cropInfoText,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.crop, color: Colors.white),
            tooltip: '裁剪',
            onPressed: _doCrop,
          ),
        ],
      ),
    );
  }

  String get _cropInfoText {
    final w = _cropRect.width.toInt();
    final h = _cropRect.height.toInt();
    final ratio = widget.config.aspectRatio;
    return ratio != null
        ? '${w}x$h (${ratio.toStringAsFixed(2)})'
        : '${w}x$h';
  }

  void _rotateClockwise() {
    setState(() {});
  }

  Future<void> _doCrop() async {
    try {
      final result = await _cropImage();
      if (result != null && mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('裁剪失败: $e')),
        );
      }
    }
  }

  Future<Uint8List?> _cropImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 绘制图片
    final srcRect = Rect.fromLTWH(
      _cropRect.left,
      _cropRect.top,
      _cropRect.width,
      _cropRect.height,
    );

    canvas.drawImageRect(
      _image!,
      srcRect,
      Offset.zero & _cropRect.size,
      Paint(),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      _cropRect.width.toInt(),
      _cropRect.height.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}

enum _DragMode { none, image, crop }

/// 裁剪区域绘制器
class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect imageRect;
  final Rect cropRect;
  final double scale;
  final Offset offset;
  final CropConfig config;

  _CropPainter({
    required this.image,
    required this.imageRect,
    required this.cropRect,
    required this.scale,
    required this.offset,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制图片
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // 2. 绘制裁剪框遮罩（上半部分）
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, cropRect.top),
      Paint()..color = config.maskColor,
    );
    // 下半部分
    canvas.drawRect(
      Rect.fromLTWH(0, cropRect.bottom, size.width, size.height - cropRect.bottom),
      Paint()..color = config.maskColor,
    );
    // 左侧
    canvas.drawRect(
      Rect.fromLTWH(0, cropRect.top, cropRect.left, cropRect.height),
      Paint()..color = config.maskColor,
    );
    // 右侧
    canvas.drawRect(
      Rect.fromLTWH(cropRect.right, cropRect.top, size.width - cropRect.right, cropRect.height),
      Paint()..color = config.maskColor,
    );

    // 3. 绘制裁剪框边框
    if (config.cornerRadius > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cropRect, Radius.circular(config.cornerRadius)),
        Paint()
          ..color = config.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = config.borderWidth,
      );
    } else {
      canvas.drawRect(
        cropRect,
        Paint()
          ..color = config.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = config.borderWidth,
      );
    }

    // 4. 绘制九宫格辅助线
    if (config.showGrid) {
      final gridPaint = Paint()
        ..color = config.gridColor
        ..strokeWidth = config.gridWidth;

      // 两条竖线
      final cellW = cropRect.width / 3;
      for (int i = 1; i < 3; i++) {
        final x = cropRect.left + cellW * i;
        canvas.drawLine(
          Offset(x, cropRect.top),
          Offset(x, cropRect.bottom),
          gridPaint,
        );
      }

      // 两条横线
      final cellH = cropRect.height / 3;
      for (int i = 1; i < 3; i++) {
        final y = cropRect.top + cellH * i;
        canvas.drawLine(
          Offset(cropRect.left, y),
          Offset(cropRect.right, y),
          gridPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => true;
}