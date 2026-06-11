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

Approval request/resolution events are now published to `MobileAppEventBus`
from the coordinator so off-route events still reach the mobile notification
handler.

## Alternatives

- Keep page-owned subscriptions and reload on route return: rejected because it
  preserves stale cache/session-list behavior while work is still running.
- Use a broadcast stream as the fan-out boundary: rejected because slow UI
  consumers need explicit recovery semantics rather than silent event loss.
- Native Android service owns a separate WebSocket stack in the first slice:
  rejected because this slice fixes foreground route-independent sync without
  duplicating Dart auth, cursor, and backfill logic.

## Evidence

- `mobile/lib/src/workflows/conversation_sync/conversation_sync_coordinator.dart`
  owns watcher lifetime, per-lease fan-out, approval event publication, and
  lifecycle policy.
- `mobile/lib/src/workflows/conversation_sync/conversation_sync_policy.dart`
  owns timing and queue defaults.
- `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` attaches and
  disposes foreground leases while leaving transport lifetime to the
  coordinator.
- Detailed design rationale remains in
  `docs/superpowers/specs/2026-06-11-mobile-conversation-background-sync-design.md`.

## Verification

```powershell
git diff --check
node scripts/check-project-knowledge.js
cd mobile
flutter test --no-pub test\conversation_sync_coordinator_test.dart
flutter test --no-pub test\widget_test.dart --plain-name "foreground route changes keep conversation event sync alive"
dart run tool\check_architecture_imports.dart
```

## Re-evaluate When

- Android foreground-service support moves from design to implementation.
- iOS resume/backfill behavior gains a native background-task bridge.
- Conversation event fan-out needs multiple simultaneous foreground rendering
  owners with different recovery behavior.
