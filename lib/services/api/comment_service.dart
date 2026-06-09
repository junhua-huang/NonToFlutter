import 'api_client.dart';

class CommentService {
  static final CommentService _i = CommentService._();
  factory CommentService() => _i;
  CommentService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> createComment(int postId, String content, {int? parentId, int? replyToUserId}) async {
    return await _api.post('/posts/$postId/comments',
      data: {
        'content': content,
        if (parentId != null) 'parent_id': parentId,
        if (replyToUserId != null) 'reply_to_user_id': replyToUserId,
      });
  }
  Future<ApiResponse> getComments(int postId, {int page = 1, int perPage = 20}) =>
      _api.getDeduped('/posts/$postId/comments', params: {'page': page, 'per_page': perPage});
  Future<ApiResponse> getReplies(int postId, {int? parentId, int page = 1, int perPage = 10}) =>
      _api.getDeduped('/posts/$postId/comments', params: {
        if (parentId != null && parentId > 0) 'parent_id': parentId,
        'page': page,
        'per_page': perPage,
      });
  Future<ApiResponse> getComment(int commentId) => _api.getDeduped('/comments/$commentId');
  Future<ApiResponse> updateComment(int commentId, String content) =>
      _api.put('/comments/$commentId', data: {'content': content});
  Future<ApiResponse> deleteComment(int commentId) => _api.delete('/comments/$commentId');
  Future<ApiResponse> likeComment(int commentId) => _api.post('/comments/$commentId/like');
  Future<ApiResponse> unlikeComment(int commentId) => _api.delete('/comments/$commentId/like');
}
