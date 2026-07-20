# Remove Native Background WebSocket Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove nonto's app-owned Android foreground service and native background WebSocket, make Flutter WebSocket foreground-only, and make Aliyun/vendor push the sole background or killed-process notification display path with persistent receiver-side deduplication.

**Architecture:** The Flutter WebSocket remains the real-time in-app transport while the app is foregrounded and disconnects when the app leaves the foreground. The backend always attempts an eligible Aliyun delivery instead of trusting a potentially stale foreground lifecycle snapshot; each payload carries a canonical business `dedupe_key`. `NontoAliyunPushMessageReceiver` applies the Aliyun SDK foreground-display decision first, then atomically claims valid keys in a bounded seven-day `SharedPreferences` store so duplicate displays remain suppressed across process death.

**Tech Stack:** Flutter/Dart, Android Kotlin, Aliyun Mobile Push, SharedPreferences, FastAPI/Python, SQLAlchemy, pytest, Flutter test, JUnit.

**Safety constraints:** Preserve all unrelated uncommitted work in both repositories. Do not reset, clean, commit, push, publish, or expose credentials. Do not print values from `.env`, `android/local.properties`, `android/key.properties`, `agconnect-services.json`, or vendor configuration files. Generated manifests and APKs can contain expanded push configuration and must not be pasted into logs or committed.

---

## File Structure

### Backend

- Modify: `D:\NanTuPy\app\services\aliyun_push_service.py`
  - Derive and attach the canonical business `dedupe_key`.
  - Remove lifecycle-only foreground delivery suppression while preserving notification visibility and database delivery claims.
- Modify: `D:\NanTuPy\tests\test_push_dedupe_contracts.py`
  - Cover canonical keys, caller override prevention, foreground-state delivery, and existing database idempotency.
- Modify: `D:\NanTuPy\tests\test_app_state_push_contracts.py`
  - Replace the obsolete recent-foreground skip contract with the Aliyun receiver ownership contract.

### Android and Flutter

- Create: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\AliyunPushDedupeStore.kt`
  - Own canonical-key validation, atomic persistent claims, seven-day expiry, and bounded eviction.
- Create: `D:\FlutterProject\nonto\android\app\src\test\kotlin\com\nonto\nonto\AliyunPushDedupeStoreTest.kt`
  - Unit-test dedupe logic without requiring a device.
- Modify: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\NontoAliyunPushMessageReceiver.kt`
  - Run the SDK display decision first, extract the canonical key, and consult the persistent store.
- Modify: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\MainActivity.kt`
  - Remove foreground-service and native-WebSocket channels, handlers, and diagnostics while retaining Aliyun/vendor setup and the alert channel.
- Modify: `D:\FlutterProject\nonto\android\app\src\main\AndroidManifest.xml`
  - Remove app-owned foreground-service permissions and service declaration while retaining the custom Aliyun receiver and vendor components.
- Modify: `D:\FlutterProject\nonto\android\app\build.gradle.kts`
  - Remove app-owned OkHttp and add only the test dependency needed by the dedupe-store unit tests if not already present.
- Delete: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\MessageKeepAliveService.kt`
  - Remove the app-owned foreground service, native WebSocket, heartbeat, sync, ACK, and `nonto_keepalive` channel.
- Delete: `D:\FlutterProject\nonto\lib\services\foreground_service_manager.dart`
  - Remove the obsolete native-service MethodChannel facade.
- Modify: `D:\FlutterProject\nonto\lib\services\app_lifecycle_keepalive_service.dart`
  - Directly own Flutter WebSocket foreground/background transitions and backend lifecycle reporting; never start native work.
- Modify: `D:\FlutterProject\nonto\lib\services\websocket_service.dart`
  - Keep in-app streams but remove system-notification display from WebSocket events.
- Modify: `D:\FlutterProject\nonto\lib\providers\auth_notifier.dart`
  - Remove native-service start/stop/clear calls while preserving device registration and Flutter WebSocket cleanup.
- Modify: `D:\FlutterProject\nonto\lib\main.dart`
  - Remove obsolete local-notification initialization if no longer used for diagnostics.
- Modify: `D:\FlutterProject\nonto\lib\screens\profile\settings_screen.dart`
  - Remove the background WebSocket keepalive preference and misleading guide.
