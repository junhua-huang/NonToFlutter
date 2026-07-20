# Huawei Raw Token Diagnostics v8.4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimal Android-only diagnostic that exposes the raw Huawei Push Kit token so Huawei Console direct-send testing can isolate Huawei-vs-Aliyun delivery failures.

**Architecture:** Add one native Android MethodChannel in `MainActivity` that calls Huawei HMS Push Kit for a raw token on a background thread. Extend `PushDiagnosticsService` and `PushDiagnosticsScreen` to collect and display the token/error without changing business push behavior.

**Tech Stack:** Flutter/Dart, Kotlin Android, Huawei HMS Push SDK already present transitively through Aliyun third-push dependency, `flutter_test` source regression tests.

---

### Task 1: Regression test for Huawei raw token diagnostics

**Files:**
- Modify: `D:/FlutterProject/nonto/test/push_diagnostics_regression_test.dart`

- [ ] **Step 1: Add a failing source regression test**

Add a test that expects:
- `PushDiagnosticsService` uses `MethodChannel('nonto/huawei_push_diagnostics')`
- diagnostics map includes `huaweiPush`
- diagnostics screen displays `Huawei raw token` and `Huawei token error`
- `MainActivity.kt` exposes `getHuaweiPushDiagnostics` and uses `HmsInstanceId`

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
cd /d/FlutterProject/nonto
flutter test test/push_diagnostics_regression_test.dart
```

Expected: FAIL because the Huawei raw token diagnostics channel/fields do not exist.

### Task 2: Android native Huawei token channel

**Files:**
- Modify: `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt`

- [ ] **Step 1: Add imports**

Add:

```kotlin
import com.huawei.hms.aaid.HmsInstanceId
import kotlin.concurrent.thread
```

- [ ] **Step 2: Add channel constant**

Add:

```kotlin
private val huaweiPushDiagnosticsChannel = "nonto/huawei_push_diagnostics"
```

- [ ] **Step 3: Register MethodChannel**

In `configureFlutterEngine`, register:

```kotlin
MethodChannel(
    flutterEngine.dartExecutor.binaryMessenger,
    huaweiPushDiagnosticsChannel
).setMethodCallHandler { call, result ->
    when (call.method) {
        "getHuaweiPushDiagnostics" -> collectHuaweiPushDiagnostics(result)
        else -> result.notImplemented()
    }
}
```

- [ ] **Step 4: Implement background token fetch**

Add:

```kotlin
private fun collectHuaweiPushDiagnostics(result: MethodChannel.Result) {
    thread {
        val diagnostics = linkedMapOf<String, Any?>(
            "huawei_raw_token_at" to System.currentTimeMillis().toString(),
            "huawei_raw_token" to "",
            "huawei_raw_token_error" to ""
        )
        try {
            val appId = BuildConfig.HUAWEI_PUSH_APP_ID
            diagnostics["huawei_app_id_configured"] = appId.isNotBlank()
            if (appId.isBlank()) {
                diagnostics["huawei_raw_token_error"] = "missing_huawei_app_id"
            } else {
                diagnostics["huawei_raw_token"] = HmsInstanceId.getInstance(this).getToken(appId, "HCM") ?: ""
            }
        } catch (e: Exception) {
            diagnostics["huawei_raw_token_error"] = e.toString()
        }
        runOnUiThread { result.success(diagnostics) }
    }
}
```

### Task 3: Dart diagnostics collection and display

**Files:**
- Modify: `D:/FlutterProject/nonto/lib/services/push_diagnostics_service.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/profile/push_diagnostics_screen.dart`

- [ ] **Step 1: Add Dart MethodChannel**

Add to `PushDiagnosticsService`:

```dart
static const MethodChannel _huaweiPushChannel =
    MethodChannel('nonto/huawei_push_diagnostics');
```

- [ ] **Step 2: Collect Huawei diagnostics**

Add `huaweiPush` to the diagnostics map and call native channel only on Android with a 10-second timeout. On exception, set `huawei_raw_token_error`.

- [ ] **Step 3: Format Huawei diagnostics**

Add a `[华为原始推送]` section with:
- app id configured
- raw token
- token at
- token error

- [ ] **Step 4: Display Huawei diagnostics**

Add a screen section `华为原始推送` and rows:
- `Huawei app id configured`
- `Huawei raw token`
- `Huawei raw token at`
- `Huawei token error`

### Task 4: Verification and v8.4 arm64 package

**Files:**
- Output: `C:/Users/25318/Desktop/nonto测试v8.4.apk`

- [ ] **Step 1: Run targeted tests**

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

- [ ] **Step 3: Build arm64 release APK**

```bash
cd /d/FlutterProject/nonto
flutter build apk --release --target-platform android-arm64
```

Expected: `build/app/outputs/flutter-apk/app-release.apk` built.

- [ ] **Step 4: Copy to desktop**

```bash
cp /d/FlutterProject/nonto/build/app/outputs/flutter-apk/app-release.apk /c/Users/25318/Desktop/nonto测试v8.4.apk
```

Expected: desktop APK exists.

---

## Self-review

- Scope is limited to diagnostics and v8.4 build.
- No business push binding or sending is included.
- Huawei secret values are not printed or committed.
- If native token fetch fails, error is displayed in diagnostics rather than crashing.
