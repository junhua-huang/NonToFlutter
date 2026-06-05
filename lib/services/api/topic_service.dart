import 'api_client.dart';

class TopicService {
  static final TopicService _i = TopicService._();
  factory TopicService() => _i;
  TopicService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> getTopics({int page = 1, int perPage = 20, String? q}) =>
      _api.get('/topics/', params: {'page': page, 'per_page': perPage, if (q != null) 'q': q});
  Future<ApiResponse> getTrending({int limit = 10}) =>
      _api.get('/topics/trending', params: {'limit': limit});
  Future<ApiResponse> getTopic(int id) => _api.get('/topics/$id');
  Future<ApiResponse> getTopicByName(String name) => _api.get('/topics/name/$name');
  Future<ApiResponse> getTopicPosts(int id, {int page = 1}) =>
      _api.get('/topics/$id/posts', params: {'page': page});
  Future<ApiResponse> createTopic(Map<String, dynamic> data) => _api.post('/topics/', data: data);
  Future<ApiResponse> followTopic(int id) => _api.post('/topics/$id/follow');
  Future<ApiResponse> unfollowTopic(int id) => _api.post('/topics/$id/unfollow');
  Future<ApiResponse> getFollowedTopics({int page = 1}) =>
      _api.get('/topics/followed', params: {'page': page});
  Future<ApiResponse> getReferencedTopics({int page = 1}) =>
      _api.get('/topics/my-referenced', params: {'page': page});
  Future<ApiResponse> updateTopic(int id, Map<String, dynamic> data) =>
      _api.put('/topics/$id', data: data);
  Future<ApiResponse> deleteTopic(int id) => _api.delete('/topics/$id');
  Future<ApiResponse> suggestTopics({int limit = 10}) =>
      _api.get('/topics/suggest', params: {'limit': limit});
}
