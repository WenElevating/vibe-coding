# Decision: Active conversation sync is route independent

- Status: accepted; implementation in progress
- Date: 2026-06-12
- Last verified: 2026-06-12

## Context

`CodingWorkbenchPage` used to own the active
`ConversationRepository.watchConversationEvents` subscription. Leaving the
conversation detail route cancelled the watcher even when the app was still in
the foreground and the conversation was still running. The daemon continued to
persist events, but mobile cache, session-list status, and approval notification
inputs stopped advancing until the user reopened the conversation.

## Decision

Active conversation event transport is owned by a workflow-level
`ConversationSyncCoordinator`, not by the conversation detail route. The
coordinator owns one underlying watcher per tracked conversation, keeps tracked
running/waiting conversations synced across foreground route changes, and gives
UI routes disposable `ConversationSyncLease` objects for transcript rendering.

Foreground route changes detach only the UI lease. They must not stop the
underlying watcher while the app remains foregrounded and the conversation is
still tracked. The `coding.keepConversationEventsInBackground` setting now
controls app-background continuation only; it does not control foreground
in-app route changes.

The coordinator uses per-lease single-subscription streams with bounded queues.
If a foreground consumer exceeds `ConversationSyncPolicy.consumerLagQueueLimit`,
the lease emits `ConversationSyncConsumerLagged`; UI recovery reloads through
the existing cache/daemon event-page path and attaches a fresh lease.

The coordinator records best-effort, content-free performance trace marks for
sync lifecycle diagnosis. Trace collection is injected as a callback from the
workbench dependency boundary and must not affect watcher lifetime, event
delivery, cache writes, or approval publication.

Approval request/resolution events are now published to `MobileAppEventBus`
from the coordinator so off-route events still reach the mobile notification
handler.

Android background continuation uses a native foreground-service bridge as a
process and user-visible notification anchor. The Dart coordinator still owns
the daemon notification transport, auth refresh path, event cursor, cache
backfill, and stop policy. If native reports denied, failed, stopped, or emits
an error, the coordinator falls back to the normal background disconnect grace.
The Android service keeps the anchor through terminal grace and exposes a
notification action that stops background live sync.

iOS continuous background sync is not implemented. The accepted product
contract remains degraded resume/backfill rather than promising suspended
WebSocket delivery. On foreground resume after app-background sync was stopped,
the coordinator stops any stale watcher, fetches daemon events after the last
tracked cursor, applies local conversation status projection for those replayed
events, and restarts the watcher from the advanced cursor. Native iOS
`beginBackgroundTask` cleanup is still not implemented because this repository
currently has no `mobile/ios` Runner/AppDelegate target.

## Alternatives

- Keep page-owned subscriptions and reload on route return: rejected because it
  preserves stale cache/session-list behavior while work is still running.
- Use a broadcast stream as the fan-out boundary: rejected because slow UI
  consumers need explicit recovery semantics rather than silent event loss.
- Native Android service owns a separate WebSocket stack in the first slice:
  rejected because this slice fixes foreground route-independent sync without
  duplicating Dart auth, cursor, and backfill logic.
- Android native service owns auth/cursor/cache in the background: rejected
  because the existing Dart repository and notification client already own
  those semantics and the first Android slice only needs a foreground-service
  lifetime anchor.

## Evidence

- `mobile/lib/src/workflows/conversation_sync/conversation_sync_coordinator.dart`
  owns watcher lifetime, per-lease fan-out, approval event publication, and
  lifecycle policy.
- `mobile/lib/src/workflows/conversation_sync/conversation_sync_policy.dart`
  owns timing and queue defaults.
- `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` attaches and
  disposes foreground leases while leaving transport lifetime to the
  coordinator.
- `mobile/lib/src/services/background_conversation_sync_bridge.dart` defines
  the Dart/native background anchor contract.
- `mobile/lib/src/services/method_channel_background_conversation_sync_bridge.dart`
  maps the bridge to Android MethodChannel/EventChannel traffic.
- `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundConversationSyncService.kt`
  owns the Android foreground service and user-visible notification anchor.
- `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundConversationSyncChannels.kt`
  reports native anchor snapshots back to Dart.
- `mobile/test/conversation_sync_coordinator_test.dart` covers foreground
  resume backfill before watcher restart and restart behavior after backfill
  failure, plus content-free coordinator lifecycle trace marks.
- Detailed design rationale remains in
  `docs/superpowers/specs/2026-06-11-mobile-conversation-background-sync-design.md`.

## Verification

```powershell
git diff --check
node scripts/check-project-knowledge.js
cd mobile
flutter test --no-pub test\conversation_sync_coordinator_test.dart
flutter test --no-pub test\background_conversation_sync_bridge_test.dart
flutter test --no-pub test\app_dependencies_test.dart
flutter test --no-pub test\widget_test.dart --plain-name "foreground route changes keep conversation event sync alive"
dart run tool\check_architecture_imports.dart
```

## Re-evaluate When

- Android foreground-service behavior is validated or fails on real OEM devices.
- An iOS target is added and resume/backfill behavior can gain a native
  background-task bridge.
- Product requires native background transport/auth ownership instead of a Dart
  process anchor.
- Conversation event fan-out needs multiple simultaneous foreground rendering
  owners with different recovery behavior.
