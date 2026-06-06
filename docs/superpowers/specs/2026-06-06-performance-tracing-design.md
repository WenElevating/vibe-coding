# Performance Trace Recording Design

- Status: approved design
- Date: 2026-06-06
- Scope: daemon and mobile performance trace recording only

## Context

The app is a LAN-first mobile control surface for CLI coding tools. The daemon
owns HTTP APIs, adapter execution, persisted conversation events, and WebSocket
notifications. The mobile app owns the client UI, repositories, ViewModels, and
rendered transcript state.

The product needs truthful performance data for:

- app loading and conversation opening latency;
- CLI/app-server event latency from daemon receipt to mobile rendering;
- mobile send latency from tap to daemon acknowledgement, first output, and
  completion.

This design records timing marks only. Later backend analysis, reporting, and
dashboard work are intentionally out of scope for this spec.

## Goals

- Record enough trace marks to reconstruct real latency across daemon and
  mobile boundaries.
- Keep trace collection off the user-visible critical path.
- Preserve current app behavior, event ordering, and conversation persistence.
- Avoid mobile UI changes. Perf tracing is enabled or disabled only by backend
  configuration.
- Avoid collecting prompt or output content.

## Non-Goals

- No in-app performance dashboard.
- No mobile settings switch.
- No local mobile persistent trace queue.
- No report script or backend analysis job in this phase.
- No product alerting or SLA enforcement.
- No changes to `conversation_events` semantics.
- No background analysis service in this phase.

## Hard Constraints

- Trace collection points must never send HTTP requests.
- Trace collection points must never perform filesystem or SQLite writes.
- Trace collection points must not `await`.
- Mobile trace marks must flow through the existing `MobileAppEventBus`.
- Mobile uploads must be performed only by a background reporter that subscribes
  to the performance trace event type.
- Mobile queue is memory-only. Marks not uploaded before app termination may be
  lost.
- Backend controls whether tracing is enabled. Mobile only follows backend
  config.

## Chosen Approach

Use a passive trace-recording layer.

Daemon adds a no-op-by-default tracer and optional perf SQLite store. Mobile
adds a lightweight publisher that emits a `MobilePerformanceTraceMark` event to
the existing `MobileAppEventBus`. A background `PerformanceTraceReporter`
subscribes to that event type, stores marks in an in-memory FIFO queue, and
uploads batches to the daemon in order.

When tracing is disabled, the daemon and mobile use no-op behavior. No mobile UI
surface is added.

## Backend Control

Tracing is controlled by daemon configuration only.

Initial control surface:

```powershell
$env:VIBE_PERF_TRACE='1'
npm run start:daemon
```

When not set, tracing is disabled. Runtime toggling is not part of this phase.
If runtime toggling is needed later, it should be added as a backend-only
administrative route without adding mobile UI.

## Daemon Components

### PerfTracer

New module:

```text
daemon/src/perf-tracer.js
```

Responsibilities:

- expose `mark(input)` and `isEnabled()`;
- return immediately when disabled;
- assign daemon-side monotonic and wall-clock timestamps;
- enqueue marks to the daemon perf writer when enabled;
- never throw into business code.

### PerfSqliteStore

New module:

```text
daemon/src/perf-sqlite-store.js
```

Responsibilities:

- lazily create `data/app/perf.sqlite` only when tracing is enabled;
- batch-write daemon and mobile marks;
- tolerate write failures by reporting a diagnostic warning only;
- avoid touching `data/app/app.sqlite`.

### Perf HTTP Routes

New routes under:

```text
/api/perf/config
/api/perf/time-sync
/api/perf/mobile-marks
```

`GET /api/perf/config` returns whether mobile should start tracing:

```json
{
  "enabled": true,
  "runId": "perf_20260606T120001Z_a8f3c2",
  "sampleRate": 1,
  "maxQueueSize": 2000,
  "maxBatchSize": 200
}
```

