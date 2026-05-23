## 0.4.0
- **New**: Opt-in batched event tracking via `batchingEnabled: true` in `OpenpanelOptions`. Configures `flushInterval` (default 60 s), `maxBatchSize` (default 50), and `maxRetries` (default 5). Events are persisted to a local SQLite database (drift) and flushed on a timer, when the queue reaches the size threshold, when the app backgrounds, or on an explicit `flush()` call. Events that fail delivery are retried up to `maxRetries` times before being dropped. Server-side validation rejections are dropped immediately without incrementing the retry counter.
- **Fix**: `openpanel-sdk-version` header now correctly reflects the actual SDK version (was `0.2.0`, now `0.4.0`).

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
