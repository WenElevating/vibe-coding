# Mobile Conversation Background Sync Design

Date: 2026-06-11
- Status: design approved, pending written-spec review
- Scope: Flutter mobile conversation sync ownership across foreground route
  changes, Android background execution, and iOS degraded-resume behavior

## Problem

The daemon already owns the authoritative conversation event log and persists
ordered `ConversationEvent` rows. The weak point is the mobile sync lifetime.

Today, `CodingWorkbenchPage` owns the active conversation event subscription.
When the user leaves the conversation route, the page cancels the watcher even
if the conversation is still running. The daemon continues to append valid
events, but the mobile client stops receiving them until the user re-enters the
conversation and reloads history.

That creates three product problems:

1. Foreground route changes make running work look stalled.
2. The local read-through cache stops advancing while the user is still using
   the app.
3. The current "keep session live in background" setting only covers app
   lifecycle backgrounding, not the common case of switching to the session
   list, settings, or another in-app route.

For a mobile control surface, that boundary is too narrow. The conversation page
should own rendering and interaction, not whether the device continues to
observe a running job.

## Current Project Context

Relevant current decisions and code paths:

- Daemon remains the source of truth for persisted conversation events.
- Mobile already has a local read-through cache for synced event rows.
- WebSocket notifications are already the primary realtime transport.
- `CodingWorkbenchPage` currently cancels or restarts event subscriptions during
  route changes and app lifecycle changes.
- `CachedConversationRepository.watchConversationEvents()` already writes
  streamed events into the local event cache and updates summary projection.

Important current files:

```text
mobile/lib/src/ui/features/workbench/coding_workbench_page.dart
mobile/lib/src/data/repositories/cached_conversation_repository.dart
mobile/lib/src/services/daemon_notification_client.dart
mobile/lib/src/data/services/conversation_event_cache_store.dart
mobile/lib/src/services/approval_notification_handler.dart
mobile/android/app/src/main/kotlin/.../BackgroundDownloadService.kt
```

## Research Summary

### Android

Android supports user-visible long-running background work through foreground
services. That is the correct platform tool when the app needs to keep work
alive while the user is no longer looking at the activity, but the user still
expects the task to continue. WorkManager may also host long-running work, but
it still relies on foreground-service behavior for user-visible long tasks and
does not remove the notification requirement.

Android also constrains when foreground services may be started. On modern
targets, the service should be started while the app is transitioning from a
user-visible state, not later from an already-idle background process. Android
14+ also requires an explicit foreground-service type. The first implementation
should use the closest supported type for daemon event synchronization, likely
`dataSync`, and validate target-SDK behavior before release.

Useful official references:

- Foreground services:
  `https://developer.android.com/develop/background-work/services/fgs`
- Long-running workers:
  `https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/long-running`
- Background-start restrictions:
  `https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start`
- Required foreground-service types:
  `https://developer.android.com/about/versions/14/changes/fgs-types-required`

### iOS

iOS should not be designed around an assumption that an arbitrary WebSocket can
remain alive indefinitely in the background. Background execution is selective,
time-bounded, and purpose-specific. Background Tasks and background URLSession
fit refresh and transfer workflows; they are not a promise of continuous socket
delivery for an arbitrary LAN session.

Useful official references:

- Background task strategies:
  `https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app`
- Extending foreground work after background transition:
  `https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time`
- `UIApplication.beginBackgroundTask(expirationHandler:)`:
  `https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask%28expirationhandler%3A%29`

## Accepted Direction

Adopt a three-part design:

1. **Foreground route-independent sync**
   Move conversation event transport ownership out of `CodingWorkbenchPage` and
   into a mobile sync coordinator that survives in-app route changes.
2. **Android true background support**
   When the user enables background live sync and active tracked conversations
   still exist, keep the Android process alive through a user-visible foreground
   service.
3. **iOS explicit degraded mode**
   Do not promise continuous background sockets. Preserve cursors and cache on
   background, then backfill and resume aggressively on foreground return.

This design keeps the daemon event log authoritative, keeps mobile cache as a
read-through copy, and stops binding sync lifetime to a single UI page.

