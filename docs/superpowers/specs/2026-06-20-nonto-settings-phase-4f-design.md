# Nonto Settings Phase 4F Design

## Context

Settings is the profile-adjacent control center for account, privacy, notifications, appearance, legal links, logout, and account deletion. The current screen is functional and analyzer-clean, but it reads as a plain list of controls. Phase 4F should make it feel more mature and consistent with the Nonto profile work without changing backend behavior.

Existing behavior to preserve:

- Password change dialog validates password length and confirmation before calling `AuthService.changePassword`.
- Privacy settings open the existing privacy subpage and save through `AuthService.updatePrivacy`.
- Notification switches load from backend first, then fall back to `SharedPreferences`.
- Notification switch changes persist locally and call `NotificationService.updateSettings`.
- Theme picker uses `themeProvider` and keeps light/dark/system choices.
- Legal and open-source links keep existing routes.
- Logout and account deletion keep their confirmation flows.

## Goals

1. Make settings easier to scan with Nonto-owned section descriptions and richer row subtitles.
2. Keep finite settings rendering simple and cheap; no heavyweight animation or eager media work.
3. Prevent notification switches from accepting taps before settings have loaded.
4. Add a mounted guard after async preference loading.
5. Preserve destructive action confirmations and existing services/routes.
6. Add source regression tests for the Phase 4F UI/UX and reliability contract.

## Non-goals

- No database migrations.
- No backend/API shape changes.
- No new settings categories or unavailable product features.
- No refactor that splits `settings_screen.dart` into multiple files in this slice.
- No broad analyzer cleanup outside touched settings files and tests.

## Design

### Settings structure

Keep the existing `Scaffold` and finite `ListView`. Settings is a short static screen, so `ListView(children: ...)` is acceptable and avoids overengineering.

Add a screen-level source comment:

- `Nonto 设置页：账号、安全、通知、外观与服务信息的统一入口。`

Upgrade `_buildSettingsSection` to accept an optional `subtitle`. The title and subtitle should appear above the card, giving users enough context before they tap rows.

Recommended section labels:

- `账号与安全` — `管理登录、隐私和账号安全`
- `通知设置` — `控制 Nonto 如何提醒你`
- `通用` — `外观和显示偏好`
- `关于 Nonto` — `版本、协议与开源信息`

### Row content

Extend `_buildListTile` and `_buildSwitchTile` with optional `subtitle`. Keep the current compact row style, but add a secondary line for rows where it clarifies consequences.

Recommended subtitles:

- 修改密码：`定期更新密码可以提升账号安全`
- 隐私设置：`控制主页、帖子和搜索可见范围`
- 账号注销：`永久删除账号和相关数据`
- 推送通知：`新互动、好友请求和系统动态`
- 消息提醒：`私信和会话更新`
- 声音：`操作反馈和提醒音效`
- 外观模式：`浅色、深色或跟随系统`

### Notification loading behavior

Switch rows should take an `enabled` flag. For notification switches, set `enabled: _isNotifSettingsLoaded` so a user cannot toggle before backend/prefs loading has settled. Disabled rows should also ignore tile taps by setting `onTap: null`.

This avoids confusing early taps and prevents local state changes before the initial source of truth has loaded.

### Async safety

`_loadFromPrefs()` awaits `SharedPreferences.getInstance()` and then calls `setState`. Add:

```dart
if (!mounted) return;
```

before `setState`.

### Destructive action consistency

Keep logout and account deletion behind confirmations. Add a small helper such as `_buildDestructiveActionButton` for the logout button so destructive actions are visually intentional and easier to keep consistent later. Do not bypass dialogs.

## Testing

Create `test/nonto_settings_phase4f_regression_test.dart` as a source regression suite. It should verify:

- settings has Nonto-owned screen wording;
- sections support subtitles and include the planned section descriptions;
- list/switch rows support optional subtitles;
- notification switches are disabled until `_isNotifSettingsLoaded`;
- `_loadFromPrefs()` checks `mounted` after awaiting prefs;
- logout and account deletion confirmation flows remain present.

Run the new test RED before production changes, then GREEN after implementation.

## Verification

After implementation:

1. `flutter test test/nonto_settings_phase4f_regression_test.dart`
2. `dart analyze lib/screens/profile/settings_screen.dart test/nonto_settings_phase4f_regression_test.dart`
3. Adjacent profile/settings tests:
   - `flutter test test/nonto_profile_phase4a_regression_test.dart test/nonto_edit_profile_phase4d_regression_test.dart test/nonto_image_crop_phase4e_regression_test.dart test/nonto_settings_phase4f_regression_test.dart`
4. Full test suite with current API/WS defines.
5. Full `flutter analyze` for honest project-wide status. Existing historical analyzer issues may remain.