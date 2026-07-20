# Huawei Vendor Push Diagnostics v8.6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a v8.6 diagnostic APK that records native Aliyun and Huawei vendor push callbacks so killed/background Huawei notification failures can be isolated.

**Architecture:** Add small native Android diagnostic helpers that persist the last Aliyun receiver callback and the last Huawei HMS service callback to SharedPreferences. Reuse the existing `nonto/huawei_push_diagnostics` MethodChannel to expose the persisted state, then show it in the existing hidden Flutter diagnostics page. Do not change business push behavior except making the app's Aliyun receiver record diagnostics before forwarding callbacks to the Flutter plugin when available.

**Tech Stack:** Flutter/Dart, Kotlin Android, Alibaba Cloud Push SDK, Huawei HMS Push SDK, source-level Flutter regression tests, arm64 release APK build.

---

### Task 1: Add regression tests for v8.6 native callback diagnostics

**Files:**
- Modify: `D:/FlutterProject/nonto/test/push_diagnostics_regression_test.dart`
- Modify: `D:/FlutterProject/nonto/test/android_push_contract_test.dart`

- [ ] **Step 1: Update Huawei diagnostics source test**

In `push_diagnostics_regression_test.dart`, extend the Huawei diagnostics test to assert these source markers:

```dart
expect(diagnostics, contains('huaweiVendor'));
expect(diagnostics, contains('[华为厂商推送]'));
expect(diagnostics, contains('aliyunNative'));
expect(diagnostics, contains('[阿里云原生回调]'));
expect(screen, contains('华为厂商推送'));
expect(screen, contains('阿里云原生回调'));
expect(screen, contains('Huawei vendor event'));
expect(screen, contains('Aliyun native callback'));
expect(activity, contains('HuaweiPushDiagnosticsStore.snapshot'));
expect(activity, contains('AliyunNativePushDiagnosticsStore.snapshot'));
```

- [ ] **Step 2: Add Android manifest/native class contract test**

In `android_push_contract_test.dart`, add a test that reads:

```dart
final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
final aliyunReceiver = File(
        'android/app/src/main/kotlin/com/nonto/nonto/NontoAliyunPushMessageReceiver.kt')
    .readAsStringSync();
final huaweiService = File(
        'android/app/src/main/kotlin/com/nonto/nonto/HuaweiPushDiagnosticsService.kt')
    .readAsStringSync();
final store = File(
        'android/app/src/main/kotlin/com/nonto/nonto/NativePushDiagnosticsStore.kt')
    .readAsStringSync();
```

Assert:

```dart
expect(manifest, contains('.NontoAliyunPushMessageReceiver'));
expect(manifest, contains('.HuaweiPushDiagnosticsService'));
expect(manifest, contains('com.huawei.push.action.MESSAGING_EVENT'));
expect(aliyunReceiver, contains('MessageReceiver'));
expect(aliyunReceiver, contains('onNotificationReceivedInApp'));
expect(aliyunReceiver, contains('showNotificationNow'));
expect(aliyunReceiver, contains('nonto_message_alerts'));
expect(aliyunReceiver, contains('AliyunNativePushDiagnosticsStore.record'));
expect(huaweiService, contains('HmsMessageService'));
expect(huaweiService, contains('onMessageReceived'));
expect(huaweiService, contains('onNewToken'));
expect(huaweiService, contains('HuaweiPushDiagnosticsStore.record'));
expect(store, contains('HuaweiPushDiagnosticsStore'));
expect(store, contains('AliyunNativePushDiagnosticsStore'));
```

- [ ] **Step 3: Run tests to verify RED**

```bash
cd /d/FlutterProject/nonto
flutter test test/push_diagnostics_regression_test.dart test/android_push_contract_test.dart
```

Expected: FAIL because the new native files and diagnostics fields do not exist yet.

### Task 2: Implement native diagnostic stores and receivers

**Files:**
- Create: `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/NativePushDiagnosticsStore.kt`
- Create: `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/NontoAliyunPushMessageReceiver.kt`
- Create: `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/HuaweiPushDiagnosticsService.kt`
- Modify: `D:/FlutterProject/nonto/android/app/src/main/AndroidManifest.xml`
- Modify: `D:/FlutterProject/nonto/android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt`

