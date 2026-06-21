import 'dart:async';
import 'package:flutter/services.dart';

/// 视频播放器平台接口（鸿蒙端通过 MethodChannel 调用原生）
abstract class NontoVideoPlayerPlatform {
  static final NontoVideoPlayerPlatform instance =
      _NontoVideoPlayerPlatformImpl();

  Future<String> create();
  Future<void> init(String source, {bool isAsset, bool isFile});
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(int milliseconds);
  Future<void> dispose();

  int get duration;
  int get position;
  bool get isPlaying;
  double get aspectRatio;
  Stream<int> get positionStream;
  Stream<void> get completionStream;
}

class _NontoVideoPlayerPlatformImpl extends NontoVideoPlayerPlatform {
  static const _channel = MethodChannel('nonto_video_player');

  int _duration = 0;
  int _position = 0;
  bool _isPlaying = false;
  double _aspectRatio = 16 / 9;

  final _positionController = StreamController<int>.broadcast();
  final _completionController = StreamController<void>.broadcast();

  _NontoVideoPlayerPlatformImpl() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPositionUpdate':
        _position = call.arguments as int;
        _positionController.add(_position);
        break;
      case 'onCompletion':
        _isPlaying = false;
        _completionController.add(null);
        break;
      case 'onPrepared':
        final args = call.arguments as Map;
        _duration = args['duration'] as int;
        _aspectRatio = (args['aspectRatio'] as num).toDouble();
        break;
    }
  }

  @override
  Future<String> create() async {
    final result = await _channel.invokeMethod<String>('create');
    return result ?? '-1';
  }

  @override
  Future<void> init(String source,
      {bool isAsset = false, bool isFile = false}) async {
    await _channel.invokeMethod('init', {
      'source': source,
      'isAsset': isAsset,
      'isFile': isFile,
    });
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    await _channel.invokeMethod('play');
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    await _channel.invokeMethod('pause');
  }

  @override
  Future<void> seekTo(int milliseconds) async {
    await _channel.invokeMethod('seekTo', {'position': milliseconds});
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
    _positionController.close();
    _completionController.close();
  }

  @override
  int get duration => _duration;

  @override
  int get position => _position;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get aspectRatio => _aspectRatio;

  @override
  Stream<int> get positionStream => _positionController.stream;

  @override
  Stream<void> get completionStream => _completionController.stream;
}
