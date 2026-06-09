import 'api_client.dart';

class NotificationService {
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;
  NotificationService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> getNotifications({int page = 1, int perPage = 20}) =>
      _api.getDeduped('/notifications/', params: {'page': page, 'per_page': perPage});
  Future<ApiResponse> markRead(int id) => _api.post('/notifications/$id/read');
  Future<ApiResponse> markAllRead() => _api.post('/notifications/mark-all-read');
  Future<ApiResponse> deleteNotification(int id) => _api.delete('/notifications/$id');
  Future<ApiResponse> clearAll() => _api.delete('/notifications/clear-all');
  Future<ApiResponse> getUnreadCount() => _api.getDeduped('/notifications/unread-count');
  Future<ApiResponse> getSettings() => _api.getDeduped('/notifications/settings');
  Future<ApiResponse> updateSettings(Map<String, dynamic> data) =>
      _api.put('/notifications/settings', data: data);
}