## Goals

- Keep active conversations syncing while the app remains in the foreground,
  even when the user leaves the conversation route.
- Keep already-synced events flowing into the local mobile cache so re-entering
  a conversation is immediate instead of waiting for a cold reload.
- Keep conversation summaries, pending approval state, and other list-level
  projections hot while tracked conversations are still running.
- Provide an Android-specific path for background continuation with explicit
  user-visible system notification.
- Provide an iOS path that is honest about platform limits and optimized for
  fast recovery on resume.
- Preserve the existing daemon WebSocket + REST backfill reliability model.
- Respect the current layered architecture: UI, optional workflow/use-case,
  repository, service, platform bridge.

## Non-Goals

- No APNs, FCM, or cloud relay service in this design.
- No daemon-side push infrastructure for fully closed or suspended clients.
- No native reimplementation of the daemon notification protocol unless later
  device testing proves the Flutter-isolate path unreliable under Android
  foreground-service anchoring.
- No change to the daemon event schema or conversation authorization model.
- No attempt to keep every historical conversation continuously subscribed.
- No UI redesign beyond the settings/notification affordances required by the
  feature.

## Architecture

### Layer Placement

Follow the current repo's layered architecture:

```text
UI
  Workbench pages and ViewModels
    -> Workflow
      ConversationSyncCoordinator
        -> Repository
          ConversationRepository / CachedConversationRepository
            -> Service
              NotificationService, background-sync bridge, lifecycle bridge
```

Ownership rules:

- `CodingWorkbenchPage` owns rendering, route transitions, scroll anchoring, and
  conversation interaction UI.
- `WorkbenchViewModel` owns feature presentation state and tells the coordinator
  which conversation is foreground-active through an idempotent lease. The
  signal must be resilient to ViewModel rebuilds and route-generation changes.
- `ConversationSyncCoordinator` owns sync lifetime, tracked conversation policy,
  and underlying stream subscriptions.
- `CachedConversationRepository` remains the source of mobile-side cache writes
  and summary projection from streamed events.
- Platform-specific background behavior lives behind a service bridge, not in
  the UI.

### New Runtime Components

Suggested new files:

```text
mobile/lib/src/workflows/conversation_sync/conversation_sync_coordinator.dart
mobile/lib/src/workflows/conversation_sync/conversation_sync_policy.dart
mobile/lib/src/workflows/conversation_sync/conversation_sync_target.dart
mobile/lib/src/services/background_conversation_sync_bridge.dart
mobile/lib/src/services/method_channel_background_conversation_sync_bridge.dart
mobile/android/app/src/main/kotlin/.../BackgroundConversationSyncService.kt
```

The exact folder names may be adjusted to match existing local conventions, but
the responsibilities should remain separated in this way.

### ConversationSyncPolicy

Sync timing must be centralized in a policy object so tests do not duplicate
magic durations.

Required defaults:

```text
terminalGrace = 45 seconds
backgroundDisconnectGrace = 30 seconds
consumerLagQueueLimit = 256 events
```

`terminalGrace` is the post-terminal period during which a tracked conversation
keeps its watcher alive for late final events. The default is intentionally
longer than a short UI frame delay and shorter than a background service that
would feel stuck. It controls:

- fake-timer expectations in coordinator tests;
- Android foreground-service stop timing after all targets become terminal;
- iOS cleanup budget decisions when the app backgrounds near a terminal event.

If a future developer setting or remote policy exposes this value, clamp it to
`15 seconds <= terminalGrace <= 120 seconds`. The first implementation should
not expose it as a user setting.

### Core Model: Tracked Conversations

The coordinator tracks only conversations that still matter for continuity:

- `running`
- `waiting_input`
- `waiting_approval`
- a `terminalGrace` post-terminal period for late final events

It does not keep idle historical conversations subscribed forever.

Each tracked target should store:

```text
conversationId
runId
lastSeq
currentStatus
foregroundConsumerCount
keepAliveReason
terminalGraceDeadline
lastEventAt
```