When disabled:

```json
{
  "enabled": false
}
```

`runId` is daemon-generated and must be unique without human coordination. Use a
UUID or timestamp plus random suffix. Human-readable labels belong in the
`scenario` column, not in the run id.

`sampleRate` is reserved for later sampling policy. In this recording-only
phase the daemon returns `1`, and mobile publishers/reporters must not implement
sampling logic.

`POST /api/perf/time-sync` supports clock offset estimation between mobile and
daemon. Request:

```json
{
  "runId": "perf_20260606T120001Z_a8f3c2",
  "appSessionId": "mobile_session_xxx",
  "mobileSendWallMs": 1791200005000,
  "mobileSendMonoUs": 128000000
}
```

Response:

```json
{
  "daemonReceiveWallMs": 1791200005060,
  "daemonSendWallMs": 1791200005062
}
```

`POST /api/perf/mobile-marks` accepts batches from the mobile background
reporter. It must require normal paired-device authentication.

## Daemon Trace Marks

Daemon should record these marks when tracing is enabled:

- `http.conversation.request.received`
- `http.conversation.response.sent`
- `conversation.send.received`
- `conversation.user.persisted`
- `adapter.send.started`
- `adapter.send.accepted`
- `adapter.raw_event.received`
- `adapter.event.normalized`
- `event.persisted`
- `ws.event.enqueued`
- `ws.event.sent`

Suggested code boundaries:

- `daemon/src/server.js` for HTTP request boundaries;
- `daemon/src/conversation-manager.js` for send and adapter event flow;
- `daemon/src/conversation-event-store.js` for append/persist marks;
- `daemon/src/notification-hub.js` for WebSocket enqueue/send marks;
- adapter-specific modules for raw event receipt.

## Mobile Components

### MobilePerformanceTraceMark

Add a new event type to the existing bus model:

```text
mobile/lib/src/services/mobile_app_event_bus.dart
```

Shape:

```dart
class MobilePerformanceTraceMark extends MobileAppEvent {
  const MobilePerformanceTraceMark({
    required this.name,
    required this.monotonicUs,
    required this.wallTimeMs,
    this.conversationId,
    this.seq,
    this.eventType,
    this.correlationId,
    this.critical = false,
    this.clockDriftWarning = false,
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final int monotonicUs;
  final int wallTimeMs;
  final String? conversationId;
  final int? seq;
  final String? eventType;
  final String? correlationId;
  final bool critical;
  final bool clockDriftWarning;
  final Map<String, Object?> metadata;
}
```

This event type is the performance trace topic. No new event bus abstraction is
needed. `critical` is for chain-preserving marks that should be preferentially
retained under queue pressure. `clockDriftWarning` is normally false at
collection sites; the reporter may also set a batch-level warning when the most
recent time-sync sample indicates unreliable cross-clock comparison.

### PerformanceTracePublisher

New mobile service:

```text
mobile/lib/src/services/performance_trace_publisher.dart
```

Responsibilities:

- keep an enabled flag from daemon config;
- return immediately when disabled;
- create a small `MobilePerformanceTraceMark`;
- publish it to `MobileAppEventBus`;
- never enqueue batches, send HTTP, encode JSON, or write local storage.

Collection sites call the publisher only:

```dart
tracePublisher.mark(
  'ws.event.received',
  conversationId: event.conversationId,
  seq: event.seq,
  eventType: event.type,
);
```

### PerformanceTraceReporter

New mobile service:

```text
mobile/lib/src/services/performance_trace_reporter.dart
```

Responsibilities:

- subscribe to `eventBus.on<MobilePerformanceTraceMark>()`;
- enqueue marks into an in-memory FIFO queue;
- flush batches in the background;
- enforce one in-flight upload at a time;
- preserve upload order;
- drop marks rather than block UI or business code.

### PerformanceTraceClient

New mobile service:

