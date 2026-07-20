import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/config/app_config.dart';

void main() {
  test('AppConfig uses production defaults when dart-define values are absent',
      () {
    expect(AppConfig.baseUrl, 'https://www.nonto.online/api');
    expect(AppConfig.wsUrl, 'https://www.nonto.online/ws');
  });
}
