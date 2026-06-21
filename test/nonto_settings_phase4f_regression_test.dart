import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4F settings source regressions', () {
    test('settings screen uses Nonto-owned source wording', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(source, contains('Nonto 设置页'));
      expect(source, contains('账号、安全、通知、外观与服务信息'));
      expect(source, isNot(contains('Twitter/X')));
      expect(source, isNot(contains('X-style')));
    });

    test('settings sections include contextual subtitles', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(source, contains('String? subtitle'));
      expect(source, contains('管理登录、隐私和账号安全'));
      expect(source, contains('控制 Nonto 如何提醒你'));
      expect(source, contains('外观和显示偏好'));
      expect(source, contains('版本、协议与开源信息'));
      expect(source, contains('关于 Nonto'));
    });

    test('settings rows support subtitles for clearer consequences', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(source, contains('Widget _buildListTile({'));
      expect(source, contains('String? subtitle'));
      expect(source, contains('定期更新密码可以提升账号安全'));
      expect(source, contains('控制主页、帖子和搜索可见范围'));
      expect(source, contains('永久删除账号和相关数据'));
      expect(source, contains('浅色、深色或跟随系统'));
    });

    test('notification switches are disabled until settings load', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(source, contains('bool enabled = true'));
      expect(source, contains('enabled: _isNotifSettingsLoaded'));
      expect(source, contains('onChanged: enabled ? onChanged : null'));
      expect(
          source, contains('onTap: enabled ? () => onChanged(!value) : null'));
    });

    test('preference fallback checks mounted after async gap', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(
        source,
        contains('final prefs = await SharedPreferences.getInstance();'),
      );
      expect(source, contains('if (!mounted) return;'));
    });

    test('logout and account deletion remain confirmation-based', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(source, contains('_showLogoutConfirmation(context, authState)'));
      expect(
          source, contains('_showAccountDeletionDialog(context, authState)'));
      expect(source, contains('账号注销'));
      expect(source, contains('此操作不可撤销'));
      expect(source, contains('_buildDestructiveActionButton'));
    });
  });
}
