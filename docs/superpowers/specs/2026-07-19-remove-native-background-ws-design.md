# Remove Native Background WebSocket Design

## Goal

Remove the Android native foreground-service WebSocket notification path and use Flutter WebSocket only while the app is foreground, with Alibaba Cloud vendor push as the sole background/killed-process notification transport.

## Architecture

### Foreground

- Flutter WebSocket remains connected and provides real-time in-app updates.
- Android system notifications are not shown while the application is foreground.
- The Aliyun receiver preserves the SDK foreground decision and does not reserve a dedupe key when the SDK would not display.

### Background and killed process

- Flutter WebSocket disconnects when the app enters background.
- No Android foreground service or native WebSocket is started.
- The backend creates notification-center records and submits eligible mobile notifications through Aliyun.
- Huawei, OPPO, vivo, and other configured vendor channels handle killed-process delivery.

## Removal Scope

Remove or disconnect:

- `MessageKeepAliveService.kt`
- `ForegroundServiceManager`
- Native WebSocket authentication, heartbeat, sync, ACK, and notification display code
- The persistent `nonto_keepalive` notification/channel
- Foreground-service manifest declarations and permissions no longer needed by other features
- MainActivity MethodChannel handlers used only by native background WebSocket
- App lifecycle start/stop calls for the foreground service
- Native-background-WS configuration keys and obsolete tests

Do not remove:

- Aliyun receiver and vendor push configuration
- Flutter foreground WebSocket
- Flutter in-app notification streams
- Backend notification records and push-device lifecycle state

## Push Display and Deduplication

- Backend database idempotency remains authoritative for `(notification_id, device_id)` delivery claims.
- Backend adds a canonical `dedupe_key` to Aliyun extension parameters:
  - `message:<message_id>` for message notifications
  - `notification:<notification_id>` for other notification types
- The custom Aliyun receiver performs persistent local dedupe after `super.showNotificationNow(...)` says the SDK would display.
- Receiver dedupe records survive process death, use a seven-day TTL, and are bounded in size.
- Confirmed duplicates return `false`; missing keys or store errors fail open and allow display.
- Stable Android notification IDs are derived from canonical keys when the SDK payload supports custom notification IDs.

## Lifecycle and Presence

- `foreground`: Flutter WebSocket connected; no system notification.
- `background`: Flutter WebSocket disconnected; Aliyun push owns notification delivery.
- `killed`: no immediate callback is guaranteed; presence expires after the existing five-minute product-presence TTL.
- The product does not promise immediate offline display after force-kill or process death.

## Backend Delivery Policy

- Notification-center records are always created.
- Backend delivery claims remain idempotent.
- Backend should not permanently suppress Aliyun delivery solely because a possibly stale lifecycle record says foreground.
- Actual display eligibility is finalized by the Android SDK/receiver foreground decision.

## Error Handling

- Aliyun receiver dedupe-store errors fail open to avoid losing notifications.
- Backend visibility errors fail closed to avoid leaking blocked notifications.
- Provider failures remain retryable until a valid 2xx Aliyun acknowledgement is recorded.

## Verification

- Source and behavior tests prove native foreground-service code and manifest wiring are removed.
- Flutter lifecycle tests prove no native keepalive service starts in background.
- Backend tests prove canonical `dedupe_key` generation and delivery idempotency.
- Receiver tests/contracts prove SDK foreground decision occurs before persistent claim and duplicates are suppressed.
- Android debug/release build verifies manifest and Kotlin compilation.
