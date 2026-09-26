import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:nonto/services/sound_service.dart';

import 'api_client.dart';

class PostService {
  static final PostService _instance = PostService._();
  factory PostService() => _instance;
  PostService._();
  final ApiClient _api = ApiClient();

  void _invalidatePostReads({int? postId}) {
    if (postId != null) {
      _api.cancelGet('/posts/$postId');
    }
    _api.invalidateRequestsWhere(
      (key) =>
          key == 'GET:/posts/' ||
          key.startsWith('GET:/posts/?') ||
          key.startsWith('GET:/posts/user/') ||
          key == 'GET:/recommendations/feed' ||
          key.startsWith('GET:/recommendations/feed?'),
    );
  }

  static Map<String, dynamic> buildMutationData({
    required String content,
    required String visibility,
    List<String>? imageUrls,
    String? videoPath,
    String? thumbnailUrl,
    String? displayRoleType,
    int? communityId,
    int? quotedPostId,
  }) {
    if (visibility != 'public' && visibility != 'friends') {
      throw ArgumentError.value(
        visibility,
        'visibility',
        'Only public and friends are supported',
      );
    }
    return <String, dynamic>{
      'content': content,
      'visibility': visibility,
      if (displayRoleType != null && displayRoleType.isNotEmpty)
        'display_role_type': displayRoleType,
      if (imageUrls != null && imageUrls.isNotEmpty)
        'image_urls': jsonEncode(imageUrls),
      if (videoPath != null && videoPath.isNotEmpty) 'video_url': videoPath,
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
        'thumbnail_url': thumbnailUrl,
      if (communityId != null) 'community_id': communityId,
      if (quotedPostId != null) 'quoted_post_id': quotedPostId,
    };
  }

  Future<ApiResponse> createPost({
    required String content,
    required String visibility,
    String? imagePath,
    List<String>? imageUrls,
    String? videoPath,
    String? thumbnailUrl,
    String? displayRoleType,
    int? communityId,
    int? quotedPostId,
  }) async {
    ApiResponse resp;
    // If local file path provided (mobile), use upload.
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        !imagePath.startsWith('http')) {
      final file = XFile(imagePath);
      final uploadResp = await _api.upload('/upload/post/image', file);
      if (uploadResp.success && uploadResp.data != null) {
        final uploadedUrl = uploadResp.data is Map
            ? uploadResp.data['url']
            : uploadResp.data;
        if (uploadedUrl == null || uploadedUrl.toString().isEmpty) {
          return ApiResponse(
            success: false,
            message: '图片上传失败，请重试',
            statusCode: uploadResp.statusCode,
          );
        }
        final formData = FormData.fromMap(
          buildMutationData(
            content: content,
            visibility: visibility,
            displayRoleType: displayRoleType,
            imageUrls: [uploadedUrl.toString()],
            communityId: communityId,
            quotedPostId: quotedPostId,
          ),
        );
        resp = await _api.post('/posts', data: formData);
        if (resp.success) {
          _invalidatePostReads();
          SoundService().playSendSound();
        }
        return resp;
      }
      return uploadResp;
    }

    final formData = FormData.fromMap(
      buildMutationData(
        content: content,
        visibility: visibility,
        imageUrls: imageUrls,
        videoPath: videoPath,
        thumbnailUrl: thumbnailUrl,
        displayRoleType: displayRoleType,
        communityId: communityId,
        quotedPostId: quotedPostId,
      ),
    );
    resp = await _api.post('/posts', data: formData);
    if (resp.success) {
      _invalidatePostReads();
      SoundService().playSendSound();
    }
    return resp;
  }

  Future<ApiResponse> getFeed({int page = 1, int perPage = 20}) {
    return _api
        .getDeduped('/posts/', params: {'page': page, 'per_page': perPage});
  }

  Future<ApiResponse> getRelatedToMe({int page = 1, int perPage = 20}) {
    return _api.getDeduped(
      '/posts/related-to-me',
      params: {'page': page, 'per_page': perPage},
    );
  }

  Future<ApiResponse> getUserPosts(
    int userId, {
    int page = 1,
    int perPage = 20,
  }) {
    return _api.getDeduped(
      '/posts/user/$userId',
      params: {'page': page, 'per_page': perPage},
    );
  }

  Future<ApiResponse> getPost(int postId) => _api.getDeduped('/posts/$postId');

  Future<ApiResponse> updatePost(
    int postId, {
    required String content,
    required String visibility,
  }) async {
    final response = await _api.put(
      '/posts/$postId',
      data: buildMutationData(content: content, visibility: visibility),
    );
    if (response.success) {
      _invalidatePostReads(postId: postId);
    }
    return response;
  }

  Future<ApiResponse> deletePost(int postId) async {
    final response = await _api.delete('/posts/$postId');
    if (response.success) {
      _invalidatePostReads(postId: postId);
    }
    return response;
  }

  Future<ApiResponse> likePost(int postId) => _api.post('/posts/$postId/like');

  Future<ApiResponse> unlikePost(int postId) =>
      _api.delete('/posts/$postId/like');

  Future<ApiResponse> getLikes(int postId) =>
      _api.getDeduped('/posts/$postId/likes');

  Future<ApiResponse> getUserLikedPosts(
    int userId, {
    int page = 1,
    int perPage = 20,
  }) =>
      _api.getDeduped(
        '/posts/user/$userId/liked',
        params: {'page': page, 'per_page': perPage},
      );

  Future<ApiResponse> recordView(int postId) =>
      _api.post('/posts/$postId/view');

  Future<ApiResponse> getPostStats(int postId) =>
      _api.getDeduped('/posts/$postId/stats');
}