`lastSeq` is the cursor boundary. The coordinator never invents event history;
it always reconnects through the existing `afterSeq` + REST backfill model.

`runId` is not the durable event identity and must not be used as an event
cursor. It exists for stale async guards, diagnostics, and route/session
correlation while the current UI still models workbench sessions with both run
and conversation ids. `conversationId` remains the event and cache identity.

### Core Rule: One Underlying Watcher Per Tracked Conversation

The coordinator owns the single underlying
`ConversationRepository.watchConversationEvents(conversationId, afterSeq)`
subscription for a tracked conversation.

The conversation page no longer opens its own transport watcher directly.
Instead:

1. The page loads the initial event page from the repository/cache.
2. The page registers itself as a foreground consumer of that conversation with
   the coordinator and receives a disposable `ConversationSyncLease`.
3. The coordinator starts or reuses the single watcher for that conversation.
4. The coordinator fans streamed events out to any current foreground listeners
   and keeps the repository stream alive when policy says the conversation
   should stay synced.

This prevents duplicate transport watchers for the same conversation while still
allowing the current route to update live.

### Foreground Consumer Leases

Do not implement foreground attachment as a bare mutable reference count.
`foregroundConsumerCount` should be derived from active lease records owned by
the coordinator.

Attach API shape:

```dart
abstract class ConversationSyncLease {
  String get conversationId;
  Stream<ConversationEvent> get events;
  Future<void> dispose();
}
```

Rules:

- `dispose()` is idempotent.
- `WorkbenchViewModel` stores the active lease and disposes it when the
  conversation route changes, the ViewModel is disposed, or a new generation of
  the route replaces the old one.
- `CodingWorkbenchPage.dispose()` and route-pop paths must indirectly release
  the lease through ViewModel disposal or an explicit ViewModel command.
- The coordinator should tag leases with an owner/generation id. When
  `WorkbenchViewModel` switches route generation, it can ask the coordinator to
  release all leases for the previous owner generation as a defensive cleanup.
- No design should rely on Dart garbage collection to stop a watcher.

### Cache Semantics

In this design, "write to cache" means:

- streamed `ConversationEvent` rows continue to flow through
  `CachedConversationRepository.watchConversationEvents()`;
- that repository continues to persist synced rows into the mobile local
  read-through cache keyed by daemon session + `conversationId`;
- re-entering a tracked conversation can immediately render the cached latest
  transcript without waiting for a full cold reload.

The daemon remains authoritative. Mobile cache is still a synced local copy, not
the source of truth.

Cursor durability should be tied to cache durability. Each accepted event write
must update the durable newest synced cursor for that conversation as part of
the same serialized cache update, or derive the cursor from the cache record's
newest event on restart. This is necessary for force-quit recovery on mobile
platforms where no background callback is guaranteed.

### Event Fan-Out And Slow Consumers

The underlying watcher has one durable responsibility: feed events through
`CachedConversationRepository` so cache and summary projection advance. UI
consumers are secondary observers.

Do not use a single `StreamController.broadcast()` as the durability boundary.
Broadcast streams do not provide the right slow-consumer semantics for the
foreground transcript.

Use per-lease single-subscription event streams with bounded queues:

- every foreground lease has its own queue;
- the default queue limit is `ConversationSyncPolicy.consumerLagQueueLimit`
  (`256` events);
- coordinator delivery to one slow lease must not block cache writes, summary
  projection, or other leases;
- if a lease queue overflows, the coordinator marks that lease as lagged,
  stops direct event delivery to that lease, and emits a recoverable
  `ConsumerLagged` signal;
- the ViewModel responds by reloading from the local cache/daemon backfill using
  its last applied `seq`, then reattaches a fresh lease.

This gives slow UI code a clear recovery path without silently dropping content.

### Foreground Route Behavior

This is the most important behavioral change.

When the app is still in the foreground:

- switching from the conversation detail route to the session list does **not**
  stop sync for tracked running conversations;
- switching to settings or another tab does **not** stop sync for tracked
  running conversations;
- the session list should keep seeing summary/status updates because the
  repository projection continues to advance;
