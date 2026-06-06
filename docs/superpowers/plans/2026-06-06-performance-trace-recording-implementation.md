# Performance Trace Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build passive daemon/mobile performance trace recording without changing user-visible behavior or adding UI.

**Architecture:** The daemon owns enablement, run lifecycle, validation, and durable SQLite storage in `data/app/perf.sqlite`. Mobile collection points only publish lightweight `MobilePerformanceTraceMark` events to the existing event bus; a background reporter owns in-memory queueing, clock sync, retry, and uploads.

**Tech Stack:** Node.js CommonJS daemon, `node:sqlite`, Flutter/Dart services, existing `DaemonClient` authenticated HTTP behavior, `MobileAppEventBus`, `scripts/run-tests.js`, focused Flutter tests.

---

## Source Spec

Implement against:

- `docs/superpowers/specs/2026-06-06-performance-tracing-design.md`

Do not implement:

- in-app UI;
- report/dashboard scripts;
- local persistent mobile queue;
- backend analysis service.

## File Structure

Daemon files:

- Create: `daemon/src/perf-config.js`
  - Reads env/config and exposes `enabled`, `runId`, `sampleRate`, queue limits, and batch limits.
- Create: `daemon/src/perf-tracer.js`
  - No-op when disabled; records daemon-origin marks with wall and monotonic timestamps.
- Create: `daemon/src/perf-sqlite-store.js`
  - Owns `data/app/perf.sqlite`, schema, run rows, mobile batches, mark writes, validation helpers.
- Create: `daemon/src/perf-routes.js`
  - Handles `/api/perf/config`, `/api/perf/time-sync`, and `/api/perf/mobile-marks`.
- Modify: `daemon/src/main.js`
  - Instantiates perf config/store/tracer and passes routes/tracer into `createServer` and later daemon services.
- Modify: `daemon/src/server.js`
  - Dispatches perf routes after normal paired-device authentication and adds HTTP boundary daemon marks.
- Modify: `daemon/src/conversation-manager.js`
  - Adds conversation send and adapter-event marks in a later task.
- Modify: `daemon/src/conversation-event-store.js`
  - Adds persisted-event marks in a later task.
- Modify: `daemon/src/notification-hub.js`
  - Adds WebSocket enqueue/send marks in a later task.
- Modify: `scripts/run-tests.js`
  - Adds daemon perf tests beside existing daemon/API/SQLite tests.

Mobile files:

- Modify: `mobile/lib/src/services/mobile_app_event_bus.dart`
  - Adds `MobilePerformanceTraceMark` event type.
- Create: `mobile/lib/src/services/performance_trace_clock.dart`
  - Small injectable wall/monotonic clock adapter.
- Create: `mobile/lib/src/services/performance_trace_startup_buffer.dart`
  - Holds at most `app.main.started` and early `app.first_frame` before reporter readiness.
- Create: `mobile/lib/src/services/performance_trace_publisher.dart`
  - Enabled flag plus `mark()` that only creates and publishes event-bus events.
- Create: `mobile/lib/src/services/performance_trace_client.dart`
  - Authenticated perf HTTP client backed by `DaemonClient`.
- Create: `mobile/lib/src/services/performance_trace_reporter.dart`
  - EventBus subscriber, bounded queue, retry/config/time-sync lifecycle, upload loop.
- Modify: `mobile/lib/main.dart`
  - Captures `app.main.started` into startup buffer before `runApp`.
- Modify: `mobile/lib/src/app/app_dependencies.dart`
  - Wires startup buffer, publisher, client, reporter into the connected daemon session.
- Modify: `mobile/lib/src/ui/main/main_page.dart`
  - Starts/stops reporter with connected shell lifecycle and records lifecycle pause flush.
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
  - Passes publisher to workbench.
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
  - Adds send, history, reducer, and render marks in a later task.
- Modify: `mobile/lib/src/services/daemon_notification_client.dart`
  - Adds WebSocket frame/event receipt marks in a later task.

