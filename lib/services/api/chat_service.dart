import 'api_client.dart';
import 'package:nonto/services/sound_service.dart';

class ChatService {
  static final ChatService _i = ChatService._();
  factory ChatService() => _i;
  ChatService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> getConversations({int page = 1, int perPage = 30}) =>
      _api.getDeduped('/chat/sessions', params: {'page': page, 'per_page': perPage});
  Future<ApiResponse> getOrCreateConversation(int userId) => _api.getDeduped('/chat/conversations/$userId');
  Future<ApiResponse> getMessages(int convId, {int page = 1, int perPage = 50}) =>
      _api.getDeduped('/chat/conversations/$convId/messages', params: {'page': page, 'per_page': perPage});

  /// 批量获取多个会话的最新消息（最多 20 个会话）。
  Future<ApiResponse> getBatchMessages(List<int> convIds, {int perPage = 30}){
    String convIdsStr = convIds.join(',');

    return _api.getDeduped('/chat/messages/batch', params: {
      'conv_ids': convIdsStr,
      'per_page': perPage,
    });
  }
  
  /// Incremental sync: fetch messages after a given message ID.
  Future<ApiResponse> getMessagesAfter(int convId, int afterId, {int limit = 50}) =>
      _api.getDeduped('/chat/conversations/$convId/messages', params: {'after_id': afterId, 'limit': limit});
  Future<ApiResponse> markRead(int convId) => _api.post('/chat/conversations/$convId/mark-read');
  Future<ApiResponse> getOnlineUsers() => _api.getDeduped('/chat/users/online');
  Future<ApiResponse> getUserStatus(int userId) => _api.getDeduped('/chat/users/$userId/status');
  Future<ApiResponse> getUnreadCount() => _api.getDeduped('/chat/unread-count');

  /// Send a message via HTTP (fallback when WebSocket is not available)
  Future<ApiResponse> sendMessage(int convId, String content, {
    String messageType = 'text',
    String? mediaUrl,
    int? relatedId,
    String? requestId,
  }) async {
    final data = <String, dynamic>{
      'content': content,
      'message_type': messageType,
    };
    if (mediaUrl != null) data['media_url'] = mediaUrl;
    if (relatedId != null) data['related_id'] = relatedId;
    if (requestId != null) data['request_id'] = requestId;
    final resp = await _api.post('/chat/conversations/$convId/messages', data: data);
    if (resp.success) {
      SoundService().playSendSound();
    }
    return resp;
  }
}
