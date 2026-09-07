import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/models/deployment.dart';

class DeploymentFailure implements Exception {
  final int? status;
  const DeploymentFailure([this.status]);
  bool get denied => status == 401 || status == 403;
  String get message => switch (status) {
        401 => '登录已失效，请重新登录。',
        403 => '无部署权限。仅允许服务器授权名单中的账号访问。',
        409 => '任务状态冲突，请刷新后检查服务器任务。',
        413 => '发布包超过服务器上传限制。',
        400 || 422 => '服务器拒绝此操作，请检查发布包和确认信息。',
        _ => '连接失败或服务器暂不可用。请刷新核对任务，勿重复提交。',
      };
  @override
  String toString() => 'DeploymentFailure($status)';
}

/// Dedicated transport: never uses ApiClient, query credentials, or logging.
class DeploymentService {
  final String? Function() readToken;
  final Dio _dio;
  final CancelToken _cancel = CancelToken();
  DeploymentService({required this.readToken, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl:
                  '${AppConfig.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/admin/deployments',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: false,
            ));

  Future<Map<String, dynamic>> _request(String path,
      {String method = 'GET', Object? data, ProgressCallback? progress}) async {
    final token = readToken();
    if (token == null || token.isEmpty || _cancel.isCancelled) {
      throw const DeploymentFailure(401);
    }
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        cancelToken: _cancel,
        onSendProgress: progress,
        options: Options(
            method: method,
            headers: {'Authorization': 'Bearer $token'},
            followRedirects: false),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      throw DeploymentFailure(error.response?.statusCode);
    }
  }

  Future<DeploymentCapabilities> capabilities() async =>
      DeploymentCapabilities.fromJson(await _request('/capabilities'));
  Future<DeploymentPage<DeploymentArtifact>> artifacts() async {
    final json = await _request('/artifacts');
    return DeploymentPage(
        (json['items'] as List)
            .map((e) => DeploymentArtifact.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        (json['total'] as num).toInt());
  }

  Future<DeploymentPage<DeploymentJob>> jobs() async {
    final json = await _request('');
    return DeploymentPage(
        (json['items'] as List)
            .map((e) =>
                DeploymentJob.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        (json['total'] as num).toInt());
  }

  Future<DeploymentActive> active() async =>
      DeploymentActive.fromJson(await _request('/active'));
  Future<DeploymentJob> job(String id) async =>
      DeploymentJob.fromJson(await _request('/${Uri.encodeComponent(id)}'));
  Future<DeploymentArtifact> upload(
          {required Uint8List manifest,
          required Uint8List bundle,
          required String reason,
          ProgressCallback? progress}) async =>
      DeploymentArtifact.fromJson(await _request('/artifacts',
          method: 'POST',
          progress: progress,
          data: FormData.fromMap({
            'manifest': MultipartFile.fromBytes(manifest,
                filename: 'manifest.json',
                contentType: DioMediaType('application', 'json')),
            'bundle': MultipartFile.fromBytes(bundle,
                filename: 'bundle.tar.gz',
                contentType: DioMediaType('application', 'gzip')),
            'reason': reason,
          })));
  Future<DeploymentJob> create(
          {required String artifactId,
          required String operation,
          required String reason,
          required String idempotencyKey}) async =>
      DeploymentJob.fromJson(await _request('', method: 'POST', data: {
        'artifact_id': artifactId,
        'operation': operation,
        'reason': reason,
        'idempotency_key': idempotencyKey
      }));
  Future<DeploymentJob> approve(String id,
          {required String reason,
          required bool migrationConfirmed,
          required bool schemaCompatible}) async =>
      DeploymentJob.fromJson(await _request(
          '/${Uri.encodeComponent(id)}/approve',
          method: 'POST',
          data: {
            'reason': reason,
            'migration_confirmed': migrationConfirmed,
            'schema_compatible': schemaCompatible
          }));
  Future<DeploymentJob> cancel(String id, {required String reason}) async =>
      DeploymentJob.fromJson(await _request(
          '/${Uri.encodeComponent(id)}/cancel',
          method: 'POST',
          data: {'reason': reason}));
  void dispose() {
    _cancel.cancel();
    _dio.close(force: true);
  }
}
