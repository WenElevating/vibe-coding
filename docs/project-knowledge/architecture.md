# Architecture

- Status: active seed
- Last verified: 2026-05-22

## System Shape

This repository is a LAN/mobile control surface for AI CLI coding tools.

- `daemon/` owns the Node.js daemon, HTTP API, workspace management, CLI adapter
  orchestration, persistence, and diagnostics.
- `mobile/` owns the Flutter client, UI state projection, repositories, models,
  ViewModels, and tests.
- `docs/superpowers/specs/` owns detailed architecture/design rationale.
- `docs/project-knowledge/` owns concise durable knowledge for future agents.

## Conversation Model

Conversation is the stable product object. CLI process handles are executor
resources. `conversationId` identifies the product conversation; `cliSessionId`
is an adapter resume token and must not drive display identity.

Daemon owns persisted conversation metadata and events. Mobile consumes
conversation summaries and event streams, then projects them into UI state.

Related decisions:

- [Conversation title is daemon-owned metadata](decisions/2026-05-22-stable-conversation-title.md)
- [Workbench transcript is bottom anchored](decisions/2026-05-22-bottom-anchored-transcript.md)

## Mobile Layered Architecture

The Flutter app follows the standard layered shape described in `AGENTS.md` and
`docs/superpowers/specs/2026-05-12-flutter-standard-layered-architecture-design.md`.

- `mobile/lib/src/app/`: composition root and dependency construction.
- `mobile/lib/src/data/`: DTOs, repository implementations, daemon/API-facing
  services.
- `mobile/lib/src/domain/`: repository abstractions, business contracts, pure
  decisions. It must not import Flutter, HTTP clients, `SharedPreferences`, UI,
  or concrete `DaemonClient`.
- `mobile/lib/src/ui/`: presentation, UI state, and widgets. `ui/main/` owns
  the app's main shell, Home surface, and tab orchestration; `ui/features/`
  owns true feature areas.
- Daemon-connected mobile runtime uses one `ui/main/` shell. A missing selected
  workspace is a presentation state inside Home/Coding/Settings, not a separate
  empty application shell.
- `mobile/lib/src/workflows/`: multi-step flows across repositories/services.
- `mobile/lib/src/services/`: infrastructure/platform adapters.
- `mobile/lib/src/testing/`: fakes, fixtures, debug helpers for tests.

## Verification

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
```

This check is necessary but not sufficient. It can pass while large widgets or
services still own the wrong state. Pair it with code inspection of ownership
and reverse dependencies.
