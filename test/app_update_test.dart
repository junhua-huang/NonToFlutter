import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/app_update.dart';
import 'package:nonto/providers/app_update_notifier.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/app_update_service.dart';
import 'package:nonto/services/app_runtime_info.dart';
import 'package:nonto/services/external_link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(ApiClient.resetTestHooks);

  group('AppUpdateInfo', () {
    test('parses and normalizes a valid update response', () {
      final info = AppUpdateInfo.fromJson(<String, dynamic>{
        'platform': ' android ',
        'channel': ' stable ',
        'release_id': 42,
        'latest_version': ' 1.4.0 ',
        'latest_build_number': 140,
        'minimum_supported_build_number': 120,
        'update_available': true,
        'force_update': false,
        'update_action': ' download ',
        'download_url': ' https://download.example.test/nonto.apk ',
        'release_notes': <Object>[' First change ', '', 7, 'Second change'],
        'published_at': '2026-09-04T08:30:00Z',
        'sha256': ' abc123 ',
        'file_size': 2048.0,
      });

      expect(info.platform, 'android');
      expect(info.channel, 'stable');
      expect(info.releaseId, 42);
      expect(info.latestVersion, '1.4.0');
      expect(info.latestBuildNumber, 140);
      expect(info.minimumSupportedBuildNumber, 120);
      expect(info.isOptional, isTrue);
      expect(info.isRequired, isFalse);
      expect(info.updateAction, 'download');
      expect(info.downloadUrl, 'https://download.example.test/nonto.apk');
      expect(info.releaseNotes, <String>['First change', 'Second change']);
      expect(info.publishedAt, DateTime.utc(2026, 9, 4, 8, 30));
      expect(info.sha256, 'abc123');
      expect(info.fileSize, 2048);
    });

    test('derives optional and required states from the update flags', () {
      final optional = AppUpdateInfo.fromJson(<String, dynamic>{
        'update_available': true,
        'force_update': false,
      });
      final required = AppUpdateInfo.fromJson(<String, dynamic>{
        'update_available': true,
        'force_update': true,
      });
      final current = AppUpdateInfo.fromJson(<String, dynamic>{
        'update_available': false,
        'force_update': true,
      });

      expect(optional.isOptional, isTrue);
      expect(required.isRequired, isTrue);
      expect(current.updateAvailable, isFalse);
      expect(current.forceUpdate, isFalse);
      expect(current.isOptional, isFalse);
      expect(current.isRequired, isFalse);
    });

    test('rejects responses without a boolean update_available contract', () {
      expect(
        () => AppUpdateInfo.fromJson(<String, dynamic>{}),
        throwsFormatException,
      );
      expect(
        () => AppUpdateInfo.fromJson(<String, dynamic>{
          'update_available': 'true',
        }),
        throwsFormatException,
      );
    });
  });

  group('AppUpdateService', () {
    test('sends client identity and accepts an explicit no-update response',
        () async {
      final adapter = _UpdateApiAdapter(
        statusCode: 200,
        body: <String, dynamic>{
          'platform': 'android',
          'channel': 'stable',
          'update_available': false,
          'force_update': false,
        },
      );
      final service = _serviceFor(adapter);

      final info = await service.check();

      expect(info.updateAvailable, isFalse);
      expect(adapter.lastRequest?.path, '/app/version');
      expect(
        adapter.lastRequest?.queryParameters,
        containsPair('platform', 'android'),
      );
      expect(
        adapter.lastRequest?.queryParameters,
        containsPair('channel', 'stable'),
      );
      expect(
        adapter.lastRequest?.queryParameters,
        containsPair('current_version', '1.3.2'),
      );
      expect(
        adapter.lastRequest?.queryParameters,
        containsPair('current_build_number', 132),
      );
    });

    test('rejects a successful but malformed response', () async {
      final service = _serviceFor(
        _UpdateApiAdapter(statusCode: 200, body: <String, dynamic>{}),
      );

      await expectLater(service.check(), throwsFormatException);
    });

    test('does not convert an unsuccessful response into no update', () async {
      final service = _serviceFor(
        _UpdateApiAdapter(
          statusCode: 503,
          body: <String, dynamic>{'detail': 'temporarily unavailable'},
        ),
      );

      await expectLater(
        service.check(),
        throwsA(isA<AppUpdateCheckException>()),
      );
    });
  });

  group('AppUpdateNotifier', () {
    test('marks an unsuccessful API check as failed, not up to date', () async {
      final service = _serviceFor(
        _UpdateApiAdapter(
          statusCode: 503,
          body: <String, dynamic>{'detail': 'temporarily unavailable'},
        ),
      );
      final notifier = AppUpdateNotifier(service);
      addTearDown(notifier.dispose);

      final result = await notifier.check();

      expect(result, AppUpdateInfo.none);
      expect(notifier.state.status, AppUpdateStatus.failed);
      expect(notifier.state.status, isNot(AppUpdateStatus.upToDate));
      expect(notifier.state.shouldPresent, isFalse);
      expect(notifier.state.error, isNotEmpty);
    });

    test('suppresses only the dismissed optional release on automatic checks',
        () async {
      var response = _updateInfo(releaseId: 41);
      final service = _StubAppUpdateService(() async => response);
      final notifier = AppUpdateNotifier(service);
      addTearDown(notifier.dispose);

      await notifier.check();
      await notifier.dismissOptional();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('app_update_dismissed_release_id'), 41);

      await notifier.check(automatic: true);
      expect(notifier.state.status, AppUpdateStatus.available);
      expect(notifier.state.suppressOptional, isTrue);
      expect(notifier.state.shouldPresent, isFalse);

      await prefs.setInt(
        'app_update_last_automatic_check_at',
        DateTime.now()
            .subtract(const Duration(hours: 25))
            .millisecondsSinceEpoch,
      );
      response = _updateInfo(releaseId: 42);
      await notifier.check(automatic: true);

      expect(notifier.state.suppressOptional, isFalse);
      expect(notifier.state.shouldPresent, isTrue);
    });

    test('a dismissed release id never suppresses a required update', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_update_dismissed_release_id': 41,
      });
      final notifier = AppUpdateNotifier(
        _StubAppUpdateService(
          () async => _updateInfo(releaseId: 41, forceUpdate: true),
        ),
      );
      addTearDown(notifier.dispose);

      await notifier.check(automatic: true);

      expect(notifier.state.info.isRequired, isTrue);
      expect(notifier.state.suppressOptional, isFalse);
      expect(notifier.state.shouldPresent, isTrue);
    });

    test('deduplicates concurrent update checks', () async {
      final result = Completer<AppUpdateInfo>();
      final service = _StubAppUpdateService(() => result.future);
      final notifier = AppUpdateNotifier(service);
      addTearDown(notifier.dispose);

      final first = notifier.check();
      final second = notifier.check();

      expect(service.calls, 1);
      expect(notifier.state.status, AppUpdateStatus.checking);

      final info = _updateInfo(releaseId: 51);
      result.complete(info);
      expect(await first, same(info));
      expect(await second, same(info));
      expect(service.calls, 1);
      expect(notifier.state.status, AppUpdateStatus.available);
    });
  });

  group('ExternalLinkService', () {
    test('opens only absolute HTTPS URLs', () async {
      final launched = <Uri>[];
      final service = ExternalLinkService(
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      );

      expect(await service.open(null), isFalse);
      expect(await service.open(''), isFalse);
      expect(
          await service.open('http://download.example.test/app.apk'), isFalse);
      expect(await service.open('https:///missing-host.apk'), isFalse);
      expect(
        await service.open(' https://download.example.test/app.apk '),
        isTrue,
      );
      expect(
        launched,
        <Uri>[Uri.parse('https://download.example.test/app.apk')],
      );
    });

    test('refresh action reloads the current page without launching a URL',
        () async {
      var refreshCalls = 0;
      var launchCalls = 0;
      final service = ExternalLinkService(
        pageRefresher: () async {
          refreshCalls += 1;
          return true;
        },
        launcher: (_) async {
          launchCalls += 1;
          return true;
        },
      );

      expect(
        await service.perform(
          action: ' refresh ',
          url: 'https://nonto.example.test',
        ),
        isTrue,
      );
      expect(refreshCalls, 1);
      expect(launchCalls, 0);
    });

    test('refresh action falls back to a safe HTTPS URL', () async {
      final launched = <Uri>[];
      final service = ExternalLinkService(
        pageRefresher: () async => false,
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      );

      expect(
        await service.perform(
          action: 'refresh',
          url: 'https://nonto.example.test/releases/latest',
        ),
        isTrue,
      );
      expect(
        launched,
        <Uri>[Uri.parse('https://nonto.example.test/releases/latest')],
      );
    });

    test('contains launcher failures', () async {
      final service = ExternalLinkService(
        launcher: (_) => throw StateError('launcher unavailable'),
      );

      expect(
          await service.open('https://download.example.test/app.apk'), isFalse);
    });
  });
}