- approval events received while the route is hidden should still feed the
  existing approval notification path.

Foreground route changes become a UI concern, not a transport concern.

### App Lifecycle Behavior

Foreground and background policy should be explicit:

- **App foreground**:
  active tracked conversations keep syncing regardless of whether the current UI
  route is the conversation detail page.
- **App background, setting disabled**:
  tracked conversations stop after a short grace period, matching current user
  expectation for battery-conscious behavior.
- **App background, setting enabled on Android**:
  tracked conversations continue while the Android foreground service is active.
- **App background on iOS**:
  preserve cursor and cache immediately, keep syncing only as long as the OS
  temporarily allows, and then rely on resume backfill.

The existing `coding.keepConversationEventsInBackground` setting should be
redefined to control only **app background continuation**, not in-app route
changes. In-app route changes should keep sync without consulting this setting.

This is a user-visible semantic change. Existing stored preference values remain
valid; there is no data migration. A stored `false` still means "do not keep
sync running after the app backgrounds." It no longer means "stop syncing when
the user leaves the conversation detail page while the app is still foreground."
The settings subtitle and release notes should call out the new interpretation.
Approving this design is product acceptance for foreground route-independent
sync being always on for tracked active conversations.

### Android Background Design

#### Accepted Direction

Use a foreground service as the Android background continuation anchor.

The Flutter sync coordinator continues to own the notification client and event
policy. The foreground service exists to keep the process user-visible and less
likely to be reclaimed while tracked conversations remain active.

This first design intentionally avoids building a parallel native Kotlin
WebSocket stack. That would duplicate notification protocol logic, auth refresh,
cursor semantics, and backfill behavior that already exist in Dart.

The service should be started while the app is still user-visible or during the
immediate transition to background. If Android rejects a start request with a
foreground-service start restriction, the coordinator records background sync as
unavailable for that lifecycle turn, stops the background watcher after normal
grace, and relies on daemon backfill when the app returns.

#### Foreground Notification Contract

The Android service notification should show:

- number of tracked running conversations;
- number of conversations waiting for approval;
- a concise status summary such as "2 tasks running" or "1 task waiting for
  approval";
- an action to reopen the app;
- an action to stop background live sync.

The notification is not optional. Background continuation must remain explicit
to the user.

#### Service Lifetime

Start the service when all of these are true:

- platform is Android;
- app transitions to background;
- the background-live-sync setting is enabled;
- at least one conversation remains in a tracked active state.

Stop the service when any of these becomes true:

- no tracked conversations remain active after terminal grace;
- the user disables background live sync;
- the user explicitly stops background live sync from the notification;
- the app returns to foreground and product policy decides the service is no
  longer necessary.

#### Reuse Existing Native Patterns

The repo already contains Android foreground-service patterns for background
download. Reuse those conventions for:

- service creation and teardown;
- method-channel bridge shape;
- notification channel management;
- status snapshot reporting back into Dart.

#### Auth And Process Lifetime

The first Android version keeps auth refresh in the existing Dart
notification-client path. The foreground service is a process/lifetime anchor;
it does not own credentials and does not open a separate native WebSocket.

Rules:

- `DaemonNotificationClient` continues to call its existing token provider and
  `refreshAuth` callback when the WebSocket reports auth expiration or closes
  for auth reasons.
- The coordinator must use the same connection-scoped repositories and services
  that foreground workbench code uses, so token refresh and daemon base URI
  state are not duplicated.
- The foreground service must report service start/stop/failure events back to
  Dart, but it must not mutate auth state directly.
- If the Android process is killed, the foreground service is not expected to
  resurrect a full Dart sync graph by itself in the first version. On next app
  launch, mobile reads cached cursor state and backfills from the daemon.
- If Android restarts the service without the Dart coordinator alive, the
  service should stop itself and leave recovery to normal app launch/backfill.

### iOS Degraded-Resume Design

The iOS path should be intentionally conservative.

Accepted behavior:

