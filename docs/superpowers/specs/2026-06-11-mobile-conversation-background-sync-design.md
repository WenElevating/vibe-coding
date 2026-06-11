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

Useful official references:

- Foreground services:
  `https://developer.android.com/develop/background-work/services/fgs`
- Long-running workers:
  `https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/long-running`

### iOS

iOS should not be designed around an assumption that an arbitrary WebSocket can
remain alive indefinitely in the background. Background execution is selective,
time-bounded, and purpose-specific. Background Tasks and background URLSession
fit refresh and transfer workflows; they are not a promise of continuous socket
delivery for an arbitrary LAN session.

Useful official references:

- Background task strategies:
  `https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app`

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
  which conversation is foreground-active.
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

### Core Model: Tracked Conversations

The coordinator tracks only conversations that still matter for continuity:

- `running`
- `waiting_input`
- `waiting_approval`
- a short post-terminal grace period for late final events

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

### Core Rule: One Underlying Watcher Per Tracked Conversation

The coordinator owns the single underlying
`ConversationRepository.watchConversationEvents(conversationId, afterSeq)`
subscription for a tracked conversation.

The conversation page no longer opens its own transport watcher directly.
Instead:

1. The page loads the initial event page from the repository/cache.
2. The page registers itself as a foreground consumer of that conversation with
   the coordinator.
3. The coordinator starts or reuses the single watcher for that conversation.
4. The coordinator fans streamed events out to any current foreground listeners
   and keeps the repository stream alive when policy says the conversation
   should stay synced.

This prevents duplicate transport watchers for the same conversation while still
allowing the current route to update live.

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

### Android Background Design

#### Accepted Direction

Use a foreground service as the Android background continuation anchor.

The Flutter sync coordinator continues to own the notification client and event
policy. The foreground service exists to keep the process user-visible and less
likely to be reclaimed while tracked conversations remain active.

This first design intentionally avoids building a parallel native Kotlin
WebSocket stack. That would duplicate notification protocol logic, auth refresh,
cursor semantics, and backfill behavior that already exist in Dart.

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

### iOS Degraded-Resume Design

The iOS path should be intentionally conservative.

Accepted behavior:

- on background, flush the latest known cursor and cache state immediately;
- request short background execution time only for finishing in-flight local
  cleanup or last backfill writes, not for promising indefinite socket uptime;
- on resume, immediately backfill every tracked conversation from its stored
  `lastSeq`, then restore the realtime watcher;
- keep approval/system state consistent through replayed conversation events
  rather than relying on persistent background sockets.

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

### Observability

Add explicit sync trace marks for:

- target tracked;
- target untracked;
- foreground consumer attached/detached;
- watcher started/reused/stopped;
- background service started/stopped;
- Android background policy denied or unavailable;
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
- terminal grace stops the watcher after the deadline;
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

### iOS Tests

- background transition preserves cursor state;
- resume triggers immediate backfill for tracked conversations;
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

1. Introduce the coordinator and move watcher ownership out of
   `CodingWorkbenchPage`.
2. Keep foreground route-independent sync working with no Android background
   service dependency.
3. Add the Android foreground-service bridge and hook it to coordinator policy.
4. Refine settings copy and lifecycle behavior for Android versus iOS.
5. Add trace coverage and regression tests.

This ordering fixes the largest product flaw first: route changes while the app
is still in active use.
