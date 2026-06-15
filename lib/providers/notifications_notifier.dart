import 'dart:async';
import 'dart:convert';

import 'package:nonto/models/notification.dart';
import 'package:nonto/services/api/notification_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationsState {
  final List<AppNotification> notifications;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final bool isInitialLoading;
  final int unreadCount;
  final String? error;

  const NotificationsState({
    this.notifications = const [],
    this.page = 1,
    this.hasMore = true,
    this.isLoading = false,
    this.isInitialLoading = true,
    this.unreadCount = 0,
    this.error,
  });

  NotificationsState copyWith({
    List<AppNotification>? notifications,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isInitialLoading,
    int? unreadCount,
    String? error,
    bool clearError = false,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      unreadCount: unreadCount ?? this.unreadCount,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  final NotificationService _service = NotificationService();
  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _wsSub;
  StreamSubscription? _dataSub;
  bool _loadInProgress = false;

  NotificationsNotifier() : super(const NotificationsState()) {
    _wsSub = _ws.notificationStream.listen(_onWsNotification);
    _loadCached();
    _dataSub = DataLayer().changeStream.listen((key) {
      if (key == '__auth:logout') {
        _reset();
      } else if (key == 'notif:list:1') {
        _loadCached();
      }
    });
  }

  /// 构造时先读缓存，空则等预热推送
  Future<void> _loadCached() async {
    if (!state.isInitialLoading || _loadInProgress) return;
    _loadInProgress = true;
    try {
      final result = await DataLayer()
          .query('notif:list:1', () async => null)
          .timeout(const Duration(seconds: 2));
      if (result.data is List && (result.data as List).isNotEmpty) {
        final list = (result.data as List<dynamic>)
            .map((e) =>
                AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(
          notifications: list,
          hasMore: list.length >= 20,
          unreadCount: list.where((n) => !n.isRead).length,
          isLoading: false,
          isInitialLoading: false,
        );
      }
    } catch (_) {}
    _loadInProgress = false;
  }

  void _onWsNotification(Map<String, dynamic> data) {
    final event = data['event'] is String ? data['event'] as String : null;
    if (event == 'notifications_read') {
      final val = data['unread_count'];
      final count = val is int
          ? val
          : (val is double ? val.toInt() : int.tryParse(val?.toString() ?? '') ?? 0);
      final ids = data['notification_ids'];
      final readIds = ids is List
          ? ids.map((e) => int.tryParse(e.toString())).whereType<int>().toSet()
          : <int>{};
      final updated = readIds.isEmpty
          ? state.notifications.map((n) => n.copyWith(isRead: true)).toList()
          : state.notifications.map((n) => readIds.contains(n.id) ? n.copyWith(isRead: true) : n).toList();
      state = state.copyWith(notifications: updated, unreadCount: count);
      try {
        DataLayer().write('notif:list:1',
          state.notifications.map((n) => n.toJson()).toList(),
          ttlSeconds: 600,
        );
      } catch (_) {}
      return;
    }
    final dynamic rawNotif = data['notification'];
    final notification = rawNotif is Map ? Map<String, dynamic>.from(rawNotif) : null;
    if (event == 'new_notification' && notification != null) {
      final appNotif = AppNotification.fromJson(notification);
      final val = data['unread_count'];
      final unread = val is int
          ? val
          : (val is double ? val.toInt() : int.tryParse(val?.toString() ?? '') ?? state.unreadCount + 1);
      final existing = state.notifications.where((n) => n.id != appNotif.id).toList();
      state = state.copyWith(
        notifications: [appNotif, ...existing],
        unreadCount: unread,
        isInitialLoading: false,
      );
      try {
        DataLayer().write('notif:list:1',
          state.notifications.map((n) => n.toJson()).toList(),
          ttlSeconds: 600,
        );
      } catch (_) {}
    }
  }

  /// 移除所有指定类型的通知（如好友请求被处理后清理）
  void removeByType(String notificationType) {
    state = state.copyWith(
      notifications: state.notifications
          .where((n) => n.notificationType != notificationType)
          .toList(),
    );
  }

  Future<void> loadNotifications({bool refresh = false}) async {
    if (refresh) {
      state = state.copyWith(page: 1, hasMore: true);
    }

    if (!state.hasMore && !refresh) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cacheKey = 'notif:list:${state.page}';
      // 缓存只存列表；翻页字段从原始响应提取
      int? serverUnread;
      bool? serverHasMore;

      final result = await DataLayer()
          .query(
            cacheKey,
            () async {
              final resp = await _service
                  .getNotifications(page: state.page)
                  .timeout(const Duration(seconds: 20));
              if (resp.success && resp.data != null) {
                final data =
                    resp.data is String ? jsonDecode(resp.data) : resp.data;
                serverHasMore = data['has_more'] as bool?;
                serverUnread = data['unread_count'] as int?;
                final list = data['notifications'] as List<dynamic>? ?? [];
                return list;
              }
              return null;
            },
            forceRefresh: refresh,
          )
          .timeout(const Duration(seconds: 25), onTimeout: () {
            return const QueryResult(data: null, source: CacheSource.remote);
          });

      if (result.data != null) {
        final list = (result.data as List<dynamic>)
            .map((e) =>
                AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        final hasMore = serverHasMore ?? list.length >= 20;
        final unreadCount = serverUnread ?? state.unreadCount;
        state = state.copyWith(
          notifications: refresh ? list : [...state.notifications, ...list],
          page: state.page + 1,
          hasMore: hasMore,
          unreadCount: unreadCount,
          isLoading: false,
          isInitialLoading: false,
        );
      } else {
        // null data: network unreachable, timeout, or empty response
        state = state.copyWith(
          isLoading: false,
          isInitialLoading: false,
          hasMore: false,
          error: state.notifications.isEmpty ? '网络请求超时，请下拉重试' : null,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isInitialLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> markAsRead(int notificationId) async {
    final resp = await _service.markRead(notificationId);
    if (resp.success) {
      final updated = state.notifications
          .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
          .toList();
      int unread = updated.where((n) => !n.isRead).length;
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (data is Map && data['unread_count'] != null) {
        final raw = data['unread_count'];
        unread = raw is int ? raw : int.tryParse(raw.toString()) ?? unread;
      }
      state = state.copyWith(notifications: updated, unreadCount: unread);
      try {
        DataLayer().write('notif:list:1',
          state.notifications.map((n) => n.toJson()).toList(),
          ttlSeconds: 600,
        );
      } catch (_) {}
    }
    DataLayer().invalidate('notif:*');
  }

  void _reset() {
    state = const NotificationsState();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _dataSub?.cancel();
    super.dispose();
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>((ref) {
  return NotificationsNotifier();
});