- [ ] **Step 1: Create SharedPreferences diagnostic stores**

Create `NativePushDiagnosticsStore.kt` with two objects:

```kotlin
package com.nonto.nonto

import android.content.Context

private const val PREFS = "nonto_native_push_diagnostics"

object HuaweiPushDiagnosticsStore {
    fun record(context: Context, event: String, values: Map<String, Any?> = emptyMap()) {
        val editor = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("huawei_vendor_last_event", event)
            .putString("huawei_vendor_last_event_at", System.currentTimeMillis().toString())
        values.forEach { (key, value) ->
            editor.putString("huawei_vendor_$key", value?.toString().orEmpty())
        }
        editor.apply()
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return linkedMapOf(
            "huawei_vendor_last_event" to prefs.getString("huawei_vendor_last_event", ""),
            "huawei_vendor_last_event_at" to prefs.getString("huawei_vendor_last_event_at", ""),
            "huawei_vendor_token" to prefs.getString("huawei_vendor_token", ""),
            "huawei_vendor_message_id" to prefs.getString("huawei_vendor_message_id", ""),
            "huawei_vendor_message_type" to prefs.getString("huawei_vendor_message_type", ""),
            "huawei_vendor_data" to prefs.getString("huawei_vendor_data", ""),
            "huawei_vendor_title" to prefs.getString("huawei_vendor_title", ""),
            "huawei_vendor_body" to prefs.getString("huawei_vendor_body", ""),
            "huawei_vendor_error" to prefs.getString("huawei_vendor_error", "")
        )
    }
}

object AliyunNativePushDiagnosticsStore {
    fun record(context: Context, callback: String, values: Map<String, Any?> = emptyMap()) {
        val editor = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("aliyun_native_last_callback", callback)
            .putString("aliyun_native_last_callback_at", System.currentTimeMillis().toString())
        values.forEach { (key, value) ->
            editor.putString("aliyun_native_$key", value?.toString().orEmpty())
        }
        editor.apply()
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return linkedMapOf(
            "aliyun_native_last_callback" to prefs.getString("aliyun_native_last_callback", ""),
            "aliyun_native_last_callback_at" to prefs.getString("aliyun_native_last_callback_at", ""),
            "aliyun_native_title" to prefs.getString("aliyun_native_title", ""),
            "aliyun_native_summary" to prefs.getString("aliyun_native_summary", ""),
            "aliyun_native_content" to prefs.getString("aliyun_native_content", ""),
            "aliyun_native_message_id" to prefs.getString("aliyun_native_message_id", ""),
            "aliyun_native_extra" to prefs.getString("aliyun_native_extra", ""),
            "aliyun_native_open_type" to prefs.getString("aliyun_native_open_type", ""),
            "aliyun_native_open_activity" to prefs.getString("aliyun_native_open_activity", ""),
            "aliyun_native_open_url" to prefs.getString("aliyun_native_open_url", ""),
            "aliyun_native_error" to prefs.getString("aliyun_native_error", "")
        )
    }
}
```

- [ ] **Step 2: Create app-owned Aliyun receiver**

Create `NontoAliyunPushMessageReceiver.kt`. It should extend `com.alibaba.sdk.android.push.MessageReceiver`, record every callback to `AliyunNativePushDiagnosticsStore`, force online notifications to use `nonto_message_alerts` in `hookNotificationBuild`, and safely forward callbacks to the Flutter plugin if it is initialized:

