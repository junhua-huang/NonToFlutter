import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/services/api/friend_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FriendService _friendService = FriendService();
  final RefreshController _refreshController = RefreshController();

  List<_RequestItem> _sentRequests = [];
  List<_RequestItem> _receivedRequests = [];
  bool _isLoadingSent = true;
  bool _isLoadingReceived = true;
  String? _sentError;
  String? _receivedError;
  // 正在处理中的请求 id 集合，用于按钮 loading 态，防止重复点击
  final Set<int> _pendingRequestIds = {};

  static const _cacheKeySent = 'friends:requests:sent';
  static const _cacheKeyReceived = 'friends:requests:received';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCached();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  /// 先从缓存加载，再请求网络
  Future<void> _loadCached() async {
    final sentCached = await DataLayer().query(_cacheKeySent, () async => null);
    if (sentCached.data is List && (sentCached.data as List).isNotEmpty) {
      final list = (sentCached.data as List)
          .map((e) => _RequestItem.fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}))
          .toList();
      if (mounted) setState(() { _sentRequests = list; _isLoadingSent = false; });
    }
    final recvCached = await DataLayer().query(_cacheKeyReceived, () async => null);
    if (recvCached.data is List && (recvCached.data as List).isNotEmpty) {
      final list = (recvCached.data as List)
          .map((e) => _RequestItem.fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}))
          .toList();
      if (mounted) setState(() { _receivedRequests = list; _isLoadingReceived = false; });
    }
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSent(), _loadReceived()]);
  }

  Future<void> _loadSent() async {
    try {
      final resp = await _friendService.getSentRequests();
      if (resp.success && resp.data != null) {
        final dynamic rawData = resp.data;
        final data = rawData is Map ? rawData as Map<String, dynamic> : <String, dynamic>{};
        final dynamic rawList = data['requests'];
        final list = (rawList is List ? rawList : const <dynamic>[])
            .map((e) => _RequestItem.fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}))
            .toList();
        setState(() {
          _sentRequests = list;
          _isLoadingSent = false;
          _sentError = null;
        });
        // 写入持久层缓存
        if (rawList is List) {
          DataLayer().write(_cacheKeySent, rawList, ttlSeconds: 300);
        }
      } else {
        setState(() {
          _sentError = resp.message ?? '加载失败';
          _isLoadingSent = false;
        });
      }
    } catch (e) {
      setState(() {
        _sentError = '网络错误';
        _isLoadingSent = false;
      });
    }
  }

  Future<void> _loadReceived() async {
    try {
      final resp = await _friendService.getReceivedRequests();
      if (resp.success && resp.data != null) {
        final dynamic rawData = resp.data;
        final data = rawData is Map ? rawData as Map<String, dynamic> : <String, dynamic>{};
        final dynamic rawList = data['requests'];
        final list = (rawList is List ? rawList : const <dynamic>[])
            .map((e) => _RequestItem.fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}))
            .toList();
        setState(() {
          _receivedRequests = list;
          _isLoadingReceived = false;
          _receivedError = null;
        });
        // 写入持久层缓存
        if (rawList is List) {
          DataLayer().write(_cacheKeyReceived, rawList, ttlSeconds: 300);
        }
      } else {
        setState(() {
          _receivedError = resp.message ?? '加载失败';
          _isLoadingReceived = false;
        });
      }
    } catch (e) {
      setState(() {
        _receivedError = '网络错误';
        _isLoadingReceived = false;
      });
    }
  }

  void _showSnackBar(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Colors.red.shade400 : AppColors.primary,
    ));
  }

  Future<void> _accept(int requestId) async {
    if (_pendingRequestIds.contains(requestId)) return;
    setState(() => _pendingRequestIds.add(requestId));
    try {
      final resp = await _friendService.acceptRequest(requestId);
      if (resp.success && mounted) {
        final accepted = _receivedRequests.firstWhere(
          (r) => r.id == requestId,
          orElse: () => _RequestItem(
              id: requestId, senderId: 0, receiverId: 0, status: ''),
        );
        final name = accepted.user?.displayName ??
            accepted.user?.username ??
            '对方';
        setState(() {
          _receivedRequests.removeWhere((r) => r.id == requestId);
          _pendingRequestIds.remove(requestId);
        });
        DataLayer().invalidate(_cacheKeyReceived);
        // 清除通知列表中的好友请求通知
        try {
          ProviderScope.containerOf(context)
              .read(notificationsProvider.notifier)
              .removeByType('friend_request');
        } catch (_) {}
        // 主动刷新会话列表，让发起方（点接受的人）本地立即出现新会话 + Hi 消息，
        // 不依赖 WS 推送（WS 推送给对方，发起方靠这里刷新）。
        try {
          ProviderScope.containerOf(context)
              .read(conversationsProvider.notifier)
              .loadConversations();
        } catch (_) {}
        _showSnackBar('已添加 $name 为好友');
      } else {
        setState(() => _pendingRequestIds.remove(requestId));
        _showSnackBar(resp.message ?? '操作失败，请重试', error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pendingRequestIds.remove(requestId));
        _showSnackBar('网络错误，请重试', error: true);
      }
    }
  }

  Future<void> _reject(int requestId) async {
    if (_pendingRequestIds.contains(requestId)) return;
    setState(() => _pendingRequestIds.add(requestId));
    try {
      final resp = await _friendService.rejectRequest(requestId);
      if (resp.success && mounted) {
        setState(() {
          _receivedRequests.removeWhere((r) => r.id == requestId);
          _pendingRequestIds.remove(requestId);
        });
        DataLayer().invalidate(_cacheKeyReceived);
        try {
          ProviderScope.containerOf(context)
              .read(notificationsProvider.notifier)
              .removeByType('friend_request');
        } catch (_) {}
        _showSnackBar('已拒绝');
      } else {
        setState(() => _pendingRequestIds.remove(requestId));
        _showSnackBar(resp.message ?? '操作失败，请重试', error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pendingRequestIds.remove(requestId));
        _showSnackBar('网络错误，请重试', error: true);
      }
    }
  }

  Future<void> _cancel(int requestId) async {
    if (_pendingRequestIds.contains(requestId)) return;
    setState(() => _pendingRequestIds.add(requestId));
    try {
      final resp = await _friendService.cancelRequest(requestId);
      if (resp.success && mounted) {
        setState(() {
          _sentRequests.removeWhere((r) => r.id == requestId);
          _pendingRequestIds.remove(requestId);
        });
        DataLayer().invalidate(_cacheKeySent);
        _showSnackBar('已取消');
      } else {
        setState(() => _pendingRequestIds.remove(requestId));
        _showSnackBar(resp.message ?? '操作失败，请重试', error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pendingRequestIds.remove(requestId));
        _showSnackBar('网络错误，请重试', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '好友申请',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            unselectedLabelStyle: const TextStyle(fontSize: 15),
            tabs: const [
              Tab(text: '向我请求的'),
              Tab(text: '我发起的'),
            ],
          ),
        ),
      ),
      body: SmartRefresher(
        controller: _refreshController,
        onRefresh: () async {
          await _loadAll();
          _refreshController.refreshCompleted();
        },
        header: const WaterDropHeader(
          complete:
              Text('刷新成功', style: TextStyle(color: AppColors.primary)),
          waterDropColor: AppColors.primary,
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildReceivedTab(),
            _buildSentTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedTab() {
    if (_isLoadingReceived) return const FriendSkeleton();
    if (_receivedError != null) {
      return ErrorStateWidget(
        message: _receivedError!,
        onRetry: () {
          setState(() => _isLoadingReceived = true);
          _loadReceived();
        },
      );
    }
    if (_receivedRequests.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.person_add_disabled,
        title: '暂无待处理的好友申请',
        subtitle: '当有人向你发送好友申请时会出现在这里',
      );
    }
    return ListView.separated(
      itemCount: _receivedRequests.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76, color: AppColors.borderLight),
      itemBuilder: (_, i) => _buildReceivedTile(_receivedRequests[i]),
    );
  }

  Widget _buildSentTab() {
    if (_isLoadingSent) return const FriendSkeleton();
    if (_sentError != null) {
      return ErrorStateWidget(
        message: _sentError!,
        onRetry: () {
          setState(() => _isLoadingSent = true);
          _loadSent();
        },
      );
    }
    if (_sentRequests.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.send_outlined,
        title: '暂无发出的好友申请',
        subtitle: '你发出的好友申请会显示在这里',
      );
    }
    return ListView.separated(
      itemCount: _sentRequests.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76, color: AppColors.borderLight),
      itemBuilder: (_, i) => _buildSentTile(_sentRequests[i]),
    );
  }

  Widget _buildReceivedTile(_RequestItem item) {
    final user = item.user;
    final isPending = _pendingRequestIds.contains(item.id);
    return InkWell(
      onTap: isPending
          ? null
          : () {
              if (user != null) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)));
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ImageUtils.buildAvatar(user, radius: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? user?.username ?? '未知用户',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user?.username ?? 'unknown'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (item.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      AppDateUtils.formatTimeAgo(item.createdAt!),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: '拒绝',
              color: AppColors.textSecondary,
              loading: isPending,
              onTap: () => _reject(item.id),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: '接受',
              color: AppColors.primary,
              loading: isPending,
              onTap: () => _accept(item.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentTile(_RequestItem item) {
    final user = item.user;
    return InkWell(
      onTap: () {
        if (user != null) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ImageUtils.buildAvatar(user, radius: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? user?.username ?? '未知用户',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user?.username ?? 'unknown'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (item.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${AppDateUtils.formatTimeAgo(item.createdAt!)} · 等待对方确认',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: '取消',
              color: AppColors.textSecondary,
              loading: _pendingRequestIds.contains(item.id),
              onTap: () => _cancel(item.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color, width: 1.2),
        ),
        alignment: Alignment.center,
        child: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            : Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _RequestItem {
  final int id;
  final int senderId;
  final int receiverId;
  final String status;
  final User? user;
  final DateTime? createdAt;

  _RequestItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    this.user,
    this.createdAt,
  });

  factory _RequestItem.fromJson(Map<String, dynamic> json) {
    return _RequestItem(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      senderId: json['sender_id'] is int
          ? json['sender_id']
          : int.tryParse(json['sender_id'].toString()) ?? 0,
      receiverId: json['receiver_id'] is int
          ? json['receiver_id']
          : int.tryParse(json['receiver_id'].toString()) ?? 0,
      status: json['status'] ?? 'pending',
      user: json['user'] != null
          ? User.fromJson(json['user'] is Map<String, dynamic>
              ? json['user'] as Map<String, dynamic>
              : <String, dynamic>{})
          : null,
      createdAt: json['created_at'] != null
          ? AppDateUtils.parseBeijingTime(json['created_at'].toString())
          : null,
    );
  }
}
