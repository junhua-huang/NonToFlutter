import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/comic_event.dart';
import 'package:facebook_clone/screens/comic/comic_detail_page.dart';
import 'package:facebook_clone/screens/post/image_viewer_screen.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 漫展卡片 — Twitter/X 风格，简约大气
///
/// 布局（从上到下）：
///   头像 + 漫展名称 + 状态标签 + N人关注
///   图片画廊（全宽）
///   地点 + 日期（同一排）
///   标签
///   关注按钮（右对齐）
///
/// 不显示：发布者名字、发布时间、点赞信息
class ComicEventCard extends StatelessWidget {
  final ComicEvent event;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFollow;
  final bool showOwnerBadge;

  const ComicEventCard({
    super.key,
    required this.event,
    this.onTap,
    this.onToggleFollow,
    this.showOwnerBadge = false,
  });

  // ── 工具方法 ──

  Color _statusColor(int status) {
    switch (status) {
      case 1:
        return AppColors.successGreen;
      case 2:
        return AppColors.textTertiary;
      default:
        return const Color(0xFFFFA726);
    }
  }

  String _fullUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
  }

  /// 是否有可展示的图片
  bool get _hasImages =>
      event.images.isNotEmpty ||
      (event.coverImage != null && event.coverImage!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ComicDetailPage(eventId: event.id),
              ),
            );
          },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _buildHeaderRow(),
          ),
          if (_hasImages) ...[
            const SizedBox(height: 10),
            _buildImageGallery(context),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _buildLocationDateRow(),
          ),
          if (event.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _buildTags(),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: _buildActionRow(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: AppColors.borderLight),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════
  //  顶部：头像 + 漫展名 + 状态 + 关注人数
  // ════════════════════════════════════════

  Widget _buildHeaderRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 头像
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primary,
          backgroundImage: event.creatorAvatar != null &&
                  event.creatorAvatar!.isNotEmpty
              ? NetworkImage(_fullUrl(event.creatorAvatar!))
              : null,
          child: event.creatorAvatar == null || event.creatorAvatar!.isEmpty
              ? Text(
                  (event.name.isNotEmpty ? event.name[0] : '?').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        // 漫展名称 + 状态标签 + 关注人数
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  event.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // 状态标签
              if (showOwnerBadge)
                _buildBadge('我发布的', AppColors.primary)
              else
                _buildBadge(event.statusText, _statusColor(event.status)),
              const SizedBox(width: 8),
              // 关注人数
              Text(
                '${_formatCount(event.followCount)}人关注',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 数字格式化：超过 1000 显示 "1.2K" 等
  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  // ════════════════════════════════════════
  //  图片画廊（全宽，圆角）
  // ════════════════════════════════════════

  Widget _buildImageGallery(BuildContext context) {
    final urls = event.images.isNotEmpty
        ? event.images.map((img) => _fullUrl(img.imageUrl)).toList()
        : [_fullUrl(event.coverImage!)];

    final isSingle = urls.length == 1;

    if (isSingle) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: () {
            ImageViewerScreen.show(context, urls, initialIndex: 0);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              urls[0],
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 220,
                color: AppColors.backgroundSecondary,
                child: const Icon(Icons.image,
                    color: AppColors.textTertiary, size: 40),
              ),
            ),
          ),
        ),
      );
    }

    // 多图横向滑动（Web 端支持鼠标/触控板拖拽）
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isFirst = index == 0;
          final isLast = index == urls.length - 1;
          return GestureDetector(
            onTap: () {
              ImageViewerScreen.show(context, urls, initialIndex: index);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isFirst ? 12 : 2),
                bottomLeft: Radius.circular(isFirst ? 12 : 2),
                topRight: Radius.circular(isLast ? 12 : 2),
                bottomRight: Radius.circular(isLast ? 12 : 2),
              ),
              child: Image.network(
                urls[index],
                width: 240,
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 240,
                  height: 220,
                  color: AppColors.backgroundSecondary,
                  child: const Icon(Icons.image,
                      color: AppColors.textTertiary, size: 32),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  }

  // ════════════════════════════════════════
  //  地点 + 日期（同一排）
  // ════════════════════════════════════════

  Widget _buildLocationDateRow() {
    final locationParts = <String>[];
    if (event.cityName.isNotEmpty) locationParts.add(event.cityName);
    if (event.venue.isNotEmpty) locationParts.add(event.venue);
    final location = locationParts.join(' · ');

    final dateRange = AppDateUtils.formatDateRange(event.startDate, event.endDate);

    return Row(
      children: [
        if (location.isNotEmpty) ...[
          const Icon(Icons.location_on_outlined,
              size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        if (location.isNotEmpty && dateRange.isNotEmpty) ...[
          const SizedBox(width: 12),
        ],
        if (dateRange.isNotEmpty) ...[
          const Icon(Icons.calendar_today,
              size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              dateRange,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        // 票价信息
        if (event.ticketInfo != null && event.ticketInfo!.isNotEmpty) ...[
          const SizedBox(width: 12),
          const Icon(Icons.confirmation_number_outlined,
              size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              event.ticketInfo!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ════════════════════════════════════════
  //  标签
  // ════════════════════════════════════════

  Widget _buildTags() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: event.tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '#$tag',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ════════════════════════════════════════
  //  底部操作行：关注按钮（右对齐）
  // ════════════════════════════════════════

  Widget _buildActionRow() {
    return Row(
      children: [
        const Spacer(),
        if (onToggleFollow != null)
          GestureDetector(
            onTap: onToggleFollow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: event.isFollowed
                    ? Colors.transparent
                    : AppColors.textPrimary,
                borderRadius: BorderRadius.circular(20),
                border: event.isFollowed
                    ? Border.all(color: AppColors.borderDivider, width: 1.2)
                    : null,
              ),
              child: Text(
                event.isFollowed ? '正在关注' : '关注',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: event.isFollowed
                      ? AppColors.textPrimary
                      : Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
