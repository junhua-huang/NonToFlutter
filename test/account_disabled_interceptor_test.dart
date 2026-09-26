import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    ApiClient.resetTestHooks();
  });

  test('ACCOUNT_DISABLED clears session without refresh', () async {
    final harness = await AccountDisabledDioHarness.create();

    final response = await harness.client.get('/auth/me');
    await Future<void>.delayed(Duration.zero);

    expect(response.success, isFalse);
    expect(response.errorCode, ApiErrorCodes.accountDisabled);
    expect(response.isRetryable, isFalse);
    expect(harness.refreshCalls, 0);
    expect(harness.tokenExpiredCalls, 1);
    expect(harness.loggedOutTransitions, 1);
    expect(ApiClient.token, isNull);
    expect(harness.prefs.containsKey('access_token'), isFalse);
    expect(harness.prefs.containsKey('current_user_id'), isFalse);
    expect(harness.tokenClearedCalls, 1);
  });

  test('disabled cleanup does not delete a new persisted session', () async {
    final harness = await AccountDisabledDioHarness.create();
    ApiClient.onTokenCleared = () async {
      harness.tokenClearedCalls += 1;
      ApiClient.setToken('new-token');
      await harness.prefs.setString('access_token', 'new-token');
      await harness.prefs.setString('current_user_id', '9');
      await harness.prefs.setString('current_user_json', '{"id":9}');
    };

    await harness.client.get('/auth/me');
    await Future<void>.delayed(Duration.zero);

    expect(ApiClient.token, 'new-token');
    expect(harness.prefs.getString('access_token'), 'new-token');
    expect(harness.prefs.getString('current_user_id'), '9');
    expect(harness.prefs.getString('current_user_json'), '{"id":9}');
  });

  test('disabled cleanup does not notify logout for newly persisted session',
      () async {
    final harness = await AccountDisabledDioHarness.create();
    ApiClient.onTokenCleared = () async {
      harness.tokenClearedCalls += 1;
      await harness.prefs.setString('access_token', 'new-token');
      await harness.prefs.setString('current_user_id', '9');
      await harness.prefs.setString('current_user_json', '{"id":9}');
    };
    ApiClient.onTokenExpired = () async {
      harness.tokenExpiredCalls += 1;
      await harness.prefs.remove('access_token');
      await harness.prefs.remove('current_user_id');
      await harness.prefs.remove('current_user_json');
    };

    await harness.client.get('/auth/me');
    await Future<void>.delayed(Duration.zero);

    expect(harness.tokenExpiredCalls, 0);
    expect(harness.prefs.getString('access_token'), 'new-token');
    expect(harness.prefs.getString('current_user_id'), '9');
    expect(harness.prefs.getString('current_user_json'), '{"id":9}');
  });

  test('stale ACCOUNT_DISABLED response does not clear a newer token',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'access_token': 'expired-token',
      'current_user_id': '7',
      'current_user_json': '{"id":7}',
    });
    final prefs = await SharedPreferences.getInstance();
    ApiClient.token = 'expired-token';

    final apiDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
    apiDio.httpClientAdapter = LoginRaceJsonAdapter(prefs: prefs);
    final refreshAdapter = CountingAdapter(
      statusCode: 200,
      body: {'access_token': 'refresh-token'},
    );
    final refreshDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
    refreshDio.httpClientAdapter = refreshAdapter;
    final client = ApiClient.test(dio: apiDio, refreshDio: refreshDio);
    var tokenExpiredCalls = 0;
    var tokenClearedCalls = 0;
    ApiClient.onTokenCleared = () async {
      tokenClearedCalls += 1;
    };
    ApiClient.onTokenExpired = () async {
      tokenExpiredCalls += 1;
      await prefs.remove('access_token');
      await prefs.remove('current_user_id');
      await prefs.remove('current_user_json');
    };

    final response = await client.get('/auth/me');
    await Future<void>.delayed(Duration.zero);

    expect(response.errorCode, ApiErrorCodes.accountDisabled);
    expect(refreshAdapter.calls, 0);
    expect(tokenClearedCalls, 0);
    expect(tokenExpiredCalls, 0);
    expect(ApiClient.token, 'new-token');
    expect(prefs.getString('access_token'), 'new-token');
    expect(prefs.getString('current_user_id'), '9');
    expect(prefs.getString('current_user_json'), '{"id":9}');
  });

  test('repeated ACCOUNT_DISABLED responses notify logout once', () async {
    final harness = await AccountDisabledDioHarness.create();

    await harness.client.get('/auth/me');
    await harness.client.get('/auth/me');
    await Future<void>.delayed(Duration.zero);

    expect(harness.refreshCalls, 0);
    expect(harness.tokenExpiredCalls, 1);
    expect(harness.loggedOutTransitions, 1);
    expect(ApiClient.token, isNull);
  });
}

class AccountDisabledDioHarness {
  AccountDisabledDioHarness._({
    required this.client,
    required this.prefs,
    required this.refreshAdapter,
  });

  final ApiClient client;
  final SharedPreferences prefs;
  final CountingAdapter refreshAdapter;
  int tokenExpiredCalls = 0;
  int loggedOutTransitions = 0;
  int tokenClearedCalls = 0;

  int get refreshCalls => refreshAdapter.calls;

  static Future<AccountDisabledDioHarness> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'access_token': 'expired-token',
      'current_user_id': '7',
      'current_user_json': '{"id":7}',
    });
    final prefs = await SharedPreferences.getInstance();
    ApiClient.token = 'expired-token';

    final apiDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
    apiDio.httpClientAdapter = StaticJsonAdapter(
      statusCode: 403,
      body: {
        'detail': {
          'code': ApiErrorCodes.accountDisabled,
          'message': '账号已停用',
          'retryable': false,
        },
      },
    );

    final refreshAdapter = CountingAdapter(
      statusCode: 200,
      body: {'access_token': 'new-token'},
    );
    final refreshDio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
    refreshDio.httpClientAdapter = refreshAdapter;

    late final AccountDisabledDioHarness harness;
    harness = AccountDisabledDioHarness._(
      client: ApiClient.test(dio: apiDio, refreshDio: refreshDio),
      prefs: prefs,
      refreshAdapter: refreshAdapter,
    );
    ApiClient.onTokenCleared = () async {
      harness.tokenClearedCalls += 1;
    };
    ApiClient.onTokenExpired = () {
      harness.tokenExpiredCalls += 1;
      harness.loggedOutTransitions += 1;
    };
    return harness;
  }
}

class StaticJsonAdapter implements HttpClientAdapter {
  StaticJsonAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Object body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = utf8.encode(jsonEncode(body));
    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class LoginRaceJsonAdapter implements HttpClientAdapter {
  LoginRaceJsonAdapter({required this.prefs});

  final SharedPreferences prefs;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ApiClient.setToken('new-token');
    await prefs.setString('access_token', 'new-token');
    await prefs.setString('current_user_id', '9');
    await prefs.setString('current_user_json', '{"id":9}');
    final bytes = utf8.encode(jsonEncode({
      'detail': {
        'code': ApiErrorCodes.accountDisabled,
        'message': '账号已停用',
        'retryable': false,
      },
    }));
    return ResponseBody.fromBytes(
      bytes,
      403,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class CountingAdapter extends StaticJsonAdapter {
  CountingAdapter({required super.statusCode, required super.body});

  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls += 1;
    return super.fetch(options, requestStream, cancelFuture);
  }
}