```text
mobile/lib/src/services/performance_trace_client.dart
```

Responsibilities:

- call `/api/perf/config`;
- call `/api/perf/time-sync`;
- upload batches to `/api/perf/mobile-marks`;
- keep perf errors out of user-visible operation errors.
- reuse the existing authenticated daemon HTTP path, or a shared equivalent
  helper, with the same paired-device token and token-refresh behavior as normal
  daemon APIs.

Authentication failures follow the reporter failure policy. They must not show
UI errors, toast notifications, or conversation-level failures.

## Mobile Queue Policy

- Queue type: memory-only FIFO.
- Default capacity: 2000 marks.
- Batch size: 200 marks or configured backend limit.
- Flush interval: 2 seconds while tracing is enabled.
- App lifecycle pause: attempt one best-effort flush with a hard 1500 ms
  timeout. Timeout abandons that lifecycle flush, does not count as an upload
  failure, and does not schedule an immediate retry.
- Queue full: preserve critical marks preferentially.
- Failed upload: retry the same batch once on the next flush interval, not
  immediately in the same interval.
- Second failure: drop that batch and increment dropped counters.
- Consecutive failures: after 3 consecutive failed upload cycles, pause uploads
  until the next successful config check or explicit reporter restart. Collection
  remains bounded by queue limits while paused.
- Concurrency: only one in-flight upload at a time.

Queue pressure policy:

- non-critical incoming mark and queue full: drop the incoming mark;
- critical incoming mark and queue contains non-critical marks: drop the oldest
  non-critical queued mark, then enqueue the critical mark in arrival order;
- critical incoming mark and queue is all critical: drop the incoming critical
  mark.

Critical marks should be declared by the publisher call site instead of inferred
solely from names. The first implementation should mark these as critical:
`send.tap`, `send.http.completed`, `history.first_page.applied`,
`history.backfill.completed`, `ws.event.received`, `reducer.applied`, and
`event.frame.rendered`. Names containing `rendered` or `completed` are good
review signals, but they are not the only retention rule.

Dropping is visible through dropped counters, split by critical and non-critical
loss where practical.

## Mobile Trace Marks

Mobile should record these marks when tracing is enabled:

- `app.main.started`
- `app.first_frame`
- `daemon.health.loaded`
- `workspace.list.loaded`
- `conversation.page.opened`
- `history.first_page.started`
- `history.first_page.applied`
- `history.backfill.completed`
- `send.tap`
- `send.http.started`
- `send.http.completed`
- `send.optimistic.rendered`
- `ws.connected`
- `ws.frame.received`
- `ws.event.received`
- `reducer.applied`
- `event.frame.rendered`

Suggested code boundaries:

- `mobile/lib/src/main.dart` for app startup and first frame;
- `mobile/lib/src/services/conversation_client.dart` for conversation HTTP;
- `mobile/lib/src/services/daemon_notification_client.dart` for WebSocket
  receipt;