```kotlin
package com.nonto.nonto

import android.app.Notification
import android.content.Context
import androidx.core.app.NotificationCompat
import com.alibaba.sdk.android.push.MessageReceiver
import com.alibaba.sdk.android.push.notification.CPushMessage
import com.alibaba.sdk.android.push.notification.NotificationConfigure
import com.alibaba.sdk.android.push.notification.PushData
import com.aliyun.ams.push.AliyunPushPlugin

class NontoAliyunPushMessageReceiver : MessageReceiver() {
    override fun hookNotificationBuild(): NotificationConfigure {
        return object : NotificationConfigure {
            override fun configBuilder(builder: Notification.Builder, pushData: PushData) {
                builder.setChannelId("nonto_message_alerts")
            }

            override fun configBuilder(builder: NotificationCompat.Builder, pushData: PushData) {
                builder.setChannelId("nonto_message_alerts")
                builder.priority = NotificationCompat.PRIORITY_HIGH
            }

            override fun configNotification(notification: Notification, pushData: PushData) = Unit
        }
    }

    override fun showNotificationNow(context: Context, map: Map<String, String>): Boolean {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "showNotificationNow",
            mapOf("extra" to map.toString())
        )
        return super.showNotificationNow(context, map)
    }

    override fun onNotification(context: Context, title: String, summary: String, extraMap: Map<String, String>) {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "onNotification",
            mapOf("title" to title, "summary" to summary, "extra" to extraMap.toString())
        )
        callFlutter("onNotification", mapOf("title" to title, "summary" to summary, "extraMap" to extraMap))
    }

    override fun onNotificationReceivedInApp(
        context: Context,
        title: String,
        summary: String,
        extraMap: Map<String, String>,
        openType: Int,
        openActivity: String,
        openUrl: String
    ) {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "onNotificationReceivedInApp",
            mapOf(
                "title" to title,
                "summary" to summary,
                "extra" to extraMap.toString(),
                "open_type" to openType,
                "open_activity" to openActivity,
                "open_url" to openUrl
            )
        )
        callFlutter(
            "onNotificationReceivedInApp",
            mapOf(
                "title" to title,
                "summary" to summary,
                "extraMap" to extraMap,
                "openType" to openType,
                "openActivity" to openActivity,
                "openUrl" to openUrl
            )
        )
    }

    override fun onMessage(context: Context, cPushMessage: CPushMessage) {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "onMessage",
            mapOf(
                "title" to cPushMessage.title,
                "content" to cPushMessage.content,
                "message_id" to cPushMessage.messageId,
                "extra" to cPushMessage.traceInfo
            )
        )
        callFlutter(
            "onMessage",
            mapOf(
                "title" to cPushMessage.title,
                "content" to cPushMessage.content,
                "msgId" to cPushMessage.messageId,
                "appId" to cPushMessage.appId,
                "traceInfo" to cPushMessage.traceInfo
            )
        )
    }

    override fun onNotificationOpened(context: Context, title: String, summary: String, extraMap: String) {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "onNotificationOpened",
            mapOf("title" to title, "summary" to summary, "extra" to extraMap)
        )
        callFlutter("onNotificationOpened", mapOf("title" to title, "summary" to summary, "extraMap" to extraMap))
    }

    override fun onNotificationRemoved(context: Context, messageId: String) {
        AliyunNativePushDiagnosticsStore.record(context, "onNotificationRemoved", mapOf("message_id" to messageId))
        callFlutter("onNotificationRemoved", mapOf("msgId" to messageId))
    }

    override fun onNotificationClickedWithNoAction(context: Context, title: String, summary: String, extraMap: String) {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "onNotificationClickedWithNoAction",
            mapOf("title" to title, "summary" to summary, "extra" to extraMap)
        )
        callFlutter(
            "onNotificationClickedWithNoAction",
            mapOf("title" to title, "summary" to summary, "extraMap" to extraMap)
        )
    }

    private fun callFlutter(method: String, arguments: Map<String, Any?>) {
        try {
            AliyunPushPlugin.sInstance.callFlutterMethod(method, arguments)
        } catch (e: Exception) {
            // The Flutter engine can be absent for killed-state vendor callbacks.
        }
    }
}
```

- [ ] **Step 3: Create Huawei HMS diagnostic service**

Create `HuaweiPushDiagnosticsService.kt`:

