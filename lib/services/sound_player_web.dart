/// Web 平台音效播放器
///
/// 使用 dart:html Audio 元素直接播放，绕过 audioplayers 在 Web 上的兼容性问题。
/// 通过 rootBundle 加载 asset 字节 → 创建 Blob URL → Audio 元素播放。
library;

import 'dart:html' as html;
import 'package:flutter/services.dart' show rootBundle;

class SoundPlayer {
  final Map<String, _CachedAudio> _cache = {};

  /// 解锁浏览器音频（解除自动播放限制）
  /// 通过短暂播放静音 Audio 元素来激活浏览器的音频上下文
  Future<void> unlock() async {
    try {
      final audio = html.AudioElement();
      audio.volume = 0;
      // 创建极短静音 WAV (44 字节 header)
      final wavHeader = _createSilentWavHeader();
      final blob = html.Blob([wavHeader], 'audio/wav');
      final url = html.Url.createObjectUrlFromBlob(blob);
      audio.src = url;
      await audio.play();
      audio.pause();
      html.Url.revokeObjectUrl(url);
      audio.remove();
    } catch (_) {}
  }

  /// 生成静音 WAV 文件头 (0.1 秒)
  static List<int> _createSilentWavHeader() {
    // 0.1s @ 8000Hz mono 8-bit = 800 samples
    final sampleRate = 8000;
    final durationSec = 0.1;
    final numSamples = (sampleRate * durationSec).round();
    final dataSize = numSamples;
    final fileSize = 44 + dataSize;
    final bytes = <int>[];
    // RIFF header
    bytes.addAll('RIFF'.codeUnits);
    bytes.addAll(_int32Le(fileSize - 8));
    bytes.addAll('WAVE'.codeUnits);
    // fmt chunk
    bytes.addAll('fmt '.codeUnits);
    bytes.addAll(_int32Le(16)); // chunk size
    bytes.addAll(_int16Le(1)); // PCM
    bytes.addAll(_int16Le(1)); // mono
    bytes.addAll(_int32Le(sampleRate));
    bytes.addAll(_int32Le(sampleRate)); // byte rate: 8000 * 1 * 1
    bytes.addAll(_int16Le(1)); // block align
    bytes.addAll(_int16Le(8)); // bits per sample (8)
    // data chunk
    bytes.addAll('data'.codeUnits);
    bytes.addAll(_int32Le(dataSize));
    // silent samples (128 = center for 8-bit unsigned PCM)
    bytes.addAll(List.filled(dataSize, 128));
    return bytes;
  }

  static List<int> _int32Le(int v) => [
    v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF
  ];

  static List<int> _int16Le(int v) => [
    v & 0xFF, (v >> 8) & 0xFF
  ];

  /// 播放 asset 音效
  Future<void> playAsset(String assetPath) async {
    try {
      // 尝试复用缓存的 blob URL
      var cached = _cache[assetPath];
      if (cached != null && cached.isValid) {
        cached.audio.currentTime = 0;
        await cached.audio.play();
        return;
      }

      // 加载 asset 字节 → Blob → URL
      final bytes = await rootBundle.load(assetPath);
      final blob = html.Blob([bytes.buffer.asUint8List()], 'audio/mpeg');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final audio = html.AudioElement(url);
      audio.load();

      // 播放完成后不立即释放 URL，缓存复用
      // 错误时释放并清除缓存
      audio.onError.listen((_) {
        html.Url.revokeObjectUrl(url);
        _cache.remove(assetPath);
      });

      await audio.play();

      _cache[assetPath] = _CachedAudio(audio: audio, url: url);
    } catch (_) {
      // 播放失败，静默处理
    }
  }

  void dispose() {
    for (final c in _cache.values) {
      c.audio.pause();
      c.audio.src = '';
      html.Url.revokeObjectUrl(c.url);
    }
    _cache.clear();
  }
}

class _CachedAudio {
  final html.AudioElement audio;
  final String url;

  _CachedAudio({required this.audio, required this.url});

  bool get isValid {
    try {
      // 检查 Audio 元素是否仍可用
      audio.readyState;
      return true;
    } catch (_) {
      return false;
    }
  }
}