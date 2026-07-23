import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/api/api_client.dart';

void main() {
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
}
