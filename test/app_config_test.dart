import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/config/app_config.dart';

void main() {
  test('AppConfig reads API and WebSocket URLs from dart-define values', () {
    expect(AppConfig.baseUrl, 'https://www.nonto.online/api');
    expect(AppConfig.wsUrl, 'wss://www.nonto.online/ws');
  });
}
