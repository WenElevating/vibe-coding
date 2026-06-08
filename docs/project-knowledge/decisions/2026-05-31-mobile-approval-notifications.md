# Decision: Approval system notifications are mobile-side event handling

- Status: accepted; implemented
- Date: 2026-05-31
- Last verified: 2026-05-31

## Context

The mobile workbench already receives live `approval.requested` conversation
events and renders approval cards. The notification requirement is to surface
those already-received approvals in Android system notifications when the app is
not in the foreground, without adding daemon-side approval topics or workspace
notification aggregation.

## Decision

Approval notifications are handled inside the mobile app. `CodingWorkbenchPage`
publishes approval lifecycle events to the app-wide `MobileAppEventBus` only
from the live conversation event stream. `ApprovalNotificationHandler` observes
app lifecycle state and shows local Android notifications only when the app is
not resumed. If an approval was first received while the app was resumed and is
still pending when the app later moves to a non-resumed lifecycle state, the
handler emits the local notification once for that pending approval.

The daemon protocol, `conversation.events`, and approval response APIs are
unchanged.

Mobile defaults to cancelling the open conversation event subscription after the
existing 30-second background grace period. Users can opt into keeping the
current open conversation live in the background through
`coding.keepConversationEventsInBackground`; the setting is persisted in
`CodingPreferencesRepository` and read directly by `CodingWorkbenchPage` through
`WorkbenchDependencies`.

## Alternatives

- Daemon workspace-level approval topic: rejected because approval events are
  already received by the mobile workbench and workspace aggregation broadens
  the protocol unnecessarily.
- Mobile subscribing to every conversation: rejected because it duplicates the
  existing live workbench event path and creates subscription fan-out.

## Evidence

- `mobile/lib/src/services/mobile_app_event_bus.dart` owns the app-wide mobile
  event bus.
- `mobile/lib/src/services/approval_notification_handler.dart` owns foreground
  suppression, approval id dedupe, notification ids, and tap forwarding.
- `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` publishes
  approval events only after live stream events are applied.
- `mobile/lib/src/data/repositories/coding_preferences_repository.dart` owns the
  background live-session preference used by the workbench lifecycle policy.

## Verification

```powershell
cd mobile
dart analyze lib test
dart run tool\check_architecture_imports.dart
flutter test --no-pub
```

## Re-evaluate When

- Notifications must arrive for conversations that the mobile app has not
  already subscribed to.
- The app must notify after it has been killed or after the OS suspends its
  daemon connection.
