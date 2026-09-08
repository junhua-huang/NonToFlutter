import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/deployment.dart';
import 'package:nonto/providers/deployment_providers.dart';
import 'package:nonto/screens/profile/deployments_screen.dart';
import 'package:nonto/services/api/deployment_service.dart';
import 'package:nonto/services/deployment_file_picker.dart';

const artifact = DeploymentArtifact(
    id: 'a1',
    releaseId: 'release-1',
    version: '1.2.3',
    buildNumber: '4',
    components: ['backend']);
DeploymentJob jobWith(String status) => DeploymentJob(
        id: 'job-1',
        artifactId: 'a1',
        operation: 'deploy',
        status: status,
        phase: 'check',
        components: [
          'backend'
        ],
        events: const [
          DeploymentEvent(phase: 'check', message: 'Checked package')
        ]);
final testSession = StateProvider<({String? token, String? userId})>(
    (ref) => (token: 'session-one', userId: '1'));

class FakeDeploymentService extends DeploymentService {
  FakeDeploymentService() : super(readToken: () => 'test');
  DeploymentCapabilities capability = const DeploymentCapabilities(
      enabled: true, canDeploy: true, canConfigure: true);
  DeploymentSettings settingsValue = const DeploymentSettings(
      enabled: true,
      operatorIds: [1],
      maxBytes: 524288000,
      maxExpandedBytes: 1073741824,
      maxFiles: 10000,
      workerStatus: 'idle',
      workerOnline: true,
      readiness: {
        'artifact_storage': true,
        'database': true,
        'worker_configuration': true,
      });
  Completer<DeploymentCapabilities>? capabilityWait;
  DeploymentFailure? failure;
  DeploymentJob? currentJob;
  Completer<DeploymentActive>? activeWait;
  int activeCalls = 0;
  int artifactCalls = 0;
  int createCalls = 0;
  int approvalCalls = 0;
  int cancelCalls = 0;
  int uploadCalls = 0;
  int settingsCalls = 0;
  int saveSettingsCalls = 0;
  int reloadSettingsCalls = 0;
  String? operation;
  String? reason;
  String? idempotencyKey;
  bool? migration;
  bool? schema;
  @override
  Future<DeploymentCapabilities> capabilities() async {
    if (failure != null) throw failure!;
    return capabilityWait == null ? capability : await capabilityWait!.future;
  }

  @override
  Future<DeploymentSettings> health() async {
    settingsCalls++;
    return settingsValue;
  }

  @override
  Future<DeploymentSettings> patchSettings(
      {required bool enabled,
      required List<int> operatorIds,
      required int maxBytes,
      required int maxExpandedBytes,
      required int maxFiles,
      required String reason}) async {
    saveSettingsCalls++;
    return settingsValue = DeploymentSettings(
        enabled: enabled,
        operatorIds: operatorIds,
        maxBytes: maxBytes,
        maxExpandedBytes: maxExpandedBytes,
        maxFiles: maxFiles,
        workerStatus: settingsValue.workerStatus,
        workerOnline: settingsValue.workerOnline,
        readiness: settingsValue.readiness);
  }

  @override
  Future<DeploymentSettings> reloadSettings(String reason) async {
    reloadSettingsCalls++;
    return settingsValue;
  }

  @override
  Future<DeploymentPage<DeploymentArtifact>> artifacts() async {
    artifactCalls++;
    return const DeploymentPage([artifact], 1);
  }

  @override
  Future<DeploymentPage<DeploymentJob>> jobs() async => DeploymentPage(
      currentJob == null ? [] : [currentJob!], currentJob == null ? 0 : 1);
  @override
  Future<DeploymentActive> active() async {
    activeCalls++;
    return activeWait == null
        ? DeploymentActive(job: currentJob, release: artifact)
        : await activeWait!.future;
  }

  @override
  Future<DeploymentJob> job(String id) async => currentJob!;
  @override
  Future<DeploymentJob> create(
      {required String artifactId,
      required String operation,
      required String reason,
      required String idempotencyKey}) async {
    createCalls++;
    this.operation = operation;
    this.reason = reason;
    this.idempotencyKey = idempotencyKey;
    return currentJob = jobWith('awaiting_approval');
  }

  @override
  Future<DeploymentJob> approve(String id,
      {required String reason,
      required bool migrationConfirmed,
      required bool schemaCompatible}) async {
    approvalCalls++;
    migration = migrationConfirmed;
    schema = schemaCompatible;
    this.reason = reason;
    return currentJob = jobWith('running');
  }

  @override
  Future<DeploymentJob> cancel(String id, {required String reason}) async {
    cancelCalls++;
    return currentJob = jobWith('cancelled');
  }

