## 0.4.0
- **New**: Opt-in batched event tracking via `batchingEnabled: true` in `OpenpanelOptions`. Configures `flushInterval` (default 60 s), `maxBatchSize` (default 50), and `maxRetries` (default 5). Events are persisted to a local SQLite database (drift) and flushed on a timer, when the queue reaches the size threshold, when the app backgrounds, or on an explicit `flush()` call. Events that fail delivery are retried up to `maxRetries` times before being dropped. Server-side validation rejections are dropped immediately without incrementing the retry counter. `clear()` (logout) leaves the queue intact — queued events deliver on the next flush under their original `profileId`, which is embedded in each payload at enqueue time.
- **Fix**: `openpanel-sdk-version` header now correctly reflects the actual SDK version (was `0.2.0`, now `0.4.0`).
- **Fix**: Transient batch failures (connect errors, timeouts, server 5xx) no longer count toward the retry budget — events stay queued for the next attempt. Only failures where the server actively processed or rejected the request (4xx) consume a retry slot.
- **New**: `OpenpanelOptions.maxEventAge` (default 5 days): expired events are purged locally before each drain. The openpanel server rejects events with `__timestamp` older than 5 days, so this prevents indefinite queue growth when the device is offline for extended periods.
- **New**: `BatchTransportError` now exposes `isTransient: bool` so consumers can differentiate retryable transport failures (offline / server 5xx) from non-retryable ones (4xx client errors).
- **Change**: Batched delivery uses the canonical `{"type": "batch", "payload": [...]}` envelope on `POST /track` instead of the deprecated `POST /track/batch` (`{"events": [...]}`) endpoint. The response contract (`202 {accepted, rejected}`) is unchanged.

## 0.3.0
- **Breaking**: Migrate to new OpenPanel tracking API
  - All API calls now use the unified `/track` endpoint
  - Event tracking uses `type: "track"`
  - User identification uses `type: "identify"`
  - Increment/decrement use `type: "increment"` and `type: "decrement"`
- Add desktop platform support (Windows, macOS, Linux)
  - Referrer tracking is gracefully disabled on non-mobile platforms
- See [API documentation](https://openpanel.dev/docs/api/track) for details

## 0.2.1
- Update documentation
- Upgrade dependencies

## 0.2.0
- Update package version
- Add sdk name to headers

## 0.0.6
- Add back referrer tracking

## 0.0.5
- Replace User Agent lib with another one that supports all platforms
- Remove lifecycle events tracking (for now)
- Update README

## 0.0.4
Add:
- Referrer url for Android & iOS
- User agent headers are now properly sent
- App lifecycle events are automatically handled now

## 0.0.3
- Remove mason_logger

## 0.0.2
- Update readme

## 0.0.1

Initial version:
- Client initialisation
- Events logging
