import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final registerSource =
      File('lib/screens/auth/register_screen.dart').readAsStringSync();

  test('registration screen explains QQ-family email requirement', () {
    expect(registerSource, contains('QQ邮箱'));
    expect(registerSource, contains('@qq.com'));
    expect(registerSource, contains('@foxmail.com'));
    expect(registerSource, contains('@vip.qq.com'));
    expect(registerSource, contains('目前仅支持 QQ 邮箱体系注册'));
  });

  test('registration keeps register OTP purpose and pre-verification', () {
    expect(registerSource, contains("purpose: 'register'"));
    expect(registerSource, contains('preVerifyOtp'));
  });

  test('registration username copy documents relaxed supported characters', () {
    expect(registerSource, contains('支持中文、英文、数字、标题符号、emoji'));
  });

  test(
      'registration source does not contain generic email-only validation copy',
      () {
    expect(registerSource, isNot(contains('请输入有效邮箱')));
  });
}
