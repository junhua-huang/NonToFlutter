import 'package:cached_network_image/cached_network_image.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/models/user.dart';
import 'package:flutter/material.dart';

class ImageUtils {
  /// 安全拼接完整 URL，避免双斜杠
  static String resolveUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    final base = AppConfig.baseUrl.replaceFirst('/api', '');
    final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final cleanUrl = url.startsWith('/') ? url : '/$url';
    return '$cleanBase$cleanUrl';
  }

  static Widget buildAvatar(User? user, {double radius = 20}) {
    if (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) {
      final url = _cacheBustUrl(resolveUrl(user.avatarUrl), user.avatarCacheTs);
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
            placeholder: (_, __) => Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400]),
            ),
            errorWidget: (_, __, ___) => Center(
              child: Text(
                user.initials ?? '?',
                style: TextStyle(fontSize: radius * 0.8, color: Colors.blue, fontWeight: FontWeight.bold),
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
        style: TextStyle(fontSize: radius * 0.8, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 为 URL 追加 ?t=xxx 缓存破坏参数，确保上传新图后 CachedNetworkImage 视为不同 URL
  static String _cacheBustUrl(String url, int? cacheTs) {
    if (cacheTs == null) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '${url}${sep}t=$cacheTs';
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

  static Widget buildPostImage(String? imageUrl, {BoxFit fit = BoxFit.cover, double? width, double? height}) {
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
    final url = resolveUrl(imageUrl);
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      placeholder: (_, __) => SizedBox(width: width, height: height ?? 200, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
      errorWidget: (_, __, ___) => Container(color: Colors.grey[300], height: height ?? 200,
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
      imageUrl: fullUrl, fit: BoxFit.cover, width: double.infinity, height: 200,
      placeholder: (_, __) => Container(color: Colors.grey[300], height: 200),
      errorWidget: (_, __, ___) => Container(color: Colors.grey[300], height: 200),
      fadeInDuration: const Duration(milliseconds: 300),
      fadeInCurve: Curves.easeInOut,
    );
  }
}
