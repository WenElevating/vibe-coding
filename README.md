# Flutter LAN AI CLI Control

V1 implements the approved scope from `.omx/plans/prd-flutter-lan-ai-cli-control.md`:

- Windows-oriented desktop daemon control plane.
- Structured Claude Code runs with raw output console fallback.
- HTTP REST + WebSocket protocol shape.
- Pairing/token auth, workspace whitelist, event persistence, approval audit.
- No unrestricted PTY shell control in V1.

This repository currently contains a dependency-light daemon skeleton and Flutter/Dart client/state skeleton so the protocol and security boundaries are testable before UI polish.

## Commands

```powershell
npm test
npm run lint
npm run start:daemon
```

## V1 Terminal Boundary

The daemon intentionally rejects arbitrary shell commands, arbitrary `cwd`, and persistent PTY sessions from mobile clients. Full PTY terminal control is deferred to a later security ADR.

## V1.1 Additions

- `/api/adapters` reports Claude, Codex, and OpenCode availability.
- Codex adapter is explicit-enable (`CODEX_ENABLED=1`) and uses a JSONL process adapter shape.
- OpenCode adapter is attach-only through `OPENCODE_SERVER_URL`; daemon does not manage OpenCode server startup in V1.1.
- `/api/shortcuts` exposes daemon-side shortcut commands.
- `/api/runs` supports `tool`, `workspaceId`, and `status` filters.
- `/api/devices/{deviceId}/revoke` revokes the current device token.
- Diff summaries use the `diff.summary` event type for phone-friendly rendering.
- Android notification handling is represented as privacy-preserving client state; native plugin wiring is a later app-shell task.

### Adapter Environment

```powershell
$env:CODEX_ENABLED='1'
$env:CODEX_COMMAND='codex'
$env:OPENCODE_SERVER_URL='http://127.0.0.1:4096'
npm run start:daemon
```

## V1.2 Task Runner Additions

- V1.2 remains a task runner: no PTY, no remote terminal, no arbitrary shell/cwd/args.
- Adapter profiles expose invocation mode and capabilities for Claude, Codex, OpenCode, and dev-only synthetic adapters.
- Run queue serializes workspace-write runs by workspace and emits queue events.
- Git review endpoints: `/api/workspaces/{workspaceId}/git/status` and `/api/workspaces/{workspaceId}/git/diff`.
- Command templates are available at `/api/command-templates` and can be invoked without exposing raw shell commands.
- Synthetic adapters are enabled only with `DEV_ADAPTERS=1` for local conformance tests.

```powershell
$env:DEV_ADAPTERS='1'
npm run start:daemon
```

## V1.3 Release Readiness

- `/api/health` now returns version, schema, counts, and visible security boundary flags.
- `/api/version` exposes daemon/API/schema compatibility metadata.
- `/api/diagnostics/export` writes a redacted local diagnostic bundle under `.omx/diagnostics`.
- `/api/e2e/smoke` runs a dev-only synthetic smoke test; release mode returns `DEV_API_DISABLED`.
- Mobile models include dashboard, health, version, diagnostic bundle, and smoke test state.
- Release checklist: `docs/release/v1.3-release-checklist.md`.