- on background, flush the latest known cursor and cache state immediately;
- call `UIApplication.beginBackgroundTask(withName:expirationHandler:)` only to
  finish in-flight local cleanup or last backfill writes, not to promise
  indefinite socket uptime;
- on resume, immediately backfill every tracked conversation from its stored
  `lastSeq`, then restore the realtime watcher;
- keep approval/system state consistent through replayed conversation events
  rather than relying on persistent background sockets.

The first iOS version should not schedule `BGAppRefreshTask`,
`BGProcessingTask`, or background `URLSession` work for conversation live sync.
Those APIs have different semantics: refresh/processing tasks are
system-scheduled background opportunities, and background URLSession is for
transfers. This feature needs short cleanup on background transition and fast
resume backfill.

Expiration handler behavior:

- mark the iOS live-sync tail as expired;
- cancel any nonessential socket/listener work;
- allow the serialized cache/cursor write currently in progress to complete if
  there is still time;
- stop scheduling new backfill work;
- call `endBackgroundTask` promptly.

iOS force-quit gives no reliable callback. Recovery must therefore depend on
cursor persistence during normal event processing, not only on the background
transition. If the app is force-quit after an event reaches Dart but before the
cache write completes, daemon backfill from the last durable `seq` replays the
missing event; duplicate delivery is handled by `conversationId + seq` dedupe.

Rejected behavior:

- advertising that iOS will continuously mirror daemon output while the app is
  suspended;
- introducing a fake "live in background" toggle that behaves materially
  differently than the product implies.

If later product requirements demand reliable off-screen approvals or task
completion alerts on iOS, that should become a separate push-notification or
server-relay design, not an undocumented side effect of this feature.

### Approval and Summary Projection

The design must preserve existing approval and summary behavior:

- streamed approval events still travel through the current event model;
- `ApprovalNotificationHandler` continues to derive notifications from already
  received app events;
- conversation summary/status updates continue to be projected by the
  repository while the coordinator keeps the stream alive;
- reopening a session list should show current running/waiting states without
  needing to open the conversation detail first.

### Error Handling and Recovery

Preserve the current reliability model:

- WebSocket remains the low-latency path.
- REST backfill remains the repair path.
- `afterSeq` remains the only resume cursor.

Coordinator rules:

- never advance `lastSeq` without receiving or backfilling actual events;
- ignore mismatched `conversationId` events;
- dedupe by `conversationId + seq`;
- preserve per-conversation terminal grace so a final late event can still be
  applied without reopening the whole tracker;
- contain watcher failures and re-enter the existing notification-client
  reconnect/backfill path rather than inventing a second recovery system.

Force-quit and process-death rules:

- daemon persistence is the recovery source;
- mobile stores the latest durable cursor as part of every accepted cache write;
- on app launch, the coordinator derives resume cursors from cache before
  subscribing;
- duplicate replayed rows are harmless and must be deduped by
  `conversationId + seq`.

### Observability

Add explicit sync trace marks for:

- target tracked;
- target untracked;
- foreground consumer attached/detached;
- watcher started/reused/stopped;
- background service started/stopped;
- Android background policy denied or unavailable;
- auth refresh requested/succeeded/failed while background sync is active;
- iOS resume backfill started/completed.

This feature should be diagnosable without guessing whether a conversation was
untracked, transport failed, background policy stopped it, or the route simply
was not visible.

## UI and Settings Contract

Settings should communicate the platform split honestly:

- the current background-live-sync setting remains user-facing;
- on Android, its subtitle should explain that active sessions may continue in
  the background with a visible system notification;
- on iOS, its subtitle should explain that background continuation is limited by
  the system and active sessions will recover on return.

Session list behavior should improve automatically once repository summaries stay
current; no separate refresh button or polling affordance is required for this
feature.

## Known Limitations

- Android foreground services are still subject to OS and vendor power
  management. Some OEM Android builds, especially heavily customized domestic
  devices, may still kill or throttle a foreground service. The app must recover
  through daemon backfill rather than claiming uninterrupted delivery.
- iOS background behavior is degraded by design. The app can request a short
  cleanup window with `beginBackgroundTask`, but it cannot honestly promise
  continuous LAN WebSocket mirroring while suspended or force-quit.