Mobile test files:

- Create: `mobile/test/performance_trace_publisher_test.dart`
- Create: `mobile/test/performance_trace_reporter_test.dart`
- Create: `mobile/test/performance_trace_client_test.dart`
- Create: `mobile/test/performance_trace_startup_buffer_test.dart`
- Modify: `mobile/test/architecture_imports_tool_test.dart` only if the architecture check needs updated allowed service files.

---

## Task 1: Daemon Perf Config, Store, And Routes

**Files:**

- Create: `daemon/src/perf-config.js`
- Create: `daemon/src/perf-sqlite-store.js`
- Create: `daemon/src/perf-routes.js`
- Modify: `daemon/src/main.js`
- Modify: `daemon/src/server.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write disabled config/store tests**

Add tests to `scripts/run-tests.js`:

```js
test('perf config is disabled by default and does not create perf database', () => {
  const { createPerfConfig } = require('../daemon/src/perf-config');
  const { PerfSqliteStore } = require('../daemon/src/perf-sqlite-store');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'perf-disabled-'));
  const dbPath = path.join(dir, 'perf.sqlite');

  const config = createPerfConfig({ env: {}, now: () => new Date('2026-06-06T00:00:00.000Z') });
  const store = new PerfSqliteStore({ dbPath, config });

  assert.equal(config.enabled, false);
  assert.equal(fs.existsSync(dbPath), false);
  store.close();
});
```

Run: `cmd.exe /c npm test`

Expected: FAIL because `daemon/src/perf-config.js` does not exist.

- [ ] **Step 2: Implement `perf-config.js`**

Create:

```js
'use strict';

const crypto = require('node:crypto');

function createPerfConfig({
  env = process.env,
  now = () => new Date(),
  randomSuffix = () => crypto.randomBytes(3).toString('hex')
} = {}) {
  const enabled = env.VIBE_PERF_TRACE === '1';
  const state = { runId: null, startedAt: null };
  return {
    get enabled() { return enabled; },
    sampleRate: 1,
    maxQueueSize: 2000,
    maxBatchSize: 200,
    maxMetadataBytes: 1024,
    ensureRun() {
      if (!enabled) return null;
      if (state.runId == null) {
        const timestamp = now().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
        state.runId = `perf_${timestamp}_${randomSuffix()}`;
        state.startedAt = now().toISOString();
      }
      return { id: state.runId, startedAt: state.startedAt };
    }
  };
}

module.exports = { createPerfConfig };
```

- [ ] **Step 3: Implement `perf-sqlite-store.js` schema and no-op disabled behavior**

Create the class with these public methods:

```js
class PerfSqliteStore {
  constructor({ dbPath = defaultPerfDbPath(), config, now = () => new Date() } = {}) {}
  ensureRun() {}
  writeDaemonMark(mark) {}
  writeMobileBatch(batch) {}
  close() {}
}
```

Required behavior:

- do not create `perf.sqlite` until `config.enabled === true`;
- use `DatabaseSync`;
- run `PRAGMA foreign_keys = ON`;
- create `perf_runs`, `perf_mobile_batches`, and `perf_marks`;
- do not declare `run_id` foreign keys;
- declare `mobile_batch_id` foreign key;
- write mobile batch + marks in one transaction.

- [ ] **Step 4: Verify disabled store test passes**

Run: `cmd.exe /c npm test`

Expected: PASS.

- [ ] **Step 5: Write route tests for auth, enabled config, disabled upload, 413, source, metadata**

Add tests using existing `createApp` helpers or the in-process `http` test pattern already in `scripts/run-tests.js`:

```js
test('perf routes require paired-device authentication', async () => {
  // Start createApp({ appDbPath, perf enabled env/config injection }) and call
  // GET /api/perf/config without bearer auth.
  // Assert 401 normal auth error.
});

