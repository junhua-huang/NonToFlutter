import 'api_client.dart';

class RecommendationService {
  static final RecommendationService _i = RecommendationService._();
  factory RecommendationService() => _i;
  RecommendationService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> getFeed({int page = 1, int perPage = 20}) =>
      _api.get('/recommendations/feed', params: {'page': page, 'per_page': perPage});
  Future<ApiResponse> getTrending({int limit = 10, int hours = 24}) =>
      _api.get('/recommendations/trending', params: {'limit': limit, 'hours': hours});
  Future<ApiResponse> suggestUsers({int limit = 10}) =>
      _api.get('/recommendations/users/suggest', params: {'limit': limit});
  Future<ApiResponse> recommendFriends({int limit = 10}) =>
      _api.get('/recommendations/friends/recommend', params: {'limit': limit});
  Future<ApiResponse> getRelatedPosts(int postId, {int limit = 5}) =>
      _api.get('/recommendations/posts/$postId/related', params: {'limit': limit});
}
