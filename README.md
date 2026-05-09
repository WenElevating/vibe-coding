# LAN AI CLI Control

[简体中文](README.zh-CN.md)

LAN AI CLI Control is a local-first control surface for running AI coding CLIs from a phone or another device on the same LAN. The daemon stays on the trusted desktop, executes inside explicitly authorized workspaces, and exposes a narrow HTTP API to the Flutter client.

The project currently supports conversation-oriented control for Claude Code and Codex CLI, plus OpenCode attachment and a development-only synthetic adapter. It is designed for real coding workflows without exposing a raw remote shell or arbitrary mobile-provided command execution.

## What It Does

- Pair a mobile client with the local daemon using token-based auth.
- Register and select trusted workspaces before any CLI execution.
- Start and resume coding conversations for supported CLI adapters.
- Stream assistant text, command/tool activity, outputs, status changes, and diagnostics to the mobile UI.
- Preserve CLI session IDs for resume workflows where the underlying CLI supports them.
- Keep lifecycle and diagnostic events in the event log while hiding low-value internal notices from the main transcript UI.
- Provide redacted diagnostics and health/version endpoints for troubleshooting.

## Safety Boundary

The daemon intentionally rejects unrestricted terminal behavior:

- No arbitrary shell commands from mobile clients.
- No arbitrary `cwd` from mobile clients.
- No mobile-provided raw CLI arguments.
- No persistent PTY session exposed over the API.
- Work only runs inside daemon-authorized workspace paths.
- Dangerous CLI bypass modes must not be exposed through the mobile control surface.

The mobile client is a controller for bounded local coding sessions, not a remote terminal.

## Project Structure

- `daemon/`: Node.js daemon, HTTP API, workspace management, adapter orchestration, persistence, and diagnostics.
- `mobile/`: Flutter client application, UI, models, services, reducers, and mobile tests.
- `scripts/`: Node-based regression and smoke test entry points.
- `docs/`: Design notes, UI references, release notes, and implementation plans.
- `data/`: Local runtime data such as SQLite databases. Do not commit it.
- `.omx/`: Local agent/runtime artifacts. Treat it as generated output.

## Requirements

- Node.js 20 or newer.
- Flutter SDK for mobile/client development.
- At least one supported local AI CLI installed for real conversations:
  - Claude Code
  - Codex CLI
  - OpenCode server, when using attach mode

## Daemon Commands

Run these from the repository root:

```powershell
npm test
npm run lint
npm run start:daemon
```

## Mobile Commands

Run these from `mobile/`:

```powershell
flutter analyze
flutter test
flutter build windows --debug
```

## Adapter Environment

Codex support is explicit-enable:

```powershell
$env:CODEX_ENABLED='1'
$env:CODEX_COMMAND='codex'
npm run start:daemon
```

OpenCode is attach-only in the current scope:

```powershell
$env:OPENCODE_SERVER_URL='http://127.0.0.1:4096'
npm run start:daemon
```

Development-only synthetic adapters can be enabled for local conformance tests:

```powershell
$env:DEV_ADAPTERS='1'
npm run start:daemon
```

## API Scope

The daemon exposes APIs for:

- Pairing, token auth, and device revocation.
- Workspace registration and authorization.
- Adapter capability diagnostics.
- Conversation creation, message sending, event replay, cancellation, input responses, and approval responses when supported.
- Legacy run/task endpoints and command templates.
- Health, version, and redacted diagnostic export.

`/api/runs` remains a bounded task-runner surface. Conversation-oriented CLI control should use `/api/conversations`.

## Testing Notes

Use daemon tests for adapter, protocol, persistence, and security-boundary changes:

```powershell
npm test
```

Use Flutter tests for reducer, model, and UI-state changes:

```powershell
cd mobile
flutter test
```

Keep regression tests close to the bug surface. Adapter and daemon behavior belongs in `scripts/run-tests.js`; mobile event rendering and state behavior belongs under `mobile/test/`.

## Current Release Notes

- V1 established the LAN daemon, pairing/token auth, workspace allowlist, event persistence, and the no-PTY/no-arbitrary-shell boundary.
- V1.1 added adapter diagnostics for Claude, Codex, and OpenCode, shortcut APIs, run filters, device revocation, and diff summaries.
- V1.2 added serialized workspace task queues, adapter profiles, Git status/diff endpoints, and command templates.
- V1.3 added health/version metadata, redacted diagnostics export, a dev-only smoke endpoint, and release-readiness models.
- Current conversation work focuses on Claude/Codex session lifecycle, resume behavior, hidden lifecycle events, and mobile-friendly event rendering.

## Security Notes

Do not commit tokens, pairing secrets, SQLite runtime data, `.omx/`, build outputs, or manual smoke artifacts. Keep CLI execution bounded to authorized workspace paths, and preserve tests around cwd, permissions, stdin handling, event replay, and protocol filtering.