```kotlin
package com.nonto.nonto

import com.huawei.hms.push.HmsMessageService
import com.huawei.hms.push.RemoteMessage

class HuaweiPushDiagnosticsService : HmsMessageService() {
    override fun onNewToken(token: String?) {
        super.onNewToken(token)
        HuaweiPushDiagnosticsStore.record(this, "onNewToken", mapOf("token" to token.orEmpty()))
    }

    override fun onMessageReceived(message: RemoteMessage?) {
        super.onMessageReceived(message)
        val notification = message?.notification
        HuaweiPushDiagnosticsStore.record(
            this,
            "onMessageReceived",
            mapOf(
                "message_id" to message?.messageId.orEmpty(),
                "message_type" to message?.messageType.orEmpty(),
                "data" to message?.data.orEmpty(),
                "title" to notification?.title.orEmpty(),
                "body" to notification?.body.orEmpty()
            )
        )
    }

    override fun onMessageSent(messageId: String?) {
        super.onMessageSent(messageId)
        HuaweiPushDiagnosticsStore.record(this, "onMessageSent", mapOf("message_id" to messageId.orEmpty()))
    }

    override fun onSendError(messageId: String?, exception: Exception?) {
        super.onSendError(messageId, exception)
        HuaweiPushDiagnosticsStore.record(
            this,
            "onSendError",
            mapOf("message_id" to messageId.orEmpty(), "error" to exception?.toString().orEmpty())
        )
    }

    override fun onDeletedMessages() {
        super.onDeletedMessages()
        HuaweiPushDiagnosticsStore.record(this, "onDeletedMessages")
    }
}
```

- [ ] **Step 4: Register app receiver and HMS service in manifest**

Replace the current receiver class:

```xml
android:name="com.aliyun.ams.push.AliyunPushMessageReceiver"
```

with:

```xml
android:name=".NontoAliyunPushMessageReceiver"
```

Add this service before `MessageKeepAliveService`:

```xml
<service
    android:name=".HuaweiPushDiagnosticsService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.huawei.push.action.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

- [ ] **Step 5: Include store snapshots in MethodChannel result**

In `MainActivity.collectHuaweiPushDiagnostics`, after the raw token collection but before `result.success`, merge:

```kotlin
diagnostics.putAll(HuaweiPushDiagnosticsStore.snapshot(this))
diagnostics.putAll(AliyunNativePushDiagnosticsStore.snapshot(this))
```

### Task 3: Expose callback diagnostics in Flutter diagnostics UI

**Files:**
- Modify: `D:/FlutterProject/nonto/lib/services/push_diagnostics_service.dart`
- Modify: `D:/FlutterProject/nonto/lib/screens/profile/push_diagnostics_screen.dart`

- [ ] **Step 1: Split native callback maps in collect()**

After collecting `huaweiPush`, populate two derived maps:

```dart
result['huaweiVendor'] = huaweiPush == null
    ? <String, dynamic>{'empty': true}
    : Map<String, dynamic>.fromEntries(
        huaweiPush.entries.where((entry) => entry.key.startsWith('huawei_vendor_')),
      );
result['aliyunNative'] = huaweiPush == null
    ? <String, dynamic>{'empty': true}
    : Map<String, dynamic>.fromEntries(
        huaweiPush.entries.where((entry) => entry.key.startsWith('aliyun_native_')),
      );
```

Initialize both maps in the `result` literal and in the non-Android skipped branch.

- [ ] **Step 2: Add formatted sections**

In `format`, add after `[华为原始推送]`:

```dart
final huaweiVendor = diagnostics['huaweiVendor'];
if (huaweiVendor is Map) {
  buffer
    ..writeln('[华为厂商推送]')
    ..writeln('last event: ${huaweiVendor['huawei_vendor_last_event'] ?? ''}')
    ..writeln('last event at: ${huaweiVendor['huawei_vendor_last_event_at'] ?? ''}')
    ..writeln('message id: ${huaweiVendor['huawei_vendor_message_id'] ?? ''}')
    ..writeln('message type: ${huaweiVendor['huawei_vendor_message_type'] ?? ''}')
    ..writeln('title: ${huaweiVendor['huawei_vendor_title'] ?? ''}')
    ..writeln('body: ${huaweiVendor['huawei_vendor_body'] ?? ''}')
    ..writeln('data: ${huaweiVendor['huawei_vendor_data'] ?? ''}')
    ..writeln('error: ${huaweiVendor['huawei_vendor_error'] ?? ''}')
    ..writeln();
}

