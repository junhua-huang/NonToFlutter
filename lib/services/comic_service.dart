import 'package:cross_file/cross_file.dart';

import '../models/comic_event.dart';
import 'api/api_client.dart';

class ComicService {
  static const String _basePath = '/comic';

  Future<ApiResponse<List<ComicCity>>> getCities() async {
    final resp = await ApiClient().getDeduped<List<dynamic>>('$_basePath/cities');
    if (resp.success && resp.data != null) {
      final cities =
          resp.data!.map((e) => ComicCity.fromJson(e as Map<String, dynamic>)).toList();
      return ApiResponse(success: true, data: cities);
    }
    return ApiResponse(success: false, message: resp.message ?? '获取城市列表失败');
  }

  Future<ApiResponse<List<ComicTag>>> getTags() async {
    final resp = await ApiClient().getDeduped<List<dynamic>>('$_basePath/tags');
    if (resp.success && resp.data != null) {
      final tags =
          resp.data!.map((e) => ComicTag.fromJson(e as Map<String, dynamic>)).toList();
      return ApiResponse(success: true, data: tags);
    }
    return ApiResponse(success: false, message: resp.message ?? '获取标签列表失败');
  }

  Future<ApiResponse<ComicEventsPage>> getEvents({
    String city = '',
    int page = 1,
    int size = 10,
  }) async {
    final params = <String, dynamic>{
      'page': page.toString(),
      'size': size.toString(),
    };
    if (city.isNotEmpty && city != '全部') {
      params['city'] = city;
    }

    final resp = await ApiClient().getDeduped<Map<String, dynamic>>(
      '$_basePath/events',
      params: params,
    );
    if (resp.success && resp.data != null) {
      return ApiResponse(success: true, data: ComicEventsPage.fromJson(resp.data!));
    }
    return ApiResponse(success: false, message: resp.message ?? '获取漫展列表失败');
  }

  Future<ApiResponse<ComicEvent>> getEventDetail(int eventId, {int? userId}) async {
    final params = <String, dynamic>{};
    if (userId != null) params['userId'] = userId.toString();

    final resp = await ApiClient().getDeduped<Map<String, dynamic>>(
      '$_basePath/events/$eventId',
      params: params,
    );
    if (resp.success && resp.data != null) {
      return ApiResponse(success: true, data: ComicEvent.fromDetailJson(resp.data!));
    }
    return ApiResponse(success: false, message: resp.message ?? '获取漫展详情失败');
  }

  Future<ApiResponse<Map<String, dynamic>>> toggleFollow(int eventId) async {
    final resp = await ApiClient().post<Map<String, dynamic>>(
      '$_basePath/events/$eventId/follow',
    );
    if (resp.success) {
      return ApiResponse(success: true, data: resp.data);
    }
    return ApiResponse(success: false, message: resp.message ?? '操作失败');
  }

  /// 获取当前用户发布的漫展（分页）
  Future<ApiResponse<ComicEventsPage>> getMyEvents({int page = 1, int size = 10}) async {
    final resp = await ApiClient().getDeduped<Map<String, dynamic>>(
      '$_basePath/my-events',
      params: {'page': page.toString(), 'size': size.toString()},
    );
    if (resp.success && resp.data != null) {
      return ApiResponse(success: true, data: ComicEventsPage.fromJson(resp.data!));
    }
    return ApiResponse(success: false, message: resp.message ?? '获取我的漫展失败');
  }

  /// 获取当前用户关注的漫展（分页）
  Future<ApiResponse<ComicEventsPage>> getMyFollowed({int page = 1, int size = 10}) async {
    final resp = await ApiClient().getDeduped<Map<String, dynamic>>(
      '$_basePath/my-followed',
      params: {'page': page.toString(), 'size': size.toString()},
    );
    if (resp.success && resp.data != null) {
      return ApiResponse(success: true, data: ComicEventsPage.fromJson(resp.data!));
    }
    return ApiResponse(success: false, message: resp.message ?? '获取关注的漫展失败');
  }

  /// 提交漫展 JSON（图片 URL 已预先上传）
  Future<ApiResponse<Map<String, dynamic>>> submitEvent(Map<String, dynamic> body) async {
    final resp =
        await ApiClient().post<Map<String, dynamic>>('$_basePath/events', data: body);
    return resp;
  }

