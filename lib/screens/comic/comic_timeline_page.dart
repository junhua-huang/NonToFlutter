import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/comic_event.dart';
import 'package:facebook_clone/screens/comic/comic_detail_page.dart';
import 'package:facebook_clone/services/comic_service.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:flutter/material.dart';

class ComicTimelinePage extends StatefulWidget {
  const ComicTimelinePage({super.key});

  @override
  State<ComicTimelinePage> createState() => _ComicTimelinePageState();
}

class _ComicTimelinePageState extends State<ComicTimelinePage> {
  final ComicService _service = ComicService();

  List<ComicEvent> _events = [];
  String _currentCity = '全部';
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadEvents();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
    setState(() {
      _showBackToTop = _scrollController.offset > 800;
    });
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });

    try {
      final resp = await _service.getEvents(
        city: _currentCity,
        page: 1,
        size: 10,
      );
      if (resp.success && resp.data != null && mounted) {
        final page = resp.data!;
        setState(() {
          _events = page.records;
          _hasMore = page.page < page.pages;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final resp = await _service.getEvents(
        city: _currentCity,
        page: _currentPage + 1,
        size: 10,
      );
      if (resp.success && resp.data != null && mounted) {
        final page = resp.data!;
        setState(() {
          _events.addAll(page.records);
          _currentPage = page.page;
          _hasMore = page.page < page.pages;
          _isLoadingMore = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingMore = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadEvents();
  }

  void _onCityChanged(String city) {
    if (city == _currentCity) return;
    setState(() {
      _currentCity = city;
    });
    _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          '漫展时间线',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: AppColors.textPrimary, size: 26),
            onPressed: () async {
              await Navigator.pushNamed(context, '/comic/upload');
              _onRefresh();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildCityFilter(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _events.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        color: AppColors.primary,
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 80),
                          itemCount: _events.length + 1,
                          itemBuilder: (context, index) {
                            if (index >= _events.length) {
                              return _buildLoadMoreIndicator();
                            }
                            return _ComicEventCard(
                              event: _events[index],
                              onToggleFollow: () async {
                                await _toggleFollow(index);
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.small(
              backgroundColor: AppColors.primary,
              elevation: 4,
              child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
              onPressed: () {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                );
              },
            )
          : null,
    );
  }

  Widget _buildCityFilter() {
    const cities = [
      '全部', '南宁', '桂林', '柳州', '北海', '梧州',
      '玉林', '贵港', '钦州', '防城港', '百色',
      '河池', '贺州', '来宾', '崇左',
    ];

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: cities.map((city) {
            final isSelected = city == _currentCity;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _onCityChanged(city),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    city,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }
    if (!_hasMore && _events.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            '— 已经到底了 —',
            style: TextStyle(
              color: AppColors.textTertiary.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildEmptyState() {
    return EmptyStateWidget(
      icon: Icons.event_busy,
      title: _currentCity == '全部' ? '暂无漫展信息' : '该城市暂无漫展',
      subtitle: _currentCity != '全部' ? '试试查看其他城市' : null,
    );
  }

  Future<void> _toggleFollow(int index) async {
    final event = _events[index];
    final wasFollowed = event.isFollowed;
    setState(() {
      _events[index] = event.copyWith(
        isFollowed: !wasFollowed,
        followCount: wasFollowed ? event.followCount - 1 : event.followCount + 1,
      );
    });
    try {
      final resp = await _service.toggleFollow(event.id);
      if (!resp.success && mounted) {
        setState(() {
          _events[index] = event;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _events[index] = event;
        });
      }
    }
  }
}

/// 漫展卡片 — 推特风格
class _ComicEventCard extends StatelessWidget {
  final ComicEvent event;
  final VoidCallback onToggleFollow;

  const _ComicEventCard({
    required this.event,
    required this.onToggleFollow,
  });

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

  String _formatDateRange() {
    final s = event.startDate;
    final e = event.endDate;
    if (s != null && e != null && s != e) {
      try {
        final sd = DateTime.parse(s);
        final ed = DateTime.parse(e);
        return '${sd.month}月${sd.day}日 - ${ed.month}月${ed.day}日';
      } catch (_) {}
    }
    if (s != null) {
      try {
        final sd = DateTime.parse(s);
        return '${sd.month}月${sd.day}日';
      } catch (_) {}
    }
    return '';
  }

  String _fullUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
  }

  String _formatTimeAgo() {
    if (event.createdAt == null) return '';
    try {
      final dt = DateTime.parse(event.createdAt!);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}月${dt.day}日';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
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
              // 封面图 16:9（圆角顶部）
              if (event.coverImage != null && event.coverImage!.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      _fullUrl(event.coverImage!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.backgroundSecondary,
                        child: const Center(
                          child: Icon(Icons.image, color: AppColors.textTertiary, size: 36),
                        ),
                      ),
                    ),
                  ),
                ),

              // 头部：发布者头像 + 用户名 + 时间 + 状态 Badge
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary,
                      backgroundImage: event.creatorAvatar != null &&
                              event.creatorAvatar!.isNotEmpty
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
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTimeAgo(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              ),

              // 内容区
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          event.cityName.isNotEmpty ? event.cityName : '未知城市',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.calendar_today,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateRange(),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    if (event.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: event.tags.take(4).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),

              // 互动栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    _XAction(
                      icon: event.isFollowed ? Icons.favorite : Icons.favorite_border,
                      count: event.followCount,
                      color: event.isFollowed ? AppColors.likeRed : null,
                      onTap: onToggleFollow,
                    ),
                    const SizedBox(width: 16),
                    _XAction(
                      icon: Icons.chat_bubble_outline,
                      count: 0,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ComicDetailPage(eventId: event.id),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    _XAction(
                      icon: Icons.share_outlined,
                      count: 0,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 互动按钮（对齐 feed_tab 中的 _XAction）
class _XAction extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const _XAction({
    required this.icon,
    this.count = 0,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}K' : '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: color ?? AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}