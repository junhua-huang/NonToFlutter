import 'package:intl/intl.dart';

/// 全局日期工具类
/// 所有时间均以北京时间 (UTC+8) 为基准显示
class AppDateUtils {
  /// 北京时区偏移
  static const Duration beijingOffset = Duration(hours: 8);

  /// 将服务器时间字符串解析为北京时间 DateTime
  /// 服务器返回的可能是 UTC 字符串（带 Z 后缀）或无时区字符串
  static DateTime parseBeijingTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return DateTime.now();
    try {
      final dt = DateTime.parse(dateString);
      // 如果字符串没有时区信息，DateTime.parse 会当作本地时间
      // 我们需要统一按 UTC 解析，再加 8 小时偏移得到北京时间
      if (!dateString.contains('Z') && !dateString.contains('+') && !dateString.contains('-', dateString.length - 6)) {
        // 无时区标记，当作 UTC 处理
        return dt.toUtc().add(beijingOffset);
      }
      // 有时区标记（如 2024-06-10T10:00:00Z），先转 UTC 再加偏移
      return dt.toUtc().add(beijingOffset);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// 获取当前北京时间
  static DateTime nowBeijing() {
    return DateTime.now().toUtc().add(beijingOffset);
  }

  /// 相对时间格式化（基于北京时间）
  /// 例如：刚刚 / N分钟前 / N小时前 / 昨天 / N天前 / N个月前 / N年前
  static String formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = nowBeijing();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}周前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }

  /// 格式化日期时间：yyyy-MM-dd HH:mm
  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  /// 格式化日期：yyyy年MM月dd日
  static String formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat('yyyy年MM月dd日').format(dateTime);
  }

  /// 格式化日期范围（用于漫展卡片）
  /// 输入为 ISO 日期字符串（如 "2026-06-10"），返回 "M月D日" 或 "M月D日 - M月D日"
  static String formatDateRange(String? startDate, String? endDate) {
    try {
      if (startDate == null || startDate.isEmpty) return '';
      final sd = DateTime.parse(startDate);
      if (endDate != null && endDate.isNotEmpty && endDate != startDate) {
        final ed = DateTime.parse(endDate);
        return '${sd.month}月${sd.day}日 - ${ed.month}月${ed.day}日';
      }
      return '${sd.month}月${sd.day}日';
    } catch (_) {
      return '';
    }
  }
}
