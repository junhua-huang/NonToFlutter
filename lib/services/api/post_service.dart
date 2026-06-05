import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:facebook_clone/services/sound_service.dart';

import 'api_client.dart';

class PostService {
  static final PostService _instance = PostService._();
  factory PostService() => _instance;
  PostService._();
  final ApiClient _api = ApiClient();

  Future<ApiResponse> createPost({
    required String content,
    String visibility = 'public',
    String? imagePath,
    List<String>? imageUrls,
    String? videoPath,
    List<int>? visibleUserIds,
  }) async {
    ApiResponse resp;
    // If local file path provided (mobile), use upload
    if (imagePath != null && imagePath.isNotEmpty && !imagePath.startsWith('http')) {
      // Upload image first, then create post with URL
      final file = XFile(imagePath);
      final uploadResp = await _api.upload('/upload/post/image', file);
      if (uploadResp.success && uploadResp.data != null) {
        final uploadedUrl = uploadResp.data is Map
            ? uploadResp.data['url'] ?? uploadResp.data['image_url']
            : uploadResp.data;
        final formData = FormData.fromMap({
          'content': content,
          'visibility': visibility,
          if (uploadedUrl != null) 'image_url': uploadedUrl.toString(),
          if (visibleUserIds != null && visibleUserIds.isNotEmpty)
            'visible_user_ids': visibleUserIds.join(','),
        });
        resp = await _api.post('/posts/', data: formData);
        if (resp.success) SoundService().playSendSound();
        return resp;
      }
      return uploadResp;
    }

    final formData = FormData.fromMap({
      'content': content,
      'visibility': visibility,
      if (imageUrls != null && imageUrls.isNotEmpty)
        'image_urls': jsonEncode(imageUrls),
      if (videoPath != null && videoPath.isNotEmpty) 'video_url': videoPath,
      if (visibleUserIds != null && visibleUserIds.isNotEmpty)
        'visible_user_ids': visibleUserIds.join(','),
    });
    resp = await _api.post('/posts/', data: formData);
    if (resp.success) SoundService().playSendSound();
    return resp;
  }

  Future<ApiResponse> getFeed({int page = 1, int perPage = 20}) {
    return _api.get('/posts/', params: {'page': page, 'per_page': perPage});
  }

  Future<ApiResponse> getUserPosts(int userId, {int page = 1, int perPage = 20}) {
    return _api.get('/posts/user/$userId', params: {'page': page, 'per_page': perPage});
  }

  Future<ApiResponse> getPost(int postId) => _api.get('/posts/$postId');

  Future<ApiResponse> updatePost(int postId, Map<String, dynamic> data) =>
      _api.put('/posts/$postId', data: data);

  Future<ApiResponse> deletePost(int postId) => _api.delete('/posts/$postId');

  Future<ApiResponse> likePost(int postId) => _api.post('/posts/$postId/like');

  Future<ApiResponse> unlikePost(int postId) => _api.delete('/posts/$postId/like');

  Future<ApiResponse> getLikes(int postId) => _api.get('/posts/$postId/likes');

  Future<ApiResponse> getUserLikedPosts(int userId, {int page = 1, int perPage = 20}) =>
      _api.get('/posts/user/$userId/liked', params: {'page': page, 'per_page': perPage});

  Future<ApiResponse> recordView(int postId) => _api.post('/posts/$postId/view');

  Future<ApiResponse> getPostStats(int postId) => _api.get('/posts/$postId/stats');
}
