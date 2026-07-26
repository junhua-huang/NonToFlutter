import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/api/api_client.dart';

void main() {
  tearDown(() {
    ApiClient.resetTestHooks();
  });

  test('parses FastAPI structured detail', () {
    final response = ApiClient.parseErrorResponse(
      statusCode: 422,
      data: {
        'detail': {
          'code': 'CONTENT_REJECTED',
          'message': '内容未通过审核',
          'retryable': false,
        },
      },
    );

    expect(response.success, isFalse);
    expect(response.errorCode, 'CONTENT_REJECTED');
    expect(response.message, '内容未通过审核');
    expect(response.isRetryable, isFalse);
  });

  test('moderation unavailable is retryable', () {
    final response = ApiClient.parseErrorResponse(
      statusCode: 503,
      data: {
        'detail': {
          'code': 'MODERATION_UNAVAILABLE',
          'message': '内容审核服务暂不可用，请稍后重试',
          'retryable': true,
        },
      },
    );

    expect(response.errorCode, 'MODERATION_UNAVAILABLE');
    expect(response.isRetryable, isTrue);
  });

  test('locked moderation retryability overrides malformed server values', () {
    expect(
      ApiClient.parseErrorResponse(
        statusCode: 422,
        data: {
          'detail': {
            'code': 'CONTENT_REJECTED',
            'message': 'bad',
            'retryable': true,
          },
        },
      ).isRetryable,
      isFalse,
    );
    expect(
      ApiClient.parseErrorResponse(
        statusCode: 503,
        data: {
          'detail': {
            'code': 'MODERATION_UNAVAILABLE',
            'message': 'bad',
            'retryable': false,
          },
        },
      ).isRetryable,
      isTrue,
    );
  });

  test('disabled account is a terminal 403 failure', () {
    final response = ApiClient.parseErrorResponse(
      statusCode: 403,
      data: {
        'detail': {
          'code': 'ACCOUNT_DISABLED',
          'message': '账号已停用',
          'retryable': false,
        },
      },
    );

    expect(response.errorCode, 'ACCOUNT_DISABLED');
    expect(response.isRetryable, isFalse);
  });

  test('legacy string and pydantic list details stay compatible', () {
    expect(
      ApiClient.parseErrorResponse(statusCode: 400, data: {'detail': 'bad'})
          .message,
      'bad',
    );
    expect(
      ApiClient.parseErrorResponse(
        statusCode: 422,
        data: {
          'detail': [
            {'msg': 'invalid'},
          ],
        },
      ).message,
      'invalid',
    );
  });

  test('request path logging redacts signed URLs', () {
    expect(
      ApiClient.safeRequestPathForLog(
        'https://cos.invalid/private.png?X-Amz-Signature=SECRET&token=SECRET',
      ),
      'https://cos.invalid/...',
    );
    expect(ApiClient.safeRequestPathForLog('/auth/me'), '/auth/me');
  });

  test('unknown server errors are retryable by default', () {
    final response = ApiClient.parseErrorResponse(
      statusCode: 500,
      data: {'detail': 'temporary'},
    );

    expect(response.errorCode, isNull);
    expect(response.isRetryable, isTrue);
  });

  test('upload confirm sends final cos filename field', () async {
    final adapter = UploadConfirmContractAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = adapter;
    final client = ApiClient.test(dio: dio);

    final response = await client.uploadBytes(
      '/upload/post/image',
      Uint8List.fromList([1, 2, 3]),
      'picked.png',
    );

    expect(response.success, isTrue);
    expect(adapter.confirmBody?['cos_key'], 'uploads/post.png');
    expect(adapter.confirmBody?['final_filename'], 'post.png');
  });

  test('upload emits safe diagnostic logs for each stage', () async {
    final adapter = UploadConfirmContractAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = adapter;
    final client = ApiClient.test(dio: dio);
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    await client.uploadBytes(
      '/upload/post/image',
      Uint8List.fromList([1, 2, 3]),
      'picked.png',
    );

    expect(
      logs,
      containsAll(<Matcher>[
        contains('[Upload] presign start'),
        contains('[Upload] presign ok'),
        contains('[Upload] cos put start'),
        contains('[Upload] cos put ok'),
        contains('[Upload] confirm start'),
        contains('[Upload] confirm ok'),
      ]),
    );
    expect(logs.join('\n'), isNot(contains('signature=secret')));
  });

  test('generic upload confirm failure returns failed structured response',
      () async {
    final adapter = UploadConfirmFailureAdapter(
      confirmPath: '/upload/confirm',
      failureStatus: 422,
      failureCode: ApiErrorCodes.contentRejected,
      failureMessage: 'regex threshold hit term: badword',
      failureRetryable: false,
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = adapter;
    final client = ApiClient.test(dio: dio);

    final response = await client.uploadBytes(
      '/posts/upload',
      Uint8List.fromList([1, 2, 3]),
      'blocked.png',
    );

    expect(response.success, isFalse);
    expect(response.statusCode, 422);
    expect(response.errorCode, ApiErrorCodes.contentRejected);
    expect(response.isRetryable, isFalse);
    expect(response.message, '内容未通过审核');
    expect(adapter.calls, containsAll(['/upload/presign', '/upload/confirm']));
  });

  test('avatar upload confirm failure returns failed structured response',
      () async {
    final adapter = UploadConfirmFailureAdapter(
      confirmPath: '/upload/avatar/confirm',
      failureStatus: 503,
      failureCode: ApiErrorCodes.moderationUnavailable,
      failureMessage: 'regex threshold service unavailable',
      failureRetryable: true,
      uploadType: 'avatar',
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = adapter;
    final client = ApiClient.test(dio: dio);

    final response = await client.uploadBytes(
      '/upload/avatar',
      Uint8List.fromList([1, 2, 3]),
      'avatar.png',
    );

    expect(response.success, isFalse);
    expect(response.statusCode, 503);
    expect(response.errorCode, ApiErrorCodes.moderationUnavailable);
    expect(response.isRetryable, isTrue);
    expect(response.message, '内容审核服务暂不可用，请稍后重试');
    expect(adapter.calls,
        containsAll(['/upload/presign', '/upload/avatar/confirm']));
  });

  test('cover upload confirm failure returns failed structured response',
      () async {
    final adapter = UploadConfirmFailureAdapter(
      confirmPath: '/upload/cover/confirm',
      failureStatus: 429,
      failureCode: 'RATE_LIMITED',
      failureMessage: '请稍后再试',
      failureRetryable: true,
      uploadType: 'cover',
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'))
      ..httpClientAdapter = adapter;
    final client = ApiClient.test(dio: dio);

    final response = await client.uploadBytes(
      '/upload/cover',
      Uint8List.fromList([1, 2, 3]),
      'cover.png',
    );

    expect(response.success, isFalse);
    expect(response.statusCode, 429);
    expect(response.errorCode, 'RATE_LIMITED');
    expect(response.isRetryable, isTrue);
    expect(response.message, '请稍后再试');
    expect(adapter.calls,
        containsAll(['/upload/presign', '/upload/cover/confirm']));
  });
}

class UploadConfirmContractAdapter implements HttpClientAdapter {
  Map<String, dynamic>? confirmBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/upload/presign') {
      return _jsonResponse(200, {
        'upload_url': 'https://cos.invalid/uploads/post.png?signature=secret',
        'cos_key': 'uploads/post.png',
        'public_url': 'https://cdn.invalid/uploads/post.png',
      });
    }
    if (options.path.startsWith('https://cos.invalid/')) {
      return ResponseBody.fromBytes(<int>[], 204);
    }
    if (options.path == '/upload/confirm') {
      confirmBody = options.data as Map<String, dynamic>?;
      if (confirmBody?['final_filename'] != 'post.png') {
        return _jsonResponse(422, {'detail': 'Upload confirmation failed'});
      }
      return _jsonResponse(
          200, {'url': 'https://cdn.invalid/uploads/post.png'});
    }
    return _jsonResponse(404, {'detail': 'unexpected ${options.path}'});
  }

  ResponseBody _jsonResponse(int statusCode, Object body) {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class UploadConfirmFailureAdapter implements HttpClientAdapter {
  UploadConfirmFailureAdapter({
    required this.confirmPath,
    required this.failureStatus,
    required this.failureCode,
    required this.failureMessage,
    required this.failureRetryable,
    this.uploadType = 'post',
  });

  final String confirmPath;
  final int failureStatus;
  final String failureCode;
  final String failureMessage;
  final bool failureRetryable;
  final String uploadType;
  final List<String> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options.path);
    if (options.path == '/upload/presign') {
      return _jsonResponse(200, {
        'upload_url':
            'https://cos.invalid/uploads/$uploadType.png?signature=secret',
        'cos_key': 'uploads/$uploadType.png',
        'public_url': 'https://cdn.invalid/uploads/$uploadType.png',
      });
    }
    if (options.path.startsWith('https://cos.invalid/')) {
      return ResponseBody.fromBytes(<int>[], 204);
    }
    if (options.path == confirmPath) {
      return _jsonResponse(failureStatus, {
        'detail': {
          'code': failureCode,
          'message': failureMessage,
          'retryable': failureRetryable,
        },
      });
    }
    if (options.path == '/upload/confirm') {
      return _jsonResponse(200, {
        'url': 'https://cdn.invalid/uploads/$uploadType.png',
      });
    }
    return _jsonResponse(404, {'detail': 'unexpected ${options.path}'});
  }

  ResponseBody _jsonResponse(int statusCode, Object body) {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
