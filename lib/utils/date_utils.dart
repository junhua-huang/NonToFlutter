import 'package:intl/intl.dart';

/// 全局日期工具类
/// 所有时间均以北京时间 (UTC+8) 为基准显示
class AppDateUtils {
  /// 北京时区偏移
  static const Duration beijingOffset = Duration(hours: 8);

  /// 将服务器时间字符串解析为本地时间 DateTime（北京时间）
  /// 后端使用 datetime.utcnow() 存储，.isoformat() 序列化时通常不带 Z 后缀
  /// 例如："2026-06-15T10:00:00" 实际是 UTC 时间
  ///
  /// 解析策略：
  /// - 无时区标记 → 视为 UTC，+8h 得到北京时间，返回 isUtc=false 的本地 DateTime
  /// - 有时区标记（Z 或 +HH:MM）→ 先转 UTC，再 +8h 得到北京时间
  ///
  /// 返回的 DateTime 的 isUtc=false，值是北京时间，可以安全调用 toLocal()
  static DateTime parseBeijingTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return _nowLocalBeijing();
    try {
      final dt = DateTime.parse(dateString);
      DateTime utcDt;
      // 如果字符串有时区标记（如 Z、+08:00），DateTime.parse 会正确解析为 UTC
      if (dateString.contains('Z') ||
          (dateString.contains('+') && dateString.indexOf('+') > dateString.indexOf('T')) ||
          (dateString.contains('-', dateString.length - 6) && dateString.indexOf('T') > 0)) {
        utcDt = dt.toUtc();
      } else {
        // 无时区标记 → 后端存的是 UTC，但 DateTime.parse 当作本地时间
        // 需要用 dt 的年月日时分秒重新构造 UTC DateTime
        utcDt = DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute,
            dt.second, dt.millisecond, dt.microsecond);
      }
      // UTC + 8h = 北京时间，构造为本地 DateTime（isUtc=false）
      final bj = utcDt.add(beijingOffset);
      return DateTime(bj.year, bj.month, bj.day, bj.hour, bj.minute,
          bj.second, bj.millisecond, bj.microsecond);
    } catch (_) {
      return _nowLocalBeijing();
    }
  }

  /// 获取当前北京时间（isUtc=false 的本地 DateTime）
  static DateTime _nowLocalBeijing() {
    final now = DateTime.now();
    if (now.timeZoneOffset == beijingOffset) {
      return now;
    }
    final utc = now.toUtc().add(beijingOffset);
    return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute,
        utc.second, utc.millisecond, utc.microsecond);
  }

  /// 相对时间格式化（基于北京时间）
  /// 例如：刚刚 / N分钟前 / N小时前 / 昨天 / N天前 / N个月前 / N年前
  static String formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = _nowLocalBeijing();
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
