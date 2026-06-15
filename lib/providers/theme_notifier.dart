import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_notifier.dart';

/// ThemeNotifier — 支持 light / dark / system 三种模式
class ThemeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences _prefs;

  ThemeNotifier(this._prefs) : super(ThemeMode.system) {
    _loadThemeMode();
  }

  bool get isDark => state == ThemeMode.dark;
  bool get isSystem => state == ThemeMode.system;

  /// 获取持久化 key
  static const _prefKey = 'theme_mode';

  Future<void> _loadThemeMode() async {
    final saved = _prefs.getString(_prefKey);
    state = _fromString(saved);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_prefKey, _toString(mode));
  }

  /// 循环切换：light → dark → system → light …
  Future<void> toggleTheme() async {
    final next = switch (state) {
      ThemeMode.light   => ThemeMode.dark,
      ThemeMode.dark    => ThemeMode.system,
      ThemeMode.system  => ThemeMode.light,
      _                 => ThemeMode.light,
    };
    await setThemeMode(next);
  }

  // ─── 序列化 ───
  static ThemeMode _fromString(String? s) => switch (s) {
    'dark'   => ThemeMode.dark,
    'system' => ThemeMode.system,
    _        => ThemeMode.light,   // null / 'light' / 未知值 → light
  };

  static String _toString(ThemeMode m) => switch (m) {
    ThemeMode.dark   => 'dark',
    ThemeMode.system => 'system',
    _                => 'light',
  };
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});
