# Remaining UX, Identity, Unread, and Chat Reliability Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the remaining user-reported Nonto fixes: unified header avatars, identity application image submission and admin email, search-result back button, correct unread counts and badge colors, and chat time/de-dup reliability verification.

**Architecture:** Keep the changes contract-driven and localized. Flutter changes use existing Riverpod providers, `NontoHeaderSearchBar`, `UploadService`, and source-contract regression tests. FastAPI changes reuse the existing `RoleApplication` model and `EmailService`, adding only configuration, validation, and a non-blocking admin reminder.

**Tech Stack:** Flutter/Dart, Riverpod, image_picker, cross_file, source regression tests, FastAPI, Pydantic, SQLAlchemy, pytest/unittest, SMTP email service.

---

## File Map

### Flutter project: `D:/FlutterProject/nonto`

- Modify: `lib/config/app_theme.dart`
  - Add `AppColors.unreadBadge` semantic color.
- Modify: `lib/widgets/nonto_header_search_bar.dart`
  - Add optional leading/back widget support while preserving avatar behavior.
- Modify: `lib/screens/home/home_screen.dart`
  - Make bottom message badge count chat unread only.
  - Set bottom badge background color to `AppColors.unreadBadge`.
  - Add identity application entry to drawer.
- Modify: `lib/screens/home/home/feed_tab.dart`
  - Make feed header avatar visually match search/messages headers.
- Modify: `lib/screens/messages/messages_tab.dart`
  - Remove local notification unread state.
  - Read notification unread count from provider.
- Modify: `lib/widgets/nonto/nonto_conversation_tile.dart`
  - Use `AppColors.unreadBadge` for unread bubble.
- Modify: `lib/screens/search/search_tab.dart`
  - Show search-box-left back button when displaying search results.
  - Back button exits search mode.
- Modify: `lib/screens/profile/identity_application_screen.dart`
  - Replace proof URL text field with 0-9 image picker/upload workflow.
  - Keep role selection reliable.
  - Add pending optimistic state after successful submission.
- Modify: `lib/services/api/role_service.dart`
  - Keep request shape; no API rename required.
- Create: `test/remaining_ux_identity_unread_regression_test.dart`
  - Source-contract tests for the remaining UI/identity/unread requirements.

### Backend project: `D:/NanTuPy`

- Modify: `app/core/config.py`
  - Add `ROLE_REVIEW_ADMIN_EMAIL` defaulting to `2531830689@qq.com`.
- Modify: `app/core/config_production.py`
  - Add the same production config key.
- Modify: `app/routers/roles.py`
  - Validate `proof_images` length 0-9.
  - Send admin review reminder after successful application creation.
  - Do not fail application if email fails.
- Create: `tests/test_role_identity_email_contracts.py`
  - Source/unit contract tests for role application email reminder and image count validation.

### Verification-only files

- Existing Flutter tests:
  - `test/chat_time_and_community_dedupe_regression_test.dart`
  - `test/notification_ux_regression_test.dart`
  - `test/permissions_and_unread_regression_test.dart`
  - `test/role_identity_contract_test.dart`
- Existing backend tests:
  - `tests/test_community_chat_contracts.py`
  - `tests/test_chat_read_state_contracts.py`
  - `tests/test_notification_service_unit.py`

---

## Task 1: Flutter RED tests for remaining UI, identity, unread contracts

**Files:**
- Create: `D:/FlutterProject/nonto/test/remaining_ux_identity_unread_regression_test.dart`

- [ ] **Step 1: Create the source-contract regression test file**

