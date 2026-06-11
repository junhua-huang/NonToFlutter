import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart' as vp;
import 'controller.dart';

/// 跨端视频播放 Widget
///
/// 根据平台选择渲染方式：
/// - 鸿蒙：Texture（外接纹理）
/// - iOS/Android：VideoPlayer widget
///
/// 注意：此 widget 仅输出原始视频渲染，不处理宽高比/缩放。
/// 调用方需自行使用 AspectRatio、FittedBox 等控制布局。
class NontoVideoPlayer extends StatelessWidget {
  final NontoVideoPlayerController controller;

  const NontoVideoPlayer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (!controller.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        if (Platform.operatingSystem == 'ohos') {
          final textureId = controller.textureId;
          if (textureId != null) {
            return Texture(textureId: textureId);
          } else {
            return const SizedBox.shrink();
          }
        } else {
          final vpc = controller.vpController;
          if (vpc == null) return const SizedBox.shrink();
          return vp.VideoPlayer(vpc);
        }
      },
    );
  }
}