import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/main.dart';

void main() {
  test('application root is NonToApp', () {
    expect(const NonToApp(), isA<NonToApp>());
  });
}