test('disabled perf mobile marks returns 200 disabled without rows', async () => {
  // Pair a device, POST /api/perf/mobile-marks with auth while VIBE_PERF_TRACE is unset.
  // Assert { accepted: 0, dropped: 0, disabled: true } and no perf.sqlite file.
});

test('perf mobile marks rejects unknown source and oversized metadata', async () => {
  // Enable tracing, pair auth, send source: "client" and assert 400.
  // Send metadata with a serialized size > 1024 bytes and assert 400.
});

test('perf mobile marks rejects oversized batch with 413', async () => {
  // Enable tracing, send 201 marks when maxBatchSize is 200, assert 413.
});
```

Expected before route implementation: FAIL with 404.

- [ ] **Step 6: Implement `perf-routes.js`**

Create `handlePerfRoute({ method, url, device, readJson, json, perfConfig, perfStore })`.

Rules:

- `GET /api/perf/config`
  - auth is already done in `server.js`;
  - if disabled, return `{ enabled: false }`;
  - if enabled, call `perfStore.ensureRun()` before returning `runId`;
  - return `enabled`, `runId`, `sampleRate`, `maxQueueSize`, `maxBatchSize`.
- `POST /api/perf/time-sync`
  - validate JSON object;
  - return daemon receive/send wall ms;
  - do not write rows.
- `POST /api/perf/mobile-marks`
  - if disabled, return `200 { accepted: 0, dropped: 0, disabled: true }`;
  - validate `runId`, `deviceId`, `appSessionId`, dropped counters, `clockSync`, and marks;
  - reject marks whose `source` is not `mobile`;
  - reject serialized `metadata` > 1024 bytes;
  - reject `marks.length > maxBatchSize` with 413;
  - call `perfStore.writeMobileBatch()`;
  - return accepted count and daemon receive/send wall ms.

- [ ] **Step 7: Wire routes into `server.js` and `main.js`**

Modify `createServer` signature to accept:

```js
perfConfig = null,
perfStore = null,
perfTracer = null
```

After `const device = auth.authenticate(...)`, add:

```js
const handledPerf = await handlePerfRoute({
  method,
  url,
  device,
  readJson: () => readJson(req),
  json: (status, body, headers) => json(res, status, body, headers),
  perfConfig,
  perfStore
});
if (handledPerf) return;
```

In `createApp`, instantiate config/store and pass them into `createServer`.

- [ ] **Step 8: Run daemon route/store tests**

Run: `cmd.exe /c npm test`

Expected: PASS for all new perf tests.

- [ ] **Step 9: Commit Task 1**

```bash
git add daemon/src/perf-config.js daemon/src/perf-sqlite-store.js daemon/src/perf-routes.js daemon/src/main.js daemon/src/server.js scripts/run-tests.js
git commit -m "Add passive perf trace daemon storage and routes"
```

---

## Task 2: Daemon Tracer And Daemon-Side Marks

**Files:**

- Create: `daemon/src/perf-tracer.js`
- Modify: `daemon/src/main.js`
- Modify: `daemon/src/server.js`
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/conversation-event-store.js`
- Modify: `daemon/src/notification-hub.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write tracer no-op and enabled tests**

Add:

```js
test('perf tracer is no-op when disabled and never throws', () => {
  const { PerfTracer } = require('../daemon/src/perf-tracer');
  const tracer = new PerfTracer({ enabled: false, writer: { writeDaemonMark() { throw new Error('boom'); } } });
  assert.doesNotThrow(() => tracer.mark({ name: 'http.conversation.request.received' }));
});

