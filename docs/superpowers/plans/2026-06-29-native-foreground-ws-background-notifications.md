# Native Foreground WebSocket Background Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Android background message notifications by allowing the Native foreground WebSocket to connect to `192.168.1.4`, stay alive with backend-recognized heartbeats, and process sync-recovered messages.

**Architecture:** Flutter owns the WebSocket while the app is foregrounded. On background, `AppLifecycleKeepAliveService` starts `MessageKeepAliveService` and disconnects Flutter WS; the native service must own an authenticated OkHttp WebSocket and show Android notifications for `new_message` / `new_notification` events. The fix keeps this handoff design and patches only the Android network policy and native service protocol handling.

**Tech Stack:** Flutter/Dart tests with `flutter_test`, Android Kotlin `Service`, OkHttp WebSocket, Android `NotificationManager`, project-local regression tests.

---

### Task 1: Permit local development backend IP for Native OkHttp WS

**Files:**
- Modify: `test/foreground_keepalive_regression_test.dart`
- Modify: `android/app/src/main/res/xml/network_security_config.xml`

- [ ] **Step 1: Write the failing test**

Add an assertion to the existing Android foreground-service regression tests that reads `android/app/src/main/res/xml/network_security_config.xml` and expects the local backend IP used by `AppConfig.wsUrl`:

```dart
test('Android network security allows local backend websocket host', () {
  final networkSecurity =
      read('android/app/src/main/res/xml/network_security_config.xml');

  expect(networkSecurity, contains('192.168.1.4'));
  expect(networkSecurity, contains('cleartextTrafficPermitted="true"'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/foreground_keepalive_regression_test.dart
```

Expected: FAIL because `192.168.1.4` is not present in `network_security_config.xml`.

- [ ] **Step 3: Write minimal implementation**

Add this domain inside the existing cleartext-permitted `domain-config`:

```xml
<domain includeSubdomains="true">192.168.1.4</domain>
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/foreground_keepalive_regression_test.dart
```

Expected: PASS.

### Task 2: Add backend-recognized business heartbeat in Native service

**Files:**
- Modify: `test/native_foreground_ws_regression_test.dart`
- Modify: `android/app/src/main/kotlin/com/nonto/nonto/MessageKeepAliveService.kt`

- [ ] **Step 1: Write the failing test**

Add expectations to `native service mirrors auth and sync protocol` or a new test that requires business heartbeat strings:

```dart
test('native service sends backend-recognized ping heartbeat', () {
  final source = read('android/app/src/main/kotlin/com/nonto/nonto/MessageKeepAliveService.kt');

  expect(source, contains('startBusinessHeartbeat'));
  expect(source, contains('stopBusinessHeartbeat'));
  expect(source, contains('sendBusinessPingFrame'));
  expect(source, contains('BUSINESS_HEARTBEAT_MS'));
  expect(source, contains('"type", "ping"'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/native_foreground_ws_regression_test.dart
```

Expected: FAIL because the native service only has OkHttp `pingInterval` and no JSON `type=ping` frame.

- [ ] **Step 3: Write minimal implementation**

In `MessageKeepAliveService.kt`:

- Add a `businessHeartbeatRunnable` that calls `sendBusinessPingFrame()` every `BUSINESS_HEARTBEAT_MS`.
- Call `startBusinessHeartbeat()` after `auth_result.success == true`.
- Call `stopBusinessHeartbeat()` on auth failure, socket close/failure, and service destroy.
- Implement `sendBusinessPingFrame()` as:

```kotlin
private fun sendBusinessPingFrame() {
    val socket = webSocket ?: return
    val frame = JSONObject()
        .put("type", "ping")
        .put("payload", JSONObject())
    socket.send(frame.toString())
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/native_foreground_ws_regression_test.dart
```

Expected: PASS.

### Task 3: Process sync_result payload envelopes in Native service

**Files:**
- Modify: `test/native_foreground_ws_regression_test.dart`
- Modify: `android/app/src/main/kotlin/com/nonto/nonto/MessageKeepAliveService.kt`

- [ ] **Step 1: Write the failing test**

Add expectations to the native sync protocol test that require reconstructing a standard message envelope from sync items:

```dart
test('native service converts sync payload items into message envelopes', () {
  final source = read('android/app/src/main/kotlin/com/nonto/nonto/MessageKeepAliveService.kt');

  expect(source, contains('handleSyncedMessage'));
  expect(source, contains('item.optJSONObject("payload")'));
  expect(source, contains('put("type", "message")'));
  expect(source, contains('put("payload", payload)'));
  expect(source, isNot(contains('item.optString("type") == "message"')));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/native_foreground_ws_regression_test.dart
```

Expected: FAIL because `handleSyncResult()` currently checks `item.optString("type") == "message"`, but backend sync rows contain `seq` and `payload`.

- [ ] **Step 3: Write minimal implementation**

Replace the sync item check with:

```kotlin
private fun handleSyncResult(payload: JSONObject?) {
    val list = payload?.optJSONArray("list") ?: return
    for (i in 0 until list.length()) {
        val item = list.optJSONObject(i) ?: continue
        handleSyncedMessage(item)
    }
}

private fun handleSyncedMessage(item: JSONObject) {
    val payload = item.optJSONObject("payload") ?: return
    val seq = item.optLong("seq", 0L)
    val envelope = JSONObject()
        .put("type", "message")
        .put("seq", seq)
        .put("payload", payload)
    handleMessage(envelope.toString())
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/native_foreground_ws_regression_test.dart
```

Expected: PASS.

### Task 4: Verify integrated behavior

**Files:**
- Test only: `test/foreground_keepalive_regression_test.dart`
- Test only: `test/native_foreground_ws_regression_test.dart`
- Optional runtime diagnostic: Android emulator app data `shared_prefs/nonto_native_ws.xml`

- [ ] **Step 1: Run focused regression tests**

Run:

```bash
flutter test test/foreground_keepalive_regression_test.dart test/native_foreground_ws_regression_test.dart
```

Expected: PASS.

- [ ] **Step 2: Build Android debug app**

Run:

```bash
flutter build apk --debug
```

Expected: Build succeeds.

- [ ] **Step 3: If an emulator is running, reinstall/launch and inspect diagnostics**

Use the Android emulator MCP build/run flow or existing Flutter workflow. After login and backgrounding, inspect native diagnostics:

```bash
adb shell run-as com.nonto.nonto cat shared_prefs/nonto_native_ws.xml
```

Expected after background handoff: `native_ws_running=true`, `native_ws_connected=true`, and `native_ws_authenticated=true` once backend is reachable.

---

## Self-Review

- Spec coverage: covers IP allowlist, Native WS heartbeat, sync recovery, and focused verification.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: Kotlin helper names in tests match implementation steps.
