# Codex App-Server Replacement Validation

- Date: 2026-06-03
- vibe-coding checkout: `D:\AIProject\vibe-coding`
- Codex source checkout: `D:\GithubProject\codex`
- Codex source commit: `d36a3ead3c896d0552207763ef483262bce9ac73`
- Validation scope: whether Codex `app-server` can replace the current `codex exec --json` conversation adapter feature surface.

## Conclusion

Protocol-level and unit-level validation show that Codex `app-server` can cover the current visible Codex adapter feature surface and adds the missing responsive approval channel.

It is not yet a drop-in production replacement. The remaining work is not the mobile approval protocol itself; it is the app-server lifecycle, transport, authentication/session handling, and a few behavioral differences that must be handled before switching the production adapter.

## Source Evidence

- Current `exec` mode rejects responsive approval and user-input server requests:
  - `D:\GithubProject\codex\codex-rs\exec\src\lib.rs:1647`
  - `D:\GithubProject\codex\codex-rs\exec\src\lib.rs:1653`
  - `D:\GithubProject\codex\codex-rs\exec\src\lib.rs:1659`
  - `D:\GithubProject\codex\codex-rs\exec\src\lib.rs:1665`
  - `D:\GithubProject\codex\codex-rs\exec\src\lib.rs:1677`
- `app-server` defines responsive approval server requests:
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\src\protocol\common.rs:1348`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\src\protocol\common.rs:1355`
- `app-server` defines the lifecycle and item notifications needed for the current mobile event contract:
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\src\protocol\common.rs:1507`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\src\protocol\common.rs:1509`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\src\protocol\common.rs:1512`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\src\protocol\common.rs:1519`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\src\protocol\common.rs:1530`
- TypeScript schema confirms request and item shapes:
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\schema\typescript\v2\ThreadStartParams.ts:12`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\schema\typescript\v2\ThreadResumeParams.ts:26`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\schema\typescript\v2\TurnStartParams.ts:13`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\schema\typescript\v2\UserInput.ts:7`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\schema\typescript\v2\ThreadItem.ts:26`
  - `D:\GithubProject\codex\codex-rs\app-server-protocol\schema\typescript\v2\SandboxPolicy.ts:7`

## Validation Added In This Repo

New helper modules:

- `daemon/src/codex-app-server-approval.js`
  - Maps `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, and `item/permissions/requestApproval` to the mobile `approval.requested` contract.
  - Builds JSON-RPC responses back to Codex app-server.
  - Avoids exposing `rawProviderRequest` or provider decision names to mobile.
- `daemon/src/codex-app-server-bridge.js`
  - Builds `thread/start`, `thread/resume`, `turn/start`, and `turn/interrupt` requests.
  - Maps app-server notifications into the existing `conversationEventTypes` contract currently produced by `mapCodexEvent`.

New regression tests in `scripts/run-tests.js`:

- `Codex app-server approval requests map to mobile contract and JSON-RPC responses`
- `Codex app-server bridge covers current exec adapter launch and event contract`

Verification command:

```powershell
node scripts\run-tests.js
```

Result:

```text
363 tests passed
```

## Current Feature Parity Matrix

| Current Codex adapter behavior | App-server validation | Status |
| --- | --- | --- |
| First turn uses authorized workspace cwd | `thread/start.cwd` and `turn/start.cwd` are built from `workspacePath` | Covered |
| `permissionMode=auto` maps to no approval prompt | `approvalPolicy: "never"` | Covered |
| Default permission mode asks on request | `approvalPolicy: "on-request"` | Covered |
| Workspace-write sandbox | `thread/start.sandbox: "workspace-write"` and `turn/start.sandboxPolicy.type: "workspaceWrite"` | Covered |
| Tool timeout config | `thread/start.config.tool_timeout_sec` and `thread/resume.config.tool_timeout_sec` | Covered |
| Resume by Codex thread id | `thread/resume.threadId` | Covered |
| Selected model propagation | `thread/start.model`, `thread/resume.model`, and `turn/start.model` | Protocol covered, registry migration still needed |
| Text attachment extraction | Reuses current text attachment wrapper and sends it as `UserInput.text` | Covered |
| Native image attachment | Sends native image scratch paths as `UserInput.localImage` | Covered |
| Thread started event stores session id | `thread/started` maps to hidden `codex_thread_started` notice with `sessionId` | Covered |
| Turn started event | `turn/started` maps to hidden `codex_turn_started` notice | Covered |
| Final assistant message | `item/completed` with `agentMessage` maps to `assistant.message` | Covered |
| Command start | `item/started` with `commandExecution` maps to `tool.started` | Covered |
| Command output streaming | `item/commandExecution/outputDelta` maps to `tool.delta` | Covered, app-server is better than current completed-only command output |
| Command completion | `item/completed` with `commandExecution` maps to `tool.completed` | Covered |
| Command declined by policy | `commandExecution.status: "declined"` maps to `codex_policy_blocked` | Covered |
| File changes | `fileChange` item maps to `codex_file_change` | Covered |
| MCP tool calls | `mcpToolCall` item maps to existing visible tool events | Covered |
| Todo/task progress | `turn/plan/updated` maps to current `task.progress.updated` contract | Covered |
| Turn failure | `turn/completed.status: "failed"` maps to `run.error` | Covered |
| User cancellation | `turn/interrupt` request plus `turn/completed.status: "interrupted"` maps to `conversation.cancelled` | Covered at contract level |
| Responsive command/file/permission approval | App-server approval server requests map to mobile approval requests and JSON-RPC responses | Covered |

## Differences And Risks

1. Production lifecycle is not implemented yet.
   - The unit test proves request and event contract feasibility.
   - A real adapter still needs to start or attach to `codex app-server`, initialize the connection, manage request ids, correlate turns, and tear down the process.

2. Transport and authentication are still migration work.
   - Current `exec --json` reads stdout JSONL from a child process.
   - App-server is JSON-RPC over its own transport. The daemon needs explicit connection handling and auth/session policy.

3. Project trust behavior is not identical to `--skip-git-repo-check`.
   - Current `exec` adapter passes `--skip-git-repo-check`.
   - App-server has no equivalent request field in the schema checked here.
   - Codex app-server tests show elevated sandbox thread starts can persist project trust:
     - `D:\GithubProject\codex\codex-rs\app-server\tests\suite\v2\thread_start.rs:803`
     - `D:\GithubProject\codex\codex-rs\app-server\tests\suite\v2\thread_start.rs:941`
   - This must be accepted deliberately or mitigated before production migration.

4. Capability listing still needs production wiring.
   - The current registry detects `exec --json`, `resume --json`, image flags, model flags, and configured models.
   - The bridge validates app-server request/event parity, but it does not yet replace adapter registry capability detection.

5. Stderr/noise behavior changes shape.
   - Current adapter has special handling for stderr after JSONL and trailing stdout noise.
   - App-server should reduce this class of noise, but transport errors need their own `protocol.warning` or `run.error` mapping.

6. Interactive user input is still outside the current Codex adapter surface.
   - `exec` rejects `item/tool/requestUserInput`.
   - App-server defines the request, but this validation focused on current Codex adapter replacement plus approvals.
   - Supporting it would be an additive feature, closer to Claude's question flow.

## Recommendation

Use app-server for Codex only after implementing a real app-server conversation handle behind the same daemon adapter interface and validating it with integration tests.

Recommended next test stages:

1. Pure adapter-handle test with fake app-server transport.
   - `sendUserMessage` sends `thread/start` or `thread/resume`, then `turn/start`.
   - Incoming notifications append the same conversation events as current Codex.
   - `cancel()` sends `turn/interrupt` and reports `conversation.cancelled`.

2. Compatibility test through `ConversationManager`.
   - Create Codex conversation, send rich attachment message, receive thread id, resume second turn.
   - Verify persisted event stream is indistinguishable from current adapter for supported events.

3. Local smoke test against real `codex app-server`.
   - Start daemon adapter against local Codex app-server.
   - Verify auth, initialization, request id routing, turn lifecycle, approval response, cancellation, and process cleanup.

4. Capability registry migration.
   - Replace `exec --help` parsing with app-server or config-backed capability discovery where possible.
   - Keep model/catalog and attachment capability hashes stable for mobile compatibility.