- Delete or rewrite: `D:\FlutterProject\nonto\lib\screens\profile\background_permission_guide_screen.dart`
  - Remove claims that battery exemptions enable an app-owned background socket.
- Modify: `D:\FlutterProject\nonto\lib\services\push_diagnostics_service.dart`
  - Remove native-WebSocket/foreground-service diagnostics and retain transport-neutral Aliyun/vendor/receiver diagnostics.
- Modify: `D:\FlutterProject\nonto\lib\screens\profile\push_diagnostics_screen.dart`
  - Remove native-service UI and explain the foreground Flutter/background Aliyun split.
- Delete or narrow: `D:\FlutterProject\nonto\lib\services\local_notification_service.dart`
  - It must not display normal business events from Flutter WebSocket. Retain only if an explicit user-triggered diagnostic notification still needs it.
- Modify if local notification support is deleted: `D:\FlutterProject\nonto\pubspec.yaml` and `D:\FlutterProject\nonto\pubspec.lock`
  - Remove `flutter_local_notifications` only after proving there are no remaining imports and another path retains Android notification permission handling.

### Regression contracts

- Create: `D:\FlutterProject\nonto\test\remove_native_background_ws_regression_test.dart`
  - Assert obsolete service wiring is absent and lifecycle ownership is correct.
- Create or revise: `D:\FlutterProject\nonto\test\push_dedupe_regression_test.dart`
  - Assert receiver/store source contracts and canonical key handling.
- Rewrite or delete obsolete positive contracts:
  - `D:\FlutterProject\nonto\test\native_foreground_ws_regression_test.dart`
  - `D:\FlutterProject\nonto\test\foreground_keepalive_regression_test.dart`
- Revise affected existing contracts:
  - `D:\FlutterProject\nonto\test\android_push_contract_test.dart`
  - `D:\FlutterProject\nonto\test\android_vendor_push_channel_regression_test.dart`
  - `D:\FlutterProject\nonto\test\push_diagnostics_regression_test.dart`
  - `D:\FlutterProject\nonto\test\permissions_and_unread_regression_test.dart`
  - `D:\FlutterProject\nonto\test\notification_ux_regression_test.dart`
  - `D:\FlutterProject\nonto\test\push_app_state_regression_test.dart`

---

### Task 1: Add the canonical backend dedupe key

**Files:**
- Modify: `D:\NanTuPy\tests\test_push_dedupe_contracts.py`
- Modify: `D:\NanTuPy\app\services\aliyun_push_service.py`

- [ ] **Step 1: Write failing message and non-message key tests**

Extend the `_build_push_params` behavior tests with payloads that assert:

```python
message_params = AliyunPushService._build_push_params(
    device_id="device-a",
    notification={
        "id": 10,
        "notification_type": "message",
        "message_id": 88,
        "related_id": 7,
        "title": "title",
        "content": "content",
        "android_ext_parameters": {"dedupe_key": "caller:override"},
    },
)
message_ext = json.loads(message_params["AndroidExtParameters"])
assert message_ext["dedupe_key"] == "message:88"

other_params = AliyunPushService._build_push_params(
    device_id="device-a",
    notification={
        "id": 10,
        "notification_type": "mention",
        "related_id": 7,
        "title": "title",
        "content": "content",
    },
)
other_ext = json.loads(other_params["AndroidExtParameters"])
assert other_ext["dedupe_key"] == "notification:10"
```

Also cover a message notification with a missing/blank `message_id`: it must fall back to `notification:<notification_id>` so every persisted notification still has a stable key.

- [ ] **Step 2: Run the focused tests and verify RED**

Run from `D:\NanTuPy`:

```bash
pytest tests/test_push_dedupe_contracts.py -k "dedupe_key or ext_parameters" -v
```

Expected: the new assertions fail because `AndroidExtParameters` does not contain `dedupe_key`.

- [ ] **Step 3: Implement one canonical key helper**

Add a pure helper to `AliyunPushService` and invoke it after merging caller extension parameters:

