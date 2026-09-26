# Android Vendor Push Channel Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Android release APK capable of using JPush vendor offline channels and improve backend diagnostics for failed vendor push delivery.

**Architecture:** Use source-contract regression tests to lock in Android build configuration, release signing behavior, Flutter deep-link handling, and backend JPush diagnostics. Keep push architecture unchanged: Flutter registers JPush registrationId, backend sends JPush Android notification payload with `third_party_channel`, and vendor delivery is enabled by APK dependencies/signing plus console credentials.

**Tech Stack:** Flutter/Dart, Android Gradle Kotlin DSL, Kotlin `MainActivity`, FastAPI/Python, pytest/unittest, JPush Flutter plugin and JPush Android SDK.

---

## File Structure

- Modify `D:/FlutterProject/nonto/android/app/build.gradle.kts`
  - Read all vendor credentials from Gradle properties or environment variables.
  - Add JPush vendor plugin dependencies.
  - Make release build use release signing when available.
- Modify `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt`
  - Disable Flutter automatic deep-link handling for vendor notification click intents.
- Create `D:/FlutterProject/nonto/test/android_vendor_push_channel_regression_test.dart`
  - Source-contract tests for Gradle vendor placeholders, plugin dependencies, release signing, and deep-link handling.
- Modify `D:/NanTuPy/app/services/push_service.py`
  - Add enabled channel diagnostics to JPush success and failure logs.
- Modify `D:/NanTuPy/tests/test_push_device_state_contracts.py`
  - Add a source-contract test that JPush logs expose third-party channel diagnostics.

---

### Task 1: Add Android vendor push source-contract tests

**Files:**
- Create: `D:/FlutterProject/nonto/test/android_vendor_push_channel_regression_test.dart`

- [ ] **Step 1: Write failing tests**

