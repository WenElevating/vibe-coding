# Claude Conversation Tool Result Design

Date: 2026-05-04
Status: Draft for user review
Scope: Claude long-lived conversation adapter, normalized conversation events, mobile command rendering

## 1. Problem

Claude command execution results are still missing in the long-lived conversation flow.

`docs/claude-code-tool-result-guide.md` explains that the reliable source for raw command output is the stream-json tool event path:

```text
tool_use → tool_use_delta → tool_result → assistant → result
```

The current conversation flow does not preserve enough `tool_result` structure. It can lose or fail to correlate:

- raw command output
- `tool_use_id`
- `exit_code`
- `is_error`
- the relationship between the command start card and final command output

This makes the mobile command card show an approval or command shell without the actual command result.

## 2. Goals

- Fix only the conversation long-lived Claude path.
- Use `tool_use_id` as the primary correlation key.
- Preserve raw command output from `tool_result.content`.
- Preserve `exit_code` and `is_error` for success/failure rendering.
- Keep command output visible in the mobile transcript.
- Avoid introducing a new persistence model or database schema.

## 3. Non-Goals

- Do not change one-shot `/api/runs` behavior in this spec.
- Do not add JSON schema output mode.
- Do not redesign the mobile command card visually beyond showing the missing result.
- Do not add a durable tool execution table.

## 4. Chosen Approach

Use in-memory tool correlation inside `ClaudeConversationAdapter` and normalized event updates through the existing conversation event stream.

The adapter records each `tool_use` by `tool_use_id`. When the matching `tool_result` arrives, it emits a `tool.output` event carrying the command output and then a `tool.completed` event carrying completion metadata. The mobile reducer uses `toolUseId` to update the same command card.

This approach is smaller than a new persisted tool execution model, but preserves the important data described by the guide.

## 5. Adapter Design

`ClaudeConversationAdapter` should maintain:

```js
pendingTools: Map<toolUseId, {
  toolUseId: string,
  name: string,
  input: object,
  startedAt: string
}>
```

Event mapping rules:

- `stream_event` wrappers must be unwrapped as the first step of the event parsing pipeline, before any event-specific mapping runs. This is not tool-specific logic; assistant, result, system, and tool frames all use the same unwrap step.
- `tool_use` creates or updates the pending tool entry and emits `tool.started`.
- Repeated `tool_use` frames for the same `toolUseId` should merge into the existing pending tool. The latest complete frame wins, and `input` should reflect the final version seen for that `toolUseId`.
- `tool_use_delta` emits `tool.delta` so the command card can show live output before the final result.
- `tool_result` extracts:
  - `toolUseId` from `tool_use_id`
  - `text` from `content`
  - `exitCode` from `exit_code`, or `null` if absent
  - `isError` from `is_error === true`
- After `tool.output`, emit `tool.completed` with `toolUseId`, `exitCode`, `isError`, and duration when known.
- If `tool_result` arrives without a known pending tool, still emit output using the supplied `tool_use_id` so the UI can render the result.
- A missing pending tool is expected during resume or adapter restart scenarios. This fallback is a degraded but valid path, not a crash condition. Duration and original input may be unknown in this case.

## 6. Conversation Event Semantics

Normalized event payloads must keep these fields:

```ts
interface ToolStartedEvent {
  type: 'tool.started';
  toolUseId: string;
  toolName: string;
  input: Record<string, unknown>;
  summary: string;
}

interface ToolOutputEvent {
  type: 'tool.output';
  toolUseId: string;
  text: string;
  exitCode: number | null;
  isError: boolean;
}

interface ToolDeltaEvent {
  type: 'tool.delta';
  toolUseId: string;
  text: string;
}

interface ToolCompletedEvent {
  type: 'tool.completed';
  toolUseId: string;
  exitCode: number | null;
  isError: boolean;
  durationMs?: number;
}
```

`ConversationManager` should pass these fields through without collapsing them into raw-only payloads.

## 7. Mobile Design

The mobile reducer should update command cards by `toolUseId`.

Rules:

- `tool.started` creates a `command` message with command text from `input.command` when available.
- `tool.delta` appends live output to the command message identified by `toolUseId`.
- `tool.output` appends output to the matching command message.
- `tool.completed` marks the matching command message complete and stores failure state via `isError` / `exitCode`.
- If `toolUseId` is missing, mobile must not guess. It should ignore the event for command-card mutation and rely on daemon-side protocol warnings or diagnostics to expose the upstream bug.
- Approval cards and command cards must remain separate. Approval resolution may create a command shell, but actual stdout/stderr comes from `tool.output`.
- Approval and command events can share the same `toolUseId`. After `approval.resolved`, later `tool.started` / `tool.delta` / `tool.output` / `tool.completed` for that `toolUseId` must render as a command card, not mutate the approval card.

## 8. Testing Strategy

Daemon tests should simulate:

```text
tool_use(Bash npm test) → tool_result(tool_use_id, content, exit_code: 1, is_error: true)
```

Assertions:

- `tool.started` contains `toolUseId`, tool name, and input command.
- wrapped `stream_event` tool frames are unwrapped and mapped exactly like bare frames.
- repeated `tool_use` frames for the same id update the pending input to the latest complete version.
- `tool.delta` carries live output for the same `toolUseId`.
- `tool.output` contains full command output.
- `tool.output` contains `exitCode` and `isError`.
- `tool.completed` is emitted for the same `toolUseId`.
- resume-style orphan `tool_result` emits output/completed without throwing, even when no pending tool is known.
- interleaved results for multiple tools do not overwrite each other:
  - `tool_use(A, Bash)`
  - `tool_use(B, Read)`
  - `tool_result(B, ...)`
  - `tool_result(A, ...)`

Mobile tests should assert:

- `tool.delta` appends live output to the matching command card.
- reducer appends `tool.output` to the command card with the same `toolUseId`.
- command card remains distinct from approval cards.
- approval and command cards sharing a `toolUseId` do not overwrite each other.
- missing `toolUseId` does not attach output to an arbitrary newest command.
- failed command metadata is preserved for rendering.

## 9. Acceptance Criteria

- A Claude conversation command result appears in the mobile command card.
- Multiple tool calls in the same turn do not overwrite each other.
- Exit code and error state survive daemon normalization.
- Existing daemon tests still pass.