- If the whole mobile process dies, the first version does not keep a native
  Android WebSocket alive independently. The daemon continues executing and
  mobile catches up on next launch.

## Alternatives Considered

### Alternative 1: Keep Page-Owned Subscriptions And Reopen On Route Return

Rejected because it preserves the existing product gap. It keeps transport tied
to UI visibility and still leaves session lists, approvals, and cache stale
while work continues.

### Alternative 2: Native Android Service Owns A Separate WebSocket Stack

Rejected for the first version because it duplicates auth, cursor, protocol, and
backfill logic that already exists in Dart. It raises maintenance cost and
creates two notification-client implementations before device evidence proves
that is necessary.

### Alternative 3: Cloud Push / Relay

Rejected for this phase because it adds infrastructure, credentials, and
security design that are orthogonal to fixing the current local architecture
problem.

## Testing Plan

### Coordinator Unit Tests

- tracking a conversation starts one watcher;
- adding a second foreground consumer reuses the watcher;
- leaving the conversation route detaches the consumer without stopping sync
  while the app is still foregrounded;
- terminal grace stops the watcher after
  `ConversationSyncPolicy.terminalGrace`;
- route teardown without an explicit "open session list" call still releases
  the foreground lease through ViewModel/page disposal;
- duplicate lease disposal is harmless;
- a slow foreground consumer that exceeds `consumerLagQueueLimit` receives a
  lagged signal and recovers through cache/backfill instead of silent event
  loss;
- disabling background live sync while backgrounded stops Android continuation.

### Repository / Cache Tests

- streamed events kept alive by the coordinator still write into local cache;
- re-entering the conversation after route detachment reads the cached latest
  events immediately;
- mismatched conversation events are still rejected.

### Widget Tests

- opening a running conversation, returning to the session list, then receiving
  new events updates session-list status without reopening the conversation;
- reopening the conversation shows the latest transcript without waiting for a
  cold fetch;
- approval events received off-route still surface through the existing mobile
  approval path.

### Android Tests

- bridge starts the foreground service when policy requires it;
- bridge updates notification content as tracked conversation counts change;
- bridge stops cleanly when no tracked conversations remain.
- foreground-service start denial is reported and falls back to resume backfill;
- token refresh while background sync is active keeps using the existing Dart
  auth path.

### Android Device Tests

- validate foreground-service survival and recovery on at least one stock or
  near-stock Android device/emulator;
- validate on representative domestic OEM devices when available, especially
  Huawei, Xiaomi, OPPO, or Vivo builds with aggressive battery management;
- verify that killing the app/process does not lose daemon-side events and that
  mobile backfills on next launch.

### iOS Tests

- background transition preserves cursor state;
- `beginBackgroundTask` expiration cancels nonessential work and ends the task;
- resume triggers immediate backfill for tracked conversations;
- force-quit recovery derives `lastSeq` from persisted cache and backfills from
  daemon;
- no platform branch falsely reports guaranteed background continuation.

### Verification Commands

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
flutter test --no-pub test\cached_connected_repositories_test.dart -r expanded
flutter test --no-pub test\daemon_notification_client_test.dart -r expanded
flutter test --no-pub test\coding_workbench_controller_test.dart -r expanded
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "workbench"
```

Additional Android bridge tests should follow the existing style used for the
background download bridge.

## Rollout Plan

1. Introduce the coordinator skeleton, policy constants, target model, and lease
   API behind existing behavior.
2. Move foreground watcher ownership from `CodingWorkbenchPage` to the
   coordinator and make foreground route-independent sync functional without any
   Android background-service dependency.
3. Add slow-consumer recovery, trace marks, and cache/cursor durability tests.
4. Add the Android foreground-service bridge and hook it to coordinator
   background policy.
5. Add iOS `beginBackgroundTask` cleanup/resume-backfill handling.
6. Refine settings copy, release-note wording, and platform-specific UX.

This ordering fixes the largest product flaw first: route changes while the app
is still in active use.
