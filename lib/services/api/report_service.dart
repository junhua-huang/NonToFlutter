import 'api_client.dart';

class ReportService {
  static final ReportService _instance = ReportService._();
  factory ReportService() => _instance;
  ReportService._();
  final ApiClient _api = ApiClient();

  /// 举报帖子
  Future<ApiResponse> reportPost(int postId, String reason) async {
    return _api.post('/reports/post', data: {
      'post_id': postId,
      'reason': reason,
    });
  }

  /// 举报评论
  Future<ApiResponse> reportComment(int commentId, String reason) async {
    return _api.post('/reports/comment', data: {
      'comment_id': commentId,
      'reason': reason,
    });
  }

  /// 举报用户
  Future<ApiResponse> reportUser(int userId, String reason) async {
    return _api.post('/reports/user', data: {
      'user_id': userId,
      'reason': reason,
    });
  }
}