```python
@staticmethod
def _canonical_dedupe_key(notification: dict) -> str | None:
    notification_id = AliyunPushService._stable_notification_id(notification)
    if notification_id is None:
        return None

    message_id = notification.get("message_id")
    if (
        notification.get("notification_type") == "message"
        and message_id is not None
        and str(message_id).strip()
    ):
        return f"message:{str(message_id).strip()}"
    return f"notification:{notification_id}"
```

In `_build_push_params`, set server-owned extension fields last:

```python
canonical_key = cls._canonical_dedupe_key(notification)
ext.update({
    "notification_id": str(notification.get("id") or ""),
    "type": str(notification.get("notification_type") or ""),
    "related_id": str(notification.get("related_id") or ""),
    "message_id": str(notification.get("message_id") or ""),
})
if canonical_key is not None:
    ext["dedupe_key"] = canonical_key
```

Do not derive the key from title/body, provider `MessageId`, or mutable text.

- [ ] **Step 4: Run the focused tests and verify GREEN**

```bash
pytest tests/test_push_dedupe_contracts.py -k "dedupe_key or ext_parameters" -v
```

Expected: all selected tests pass.

- [ ] **Step 5: Checkpoint without committing**

Run `git diff --check -- app/services/aliyun_push_service.py tests/test_push_dedupe_contracts.py`. Do not commit because the user has not authorized commits.

---

### Task 2: Remove stale foreground-state suppression from backend delivery

**Files:**
- Modify: `D:\NanTuPy\tests\test_app_state_push_contracts.py`
- Modify: `D:\NanTuPy\tests\test_push_dedupe_contracts.py`
- Modify: `D:\NanTuPy\app\services\aliyun_push_service.py`

- [ ] **Step 1: Replace the obsolete skip test with an eligible-delivery test**

Write a behavior test that registers a device with recent `app_state="foreground"`, schedules one persisted notification, and asserts:

```python
assert send_request.call_count == 1
assert db.query(PushLog).one().status == "success"
```

Schedule the same notification again and assert `send_request.call_count` remains one because `(notification_id, device_id)` database idempotency—not lifecycle state—suppresses the duplicate.

- [ ] **Step 2: Run the new contract and verify RED**

```bash
pytest tests/test_app_state_push_contracts.py tests/test_push_dedupe_contracts.py -k "foreground" -v
```

Expected: the new test fails because recent foreground devices are skipped.

- [ ] **Step 3: Remove the lifecycle-only delivery gate**

Remove from `aliyun_push_service.py`:

- `FOREGROUND_PUSH_SKIP_SECONDS` if no longer used.
- `_should_skip_device_for_app_state` if no longer used.
- The `APP_FOREGROUND_RECENT` skip branch in `schedule_notification_push`.

Keep all of the following unchanged:

- stable notification-ID requirement;
- database-authoritative notification visibility;
- per-device enablement;
- user `notify_push` preference;
- delivery claim/finalization logic;
- success terminality and retryable failures;
- presence app-state storage and the separate 300-second presence TTL.

The Android receiver will suppress foreground display using the SDK's live decision. The backend must not permanently lose a notification because of a delayed lifecycle report.

- [ ] **Step 4: Run backend push and presence regressions**

```bash
pytest tests/test_push_dedupe_contracts.py tests/test_aliyun_push_contracts.py tests/test_app_state_push_contracts.py tests/test_presence_app_state_contracts.py tests/test_notification_service_unit.py -v
```

Expected: all tests pass. Presence tests must continue to enforce `BACKGROUND_ACTIVE_SECONDS == 300`.

- [ ] **Step 5: Checkpoint without committing**

Run `git diff --check` for only the touched backend files. Do not commit.

---

### Task 3: Build a persistent bounded Android dedupe store

