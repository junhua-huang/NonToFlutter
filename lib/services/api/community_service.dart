import 'api_client.dart';

/// 社群 API 服务 — 对接后端 /api/communities/* 端点
class CommunityApiService {
  static final CommunityApiService _instance = CommunityApiService._();
  factory CommunityApiService() => _instance;
  CommunityApiService._();
  final ApiClient _api = ApiClient();

  // ── 社群 CRUD ──

  /// 搜索/列出社群
  Future<ApiResponse> list({String? keyword, int limit = 20, int offset = 0}) {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
    return _api.get('/communities', params: params);
  }

  /// 我的社群
  Future<ApiResponse> getMy({bool manageOnly = false}) {
    return _api.get('/communities/my',
        params: {'manage_only': manageOnly});
  }

  /// 社群详情
  Future<ApiResponse> getDetail(int id) {
    return _api.get('/communities/$id');
  }

  /// 创建社群
  Future<ApiResponse> create(Map<String, dynamic> data) {
    return _api.post('/communities', data: data);
  }

  /// 编辑社群
  Future<ApiResponse> update(int id, Map<String, dynamic> data) {
    return _api.put('/communities/$id', data: data);
  }

  /// 解散社群
  Future<ApiResponse> disband(int id) {
    return _api.delete('/communities/$id');
  }

  // ── 加群 / 审核 ──

  /// 申请加群
  Future<ApiResponse> join(int communityId, {String? message}) {
    final data = <String, dynamic>{};
    if (message != null && message.isNotEmpty) data['message'] = message;
    return _api.post('/communities/$communityId/join', data: data);
  }

  /// 待审核列表
  Future<ApiResponse> getJoinRequests(int communityId,
      {int limit = 50, int offset = 0}) {
    return _api.get('/communities/$communityId/join-requests',
        params: {'limit': limit, 'offset': offset});
  }

  /// 通过申请
  Future<ApiResponse> approveJoin(int communityId, int requestId) {
    return _api.post('/communities/$communityId/join-requests/$requestId/approve');
  }

  /// 拒绝申请
  Future<ApiResponse> rejectJoin(int communityId, int requestId) {
    return _api.post('/communities/$communityId/join-requests/$requestId/reject');
  }

  // ── 成员管理 ──

  /// 成员列表
  Future<ApiResponse> getMembers(int communityId,
      {int limit = 50, int offset = 0}) {
    return _api.get('/communities/$communityId/members',
        params: {'limit': limit, 'offset': offset});
  }

  /// 退群
  Future<ApiResponse> leave(int communityId) {
    return _api.delete('/communities/$communityId/members/me');
  }

  /// 踢人
  Future<ApiResponse> kick(int communityId, int userId) {
    return _api.delete('/communities/$communityId/members/$userId');
  }

  /// 设管理员/撤管理员
  Future<ApiResponse> setRole(int communityId, int userId, String role) {
    return _api.put('/communities/$communityId/members/$userId',
        data: {'role': role});
  }

  // ── 群聊 ──

  /// 获取群聊会话 + 最近消息
  Future<ApiResponse> getChat(int communityId,
      {int limit = 50}) {
    return _api.get('/communities/$communityId/chat',
        params: {'limit': limit});
  }

  /// 发送群聊消息
  Future<ApiResponse> sendMessage(
    int communityId, {
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    List<int>? mentionUserIds,
  }) {
    final data = <String, dynamic>{
      'content': content,
      'message_type': messageType,
    };
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      data['media_url'] = mediaUrl;
    }
    if (mentionUserIds != null && mentionUserIds.isNotEmpty) {
      data['mention_user_ids'] = mentionUserIds;
    }
    return _api.post('/communities/$communityId/chat/messages', data: data);
  }

  /// 撤回消息
  Future<ApiResponse> recallMessage(int communityId, int messageId) {
    return _api.delete('/communities/$communityId/chat/messages/$messageId');
  }

  // ── 公告 ──

  /// 公告列表
  Future<ApiResponse> getAnnouncements(int communityId) {
    return _api.get('/communities/$communityId/announcements');
  }

  /// 发布公告
  Future<ApiResponse> createAnnouncement(int communityId,
      {required String title, String? content, bool isPinned = false}) {
    return _api.post('/communities/$communityId/announcements',
        data: {'title': title, 'content': content, 'is_pinned': isPinned});
  }

  /// 编辑公告
  Future<ApiResponse> updateAnnouncement(int communityId, int announcementId,
      Map<String, dynamic> data) {
    return _api.put(
        '/communities/$communityId/announcements/$announcementId', data: data);
  }

  /// 删除公告
  Future<ApiResponse> deleteAnnouncement(int communityId, int announcementId) {
    return _api.delete(
        '/communities/$communityId/announcements/$announcementId');
  }

  // ── 黑名单 ──

  /// 黑名单列表
  Future<ApiResponse> getBans(int communityId) {
    return _api.get('/communities/$communityId/bans');
  }

  /// 拉黑
  Future<ApiResponse> banUser(int communityId,
      {required int userId, String? reason}) {
    return _api.post('/communities/$communityId/bans',
        data: {'user_id': userId, 'reason': reason});
  }

  /// 解封
  Future<ApiResponse> unbanUser(int communityId, int userId) {
    return _api.delete('/communities/$communityId/bans/$userId');
  }

  // ── 热门帖子 ──

  /// 热门帖子
  Future<ApiResponse> getHotPosts(int communityId, {int limit = 20}) {
    return _api.get('/communities/$communityId/hot-posts',
        params: {'limit': limit});
  }

  /// 通用 GET（给 provider 内部用）
  Future<ApiResponse> get(String path, {Map<String, dynamic>? params}) {
    return _api.get(path, params: params);
  }
}
