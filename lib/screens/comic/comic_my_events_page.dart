import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/comic_event.dart';
import 'package:facebook_clone/screens/comic/comic_detail_page.dart';
import 'package:facebook_clone/services/comic_service.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:flutter/material.dart';

/// 「我的漫展」页面 — 我发布的 / 我关注的 两个 Tab
class ComicMyEventsPage extends StatefulWidget {
  const ComicMyEventsPage({super.key});

  @override
  State<ComicMyEventsPage> createState() => _ComicMyEventsPageState();
}

class _ComicMyEventsPageState extends State<ComicMyEventsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          '我的漫展',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Column(
            children: [
              Container(height: 0.5, color: AppColors.borderLight),
              TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: '我发布的'),
                  Tab(text: '我关注的'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ComicTabList(fetchMode: _FetchMode.myEvents),
          _ComicTabList(fetchMode: _FetchMode.myFollowed),
        ],
      ),
    );
  }
}

enum _FetchMode { myEvents, myFollowed }

/// 单个 Tab 的漫展列表
class _ComicTabList extends StatefulWidget {
  final _FetchMode fetchMode;
  const _ComicTabList({required this.fetchMode});

  @override
  State<_ComicTabList> createState() => _ComicTabListState();
}

class _ComicTabListState extends State<_ComicTabList> {
  final ComicService _service = ComicService();
  final ScrollController _scrollController = ScrollController();

  List<ComicEvent> _events = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
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
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 1;
    });
    try {
      final resp = widget.fetchMode == _FetchMode.myEvents
          ? await _service.getMyEvents(page: 1)
          : await _service.getMyFollowed(page: 1);
      if (resp.success && resp.data != null && mounted) {
        final page = resp.data!;
        setState(() {
          _events = page.records;
          _hasMore = page.page < page.pages;
          _isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _error = resp.message ?? '加载失败';
            _isLoading = false;
          });
        }
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

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final resp = widget.fetchMode == _FetchMode.myEvents
          ? await _service.getMyEvents(page: nextPage)
          : await _service.getMyFollowed(page: nextPage);
      if (resp.success && resp.data != null && mounted) {
        final page = resp.data!;
        setState(() {
          _events.addAll(page.records);
          _currentPage = page.page;
          _hasMore = page.page < page.pages;
          _isLoadingMore = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _hasMore = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  Future<void> _toggleFollow(int index) async {
    final event = _events[index];
    final wasFollowed = event.isFollowed;
    setState(() {
      _events[index] = event.copyWith(
        isFollowed: !wasFollowed,
        followCount:
            wasFollowed ? event.followCount - 1 : event.followCount + 1,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_events.isEmpty) {
      return widget.fetchMode == _FetchMode.myEvents
          ? const EmptyStateWidget(
              icon: Icons.event_busy_rounded,
              title: '暂无发布的漫展',
              subtitle: '去发布一个漫展吧',
            )
          : const EmptyStateWidget(
              icon: Icons.bookmark_border,
              title: '暂无关注的漫展',
              subtitle: '去漫展时间线发现感兴趣的漫展',
            );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: _events.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (ctx, index) {
          if (index >= _events.length) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            );
          }
          final event = _events[index];
          return _ComicEventCard(
            event: event,
            showOwnerBadge: widget.fetchMode == _FetchMode.myEvents,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComicDetailPage(eventId: event.id),
                ),
              );
              _loadData();
            },
            onToggleFollow: widget.fetchMode == _FetchMode.myFollowed
                ? () => _toggleFollow(index)
                : null,
          );
        },
      ),
    );
  }
}

/// 漫展卡片 — 推特风格（对齐 comic_timeline_page 的 _ComicEventCard）
class _ComicEventCard extends StatelessWidget {
  final ComicEvent event;
  final bool showOwnerBadge;
  final VoidCallback onTap;
  final VoidCallback? onToggleFollow;

  const _ComicEventCard({
    required this.event,
    required this.showOwnerBadge,
    required this.onTap,
    this.onToggleFollow,
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
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面图 16:9（圆角顶部）
              if (event.coverImage != null && event.coverImage!.isNotEmpty)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      _fullUrl(event.coverImage!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.backgroundSecondary,
                        child: const Center(
                          child: Icon(Icons.image,
                              color: AppColors.textTertiary, size: 36),
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
                      child: event.creatorAvatar == null ||
                              event.creatorAvatar!.isEmpty
                          ? Text(
                              (event.creatorName ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
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
                    if (showOwnerBadge)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '我发布的',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(event.status)
                              .withValues(alpha: 0.12),
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
                          event.cityName.isNotEmpty ? event.cityName : '未知',
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.1),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    if (showOwnerBadge)
                      _XAction(
                        icon: Icons.favorite_border,
                        count: event.followCount,
                        onTap: null,
                      )
                    else
                      _XAction(
                        icon: event.isFollowed
                            ? Icons.favorite
                            : Icons.favorite_border,
                        count: event.followCount,
                        color: event.isFollowed ? AppColors.likeRed : null,
                        onTap: onToggleFollow,
                      ),
                    const SizedBox(width: 16),
                    _XAction(
                      icon: Icons.chat_bubble_outline,
                      count: 0,
                      onTap: onTap,
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

/// 互动按钮（对齐 comic_timeline_page 的 _XAction）
class _XAction extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback? onTap;

  const _XAction({
    required this.icon,
    this.count = 0,
    this.color,
    this.onTap,
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
                count >= 1000
                    ? '${(count / 1000).toStringAsFixed(1)}K'
                    : '$count',
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