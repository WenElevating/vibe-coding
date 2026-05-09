# Codex CLI Conversation Adapter Design

Date: 2026-05-09
Status: Approved for implementation planning

## Problem

The mobile app should support Codex CLI as a real conversation adapter. The current repository already exposes `codex` in adapter diagnostics and picker surfaces, but the actual conversation path still uses a `notImplementedConversationAdapter('Codex')` placeholder. `/api/runs` support is residual logic and is not part of this work.

The implementation must be based on current Codex CLI behavior, not guesses from the existing generic JSONL adapter. The verified local CLI is `codex-cli 0.130.0` on Windows, installed through npm shims under `C:\Users\wenmm\npm-global`.

## Goals

- Add a real daemon conversation adapter for `codex`.
- Use Codex CLI's non-interactive JSONL interface.
- Preserve the mobile conversation model: create a conversation, send messages, receive normalized events, resume the same CLI thread, and cancel the active turn.
- Keep adapter behavior explicit when Codex cannot provide a Claude-like capability, especially mobile approval callbacks.
- Preserve Windows npm shim detection through the existing `cli-resolver` path.

## Non-Goals

- Do not make `/api/runs` the target workflow.
- Do not build a Codex TUI wrapper.
- Do not depend on experimental `exec-server`, `app-server`, or remote-control modes.
- Do not expose arbitrary user-provided command arguments from mobile.
- Do not pretend Codex supports mobile-driven approval callbacks when the CLI is enforcing policy locally.

## Verified Codex CLI Behavior

The correct daemon entry points are:

```powershell
codex --ask-for-approval never exec --json --sandbox read-only --ephemeral "Reply with exactly OK."
codex --ask-for-approval never exec --json -C D:\AIProject\vibe-coding --sandbox read-only "Reply with exactly FIRST."
codex --ask-for-approval never exec resume --json <thread_id> "Reply with exactly SECOND."
```

The placement of `--ask-for-approval` matters. On the verified CLI, `codex exec --json --ask-for-approval never ...` fails with `unexpected argument '--ask-for-approval'`. The approval option must be passed before the `exec` subcommand.

Successful JSONL output includes:

```jsonl
{"type":"thread.started","thread_id":"019e0a91-d1be-7881-aaec-6a7ed79c5e82"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
{"type":"turn.completed","usage":{"input_tokens":24243,"cached_input_tokens":2432,"output_tokens":26,"reasoning_output_tokens":19}}
```

Tool execution output includes `item.started` and `item.completed` with `item.type = "command_execution"`, `command`, `aggregated_output`, `exit_code`, and `status`.

Policy-blocked commands are surfaced as completed command execution items with `status = "declined"` and output such as `rejected: blocked by policy`. No file was created in the read-only policy test.

Model, auth, and network failures may still be JSONL:

```jsonl
{"type":"error","message":"..."}
{"type":"turn.failed","error":{"message":"..."}}
```

Invalid resume IDs can fail before JSONL streaming and only write stderr, for example `thread/resume failed: no rollout found for thread id ...`.

## Recommended Architecture

Add a dedicated `CodexConversationAdapter` instead of stretching `JsonLineProcessAdapter`.

This adapter starts one Codex process per user message. It is not a long-lived process adapter, but it preserves conversation continuity by storing Codex's `thread_id` as the daemon `cliSessionId` and using `codex exec resume` for later messages.

The adapter should expose capabilities that match this reality:

- `longLivedProcess: false`
- `waitingInput: false`
- `waitingApproval: false`
- `resume: true`
- `partialOutput: true`
- `toolEvents: true`
- `approvalPolicy: "cli-policy"`

`waitingApproval` must stay false because Codex policy decisions are handled inside the CLI run. The mobile client can display declined commands and policy notices, but it cannot approve a pending Codex tool call through the existing Claude-style approval callback.

## Components

### `daemon/src/codex-conversation-adapter.js`

Responsibilities:

- Resolve the `codex` command with `resolveCliInvocation`.
- Detect CLI availability and required capabilities.
- Build first-turn and resume-turn argv with correct global/subcommand option order.
- Spawn Codex in the authorized workspace root.
- Parse JSONL incrementally across chunk boundaries.
- Map Codex events to daemon conversation events.
- Track active child process for cancellation.
- Surface non-JSONL stderr startup failures as adapter failures.

### `daemon/src/main.js`

Replace the current Codex conversation placeholder:

