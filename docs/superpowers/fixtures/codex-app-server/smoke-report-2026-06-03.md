# Codex App-Server Smoke Report

- Date: 2026-06-03
- Operator: Codex
- vibe-coding commit: 8c0546ed1e11eff40375e5e0ed077ca2a64e7d4e
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
$env:CODEX_APP_SERVER_SMOKE_SCENARIO='resume-rejoin'; $env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS='120000'; node scripts\codex-app-server-smoke.js; Remove-Item Env:CODEX_APP_SERVER_SMOKE_SCENARIO; Remove-Item Env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS
$env:CODEX_APP_SERVER_SMOKE_SCENARIO='image-input'; $env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS='120000'; node scripts\codex-app-server-smoke.js; Remove-Item Env:CODEX_APP_SERVER_SMOKE_SCENARIO; Remove-Item Env:CODEX_APP_SERVER_SMOKE_TIMEOUT_MS
```

The smoke uses the installed Codex CLI and starts `codex app-server` with its
default stdio transport. The upstream source checkout was used for protocol
schema inspection. The approval scenario also uses an isolated `CODEX_HOME` and
a local mock Responses SSE server patterned after upstream app-server tests, so
approval triggering is deterministic without building Codex or relying on prompt
behavior from a live model.

## Gate Results

| Gate | Result | Evidence |
| --- | --- | --- |
| initialize within 10s | pass | `samples/2026-06-03-stdio-basic-turn.json` initialized at 2026-06-03T13:06:14.848Z and received the initialize response before subsequent requests. |
| 10 sequential turns | pass | `samples/2026-06-03-stdio-sequential-turns.json` completed 10 consecutive turns on one stdio app-server child; all 10 `turn/completed` statuses were `completed`. |
| 3 approval round trips | pass | `samples/2026-06-03-stdio-command-approval.json` captured three `item/commandExecution/requestApproval` requests over stdio; all three received client responses, emitted `serverRequest/resolved`, and ended with `turn/completed` status `completed`. |
| approval p95 latency under 2s | pass | `samples/2026-06-03-stdio-command-approval.json` recorded response latencies `[0, 0, 0]` ms and resolved latencies `[0, 0, 0]` ms. |
| cancellation cleanup deadline | pass | `samples/2026-06-03-stdio-cancellation.json` used `thread/shellCommand` to start a long-running shell turn, sent `turn/interrupt`, received a successful response, and observed `turn/completed` with status `interrupted`; the app-server child exited via SIGTERM during cleanup. |
| large output no pipe block | pass | `samples/2026-06-03-stdio-large-output.json` completed a `thread/shellCommand` command that printed 1200 numbered lines without JSONL parse errors, request timeouts, or pipe deadlock. |
| no orphan processes | pass | `samples/2026-06-03-stdio-cancellation.json` captured 12 Windows descendant processes before cleanup and zero survivors after process-tree cleanup. |
| side-effect-free probe creates no thread | pass | `model/list` and `thread/list` completed before any `thread/start`; no `thread/started` appeared before the explicit `thread/start`. |
| session scope field identified | pass | `samples/2026-06-03-stdio-command-approval.json` confirmed request-level `availableDecisions` as the authoritative field. Observed command decisions were `accept`, `acceptWithExecpolicyAmendment`, and `cancel`; `acceptForSession` was not present, so session scope must remain disabled for command approvals. |
| project trust behavior known | pass | `samples/2026-06-03-stdio-project-trust.json` used isolated `CODEX_HOME`: read-only `thread/start` left config absent, while workspace-write `thread/start` persisted `trust_level = "trusted"` for the temp workspace. |
| user-input request behavior known | pass | The basic and command scenarios completed without `item/tool/requestUserInput`. |
| resume/rejoin with persisted threadId | pass | `samples/2026-06-03-stdio-resume-rejoin.json` created a thread, completed a turn, terminated the app-server process, initialized a fresh stdio app-server process, resumed the same `threadId`, and completed a second turn. |
| native image input | pass | `samples/2026-06-03-stdio-image-input.json` sent a local 1x1 PNG as `localImage`; the mock Responses payload contained `input_image` and the turn completed. |

## Captured Samples

- `samples/2026-06-03-stdio-basic-turn.json`
- `samples/2026-06-03-stdio-command-approval.json`
- `samples/2026-06-03-stdio-sequential-turns.json`
- `samples/2026-06-03-stdio-cancellation.json`
- `samples/2026-06-03-stdio-large-output.json`
- `samples/2026-06-03-stdio-project-trust.json`
- `samples/2026-06-03-stdio-resume-rejoin.json`
- `samples/2026-06-03-stdio-image-input.json`

## Decisions

- Transport selected for Phase 2: stdio-first.
- Capabilities to expose: initialize, model/list probe, thread/start, turn/start, turn/interrupt, streamed non-blocking notifications, turn/completed, and stdio operation across 10 consecutive turns.
- Capabilities to keep adapter-internal only for smoke: `thread/shellCommand`, because official docs state it runs outside the sandbox and should only be exposed for explicit user-initiated commands.
- Capabilities to expose for command approval: approval callbacks, request-level `availableDecisions`, and cancel only when the current request includes `cancel`.
- Capabilities to lower or omit: session-scoped approval remains unavailable for command approvals until a real request includes `acceptForSession` or an equivalent stable request-level marker.
- Product mitigation applied in bridge: app-server `thread/start` and `thread/resume` should use read-only sandbox, because elevated `workspace-write` at thread start persists project trust. Elevated workspace write remains a turn-level setting.
- Approval timeout policy: daemon-side approval TTL fail-closes by resolving the pending app-server request with the safest mapped denial. For observed command approvals with `cancel` but no `decline`, this sends native `cancel`; otherwise deny maps to `decline` when available.
- App-server selectable: still no for default rollout. The production adapter lifecycle, approval timeout/idempotency behavior, fallback boundary, metrics, attachment conversion, and kill-switch wiring now exist in daemon code, but selection still requires explicit feature, experimental API, stdio transport, and rollout-percent gates.
- Real resume/rejoin: app-server `threadId` is viable as the compatibility `cliSessionId` for the tested installed Codex version when paired with structured `providerSession` metadata.
- Native image input: app-server accepts `localImage` turn input; mobile/daemon should keep existing MIME/size validation and reject PDFs before `thread/start`/`turn/start`.
- Permissions approval: current installed Codex did not produce `item/permissions/requestApproval` from the smoke runner's mock provider path, despite matching the upstream test shape closely. Keep permissions approval regression-covered by mapper tests and do not treat it as default-route evidence until a real server request fixture is captured.

## Follow-up

- Keep regression coverage that app-server bridge does not request workspace-write at thread start and does not expose session-scoped command/file approval without request-level `acceptForSession`.
- Capture real file-change and permissions approval fixtures before merging `codex-app-server` into the default `codex` route.