final aliyunNative = diagnostics['aliyunNative'];
if (aliyunNative is Map) {
  buffer
    ..writeln('[阿里云原生回调]')
    ..writeln('last callback: ${aliyunNative['aliyun_native_last_callback'] ?? ''}')
    ..writeln('last callback at: ${aliyunNative['aliyun_native_last_callback_at'] ?? ''}')
    ..writeln('title: ${aliyunNative['aliyun_native_title'] ?? ''}')
    ..writeln('summary: ${aliyunNative['aliyun_native_summary'] ?? ''}')
    ..writeln('content: ${aliyunNative['aliyun_native_content'] ?? ''}')
    ..writeln('message id: ${aliyunNative['aliyun_native_message_id'] ?? ''}')
    ..writeln('extra: ${aliyunNative['aliyun_native_extra'] ?? ''}')
    ..writeln('open activity: ${aliyunNative['aliyun_native_open_activity'] ?? ''}')
    ..writeln('error: ${aliyunNative['aliyun_native_error'] ?? ''}')
    ..writeln();
}
```

- [ ] **Step 3: Add screen sections and rows**

In `PushDiagnosticsScreen.build`, add sections after `华为原始推送`:

```dart
const SizedBox(height: 12),
_buildSection('华为厂商推送', data['huaweiVendor']),
const SizedBox(height: 12),
_buildSection('阿里云原生回调', data['aliyunNative']),
```

In `_buildSection`, add rows:

```dart
_buildRow('Huawei vendor event', map['huawei_vendor_last_event']),
_buildRow('Huawei vendor event at', map['huawei_vendor_last_event_at']),
_buildRow('Huawei vendor message id', map['huawei_vendor_message_id']),
_buildRow('Huawei vendor message type', map['huawei_vendor_message_type']),
_buildRow('Huawei vendor title', map['huawei_vendor_title']),
_buildRow('Huawei vendor body', map['huawei_vendor_body']),
_buildRow('Huawei vendor data', map['huawei_vendor_data']),
_buildRow('Huawei vendor error', map['huawei_vendor_error']),
_buildRow('Aliyun native callback', map['aliyun_native_last_callback']),
_buildRow('Aliyun native callback at', map['aliyun_native_last_callback_at']),
_buildRow('Aliyun native title', map['aliyun_native_title']),
_buildRow('Aliyun native summary', map['aliyun_native_summary']),
_buildRow('Aliyun native content', map['aliyun_native_content']),
_buildRow('Aliyun native message id', map['aliyun_native_message_id']),
_buildRow('Aliyun native extra', map['aliyun_native_extra']),
_buildRow('Aliyun native open activity', map['aliyun_native_open_activity']),
_buildRow('Aliyun native error', map['aliyun_native_error']),
```

### Task 4: Verify and build v8.6 APK

**Files:**
- Output: `C:/Users/25318/Desktop/nonto测试v8.6.apk`

- [ ] **Step 1: Run targeted regression tests**

```bash
cd /d/FlutterProject/nonto
flutter test test/push_diagnostics_regression_test.dart test/android_push_contract_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Analyze modified Dart files**

```bash
cd /d/FlutterProject/nonto
flutter analyze lib/services/push_diagnostics_service.dart lib/screens/profile/push_diagnostics_screen.dart test/push_diagnostics_regression_test.dart test/android_push_contract_test.dart
```

Expected: no issues.

- [ ] **Step 3: Build arm64 release APK**

```bash
cd /d/FlutterProject/nonto
flutter --no-version-check build apk --release --target-platform android-arm64
```

Expected: Gradle compiles Kotlin and produces `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 4: Copy APK to desktop**

```bash
cp /d/FlutterProject/nonto/build/app/outputs/flutter-apk/app-release.apk /c/Users/25318/Desktop/nonto测试v8.6.apk
ls -lh /c/Users/25318/Desktop/nonto测试v8.6.apk
```

Expected: desktop APK exists, around 36 MB.

---

## Self-review

- Tests cover manifest wiring, new native classes, store names, Flutter formatted sections, and screen labels.
- Scope is diagnostic-only; no backend push integration is added.
- Sensitive tokens are only displayed in the existing diagnostics page; no token values are printed by this plan.
- Replacing the plugin receiver is intentional so callbacks can be persisted before forwarding to the Flutter plugin when the engine exists.