Create `D:/FlutterProject/nonto/test/remaining_ux_identity_unread_regression_test.dart` with this content:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('remaining UX, identity, and unread regressions', () {
    test('feed header avatar uses the shared header avatar size', () {
      final feed = read('lib/screens/home/home/feed_tab.dart');
      final header = read('lib/widgets/nonto_header_search_bar.dart');

      expect(header, contains('class NontoHeaderAvatar'));
      expect(header, contains('this.radius = 18'));
      expect(feed, contains('NontoHeaderAvatar('));
      expect(feed, contains('radius: 18'));
      expect(feed, isNot(contains('radius: 10')));
    });

    test('drawer exposes identity application entry', () {
      final home = read('lib/screens/home/home_screen.dart');

      expect(home, contains('身份认证'));
      expect(home, contains('Icons.verified_outlined'));
      expect(home, contains('AppRoutes.identityApplication'));
    });

    test('search results show a left back button that exits search state', () {
      final header = read('lib/widgets/nonto_header_search_bar.dart');
      final search = read('lib/screens/search/search_tab.dart');

      expect(header, contains('Widget? leading'));
      expect(search, contains('_buildSearchLeading'));
      expect(search, contains('Icons.arrow_back'));
      expect(search, contains('_exitSearchMode(clearResults: true)'));
    });

    test('bottom message badge counts chat unread only', () {
      final home = read('lib/screens/home/home_screen.dart');
      final buildStart = home.indexOf('Widget build(BuildContext context)');
      final buildEnd = home.indexOf('Widget? _buildComposeButton', buildStart);
      expect(buildStart, greaterThanOrEqualTo(0));
      expect(buildEnd, greaterThan(buildStart));
      final buildSource = home.substring(buildStart, buildEnd);

      expect(buildSource, contains('ref.watch(unreadMessagesCountProvider)'));
      expect(buildSource, isNot(contains('unreadNotificationsCountProvider) +')));
      expect(buildSource, isNot(contains('+\n            ref.watch(unreadMessagesCountProvider)')));
    });

    test('messages notification entry uses notification provider unread count', () {
      final messages = read('lib/screens/messages/messages_tab.dart');

      expect(messages, isNot(contains('int _unreadNotifications = 0;')));
      expect(messages, isNot(contains('_fetchUnreadNotifications')));
      expect(messages, contains('unreadNotificationsCountProvider'));
    });

    test('unread badges use a shared semantic color token', () {
      final theme = read('lib/config/app_theme.dart');
      final home = read('lib/screens/home/home_screen.dart');
      final messages = read('lib/screens/messages/messages_tab.dart');
      final tile = read('lib/widgets/nonto/nonto_conversation_tile.dart');

      expect(theme, contains('unreadBadge'));
      expect(home, contains('backgroundColor: AppColors.unreadBadge'));
      expect(messages, contains('AppColors.unreadBadge'));
      expect(tile, contains('AppColors.unreadBadge'));
    });

    test('identity application supports image selection instead of proof URL text field', () {
      final identity = read('lib/screens/profile/identity_application_screen.dart');

      expect(identity, contains('ImagePicker'));
      expect(identity, contains('_selectedProofImages'));
      expect(identity, contains('static const int _maxProofImages = 9'));
      expect(identity, contains('UploadService'));
      expect(identity, contains('proofImages: uploadedProofImages'));
      expect(identity, isNot(contains('证明图片链接（每行一个，可选）')));
    });

    test('identity application has optimistic pending state after submit success', () {
      final identity = read('lib/screens/profile/identity_application_screen.dart');

      expect(identity, contains('_submittedApplication'));
      expect(identity, contains('等待管理员审核'));
      expect(identity, contains('setState(() {'));
    });
  });
}
```

- [ ] **Step 2: Run the new Flutter test and confirm RED**

Run from Git Bash:

```bash
cd /d/FlutterProject/nonto && flutter test test/remaining_ux_identity_unread_regression_test.dart
```

Expected now: FAIL. The expected failures should mention missing `unreadBadge`, missing search leading support, existing `_unreadNotifications`, `radius: 10`, or missing identity image picker support.

---

## Task 2: Flutter unread counts and badge color implementation

**Files:**
- Modify: `D:/FlutterProject/nonto/lib/config/app_theme.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/home/home_screen.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/messages/messages_tab.dart`
- Modify: `D:/FlutterProject/nonto/lib/widgets/nonto/nonto_conversation_tile.dart`

- [ ] **Step 1: Add semantic unread color**

In `lib/config/app_theme.dart`, change the functional color block from:

```dart
  // 功能色
  static const Color likeRed = Color(0xFFF91880);
  static const Color successGreen = Color(0xFF00BA7C);
```

to:

```dart
  // 功能色
  static const Color likeRed = Color(0xFFF91880);
  static const Color unreadBadge = likeRed;
  static const Color successGreen = Color(0xFF00BA7C);
```

- [ ] **Step 2: Make bottom message badge count chat unread only**

In `lib/screens/home/home_screen.dart`, replace:

```dart
    final totalBadge = (ref.watch(unreadNotificationsCountProvider) +
            ref.watch(unreadMessagesCountProvider))
        .toInt();
