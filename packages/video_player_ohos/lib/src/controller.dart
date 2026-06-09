import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart' as vp;
import 'platform_interface.dart';

/// 跨端视频播放控制器
///
/// 统一封装三端差异：
/// - 鸿蒙：调用 OHOS AVPlayer 原生通道
/// - iOS/Android：委托给 [vp.VideoPlayerController]
class NontoVideoPlayerController extends ChangeNotifier {
  late final vp.VideoPlayerController? _vpController;
  NontoVideoPlayerPlatform? _ohosPlatform;
  String? _ohosTextureKey;

  bool _isOhos = false;
  bool _initialized = false;

  NontoVideoPlayerController.network(String url) {
    _init(url, isAsset: false, isFile: false);
  }

  NontoVideoPlayerController.asset(String dataSource) {
    _init(dataSource, isAsset: true, isFile: false);
  }

  NontoVideoPlayerController.file(String filePath) {
    _init(filePath, isAsset: false, isFile: true);
  }

  void _init(String source, {required bool isAsset, required bool isFile}) {
    _isOhos = Platform.operatingSystem == 'ohos';

    if (_isOhos) {
      _ohosPlatform = NontoVideoPlayerPlatform.instance;
      _ohosPlatform!.init(source, isAsset: isAsset, isFile: isFile);
    } else {
      if (isAsset) {
        _vpController = vp.VideoPlayerController.asset(source);
      } else if (isFile) {
        _vpController = vp.VideoPlayerController.file(
          java_io_File(source),
        );
      } else {
        _vpController = vp.VideoPlayerController.networkUrl(
          Uri.parse(source),
        );
      }
    }
  }

  // ignore: non_constant_identifier_names
  dynamic java_io_File(String path) {
    // On non-Android this will just pass through
    return path;
  }

  /// 初始化播放器（加载视频信息后调用）
  Future<void> initialize() async {
    if (_isOhos) {
      _ohosTextureKey = await _ohosPlatform!.create();
      _initialized = true;
    } else {
      await _vpController!.initialize();
      _initialized = true;
    }
    notifyListeners();
  }

  /// 播放
  Future<void> play() async {
    if (_isOhos) {
      await _ohosPlatform!.play();
    } else {
      await _vpController!.play();
    }
    notifyListeners();
  }

  /// 暂停
  Future<void> pause() async {
    if (_isOhos) {
      await _ohosPlatform!.pause();
    } else {
      await _vpController!.pause();
    }
    notifyListeners();
  }

  /// 跳转到指定位置（毫秒）
  Future<void> seekTo(Duration position) async {
    if (_isOhos) {
      await _ohosPlatform!.seekTo(position.inMilliseconds);
    } else {
      await _vpController!.seekTo(position);
    }
  }

  /// 视频总时长
  Duration get duration {
    if (_isOhos) {
      return Duration(milliseconds: _ohosPlatform!.duration);
    }
    return _vpController!.value.duration;
  }

  /// 当前播放位置
  Duration get position {
    if (_isOhos) {
      return Duration(milliseconds: _ohosPlatform!.position);
    }
    return _vpController!.value.position;
  }

  /// 是否正在播放
  bool get isPlaying {
    if (_isOhos) {
      return _ohosPlatform!.isPlaying;
    }
    return _vpController!.value.isPlaying;
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 视频宽高比
  double get aspectRatio {
    if (_isOhos) {
      return _ohosPlatform!.aspectRatio;
    }
    return _vpController!.value.aspectRatio;
  }

  /// 外接纹理 ID（鸿蒙端使用）
  int? get textureId {
    if (_isOhos && _ohosTextureKey != null) {
      return int.tryParse(_ohosTextureKey!);
    }
    return null;
  }

  /// 获取底层 video_player 控制器（仅 iOS/Android 端非 null）
  vp.VideoPlayerController? get vpController => _vpController;

  /// 播放位置流
  Stream<Duration> get positionStream {
    if (_isOhos) {
      return _ohosPlatform!.positionStream.map(
        (ms) => Duration(milliseconds: ms),
      );
    }
    // position 是 ValueNotifier<Duration>，asStream 返回 Stream<Duration>
    // 某些版本可能返回 Stream<Duration?>，做一层安全映射
    return _vpController!.position.asStream().map((d) => d ?? Duration.zero);
  }

  /// 播放结束回调
  Stream<void> get completedStream {
    if (_isOhos) {
      return _ohosPlatform!.completionStream;
    }
    // video_player 没有内置 completed 流，通过监听 isPlaying 状态变化模拟
    late StreamController<void> sc;
    bool wasPlaying = false;
    void listener() {
      final vp = _vpController;
      if (vp == null) return;
      final playing = vp.value.isPlaying;
      final pos = vp.value.position;
      final dur = vp.value.duration;
      final completed = !playing && wasPlaying &&
          dur > Duration.zero &&
          pos >= dur - const Duration(milliseconds: 500);
      wasPlaying = playing;
      if (completed) {
        sc.add(null);
      }
    }
    sc = StreamController<void>.broadcast(
      onListen: () {
        _vpController?.addListener(listener);
      },
      onCancel: () {
        _vpController?.removeListener(listener);
      },
    );
    return sc.stream;
  }

  @override
  Future<void> dispose() async {
    if (_isOhos) {
      await _ohosPlatform!.dispose();
    } else {
      await _vpController?.dispose();
    }
    super.dispose();
  }
}