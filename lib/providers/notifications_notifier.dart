import 'dart:async';
import 'dart:convert';

import 'package:facebook_clone/models/notification.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import 'package:facebook_clone/services/data_layer.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationsState {
  final List<AppNotification> notifications;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final bool isInitialLoading;
  final String? error;

  const NotificationsState({
    this.notifications = const [],
    this.page = 1,
    this.hasMore = true,
    this.isLoading = false,
    this.isInitialLoading = true,
    this.error,
  });

  NotificationsState copyWith({
    List<AppNotification>? notifications,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isInitialLoading,
    String? error,
    bool clearError = false,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  final NotificationService _service = NotificationService();
  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _wsSub;
  StreamSubscription? _dataSub;

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
    if (state.notifications.isNotEmpty) return;
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
          isLoading: false,
          isInitialLoading: false,
        );
      }
    } catch (_) {}
  }

  void _onWsNotification(Map<String, dynamic> data) {
    final event = data['event'] as String?;
    final notification = data['notification'] as Map<String, dynamic>?;
    if (event == 'new_notification' && notification != null) {
      final appNotif = AppNotification.fromJson(notification);
      state = state.copyWith(
        notifications: [appNotif, ...state.notifications],
      );
    }
  }

  Future<void> loadNotifications({bool refresh = false}) async {
    if (refresh) {
      state = state.copyWith(page: 1, hasMore: true);
    }

    if (!state.hasMore && !refresh) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cacheKey = 'notif:list:${state.page}';
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
        final hasMore = list.length >= 20;
        state = state.copyWith(
          notifications: refresh ? list : [...state.notifications, ...list],
          page: state.page + 1,
          hasMore: hasMore,
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
    await _service.markRead(notificationId);
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
