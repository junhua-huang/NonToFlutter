# Huawei Sender ID Token Diagnostics v8.5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend Huawei diagnostics to show AAID, token by app id, and token by sender id so Huawei Console token validation can be isolated.

**Architecture:** Reuse the existing `nonto/huawei_push_diagnostics` native MethodChannel added in v8.4. Expand the returned diagnostic map and Dart display/formatting only; no business push behavior changes.

**Tech Stack:** Flutter/Dart, Kotlin Android, Huawei HMS Push SDK, `flutter_test` source regression tests.

---

### Task 1: Regression test for AAID and sender-id token fields

**Files:**
- Modify: `D:/FlutterProject/nonto/test/push_diagnostics_regression_test.dart`

- [ ] **Step 1: Update the existing Huawei raw token diagnostics test**

Add expectations for these strings:

```dart
expect(diagnostics, contains('huawei_aaid'));
expect(diagnostics, contains('huawei_token_by_app_id'));
expect(diagnostics, contains('huawei_token_by_sender_id'));
expect(screen, contains('Huawei AAID'));
expect(screen, contains('Huawei token by app id'));
expect(screen, contains('Huawei token by sender id'));
expect(activity, contains('101653523864368310'));
expect(activity, contains('huawei_token_by_sender_id_error'));
```

- [ ] **Step 2: Run the test to verify RED**

```bash
cd /d/FlutterProject/nonto
flutter test test/push_diagnostics_regression_test.dart
```

Expected: FAIL because sender-id token and AAID fields are not implemented yet.

### Task 2: Native diagnostic expansion

**Files:**
- Modify: `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt`

- [ ] **Step 1: Add sender ID constant**

Add near the existing channel constants:

```kotlin
private val huaweiPushSenderId = "101653523864368310"
```

- [ ] **Step 2: Expand `collectHuaweiPushDiagnostics` map**

Return:

```kotlin
"huawei_aaid" to "",
"huawei_token_by_app_id" to "",
"huawei_token_by_sender_id" to "",
"huawei_token_by_sender_id_error" to ""
```

- [ ] **Step 3: Fetch AAID, app-id token, and sender-id token**

Inside the existing background thread:

```kotlin
val hms = HmsInstanceId.getInstance(this)
diagnostics["huawei_aaid"] = hms.id ?: ""
diagnostics["huawei_token_by_app_id"] = hms.getToken(appId, "HCM") ?: ""
try {
    diagnostics["huawei_token_by_sender_id"] = hms.getToken(huaweiPushSenderId, "HCM") ?: ""
} catch (e: Exception) {
    diagnostics["huawei_token_by_sender_id_error"] = e.toString()
}
```

Keep `huawei_raw_token` populated with the app-id token for backwards compatibility.

### Task 3: Dart formatting and screen rows

**Files:**
- Modify: `D:/FlutterProject/nonto/lib/services/push_diagnostics_service.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/profile/push_diagnostics_screen.dart`

- [ ] **Step 1: Add formatted diagnostic lines**

In `[华为原始推送]`, include:

```dart
..writeln('AAID: ${huaweiPush['huawei_aaid'] ?? ''}')
..writeln('token by app id: ${huaweiPush['huawei_token_by_app_id'] ?? ''}')
..writeln('token by sender id: ${huaweiPush['huawei_token_by_sender_id'] ?? ''}')
..writeln('sender id token error: ${huaweiPush['huawei_token_by_sender_id_error'] ?? ''}')
```

- [ ] **Step 2: Add UI rows**

In `PushDiagnosticsScreen`, add rows for:

```dart
_buildRow('Huawei AAID', map['huawei_aaid']),
_buildRow('Huawei token by app id', map['huawei_token_by_app_id']),
_buildRow('Huawei token by sender id', map['huawei_token_by_sender_id']),
_buildRow('Huawei sender token error', map['huawei_token_by_sender_id_error']),
```

### Task 4: Verify and build v8.5 arm64 APK

**Files:**
- Output: `C:/Users/25318/Desktop/nonto测试v8.5.apk`

- [ ] **Step 1: Run targeted test**

```bash
cd /d/FlutterProject/nonto
flutter test test/push_diagnostics_regression_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Run targeted analyze**

```bash
cd /d/FlutterProject/nonto
flutter analyze lib/services/push_diagnostics_service.dart lib/screens/profile/push_diagnostics_screen.dart android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt
```

Expected: no issues.

- [ ] **Step 3: Build arm64 release**

```bash
cd /d/FlutterProject/nonto
flutter build apk --release --target-platform android-arm64
```

Expected: arm64 release APK built.

- [ ] **Step 4: Copy to desktop**

```bash
cp /d/FlutterProject/nonto/build/app/outputs/flutter-apk/app-release.apk /c/Users/25318/Desktop/nonto测试v8.5.apk
```

Expected: desktop APK exists.

---

## Self-review

- Scope is limited to diagnostics for Huawei Console token validation.
- Sender ID is from Huawei Push Kit page and not a secret.
- No push business behavior changes are included.
- Existing v8.4 raw token remains displayed for continuity.
