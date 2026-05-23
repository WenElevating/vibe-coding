# Decision: Workbench Conversation Events Use WebSocket Notifications

- Status: accepted
- Date: 2026-05-23
- Last verified: 2026-05-23

## Context

The workbench previously used foreground REST polling for conversation events.
That made high-frequency CLI output laggy and left recovery behavior split
between page timers and repository fetches.

## Decision

Use daemon WebSocket notifications as the primary foreground event path for
`conversation.events`. The mobile client keeps one socket per daemon session,
multiplexes conversation subscriptions by `topic + scope`, and falls back to
REST backfill when replay is truncated or socket failures repeat.

`DaemonConversationRepository.watchConversationEvents` depends on
`NotificationService`; it should not keep an independent HTTP polling fallback.
REST event fetches remain available for explicit loads and notification-client
backfill, not as a hidden foreground watch loop.

The workbench page cancels the active foreground event subscription after a
short background grace period and restarts it from the current cursor on resume.
Short app lifecycle interruptions that do not reach the grace period keep the
existing subscription.

## Constraints

- The daemon must register live subscriptions before replaying stored events so
  appends during replay are not lost.
- Duplicate subscriptions for the same `topic + scope` replace the previous
  generation.
- Runtime authorization must still be checked before live delivery; do not cache
  authorization without an explicit invalidation signal.
- Mobile UI event application must guard against stale async work after route,
  conversation, or run changes.
- Foreground WebSocket subscription lifecycle belongs to the workbench UI
  owner; repository code should expose the stream boundary but not decide app
  lifecycle policy.

## Evidence

- Daemon notification protocol and hub live under `daemon/src/notification-*`.
- Mobile notification client lives under
  `mobile/lib/src/services/daemon_notification_client.dart`.
- Repository boundary is
  `ConversationRepository.watchConversationEvents`.
- Workbench lifecycle subscription management lives in
  `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`.
- Detailed rationale remains in
  `docs/superpowers/specs/2026-05-23-websocket-notification-gateway-design.md`.

## Verification

```powershell
node scripts/run-tests.js
cd mobile
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\daemon_notification_client_test.dart test\daemon_conversation_repository_test.dart test\coding_workbench_controller_test.dart -r expanded
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "workbench lifecycle restarts event subscription after background"
```

## Re-evaluate When

- More notification topics need different authorization or sequence spaces.
- Conversation permission changes gain explicit invalidation events.
- Foreground event volume requires binary framing or compression.
