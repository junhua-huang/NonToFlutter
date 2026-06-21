import 'package:cached_network_image/cached_network_image.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/models/user.dart';
import 'package:flutter/material.dart';

class ImageUtils {
  /// 安全拼接完整 URL，避免双斜杠
  static String resolveUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    final value = url.trim();
    if (value.isEmpty) return '';

    final lower = value.toLowerCase();
    if (lower.startsWith('file:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('data:')) {
      return '';
    }
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return value;
    }

    final base = AppConfig.baseUrl.replaceFirst('/api', '');
    final cleanBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final cleanUrl = value.startsWith('/') ? value : '/$value';
    return '$cleanBase$cleanUrl';
  }

  static Widget buildAvatar(User? user, {double radius = 20}) {
    if (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) {
      final url = _cacheBustUrl(resolveUrl(user.avatarUrl), user.avatarCacheTs);
      // 限制解码尺寸：头像最多按直径的 2x 设备像素解码，避免几 MB 的原图
      // 全分辨率解码进内存缓存（之前每个头像都解码原图，是「网络/列表卡」的主因之一）。
      final displayPx = (radius * 2 * 2).round().clamp(64, 512);
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[200]!,
        child: ClipOval(
          child: CachedNetworkImage(
            key: ValueKey(url),
            imageUrl: url,
            fit: BoxFit.cover,
            width: radius * 2,
            height: radius * 2,
            memCacheWidth: displayPx,
            memCacheHeight: displayPx,
            placeholder: (_, __) => Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.grey[400]),
            ),
            errorWidget: (_, __, ___) => Center(
              child: Text(
                user.initials,
                style: TextStyle(
                    fontSize: radius * 0.8,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold),
              ),
            ),
            fadeInDuration: const Duration(milliseconds: 200),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.blue,
      child: Text(
        user?.initials ?? '?',
        style: TextStyle(
            fontSize: radius * 0.8,
            color: Colors.white,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  static Widget buildCircularRemoteImage(
    String url, {
    double radius = 20,
    Widget? fallback,
    Color? backgroundColor,
  }) {
    final displayPx = (radius * 2 * 2).round().clamp(64, 512);
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey[200]!,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: radius * 2,
          height: radius * 2,
          memCacheWidth: displayPx,
          memCacheHeight: displayPx,
          errorWidget: (_, __, ___) =>
              fallback ?? const Icon(Icons.broken_image),
          fadeInDuration: const Duration(milliseconds: 200),
        ),
      ),
    );
  }

  /// 为 URL 追加 ?t=xxx 缓存破坏参数，确保上传新图后 CachedNetworkImage 视为不同 URL
  static String _cacheBustUrl(String url, int? cacheTs) {
    if (cacheTs == null) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}t=$cacheTs';
  }

  /// 清除指定 URL 的 CachedNetworkImage 缓存
  static Future<void> evictCachedImage(String? url) async {
    if (url == null || url.isEmpty) return;
    final fullUrl = resolveUrl(url);
    try {
      await CachedNetworkImage.evictFromCache(fullUrl);
    } catch (_) {
      // 忽略清除缓存失败
    }
  }

  static Widget buildPostImage(String? imageUrl,
      {BoxFit fit = BoxFit.cover, double? width, double? height}) {
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
    final url = resolveUrl(imageUrl);
    // 限制解码宽度：feed 里图片按屏幕宽度显示，没必要解码 3000-4000px 的原图。
    // 1080 足够覆盖主流手机屏幕（约 2x 像素），显著降低内存与解码耗时，
    // 这是「200M 带宽却感觉卡」的主因——卡的是解码与内存压力，不是带宽。
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: 1080,
      placeholder: (_, __) => SizedBox(
          width: width,
          height: height ?? 200,
          child:
              const Center(child: CircularProgressIndicator(strokeWidth: 2))),
      errorWidget: (_, __, ___) => Container(
          color: Colors.grey[300],
          height: height ?? 200,
          child: const Icon(Icons.broken_image, color: Colors.grey)),
      fadeInDuration: const Duration(milliseconds: 300),
      fadeInCurve: Curves.easeInOut,
    );
  }

  static Widget buildCoverPhoto(String? url, {int? cacheTs}) {
    if (url == null || url.isEmpty) return Container(color: Colors.grey[300]);
    final fullUrl = _cacheBustUrl(resolveUrl(url), cacheTs);
    return CachedNetworkImage(
      key: ValueKey(fullUrl),
      imageUrl: fullUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: 200,
      memCacheWidth: 1080,
      placeholder: (_, __) => Container(color: Colors.grey[300], height: 200),
      errorWidget: (_, __, ___) =>
          Container(color: Colors.grey[300], height: 200),
      fadeInDuration: const Duration(milliseconds: 300),
      fadeInCurve: Curves.easeInOut,
    );
  }
}