- `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
  for history/reducer application;
- `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` for send
  taps and post-frame render marks.

## API Contract

`POST /api/perf/mobile-marks` request:

```json
{
  "runId": "perf_20260606T120001Z_a8f3c2",
  "deviceId": "device_xxx",
  "appSessionId": "mobile_session_xxx",
  "mobileSentWallMs": 1791200005000,
  "mobileSentMonoUs": 128000000,
  "droppedCountSinceLastSuccessfulFlush": 0,
  "droppedCriticalCountSinceLastSuccessfulFlush": 0,
  "droppedNonCriticalCountSinceLastSuccessfulFlush": 0,
  "marks": [
    {
      "name": "ws.event.received",
      "source": "mobile",
      "wallTimeMs": 1791200002500,
      "monotonicUs": 125500000,
      "conversationId": "conv_xxx",
      "seq": 5485,
      "eventType": "assistant.message",
      "correlationId": "conv_xxx:5485",
      "critical": true,
      "clockDriftWarning": false,
      "metadata": {
        "bytes": 1200
      }
    }
  ],
  "clockSync": {
    "offsetEstimateMs": -12.4,
    "roundTripMs": 18.7,
    "ageMs": 1530,
    "quality": "good",
    "clockDriftWarning": false
  }
}
```

Response:

```json
{
  "accepted": 1,
  "dropped": 0,
  "daemonReceiveWallMs": 1791200005060,
  "daemonSendWallMs": 1791200005062
}
```

The response timestamps allow the reporter to refine clock offset estimates
without a separate time-sync request for every flush.

`droppedCountSinceLastSuccessfulFlush` and the critical/non-critical split are
reset only after a successful upload. If an upload fails and the batch remains
eligible for retry, counters continue accumulating. If a retry also fails and
the batch is discarded, the discarded mark count is folded into the next
successful upload's dropped counters rather than silently reset.

## Clock Alignment

Mobile and daemon clocks are not assumed to be perfectly aligned. The reporter
uses an NTP-style offset estimate from `/api/perf/time-sync` and from successful
flush responses:

- `t0`: mobile send wall-clock timestamp;
- `t1`: daemon receive wall-clock timestamp;
- `t2`: daemon send wall-clock timestamp;
- `t3`: mobile receive wall-clock timestamp.

Derived values:

```text
roundTripMs = (t3 - t0) - (t2 - t1)
offsetEstimateMs = ((t1 - t0) + (t2 - t3)) / 2
```

The latest estimate is attached to reporter flushes as `clockSync`. Backend
analysis should treat cross-device wall-clock latency as low confidence when:

- `clockSync.ageMs` is too old;
- `roundTripMs` exceeds the configured quality threshold;
- mobile wall-clock delta and monotonic delta diverge unexpectedly;
- the app crossed background, lock-screen, or lifecycle pause/resume while marks
  were queued.

The reporter sets `clockSync.clockDriftWarning` for suspicious batches. Marks
may also carry `clockDriftWarning` when a specific capture window is known to be
affected. Analysis must keep these rows but exclude or flag them for
cross-device latency calculations.

## Correlation

Correlation keys should be stable and content-free:

- send path: existing or extended `traceId` / `clientMessageId`;
- conversation event path: `conversationId:seq`;
- tool path: `toolUseId`;
- app-server path: optional `threadId:turnId:itemId` metadata.

The first implementation should prioritize `traceId`, `conversationId`, `seq`,
and `toolUseId`.

## Data Storage

Use a separate daemon database:

```text
data/app/perf.sqlite
```

Schema:

```sql
CREATE TABLE IF NOT EXISTS perf_runs (
  id TEXT PRIMARY KEY,
  scenario TEXT,
  adapter TEXT,
  device_id TEXT,
  conversation_id TEXT,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS perf_mobile_batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT,
  device_id TEXT,
  app_session_id TEXT,
  mobile_sent_wall_ms INTEGER,
  mobile_sent_mono_us INTEGER,
  daemon_receive_wall_ms INTEGER,
  daemon_send_wall_ms INTEGER,
  clock_offset_estimate_ms REAL,
  clock_round_trip_ms REAL,
  clock_sync_age_ms INTEGER,
  clock_sync_quality TEXT,
  clock_drift_warning INTEGER NOT NULL DEFAULT 0,
  dropped_count_since_last_successful_flush INTEGER NOT NULL DEFAULT 0,
  dropped_critical_count_since_last_successful_flush INTEGER NOT NULL DEFAULT 0,
  dropped_non_critical_count_since_last_successful_flush INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS perf_marks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT,
  mobile_batch_id INTEGER,
  source TEXT NOT NULL,
  name TEXT NOT NULL,
  wall_time_ms INTEGER,
  monotonic_us INTEGER,
  critical INTEGER NOT NULL DEFAULT 0,
  clock_drift_warning INTEGER NOT NULL DEFAULT 0,
  daemon_receive_wall_ms INTEGER,
  conversation_id TEXT,
  seq INTEGER,
  event_type TEXT,
  correlation_id TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_perf_marks_run_name
  ON perf_marks(run_id, name);

CREATE INDEX IF NOT EXISTS idx_perf_marks_correlation
  ON perf_marks(correlation_id, source, name);

CREATE INDEX IF NOT EXISTS idx_perf_mobile_batches_run
  ON perf_mobile_batches(run_id, app_session_id, created_at);
```

Daemon-origin marks have `mobile_batch_id = NULL`. Mobile-origin marks uploaded
in a batch reference `perf_mobile_batches.id`, so later analysis can apply the
same clock-sync quality and dropped-count context to all marks in that batch.

## Privacy And Redaction

Perf marks must not include:

- prompt text;
- assistant output text;
- command output text;
- attachment contents;
- secrets or tokens.

Allowed metadata:

- byte lengths;
- event type;
- adapter;
- route name;
- queue depth;
- dropped count;
- status code;
- coarse error code.

## Metrics To Derive Later

The backend analysis service can derive:

- app cold start time;
- conversation open to first visible message;
- large history first page and full backfill time;
- send tap to HTTP acknowledgement;
- send tap to first assistant partial frame;
- daemon raw event to persisted event;
- persisted event to WebSocket sent;
- WebSocket received to reducer applied;
- reducer applied to rendered frame;
- end-to-end adapter event to mobile frame.

This spec records enough marks for these metrics but does not implement the
analysis service.

## Failure Handling

Daemon:

- disabled tracing must not create `perf.sqlite`;
- perf write failures must not fail business requests;
- malformed mobile batches return controlled 400 errors;
- oversized batches return 413;
- unauthenticated requests return the normal auth error;
- disabled perf route accepts config checks and ignores mark uploads.

Mobile:

- disabled config prevents reporter startup;
- mark collection failures are swallowed;
- upload failures are invisible to the user;
- queue overflow drops marks;
- app termination loses queued marks;
- reporter disposal cancels timers and subscriptions.

## Testing Plan

Daemon tests:

- disabled tracer is no-op and does not create `perf.sqlite`;
- config route reflects enabled/disabled state;
- mobile marks route validates authentication, batch size, and metadata size;
- store writes marks in received order;
- store failure does not affect API response;
- stored rows can be inspected through direct SQL in tests.

Mobile tests:

- disabled publisher does not publish events;
- enabled publisher publishes `MobilePerformanceTraceMark`;
- reporter subscribes to `MobileAppEventBus` by event type;
- reporter preserves FIFO order;
- reporter enforces one in-flight upload;
- queue overflow increments dropped count;
- upload failure retries once and then drops;
- reporter disposal cancels subscription/timer.

Integration checks:

- start daemon with `VIBE_PERF_TRACE=1`;
- open mobile app and verify `/api/perf/config` enables tracing;
- send a short conversation message;
- verify daemon records mobile and daemon marks in `perf.sqlite`;
- inspect captured rows directly in `perf.sqlite`.

## Rollout

1. Add daemon no-op tracer, perf config route, and perf store.
2. Add daemon marks at event append and WebSocket boundaries.
3. Add mobile performance event type and disabled publisher.
4. Add mobile reporter, queue, and upload client.
5. Add mobile marks for send, WebSocket receipt, reducer, and post-frame render.
6. Add app startup and history loading marks.

Each step should keep tracing disabled by default and pass existing tests.
During step 3, published marks may have no reporter subscriber and be silently
dropped by the event bus. That is expected during staged rollout; the reporter
added in step 4 is the first durable consumer.

## Open Decisions

- Runtime backend toggling is deferred.
- Backend analysis service is deferred.
- UI/dashboard is explicitly excluded.
- Mobile local persistent queue is explicitly excluded.
