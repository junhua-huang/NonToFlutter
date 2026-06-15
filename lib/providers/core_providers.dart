import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/local_db_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_notifiers.dart';
import 'notifications_notifier.dart';

/// Singleton service providers — thin wrappers around existing factory singletons.
/// These are Regular providers (not autoDispose) because the singleton lifecycle
/// is managed by the services themselves.

final dataLayerProvider = Provider<DataLayer>((ref) => DataLayer());

final webSocketProvider = Provider<WebSocketService>((ref) => WebSocketService());

final localDbServiceProvider = Provider<LocalDbService>((ref) => LocalDbService());

/// Current active tab index in HomeScreen (0-3).
/// Migrated from setState to Riverpod to avoid full widget tree rebuild on tab switch.
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

/// Bottom bar / AppBar visibility state.
/// Tabs toggle this via ref.read(barVisibleProvider.notifier).state = false/true
/// when scrolling, replacing the old HomeScreen.barVisible ValueNotifier.
final barVisibleProvider = StateProvider<bool>((ref) => true);

/// Derived: total unread notification count across all notifications.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final state = ref.watch(notificationsProvider);
  return state.notifications.where((n) => !n.isRead).length;
});

/// Derived: total unread message count across all conversations.
final unreadMessagesCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsProvider).conversations;
  return conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
});
