# Aliyun Push Minimal Validation Design

## Context

The current Android notification path is WebSocket plus local notifications. It works while the app or foreground service remains alive, but Huawei devices can restrict background networking. The project already has Alibaba Cloud Mobile Push console credentials and vendor channel configuration for Huawei, OPPO, and vivo.

## Goal

Add a minimal Android validation path for Alibaba Cloud Mobile Push so a release APK can initialize Aliyun Push, initialize Android third-party vendor channels, expose diagnostics, and receive test pushes from the Aliyun console.

## Non-goals

- No backend push sending service yet.
- No user-device binding API yet.
- No notification deduplication with WebSocket yet.
- No iOS push setup.
- No business notification routing beyond storing callback payloads for diagnostics.

## Client architecture

Use the Flutter package `aliyun_push_flutter` for the Flutter-facing API. Add a new `AliyunPushService` singleton responsible for:

1. Loading Android push config from a native MethodChannel.
2. Registering Aliyun callback receivers.
3. Creating the Android notification channel used by Aliyun Push.
4. Calling `initPush` with Android AppKey/AppSecret.
5. Calling `initAndroidThirdPush` for vendor channels.
6. Reading and storing the Aliyun device ID.
7. Writing diagnostic fields to `SharedPreferences`.

The service is initialized during app startup after local notification initialization.

## Android native configuration

Do not hardcode secrets in source files. Read push values from ignored `android/local.properties`, then inject them into:

- AndroidManifest placeholders for Aliyun and vendor metadata.
- `BuildConfig` fields used by `MainActivity` to return config to Flutter through MethodChannel.

The Android manifest adds:

- Aliyun AppKey/AppSecret metadata.
- Huawei AppID metadata using `appid=<value>` format.
- OPPO AppKey/AppSecret metadata.
- vivo AppID/AppKey metadata.
- Aliyun push receiver.
- Aliyun push popup activity.
- Optional launcher badge permissions for Huawei/Honor/vivo.

## Diagnostics

Extend the existing push diagnostics screen and service to include an `Aliyun Push` section with:

- supported platform flag
- initialized flag
- init success/failure details
- third-party channel init result
- device ID
- last callback type and payload summary
- last error

## Secret handling

The desktop text file contains sensitive push credentials. Values are copied only into `android/local.properties`, which is already ignored by Git. Source-controlled files only contain placeholder names.

## Validation

Local validation:

1. `flutter pub get`
2. `flutter analyze` or a targeted Dart analysis if full analyze is too noisy.
3. Android debug build if dependencies resolve.

Device validation:

1. Build a release APK with the real release signing key.
2. Install on Huawei device.
3. Open app once and grant notification permission.
4. Open the hidden diagnostics page and confirm Aliyun init success plus non-empty device ID.
5. Send a test push from Aliyun console.
6. Confirm Huawei notification appears and click callback is recorded.
