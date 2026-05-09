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
- Do not run real `codex exec` smoke tests from background diagnostics. Real exec calls may consume quota, require login/network access, and create session history, so they should only happen when the user starts a Codex conversation or explicitly requests a smoke test.

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

The verified `codex-cli 0.130.0` does not accept `--cd` or `-C` after `codex exec resume`. Both forms fail during argument parsing:

```powershell
codex --ask-for-approval never exec resume --json --cd D:\AIProject\vibe-coding <thread_id> "Reply OK"
codex --ask-for-approval never exec resume --json -C D:\AIProject\vibe-coding <thread_id> "Reply OK"
```

The implementation should still detect this capability from `codex exec resume --help`. If a future installed Codex version supports `--cd` or `-C` for resume, pass the authorized workspace explicitly. If not, rely on fixed process `cwd` plus the stored thread id.

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
- Track active process trees for cancellation.
- Surface non-JSONL stderr startup failures as adapter failures.
- Enforce output and JSONL line limits before forwarding payloads to mobile clients.

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
spawn cwd = authorizedWorkspaceRoot
codex --ask-for-approval <policy> exec --json -C <workspacePath> --sandbox workspace-write <prompt>
```

4. Adapter receives `thread.started` and updates the conversation session id to Codex `thread_id`.
5. Adapter maps `item.*`, `error`, and `turn.*` events into daemon conversation events.
6. Later mobile messages start:

```text
spawn cwd = authorizedWorkspaceRoot
codex --ask-for-approval <policy> exec resume --json <thread_id> <prompt>
```

If the installed Codex version supports `--cd` or `-C` on `exec resume`, the resume argv should also pass the authorized workspace explicitly. The verified local version does not support that flag placement, so the required baseline is fixed process cwd.

7. Cancellation kills the active Codex process tree. A later message can still resume the stored `thread_id` unless Codex reports that the session no longer exists.

The adapter must never accept a workspace path directly from mobile. `workspacePath` must come from the daemon's authorized workspace registry, and the child process `cwd` must be set to that authorized root for both first-turn and resume-turn execution. This protects Windows service launches, daemon launches from unrelated directories, and multi-workspace concurrency from cwd drift.

## Permission Mapping

The existing daemon permission modes remain the external contract:

- `default` maps to `--ask-for-approval on-request`.
- `auto` maps to `--ask-for-approval never`.

Sandbox mode should default to `workspace-write` for real conversations, matching the app's purpose as a coding control surface. Tests and diagnostics may use `read-only`.

Do not use `--dangerously-bypass-approvals-and-sandbox`.

The adapter capability payload should make Codex approval semantics explicit:

```json
{
  "approvalPolicy": "cli-policy",
  "mobileApprovalCallbacks": false
}
```

Mobile should render declined commands as local policy blocks, not as pending approvals. Suggested user-facing text: `Codex CLI blocked this command under the current local policy.`

## Security Boundaries

- `workspacePath` must come from the daemon's authorized workspace registry.
- Mobile must not pass arbitrary Codex argv.
- The adapter must never use `--dangerously-bypass-approvals-and-sandbox`.
- Prompts must be passed as individual argv entries, not composed into shell strings.
- stdout, stderr, command text, and tool output should be stripped of unsafe ANSI control sequences or safely escaped before display.
- JSONL lines and tool output must have size limits before they are persisted or sent to mobile clients.

## Event Mapping

Codex event mapping should be explicit. Internally, map raw Codex JSON into a narrow normalized envelope before translating to daemon conversation events:

```js
{
  type: 'assistant_text' | 'tool_started' | 'tool_completed' | 'system_notice' | 'turn_completed' | 'turn_failed',
  adapter: 'codex',
  raw: originalJson,
  timestamp
}
```

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

The parser should be wide on input and strict on output. Raw Codex events may evolve, but daemon-facing events should remain small, typed, and bounded.

Recommended limits:

- `maxJsonLineBytes`: reject or truncate an individual JSONL line before parsing or persisting oversized data.
- `maxAggregatedOutputBytes`: truncate large `command_execution.aggregated_output` values and mark the event as truncated.

Large tool output should be folded, truncated, or later moved to an attachment or paging model before mobile rendering. The first implementation can truncate with a clear `truncated: true` marker.

## Error Handling

Capability detection should be layered:

| Layer | Detection | Failure handling |
| --- | --- | --- |
| Base | `resolveCliInvocation` finds `codex` | diagnostics unavailable |
| Version | `codex --version` succeeds and records version | diagnostics unavailable or warning with reason |
| Static capability | `codex exec --help` and `codex exec resume --help` expose required flags/subcommands | diagnostics unavailable with reason |
| Runtime capability | first real conversation call handles auth, network, provider, model, and account errors | conversation error; do not downgrade or silently create a new thread |

Background diagnostics must stop at static capability checks unless the user explicitly triggers a live smoke test.

Static capability detection failures should report:

- Codex CLI missing.
- `codex --version` failed.
- `codex exec --help` missing `--json`.
- `codex exec resume --help` unavailable.
- Windows shim could not be resolved.
- Resume workspace override support unavailable, when `exec resume --help` does not expose `--cd` or `-C`. This is not fatal if fixed spawn cwd is used.

Runtime failures should distinguish:

- JSONL `turn.failed` from process exit failure.
- Pre-stream stderr failures such as invalid resume id.
- Spawn errors such as missing executable.
- Parse errors in individual stdout lines.

Invalid resume should fail explicitly and tell the user the Codex thread could not be resumed. It should not silently create a new thread, because that would misrepresent conversation continuity.

If `thread.started` has already provided a `thread_id` and the same turn later fails, the adapter should preserve `cliSessionId` while marking the current turn failed. A later resume attempt may still be valid; the adapter should let Codex decide and surface an explicit resume failure if the thread cannot continue.

stderr handling must distinguish mixed streams from startup failure. If stdout has already produced valid JSONL events, stderr warnings should be surfaced as notices or raw stderr, not treated as pre-stream startup failure. Only the "no valid JSONL and non-zero exit/stderr failure" path should become a pre-stream adapter failure.

## Cancellation

Cancellation must terminate the active process tree, not just the immediate child pid. Codex may run through a Windows npm shim, a Node wrapper, the Codex binary, and nested shell/tool processes. Killing only the parent can leave descendant commands running.

On Windows, the implementation may use a small process-tree kill abstraction backed by `taskkill /PID <pid> /T /F`. Other platforms should use an equivalent process group or tree-kill strategy. Cancellation should clear active turn state and emit a cancelled terminal event. A non-zero exit caused by cancellation must not be reported as an ordinary turn failure.

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
- Resume workspace stability: when the daemon starts from a non-workspace cwd, resume still executes with `cwd` fixed to the authorized workspace root.
- Process-tree cancellation: cancellation terminates the Codex process and descendant tool processes.
- Large output truncation: oversized `aggregated_output` becomes a bounded, renderable event with `truncated: true`.
- Unknown JSON event preservation: unknown Codex events surface as raw/system notices without failing the turn.
- `thread.started` followed by `turn.failed`: `cliSessionId` is preserved, while the current turn is marked failed.
- Mixed stderr plus partial JSONL: stderr warnings do not become startup failures after valid JSONL has started.
- Cancellation emits cancellation and does not misclassify cancellation exit as a normal failure.
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
