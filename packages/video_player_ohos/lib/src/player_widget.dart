import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart' as vp;
import 'controller.dart';

/// 跨端视频播放 Widget
///
/// 根据平台选择渲染方式：
/// - 鸿蒙：Texture（外接纹理）
/// - iOS/Android：VideoPlayer widget
class NontoVideoPlayer extends StatelessWidget {
  final NontoVideoPlayerController controller;
  final BoxFit? fit;

  const NontoVideoPlayer({super.key, required this.controller, this.fit});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (!controller.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        Widget videoWidget;
        if (Platform.operatingSystem == 'ohos') {
          final textureId = controller.textureId;
          if (textureId != null) {
            videoWidget = Texture(textureId: textureId);
          } else {
            return const SizedBox.shrink();
          }
        } else {
          final vpc = controller.vpController;
          if (vpc == null) return const SizedBox.shrink();
          videoWidget = vp.VideoPlayer(vpc);
        }

        final fitToUse = fit ?? BoxFit.contain;
        return FittedBox(
          fit: fitToUse,
          child: AspectRatio(
            aspectRatio: controller.aspectRatio,
            child: videoWidget,
          ),
        );
      },
    );
  }
}