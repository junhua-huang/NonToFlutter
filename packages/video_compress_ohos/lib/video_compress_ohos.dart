/// 跨端视频压缩（nonto）
///
/// - 鸿蒙端：基于 AVTranscoder 实现视频转码压缩
/// - iOS/Android 端：委托给 video_compress 包
library video_compress_ohos;

import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:video_compress/video_compress.dart' as vc;

/// 压缩视频文件，返回压缩后的文件路径
///
/// [inputPath] 原始视频路径
/// [quality] 压缩质量：'low' / 'medium' / 'high'，默认 'medium'
/// [deleteOrigin] 压缩后是否删除原视频，默认 false
/// [frameRate] 目标帧率，默认 30
Future<String?> compressVideo({
  required String inputPath,
  String quality = 'medium',
  bool deleteOrigin = false,
  int frameRate = 30,
}) async {
  if (Platform.operatingSystem == 'ohos') {
    return _ohosCompress(
      inputPath: inputPath,
      quality: quality,
      deleteOrigin: deleteOrigin,
      frameRate: frameRate,
    );
  }

  // iOS / Android
  final info = await vc.VideoCompress.compressVideo(
    inputPath,
    quality: _mapQuality(quality),
    deleteOrigin: deleteOrigin,
    includeAudio: true,
    frameRate: frameRate,
  );
  return info?.file?.path;
}

vc.VideoQuality _mapQuality(String quality) {
  switch (quality) {
    case 'low':
      return vc.VideoQuality.LowQuality;
    case 'medium':
      return vc.VideoQuality.MediumQuality;
    case 'high':
      return vc.VideoQuality.HighestQuality;
    default:
      return vc.VideoQuality.DefaultQuality;
  }
}

Future<String?> _ohosCompress({
  required String inputPath,
  required String quality,
  required bool deleteOrigin,
  required int frameRate,
}) async {
  const channel = MethodChannel('nonto_video_compress');
  try {
    final result = await channel.invokeMethod<String>('compress', {
      'inputPath': inputPath,
      'quality': quality,
      'deleteOrigin': deleteOrigin,
      'frameRate': frameRate,
    });
    return result;
  } catch (_) {
    return null;
  }
}

/// 取消当前压缩任务
Future<void> cancelCompression() async {
  if (Platform.operatingSystem == 'ohos') {
    const channel = MethodChannel('nonto_video_compress');
    await channel.invokeMethod('cancel');
  } else {
    await vc.VideoCompress.cancelCompression();
  }
}