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
```

The smoke uses the installed Codex CLI and starts `codex app-server` with its
default stdio transport. The upstream source checkout was used for protocol
schema inspection only.

## Gate Results

| Gate | Result | Evidence |
| --- | --- | --- |
| initialize within 10s | pass | `samples/2026-06-03-stdio-basic-turn.json` initialized at 2026-06-03T13:06:14.848Z and received the initialize response before subsequent requests. |
| 10 sequential turns | blocked | Only single-turn stdio smoke was run. |
| 3 approval round trips | blocked | `samples/2026-06-03-stdio-command-approval.json` completed command execution but did not emit `item/commandExecution/requestApproval`. |
| approval p95 latency under 2s | blocked | No approval request was emitted, so latency cannot be measured. |
| cancellation cleanup deadline | blocked | Not yet exercised. |
| large output no pipe block | blocked | Not yet exercised. |
| no orphan processes | blocked | Samples record owned child pids 20216 and 64332 exiting via SIGTERM, but descendant process-tree orphan checks were not measured. |
| side-effect-free probe creates no thread | pass | `model/list` and `thread/list` completed before any `thread/start`; no `thread/started` appeared before the explicit `thread/start`. |
| session scope field identified | blocked | No approval request was emitted, so `availableDecisions` was not observed. |
| project trust behavior known | blocked | `thread/start` succeeded, but project trust side effects were not isolated or proven. |
| user-input request behavior known | pass | The basic and command scenarios completed without `item/tool/requestUserInput`. |

## Captured Samples

- `samples/2026-06-03-stdio-basic-turn.json`
- `samples/2026-06-03-stdio-command-approval.json`

## Decisions

- Transport selected for Phase 2: stdio-first.
- Capabilities to expose: initialize, model/list probe, thread/start, turn/start, streamed non-blocking notifications, turn/completed.
- Capabilities to lower or omit: approval callbacks, session-scoped approval, cancellation, large-output guarantees, and cleanup guarantees remain unavailable until dedicated smoke gates pass.
- App-server selectable: no. Keep behind feature flag until blocked gates are resolved.

## Follow-up

- Add a dedicated approval trigger that produces `item/commandExecution/requestApproval`, then capture `availableDecisions`.
- Add cancellation and large-output stdio tests.
- Add descendant process-tree tracking so no-orphan status is measurable beyond the direct child process.
