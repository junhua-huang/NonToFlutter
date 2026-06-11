import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sound_player_native.dart'
    if (dart.library.html) 'sound_player_web.dart';

/// 全局音效服务
///
/// 管理上线、发送、通知三类音效的播放与防抖。
/// 通过条件导入自动切换平台实现：
/// - Web：dart:html Audio 元素（绕过 audioplayers Web 兼容问题）
/// - Native：audioplayers 包
class SoundService {
  static final SoundService _instance = SoundService._();
  factory SoundService() => _instance;
  SoundService._();

  final SoundPlayer _player = SoundPlayer();
  bool _unlocked = false;

  // 防抖：记录每种音效的最后播放时间（ms），500ms 内同一种不重复播放
  final Map<String, int> _lastPlayTime = {};
  static const int _debounceMs = 500;

  /// Web 音频解锁：在用户首次交互后激活浏览器 AudioContext
  Future<void> unlockAudio() async {
    if (_unlocked) return;
    try {
      await _player.unlock();
      _unlocked = true;
      debugPrint('SoundService: audio context unlocked');
    } catch (e) {
      debugPrint('SoundService: unlock failed — $e');
    }
  }

  /// 播放音效，带 500ms 防抖
  Future<void> _play(String assetPath, String key) async {
    // 检查声音设置
    if (!await _isSoundEnabled()) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastPlayTime[key] ?? 0;
    if (now - last < _debounceMs) return;

    _lastPlayTime[key] = now;
    try {
      await _player.playAsset(assetPath);
    } catch (e) {
      debugPrint('SoundService: failed to play $key — $e');
    }
  }

  /// 检查用户是否启用了声音
  Future<bool> _isSoundEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('pref_sound_enabled') ?? true; // 默认开启
    } catch (_) {
      return true;
    }
  }

  /// 上线音效
  Future<void> playOnlineSound() =>
      _play('assets/sounds/online.mp3', 'online');

  /// 发送音效（评论/消息/帖子）
  Future<void> playSendSound() =>
      _play('assets/sounds/send.mp3', 'send');

  /// 通知音效
  Future<void> playNotificationSound() =>
      _play('assets/sounds/notification.mp3', 'notification');

  /// 释放播放器资源
  void dispose() {
    _player.dispose();
  }
}