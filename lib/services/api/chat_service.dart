import 'api_client.dart';
import 'package:facebook_clone/services/sound_service.dart';

class ChatService {
  static final ChatService _i = ChatService._();
  factory ChatService() => _i;
  ChatService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> getConversations() => _api.get('/chat/conversations');
  Future<ApiResponse> getOrCreateConversation(int userId) => _api.get('/chat/conversations/$userId');
  Future<ApiResponse> getMessages(int convId, {int page = 1, int perPage = 50}) =>
      _api.get('/chat/conversations/$convId/messages', params: {'page': page, 'per_page': perPage});
  Future<ApiResponse> markRead(int convId) => _api.post('/chat/conversations/$convId/mark-read');
  Future<ApiResponse> getOnlineUsers() => _api.get('/chat/users/online');
  Future<ApiResponse> getUserStatus(int userId) => _api.get('/chat/users/$userId/status');
  Future<ApiResponse> getUnreadCount() => _api.get('/chat/unread-count');

  /// Send a message via HTTP (fallback when WebSocket is not available)
  Future<ApiResponse> sendMessage(int convId, String content, {String messageType = 'text'}) async {
    final resp = await _api.post('/chat/conversations/$convId/messages', data: {
      'content': content,
      'message_type': messageType,
    });
    if (resp.success) {
      SoundService().playSendSound();
    }
    return resp;
  }
}
