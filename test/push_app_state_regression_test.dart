import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('push app state contracts', () {
    test('PushDeviceService exposes backend app state API', () {
      final source =
          File('lib/services/api/push_device_service.dart').readAsStringSync();

      expect(source, contains('Future<ApiResponse> updateDeviceState'));
      expect(source, contains("'/push/devices/state'"));
      expect(source, contains("'app_state'"));
      expect(source, contains('foreground'));
      expect(source, contains('background'));
    });

    test('AliyunPushService can report foreground/background state', () {
      final source =
          File('lib/services/aliyun_push_service.dart').readAsStringSync();

      expect(source, contains('Future<void> updateBackendDeviceState'));
      expect(source, contains('PushDeviceService().updateDeviceState'));
      expect(source, contains('aliyun_push_backend_state_status'));
      expect(source, contains('aliyun_push_backend_state_error'));
    });

    test('app lifecycle reports foreground and background push state', () {
      final source = File('lib/services/app_lifecycle_keepalive_service.dart')
          .readAsStringSync();

      expect(
          source, contains("package:nonto/services/aliyun_push_service.dart"));
      expect(source, contains("updateBackendDeviceState('foreground')"));
      expect(source, contains("updateBackendDeviceState('background')"));
    });
  });
}