```

with:

```dart
    final totalBadge = ref.watch(unreadMessagesCountProvider).toInt();
```

- [ ] **Step 3: Set bottom badge color explicitly**

In `_buildNavIcon`, replace:

```dart
    return Badge(
      label: Text(_formatBadgeCount(badgeCount)),
      child: icon,
    );
```

with:

```dart
    return Badge(
      backgroundColor: AppColors.unreadBadge,
      label: Text(_formatBadgeCount(badgeCount)),
      child: icon,
    );
```

- [ ] **Step 4: Remove local notification unread state from messages tab**

In `lib/screens/messages/messages_tab.dart`, remove these imports and fields if they are now unused:

```dart
import 'package:nonto/services/api/notification_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';
```

Remove these fields:

```dart
  final NotificationService _notifService = NotificationService();

  int _unreadNotifications = 0;
  StreamSubscription? _wsNotifSub;
```

Remove these lines from `initState()`:

```dart
    _wsNotifSub = _wsService.notificationStream.listen(_onWsNotification);
    _fetchUnreadNotifications();
```

Remove this line from `dispose()`:

```dart
    _wsNotifSub?.cancel();
```

Remove the full `_onWsNotification` and `_fetchUnreadNotifications` methods.

In `_onRefresh()`, replace:

```dart
    _fetchUnreadNotifications();
```

with:

```dart
    ref.read(notificationsProvider.notifier).loadNotifications(refresh: true);
```

- [ ] **Step 5: Read notification unread count from provider in the entry builder**

In `_buildNotificationEntry()`, add this as the first line:

```dart
    final unreadNotifications = ref.watch(unreadNotificationsCountProvider);