  @override
  Future<DeploymentArtifact> upload(
      {required Uint8List manifest,
      required Uint8List bundle,
      required String reason,
      ProgressCallback? progress}) async {
    uploadCalls++;
    progress?.call(1, 2);
    return artifact;
  }
}

Future<ProviderContainer> mount(
    WidgetTester tester, FakeDeploymentService service,
    {bool web = true, DeploymentPicker? picker}) async {
  final container = ProviderContainer(overrides: [
    deploymentSessionProvider.overrideWith((ref) => ref.watch(testSession)),
    deploymentWebProvider.overrideWithValue(web),
    deploymentServiceProvider.overrideWithValue(service),
  ]);
  addTearDown(container.dispose);
  addTearDown(service.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: DeploymentsScreen(picker: picker))));
  await tester.pump();
  return container;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 240,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows actual loading before capability resolves',
      (tester) async {
    final service = FakeDeploymentService()..capabilityWait = Completer();
    await mount(tester, service);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    service.capabilityWait!.complete(service.capability);
    await tester.pumpAndSettle();
    expect(find.text('发布包'), findsOneWidget);
    expect(service.artifactCalls, 1);
  });

  testWidgets(
      'ordinary admin not in allowlist is forbidden without data requests',
      (tester) async {
    final service = FakeDeploymentService()
      ..capability =
          const DeploymentCapabilities(enabled: true, canDeploy: false);
    await mount(tester, service);
    await tester.pumpAndSettle();
    expect(find.textContaining('无部署权限'), findsOneWidget);
    expect(find.text('上传发布包'), findsNothing);
    expect(service.artifactCalls, 0);
  });

  testWidgets(
      'configuring admin can initialize settings before deployment is enabled',
      (tester) async {
    final service = FakeDeploymentService()
      ..capability = const DeploymentCapabilities(
          enabled: false, canDeploy: false, canConfigure: true)
      ..settingsValue = const DeploymentSettings(
          enabled: false,
          operatorIds: [],
          maxBytes: 524288000,
          maxExpandedBytes: 1073741824,
          maxFiles: 10000,
          workerStatus: 'offline');
    await mount(tester, service);
    await tester.pumpAndSettle();
    expect(find.text('运行配置'), findsOneWidget);
    expect(service.artifactCalls, 0);
    await tester.enterText(find.byType(TextField).first, '1,2');
    await tapVisible(tester, find.widgetWithText(FilledButton, '保存配置'));
    expect(find.text('保存运行配置'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Initialize console');
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.saveSettingsCalls, 1);
    expect(service.settingsValue.operatorIds, [1, 2]);
  });

  testWidgets('reload settings requires an audit reason', (tester) async {
    final service = FakeDeploymentService();
    await mount(tester, service);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(OutlinedButton, '重新加载'));
    expect(service.reloadSettingsCalls, 0);
    await tester.enterText(find.byType(TextField), 'Refresh stored settings');
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.reloadSettingsCalls, 1);
  });

  testWidgets('non Web direct entry is denied', (tester) async {
    final service = FakeDeploymentService();
    await mount(tester, service, web: false);
    expect(find.text('部署管理仅在 Web 端可用。'), findsOneWidget);
    expect(service.artifactCalls, 0);
  });

  testWidgets('error view retries capability and loads data', (tester) async {
    final service = FakeDeploymentService()
      ..failure = const DeploymentFailure();
    await mount(tester, service);
    await tester.pumpAndSettle();
    expect(find.textContaining('连接失败'), findsOneWidget);
    service.failure = null;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('发布包'), findsOneWidget);
  });

  for (final status in [401, 403]) {
    testWidgets('$status clears data and stops polling', (tester) async {
      final service = FakeDeploymentService()..currentJob = jobWith('running');
      await mount(tester, service);
      await tester.pumpAndSettle();
      service.failure = DeploymentFailure(status);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('发布包'), findsNothing);
      expect(find.textContaining(status == 401 ? '登录已失效' : '无部署权限'),
          findsOneWidget);
      final calls = service.activeCalls;
      await tester.pump(const Duration(seconds: 9));
      expect(service.activeCalls, calls);
    });
  }

  for (final operation in {
    '预检': 'preflight',
    '部署': 'deploy',
    '登记': 'register',
    '恢复': 'restore'
  }.entries) {
    testWidgets('${operation.value} requires reason and creates job with key',
        (tester) async {
      final service = FakeDeploymentService();
      await mount(tester, service);
      await tester.pumpAndSettle();
      await tapVisible(
          tester, find.widgetWithText(OutlinedButton, operation.key));
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '确认'))
              .onPressed,
          isNull);
      await tester.enterText(find.byType(TextField), 'Release reviewed');
      await tester.pump();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(service.createCalls, 1);
      expect(service.operation, operation.value);
      expect(service.reason, 'Release reviewed');
      expect(service.idempotencyKey, isNotEmpty);
    });
  }

  testWidgets(
      'approval requires migration, schema and explicit compatibility text',
      (tester) async {
    final service = FakeDeploymentService()
      ..currentJob = jobWith('awaiting_approval');
    await mount(tester, service);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(FilledButton, '批准部署'));
    await tester.enterText(find.byType(TextField).first, 'Migration reviewed');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认'))
            .onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.enterText(find.byType(TextField).last, '兼容');
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.approvalCalls, 1);
    expect(service.migration, isTrue);
    expect(service.schema, isTrue);
  });

  testWidgets('cancel requires reason', (tester) async {
    final service = FakeDeploymentService()..currentJob = jobWith('queued');
    await mount(tester, service);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(OutlinedButton, '取消任务'));
    await tester.enterText(find.byType(TextField), 'Abort rollout');
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.cancelCalls, 1);
  });

  testWidgets('polls sequentially and discards in-flight response on logout',
      (tester) async {
    final service = FakeDeploymentService()..currentJob = jobWith('running');
    final container = await mount(tester, service);
    await tester.pumpAndSettle();
    expect(service.activeCalls, 1);
    service.activeWait = Completer();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(service.activeCalls, 2);
    await tester.pump(const Duration(seconds: 12));
    expect(service.activeCalls, 2);
    container.read(testSession.notifier).state = (token: null, userId: null);
    await tester.pumpAndSettle();
    service.activeWait!.complete(
        DeploymentActive(job: jobWith('succeeded'), release: artifact));
    await tester.pumpAndSettle();
    expect(find.text('请先登录后访问部署管理。'), findsOneWidget);
    expect(find.textContaining('release-1'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(service.activeCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout closes pending confirmation without mutation',
      (tester) async {
    final service = FakeDeploymentService();
    final container = await mount(tester, service);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(OutlinedButton, '部署'));
    container.read(testSession.notifier).state = (token: null, userId: null);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.createCalls, 0);
  });

  testWidgets(
      'phone layout supports manifest and bundle upload without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeDeploymentService();
    await mount(tester, service,
        picker: ({required manifest}) async => DeploymentFile(
              manifest ? 'manifest.json' : 'bundle.tar.gz',
              Uint8List.fromList(manifest
                  ? utf8.encode('{"version":"1.2.3"}')
                  : [0x1f, 0x8b, 0]),
            ));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('选择 manifest.json'));
    await tapVisible(tester, find.text('选择 bundle.tar.gz'));
    await tapVisible(tester, find.widgetWithText(FilledButton, '上传发布包'));
    await tester.enterText(find.byType(TextField), 'Upload release');
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.uploadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  test('transport reads live token and sends no URL credentials', () async {
    var token = 'first-secret';
    final requests = <RequestOptions>[];
    final dio =
        Dio(BaseOptions(baseUrl: 'https://example.test/api/admin/deployments'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(
          requestOptions: options,
          data: {'enabled': true, 'can_deploy': true}));
    }));
    final service = DeploymentService(readToken: () => token, dio: dio);
    addTearDown(service.dispose);
    await service.capabilities();
    token = 'second-secret';
    await service.capabilities();
    expect(requests.first.headers['Authorization'], 'Bearer first-secret');
    expect(requests.last.headers['Authorization'], 'Bearer second-secret');
    for (final request in requests) {
      expect(request.uri.toString(),
          'https://example.test/api/admin/deployments/capabilities');
      expect(request.uri.query, isEmpty);
      expect(request.followRedirects, isFalse);
    }
  });

  test('upload multipart and approval fields match contract', () async {
    final requests = <RequestOptions>[];
    final dio =
        Dio(BaseOptions(baseUrl: 'https://example.test/api/admin/deployments'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(requestOptions: options, data: {
        'id': '1',
        'release_id': 'r1',
        'version': '1',
        'build_number': 1,
        'artifact_id': 'a1',
        'status': 'running',
        'operation': 'deploy',
      }));
    }));
    final service = DeploymentService(readToken: () => 'secret', dio: dio);
    addTearDown(service.dispose);
    await service.upload(
        manifest: Uint8List.fromList([123, 125]),
        bundle: Uint8List.fromList([1, 2]),
        reason: 'Upload');
    final data = requests.first.data as FormData;
    expect(data.files.map((file) => file.key), ['manifest', 'bundle']);
    expect(data.files.map((file) => file.value.filename),
        ['manifest.json', 'bundle.tar.gz']);
    expect(data.fields.single.value, 'Upload');
    await service.approve('job1',
        reason: 'Reviewed', migrationConfirmed: true, schemaCompatible: true);
    expect(requests.last.data, {
      'reason': 'Reviewed',
      'migration_confirmed': true,
      'schema_compatible': true
    });
    expect(requests.last.path, '/job1/approve');
  });
}
