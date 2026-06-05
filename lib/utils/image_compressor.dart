import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 全局图片无损/高质量压缩工具（纯字节 API，全平台兼容）
///
/// 使用 dart:ui 内置编解码器，在后台线程中解码/缩放/重编码为 PNG（无损），
/// 不阻塞 UI 线程。输入输出均为 [Uint8List]，不依赖 dart:io。
class ImageCompressor {
  /// 压缩图片字节数据
  ///
  /// [originalBytes] 原始图片字节
  /// [quality] 保留参数（PNG 无损输出，quality 仅用于兼容旧接口）
  /// [maxWidth] 最大宽度（像素），保持宽高比，默认 1920
  ///
  /// 返回压缩后的 [Uint8List] 字节。
  static Future<Uint8List> compressImage(
    Uint8List originalBytes, {
    int quality = 92,
    int maxWidth = 1920,
  }) async {
    try {
      // 直接使用 instantiateImageCodec 解码 + 缩放（避免 ImmutableBuffer/ImageDescriptor 兼容性问题）
      final ui.Codec codec = await ui.instantiateImageCodec(
        originalBytes,
        targetWidth: maxWidth,
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;

      // 重编码为 PNG（无损）
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      codec.dispose();

      if (byteData == null) {
        debugPrint('ImageCompressor: re-encode returned null, returning original');
        return originalBytes;
      }

      final Uint8List compressed = byteData.buffer.asUint8List();

      // 如果压缩后反而更大，返回原字节
      if (compressed.length >= originalBytes.length) {
        debugPrint(
          'ImageCompressor: compressed size (${compressed.length}) >= '
          'original (${originalBytes.length}), returning original',
        );
        return originalBytes;
      }

      debugPrint(
        'ImageCompressor: ${originalBytes.length} -> ${compressed.length} bytes '
        '(${image.width}x${image.height})',
      );

      return compressed;
    } catch (e) {
      debugPrint('ImageCompressor: compression failed ($e), returning original');
      return originalBytes;
    }
  }

  /// 批量压缩图片字节
  ///
  /// 对列表中的每组字节依次压缩，失败时保留原始字节。
  static Future<List<Uint8List>> compressMultiple(
    List<Uint8List> bytesList, {
    int quality = 92,
    int maxWidth = 1920,
  }) async {
    final List<Uint8List> results = [];
    for (final bytes in bytesList) {
      try {
        final compressed = await compressImage(
          bytes, quality: quality, maxWidth: maxWidth);
        results.add(compressed);
      } catch (e) {
        debugPrint(
          'ImageCompressor: batch compression failed, using original');
        results.add(bytes);
      }
    }
    return results;
  }
}