```

Then replace every `_unreadNotifications` reference inside `_buildNotificationEntry()` with `unreadNotifications`.

- [ ] **Step 6: Use unreadBadge color in messages notification entry**

In `_buildNotificationEntry()`, replace:

```dart
                          decoration: const BoxDecoration(
                            color: AppColors.likeRed,
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
```

with:

```dart
                          decoration: const BoxDecoration(
                            color: AppColors.unreadBadge,
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
```

- [ ] **Step 7: Use unreadBadge color in conversation tile**

In `lib/widgets/nonto/nonto_conversation_tile.dart`, replace:

```dart
      decoration: const BoxDecoration(
        color: AppColors.likeRed,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
```

with:

```dart
      decoration: const BoxDecoration(
        color: AppColors.unreadBadge,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
```

- [ ] **Step 8: Run focused unread/color tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/remaining_ux_identity_unread_regression_test.dart
```

Expected: unread/color related tests pass; identity/search tests may still fail until later tasks.

---

## Task 3: Flutter header avatar and search-result back button

**Files:**
- Modify: `D:/FlutterProject/nonto/lib/widgets/nonto_header_search_bar.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/home/home/feed_tab.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/search/search_tab.dart`

- [ ] **Step 1: Add optional leading support to NontoHeaderSearchBar**

In `lib/widgets/nonto_header_search_bar.dart`, add a field after `trailing`:

```dart
  final Widget? leading;
```

Update the constructor to include:

```dart
    this.leading,
```

In `build`, replace the current leading avatar `AnimatedSize` block:

```dart
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: showAvatar
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: showAvatar ? 1 : 0,
                        child: NontoHeaderAvatar(
                          user: widget.user,
                          radius: 18,
                          onTap: widget.onAvatarTap,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
```

with:

```dart
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: widget.leading != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: widget.leading!,
                    )
                  : showAvatar
                      ? Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: showAvatar ? 1 : 0,
                            child: NontoHeaderAvatar(
                              user: widget.user,
                              radius: 18,
                              onTap: widget.onAvatarTap,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
            ),
```

- [ ] **Step 2: Make FeedTab avatar radius match shared header avatar**

In `lib/screens/home/home/feed_tab.dart`, replace:

```dart
                          child: NontoHeaderAvatar(
                            user: authState.user,
                            radius: 10,
                            onTap: () => Scaffold.of(context).openDrawer(),
                          ),
```

with:

```dart
                          child: NontoHeaderAvatar(
                            user: authState.user,
                            radius: 18,
                            onTap: () => Scaffold.of(context).openDrawer(),
                          ),
```

- [ ] **Step 3: Add search-result leading builder**

In `lib/screens/search/search_tab.dart`, add this method before `_buildRightButton()`:

```dart
  Widget? _buildSearchLeading() {
    if (!_isSearching) return null;
    return IconButton(
      icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
      tooltip: '退出搜索',
      onPressed: () => _exitSearchMode(clearResults: true),
    );
  }
```

- [ ] **Step 4: Pass leading into the search header**

In the `NontoHeaderSearchBar` call inside `SearchTab.build`, add:

```dart
                            leading: _buildSearchLeading(),
```

Place it near `hintText: '搜索',` so the call becomes structurally clear:

```dart
                            hintText: '搜索',
                            leading: _buildSearchLeading(),
                            onAvatarTap: () =>
                                Scaffold.of(context).openDrawer(),
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/remaining_ux_identity_unread_regression_test.dart
```

Expected: header avatar and search-result back button tests pass; identity image tests may still fail.

---

## Task 4: Flutter identity application entry, image selection/upload, optimistic pending state

**Files:**
- Modify: `D:/FlutterProject/nonto/lib/screens/home/home_screen.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/profile/identity_application_screen.dart`

- [ ] **Step 1: Add identity route import if needed**

`home_screen.dart` already imports `AppRoutes`; keep using it. No direct import of `IdentityApplicationScreen` is needed.

- [ ] **Step 2: Add drawer identity application entry**

In `_buildDrawer`, insert this `ListTile` after the “编辑个人资料” entry and before “好友申请”:

```dart
            ListTile(
              leading: Icon(Icons.verified_outlined, color: AppColors.textPrimary),
              title: Text('身份认证',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.identityApplication);
              },
            ),
```

- [ ] **Step 3: Add imports to identity application screen**

At the top of `identity_application_screen.dart`, replace current imports:

```dart
import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/api/role_service.dart';
```

with:

```dart
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/api/role_service.dart';
import 'package:nonto/services/api/upload_service.dart';
import 'package:nonto/utils/picker_error_utils.dart';
```

- [ ] **Step 4: Replace proof text controller with image state**

Remove this field:

```dart
  final _proofController = TextEditingController();
```

Add these fields under the controller fields:

```dart
  static const int _maxProofImages = 9;

  final ImagePicker _imagePicker = ImagePicker();
  final List<XFile> _selectedProofImages = [];
  Map<String, dynamic>? _submittedApplication;
```

In `dispose()`, remove:

```dart
    _proofController.dispose();
```

- [ ] **Step 5: Add image picker helper**

Add this method before `_submit()`:

```dart
  Future<void> _pickProofImages() async {
    if (_submitting) return;
    final remaining = _maxProofImages - _selectedProofImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多只能提交 9 张证明图片')),
      );
      return;
    }

    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 92);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _selectedProofImages.addAll(picked.take(remaining));
        _error = null;
      });
      if (picked.length > remaining && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多只能提交 9 张证明图片')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showPickerErrorSnackBar(context, e);
    }
  }
```

- [ ] **Step 6: Add upload helper**

Add this method before `_submit()`:

```dart
  Future<List<String>> _uploadProofImages() async {
    final uploadedProofImages = <String>[];
    for (final image in _selectedProofImages) {
      final resp = await UploadService().uploadImage(image);
      if (!resp.success || resp.data == null) {
        throw Exception(resp.message ?? '证明图片上传失败');
      }
      final data = resp.data;
      final url = data is Map
          ? (data['url'] ?? data['public_url'] ?? data['file_url'])?.toString()
          : data.toString();
      if (url == null || url.isEmpty) {
        throw Exception('证明图片上传失败');
      }
      uploadedProofImages.add(url);
    }
    return uploadedProofImages;
  }
```

- [ ] **Step 7: Update submit to upload images and set optimistic pending state**

Inside `_submit()`, replace the `RoleService().applyIdentity` call block:

```dart
      final resp = await RoleService().applyIdentity(
        roleName: roleName,
        applicationText: applicationText,
        proofImages: _splitLines(_proofController.text),
        portfolioLinks: _splitLines(_portfolioController.text),
        contactInfo: _contactController.text.trim(),
        extraNote: _noteController.text.trim(),
      );
```

with:

```dart
      final uploadedProofImages = await _uploadProofImages();
      final resp = await RoleService().applyIdentity(
        roleName: roleName,
        applicationText: applicationText,
        proofImages: uploadedProofImages,
        portfolioLinks: _splitLines(_portfolioController.text),
        contactInfo: _contactController.text.trim(),
        extraNote: _noteController.text.trim(),
      );
```

Then replace the success branch:

```dart
      if (resp.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('认证申请已提交，等待管理员审核')),
        );
        Navigator.of(context).pop(true);
      } else {
```

with:

```dart
      if (resp.success) {
        final data = resp.data;
        setState(() {
          _submitting = false;
          _submittedApplication = data is Map<String, dynamic>
              ? data['application'] as Map<String, dynamic>?
              : <String, dynamic>{'status': 'pending'};
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('认证申请已提交，等待管理员审核')),
        );
      } else {
```

- [ ] **Step 8: Replace proof URL text field with image section**

In the `ListView` children, replace:

```dart
                const SizedBox(height: 12),
                _buildTextField(_proofController, '证明图片链接（每行一个，可选）', maxLines: 3),
```

with:

```dart
                const SizedBox(height: 12),
                _buildProofImagesSection(),
```

- [ ] **Step 9: Show submitted pending state**

At the start of `body` when not loading, before the existing `ListView`, use a branch:

```dart
          : _submittedApplication != null
              ? _buildSubmittedState()
              : ListView(
```

Keep the existing `ListView` as the final branch.

- [ ] **Step 10: Add proof image section widget**

Add these widget helpers before `_buildTextField()`:

```dart
  Widget _buildSubmittedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, color: AppColors.primary, size: 48),
            const SizedBox(height: 16),
            Text(
              '认证申请已提交',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '等待管理员审核',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProofImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '证明图片（0-9 张，可选）',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            const Spacer(),
            Text(
              '${_selectedProofImages.length}/$_maxProofImages',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._selectedProofImages.asMap().entries.map((entry) {
              final index = entry.key;
              final image = entry.value;
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      image.path,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: AppColors.backgroundSecondary,
                        child: Icon(Icons.image, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: _submitting
                          ? null
                          : () => setState(() => _selectedProofImages.removeAt(index)),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              );
            }),
            if (_selectedProofImages.length < _maxProofImages)
              InkWell(
                onTap: _submitting ? null : _pickProofImages,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Icon(Icons.add_photo_alternate_outlined,
                      color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ],
    );
  }
```

- [ ] **Step 11: Run focused Flutter tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/remaining_ux_identity_unread_regression_test.dart test/role_identity_contract_test.dart
```

Expected: PASS. If analyzer reports `Image.network(image.path)` unsuitable for local file paths on mobile, replace preview with `Image.file(File(image.path))` for non-web and add `dart:io` guarded with `kIsWeb`; keep source tests updated accordingly.

---

## Task 5: Backend RED tests for role image limit and admin email reminder

**Files:**
- Create: `D:/NanTuPy/tests/test_role_identity_email_contracts.py`

- [ ] **Step 1: Create backend contract tests**

Create `D:/NanTuPy/tests/test_role_identity_email_contracts.py` with this content:

```python
import inspect
import unittest

from app.core.config import Config
from app.routers import roles


class RoleIdentityEmailContractsTest(unittest.TestCase):
    def test_config_has_default_role_review_admin_email(self):
        self.assertEqual(Config.ROLE_REVIEW_ADMIN_EMAIL, "2531830689@qq.com")

    def test_role_apply_request_limits_proof_images_to_nine(self):
        source = inspect.getsource(roles.RoleApplyRequest)

        self.assertIn("max_length=9", source)
        self.assertIn("proof_images", source)

    def test_apply_role_sends_admin_review_email_after_commit(self):
        source = inspect.getsource(roles.apply_role)

        self.assertIn("_send_role_review_email", source)
        self.assertIn("db.commit()", source)
        self.assertLess(source.index("db.commit()"), source.index("_send_role_review_email"))

    def test_admin_review_email_uses_configured_recipient_and_is_non_blocking(self):
        source = inspect.getsource(roles._send_role_review_email)

        self.assertIn("Config.ROLE_REVIEW_ADMIN_EMAIL", source)
        self.assertIn("EmailService.send_email", source)
        self.assertIn("except Exception", source)
        self.assertIn("logger.warning", source)
        self.assertIn("return", source)

    def test_admin_review_email_contains_application_context(self):
        source = inspect.getsource(roles._build_role_review_email_html)

        for expected in [
            "application.id",
            "user.id",
            "user.username",
            "user.email",
            "role.name",
            "role.label",
            "application.application_text",
            "application.contact_info",
            "application.proof_images",
            "application.portfolio_links",
        ]:
            self.assertIn(expected, source)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run backend test and confirm RED**

Run:

```bash
cd /d/NanTuPy && python -m pytest tests/test_role_identity_email_contracts.py -q
```

Expected now: FAIL because config and helper functions do not exist and `proof_images` has no max length.

---

## Task 6: Backend role application email implementation

**Files:**
- Modify: `D:/NanTuPy/app/core/config.py`
- Modify: `D:/NanTuPy/app/core/config_production.py`
- Modify: `D:/NanTuPy/app/routers/roles.py`

- [ ] **Step 1: Add config key in development config**

In `app/core/config.py`, after SMTP settings, add:

```python
    # 身份认证审核提醒邮箱
    ROLE_REVIEW_ADMIN_EMAIL = os.environ.get('ROLE_REVIEW_ADMIN_EMAIL', '2531830689@qq.com')
```

- [ ] **Step 2: Add config key in production config**

In `app/core/config_production.py`, after SMTP settings, add:

```python
    # 身份认证审核提醒邮箱
    ROLE_REVIEW_ADMIN_EMAIL = os.environ.get('ROLE_REVIEW_ADMIN_EMAIL', '2531830689@qq.com')
```

- [ ] **Step 3: Update roles.py imports**

In `app/routers/roles.py`, replace imports:

```python
import json
import logging
from fastapi import APIRouter, Depends, HTTPException, Body, Query
```

with:

```python
import asyncio
import html
import json
import logging
from fastapi import APIRouter, Depends, HTTPException, Body, Query
```

Add these imports after existing app imports:

```python
from app.core.config import Config
from app.services.email_service import EmailService
```

- [ ] **Step 4: Limit proof images to 9 in request schema**

Change:

```python
    proof_images: list[str] = Field(default_factory=list)
```

to:

```python
    proof_images: list[str] = Field(default_factory=list, max_length=9)
```

- [ ] **Step 5: Add email HTML builder helper**

Add this helper above `apply_role()`:

```python
def _html_list(items: list[str]) -> str:
    if not items:
        return "<li>无</li>"
    return "".join(f"<li>{html.escape(str(item))}</li>" for item in items)


def _build_role_review_email_html(application: RoleApplication, user: User, role: Role) -> str:
    proof_images = json.loads(application.proof_images or "[]")
    portfolio_links = json.loads(application.portfolio_links or "[]")
    return f"""\
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;max-width:640px;margin:0 auto;padding:24px;">
  <h2 style="color:#1DA1F2;margin:0 0 16px;">南图 NonTo - 新的身份认证申请</h2>
  <p>有新的身份认证申请待审核。</p>
  <table style="border-collapse:collapse;width:100%;font-size:14px;">
    <tr><td style="padding:6px 0;color:#536471;">申请 ID</td><td>{application.id}</td></tr>
    <tr><td style="padding:6px 0;color:#536471;">用户 ID</td><td>{user.id}</td></tr>
    <tr><td style="padding:6px 0;color:#536471;">用户名</td><td>{html.escape(user.username or '')}</td></tr>
    <tr><td style="padding:6px 0;color:#536471;">邮箱</td><td>{html.escape(user.email or '')}</td></tr>
    <tr><td style="padding:6px 0;color:#536471;">申请身份</td><td>{html.escape(role.label or role.name)} ({html.escape(role.name)})</td></tr>
    <tr><td style="padding:6px 0;color:#536471;">联系方式</td><td>{html.escape(application.contact_info or '未填写')}</td></tr>
  </table>
  <h3 style="margin:20px 0 8px;">认证说明</h3>
  <p style="white-space:pre-wrap;">{html.escape(application.application_text or application.reason or '')}</p>
  <h3 style="margin:20px 0 8px;">证明图片（{len(proof_images)} 张）</h3>
  <ul>{_html_list(proof_images)}</ul>
  <h3 style="margin:20px 0 8px;">作品/主页链接</h3>
  <ul>{_html_list(portfolio_links)}</ul>
  <h3 style="margin:20px 0 8px;">补充说明</h3>
  <p style="white-space:pre-wrap;">{html.escape(application.extra_note or '无')}</p>
  <hr style="border:none;border-top:1px solid #eff3f4;margin:24px 0;">
  <p style="color:#8899a6;font-size:12px;margin:0;">此邮件由系统自动发送，请尽快进入后台审核。</p>
</div>"""
```

- [ ] **Step 6: Add non-blocking email sender helper**

Add this helper below the HTML builder:

```python
async def _send_role_review_email(application: RoleApplication, user: User, role: Role) -> None:
    if not Config.ROLE_REVIEW_ADMIN_EMAIL:
        logger.warning("[ROLE] ROLE_REVIEW_ADMIN_EMAIL not configured, skip reminder")
        return
    try:
        await EmailService.send_email(
            Config.ROLE_REVIEW_ADMIN_EMAIL,
            "【南图】新的身份认证申请待审核",
            _build_role_review_email_html(application, user, role),
        )
    except Exception as exc:
        logger.warning("[ROLE] role review email failed application_id=%s: %s", application.id, exc)
        return
```

- [ ] **Step 7: Trigger email after commit**

In `apply_role()`, after:

```python
    logger.info(f"User {user.username} applied for role: {role_name}")
```

add:

```python
    try:
        asyncio.create_task(_send_role_review_email(application, user, role))
    except RuntimeError:
        logger.warning("[ROLE] no running event loop, skip async email reminder application_id=%s", application.id)
```

- [ ] **Step 8: Run backend focused test**

Run:

```bash
cd /d/NanTuPy && python -m pytest tests/test_role_identity_email_contracts.py -q
```

Expected: PASS.

---

## Task 7: Chat reliability verification and targeted gap fix

**Files:**
- Inspect/modify if needed: `D:/FlutterProject/nonto/lib/models/message.dart`
- Inspect/modify if needed: `D:/FlutterProject/nonto/lib/screens/community/community_chat_screen.dart`
- Inspect/modify if needed: `D:/FlutterProject/nonto/lib/services/api/community_service.dart`
- Inspect/modify if needed: `D:/NanTuPy/app/routers/communities.py`
- Inspect/modify if needed: `D:/NanTuPy/app/routers/chat.py`
- Existing tests:
  - `D:/FlutterProject/nonto/test/chat_time_and_community_dedupe_regression_test.dart`
  - `D:/NanTuPy/tests/test_community_chat_contracts.py`

- [ ] **Step 1: Run existing Flutter chat reliability test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/chat_time_and_community_dedupe_regression_test.dart
```

Expected: PASS. If it fails, read the failure and fix only the failing contract.

- [ ] **Step 2: Run existing backend community chat contract test**

Run:

```bash
cd /d/NanTuPy && python -m pytest tests/test_community_chat_contracts.py -q
```

Expected: PASS. If it fails, read the failure and fix only the failing contract.

- [ ] **Step 3: If Flutter test fails on timestamp parsing**

In `lib/models/message.dart`, ensure `Message.fromJson` uses:

```dart
createdAt: AppDateUtils.parseServerTime(json['created_at']?.toString()),
updatedAt: AppDateUtils.parseServerTime(json['updated_at']?.toString()),
```

and does not use `DateTime.now()` as fallback for historical messages.

In `lib/screens/community/community_chat_screen.dart`, ensure message time helper contains:

```dart
final parsed = AppDateUtils.parseServerTime(raw?.toString());
if (parsed != null) return parsed;
```

and does not contain `DateTime.tryParse` in the message sort helper.

- [ ] **Step 4: If Flutter test fails on community client_msg_id**

In `lib/services/api/community_service.dart`, ensure send message signature contains:

```dart
  Future<ApiResponse> sendMessage(
    int communityId,
    String content, {
    String messageType = 'text',
    String? mediaUrl,
    String? clientMsgId,
  }) {
```

and request data includes:

```dart
    if (clientMsgId != null && clientMsgId.isNotEmpty) {
      data['client_msg_id'] = clientMsgId;
    }
```

In `community_chat_screen.dart`, ensure `_sendMessage()` generates one client id and uses it for both optimistic message and API call:

```dart
final clientMsgId = _newClientMsgId();
```

and optimistic message contains:

```dart
'client_msg_id': clientMsgId,
```

and service call passes:

```dart
clientMsgId: clientMsgId,
```

- [ ] **Step 5: If backend test fails on community client_msg_id or UTC timestamps**

In `D:/NanTuPy/app/routers/communities.py`, ensure community message response contains:

```python
"client_msg_id": message.client_msg_id,
"created_at": _utc_z(message.created_at),
"updated_at": _utc_z(message.updated_at),
```

and send request accepts `client_msg_id` from request body.

- [ ] **Step 6: Re-run chat reliability tests after any targeted fix**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/chat_time_and_community_dedupe_regression_test.dart
cd /d/NanTuPy && python -m pytest tests/test_community_chat_contracts.py -q
```

Expected: PASS for both commands.

---

## Task 8: Focused verification suite

**Files:**
- No code changes unless verification fails.

- [ ] **Step 1: Run Flutter focused tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/remaining_ux_identity_unread_regression_test.dart test/chat_time_and_community_dedupe_regression_test.dart test/notification_ux_regression_test.dart test/permissions_and_unread_regression_test.dart test/role_identity_contract_test.dart
```

Expected: PASS. If failing, report exact failing test and return to the relevant task.

- [ ] **Step 2: Run backend focused tests**

Run:

```bash
cd /d/NanTuPy && python -m pytest tests/test_role_identity_email_contracts.py tests/test_community_chat_contracts.py tests/test_chat_read_state_contracts.py tests/test_notification_service_unit.py -q
```

Expected: PASS. If failing, report exact failing test and return to the relevant task.

- [ ] **Step 3: Run Flutter analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: exit 0. If existing unrelated analyzer issues appear, capture exact output and separate pre-existing issues from this change only if evidence supports that separation.

- [ ] **Step 4: Build release APK if tests/analyze pass**

Run:

```bash
cd /d/FlutterProject/nonto && flutter build apk --release --target-platform android-arm64
```

Expected: build succeeds and produces `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 5: Verify APK signing certificate SHA-256 if APK build succeeds**

Run:

```bash
cd /d/FlutterProject/nonto && keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk
```

Expected output includes the release certificate SHA-256 configured for the project. Do not claim it matches a known fingerprint unless the command output shows it.

---

## Task 9: Completion report

**Files:**
- No code changes.

- [ ] **Step 1: Summarize changed files**

Report the actual changed files in both projects.

- [ ] **Step 2: Summarize requirement coverage**

Use this checklist:

- 首页推荐流头像 UI 与发现页/消息页一致。
- 抽屉栏和设置页都能进入身份认证。
- 身份认证可以选择身份。
- 身份认证支持 0-9 张图片。
- 身份认证提交成功后有 pending/等待审核乐观状态。
- 后端申请成功后向 `2531830689@qq.com` 发送邮件提醒。
- 搜索结果页搜索框左侧返回按钮退出搜索状态。
- 底部消息 Tab 只统计聊天未读。
- 通知入口显示通知 unread provider 的气泡。
- 底部、通知入口、会话列表未读气泡颜色一致。
- 群聊重复消息和私聊/群聊时间排序相关测试通过。

- [ ] **Step 3: Report exact verification commands and results**

Include exact commands and whether they passed or failed. If any command was skipped, explain why.

- [ ] **Step 4: Note no git commit was made**

Because `D:/FlutterProject/nonto` and `D:/NanTuPy` did not expose `.git` directories during planning, do not claim a commit. Say changes are local filesystem edits only.

---

## Self-Review

- Spec coverage: Tasks 1-4 cover Flutter avatar, identity, search, unread, badge colors. Tasks 5-6 cover backend email and image limit. Task 7 covers chat time/de-dup verification and targeted gap fixes. Task 8 covers verification. Task 9 covers reporting.
- Placeholder scan: No TBD/TODO placeholders remain. Conditional chat fix steps include exact target code and are gated by failing existing tests.
- Type consistency: Flutter uses existing `RoleService.applyIdentity`, `UploadService.uploadImage`, `unreadNotificationsCountProvider`, `unreadMessagesCountProvider`, and `AppColors`. Backend uses existing `Config`, `EmailService`, `RoleApplication`, `User`, and `Role`.
- Git note: Commit steps are intentionally omitted because both working directories are not git repositories in this environment.
