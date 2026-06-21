import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/comic_event.dart';
import 'package:nonto/widgets/comic_event_card.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/comic_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
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
      // 走缓存层（page=1），后续刷新即时展示
      final result = await DataLayer().query(
        CacheKeys.comicEvents(),
        () async {
          final params = <String, dynamic>{'page': '1', 'size': '10'};
          if (_currentCity.isNotEmpty && _currentCity != '全部') {
            params['city'] = _currentCity;
          }
          final resp = await ApiClient().get<Map<String, dynamic>>(
            '/comic/events',
            params: params,
          );
          if (resp.success && resp.data != null) return resp.data;
          return null;
        },
      );
      if (result.data != null && mounted) {
        final page =
            ComicEventsPage.fromJson(result.data as Map<String, dynamic>);
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
                            return ComicEventCard(
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
              child:
                  const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
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
      '全部',
      '南宁',
      '桂林',
      '柳州',
      '北海',
      '梧州',
      '玉林',
      '贵港',
      '钦州',
      '防城港',
      '百色',
      '河池',
      '贺州',
      '来宾',
      '崇左',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    city,
                    style: TextStyle(
                      color:
                          isSelected ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
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
}
