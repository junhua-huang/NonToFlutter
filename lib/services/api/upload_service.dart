import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:nonto/utils/image_compressor.dart';

import 'api_client.dart';

class ImageUploadFormat {
  final String extension;
  final String mimeType;

  const ImageUploadFormat(this.extension, this.mimeType);
}

class UploadService {
  static final UploadService _i = UploadService._();
  factory UploadService() => _i;
  UploadService._();
  final ApiClient _api = ApiClient();

  static ImageUploadFormat? detectImageUploadFormat(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return const ImageUploadFormat('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return const ImageUploadFormat('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return const ImageUploadFormat('webp', 'image/webp');
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return const ImageUploadFormat('gif', 'image/gif');
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return const ImageUploadFormat('bmp', 'image/bmp');
    }
    return null;
  }

  static String uploadFileNameForFormat(String originalName, String extension) {
    final trimmed = originalName.trim();
    if (trimmed.isEmpty) {
      return 'image_${DateTime.now().millisecondsSinceEpoch}.$extension';
    }
    final dotIndex = trimmed.lastIndexOf('.');
    final baseName = dotIndex > 0 ? trimmed.substring(0, dotIndex) : trimmed;
    return '$baseName.$extension';
  }

  static String compressedJpegFileName(String originalName) =>
      uploadFileNameForFormat(originalName, 'jpg');

  /// 压缩 XFile 图片（如果为图片格式），返回压缩后的 XFile
  static Future<XFile> _compressIfImage(XFile file) async {
    final ext = (file.name.contains('.') ? file.name.split('.').last : '')
        .toLowerCase();
    const imageExts = [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'bmp',
      'gif',
      'heic',
      'heif'
    ];
    final isImageMime =
        (file.mimeType ?? '').toLowerCase().startsWith('image/');
    if (!imageExts.contains(ext) && !isImageMime) return file;

    final originalBytes = await file.readAsBytes();
    final compressedBytes = await ImageCompressor.compressImage(
      originalBytes,
      quality: 92,
      maxWidth: 1920,
      allowLargerOutput: true,
    );
    final format = detectImageUploadFormat(compressedBytes);
    if (format == null) {
      throw UnsupportedError('图片格式暂不支持，请换用 JPG/PNG/WEBP');
    }
    final uploadFileName = uploadFileNameForFormat(file.name, format.extension);
    return XFile.fromData(
      compressedBytes,
      name: uploadFileName,
      path: uploadFileName,
      mimeType: format.mimeType,
    );
  }

  static Future<Uint8List> _encodeJpegBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    final image = frameInfo.image;
    try {
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        throw UnsupportedError('图片格式暂不支持，请换用 JPG/PNG/WEBP');
      }
      final decoded = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: byteData.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  static Future<XFile> _compressPostImage(XFile file) async {
    final compressed = await _compressIfImage(file);
    final compressedBytes = await compressed.readAsBytes();
    final jpegBytes = await _encodeJpegBytes(compressedBytes);
    final uploadFileName = compressedJpegFileName(file.name);
    return XFile.fromData(
      jpegBytes,
      name: uploadFileName,
      path: uploadFileName,
      mimeType: 'image/jpeg',
    );
  }

  /// 上传通用图片（压缩后上传）
  Future<ApiResponse> uploadImage(XFile file,
      {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressIfImage(file);
    return _api.upload('/upload/image', compressed, onSendProgress: onProgress);
  }

  /// 上传通用视频
  Future<ApiResponse> uploadVideo(XFile file,
          {void Function(int sent, int total)? onProgress}) =>
      _api.upload('/upload/video', file, onSendProgress: onProgress);

  /// 上传帖子图片（压缩后上传）
  Future<ApiResponse> uploadPostImage(XFile file,
      {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressPostImage(file);
    return _api.upload('/upload/post/image', compressed,
        onSendProgress: onProgress);
  }

  /// 上传帖子视频
  Future<ApiResponse> uploadPostVideo(XFile file,
          {void Function(int sent, int total)? onProgress}) =>
      _api.upload('/upload/post/video', file, onSendProgress: onProgress);

  /// 上传头像（压缩后上传）
  Future<ApiResponse> uploadAvatar(XFile file,
      {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressIfImage(file);
    return _api.upload('/upload/avatar', compressed,
        onSendProgress: onProgress);
  }

  /// 上传封面图（压缩后上传）
  Future<ApiResponse> uploadCover(XFile file,
      {void Function(int sent, int total)? onProgress}) async {
    final compressed = await _compressIfImage(file);
    return _api.upload('/upload/cover', compressed, onSendProgress: onProgress);
  }

  /// 上传封面图别名（用于 profile_tab）
  Future<ApiResponse> uploadCoverPhoto(XFile file,
          {void Function(int sent, int total)? onProgress}) =>
      uploadCover(file, onProgress: onProgress);

  /// 批量上传文件（逐个通过 COS 直传，压缩后上传）
  Future<ApiResponse> uploadMultiple(List<XFile> files, String type) async {
    final uploadedUrls = <String>[];
    for (final file in files) {
      final compressed = await _compressIfImage(file);
      final resp = await _api
          .upload('/upload/multiple', compressed, extraData: {'type': type});
      if (resp.success && resp.data != null) {
        final url = resp.data is Map
            ? (resp.data as Map)['url']?.toString()
            : resp.data?.toString();
        if (url != null) uploadedUrls.add(url);
      } else {
        return ApiResponse(
          success: false,
          message: resp.message ?? '上传失败',
          data: uploadedUrls,
          statusCode: resp.statusCode,
          errorCode: resp.errorCode,
          isRetryable: resp.isRetryable,
        );
      }
    }
    return ApiResponse(
        success: true, data: {'urls': uploadedUrls, 'type': type});
  }

  /// 压缩 XFile 图片（不通过 Service 上传，供外部使用）
  static Future<XFile> compressXFile(XFile file) => _compressIfImage(file);

  /// 压缩帖子图片为后端帖子上传链路使用的 JPEG。
  static Future<XFile> compressXFileForPost(XFile file) =>
      _compressPostImage(file);

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
      _api.getDeduped('/upload/info', params: {'url': url});
}
