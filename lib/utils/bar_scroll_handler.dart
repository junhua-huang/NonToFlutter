import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';

/// 统一的顶部标题栏 / 底部导航栏滚动显隐处理。
///
/// 四个首页 Tab（Feed / Search / Messages / Profile）原本各自内联了一份
/// 几乎相同的 `NotificationListener<ScrollUpdateNotification>` 逻辑，存在两
/// 个问题：
///   1. 重复代码——改一处容易漏改其余三处，导致行为不一致；
///   2. 在列表顶部（pixels <= 0）时仍参与方向判断，下拉刷新的弹性回弹会
///      发出方向不稳定的 scrollDelta，把标题栏误判为「向上滚→隐藏」，
///      回弹触顶后又显示，造成抖动。
///
/// 本 helper 的关键差异：在顶部区域（含下拉刷新的 overscroll）**无条件返回**，
/// 不参与隐藏判断，从而杜绝抖动；其余位置维持原有的方向判断逻辑。
bool handleBarScrollNotification(
  ScrollUpdateNotification notif,
  WidgetRef ref,
) {
  final metrics = notif.metrics;

  // 顶部安全区（含下拉刷新回弹越界）：始终显示，且不参与方向判断。
  // 阈值 5.0 用于吸收 SmartRefresher 收起 header 后 scroll position 短暂越界
  // 至 0~2px 的情况，避免 barVisible 在显示/隐藏间反复 toggle 导致页面晃动。
  if (metrics.pixels <= 5.0) {
    if (!ref.read(barVisibleProvider)) {
      ref.read(barVisibleProvider.notifier).state = true;
    }
    return false;
  }

  // 微小位移忽略，避免抖动
  final delta = notif.scrollDelta ?? 0;
  if (delta.abs() < 3) return false;

  final barVisible = ref.read(barVisibleProvider);
  if (delta > 3 && barVisible) {
    ref.read(barVisibleProvider.notifier).state = false;
  } else if (delta < -3 && !barVisible) {
    ref.read(barVisibleProvider.notifier).state = true;
  }
  return false;
}