test('perf tracer writes daemon marks with source and timestamps when enabled', () => {
  const marks = [];
  const { PerfTracer } = require('../daemon/src/perf-tracer');
  const tracer = new PerfTracer({
    enabled: true,
    writer: { writeDaemonMark(mark) { marks.push(mark); } },
    nowWallMs: () => 1791200000000,
    nowMonoUs: () => 123456
  });
  tracer.mark({ name: 'ws.event.sent', conversationId: 'conv_1', seq: 7 });
  assert.equal(marks[0].source, 'daemon');
  assert.equal(marks[0].name, 'ws.event.sent');
  assert.equal(marks[0].wallTimeMs, 1791200000000);
  assert.equal(marks[0].monotonicUs, 123456);
});
```

Expected: FAIL until tracer exists.

- [ ] **Step 2: Implement `PerfTracer`**

Implementation shape:

```js
class PerfTracer {
  constructor({ enabled, writer, nowWallMs = () => Date.now(), nowMonoUs = defaultMonoUs } = {}) {}
  isEnabled() { return this.enabled === true; }
  mark(input) {
    if (!this.isEnabled()) return;
    try {
      this.writer.writeDaemonMark({
        source: 'daemon',
        name: input.name,
        wallTimeMs: this.nowWallMs(),
        monotonicUs: this.nowMonoUs(),
        conversationId: input.conversationId ?? null,
        seq: input.seq ?? null,
        eventType: input.eventType ?? null,
        correlationId: input.correlationId ?? null,
        metadata: input.metadata ?? {}
      });
    } catch (error) {
      // Swallow by design. Diagnostic warning can be added through audit/log later.
    }
  }
}
```

- [ ] **Step 3: Wire tracer into `main.js` and `server.js`**

Instantiate with `enabled: perfConfig.enabled, writer: perfStore`.

Add initial HTTP marks in `server.js`:

- `http.conversation.request.received`
- `http.conversation.response.sent`
- `conversation.send.received`

Keep response mark placement narrow around conversation POST routes.

- [ ] **Step 4: Add conversation/store/notification marks**

Add marks at existing boundaries:

- `conversation.user.persisted` after user message persistence;
- `adapter.send.started`;
- `adapter.send.accepted`;
- `adapter.raw_event.received`;
- `adapter.event.normalized`;
- `event.persisted` in `ConversationEventStore`;
- `ws.event.enqueued` and `ws.event.sent` in `NotificationHub`.

Use only content-free metadata: route, queue depth, status code, event type, byte length.

- [ ] **Step 5: Add focused tests for mark names and disabled safety**

Use fakes around `ConversationManager`, `ConversationEventStore`, and `NotificationHub` similar to existing tests. Assert mark names appear in order for a synthetic conversation event path.

- [ ] **Step 6: Run daemon tests**

Run: `cmd.exe /c npm test`

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

```bash
git add daemon/src/perf-tracer.js daemon/src/main.js daemon/src/server.js daemon/src/conversation-manager.js daemon/src/conversation-event-store.js daemon/src/notification-hub.js scripts/run-tests.js
git commit -m "Record daemon-side perf trace marks"
```

---

## Task 3: Mobile Event Type, Startup Buffer, Publisher, And Client

**Files:**

- Modify: `mobile/lib/src/services/mobile_app_event_bus.dart`
- Create: `mobile/lib/src/services/performance_trace_clock.dart`
- Create: `mobile/lib/src/services/performance_trace_startup_buffer.dart`
- Create: `mobile/lib/src/services/performance_trace_publisher.dart`
- Create: `mobile/lib/src/services/performance_trace_client.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Create: `mobile/test/performance_trace_startup_buffer_test.dart`
- Create: `mobile/test/performance_trace_publisher_test.dart`
- Create: `mobile/test/performance_trace_client_test.dart`

- [ ] **Step 1: Add failing tests for publisher and startup buffer**

Create tests:

