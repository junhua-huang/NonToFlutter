/// 原生平台（Android/iOS/Desktop）音效播放器
///
/// 使用 audioplayers 包播放 asset 音效。
library;

import 'package:audioplayers/audioplayers.dart';

class SoundPlayer {
  AudioPlayer? _player;

  AudioPlayer get _p => _player ??= AudioPlayer();

  /// 原生平台无需解锁音频上下文
  Future<void> unlock() async {}

  /// 播放 asset 音效
  Future<void> playAsset(String assetPath) async {
    try {
      await _p.play(AssetSource(assetPath));
    } catch (_) {
      // 静默处理播放失败
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}