Create `D:/FlutterProject/nonto/test/android_vendor_push_channel_regression_test.dart` with exactly:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Android vendor push channel configuration', () {
    test('vendor credentials are read from Gradle properties or environment', () {
      final source = read('android/app/build.gradle.kts');

      expect(source, contains('fun gradleOrEnv(name: String): String'));
      expect(
        source,
        contains('providers.gradleProperty(name)\n    .orElse(providers.environmentVariable(name))'),
      );
      for (final key in [
        'HUAWEI_APPID',
        'XIAOMI_APPID',
        'XIAOMI_APPKEY',
        'OPPO_APPID',
        'OPPO_APPKEY',
        'OPPO_APPSECRET',
        'VIVO_APPID',
        'VIVO_APPKEY',
        'MEIZU_APPID',
        'MEIZU_APPKEY',
      ]) {
        expect(source, contains('manifestPlaceholders["$key"] = gradleOrEnv("$key")'));
      }
    });

    test('JPush vendor channel plugin dependencies are packaged into Android app', () {
      final source = read('android/app/build.gradle.kts');

      for (final artifact in [
        'cn.jiguang.sdk.plugin:huawei',
        'cn.jiguang.sdk.plugin:xiaomi',
        'cn.jiguang.sdk.plugin:oppo',
        'cn.jiguang.sdk.plugin:vivo',
        'cn.jiguang.sdk.plugin:meizu',
      ]) {
        expect(source, contains('implementation("$artifact:'));
      }
    });

    test('release build prefers release signing instead of hard-coded debug signing', () {
      final source = read('android/app/build.gradle.kts');
      final releaseStart = source.indexOf('release {');
      final androidEnd = source.indexOf('\n}\n\nflutter {', releaseStart);
      expect(releaseStart, greaterThanOrEqualTo(0));
      expect(androidEnd, greaterThan(releaseStart));
      final releaseSource = source.substring(releaseStart, androidEnd);

      expect(releaseSource, isNot(contains('signingConfig = signingConfigs.getByName("debug")')));
      expect(
        releaseSource,
        contains('signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")'),
      );
    });

    test('MainActivity disables Flutter automatic deep link handling for vendor notification clicks', () {
      final source = read('android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt');

      expect(source, contains('override fun shouldHandleDeeplinking(): Boolean'));
      expect(source, contains('return false'));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/android_vendor_push_channel_regression_test.dart
```

Expected: FAIL because `gradleOrEnv`, vendor plugin dependencies, release signing fallback expression, and `shouldHandleDeeplinking` are not implemented yet.

- [ ] **Step 3: Commit failing test**

Run:

```bash
git -C D:/FlutterProject/nonto add test/android_vendor_push_channel_regression_test.dart
git -C D:/FlutterProject/nonto commit -m "test: cover Android vendor push channel config"
```

---

### Task 2: Fix Android Gradle vendor placeholders, plugin dependencies, and release signing

**Files:**
- Modify: `D:/FlutterProject/nonto/android/app/build.gradle.kts`
- Test: `D:/FlutterProject/nonto/test/android_vendor_push_channel_regression_test.dart`

- [ ] **Step 1: Replace the Huawei-only property block**

In `D:/FlutterProject/nonto/android/app/build.gradle.kts`, replace:

```kotlin
val huaweiAppId = providers.gradleProperty("HUAWEI_APPID")
    .orElse(providers.environmentVariable("HUAWEI_APPID"))
    .orElse("")
    .get()
```

with:

```kotlin
fun gradleOrEnv(name: String): String = providers.gradleProperty(name)
    .orElse(providers.environmentVariable(name))
    .orElse("")
    .get()
```

- [ ] **Step 2: Replace vendor manifest placeholders**

In `defaultConfig`, replace the vendor placeholder block:

```kotlin
        manifestPlaceholders["HUAWEI_APPID"] = huaweiAppId
        manifestPlaceholders["XIAOMI_APPID"] = ""
        manifestPlaceholders["XIAOMI_APPKEY"] = ""
        manifestPlaceholders["OPPO_APPKEY"] = ""
        manifestPlaceholders["OPPO_APPID"] = ""
        manifestPlaceholders["OPPO_APPSECRET"] = ""
        manifestPlaceholders["VIVO_APPKEY"] = ""
        manifestPlaceholders["VIVO_APPID"] = ""
        manifestPlaceholders["MEIZU_APPID"] = ""
        manifestPlaceholders["MEIZU_APPKEY"] = ""
```

with:

```kotlin
        manifestPlaceholders["HUAWEI_APPID"] = gradleOrEnv("HUAWEI_APPID")
        manifestPlaceholders["XIAOMI_APPID"] = gradleOrEnv("XIAOMI_APPID")
        manifestPlaceholders["XIAOMI_APPKEY"] = gradleOrEnv("XIAOMI_APPKEY")
        manifestPlaceholders["OPPO_APPKEY"] = gradleOrEnv("OPPO_APPKEY")
        manifestPlaceholders["OPPO_APPID"] = gradleOrEnv("OPPO_APPID")
        manifestPlaceholders["OPPO_APPSECRET"] = gradleOrEnv("OPPO_APPSECRET")
        manifestPlaceholders["VIVO_APPKEY"] = gradleOrEnv("VIVO_APPKEY")
        manifestPlaceholders["VIVO_APPID"] = gradleOrEnv("VIVO_APPID")
        manifestPlaceholders["MEIZU_APPID"] = gradleOrEnv("MEIZU_APPID")
        manifestPlaceholders["MEIZU_APPKEY"] = gradleOrEnv("MEIZU_APPKEY")
```

- [ ] **Step 3: Replace release signing config**

In `buildTypes.release`, replace:

```kotlin
            // 先使用调试签名测试构建是否正常
            signingConfig = signingConfigs.getByName("debug")
            // 暂时禁用代码压缩和混淆以排查问题
```

with:

```kotlin
            // 厂商通道会校验包名 + 签名证书；有 release keystore 时必须使用正式签名。
            // 没有 key.properties 的本地开发环境降级 debug，但该 APK 不能用于厂商通道验收。
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // 暂时禁用代码压缩和混淆以排查问题
```

- [ ] **Step 4: Add app-level dependencies block**

At the end of `D:/FlutterProject/nonto/android/app/build.gradle.kts`, after the existing `flutter { ... }` block, add:

```kotlin
dependencies {
    val jpushVendorPluginVersion = "6.1.0"
    implementation("cn.jiguang.sdk.plugin:huawei:$jpushVendorPluginVersion")
    implementation("cn.jiguang.sdk.plugin:xiaomi:$jpushVendorPluginVersion")
    implementation("cn.jiguang.sdk.plugin:oppo:$jpushVendorPluginVersion")
    implementation("cn.jiguang.sdk.plugin:vivo:$jpushVendorPluginVersion")
    implementation("cn.jiguang.sdk.plugin:meizu:$jpushVendorPluginVersion")
}
```

- [ ] **Step 5: Run focused Android vendor config test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/android_vendor_push_channel_regression_test.dart
```

Expected: PASS. If this fails because a source-contract string differs, inspect the failure and align code/test only if behavior remains unchanged.

- [ ] **Step 6: Commit Android Gradle fix**

Run:

```bash
git -C D:/FlutterProject/nonto add android/app/build.gradle.kts
git -C D:/FlutterProject/nonto commit -m "fix: package Android vendor push channels"
```

---

### Task 3: Disable Flutter deep-link handling for vendor notification click intents

**Files:**
- Modify: `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt`
- Test: `D:/FlutterProject/nonto/test/android_vendor_push_channel_regression_test.dart`

- [ ] **Step 1: Add `shouldHandleDeeplinking` override**

Change `MainActivity.kt` from:

```kotlin
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
```

to:

```kotlin
class MainActivity : FlutterActivity() {
    // Flutter 3.29+ 会默认把厂商离线通知点击 intent.data 当作 deep link 处理，
    // 极光厂商通道可能携带 n_extra 等参数，自动解析会导致无匹配路由或白屏。
    override fun shouldHandleDeeplinking(): Boolean {
        return false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
```

- [ ] **Step 2: Run focused Android vendor config test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/android_vendor_push_channel_regression_test.dart
```

Expected: PASS.

- [ ] **Step 3: Commit MainActivity fix**

Run:

```bash
git -C D:/FlutterProject/nonto add android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt
git -C D:/FlutterProject/nonto commit -m "fix: disable Flutter deep links for vendor push clicks"
```

---

### Task 4: Add backend JPush diagnostic test and logging

**Files:**
- Modify: `D:/NanTuPy/tests/test_push_device_state_contracts.py`
- Modify: `D:/NanTuPy/app/services/push_service.py`

- [ ] **Step 1: Add failing backend source-contract test**

In `D:/NanTuPy/tests/test_push_device_state_contracts.py`, add this test method inside `PushDeviceStateContractTests` after `test_payload_third_party_channel_is_config_gated`:

```python
    def test_jpush_send_logs_include_third_party_channel_diagnostics(self):
        source = inspect.getsource(PushService.send_to_user)

        self.assertIn('channels=%s', source)
        self.assertIn('Config.JPUSH_THIRD_PARTY_CHANNELS', source)
        self.assertIn('third_party=%s', source)
        self.assertIn('resp.text[:300]', source)
```

- [ ] **Step 2: Run backend push tests to verify RED**

Run:

```bash
cd /d/NanTuPy && .venv/Scripts/python.exe -m pytest tests/test_push_device_state_contracts.py -q
```

Expected: FAIL because logs do not include `channels=%s` diagnostics yet.

- [ ] **Step 3: Add enabled channel diagnostics in `send_to_user`**

In `D:/NanTuPy/app/services/push_service.py`, after payload creation:

```python
        payload = cls.build_android_payload(
            reg_ids=reg_ids,
            alert_title=alert_title,
            alert_content=alert_content,
            extras=extras,
        )
```

add:

```python
        enabled_channels = sorted(Config.JPUSH_THIRD_PARTY_CHANNELS)
```

Then replace the success log block:

```python
                logger.info(
                    "[JPUSH] pushed uid=%s targets=%s type=%s third_party=%s",
                    user_id,
                    len(reg_ids),
                    extras.get("type"),
                    Config.JPUSH_ENABLE_THIRD_PARTY_CHANNEL,
                )
```

with:

```python
                logger.info(
                    "[JPUSH] pushed uid=%s targets=%s type=%s third_party=%s channels=%s",
                    user_id,
                    len(reg_ids),
                    extras.get("type"),
                    Config.JPUSH_ENABLE_THIRD_PARTY_CHANNEL,
                    enabled_channels,
                )
```

Replace the failure log block:

```python
            logger.warning(
                "[JPUSH] push failed uid=%s targets=%s status=%s body=%s",
                user_id,
                len(reg_ids),
                resp.status_code,
                resp.text[:300],
            )
```

with:

```python
            logger.warning(
                "[JPUSH] push failed uid=%s targets=%s status=%s third_party=%s channels=%s body=%s",
                user_id,
                len(reg_ids),
                resp.status_code,
                Config.JPUSH_ENABLE_THIRD_PARTY_CHANNEL,
                enabled_channels,
                resp.text[:300],
            )
```

- [ ] **Step 4: Run backend push tests to verify GREEN**

Run:

```bash
cd /d/NanTuPy && .venv/Scripts/python.exe -m pytest tests/test_push_device_state_contracts.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit backend diagnostic fix**

Run:

```bash
git -C D:/NanTuPy add app/services/push_service.py tests/test_push_device_state_contracts.py
git -C D:/NanTuPy commit -m "fix: log JPush vendor channel diagnostics"
```

---

### Task 5: Full verification and APK build

**Files:**
- Verify all changed frontend/backend files.

- [ ] **Step 1: Run focused Flutter vendor test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/android_vendor_push_channel_regression_test.dart
```

Expected: All tests pass.

- [ ] **Step 2: Run existing focused Flutter regression tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/remaining_ux_identity_unread_regression_test.dart test/chat_time_and_community_dedupe_regression_test.dart test/android_vendor_push_channel_regression_test.dart
```

Expected: All tests pass.

- [ ] **Step 3: Run Flutter analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Run backend push and identity tests**

Run:

```bash
cd /d/NanTuPy && .venv/Scripts/python.exe -m pytest tests/test_push_device_state_contracts.py tests/test_identity_role_contracts.py -q
```

Expected: All tests pass.

- [ ] **Step 5: Build release APK**

Run:

```bash
cd /d/FlutterProject/nonto && flutter build apk --release --target-platform android-arm64
```

Expected: Build succeeds and prints `Built build\app\outputs\flutter-apk\app-release.apk`.

If Gradle fails to resolve one of the `cn.jiguang.sdk.plugin:*:6.1.0` dependencies, do not remove vendor coverage. Use the exact Gradle error to switch all vendor plugin dependencies to a JPush-compatible version available from configured Maven repositories, rerun the focused test/build, and document the selected version in the final report.

- [ ] **Step 6: Check git status**

Run:

```bash
git -C D:/FlutterProject/nonto status --short --branch
git -C D:/NanTuPy status --short --branch
```

Expected: clean working trees, each branch ahead of remote by the new commits.

---

## Self-Review

- Spec coverage: Android vendor plugin packaging, release signing, deep-link handling, backend third-party channel diagnostics, tests, analyzer, and APK build are covered.
- Placeholder scan: no `TBD`, no unresolved implementation placeholders; private vendor credentials remain intentionally injected via environment/Gradle properties.
- Type consistency: Gradle function name `gradleOrEnv`, Kotlin method `shouldHandleDeeplinking`, and Python test/log strings match the implementation steps.