```dart
test('disabled publisher does not publish performance marks', () async {
  final bus = MobileAppEventBus();
  final publisher = PerformanceTracePublisher(
    eventBus: bus,
    clock: FakePerformanceTraceClock(wallMs: 10, monoUs: 20),
  );
  final events = <MobilePerformanceTraceMark>[];
  final sub = bus.on<MobilePerformanceTraceMark>().listen(events.add);

  publisher.mark('send.tap');
  await pumpEventQueue();

  expect(events, isEmpty);
  await sub.cancel();
  await bus.dispose();
});

test('startup buffer retains at most two marks and drops later by arrival order', () {
  final buffer = PerformanceTraceStartupBuffer();
  buffer.capture(MobilePerformanceTraceMark(name: 'app.main.started', wallTimeMs: 1, monotonicUs: 1, critical: true));
  buffer.capture(MobilePerformanceTraceMark(name: 'app.first_frame', wallTimeMs: 2, monotonicUs: 2, critical: true));
  buffer.capture(MobilePerformanceTraceMark(name: 'startup.third', wallTimeMs: 3, monotonicUs: 3, critical: true));

  final drained = buffer.drain();
  expect(drained.map((mark) => mark.name), ['app.main.started', 'app.first_frame']);
  expect(buffer.droppedCriticalCount, 1);
});
```

Expected: FAIL until files/classes exist.

- [ ] **Step 2: Add `MobilePerformanceTraceMark` to EventBus file**

Add immutable fields exactly from the spec:

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
  // fields...
}
```

- [ ] **Step 3: Implement clock, startup buffer, and publisher**

Requirements:

- publisher has `setEnabled(bool enabled)`;
- disabled publisher returns immediately;
- enabled publisher creates one mark and calls `eventBus.publish`;
- no HTTP, no JSON, no file IO, no await in `mark()`;
- startup buffer is max length 2 and append-only until drained.

- [ ] **Step 4: Add `DaemonClient` raw JSON helpers if needed**

If `_post`/`_get` remain private, add public methods:

```dart
Future<Map<String, Object?>> getAuthorizedJson(String path);
Future<Map<String, Object?>> postAuthorizedJson(String path, Map<String, Object?> body);
```

Reuse existing auth retry behavior.

- [ ] **Step 5: Implement `PerformanceTraceClient`**

Public methods:

```dart
Future<PerformanceTraceConfig> fetchConfig();
Future<PerformanceTimeSyncResponse> timeSync(PerformanceTimeSyncRequest request);
Future<PerformanceTraceUploadResponse> upload(PerformanceTraceUploadRequest request);
```

It must:

- reuse `DaemonClient`;
- parse disabled config;
- surface 413 as a typed `PerformanceTraceUploadTooLarge`;
- keep token refresh behavior identical to normal authenticated APIs.

- [ ] **Step 6: Run mobile service tests**

Run from `mobile/`:

`flutter test --no-pub test\performance_trace_startup_buffer_test.dart test\performance_trace_publisher_test.dart test\performance_trace_client_test.dart`

Expected: PASS.

- [ ] **Step 7: Run architecture check**

Run from `mobile/`:

`dart run tool\check_architecture_imports.dart`

Expected: PASS.

- [ ] **Step 8: Commit Task 3**

```bash
git add mobile/lib/src/services/mobile_app_event_bus.dart mobile/lib/src/services/performance_trace_clock.dart mobile/lib/src/services/performance_trace_startup_buffer.dart mobile/lib/src/services/performance_trace_publisher.dart mobile/lib/src/services/performance_trace_client.dart mobile/lib/src/services/daemon_client.dart mobile/test/performance_trace_startup_buffer_test.dart mobile/test/performance_trace_publisher_test.dart mobile/test/performance_trace_client_test.dart
git commit -m "Add mobile perf trace publisher and client"
```

---

## Task 4: Mobile Reporter Queue, Retry, Time Sync, And Lifecycle Flush

**Files:**

- Create: `mobile/lib/src/services/performance_trace_reporter.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/main/main_page.dart`
- Create: `mobile/test/performance_trace_reporter_test.dart`

- [ ] **Step 1: Write reporter queue pressure tests**

Create tests that assert:

- FIFO order for normal marks;
- queue overflow increments dropped counters;
- critical mark at full capacity evicts oldest non-critical;
- all-critical full queue drops incoming critical;
- pre-startup drained marks keep original timestamps.

Use a fake client with captured upload requests.

- [ ] **Step 2: Write reporter failure/time-sync tests**

Tests must cover:

- one in-flight upload at a time;
- failed upload retries once on next flush interval;
- second failure drops retained batch and folds counts into next successful upload;
- 3 consecutive failures pause uploads;
- config check success while paused resumes uploads and resets count;
- HTTP 413 refreshes config, splits retained batch, and retries;
- failed split retry after 413 counts toward consecutive failure count;
- first flush before time-sync completion sends `unknown`;
- stale age over 30000 ms triggers standalone time-sync;
- time-sync failure is swallowed;
- lifecycle pause flush times out after 1500 ms and does not schedule immediate retry.

- [ ] **Step 3: Implement reporter**

Core fields:

```dart
final Queue<MobilePerformanceTraceMark> _queue = Queue<MobilePerformanceTraceMark>();
int _nonCriticalCount = 0;
int _droppedCriticalSinceSuccess = 0;
int _droppedNonCriticalSinceSuccess = 0;
int _consecutiveFailures = 0;
bool _paused = false;
bool _uploadInFlight = false;
```

Queue full behavior:

- non-critical incoming: drop incoming;
- critical incoming and non-critical exists: remove oldest non-critical by bounded scan;
- critical incoming and all critical: drop incoming.

Startup buffer:

- reporter actively drains composition-root buffer after config enabled;
- folded startup dropped counts are included in first successful upload counters.

- [ ] **Step 4: Wire reporter in connected session**

In `AppDependencies.createMainDependencies`, build:

- `PerformanceTraceClient` from connected `DaemonClient`;
- `PerformanceTracePublisher`;
- `PerformanceTraceReporter`.

In `MainPage.initState`, start reporter after `_mobileAppEventBus` exists.

In `MainPage.dispose`, dispose reporter before event bus.

In `didChangeAppLifecycleState`, call best-effort flush for paused/inactive states.

- [ ] **Step 5: Run reporter tests**

Run from `mobile/`:

`flutter test --no-pub test\performance_trace_reporter_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

