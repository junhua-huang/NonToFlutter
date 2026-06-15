import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/comic_event.dart';
import 'package:nonto/widgets/comic_event_card.dart';
import 'package:nonto/screens/comic/comic_detail_page.dart';
import 'package:nonto/services/comic_service.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
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
          return ComicEventCard(
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