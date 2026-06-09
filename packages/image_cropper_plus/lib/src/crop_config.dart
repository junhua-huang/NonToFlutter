import 'dart:ui';

/// 裁剪配置
class CropConfig {
  /// 裁剪框宽高比（null = 自由裁剪）
  final double? aspectRatio;

  /// 裁剪框最小尺寸（逻辑像素）
  final double minCropSize;

  /// 裁剪框最大尺寸（逻辑像素）
  final double maxCropSize;

  /// 裁剪框圆角半径
  final double cornerRadius;

  /// 裁剪网格线颜色
  final Color gridColor;

  /// 裁剪网格线宽度
  final double gridWidth;

  /// 遮罩颜色（裁剪框外部的半透明遮罩）
  final Color maskColor;

  /// 裁剪框边框颜色
  final Color borderColor;

  /// 裁剪框边框宽度
  final double borderWidth;

  /// 是否显示九宫格辅助线
  final bool showGrid;

  /// 是否允许旋转
  final bool allowRotation;

  const CropConfig({
    this.aspectRatio,
    this.minCropSize = 100,
    this.maxCropSize = 500,
    this.cornerRadius = 0,
    this.gridColor = const Color(0x80FFFFFF),
    this.gridWidth = 1.0,
    this.maskColor = const Color(0x80000000),
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderWidth = 1.5,
    this.showGrid = true,
    this.allowRotation = false,
  });
}