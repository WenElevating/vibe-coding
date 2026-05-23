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

## Constraints

- The daemon must register live subscriptions before replaying stored events so
  appends during replay are not lost.
- Duplicate subscriptions for the same `topic + scope` replace the previous
  generation.
- Runtime authorization must still be checked before live delivery; do not cache
  authorization without an explicit invalidation signal.
- Mobile UI event application must guard against stale async work after route,
  conversation, or run changes.

## Evidence

- Daemon notification protocol and hub live under `daemon/src/notification-*`.
- Mobile notification client lives under
  `mobile/lib/src/services/daemon_notification_client.dart`.
- Repository boundary is
  `ConversationRepository.watchConversationEvents`.
- Detailed rationale remains in
  `docs/superpowers/specs/2026-05-23-websocket-notification-gateway-design.md`.

## Verification

```powershell
node scripts/run-tests.js
cd mobile
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\daemon_notification_client_test.dart test\coding_workbench_controller_test.dart -r expanded
```

## Re-evaluate When

- More notification topics need different authorization or sequence spaces.
- Conversation permission changes gain explicit invalidation events.
- Foreground event volume requires binary framing or compression.
