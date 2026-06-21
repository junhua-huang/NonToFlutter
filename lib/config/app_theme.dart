import 'package:flutter/material.dart';

/// 统一颜色入口。
///
/// 品牌/功能色保持固定；背景、文本、边框等语义色会跟随当前 ThemeMode。
/// 这样旧页面继续引用 AppColors 也能获得深色模式适配，避免逐页漏改。
class AppColors {
  AppColors._();

  static Brightness _brightness = Brightness.light;

  static bool get _isDark => _brightness == Brightness.dark;

  /// 在 MaterialApp 构建前同步当前主题模式。
  static void syncThemeMode(ThemeMode mode) {
    _brightness = switch (mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
  }

  // 主色调
  static const Color primary = Color(0xFF1D9BF0);

  static Color get primaryBlack =>
      _isDark ? const Color(0xFFE7E9EA) : const Color(0xFF0F1419);

  // 文本颜色
  static Color get textPrimary =>
      _isDark ? const Color(0xFFE7E9EA) : const Color(0xFF0F1419);
  static Color get textSecondary =>
      _isDark ? const Color(0xFFB0B8C1) : const Color(0xFF536471);
  static Color get textTertiary =>
      _isDark ? const Color(0xFF71767B) : const Color(0xFF8B98A5);

  // 边框 & 分割线
  static Color get borderLight =>
      _isDark ? const Color(0xFF2F3336) : const Color(0xFFEFF3F4);
  static Color get borderDivider =>
      _isDark ? const Color(0xFF2A2F33) : const Color(0xFFE0E0E0);

  // 背景
  static Color get background =>
      _isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color get backgroundSecondary =>
      _isDark ? const Color(0xFF16181C) : const Color(0xFFF7F9F9);
  static Color get surface =>
      _isDark ? const Color(0xFF202327) : const Color(0xFFF7F9F9);

  // 功能色
  static const Color likeRed = Color(0xFFF91880);
  static const Color successGreen = Color(0xFF00BA7C);

  // UI 元素色
  static Color get dragHandle =>
      _isDark ? const Color(0xFF536471) : const Color(0xFFCBD5E1);
  static Color get selectionHighlight =>
      _isDark ? const Color(0xFF102A43) : const Color(0xFFE8F0FE);
}

/// 全局 AppBar 主题配置
class AppTheme {
  AppTheme._();

  static AppBarTheme get appBarTheme => AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        shadowColor: AppColors.borderLight,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      );
}
