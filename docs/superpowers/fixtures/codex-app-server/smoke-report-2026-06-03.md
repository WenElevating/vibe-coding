# Codex App-Server Smoke Report

- Date: 2026-06-03
- Operator: Codex
- vibe-coding commit: 3328742ee7de1dfd4c2bb842778680f8a2d8574a
- Codex source commit: 3389fa554e953d07a12a34f5681aae46f17958f8
- Codex binary: D:\nodejs\codex.cmd
- Codex version: codex-cli 0.136.0
- Transport: stdio
- Workspace: D:\AiProject\vibe-coding

## Commands

```powershell
node scripts\codex-app-server-smoke.js
$env:CODEX_APP_SERVER_SMOKE_SCENARIO='command-approval'; node scripts\codex-app-server-smoke.js; Remove-Item Env:CODEX_APP_SERVER_SMOKE_SCENARIO
$env:CODEX_APP_SERVER_SMOKE_SCENARIO='sequential-turns'; $env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS='180000'; node scripts\codex-app-server-smoke.js; Remove-Item Env:CODEX_APP_SERVER_SMOKE_SCENARIO; Remove-Item Env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS
$env:CODEX_APP_SERVER_SMOKE_SCENARIO='cancellation'; $env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS='120000'; node scripts\codex-app-server-smoke.js; Remove-Item Env:CODEX_APP_SERVER_SMOKE_SCENARIO; Remove-Item Env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS
$env:CODEX_APP_SERVER_SMOKE_SCENARIO='large-output'; $env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS='120000'; node scripts\codex-app-server-smoke.js; Remove-Item Env:CODEX_APP_SERVER_SMOKE_SCENARIO; Remove-Item Env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS
$env:CODEX_APP_SERVER_SMOKE_SCENARIO='project-trust'; $env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS='120000'; node scripts\codex-app-server-smoke.js; Remove-Item Env:CODEX_APP_SERVER_SMOKE_SCENARIO; Remove-Item Env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS
```

The smoke uses the installed Codex CLI and starts `codex app-server` with its
default stdio transport. The upstream source checkout was used for protocol
schema inspection only.

## Gate Results

| Gate | Result | Evidence |
| --- | --- | --- |
| initialize within 10s | pass | `samples/2026-06-03-stdio-basic-turn.json` initialized at 2026-06-03T13:06:14.848Z and received the initialize response before subsequent requests. |
| 10 sequential turns | pass | `samples/2026-06-03-stdio-sequential-turns.json` completed 10 consecutive turns on one stdio app-server child; all 10 `turn/completed` statuses were `completed`. |
| 3 approval round trips | blocked | `samples/2026-06-03-stdio-command-approval.json` completed command execution but did not emit `item/commandExecution/requestApproval`. |
| approval p95 latency under 2s | blocked | No approval request was emitted, so latency cannot be measured. |
| cancellation cleanup deadline | pass | `samples/2026-06-03-stdio-cancellation.json` used `thread/shellCommand` to start a long-running shell turn, sent `turn/interrupt`, received a successful response, and observed `turn/completed` with status `interrupted`; the app-server child exited via SIGTERM during cleanup. |
| large output no pipe block | pass | `samples/2026-06-03-stdio-large-output.json` completed a `thread/shellCommand` command that printed 1200 numbered lines without JSONL parse errors, request timeouts, or pipe deadlock. |
| no orphan processes | pass | `samples/2026-06-03-stdio-cancellation.json` captured 12 Windows descendant processes before cleanup and zero survivors after process-tree cleanup. |
| side-effect-free probe creates no thread | pass | `model/list` and `thread/list` completed before any `thread/start`; no `thread/started` appeared before the explicit `thread/start`. |
| session scope field identified | blocked | No approval request was emitted, so `availableDecisions` was not observed. |
| project trust behavior known | pass | `samples/2026-06-03-stdio-project-trust.json` used isolated `CODEX_HOME`: read-only `thread/start` left config absent, while workspace-write `thread/start` persisted `trust_level = "trusted"` for the temp workspace. |
| user-input request behavior known | pass | The basic and command scenarios completed without `item/tool/requestUserInput`. |

## Captured Samples

- `samples/2026-06-03-stdio-basic-turn.json`
- `samples/2026-06-03-stdio-command-approval.json`
- `samples/2026-06-03-stdio-sequential-turns.json`
- `samples/2026-06-03-stdio-cancellation.json`
- `samples/2026-06-03-stdio-large-output.json`
- `samples/2026-06-03-stdio-project-trust.json`

## Decisions

- Transport selected for Phase 2: stdio-first.
- Capabilities to expose: initialize, model/list probe, thread/start, turn/start, turn/interrupt, streamed non-blocking notifications, turn/completed, and stdio operation across 10 consecutive turns.
- Capabilities to keep adapter-internal only for smoke: `thread/shellCommand`, because official docs state it runs outside the sandbox and should only be exposed for explicit user-initiated commands.
- Capabilities to lower or omit: approval callbacks and session-scoped approval remain unavailable until dedicated smoke gates pass.
- Product mitigation applied in bridge: app-server `thread/start` and `thread/resume` should use read-only sandbox, because elevated `workspace-write` at thread start persists project trust. Elevated workspace write remains a turn-level setting.
- App-server selectable: no. Keep behind feature flag until blocked gates are resolved.

## Follow-up

- Add a dedicated approval trigger that produces `item/commandExecution/requestApproval`, then capture `availableDecisions`.
- Keep regression coverage that app-server bridge does not request workspace-write at thread start.