AppUpdateService _serviceFor(_UpdateApiAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
    ..httpClientAdapter = adapter;
  return AppUpdateService(
    api: ApiClient.test(dio: dio),
    runtimeInfo: const AppRuntimeInfo(version: '1.3.2', buildNumber: 132),
    platform: 'android',
  );
}

AppUpdateInfo _updateInfo({required int releaseId, bool forceUpdate = false}) {
  return AppUpdateInfo(
    platform: 'android',
    channel: 'stable',
    releaseId: releaseId,
    latestVersion: '1.4.0',
    latestBuildNumber: 140,
    minimumSupportedBuildNumber: forceUpdate ? 139 : 100,
    updateAvailable: true,
    forceUpdate: forceUpdate,
    updateAction: 'download',
    downloadUrl: 'https://download.example.test/nonto.apk',
    releaseNotes: const <String>['Update available'],
    publishedAt: DateTime.utc(2026, 9, 4),
    sha256: null,
    fileSize: null,
  );
}

class _StubAppUpdateService extends AppUpdateService {
  _StubAppUpdateService(this._check) : super(platform: 'android');

  final Future<AppUpdateInfo> Function() _check;
  int calls = 0;

  @override
  Future<AppUpdateInfo> check({String channel = 'stable'}) {
    calls += 1;
    return _check();
  }
}

class _UpdateApiAdapter implements HttpClientAdapter {
  _UpdateApiAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Object body;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}
