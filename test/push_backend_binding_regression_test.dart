import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) => File('$projectRoot/$relativePath')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('Aliyun backend push binding contracts', () {
    test('client exposes backend push device registration API', () {
      final service = read('lib/services/api/push_device_service.dart');

      expect(service, contains('class PushDeviceService'));
      expect(service, contains('/push/devices/register'));
      expect(service, contains('/push/devices/unregister'));
      expect(service, contains('/push/devices/status'));
      expect(service, contains('device_id'));
      expect(service, contains('provider'));
      expect(service, contains('aliyun'));
    });

    test('AliyunPushService binds initialized device id to backend', () {
      final source = read('lib/services/aliyun_push_service.dart');
      final diagnostics = read('lib/services/push_diagnostics_service.dart');
      final screen = read('lib/screens/profile/push_diagnostics_screen.dart');

      expect(source, contains('PushDeviceService'));
      expect(source, contains('registerBackendDevice'));
      expect(source, contains('unregisterBackendDevice'));
      expect(source, contains('aliyun_push_backend_bind_status'));
      expect(source, contains('aliyun_push_backend_bind_at'));
      expect(source, contains('aliyun_push_backend_bind_error'));
      expect(diagnostics, contains('aliyun_push_backend_bind_status'));
      expect(diagnostics, contains('aliyun_push_backend_bind_at'));
      expect(diagnostics, contains('aliyun_push_backend_bind_error'));
      expect(diagnostics, contains('backend bind status'));
      expect(screen, contains("_buildSection('阿里云推送', data['aliyunPush'])"));
    });

    test('auth lifecycle uses serialized binding and invalidates WS first', () {
      final source = read('lib/providers/auth_notifier.dart');
      final endSessionStart = source.indexOf('Future<void> _endSession()');
      final endSessionEnd = source.indexOf('Future<void> _clearLocalSession()');
      final endSession = source.substring(endSessionStart, endSessionEnd);

      expect(source, contains('AliyunPushService'));
      expect(source, contains('reconcileBackendBinding(authenticated: true)'));
      expect(endSession, contains('_setAppForeground(false)'));
      expect(endSession,
          contains('reconcileBackendBinding(authenticated: false)'));
      expect(
        endSession.indexOf('_setAppForeground(false)'),
        lessThan(endSession.indexOf('reconcileBackendBinding')),
      );
      expect(
        endSession.indexOf('reconcileBackendBinding'),
        lessThan(endSession.indexOf('_setToken(null)')),
      );
    });

    test('token diagnostics never log credentials or decoded claims', () {
      final apiClient = read('lib/services/api/api_client.dart');
      final splash = read('lib/screens/splash/splash_screen.dart');
      final wsClient = read('packages/reliable_websocket/lib/src/client.dart');
      final connectionManager = read(
        'packages/reliable_websocket/lib/src/connection/connection_manager.dart',
      );

      expect(apiClient, isNot(contains('JWT Header')));
      expect(apiClient, isNot(contains('JWT Payload')));
      expect(splash, isNot(contains('substring(0, 12)')));
      expect(splash, isNot(contains('token=\${ApiClient.token')));
      expect(wsClient, isNot(contains('Connecting to \${_config.url}')));
      expect(connectionManager, isNot(contains('Opening WebSocket to \$_url')));
      expect(
          connectionManager, isNot(contains('WebSocket connected to \$_url')));
      expect(connectionManager,
          isNot(contains("'→ \${frame.type.name}: \$data'")));
      expect(connectionManager,
          isNot(contains("'← \${frame.type.name}: \$rawStr'")));
    });
  });
}