```bash
git add mobile/lib/src/services/performance_trace_reporter.dart mobile/lib/src/app/app_dependencies.dart mobile/lib/src/ui/main/main_page.dart mobile/test/performance_trace_reporter_test.dart
git commit -m "Add mobile perf trace reporter queue"
```

---

## Task 5: Mobile Trace Mark Collection Sites

**Files:**

- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/services/daemon_notification_client.dart`
- Modify: mobile tests as needed for constructor changes.

- [ ] **Step 1: Capture startup marks**

In `main.dart`, replace the one-line main with:

```dart
void main() {
  final startupBuffer = PerformanceTraceStartupBuffer.global;
  startupBuffer.captureStartupMark('app.main.started', critical: true);
  runApp(LanAiCliControlApp(startupBuffer: startupBuffer));
}
```

Adapt `LanAiCliControlApp`/`MobileUi` only as needed to pass the buffer into `AppDependencies`.

- [ ] **Step 2: Add workbench publisher dependency**

Add nullable `PerformanceTracePublisher? performanceTracePublisher` to `WorkbenchDependencies` and `copyWith`.

Use nullable injection so tests and disconnected states remain simple.

- [ ] **Step 3: Add send/history/reducer/render marks**

In `coding_workbench_page.dart`, mark:

- `conversation.page.opened`;
- `history.first_page.started`;
- `history.first_page.applied` critical;
- `history.backfill.completed` critical;
- `send.tap` critical;
- `send.http.started`;
- `send.http.completed` critical;
- `send.optimistic.rendered`;
- `reducer.applied` critical;
- `event.frame.rendered` critical via post-frame callback.

All metadata must be content-free.

- [ ] **Step 4: Add WebSocket receipt marks**

In `DaemonNotificationClient`, add optional publisher dependency or callback and mark:

- `ws.connected`;
- `ws.frame.received`;
- `ws.event.received` critical.

Preserve current reconnect/backfill behavior.

- [ ] **Step 5: Run focused mobile tests**

Run from `mobile/`:

`flutter test --no-pub test\coding_workbench_controller_test.dart test\daemon_notification_client_test.dart test\widget_test.dart`

Expected: PASS.

- [ ] **Step 6: Run architecture check**

Run from `mobile/`:

`dart run tool\check_architecture_imports.dart`

Expected: PASS.

- [ ] **Step 7: Commit Task 5**

```bash
git add mobile/lib/main.dart mobile/lib/src/app/app_dependencies.dart mobile/lib/src/ui/features/workbench/workbench_dependencies.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/src/services/daemon_notification_client.dart mobile/test
git commit -m "Record mobile perf trace marks"
```

---

## Task 6: End-To-End Verification And Rollout Guardrails

**Files:**

- Modify: `scripts/run-tests.js`
- Modify: `docs/project-knowledge/architecture.md` or `docs/project-knowledge/open-risks.md` only if implementation reveals durable lessons not already in the spec.

- [ ] **Step 1: Add integration-style daemon smoke**

Add a daemon test that:

- starts `createApp` with perf enabled and temp `appDbPath`;
- pairs a device;
- calls `/api/perf/config`;
- posts one mobile batch;
- queries `perf.sqlite` directly and asserts one run row, one batch row, and one mark row.

- [ ] **Step 2: Run daemon test suite**

Run:

`cmd.exe /c npm test`

Expected: PASS.

- [ ] **Step 3: Run mobile focused test suite**

Run from `mobile/`:

`flutter test --no-pub test\performance_trace_startup_buffer_test.dart test\performance_trace_publisher_test.dart test\performance_trace_client_test.dart test\performance_trace_reporter_test.dart test\daemon_notification_client_test.dart test\coding_workbench_controller_test.dart`

Expected: PASS.

- [ ] **Step 4: Run mobile architecture check**

Run from `mobile/`:

`dart run tool\check_architecture_imports.dart`

Expected: PASS.

- [ ] **Step 5: Run final static checks**

Run from repo root:

`node scripts/check-project-knowledge.js`

`git diff --check`

Expected: PASS.

- [ ] **Step 6: Manual integration smoke**

Manual sequence:

1. Start daemon with `VIBE_PERF_TRACE=1`.
2. Wait until daemon is listening.
3. Open or restart mobile.
4. Pair/connect mobile if needed.
5. Send one short conversation message.
6. Inspect `data/app/perf.sqlite`.

Expected:

- `perf_runs` has one row for the daemon process;
- `perf_mobile_batches` has at least one row;
- `perf_marks` has daemon and mobile rows;
- prompt/output text is absent from `metadata_json`.

- [ ] **Step 7: Commit final verification adjustments**

```bash
git add scripts/run-tests.js docs/project-knowledge
git commit -m "Verify passive perf trace recording"
```

---

## Self-Review

Spec coverage:

- Backend enablement and no-op default: Task 1.
- Perf routes, auth, disabled response, 413, metadata/source validation: Task 1.
- SQLite schema, run lifecycle, batch atomicity: Task 1.
- Daemon marks: Task 2.
- Mobile event bus, publisher, client, startup buffer: Task 3.
- Reporter queue, dropped counters, retries, pause/config checks, time-sync: Task 4.
- Mobile collection sites: Task 5.
- Integration and verification: Task 6.

Known sequencing constraints:

- Do not add collection-site marks before Task 4 reporter exists unless they are disabled/no-op.
- Do not add UI controls.
- Do not write mobile trace data to files or SQLite.
- Keep every collection path synchronous and allocation-light.

The implementation sequence has concrete files, behavior, tests, and commands.