**Files:**
- Create: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\AliyunPushDedupeStore.kt`
- Create: `D:\FlutterProject\nonto\android\app\src\test\kotlin\com\nonto\nonto\AliyunPushDedupeStoreTest.kt`
- Modify: `D:\FlutterProject\nonto\android\app\build.gradle.kts`

- [ ] **Step 1: Introduce a testable storage boundary and failing unit tests**

Define an internal key-value boundary so pure JVM tests do not require an Android device:

```kotlin
internal interface PushDedupeStorage {
    fun readClaims(): Map<String, Long>
    fun writeClaims(claims: Map<String, Long>)
}
```

Write JUnit tests for `AliyunPushDedupeStore.claim(key)` covering:

- first valid key returns `true`;
- duplicate valid key returns `false`;
- a new store instance over the same storage still rejects the duplicate;
- `message:<nonblank>` and `notification:<positive-id>` are accepted;
- blank, missing, unknown-prefix, whitespace-containing, and oversized keys fail open without persistence;
- a claim older than seven days is accepted again;
- future/corrupt timestamps are pruned safely;
- inserting above the fixed maximum evicts oldest entries;
- read or write exceptions return `true` (fail open);
- concurrent claims for the same key have exactly one successful winner.

Use an injected clock:

```kotlin
private var now = 1_700_000_000_000L
val store = AliyunPushDedupeStore(storage, nowMillis = { now })
```

- [ ] **Step 2: Run the Android unit test and verify RED**

From `D:\FlutterProject\nonto\android`:

```bash
./gradlew :app:testDebugUnitTest --tests "com.nonto.nonto.AliyunPushDedupeStoreTest"
```

Expected: compilation fails because the store does not exist.

- [ ] **Step 3: Implement minimal atomic claim behavior**

Implement `AliyunPushDedupeStore` with:

```kotlin
internal class AliyunPushDedupeStore(
    private val storage: PushDedupeStorage,
    private val nowMillis: () -> Long = System::currentTimeMillis,
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
) {
    @Synchronized
    fun claim(key: String): Boolean {
        if (!isCanonicalKey(key)) return true
        return try {
            val now = nowMillis()
            val claims = storage.readClaims()
                .filterValues { timestamp -> timestamp in (now - ttlMillis)..now }
                .toMutableMap()
            if (claims.containsKey(key)) return false
            claims[key] = now
            val bounded = claims.entries
                .sortedByDescending { it.value }
                .take(maxEntries)
                .associate { it.key to it.value }
            storage.writeClaims(bounded)
            true
        } catch (_: Exception) {
            true
        }
    }
}
```

Use constants equivalent to:

```kotlin
private const val DEFAULT_MAX_ENTRIES = 512
private const val DEFAULT_TTL_MILLIS = 7L * 24L * 60L * 60L * 1000L
```

Implement `SharedPreferencesPushDedupeStorage` using only application context. Persist only canonical keys and timestamps; never persist title, body, access tokens, signatures, or full payloads. Use a compact JSON object or one versioned string-set encoding and treat parse errors as fail-open.

- [ ] **Step 4: Run the unit test and verify GREEN**

```bash
./gradlew :app:testDebugUnitTest --tests "com.nonto.nonto.AliyunPushDedupeStoreTest"
```

Expected: all dedupe-store tests pass.

- [ ] **Step 5: Checkpoint without committing**

Run `git diff --check` for the new Kotlin files and Gradle file. Do not commit.

---

### Task 4: Apply dedupe at the Aliyun receiver display boundary

**Files:**
- Modify: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\NontoAliyunPushMessageReceiver.kt`
- Create or modify: `D:\FlutterProject\nonto\test\push_dedupe_regression_test.dart`

- [ ] **Step 1: Write source and behavior contracts for decision ordering**

The regression contract must assert that `showNotificationNow` follows this order:

```kotlin
val sdkWouldDisplay = super.showNotificationNow(context, map)
if (!sdkWouldDisplay) return false
val dedupeKey = extractDedupeKey(context, map) ?: return true
return dedupeStore(context).claim(dedupeKey)
```

Also assert that `onNotification`, `onNotificationReceivedInApp`, and `onMessage` do not call `NotificationManager.notify`; they remain callback/diagnostic paths only.

- [ ] **Step 2: Run the focused Flutter contract and verify RED**

```bash
flutter --no-version-check test test/push_dedupe_regression_test.dart
```

Expected: failure because the receiver currently delegates directly to `super.showNotificationNow`.

- [ ] **Step 3: Implement receiver extraction and fail-open behavior**

In `NontoAliyunPushMessageReceiver`:

