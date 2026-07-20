import 'api_client.dart';

abstract interface class BlockApi {
  Future<ApiResponse> blockUser(int userId);

  Future<ApiResponse> unblockUser(int userId);

  Future<ApiResponse> getBlockedUsers({int page = 1, int perPage = 20});
}

class BlockService implements BlockApi {
  static final BlockService _instance = BlockService._();
  factory BlockService() => _instance;
  BlockService._();
  final ApiClient _api = ApiClient();

  /// 屏蔽用户
  @override
  Future<ApiResponse> blockUser(int userId) async {
    return _api.post('/blocks', data: {
      'user_id': userId,
    });
  }

  /// 取消屏蔽用户
  @override
  Future<ApiResponse> unblockUser(int userId) async {
    return _api.delete('/blocks/$userId');
  }

  /// 获取屏蔽列表
  @override
  Future<ApiResponse> getBlockedUsers({int page = 1, int perPage = 20}) async {
    return _api
        .getDeduped('/blocks', params: {'page': page, 'per_page': perPage});
  }
}
