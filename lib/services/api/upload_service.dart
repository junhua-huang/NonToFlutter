import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:facebook_clone/utils/image_compressor.dart';

import 'api_client.dart';

class UploadService {
  static final UploadService _i = UploadService._();
  factory UploadService() => _i;
  UploadService._();
  final ApiClient _api = ApiClient();

  /// 压缩 XFile 图片（如果为图片格式），返回压缩后的 XFile
  static Future<XFile> _compressIfImage(XFile file) async {
    final ext = (file.name.contains('.') ? file.name.split('.').last : '').toLowerCase();
    const imageExts = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif'];
    if (!imageExts.contains(ext)) return file;

    try {
      final originalBytes = await file.readAsBytes();
      final compressedBytes = await ImageCompressor.compressImage(
        originalBytes,
        quality: 92,
        maxWidth: 1920,
      );
      return XFile.fromData(
        compressedBytes,
        name: file.name,
        mimeType: 'image/jpeg',
      );
    } catch (e) {
      return file; // 压缩失败回退原图
    }
  }

  /// 上传通用图片（压缩后上传）
  Future<ApiResponse> uploadImage(XFile file, {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressIfImage(file);
    return _api.upload('/upload/image', compressed, onSendProgress: onProgress);
  }

  /// 上传通用视频
  Future<ApiResponse> uploadVideo(XFile file, {void Function(int sent, int total)? onProgress}) =>
      _api.upload('/upload/video', file, onSendProgress: onProgress);

  /// 上传帖子图片（压缩后上传）
  Future<ApiResponse> uploadPostImage(XFile file, {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressIfImage(file);
    return _api.upload('/upload/post/image', compressed, onSendProgress: onProgress);
  }

  /// 上传帖子视频
  Future<ApiResponse> uploadPostVideo(XFile file, {void Function(int sent, int total)? onProgress}) =>
      _api.upload('/upload/post/video', file, onSendProgress: onProgress);

  /// 上传头像（压缩后上传）
  Future<ApiResponse> uploadAvatar(XFile file, {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressIfImage(file);
    return _api.upload('/upload/avatar', compressed, onSendProgress: onProgress);
  }

  /// 上传封面图（压缩后上传）
  Future<ApiResponse> uploadCover(XFile file, {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressIfImage(file);
    return _api.upload('/upload/cover', compressed, onSendProgress: onProgress);
  }

  /// 上传封面图别名（用于 profile_tab）
  Future<ApiResponse> uploadCoverPhoto(XFile file, {void Function(int sent, int total)? onProgress}) =>
      uploadCover(file, onProgress: onProgress);

  /// 批量上传文件（逐个通过 COS 直传，压缩后上传）
  Future<ApiResponse> uploadMultiple(List<XFile> files, String type) async {
    final uploadedUrls = <String>[];
    for (final file in files) {
      final compressed = await _compressIfImage(file);
      final resp = await _api.upload('/upload/multiple', compressed,
          extraData: {'type': type});
      if (resp.success && resp.data != null) {
        final url = resp.data is Map
            ? (resp.data as Map)['url']?.toString()
            : resp.data?.toString();
        if (url != null) uploadedUrls.add(url);
      } else {
        return ApiResponse(
            success: false,
            message: '上传失败: ${resp.message}',
            data: uploadedUrls);
      }
    }
    return ApiResponse(
        success: true, data: {'urls': uploadedUrls, 'type': type});
  }

  /// 压缩 XFile 图片（不通过 Service 上传，供外部使用）
  static Future<XFile> compressXFile(XFile file) => _compressIfImage(file);

  /// 批量压缩 XFile 图片列表（不通过 Service 上传，供外部使用）
  static Future<List<XFile>> compressXFiles(List<XFile> files) async {
    final results = <XFile>[];
    for (final file in files) {
      results.add(await _compressIfImage(file));
    }
    return results;
  }

  /// 删除文件
  Future<ApiResponse> deleteFile(String fileUrl) =>
      _api.post('/upload/delete', data: {'file_url': fileUrl});

  /// 获取文件信息
  Future<ApiResponse> getFileInfo(String url) =>
      _api.get('/upload/info', params: {'url': url});
}