1. Call `super.showNotificationNow(context, map)` before parsing or claiming.
2. If it returns `false`, return `false` and do not write a claim.
3. Extract `dedupe_key` from Aliyun extension parameters/`PushData.extraMap`; accept direct `map["dedupe_key"]` only as a compatibility fallback.
4. Validate with the store; no title/body fallback.
5. Claim through an application-context store.
6. Return `false` only for a confirmed duplicate.
7. On missing/malformed key or parse/store errors, return `true`.

Do not manually post a second notification. Do not claim keys in callback methods that do not make the SDK display decision.

- [ ] **Step 4: Run receiver and Kotlin regressions**

```bash
flutter --no-version-check test test/push_dedupe_regression_test.dart
```

```bash
./gradlew :app:testDebugUnitTest --tests "com.nonto.nonto.AliyunPushDedupeStoreTest"
```

Expected: both commands pass.

- [ ] **Step 5: Checkpoint without committing**

Run `git diff --check` for receiver, store, and tests. Do not commit.

---

### Task 5: Remove the native foreground service and Android WebSocket wiring

**Files:**
- Create: `D:\FlutterProject\nonto\test\remove_native_background_ws_regression_test.dart`
- Delete: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\MessageKeepAliveService.kt`
- Modify: `D:\FlutterProject\nonto\android\app\src\main\kotlin\com\nonto\nonto\MainActivity.kt`
- Modify: `D:\FlutterProject\nonto\android\app\src\main\AndroidManifest.xml`
- Modify: `D:\FlutterProject\nonto\android\app\build.gradle.kts`

- [ ] **Step 1: Write negative source contracts**

Assert:

```dart
expect(File(messageKeepAlivePath).existsSync(), isFalse);
expect(manifest, isNot(contains('MessageKeepAliveService')));
expect(manifest, isNot(contains('android.permission.FOREGROUND_SERVICE')));
expect(manifest, isNot(contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC')));
expect(mainActivity, isNot(contains('nonto/foreground_service')));
expect(mainActivity, isNot(contains('nonto/native_ws_diagnostics')));
expect(mainActivity, isNot(contains('startMessageKeepAlive')));
expect(mainActivity, isNot(contains('nonto_keepalive')));
expect(buildGradle, isNot(contains('com.squareup.okhttp3:okhttp')));
```

Positive assertions must retain:

```dart
expect(manifest, contains('.NontoAliyunPushMessageReceiver'));
expect(manifest, contains('POST_NOTIFICATIONS'));
expect(mainActivity, contains('nonto_message_alerts'));
expect(mainActivity, contains('nonto/aliyun_push_config'));
```

- [ ] **Step 2: Run the removal contract and verify RED**

```bash
flutter --no-version-check test test/remove_native_background_ws_regression_test.dart
```

Expected: failures identify the still-present service and wiring.

- [ ] **Step 3: Remove only the app-owned native path**

Perform these exact removals:

- delete `MessageKeepAliveService.kt`;
- remove `MessageKeepAliveService` from `AndroidManifest.xml`;
- remove app-owned foreground-service permissions;
- remove `nonto/foreground_service` and `nonto/native_ws_diagnostics` channels and handlers from `MainActivity.kt`;
- remove `startMessageKeepAliveService` and native-WebSocket diagnostics fields;
- remove app-owned OkHttp from `android/app/build.gradle.kts` if no remaining app code imports it;
- remove `nonto_keepalive` creation with the deleted service.

Retain Aliyun/vendor dependency-contributed services and receivers. Do not remove the app's custom Aliyun receiver, Huawei diagnostics service, vendor metadata, notification permission, or `nonto_message_alerts`.

- [ ] **Step 4: Run the removal contract and process the debug manifest**

```bash
flutter --no-version-check test test/remove_native_background_ws_regression_test.dart
```

```bash
./gradlew :app:processDebugMainManifest
```

Expected: tests and manifest processing pass.

- [ ] **Step 5: Checkpoint without committing**

Confirm the deleted file was the untracked app-owned native service described by the approved design, then run `git diff --check`. Do not commit.

---

### Task 6: Make Flutter lifecycle own the foreground-only WebSocket

**Files:**
- Delete: `D:\FlutterProject\nonto\lib\services\foreground_service_manager.dart`
- Modify: `D:\FlutterProject\nonto\lib\services\app_lifecycle_keepalive_service.dart`
- Modify: `D:\FlutterProject\nonto\lib\providers\auth_notifier.dart`
- Modify: `D:\FlutterProject\nonto\lib\services\websocket_service.dart`
- Modify: `D:\FlutterProject\nonto\test\push_app_state_regression_test.dart`
- Modify: `D:\FlutterProject\nonto\test\remove_native_background_ws_regression_test.dart`

- [ ] **Step 1: Write failing lifecycle contracts**

Assert that lifecycle handling does not import or call `ForegroundServiceManager`, and that:

```dart
case AppLifecycleState.resumed:
  WebSocketService().setAppForeground(true);
  // report foreground, then reconnect when authenticated

case AppLifecycleState.inactive:
case AppLifecycleState.paused:
case AppLifecycleState.hidden:
case AppLifecycleState.detached:
  WebSocketService().setAppForeground(false);
  // report background, then disconnect
```

Tests should validate behavior through injected callbacks where existing constructor patterns allow it, not only with brittle source strings.

Also assert `websocket_service.dart` no longer calls:

```dart
LocalNotificationService().showMessageNotification(...)
LocalNotificationService().showInteractionNotification(...)
```

- [ ] **Step 2: Run lifecycle tests and verify RED**

```bash
flutter --no-version-check test test/push_app_state_regression_test.dart test/remove_native_background_ws_regression_test.dart
```

Expected: failures show native-service calls and WebSocket-driven system notification calls.

- [ ] **Step 3: Implement the foreground-only lifecycle**

- Delete `foreground_service_manager.dart`.
- In the lifecycle observer, directly call `WebSocketService().setAppForeground`.
- On `resumed`, report backend state `foreground` and reconnect/force-reconnect only when authenticated.
- On every non-resumed state, report backend state `background` and explicitly disconnect Flutter WebSocket.
- Keep task coalescing/generation guards so delayed foreground reports cannot overwrite a later background state or vice versa.
- Remove native service start/stop/clear calls from token restoration, login, logout, and session clearing.
- Preserve Aliyun backend device registration/unregistration and Flutter WebSocket cleanup.
- Remove local system-notification calls from WebSocket event handlers; preserve streams, unread updates, in-app sounds/haptics, sequence ACK, and sync behavior.

- [ ] **Step 4: Run lifecycle, presence, chat, and unread regressions**

```bash
flutter --no-version-check test test/push_app_state_regression_test.dart test/remove_native_background_ws_regression_test.dart test/presence_background_regression_test.dart test/messages_notification_unread_regression_test.dart
```

Expected: all selected tests pass.

- [ ] **Step 5: Checkpoint without committing**

Run `dart format` on touched Dart files, then `git diff --check`. Do not commit.

---

### Task 7: Remove obsolete settings and migrate diagnostics

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\profile\settings_screen.dart`
- Delete or rewrite: `D:\FlutterProject\nonto\lib\screens\profile\background_permission_guide_screen.dart`
- Modify: `D:\FlutterProject\nonto\lib\services\push_diagnostics_service.dart`
- Modify: `D:\FlutterProject\nonto\lib\screens\profile\push_diagnostics_screen.dart`
- Modify: `D:\FlutterProject\nonto\lib\main.dart`
- Delete or narrow: `D:\FlutterProject\nonto\lib\services\local_notification_service.dart`
- Modify if unused: `D:\FlutterProject\nonto\pubspec.yaml`
- Regenerate if dependency removed: `D:\FlutterProject\nonto\pubspec.lock`
- Modify: `D:\FlutterProject\nonto\test\push_diagnostics_regression_test.dart`
- Modify: `D:\FlutterProject\nonto\test\permissions_and_unread_regression_test.dart`

- [ ] **Step 1: Rewrite tests around the new architecture**

Remove positive expectations for:

- `foreground_keepalive_enabled`;
- “后台消息保活”;
- native WebSocket/service state;
- `nonto/native_ws_diagnostics`;
- automatic background-service startup.

Retain expectations for:

- Aliyun initialization and backend device binding;
- vendor push configuration diagnostics;
- notification permission and `nonto_message_alerts` channel health;
- last native receiver callback;
- Flutter WebSocket foreground connection state;
- receiver dedupe store health/last decision without exposing payload content.

- [ ] **Step 2: Run diagnostics/settings tests and verify RED**

```bash
flutter --no-version-check test test/push_diagnostics_regression_test.dart test/permissions_and_unread_regression_test.dart
```

Expected: failures identify obsolete keepalive UI and diagnostics.

- [ ] **Step 3: Remove misleading UI and preserve useful diagnostics**

- Remove the keepalive preference, toggle, and WebSocket battery-exemption wording.
- Delete the guide if it exists only for the native socket; otherwise rewrite it strictly as vendor notification permission/startup guidance without claiming a background socket is kept alive.
- Remove native-WebSocket and foreground-service diagnostics fields/channels.
- Retain generic package/version/signature hash, notification permission, alert channel, Aliyun registration, vendor callback, and Flutter foreground-WebSocket diagnostics.
- Add safe dedupe diagnostics only if the existing diagnostics store can expose them without recording title/body or complete payloads.
- Remove `LocalNotificationService` from startup and dependencies only if no explicit diagnostic test-notification action remains and notification permission is still requested through the Aliyun/native integration. Otherwise retain a narrowly named diagnostic-only service with no production WebSocket callers.
- Correct stale comments that claim Flutter/WebSocket supplies background system notifications.

- [ ] **Step 4: Resolve dependencies and run tests**

If `pubspec.yaml` changed:

```bash
flutter --no-version-check pub get
```

Then:

```bash
flutter --no-version-check test test/push_diagnostics_regression_test.dart test/permissions_and_unread_regression_test.dart test/remove_native_background_ws_regression_test.dart
```

Expected: all selected tests pass.

- [ ] **Step 5: Checkpoint without committing**

Run `dart format` on touched Dart files and `git diff --check`. Do not commit.

---

### Task 8: Rewrite all obsolete Android push contracts

**Files:**
- Delete or rewrite: `D:\FlutterProject\nonto\test\native_foreground_ws_regression_test.dart`
- Delete or rewrite: `D:\FlutterProject\nonto\test\foreground_keepalive_regression_test.dart`
- Modify: `D:\FlutterProject\nonto\test\android_push_contract_test.dart`
- Modify: `D:\FlutterProject\nonto\test\android_vendor_push_channel_regression_test.dart`
- Modify: `D:\FlutterProject\nonto\test\notification_ux_regression_test.dart`

- [ ] **Step 1: Remove tests that positively require deleted production code**

Replace them with negative architecture assertions or delete them when their entire subject no longer exists. No test may require:

- `MessageKeepAliveService`;
- `ForegroundServiceManager`;
- `nonto_keepalive`;
- app-owned native WebSocket auth/heartbeat/sync/ACK;
- Flutter WebSocket system-notification display.

- [ ] **Step 2: Preserve positive vendor and UX contracts**

Ensure revised tests still require:

- `.NontoAliyunPushMessageReceiver` rather than the plugin base receiver;
- Aliyun/Huawei/OPPO/vivo configuration placeholders without asserting secret values;
- `nonto_message_alerts`;
- notification routing/open behavior;
- foreground in-app events;
- persistent canonical-key dedupe;
- absence of duplicate manual notification posting.

- [ ] **Step 3: Run the revised contract group**

```bash
flutter --no-version-check test \
  test/remove_native_background_ws_regression_test.dart \
  test/push_dedupe_regression_test.dart \
  test/android_push_contract_test.dart \
  test/android_vendor_push_channel_regression_test.dart \
  test/push_diagnostics_regression_test.dart \
  test/notification_ux_regression_test.dart \
  test/permissions_and_unread_regression_test.dart \
  test/push_app_state_regression_test.dart
```

Expected: all tests pass.

- [ ] **Step 4: Run a static obsolete-wiring scan**

Search active production code for:

```text
MessageKeepAliveService
ForegroundServiceManager
nonto/foreground_service
nonto/native_ws_diagnostics
startMessageKeepAlive
stopMessageKeepAlive
nonto_keepalive
native_ws_
showMessageNotification
showInteractionNotification
```

Expected: no obsolete references in active production code. Negative assertions in tests are allowed.

- [ ] **Step 5: Checkpoint without committing**

Run `git diff --check`. Do not commit.

---

### Task 9: Verify backend, Flutter, Android manifests, and builds

**Files:**
- Verification only; fix only failures caused by Tasks 1–8.

- [ ] **Step 1: Run focused backend regressions**

From `D:\NanTuPy`:

```bash
pytest tests/test_push_dedupe_contracts.py tests/test_aliyun_push_contracts.py tests/test_app_state_push_contracts.py tests/test_presence_app_state_contracts.py tests/test_notification_service_unit.py tests/test_notification_unread_count_contracts.py -v
```

Expected: all tests pass.

- [ ] **Step 2: Run backend syntax and migration-head checks**

Compile only touched/importable modules to avoid known unrelated NULL-byte files:

```bash
python -m py_compile app/services/aliyun_push_service.py app/services/presence_service.py app/services/notification_service.py
alembic heads
```

Expected: compilation succeeds and Alembic reports one head (`2026_07_18_0100`).

- [ ] **Step 3: Run Flutter analysis and complete tests**

From `D:\FlutterProject\nonto`:

```bash
flutter --no-version-check analyze
flutter --no-version-check test
```

Expected: both succeed. If an unrelated pre-existing test fails, record its exact name and evidence; do not hide or rewrite it unless it conflicts with this approved architecture.

- [ ] **Step 4: Run Kotlin unit tests and Android builds**

```bash
cd android && ./gradlew :app:testDebugUnitTest && cd ..
flutter --no-version-check build apk --debug
flutter --no-version-check build apk --release --target-platform android-arm64
```

Expected: unit tests and both APK builds succeed.

- [ ] **Step 5: Inspect generated merged manifests without printing secrets**

Inspect debug and release merged manifests locally and assert absence of:

- `MessageKeepAliveService`;
- app-owned `android.permission.FOREGROUND_SERVICE`;
- app-owned `android.permission.FOREGROUND_SERVICE_DATA_SYNC`;
- `nonto_keepalive`.

Assert presence of:

- `NontoAliyunPushMessageReceiver`;
- Aliyun receiver actions;
- Huawei/OPPO/vivo dependency components and metadata;
- `POST_NOTIFICATIONS`;
- `nonto_message_alerts`.

Do not paste expanded metadata or credential values into output.

- [ ] **Step 6: Record device-only acceptance checks as pending if hardware is unavailable**

On a physical Android device, verify:

1. Foreground: Flutter WebSocket receives in-app updates and no system notification appears.
2. Background: Flutter WebSocket disconnects and Aliyun/vendor push displays one notification.
3. Killed process: no foreground-service notification/native socket exists; vendor push still displays.
4. Duplicate canonical key: second delivery is suppressed after process restart.
5. Missing key or dedupe-store failure: notification fails open and displays.
6. Resume: Flutter WebSocket reconnects and notification-center state remains consistent.

If a suitable physical device/vendor delivery cannot be exercised, state that explicitly; do not claim these checks passed based only on source tests.

- [ ] **Step 7: Final diff and scope review**

Run `git diff --check` in both repositories. Review status without displaying sensitive file contents. Confirm no unrelated changes were reset or overwritten and no credentials/build outputs were added intentionally. Do not commit or push.

---

## Plan Self-Review

- **Spec coverage:** Foreground Flutter WebSocket, background/killed Aliyun ownership, service removal, lifecycle/presence constraints, canonical backend key, receiver decision ordering, persistent seven-day bounded dedupe, fail-open handling, database delivery idempotency, diagnostics migration, tests, manifests, and builds each map to a task above.
- **No unsafe fallback:** The plan never derives dedupe identity from title/body and never treats a missing key as a duplicate.
- **Decision ordering:** The SDK foreground decision occurs before key claim, so a foreground suppression does not reserve the key.
- **Type consistency:** The backend emits `message:<message_id>` for message notifications and `notification:<notification_id>` otherwise; the Android store validates the same two forms.
- **Presence isolation:** The backend's 300-second product-presence TTL remains intact even though mobile delivery no longer trusts foreground lifecycle state.
- **Scope discipline:** Aliyun/vendor dependency services remain; only the app-owned foreground service/native WebSocket path is removed.
- **Repository safety:** All checkpoints explicitly avoid commit/reset/clean and protect uncommitted work and secrets.
