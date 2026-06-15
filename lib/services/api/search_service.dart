import 'api_client.dart';

class SearchService {
  static final SearchService _i = SearchService._();
  factory SearchService() => _i;
  SearchService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> searchUsers(String q, {int page = 1}) =>
      _api.getDeduped('/search/users', params: {'q': q, 'page': page});
  Future<ApiResponse> searchPosts(String q, {int page = 1}) =>
      _api.getDeduped('/search/posts', params: {'q': q, 'page': page});
  Future<ApiResponse> globalSearch(String q, {int page = 1, int perPage = 10}) {
    final trimmed = q.trim();
    if (trimmed.length < 2) {
      return Future.value(ApiResponse(
        success: false,
        message: '搜索关键词至少需要2个字符',
        statusCode: 422,
      ));
    }
    return _api.getDeduped('/search/global', params: {'q': q, 'page': page, 'per_page': perPage});
  }
  Future<ApiResponse> hashtagSearch(String tag, {int page = 1}) =>
      _api.getDeduped('/search/hashtag/$tag', params: {'page': page});
  Future<ApiResponse> trendingHashtags({int limit = 10}) =>
      _api.getDeduped('/search/trending-hashtags', params: {'limit': limit});
  Future<ApiResponse> suggestUsers(String prefix, {int limit = 5}) =>
      _api.getDeduped('/search/suggest/users', params: {'prefix': prefix, 'limit': limit});
  Future<ApiResponse> mentionSuggestions(String prefix, {int limit = 5}) =>
      _api.getDeduped('/search/mention-suggestions', params: {'prefix': prefix, 'limit': limit});
  Future<ApiResponse> getHistory({int limit = 20}) =>
      _api.getDeduped('/search/history', params: {'limit': limit});
  Future<ApiResponse> saveHistory(String query, String type) =>
      _api.post('/search/history', data: {'query': query, 'type': type});
  Future<ApiResponse> clearHistory() => _api.delete('/search/history');
  Future<ApiResponse> searchTopics(String q, {int page = 1}) =>
      _api.getDeduped('/search/topics', params: {'q': q, 'page': page});
}
