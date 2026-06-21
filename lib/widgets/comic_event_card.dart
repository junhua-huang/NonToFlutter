import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/comic_event.dart';
import 'package:nonto/screens/comic/comic_detail_page.dart';
import 'package:nonto/screens/post/image_viewer_screen.dart';
import 'package:nonto/services/comic_service.dart';
import 'package:nonto/utils/date_utils.dart';
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
class ComicEventCard extends StatefulWidget {
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

  @override
  State<ComicEventCard> createState() => _ComicEventCardState();
}

class _ComicEventCardState extends State<ComicEventCard> {
  final ComicService _comicService = ComicService();
  late bool _isFollowed;
  late int _followCount;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _isFollowed = widget.event.isFollowed;
    _followCount = widget.event.followCount;
  }

  @override
  void didUpdateWidget(covariant ComicEventCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部 event 更新时同步本地状态（如列表刷新后数据变化）
    if (oldWidget.event.isFollowed != widget.event.isFollowed) {
      _isFollowed = widget.event.isFollowed;
    }
    if (oldWidget.event.followCount != widget.event.followCount) {
      _followCount = widget.event.followCount;
    }
  }

  Future<void> _handleToggleFollow() async {
    if (_isToggling) return;
    if (widget.onToggleFollow != null) {
      widget.onToggleFollow!();
      return;
    }
    // 卡片自带关注能力：乐观更新 + 失败回滚
    _isToggling = true;
    final wasFollowed = _isFollowed;
    final oldCount = _followCount;
    setState(() {
      _isFollowed = !wasFollowed;
      _followCount = wasFollowed ? oldCount - 1 : oldCount + 1;
    });
    try {
      final resp = await _comicService.toggleFollow(widget.event.id);
      if (!resp.success && mounted) {
        setState(() {
          _isFollowed = wasFollowed;
          _followCount = oldCount;
        });
      } else if (resp.success && resp.data != null) {
        // 以服务端返回的真实关注数为准
        final serverCount = resp.data!['followCount'];
        if (serverCount is int && mounted) {
          setState(() => _followCount = serverCount);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isFollowed = wasFollowed;
          _followCount = oldCount;
        });
      }
    } finally {
      _isToggling = false;
    }
  }

  ComicEvent get _event => widget.event;

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
      _event.images.isNotEmpty ||
      (_event.coverImage != null && _event.coverImage!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ComicDetailPage(eventId: _event.id),
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
          if (_event.tags.isNotEmpty) ...[
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
          Padding(
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
          backgroundImage:
              _event.creatorAvatar != null && _event.creatorAvatar!.isNotEmpty
                  ? NetworkImage(_fullUrl(_event.creatorAvatar!))
                  : null,
          child: _event.creatorAvatar == null || _event.creatorAvatar!.isEmpty
              ? Text(
                  (_event.name.isNotEmpty ? _event.name[0] : '?').toUpperCase(),
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
                  _event.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // 状态标签：用本地实时计算的状态，避免服务端遗漏重算导致
              // 已结束的漫展显示为"即将开始"。
              if (widget.showOwnerBadge)
                _buildBadge('我发布的', AppColors.primary)
              else
                _buildBadge(_event.effectiveStatusText,
                    _statusColor(_event.effectiveStatus)),
              const SizedBox(width: 8),
              // 关注人数
              Text(
                '${_formatCount(_followCount)}人关注',
                style: TextStyle(
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
    final urls = _event.images.isNotEmpty
        ? _event.images.map((img) => _fullUrl(img.imageUrl)).toList()
        : [_fullUrl(_event.coverImage!)];

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
                child:
                    Icon(Icons.image, color: AppColors.textTertiary, size: 40),
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
                    child: Icon(Icons.image,
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
    if (_event.cityName.isNotEmpty) locationParts.add(_event.cityName);
    if (_event.venue.isNotEmpty) locationParts.add(_event.venue);
    final location = locationParts.join(' · ');

    final dateRange =
        AppDateUtils.formatDateRange(_event.startDate, _event.endDate);

    return Row(
      children: [
        if (location.isNotEmpty) ...[
          Icon(Icons.location_on_outlined,
              size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
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
          Icon(Icons.calendar_today, size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              dateRange,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        // 票价信息
        if (_event.ticketInfo != null && _event.ticketInfo!.isNotEmpty) ...[
          const SizedBox(width: 12),
          Icon(Icons.confirmation_number_outlined,
              size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              _event.ticketInfo!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
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
      children: _event.tags.map((tag) {
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
    // 自己发布的漫展不显示关注按钮
    if (_event.isOwner) return const SizedBox.shrink();
    return Row(
      children: [
        const Spacer(),
        GestureDetector(
          onTap: _handleToggleFollow,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _isFollowed ? Colors.transparent : AppColors.textPrimary,
              borderRadius: BorderRadius.circular(20),
              border: _isFollowed
                  ? Border.all(color: AppColors.borderDivider, width: 1.2)
                  : null,
            ),
            child: Text(
              _isFollowed ? '正在关注' : '关注',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _isFollowed ? AppColors.textPrimary : AppColors.background,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
