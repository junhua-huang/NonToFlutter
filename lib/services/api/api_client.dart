import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'request_manager.dart';

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;

  ApiResponse({required this.success, this.data, this.message, this.statusCode});
}

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;
  ApiClient._();

  static String? token;

  /// 请求管理器：去重 + 限并发，可全局配置
  static final RequestManager requestManager = RequestManager(maxConcurrent: 4);

  /// 防止并发刷新 token
  static bool _isRefreshing = false;

  late final Dio _dio = _createDio();

  /// 专用于刷新 token 的 Dio（无拦截器，避免无限循环）
  static final Dio _refreshDio = _createRefreshDio();

  Dio get dio => _dio;

  static Dio _createRefreshDio() {
    return Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (token != null && token!.isNotEmpty) {
          final url = options.uri.toString();
          // 仅对自身 API 请求注入 Authorization，COS / 第三方 URL 不注入
          // （COS 预签名 URL 已自带鉴权签名，额外 Header 会导致 403 签名不匹配）
          if (!url.startsWith('http') || url.startsWith(AppConfig.baseUrl)) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        try {
          if (error.response?.statusCode == 401) {
            debugPrint('[ApiClient] 401 caught on ${error.requestOptions.path}, isRefreshing=$_isRefreshing');
            // 跳过刷新端点自身，避免无限循环
            if (error.requestOptions.path == '/auth/refresh') {
              debugPrint('[ApiClient] 401 on /auth/refresh itself — giving up');
              _handleRefreshFailed();
              return handler.next(error);
            }

            if (!_isRefreshing) {
              debugPrint('[ApiClient] starting token refresh...');
              _isRefreshing = true;
              try {
                final newToken = await _doRefreshToken();
                if (newToken != null) {
                  debugPrint('[ApiClient] refresh OK, retrying original request');
                  token = newToken;
                  final opts = error.requestOptions;
                  opts.headers['Authorization'] = 'Bearer $newToken';
                  try {
                    final response = await dio.fetch(opts);
                    debugPrint('[ApiClient] retry succeeded');
                    return handler.resolve(response);
                  } catch (retryErr) {
                    debugPrint('[ApiClient] retry also failed: $retryErr');
                    if (retryErr is DioException) {
                      return handler.next(retryErr);
                    }
                    return handler.next(
                      DioException(requestOptions: opts, error: retryErr),
                    );
                  }
                }
              } finally {
                _isRefreshing = false;
                debugPrint('[ApiClient] refresh attempt finished, isRefreshing=false');
              }
              // 刷新失败，清理 token
              if (token != null) {
                _handleRefreshFailed();
              }
            } else {
              debugPrint('[ApiClient] refresh already in progress, skipping duplicate');
            }
          }
          return handler.next(error);
        } catch (unexpected) {
          debugPrint('[ApiClient] FATAL: onError interceptor threw: $unexpected');
          // 兜底：保证 handler 一定被调用，避免请求永久挂起
          return handler.next(DioException(
            requestOptions: error.requestOptions,
            error: unexpected,
            type: DioExceptionType.unknown,
          ));
        }
      },
    ));
    return dio;
  }

  static void setToken(String? t) {
    token = t;
    if (t != null && t.isNotEmpty) {
      // Async connect WS whenever token is available
      WebSocketService().connect().catchError((e, stack) {
        debugPrint('❗ WebSocket connect failed: $e');
        debugPrint(stack.toString());
      });
    } else {
      // Disconnect WS when token is cleared
      WebSocketService().disconnect();
    }
  }

  /// 调用 /auth/refresh 获取新 token，使用专用 Dio 避免触发 401 拦截器
  static Future<String?> _doRefreshToken() async {
    final t0 = DateTime.now();
    try {
      if (token == null) {
        debugPrint('[ApiClient] _doRefreshToken: token is null, abort');
        return null;
      }
      debugPrint('[ApiClient] _doRefreshToken: step1 setting auth header...');
      _refreshDio.options.headers['Authorization'] = 'Bearer $token';
      debugPrint('[ApiClient] _doRefreshToken: step2 calling POST /auth/refresh...');
      final resp = await _refreshDio
          .post('/auth/refresh')
          .timeout(const Duration(seconds: 8));
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      debugPrint('[ApiClient] _doRefreshToken: step3 got response status=${resp.statusCode} in ${elapsed}ms');
      if (resp.statusCode == 200 && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final newToken = data['access_token'] as String?;
        debugPrint('[ApiClient] _doRefreshToken: step4 newToken=${newToken != null ? "yes(${newToken.length}chars)" : "no"}');
        if (newToken != null && newToken.isNotEmpty) {
          // 持久化新 token
          try {
            debugPrint('[ApiClient] _doRefreshToken: step5 persisting to SharedPreferences...');
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('access_token', newToken);
            debugPrint('[ApiClient] _doRefreshToken: step6 persisted OK');
          } catch (e) {
            debugPrint('[ApiClient] _doRefreshToken: step6 persist failed: $e');
          }
          debugPrint('[ApiClient] token refreshed (total ${DateTime.now().difference(t0).inMilliseconds}ms)');
          return newToken;
        }
        debugPrint('[ApiClient] _doRefreshToken: newToken was empty/null in response body');
      } else {
        debugPrint('[ApiClient] _doRefreshToken: non-200 status=${resp.statusCode}');
      }
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      debugPrint('[ApiClient] _doRefreshToken failed after ${elapsed}ms: $e');
    }
    return null;
  }

  /// 刷新失败后的统一清理：置空 token + 清除持久化 + 断开 WS
  static void _handleRefreshFailed() {
    debugPrint('[ApiClient] _handleRefreshFailed: clearing token (was=${token != null ? "set" : "null"})');
    final oldToken = token;
    token = null;
    debugPrint('[ApiClient] _handleRefreshFailed: disconnecting WS...');
    WebSocketService().disconnect();
    // 异步清除 SharedPreferences 中的过期 token
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString('access_token') == oldToken) {
          await prefs.remove('access_token');
          await prefs.remove('current_user_id');
          await prefs.remove('current_user_json');
          debugPrint('[ApiClient] _handleRefreshFailed: cleared expired token from prefs');
        } else {
          debugPrint('[ApiClient] _handleRefreshFailed: prefs token already different, skip');
        }
      } catch (e) {
        debugPrint('[ApiClient] _handleRefreshFailed: prefs cleanup error: $e');
      }
    }();
  }

  Future<ApiResponse<T>> get<T>(String path, {Map<String, dynamic>? params}) async {
    try {
      final resp = await _dio.get(path, queryParameters: params);
      return ApiResponse(success: true, data: resp.data as T?, statusCode: resp.statusCode);
    } on DioException catch (e) {
      return _handleError<T>(e);
    }
  }

  /// GET 请求（去重 + 限并发版）。
  ///
  /// 与 [get] 功能相同，但通过 [requestManager] 去重：
  /// - 同一个 path+params 组合只发一次请求，后续调用复用结果
  /// - 总并发数收 [requestManager.maxConcurrent] 限制
  ///
  /// [customKey] 可覆盖自动生成的 key，用于跨端点的去重需求。
  /// [priority] 优先级，值越大越优先（默认 0，预热请求用 -1）。
  Future<ApiResponse<T>> getDeduped<T>(String path, {Map<String, dynamic>? params, String? customKey, int priority = 0, bool bypassManager = false}) async {
    final key = customKey ?? _makeKey('GET', path, params);
    return requestManager.execute(
      key: key,
      task: () => get<T>(path, params: params),
      priority: priority,
      bypassManager: bypassManager,
    );
  }

  /// 生成请求去重 key。
  String _makeKey(String method, String path, Map<String, dynamic>? params) {
    if (params != null && params.isNotEmpty) {
      // 排序保证相同参数生成相同 key
      final sorted = Map.fromEntries(
        params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      final qs = sorted.entries.map((e) => '${e.key}=${e.value}').join('&');
      return '$method:$path?$qs';
    }
    return '$method:$path';
  }

  Future<ApiResponse<T>> post<T>(String path, {dynamic data}) async {
    return requestManager.throttle(() async {
      try {
        final resp = await _dio.post(path, data: data);
        return ApiResponse(success: true, data: resp.data as T?, statusCode: resp.statusCode);
      } on DioException catch (e) {
        return _handleError<T>(e);
      }
    });
  }

  Future<ApiResponse<T>> put<T>(String path, {dynamic data}) async {
    return requestManager.throttle(() async {
      try {
        final resp = await _dio.put(path, data: data);
        return ApiResponse(success: true, data: resp.data as T?, statusCode: resp.statusCode);
      } on DioException catch (e) {
        return _handleError<T>(e);
      }
    });
  }

  Future<ApiResponse<T>> delete<T>(String path) async {
    return requestManager.throttle(() async {
      try {
        final resp = await _dio.delete(path);
        return ApiResponse(success: true, data: resp.data as T?, statusCode: resp.statusCode);
      } on DioException catch (e) {
        return _handleError<T>(e);
      }
    });
  }

  /// 获取 COS 预签名上传 URL（从 XFile 提取文件名）
  Future<ApiResponse<Map<String, dynamic>>> _getCosPresignedUrl({
    required XFile file,
    required String type,
  }) async {
    final fileName = file.name;
    final fileExt = fileName.contains('.') ? fileName.split('.').last : '';
    return _getCosPresignedUrlFromName(fileName: fileName, fileExt: fileExt, type: type);
  }

  /// 获取 COS 预签名上传 URL（直接提供文件名和扩展名）
  Future<ApiResponse<Map<String, dynamic>>> _getCosPresignedUrlFromName({
    required String fileName,
    required String fileExt,
    required String type,
  }) async {
    final result = await post<Map<String, dynamic>>('/upload/presign', data: {
      'filename': fileName,
      'file_type': fileExt,
      'upload_type': type,
    });

    if (result.success && result.data != null) {
      return result;
    }
    return ApiResponse(success: false, message: '获取上传链接失败', statusCode: result.statusCode);
  }

  /// 直接上传文件到 COS（使用预签名 URL）
  ///
  /// [presignedUrl] COS 预签名 URL
  /// [file] XFile 对象
  /// [onSendProgress] 上传进度回调
  Future<ApiResponse<T>> _uploadToCosDirect<T>({
    required String presignedUrl,
    required XFile file,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final fileName = file.name;
      final contentType = _getContentType(fileName);

      // 使用 Dio 直接 PUT 到 COS
      final resp = await _dio.put(
        presignedUrl,
        data: bytes,
        options: Options(
          headers: {'Content-Type': contentType},
          // COS 预签名 URL 不需要额外的 Authorization
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
        onSendProgress: onSendProgress != null
            ? (sent, total) => onSendProgress(sent, total)
            : null,
      );

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        return ApiResponse(success: true, data: {'url': presignedUrl.split('?').first} as T?, statusCode: resp.statusCode);
      }
      return ApiResponse(success: false, message: 'COS 上传失败: ${resp.statusCode}', statusCode: resp.statusCode);
    } on DioException catch (e) {
      return _handleError<T>(e);
    }
  }

  /// 上传字节数组到 COS（使用预签名 URL）
  Future<ApiResponse<T>> _uploadBytesToCos<T>({
    required String presignedUrl,
    required List<int> bytes,
    required String fileName,
    void Function(int sent, int total)? onSendProgress,
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) async {
    try {
      final contentType = _getContentType(fileName);
      final isVideo = contentType.startsWith('video/');

      final resp = await _dio.put(
        presignedUrl,
        data: bytes,
        options: Options(
          headers: {'Content-Type': contentType},
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          // 视频上传需要更长超时：发送最多 5min，接收 3min
          sendTimeout: sendTimeout ?? (isVideo ? const Duration(minutes: 5) : null),
          receiveTimeout: receiveTimeout ?? (isVideo ? const Duration(minutes: 3) : null),
        ),
        onSendProgress: onSendProgress != null
            ? (sent, total) => onSendProgress(sent, total)
            : null,
      );

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        return ApiResponse(success: true, data: {'url': presignedUrl.split('?').first} as T?, statusCode: resp.statusCode);
      }
      return ApiResponse(success: false, message: 'COS 上传失败: ${resp.statusCode}', statusCode: resp.statusCode);
    } on DioException catch (e) {
      return _handleError<T>(e);
    }
  }

  /// 改造后的 upload 方法：先获取预签名 URL，再直传 COS
  ///
  /// [path] 后端接口路径（用于获取预签名 URL）
  /// [file] XFile 对象
  /// [extraData] 额外参数（兼容旧接口）
  /// [onSendProgress] 上传进度回调
  Future<ApiResponse<T>> upload<T>(String path, XFile file,
      {Map<String, dynamic>? extraData,
       void Function(int sent, int total)? onSendProgress}) async {
    try {
      final uploadType = _extractUploadType(path);
      final presignResp = await _getCosPresignedUrl(file: file, type: uploadType);
      return _handlePresignAndUpload<T>(
        path: path,
        presignResp: presignResp,
        uploadType: uploadType,
        onSendProgress: onSendProgress,
        cosUpload: (presignedUrl) => _uploadToCosDirect<T>(
          presignedUrl: presignedUrl,
          file: file,
          onSendProgress: onSendProgress,
        ),
        fileName: file.name,
      );
    } on DioException catch (e) {
      return _handleError<T>(e);
    }
  }

  /// 改造后的 uploadBytes 方法：先获取预签名 URL，再直传 COS
  Future<ApiResponse> uploadBytes(String path, List<int> bytes,
      String fileName, {String fileKey = 'file',
       void Function(int sent, int total)? onSendProgress}) async {
    try {
      final uploadType = _extractUploadType(path);
      final fileExt = fileName.contains('.') ? fileName.split('.').last : '';
      final presignResp = await _getCosPresignedUrlFromName(fileName: fileName, fileExt: fileExt, type: uploadType);
      return _handlePresignAndUpload(
        path: path,
        presignResp: presignResp,
        uploadType: uploadType,
        onSendProgress: onSendProgress,
        cosUpload: (presignedUrl) => _uploadBytesToCos(
          presignedUrl: presignedUrl,
          bytes: bytes,
          fileName: fileName,
          onSendProgress: onSendProgress,
        ),
        fileName: fileName,
      );
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// 公共方法：处理预签名 URL 获取结果 → 直传 COS → confirm 回调
  Future<ApiResponse<T>> _handlePresignAndUpload<T>({
    required String path,
    required ApiResponse<Map<String, dynamic>> presignResp,
    required String uploadType,
    required String fileName,
    void Function(int sent, int total)? onSendProgress,
    required Future<ApiResponse<T>> Function(String presignedUrl) cosUpload,
  }) async {
    if (!presignResp.success || presignResp.data == null) {
      return ApiResponse(success: false, message: presignResp.message ?? '获取上传链接失败');
    }

    final presignedUrl = presignResp.data!['upload_url'] as String? ?? presignResp.data!['presigned_url'] as String? ?? presignResp.data!['url'] as String? ?? '';
    if (presignedUrl.isEmpty) {
      debugPrint('_handlePresignAndUpload: presigned URL is empty. presignResp.data=${presignResp.data}');
      return ApiResponse(success: false, message: '上传服务暂不可用，请检查 COS 配置或稍后重试');
    }

    // 直传 COS
    final cosResp = await cosUpload(presignedUrl);

    // COS 上传成功后调用 /upload/confirm 通知后端
    if (cosResp.success) {
      final cosKey = presignResp.data!['cos_key'] as String? ?? '';
      var publicUrl = presignResp.data!['public_url'] as String? ?? '';

      if (cosKey.isNotEmpty) {
        try {
          final confirmResp = await post('/upload/confirm', data: {
            'cos_key': cosKey,
            'final_filename': fileName,
          });
          if (confirmResp.success && confirmResp.data != null && confirmResp.data['url'] != null) {
            publicUrl = confirmResp.data['url'] as String;
          }
        } catch (e) {
          debugPrint('Upload confirm failed: $e');
        }
      }

      // 兜底：如果 public_url 仍为空，使用预签名 URL 的基础地址（去掉查询参数）
      if (publicUrl.isEmpty) {
        publicUrl = presignedUrl.split('?').first;
        debugPrint('_handlePresignAndUpload: public_url is empty, fallback to presigned base URL: $publicUrl');
      }

      // 头像/封面需要调用专属 confirm 端点更新数据库
      if (uploadType == 'avatar') {
        try {
          await post('/upload/avatar/confirm', data: {'url': publicUrl});
        } catch (e) {
          debugPrint('Avatar confirm failed: $e');
        }
        return ApiResponse(
          success: true,
          data: {'avatar_url': publicUrl, 'url': publicUrl} as T?,
          statusCode: 200,
        );
      } else if (uploadType == 'cover') {
        try {
          await post('/upload/cover/confirm', data: {'url': publicUrl});
        } catch (e) {
          debugPrint('Cover confirm failed: $e');
        }
        return ApiResponse(
          success: true,
          data: {'cover_photo_url': publicUrl, 'url': publicUrl} as T?,
          statusCode: 200,
        );
      }

      return ApiResponse(
        success: true,
        data: {'url': publicUrl} as T?,
        statusCode: 200,
      );
    }

    return cosResp;
  }

  /// 从路径中提取上传类型（与后端 upload_type: avatar/cover/post/comic 对齐）
  String _extractUploadType(String path) {
    if (path.contains('avatar')) return 'avatar';
    if (path.contains('cover')) return 'cover';
    if (path.contains('comic')) return 'comic';
    if (path.contains('post')) return 'post';
    // 通用图片/视频上传默认走 post 类型
    return 'post';
  }

  /// 根据文件名获取 Content-Type
  String _getContentType(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  ApiResponse<T> _handleError<T>(DioException e) {
    final data = e.response?.data;
    String? msg;
    if (data is Map) {
      // FastAPI returns errors with 'detail' field
      final detail = data['detail'];
      if (detail is String) {
        msg = detail;
      } else if (detail is List && detail.isNotEmpty) {
        // Pydantic validation errors: [{loc, msg, type}, ...]
        final first = detail[0];
        if (first is Map) {
          msg = (first['msg'] ?? first.toString()).toString();
        } else {
          msg = detail.toString();
        }
      }
      msg ??= data['message']?.toString();
    }
    msg ??= e.message ?? 'Network error';
    return ApiResponse(success: false, message: msg, statusCode: e.response?.statusCode);
  }
}