  /// 更新漫展 JSON
  Future<ApiResponse<Map<String, dynamic>>> updateEventData(
      int eventId, Map<String, dynamic> body) async {
    final resp = await ApiClient()
        .put<Map<String, dynamic>>('$_basePath/events/$eventId', data: body);
    return resp;
  }

  /// 逐张图片上传到 COS（创建漫展用）
  Future<int> createEvent(
    Map<String, String> fields,
    List<XFile> imageFiles, {
    void Function(int idx, int total, double progress)? onImageProgress,
  }) async {
    final api = ApiClient();

    final imageUrls = <String>[];
    for (int i = 0; i < imageFiles.length; i++) {
      final resp = await api.upload<Map<String, dynamic>>(
        '/upload/comic',
        imageFiles[i],
        onSendProgress: (sent, total) {
          onImageProgress?.call(i + 1, imageFiles.length, sent / total);
        },
      );
      if (!resp.success || resp.data == null) {
        throw Exception(resp.message ?? '图片 ${i + 1} 上传失败');
      }
      final url = resp.data!['url']?.toString() ?? '';
      if (url.isEmpty) {
        throw Exception('图片 ${i + 1} 上传返回 URL 为空');
      }
      imageUrls.add(url);
    }

    final body = <String, dynamic>{...fields, 'imageUrls': imageUrls};
    final resp = await api.post<Map<String, dynamic>>('$_basePath/events', data: body);
    if (resp.success && resp.data != null) {
      return resp.data!['id'] ?? -1;
    }
    throw Exception(resp.message ?? '发布失败');
  }

  // ==========================================
  // 漫展评论
  // ==========================================

  Future<ApiResponse<Map<String, dynamic>>> getEventComments(int eventId, {int page = 1, int size = 20}) async {
    return ApiClient().get<Map<String, dynamic>>(
      '$_basePath/events/$eventId/comments',
      params: {'page': page.toString(), 'size': size.toString()},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> postEventComment(
    int eventId, {
    required String content,
    int? parentId,
    int? replyToUserId,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (parentId != null) body['parent_id'] = parentId;
    if (replyToUserId != null) body['reply_to_user_id'] = replyToUserId;
    return ApiClient().post<Map<String, dynamic>>(
      '$_basePath/events/$eventId/comments',
      data: body,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getCommentReplies(int commentId, {int page = 1, int size = 50}) async {
    return ApiClient().get<Map<String, dynamic>>(
      '$_basePath/events/comments/$commentId/replies',
      params: {'page': page.toString(), 'size': size.toString()},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> likeComment(int commentId) async {
    return ApiClient().post<Map<String, dynamic>>(
      '$_basePath/events/comments/$commentId/like',
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteComment(int commentId) async {
    return ApiClient().delete<Map<String, dynamic>>(
      '$_basePath/events/comments/$commentId',
    );
  }

  /// 逐张图片上传到 COS（编辑漫展用）
  Future<void> updateEvent(
    int eventId,
    Map<String, String> fields,
    List<XFile> newImageFiles, {
    void Function(int idx, int total, double progress)? onImageProgress,
  }) async {
    final api = ApiClient();

    final imageUrls = <String>[];
    for (int i = 0; i < newImageFiles.length; i++) {
      final resp = await api.upload<Map<String, dynamic>>(
        '/upload/comic',
        newImageFiles[i],
        onSendProgress: (sent, total) {
          onImageProgress?.call(i + 1, newImageFiles.length, sent / total);
        },
      );
      if (!resp.success || resp.data == null) {
        throw Exception(resp.message ?? '图片 ${i + 1} 上传失败');
      }
      final url = resp.data!['url']?.toString() ?? '';
      if (url.isEmpty) {
        throw Exception('图片 ${i + 1} 上传返回 URL 为空');
      }
      imageUrls.add(url);
    }

    final body = <String, dynamic>{...fields, 'imageUrls': imageUrls};
    final resp =
        await api.put<Map<String, dynamic>>('$_basePath/events/$eventId', data: body);
    if (!resp.success) {
      throw Exception(resp.message ?? '编辑失败');
    }
  }
}