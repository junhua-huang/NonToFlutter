/// 跨端视频播放器（nonto）
///
/// - 鸿蒙端：基于 AVPlayer + Texture（外接纹理）实现硬件解码播放
/// - iOS 端：封装 video_player（AVPlayer）
/// - Android 端：封装 video_player（ExoPlayer）
library;

export 'src/controller.dart';
export 'src/player_widget.dart';
export 'src/platform_stub.dart' if (dart.library.io) 'src/platform_native.dart';
