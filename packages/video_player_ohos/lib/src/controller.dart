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
///
/// 关键：iOS/Android 端必须把底层 [_vpController] 的 value 变化转发给
/// 自身的 listeners，否则 [NontoVideoPlayer]（AnimatedBuilder）不会随播放
/// 进度重建，导致黑屏、进度条不更新。
class NontoVideoPlayerController extends ChangeNotifier {
  late final vp.VideoPlayerController? _vpController;
  NontoVideoPlayerPlatform? _ohosPlatform;
  String? _ohosTextureKey;

  bool _isOhos = false;
  bool _initialized = false;

  // 用于在 iOS/Android 端把 position 变化推给 positionStream 的订阅者。
  // video_player 内部更新 value 时会触发 _vpForwardListener，借此把当前
  // position 推入流。鸿蒙端由 platform 的 positionStream 直接驱动。
  final StreamController<Duration> _positionStreamController =
      StreamController<Duration>.broadcast();

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
      // 桥接：底层 vpController 的 value 任何变化都转发给自己的 listeners，
      // 使 NontoVideoPlayer（AnimatedBuilder）随播放进度重建，避免黑屏和进度条不动。
      _vpController!.addListener(_vpForwardListener);
    }
  }

  /// iOS/Android 端的桥接监听器：转发底层 value 变化，并把当前 position
  /// 推入 positionStream，使订阅者能拿到实时进度。
  void _vpForwardListener() {
    if (!_initialized) return;
    final vpc = _vpController;
    if (vpc == null) return;
    // 转发给 NontoVideoPlayer / 外部 listener（触发重建）
    notifyListeners();
    // 推送 position 给 positionStream 订阅者
    if (!_positionStreamController.isClosed) {
      _positionStreamController.add(vpc.value.position);
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

  /// 设置音量（0.0 静音 ~ 1.0 最大）
  Future<void> setVolume(double volume) async {
    if (_isOhos) {
      // 鸿蒙端 platform 暂未暴露音量接口，忽略
      return;
    }
    await _vpController!.setVolume(volume);
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

  /// 是否缓冲中（iOS/Android 端从底层 value 读取）
  bool get isBuffering {
    if (_isOhos) {
      return false;
    }
    return _vpController!.value.isBuffering;
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
  ///
  /// iOS/Android 端：由 [_vpForwardListener] 在底层 value 变化时把当前
  /// position 推入 [_positionStreamController]（之前用 `position.asStream()`
  /// 不会因播放进度更新而触发，导致进度条不动）。
  Stream<Duration> get positionStream {
    if (_isOhos) {
      return _ohosPlatform!.positionStream.map(
        (ms) => Duration(milliseconds: ms),
      );
    }
    return _positionStreamController.stream;
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
      _vpController?.removeListener(_vpForwardListener);
      await _vpController?.dispose();
    }
    await _positionStreamController.close();
    super.dispose();
  }
}