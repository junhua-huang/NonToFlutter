import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/screens/profile/user_profile_screen.dart';
import 'package:facebook_clone/services/api/friend_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FriendService _friendService = FriendService();

  List<_RequestItem> _sentRequests = [];
  List<_RequestItem> _receivedRequests = [];
  bool _isLoadingSent = true;
  bool _isLoadingReceived = true;
  String? _sentError;
  String? _receivedError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSent(), _loadReceived()]);
  }

  Future<void> _loadSent() async {
    try {
      final resp = await _friendService.getSentRequests();
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['requests'] as List? ?? [])
            .map((e) => _RequestItem.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _sentRequests = list;
          _isLoadingSent = false;
          _sentError = null;
        });
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
        final data = resp.data as Map<String, dynamic>;
        final list = (data['requests'] as List? ?? [])
            .map((e) => _RequestItem.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _receivedRequests = list;
          _isLoadingReceived = false;
          _receivedError = null;
        });
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

  Future<void> _accept(int requestId) async {
    try {
      final resp = await _friendService.acceptRequest(requestId);
      if (resp.success) {
        setState(() {
          _receivedRequests.removeWhere((r) => r.id == requestId);
        });
      }
    } catch (_) {}
  }

  Future<void> _reject(int requestId) async {
    try {
      final resp = await _friendService.rejectRequest(requestId);
      if (resp.success) {
        setState(() {
          _receivedRequests.removeWhere((r) => r.id == requestId);
        });
      }
    } catch (_) {}
  }

  Future<void> _cancel(int requestId) async {
    try {
      final resp = await _friendService.cancelRequest(requestId);
      if (resp.success) {
        setState(() {
          _sentRequests.removeWhere((r) => r.id == requestId);
        });
      }
    } catch (_) {}
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReceivedTab(),
          _buildSentTab(),
        ],
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
              onTap: () => _reject(item.id),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: '接受',
              color: AppColors.primary,
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
            GestureDetector(
              onTap: () => _cancel(item.id),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.borderLight, width: 1),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '取消',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color, width: 1.2),
        ),
        alignment: Alignment.center,
        child: Text(
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
          ? User.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}
