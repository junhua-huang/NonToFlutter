import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 裁剪形状
enum CropShape { circle, rectangle }

/// 内部交互模式
enum _InteractionMode { none, moveImage, moveCrop, resizeCrop }

/// Nonto 图片裁剪页：头像与封面编辑时使用的轻量裁剪入口。
///
/// 双 GestureDetector 架构：
/// - 底层：控制图片的平移 / 缩放（单指平移图片，双指捏合缩放）
/// - 顶层：控制裁剪框的拖动 / 缩放（单指拖动裁剪框，拖拽四角调整大小）
///
/// 圆形模式：裁剪框为圆形，只能等比缩放
/// 矩形模式：裁剪框为矩形，支持自由调整宽高，aspectRatio 参数锁定时按比例缩放
class ImageCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final CropShape cropShape;
  final double? aspectRatio; // w/h，仅用于 rectangle 模式，null = 自由比例

  const ImageCropScreen({
    super.key,
    required this.imageBytes,
    this.cropShape = CropShape.circle,
    this.aspectRatio,
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  // ── 图片 ──
  ui.Image? _image;
  bool _isLoading = true;
  String? _loadError;

  // ── 图片变换状态 ──
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;

  // ── 裁剪框状态 ──
  Offset _cropOffset = Offset.zero;
  Size _cropSize = Size.zero;

  // ── 手势追踪 ──
  _InteractionMode _mode = _InteractionMode.none;
  Offset _initialFocalPoint = Offset.zero;
  Offset _initialImageOffset = Offset.zero;
  double _initialImageScale = 1.0;
  Offset _initialCropOffset = Offset.zero;
  Size _initialCropSize = Size.zero;
  int _resizeCorner = 0; // 1=左上 2=右上 3=左下 4=右下
  bool _pinchStarted = false;

  static const double _cropMinSize = 100.0;
  static const double _cornerHitRadius = 36.0;

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
    } catch (e) {
      _loadError = '图片加载失败: $e';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// 根据屏幕尺寸初始化裁剪框（居中放置）
  void _initCropBox(Size screen) {
    if (widget.cropShape == CropShape.circle) {
      final d = screen.width * 0.75;
      _cropSize = Size(d, d);
      _cropOffset = Offset((screen.width - d) / 2, (screen.height - d) / 2);
    } else {
      final ratio = widget.aspectRatio ?? 16 / 9;
      final w = screen.width * 0.85;
      final h = w / ratio;
      _cropSize = Size(w, h);
      _cropOffset = Offset((screen.width - w) / 2, (screen.height - h) / 2);
    }
  }

  // ── 命中检测 ──

  /// 返回触摸点命中的角索引，0 表示未命中任何角
  int _hitCorner(Offset point) {
    final r = _cropRect;
    if ((point - r.topLeft).distance < _cornerHitRadius) return 1;
    if ((point - r.topRight).distance < _cornerHitRadius) return 2;
    if ((point - r.bottomLeft).distance < _cornerHitRadius) return 3;
    if ((point - r.bottomRight).distance < _cornerHitRadius) return 4;
    return 0;
  }

  /// 判断点是否在裁剪框内部
  bool _isInsideCropBox(Offset point) {
    if (widget.cropShape == CropShape.circle) {
      final c = _cropRect.center;
      final r = _cropSize.width / 2;
      return (point - c).distance <= r;
    }
    return _cropRect.contains(point);
  }

  Rect get _cropRect => Rect.fromLTWH(
      _cropOffset.dx, _cropOffset.dy, _cropSize.width, _cropSize.height);

  // ── 手势处理 ──

  void _onScaleStart(ScaleStartDetails d) {
    _pinchStarted = d.pointerCount >= 2;
    _initialFocalPoint = d.localFocalPoint;
    _initialImageOffset = _imageOffset;
    _initialImageScale = _imageScale;
    _initialCropOffset = _cropOffset;
    _initialCropSize = _cropSize;

    if (d.pointerCount >= 2) {
      // 双指 → 图片缩放
      _mode = _InteractionMode.moveImage;
    } else {
      final corner = _hitCorner(d.localFocalPoint);
      if (corner > 0) {
        _mode = _InteractionMode.resizeCrop;
        _resizeCorner = corner;
      } else if (_isInsideCropBox(d.localFocalPoint)) {
        _mode = _InteractionMode.moveCrop;
      } else {
        _mode = _InteractionMode.moveImage;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // 从单指平移平滑过渡到双指缩放
    if (_mode == _InteractionMode.moveImage &&
        d.pointerCount >= 2 &&
        !_pinchStarted) {
      _pinchStarted = true;
      _initialFocalPoint = d.localFocalPoint;
      _initialImageOffset = _imageOffset;
      _initialImageScale = _imageScale;
    }

    switch (_mode) {
      case _InteractionMode.moveImage:
        _updateImageTransform(d);
      case _InteractionMode.moveCrop:
        _updateCropMove(d.localFocalPoint - _initialFocalPoint);
      case _InteractionMode.resizeCrop:
        _updateCropResize(d.localFocalPoint - _initialFocalPoint);
      case _InteractionMode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _mode = _InteractionMode.none;
    _pinchStarted = false;
  }

  /// 更新图片平移/缩放：保持初始焦点锚定 + 累积平移
  void _updateImageTransform(ScaleUpdateDetails d) {
    final newScale = (_initialImageScale * d.scale).clamp(0.5, 4.0);
    final zoom = newScale / _initialImageScale;
    setState(() {
      _imageScale = newScale;
      _imageOffset =
          d.localFocalPoint - (_initialFocalPoint - _initialImageOffset) * zoom;
    });
  }

  /// 拖动裁剪框移动，限制在屏幕边界内
  void _updateCropMove(Offset delta) {
    final screen = MediaQuery.of(context).size;
    setState(() {
      _cropOffset = Offset(
        (_initialCropOffset.dx + delta.dx)
            .clamp(0.0, screen.width - _cropSize.width),
        (_initialCropOffset.dy + delta.dy)
            .clamp(0.0, screen.height - _cropSize.height),
      );
    });
  }

  /// 拖拽四角调整裁剪框大小
  void _updateCropResize(Offset delta) {
    final screen = MediaQuery.of(context).size;
    final isCircle = widget.cropShape == CropShape.circle;
    final ratio =
        (widget.cropShape == CropShape.rectangle) ? widget.aspectRatio : null;

    double newLeft = _initialCropOffset.dx;
    double newTop = _initialCropOffset.dy;
    double newW = _initialCropSize.width;
    double newH = _initialCropSize.height;

    switch (_resizeCorner) {
      case 1: // 左上角
        newLeft = (_initialCropOffset.dx + delta.dx).clamp(
            0.0, _initialCropOffset.dx + _initialCropSize.width - _cropMinSize);
        newTop = (_initialCropOffset.dy + delta.dy).clamp(0.0,
            _initialCropOffset.dy + _initialCropSize.height - _cropMinSize);
        newW = _initialCropOffset.dx + _initialCropSize.width - newLeft;
        newH = _initialCropOffset.dy + _initialCropSize.height - newTop;
        break;
      case 2: // 右上角
        newW = (_initialCropSize.width + delta.dx)
            .clamp(_cropMinSize, screen.width - _initialCropOffset.dx);
        newTop = (_initialCropOffset.dy + delta.dy).clamp(0.0,
            _initialCropOffset.dy + _initialCropSize.height - _cropMinSize);
        newH = _initialCropOffset.dy + _initialCropSize.height - newTop;
        break;
      case 3: // 左下角
        newLeft = (_initialCropOffset.dx + delta.dx).clamp(
            0.0, _initialCropOffset.dx + _initialCropSize.width - _cropMinSize);
        newW = _initialCropOffset.dx + _initialCropSize.width - newLeft;
        newH = (_initialCropSize.height + delta.dy)
            .clamp(_cropMinSize, screen.height - _initialCropOffset.dy);
        break;
      case 4: // 右下角
        newW = (_initialCropSize.width + delta.dx)
            .clamp(_cropMinSize, screen.width - _initialCropOffset.dx);
        newH = (_initialCropSize.height + delta.dy)
            .clamp(_cropMinSize, screen.height - _initialCropOffset.dy);
        break;
    }

    if (isCircle) {
      // ── 圆形：强制等比 ──
      final size =
          (_cropMinSize > (newW + newH) / 2 ? _cropMinSize : (newW + newH) / 2)
              .clamp(_cropMinSize, min(screen.width, screen.height).toDouble());
      final initCx = _initialCropOffset.dx + _initialCropSize.width / 2;
      final initCy = _initialCropOffset.dy + _initialCropSize.height / 2;

      switch (_resizeCorner) {
        case 1:
          newLeft = (initCx - size / 2).clamp(0.0, screen.width - size);
          newTop = (initCy - size / 2).clamp(0.0, screen.height - size);
          break;
        case 2:
          newTop = (initCy - size / 2).clamp(0.0, screen.height - size);
          break;
        case 3:
          newLeft = (initCx - size / 2).clamp(0.0, screen.width - size);
          break;
        case 4:
          break;
      }
      newW = size;
      newH = size;
    } else if (ratio != null) {
      // ── 矩形 + 锁定比例 ──
      final aRatio = ratio;

      switch (_resizeCorner) {
        case 1: // 左上 → 以右下角为锚点
          final anchorX = _initialCropOffset.dx + _initialCropSize.width;
          final anchorY = _initialCropOffset.dy + _initialCropSize.height;
          final wCand = anchorX - newLeft;
          final hCand = anchorY - newTop;
          if (wCand / hCand > aRatio) {
            newH = (anchorY - newTop).clamp(_cropMinSize, anchorY);
            newW = newH * aRatio;
            newLeft = anchorX - newW;
          } else {
            newW = (anchorX - newLeft).clamp(_cropMinSize, anchorX);
            newH = newW / aRatio;
            newTop = anchorY - newH;
          }
          break;
        case 2: // 右上 → 以左下角为锚点
          final anchorYb = _initialCropOffset.dy + _initialCropSize.height;
          newH = (anchorYb - newTop).clamp(_cropMinSize, anchorYb);
          newW = newH * aRatio;
          break;
        case 3: // 左下 → 以右上角为锚点
          final anchorXb = _initialCropOffset.dx + _initialCropSize.width;
          newW = (anchorXb - newLeft).clamp(_cropMinSize, anchorXb);
          newH = newW / aRatio;
          break;
        case 4: // 右下 → 以左上角为锚点
          final wDelta2 = newW - _initialCropSize.width;
          final hDelta2 = newH - _initialCropSize.height;
          if (wDelta2.abs() >= hDelta2.abs()) {
            newW =
                newW.clamp(_cropMinSize, screen.width - _initialCropOffset.dx);
            newH = newW / aRatio;
          } else {
            newH =
                newH.clamp(_cropMinSize, screen.height - _initialCropOffset.dy);
            newW = newH * aRatio;
          }
          break;
      }
      // 边界兜底
      if (newLeft + newW > screen.width) newW = screen.width - newLeft;
      if (newTop + newH > screen.height) newH = screen.height - newTop;
    }

    setState(() {
      _cropOffset = Offset(newLeft, newTop);
      _cropSize = Size(newW, newH);
    });
  }

  // ── 裁剪坐标计算（复用原有逻辑）──

  Rect _getCropScreenRect() => _cropRect;

  Offset _toChild(Offset screenPoint, Matrix4 inverseMatrix) =>
      MatrixUtils.transformPoint(inverseMatrix, screenPoint);

  Rect _getImageDisplayRect(ui.Image image, Size childSize) {
    final imgAspect = image.width / image.height;
    final childAspect = childSize.width / childSize.height;
    if (imgAspect > childAspect) {
      final h = childSize.width / imgAspect;
      return Rect.fromLTWH(0, (childSize.height - h) / 2, childSize.width, h);
    } else {
      final w = childSize.height * imgAspect;
      return Rect.fromLTWH((childSize.width - w) / 2, 0, w, childSize.height);
    }
  }

  Offset? _childToImage(Offset childPoint, Rect displayRect) {
    final dx = childPoint.dx;
    final dy = childPoint.dy;
    if (dx < displayRect.left ||
        dx > displayRect.right ||
        dy < displayRect.top ||
        dy > displayRect.bottom) {
      return null;
    }
    return Offset(
      (dx - displayRect.left) / displayRect.width * _image!.width,
      (dy - displayRect.top) / displayRect.height * _image!.height,
    );
  }

  // ── 裁剪执行 ──

  Future<Uint8List?> _doCrop() async {
    if (_image == null) return null;

    final matrix = Matrix4.identity()
      ..translateByDouble(_imageOffset.dx, _imageOffset.dy, 0, 1)
      ..scaleByDouble(_imageScale, _imageScale, 1, 1);
    final inverseMatrix = Matrix4.inverted(matrix);
    final screenSize = MediaQuery.of(context).size;
    final cropRect = _getCropScreenRect();
    final displayRect = _getImageDisplayRect(_image!, screenSize);

    if (widget.cropShape == CropShape.circle) {
      return _cropCircle(inverseMatrix, cropRect, displayRect);
    } else {
      return _cropRectangle(inverseMatrix, cropRect, displayRect);
    }
  }

  Future<Uint8List?> _cropCircle(
    Matrix4 inverseMatrix,
    Rect cropRect,
    Rect displayRect,
  ) async {
    const numSamples = 48;
    double? minPx, maxPx, minPy, maxPy;

    for (int i = 0; i < numSamples; i++) {
      final angle = 2 * pi * i / numSamples;
      final sx = cropRect.center.dx + cropRect.width / 2 * cos(angle);
      final sy = cropRect.center.dy + cropRect.height / 2 * sin(angle);
      final child = _toChild(Offset(sx, sy), inverseMatrix);
      final pixel = _childToImage(child, displayRect);
      if (pixel != null) {
        minPx = minPx == null ? pixel.dx : min(minPx, pixel.dx);
        maxPx = maxPx == null ? pixel.dx : max(maxPx, pixel.dx);
        minPy = minPy == null ? pixel.dy : min(minPy, pixel.dy);
        maxPy = maxPy == null ? pixel.dy : max(maxPy, pixel.dy);
      }
    }

    final safeMinPx = minPx;
    final safeMaxPx = maxPx;
    final safeMinPy = minPy;
    final safeMaxPy = maxPy;
    if (safeMinPx == null ||
        safeMaxPx == null ||
        safeMinPy == null ||
        safeMaxPy == null) {
      return null;
    }

    final srcW = safeMaxPx - safeMinPx;
    final srcH = safeMaxPy - safeMinPy;
    final srcSize = max(srcW, srcH);
    final cx = (safeMinPx + safeMaxPx) / 2;
    final cy = (safeMinPy + safeMaxPy) / 2;
    final srcLeft =
        (cx - srcSize / 2).clamp(0, _image!.width.toDouble() - 1).toDouble();
    final srcTop =
        (cy - srcSize / 2).clamp(0, _image!.height.toDouble() - 1).toDouble();
    final clampedSize = min(
      min(srcSize, _image!.width.toDouble() - srcLeft),
      _image!.height.toDouble() - srcTop,
    ).toDouble();
    if (clampedSize <= 0) return null;

    final outputSize = clampedSize.toInt().clamp(200, 1200);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipPath(Path()
      ..addOval(
          Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble())));
    canvas.drawImageRect(
      _image!,
      Rect.fromLTWH(srcLeft, srcTop, clampedSize, clampedSize),
      Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble()),
      Paint(),
    );

    final picture = recorder.endRecording();
    final result = await picture.toImage(outputSize, outputSize);
    final byteData = await result.toByteData(format: ui.ImageByteFormat.png);

    picture.dispose();
    result.dispose();

    return byteData?.buffer.asUint8List();
  }

  Future<Uint8List?> _cropRectangle(
    Matrix4 inverseMatrix,
    Rect cropRect,
    Rect displayRect,
  ) async {
    final samplePoints = [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
      Offset(cropRect.center.dx, cropRect.top),
      Offset(cropRect.center.dx, cropRect.bottom),
      Offset(cropRect.left, cropRect.center.dy),
      Offset(cropRect.right, cropRect.center.dy),
    ];

    double? minPx, maxPx, minPy, maxPy;
    for (final sp in samplePoints) {
      final child = _toChild(sp, inverseMatrix);
      final pixel = _childToImage(child, displayRect);
      if (pixel != null) {
        minPx = minPx == null ? pixel.dx : min(minPx, pixel.dx);
        maxPx = maxPx == null ? pixel.dx : max(maxPx, pixel.dx);
        minPy = minPy == null ? pixel.dy : min(minPy, pixel.dy);
        maxPy = maxPy == null ? pixel.dy : max(maxPy, pixel.dy);
      }
    }

    final safeMinPx = minPx;
    final safeMaxPx = maxPx;
    final safeMinPy = minPy;
    final safeMaxPy = maxPy;
    if (safeMinPx == null ||
        safeMaxPx == null ||
        safeMinPy == null ||
        safeMaxPy == null) {
      return null;
    }

    final srcLeft = safeMinPx.clamp(0, _image!.width.toDouble() - 1).toDouble();
    final srcTop = safeMinPy.clamp(0, _image!.height.toDouble() - 1).toDouble();
    final srcW = (safeMaxPx - safeMinPx)
        .clamp(1, _image!.width.toDouble() - srcLeft)
        .toDouble();
    final srcH = (safeMaxPy - safeMinPy)
        .clamp(1, _image!.height.toDouble() - srcTop)
        .toDouble();

    const maxOutputW = 1600;
    final ratio = srcW / srcH;
    final outputW = (srcW > maxOutputW ? maxOutputW : srcW).toInt();
    final outputH = (outputW / ratio).toInt();

    if (outputW <= 0 || outputH <= 0) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      _image!,
      Rect.fromLTWH(srcLeft, srcTop, srcW, srcH),
      Rect.fromLTWH(0, 0, outputW.toDouble(), outputH.toDouble()),
      Paint(),
    );

    final picture = recorder.endRecording();
    final result = await picture.toImage(outputW, outputH);
    final byteData = await result.toByteData(format: ui.ImageByteFormat.png);

    picture.dispose();
    result.dispose();

    return byteData?.buffer.asUint8List();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  // ── UI 构建 ──

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_loadError != null || _image == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_loadError ?? '图片加载失败',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_cropSize == Size.zero) {
      _initCropBox(screenSize);
    }

    final isCircle = widget.cropShape == CropShape.circle;
    final imgMatrix = Matrix4.identity()
      ..translateByDouble(_imageOffset.dx, _imageOffset.dy, 0, 1)
      ..scaleByDouble(_imageScale, _imageScale, 1, 1);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          children: [
            // ── 图层 1：图片（全屏 Transform）──
            Transform(
              transform: imgMatrix,
              child: SizedBox(
                width: screenSize.width,
                height: screenSize.height,
                child: Center(
                  child: RawImage(
                    image: _image,
                    fit: BoxFit.contain,
                    width: screenSize.width,
                    height: screenSize.height,
                  ),
                ),
              ),
            ),

            // ── 图层 2：半透明遮罩 ──
            IgnorePointer(
              child: CustomPaint(
                size: screenSize,
                painter: isCircle
                    ? _CircleHolePainter(
                        center: Offset(_cropOffset.dx + _cropSize.width / 2,
                            _cropOffset.dy + _cropSize.height / 2),
                        radius: _cropSize.width / 2)
                    : _RectHolePainter(rect: _cropRect),
              ),
            ),

            // ── 图层 3：裁剪框白边框 ──
            Positioned(
              left: _cropOffset.dx,
              top: _cropOffset.dy,
              child: IgnorePointer(
                child: isCircle
                    ? Container(
                        width: _cropSize.width,
                        height: _cropSize.height,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      )
                    : Container(
                        width: _cropSize.width,
                        height: _cropSize.height,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
              ),
            ),

            // ── 图层 4：四角拖拽手柄 ──
            ..._buildCornerHandles(isCircle),

            // ── 图层 5：矩形网格辅助线 ──
            if (!isCircle)
              Positioned(
                left: _cropOffset.dx,
                top: _cropOffset.dy,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: _cropSize,
                    painter: _GridPainter(),
                  ),
                ),
              ),

            // ── UI 控件 ──
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              child: ClipOval(
                child: Material(
                  color: Colors.black45,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              right: 24,
              child: FloatingActionButton(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 4,
                onPressed: () async {
                  final result = await _doCrop();
                  if (!context.mounted) return;
                  Navigator.of(context).pop(result);
                },
                child: const Icon(Icons.check, size: 28),
              ),
            ),

            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 24,
              child: Text(
                '拖动裁剪框 / 拖拽四角调整 / 双指缩放图片',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCornerHandles(bool isCircle) {
    final positions = [
      Offset(_cropOffset.dx - 9, _cropOffset.dy - 9), // 左上
      Offset(_cropOffset.dx + _cropSize.width - 9, _cropOffset.dy - 9), // 右上
      Offset(_cropOffset.dx - 9, _cropOffset.dy + _cropSize.height - 9), // 左下
      Offset(_cropOffset.dx + _cropSize.width - 9,
          _cropOffset.dy + _cropSize.height - 9), // 右下
    ];

    return positions.map((p) {
      return Positioned(
        left: p.dx,
        top: p.dy,
        child: IgnorePointer(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.9),
              border: Border.all(color: Colors.black26, width: 1),
            ),
          ),
        ),
      );
    }).toList();
  }
}

// ─── 遮罩绘制器 ────────────────────────────────────────────

class _CircleHolePainter extends CustomPainter {
  final Offset center;
  final double radius;

  _CircleHolePainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircleHolePainter oldD) =>
      center != oldD.center || radius != oldD.radius;
}

class _RectHolePainter extends CustomPainter {
  final Rect rect;

  _RectHolePainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4))),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RectHolePainter oldD) => rect != oldD.rect;
}

/// 矩形裁剪框内 3x3 网格辅助线
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;

    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), paint);
    canvas.drawLine(Offset(w * 2 / 3, 0), Offset(w * 2 / 3, h), paint);
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), paint);
    canvas.drawLine(Offset(0, h * 2 / 3), Offset(w, h * 2 / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldD) => false;
}
