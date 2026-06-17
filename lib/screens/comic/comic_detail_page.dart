import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/comic_event.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/screens/comic/comic_upload_page.dart';
import 'package:nonto/screens/post/image_viewer_screen.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/comic_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/widgets/comment_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ComicDetailPage extends StatefulWidget {
  final int eventId;
  const ComicDetailPage({super.key, required this.eventId});

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  final ComicService _service = ComicService();
  final ScrollController _scrollController = ScrollController();

  ComicEvent? _event;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // 走缓存层，再次进入同一漫展即时展示
      final result = await DataLayer().query(
        CacheKeys.comicDetail(widget.eventId),
        () async {
          final resp = await ApiClient().get<Map<String, dynamic>>(
            '/comic/events/${widget.eventId}',
          );
          if (resp.success && resp.data != null) return resp.data;
          return null;
        },
      );
      if (result.data != null && mounted) {
        setState(() {
          _event = ComicEvent.fromDetailJson(result.data as Map<String, dynamic>);
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() { _error = '加载失败'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '网络错误，请稍后重试';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_event == null) return;
    final wasFollowed = _event!.isFollowed;
    setState(() {
      _event = _event!.copyWith(
        isFollowed: !wasFollowed,
        followCount: wasFollowed ? _event!.followCount - 1 : _event!.followCount + 1,
      );
    });
    try {
      final resp = await _service.toggleFollow(_event!.id);
      if (!resp.success && mounted) {
        setState(() {
          _event = _event!.copyWith(
            isFollowed: wasFollowed,
            followCount: wasFollowed ? _event!.followCount + 1 : _event!.followCount - 1,
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _event = _event!.copyWith(
            isFollowed: wasFollowed,
            followCount: wasFollowed ? _event!.followCount + 1 : _event!.followCount - 1,
          );
        });
      }
    }
  }

  String _fullUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
  }

  String _formatTimeAgo() {
    if (_event?.createdAt == null) return '';
    return AppDateUtils.formatTimeAgo(
      AppDateUtils.parseBeijingTime(_event!.createdAt),
    );
  }

  String _formatDateRange() {
    return AppDateUtils.formatDateRange(_event?.startDate, _event?.endDate);
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '漫展详情',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
        actions: _event != null && _event!.isOwner
            ? [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ComicUploadPage(eventId: _event!.id),
                      ),
                    );
                    _loadDetail();
                  },
                ),
              ]
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadDetail, child: const Text('重试')),
                    ],
                  ),
                )
              : _event == null
                  ? const Center(child: Text('漫展不存在'))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    final event = _event!;
    final hasCover = event.coverImage != null && event.coverImage!.isNotEmpty;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 封面图 + 发布者行 + 内容区 + 图片列表 —— 整体作为一个 sliver
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部大图全宽
              if (hasCover)
                Image.network(
                  _fullUrl(event.coverImage!),
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (_, __, ___) => AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: AppColors.backgroundSecondary,
                      child: const Icon(Icons.event, size: 48, color: AppColors.textTertiary),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  height: 200,
                  color: AppColors.backgroundSecondary,
                  child: const Icon(Icons.event, size: 48, color: AppColors.textTertiary),
                ),

              // 发布者行（头像 + 用户名 + 时间 + 关注按钮）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary,
                      backgroundImage: event.creatorAvatar != null && event.creatorAvatar!.isNotEmpty
                          ? NetworkImage(_fullUrl(event.creatorAvatar!))
                          : null,
                      child: event.creatorAvatar == null || event.creatorAvatar!.isEmpty
                          ? Text(
                              (event.creatorName ?? '?').substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.creatorName ?? '匿名用户',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTimeAgo(),
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (!event.isOwner)
                      GestureDetector(
                        onTap: _toggleFollow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: event.isFollowed ? Colors.transparent : AppColors.textPrimary,
                            borderRadius: BorderRadius.circular(20),
                            border: event.isFollowed
                                ? Border.all(color: AppColors.borderDivider)
                                : null,
                          ),
                          child: Text(
                            event.isFollowed ? '正在关注' : '关注',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: event.isFollowed ? AppColors.textPrimary : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.borderLight),

              // 内容区
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题 + 状态
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor(event.status).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            event.statusText,
                            style: TextStyle(
                              color: _statusColor(event.status),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 城市
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          event.cityName.isNotEmpty ? event.cityName : '未知城市',
                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 日期
                    if (event.startDate != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 15, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            _formatDateRange(),
                            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],

                    // 场馆
                    if (event.venue.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 15, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.venue,
                              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],

                    // 标签
                    if (event.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: event.tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // 介绍
                    if (event.intro != null && event.intro!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: AppColors.borderLight),
                      const SizedBox(height: 16),
                      const Text(
                        '漫展介绍',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        event.intro!,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 漫展图片列表（竖列排列）
              if (event.images.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: AppColors.borderLight),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '漫展图片',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(event.images.length, (i) {
                  final url = _fullUrl(event.images[i].imageUrl);
                  return GestureDetector(
                    onTap: () {
                      ImageViewerScreen.show(
                        context,
                        event.images.map((img) => _fullUrl(img.imageUrl)).toList(),
                        initialIndex: i,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 200,
                            color: AppColors.backgroundSecondary,
                            child: const Icon(Icons.broken_image, color: AppColors.textTertiary),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 8),
              const Divider(height: 1, color: AppColors.borderLight),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // 评论区 —— SliverFillRemaining 提供有界高度，CommentSection 的 Expanded 正常工作
        SliverFillRemaining(
          hasScrollBody: true,
          child: CommentSection(
            targetType: 'comic',
            targetId: event.id,
            scrollController: _scrollController,
          ),
        ),
      ],
    );
  }
}