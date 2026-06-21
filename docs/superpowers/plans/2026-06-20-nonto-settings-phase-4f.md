# Nonto Settings Phase 4F Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize the Nonto settings screen with clearer section context, row descriptions, safer notification loading, and source regression coverage.

**Architecture:** Keep `settings_screen.dart` as the single profile-adjacent settings file for this slice. Add optional subtitle/enabled parameters to existing helpers rather than introducing new abstractions, and preserve all existing services, routes, and confirmation flows.

**Tech Stack:** Flutter, Riverpod, SharedPreferences, `flutter_test`, source-regression tests.

---

## File Structure

- Create: `test/nonto_settings_phase4f_regression_test.dart`
  - Source regression checks for Nonto wording, section subtitles, row subtitles, notification loading guard, async mounted guard, and confirmation flow preservation.
- Modify: `lib/screens/profile/settings_screen.dart`
  - Add Nonto screen comment.
  - Add section subtitles.
  - Add row subtitles.
  - Disable notification switch rows until settings are loaded.
  - Guard `_loadFromPrefs()` after async prefs retrieval.
  - Add a small logout/destructive button helper.

Do not commit unless the user explicitly asks.

---

### Task 1: Add RED source regression coverage

**Files:**
- Create: `test/nonto_settings_phase4f_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nonto_settings_phase4f_regression_test.dart` with:

```dart
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

      expect(source, contains('{String? subtitle}'));
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
      expect(source, contains('onTap: enabled ? () => onChanged(!value) : null'));
    });

    test('preference fallback checks mounted after async gap', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(source, contains('final prefs = await SharedPreferences.getInstance();'));
      expect(source, contains('if (!mounted) return;'));
    });

    test('logout and account deletion remain confirmation-based', () {
      final source = read('lib/screens/profile/settings_screen.dart');

      expect(source, contains('_showLogoutConfirmation(context, authState)'));
      expect(source, contains('_showAccountDeletionDialog(context, authState)'));
      expect(source, contains('账号注销'));
      expect(source, contains('此操作不可撤销'));
      expect(source, contains('_buildDestructiveActionButton'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_settings_phase4f_regression_test.dart
```

Expected: FAIL because `settings_screen.dart` does not yet have Phase 4F wording, section subtitles, enabled switch rows, mounted preference fallback guard, or destructive button helper.

---

### Task 2: Implement settings polish and reliability guards

**Files:**
- Modify: `lib/screens/profile/settings_screen.dart`
- Test: `test/nonto_settings_phase4f_regression_test.dart`

- [ ] **Step 1: Add the Nonto screen comment**

Add above `class SettingsScreen`:

```dart
/// Nonto 设置页：账号、安全、通知、外观与服务信息的统一入口。
```

- [ ] **Step 2: Update `_buildSettingsSection`**

Change the helper signature to:

```dart
Widget _buildSettingsSection(
  String title,
  List<Widget> children, {
  String? subtitle,
}) {
```

Inside the heading `Padding`, replace the single `Text(title, ...)` with a `Column` that renders the subtitle when present:

```dart
child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    ),
    if (subtitle != null) ...[
      const SizedBox(height: 2),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textTertiary,
        ),
      ),
    ],
  ],
),
```

- [ ] **Step 3: Add section subtitles at call sites**

Use named subtitle arguments:

```dart
_buildSettingsSection('账号与安全', [
  ...
], subtitle: '管理登录、隐私和账号安全'),
```

```dart
_buildSettingsSection('通知设置', [
  ...
], subtitle: '控制 Nonto 如何提醒你'),
```

```dart
_buildSettingsSection('通用', [
  ...
], subtitle: '外观和显示偏好'),
```

```dart
_buildSettingsSection('关于 Nonto', [
  ...
], subtitle: '版本、协议与开源信息'),
```

- [ ] **Step 4: Add subtitle support to row helpers**

Update `_buildListTile` signature:

```dart
Widget _buildListTile({
  required String title,
  required IconData icon,
  String? subtitle,
  Color? iconColor,
  Color? titleColor,
  Widget? trailing,
  VoidCallback? onTap,
}) {
```

Add this argument to `ListTile`:

```dart
subtitle: subtitle == null
    ? null
    : Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
```

Update `_buildSwitchTile` signature:

```dart
Widget _buildSwitchTile({
  required String title,
  required IconData icon,
  required bool value,
  required ValueChanged<bool> onChanged,
  String? subtitle,
  bool enabled = true,
}) {
```

Add `subtitle` to `ListTile`, and change switch/tap behavior:

```dart
trailing: Switch.adaptive(
  value: value,
  onChanged: enabled ? onChanged : null,
  activeTrackColor: AppColors.primary.withValues(alpha: 0x80),
  activeThumbColor: AppColors.primary,
),
onTap: enabled ? () => onChanged(!value) : null,
```

- [ ] **Step 5: Add row subtitles and notification enabled guards**

Add subtitles to key rows:

```dart
subtitle: '定期更新密码可以提升账号安全',
subtitle: '控制主页、帖子和搜索可见范围',
subtitle: '永久删除账号和相关数据',
subtitle: '新互动、好友请求和系统动态',
subtitle: '私信和会话更新',
subtitle: '操作反馈和提醒音效',
subtitle: '浅色、深色或跟随系统',
```

For each notification `_buildSwitchTile`, add:

```dart
enabled: _isNotifSettingsLoaded,
```

- [ ] **Step 6: Guard `_loadFromPrefs()` after async gap**

Change `_loadFromPrefs()` from:

```dart
Future<void> _loadFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
```

to:

```dart
Future<void> _loadFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  if (!mounted) return;
  setState(() {
```

- [ ] **Step 7: Extract destructive action button helper**

Add a helper near other UI helpers:

```dart
Widget _buildDestructiveActionButton({
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
  );
}
```

Replace the logout `Padding(child: ElevatedButton.icon(...))` with:

```dart
_buildDestructiveActionButton(
  icon: Icons.logout,
  label: '退出登录',
  onPressed: () => _showLogoutConfirmation(context, authState),
),
```

- [ ] **Step 8: Format files**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/profile/settings_screen.dart test/nonto_settings_phase4f_regression_test.dart
```

Expected: files formatted.

- [ ] **Step 9: Run test to verify it passes**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_settings_phase4f_regression_test.dart
```

Expected: PASS.

---

### Task 3: Verify analyzer and adjacent coverage

**Files:**
- Verify: `lib/screens/profile/settings_screen.dart`
- Verify: `test/nonto_settings_phase4f_regression_test.dart`

- [ ] **Step 1: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/profile/settings_screen.dart test/nonto_settings_phase4f_regression_test.dart
```

Expected: `No issues found!`

- [ ] **Step 2: Run adjacent profile/settings tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart test/nonto_edit_profile_phase4d_regression_test.dart test/nonto_image_crop_phase4e_regression_test.dart test/nonto_settings_phase4f_regression_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run full test suite**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: all tests pass.

- [ ] **Step 4: Run full analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: may still fail on historical project-wide issues. Record the issue count honestly.

---

## Self-Review

- Spec coverage: plan covers Nonto wording, section subtitles, row subtitles, notification loading guard, async mounted guard, destructive flow preservation, tests, and verification.
- Placeholder scan: no placeholders or unresolved TODOs.
- Type consistency: helper signatures and call sites match the existing `settings_screen.dart` structure.