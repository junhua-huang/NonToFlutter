import 'api_client.dart';

class FriendService {
  static final FriendService _i = FriendService._();
  factory FriendService() => _i;
  FriendService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> sendRequest(int receiverId) =>
      _api.post('/friends/request', data: {'receiver_id': receiverId});
  Future<ApiResponse> acceptRequest(int requestId) =>
      _api.post('/friends/request/$requestId/accept');
  Future<ApiResponse> rejectRequest(int requestId) =>
      _api.post('/friends/request/$requestId/reject');
  Future<ApiResponse> cancelRequest(int requestId) =>
      _api.delete('/friends/request/$requestId');
  Future<ApiResponse> getFriends() => _api.get('/friends/');
  Future<ApiResponse> getPendingRequests() => _api.get('/friends/requests/pending');
  Future<ApiResponse> getSentRequests() => _api.get('/friends/requests/sent');
  Future<ApiResponse> getReceivedRequests() => _api.get('/friends/requests/received');
  Future<ApiResponse> deleteFriend(int userId) => _api.delete('/friends/$userId');
  Future<ApiResponse> checkStatus(int userId) => _api.get('/friends/status/$userId');
  Future<ApiResponse> getFriendCount(int userId) => _api.get('/friends/count/$userId');
  Future<ApiResponse> getFriendRecommendations({int limit = 10}) =>
      _api.get('/friends/recommendations', params: {'limit': limit});

  /// Follow a user (alias for sendFriendRequest)
  Future<ApiResponse> followUser(int userId) => sendRequest(userId);

  /// Unfollow a user (alias for deleteFriend)
  Future<ApiResponse> unfollowUser(int userId) => deleteFriend(userId);
}
