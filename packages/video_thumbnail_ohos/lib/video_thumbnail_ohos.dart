/// 跨端视频缩略图提取（nonto）
///
/// - 鸿蒙端：基于 AVImageGenerator 从视频中提取指定位置的帧
/// - iOS/Android 端：委托给 video_thumbnail 包
library;

import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

/// 从视频文件中提取缩略图（返回 JPEG 字节数组）
///
/// [videoPath] 视频文件路径
/// [positionMs] 截取位置（毫秒），默认 0（首帧）
/// [maxWidth] 缩略图最大宽度（px），默认 320
/// [maxHeight] 缩略图最大高度（px），默认 240
/// [quality] JPEG 质量 1-100，默认 80
Future<Uint8List?> extractThumbnail({
  required String videoPath,
  int positionMs = 0,
  int maxWidth = 320,
  int maxHeight = 240,
  int quality = 80,
}) async {
  if (Platform.operatingSystem == 'ohos') {
    return _ohosExtract(
      videoPath: videoPath,
      positionMs: positionMs,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
    );
  }

  // iOS / Android
  return vt.VideoThumbnail.thumbnailData(
    video: videoPath,
    imageFormat: vt.ImageFormat.JPEG,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    quality: quality,
    timeMs: positionMs,
  );
}

Future<Uint8List?> _ohosExtract({
  required String videoPath,
  required int positionMs,
  required int maxWidth,
  required int maxHeight,
  required int quality,
}) async {
  const channel = MethodChannel('nonto_video_thumbnail');
  try {
    final result = await channel.invokeMethod<Map>('extractThumbnail', {
      'videoPath': videoPath,
      'positionMs': positionMs,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'quality': quality,
    });
    return result?['data'] as Uint8List?;
  } catch (_) {
    return null;
  }
}
