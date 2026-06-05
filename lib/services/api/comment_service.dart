import 'api_client.dart';
import 'package:facebook_clone/services/sound_service.dart';

class CommentService {
  static final CommentService _i = CommentService._();
  factory CommentService() => _i;
  CommentService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> createComment(int postId, String content, {int? parentId}) async {
    final resp = await _api.post('/posts/$postId/comments',
      data: {'content': content, if (parentId != null) 'parent_id': parentId});
    if (resp.success) {
      SoundService().playSendSound();
    }
    return resp;
  }
  Future<ApiResponse> getComments(int postId, {int page = 1, int perPage = 20}) =>
      _api.get('/posts/$postId/comments', params: {'page': page, 'per_page': perPage});
  Future<ApiResponse> getReplies(int postId, {int? parentId}) =>
      _api.get('/posts/$postId/comments', params: {'parent_id': parentId ?? 0});
  Future<ApiResponse> getComment(int commentId) => _api.get('/comments/$commentId');
  Future<ApiResponse> updateComment(int commentId, String content) =>
      _api.put('/comments/$commentId', data: {'content': content});
  Future<ApiResponse> deleteComment(int commentId) => _api.delete('/comments/$commentId');
  Future<ApiResponse> likeComment(int commentId) => _api.post('/comments/$commentId/like');
  Future<ApiResponse> unlikeComment(int commentId) => _api.delete('/comments/$commentId/like');
}
