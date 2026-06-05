import 'package:flutter/material.dart';

/// 统一颜色常量 — 所有 screen/widget 文件应引用此类，禁止硬编码颜色值
class AppColors {
  AppColors._();

  // 主色调
  static const Color primary = Color(0xFF1D9BF0);

  // 文本颜色
  static const Color textPrimary = Color(0xFF0F1419);
  static const Color textSecondary = Color(0xFF536471);
  static const Color textTertiary = Color(0xFF8B98A5);

  // 边框 & 分割线
  static const Color borderLight = Color(0xFFEFF3F4);
  static const Color borderDivider = Color(0xFFE0E0E0);

  // 背景
  static const Color background = Color(0xFFFFFFFF);
  static const Color backgroundSecondary = Color(0xFFF7F9F9);
  static const Color surface = Color(0xFFF7F9F9);

  // 功能色
  static const Color likeRed = Color(0xFFF91880);
  static const Color successGreen = Color(0xFF00BA7C);

  // UI 元素色
  static const Color dragHandle = Color(0xFFCBD5E1);
  static const Color selectionHighlight = Color(0xFFE8F0FE);
}

/// 全局 AppBar 主题配置
class AppTheme {
  AppTheme._();

  static const AppBarTheme appBarTheme = AppBarTheme(
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