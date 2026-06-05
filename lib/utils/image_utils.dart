import 'package:cached_network_image/cached_network_image.dart';
import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:flutter/material.dart';

class ImageUtils {
  static Widget buildAvatar(User? user, {double radius = 20}) {
    if (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) {
      final url = user.avatarUrl!.startsWith('http')
          ? user.avatarUrl!
          : '${AppConfig.baseUrl.replaceFirst('/api', '')}${user.avatarUrl!}';
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(url),
        backgroundColor: Colors.grey[200]!,
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

  static Widget buildPostImage(String? imageUrl, {BoxFit fit = BoxFit.cover, double? width, double? height}) {
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
    final url = imageUrl.startsWith('http')
        ? imageUrl
        : '${AppConfig.baseUrl.replaceFirst('/api', '')}$imageUrl';
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

  static Widget buildCoverPhoto(String? url) {
    if (url == null || url.isEmpty) return Container(color: Colors.grey[300]);
    final fullUrl = url.startsWith('http')
        ? url
        : '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
    return CachedNetworkImage(
      imageUrl: fullUrl, fit: BoxFit.cover, width: double.infinity, height: 200,
      placeholder: (_, __) => Container(color: Colors.grey[300], height: 200),
      errorWidget: (_, __, ___) => Container(color: Colors.grey[300], height: 200),
      fadeInDuration: const Duration(milliseconds: 300),
      fadeInCurve: Curves.easeInOut,
    );
  }
}