```js
['codex', notImplementedConversationAdapter('Codex')]
```

with:

```js
['codex', new CodexConversationAdapter({ command: codexCommand })]
```

`createConversationAdapters()` should accept `codexCommand` alongside `claudeCommand`.

### Existing Mobile Surface

The mobile adapter picker already treats `codex` as a real selectable adapter. The expected UI change is primarily behavioral: Codex should become selectable when daemon diagnostics mark it available, and the workbench should render normalized Codex events through the existing conversation reducer.

No new mobile page is needed for this design.

## Data Flow

1. Mobile creates a conversation with `adapter: "codex"`.
2. Daemon creates the conversation record with no `cliSessionId`.
3. First mobile message starts:

```text
codex --ask-for-approval <policy> exec --json -C <workspacePath> --sandbox workspace-write <prompt>
```

4. Adapter receives `thread.started` and updates the conversation session id to Codex `thread_id`.
5. Adapter maps `item.*`, `error`, and `turn.*` events into daemon conversation events.
6. Later mobile messages start:

```text
codex --ask-for-approval <policy> exec resume --json <thread_id> <prompt>
```

7. Cancellation kills the active Codex child process. A later message can still resume the stored `thread_id` unless Codex reports that the session no longer exists.

## Permission Mapping

The existing daemon permission modes remain the external contract:

- `default` maps to `--ask-for-approval on-request`.
- `auto` maps to `--ask-for-approval never`.

Sandbox mode should default to `workspace-write` for real conversations, matching the app's purpose as a coding control surface. Tests and diagnostics may use `read-only`.

Do not use `--dangerously-bypass-approvals-and-sandbox`.

## Event Mapping

Codex event mapping should be explicit:

- `thread.started` stores `thread_id` as `cliSessionId` and may emit a system notice with session metadata.
- `turn.started` emits a running/notice event if the conversation manager needs one.
- `item.completed` with `item.type = "agent_message"` maps to assistant text.
- `item.started` with `item.type = "command_execution"` maps to tool started.
- `item.completed` with `item.type = "command_execution"` maps to tool output.
- `command_execution` with `status = "declined"` maps to a policy-blocked notice or tool output marked declined.
- `error` maps to a system notice so retry progress is visible.
- `turn.completed` maps to conversation completion for the active turn.
- `turn.failed` maps to a failed terminal event with the error message.

Unknown JSON events should be preserved as raw payloads and surfaced as low-risk raw output or system notices. They should not crash the adapter unless parsing itself fails in a way that prevents the turn from continuing.

## Error Handling

Capability detection failures should report:

- Codex CLI missing.
- `codex --version` failed.
- `codex exec --help` missing `--json`.
- `codex exec resume --help` unavailable.
- Windows shim could not be resolved.

Runtime failures should distinguish:

- JSONL `turn.failed` from process exit failure.
- Pre-stream stderr failures such as invalid resume id.
- Spawn errors such as missing executable.
- Parse errors in individual stdout lines.

Invalid resume should fail explicitly and tell the user the Codex thread could not be resumed. It should not silently create a new thread, because that would misrepresent conversation continuity.

## Testing

Add daemon regression tests for:

- Codex argv order puts `--ask-for-approval` before `exec`.
- First message starts `codex --ask-for-approval <policy> exec --json -C <workspace> --sandbox workspace-write <prompt>`.
- Resume message starts `codex --ask-for-approval <policy> exec resume --json <thread_id> <prompt>`.
- `thread.started` persists `cliSessionId`.
- `agent_message` becomes assistant text.
- `command_execution` start/completion becomes tool events.
- `command_execution status=declined` becomes a policy-blocked visible event.
- `error` plus `turn.failed` becomes a failed turn.
- Non-JSONL stderr before exit becomes an adapter failure.
- Cancellation kills the active child and emits cancellation.
- Windows npm shim resolution still resolves `@openai/codex\bin\codex.js`.

Add or update mobile reducer/protocol tests only where the current reducer fails to render Codex's normalized events. Avoid broad UI churn.

Verification commands:

```powershell
npm test
npm run lint
cd mobile && flutter test
cd mobile && flutter analyze
```

If Flutter generated Windows plugin files remain dirty before implementation, leave them out of commits unless the implementation actually changes plugin configuration.

## Open Questions

No product-level open questions remain for the first implementation plan. The selected path is CLI behavior research followed by a real Codex conversation adapter. `/api/runs` remains residual and should not drive the integration.
