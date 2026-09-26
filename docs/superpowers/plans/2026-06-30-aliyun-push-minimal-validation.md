# Aliyun Push Minimal Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add minimal Aliyun Mobile Push validation to the Flutter Android app so Huawei release devices can receive Aliyun console test pushes.

**Architecture:** Use `aliyun_push_flutter` from Dart for SDK initialization and callbacks. Store secrets in ignored `android/local.properties`, inject them into Android manifest placeholders and `BuildConfig`, and expose a small native MethodChannel so Flutter can initialize without hardcoded credentials.

**Tech Stack:** Flutter/Dart, Android Kotlin, Gradle Kotlin DSL, AndroidManifest metadata, `aliyun_push_flutter`, SharedPreferences diagnostics.

---

## File Structure

- Modify `D:\FlutterProject\nonto\pubspec.yaml`: add `aliyun_push_flutter` dependency.
- Modify `D:\FlutterProject\nonto\android\build.gradle.kts`: add Aliyun/Huawei/Honor Maven repositories.
- Modify `D:\FlutterProject\nonto\android\app\build.gradle.kts`: read push config from `local.properties`, enable `buildConfig`, set manifest placeholders, and add BuildConfig string fields.
- Modify `D:\FlutterProject\nonto\android\app\src\main\AndroidManifest.xml`: add Aliyun/vendor metadata, Aliyun receiver, popup activity, and badge permissions.
- Modify `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\MainActivity.kt`: expose `getAliyunPushConfig` through MethodChannel.
- Create `D:\FlutterProject\nonto\lib\services\aliyun_push_service.dart`: initialize Aliyun Push, Android third-party push, collect callbacks, and provide diagnostics.
- Modify `D:\FlutterProject\nonto\lib\main.dart`: initialize `AliyunPushService` during startup.
- Modify `D:\FlutterProject\nonto\lib\services\push_diagnostics_service.dart`: include Aliyun diagnostics in collected/formatted output.
- Modify `D:\FlutterProject\nonto\lib\screens\profile\push_diagnostics_screen.dart`: show Aliyun diagnostics section.
- Modify ignored `D:\FlutterProject\nonto\android\local.properties`: add local Aliyun push secrets from the desktop configuration file.

## Tasks

### Task 1: Add Flutter dependency

- [ ] Add `aliyun_push_flutter: ^1.3.7` under dependencies in `pubspec.yaml`.
- [ ] Run `flutter pub get` from `D:\FlutterProject\nonto`.
- [ ] Verify generated dependency resolution succeeds.

### Task 2: Add Android repository/config injection

- [ ] Add Aliyun release Maven repository and Huawei/Honor repositories to `android/build.gradle.kts`.
- [ ] Add helper function in `android/app/build.gradle.kts` to read values from root `local.properties`.
- [ ] Enable `buildFeatures { buildConfig = true }`.
- [ ] Add manifest placeholders for Aliyun AppKey/AppSecret, Huawei AppID, OPPO AppKey/AppSecret, vivo AppID/AppKey.
- [ ] Add BuildConfig string fields for the same values.
- [ ] Add ignored local properties with real values from `C:\Users\25318\Desktop\推送\阿里云推送配置.txt`.

### Task 3: Add Android manifest and native bridge

- [ ] Add badge permissions for Huawei/Honor/vivo.
- [ ] Add metadata inside `<application>` for Aliyun, Huawei, OPPO, and vivo.
- [ ] Add `com.aliyun.ams.push.AliyunPushMessageReceiver` receiver.
- [ ] Add `com.aliyun.ams.push.PushPopupActivity` activity.
- [ ] Add a `nonto/aliyun_push_config` MethodChannel to `MainActivity.kt`.
- [ ] Implement `getAliyunPushConfig` returning config without logging secrets.

### Task 4: Add Dart AliyunPushService

- [ ] Create `lib/services/aliyun_push_service.dart`.
- [ ] Use `AliyunPushFlutter` to add all message receivers.
- [ ] Load Android config through MethodChannel.
- [ ] Call `createAndroidChannel('nonto_message', '南图消息通知', 3, '南图消息与互动通知')`.
- [ ] Call `initPush(appKey, appSecret)` and record result.
- [ ] Call `initAndroidThirdPush()` on Android and record result.
- [ ] Call `getDeviceId()` and record the device ID.
- [ ] Store diagnostics in SharedPreferences.

### Task 5: Wire startup and diagnostics UI

- [ ] Import `AliyunPushService` in `main.dart`.
- [ ] Call `await AliyunPushService().init();` after `LocalNotificationService().init()`.
- [ ] Extend `PushDiagnosticsService.collect()` with `aliyunPush` diagnostics.
- [ ] Extend formatted diagnostics text with Aliyun fields.
- [ ] Add an `阿里云推送` section to `PushDiagnosticsScreen`.

### Task 6: Verify

- [ ] Run `flutter pub get`.
- [ ] Run `flutter analyze` or targeted analyzer if the full project has unrelated issues.
- [ ] Run Android debug build if dependencies resolve.
- [ ] If build succeeds, use Huawei release APK for device validation outside this session.
