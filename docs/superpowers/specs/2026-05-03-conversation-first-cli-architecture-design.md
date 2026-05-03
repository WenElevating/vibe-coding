# Conversation First CLI Architecture Design

Date: 2026-05-03
Status: Draft for user review
Scope: Mobile coding workbench architecture, daemon conversation lifecycle, normalized event protocol, Claude long-lived adapter

## 1. Problem

The current mobile coding workbench is built around `run` objects. That worked for early smoke tests, but it now overloads one concept with several responsibilities:

- user-facing conversation
- one CLI process invocation
- one prompt/turn
- event stream
- approval lifecycle
- Claude session/resume identity

This causes repeated issues:

- A UI "new conversation" can still be affected by old run/session/event assumptions.
- The frontend must infer meaning from raw Claude JSON and can misclassify events.
- `AskUserQuestion`, approval requests, partial output, and final output compete in the same message merge path.
- Multiple approval cards or temporary question cards can appear when the CLI is really in a single blocking state.
- The current model is closer to short one-shot CLI execution than Claude Agent SDK's streaming interaction model.

The target architecture must model a coding conversation as a first-class daemon object and let the daemon own CLI lifecycle and control protocol handling.

## 2. Goals

- Make every new coding conversation isolated from previous daemon/CLI conversation state.
- Support a long-lived CLI process per active conversation when possible.
- Support blocking states for both user questions and permission approvals without killing the CLI process.
- Normalize CLI events before the frontend sees them.
- Stop exposing raw protocol objects in the normal mobile transcript.
- Keep the first implementation focused on Claude, while defining cross-adapter capabilities for Codex/OpenCode.
- Keep existing `/api/runs` behavior available as a compatibility layer during migration.
- Keep transport as polling in phase 1, while leaving room for SSE/WebSocket later.

## 3. Non-Goals

- Do not redesign the visual UI in this phase.
- Do not split all Flutter UI components out of `main.dart` in this phase.
- Do not require Codex/OpenCode to implement long-lived `waiting_input` and `waiting_approval` in phase 1.
- Do not add real file-writing or permission-heavy Claude e2e tests as mandatory CI gates in phase 1.
- Do not isolate project files from Claude. New conversations isolate daemon/CLI session state, but still share the selected workspace context.

## 4. Chosen Approach

Use a **Conversation First** architecture.

Add a new daemon-side `ConversationManager` and `/api/conversations` API. A frontend coding conversation maps to one daemon `ConversationSession`. The existing `RunManager` and `/api/runs` remain for compatibility, but the mobile coding workbench migrates to conversations.

This design was chosen over extending `/api/runs` because `run` is already conceptually overloaded. A first-class conversation model gives clear boundaries for:

- long-lived CLI process ownership
- idle TTL
- captured CLI session id
- current blocking item
- normalized event stream
- frontend conversation list

## 5. Conversation Model

A daemon conversation owns the CLI lifecycle and the normalized event stream.

```ts
interface ConversationSession {
  id: string;
  deviceId: string;
  workspaceId: string;
  adapterId: 'claude' | 'codex' | 'opencode';
  status: ConversationStatus;
  cliProcess?: ChildProcess;
  cliSessionId?: string;
  activeTurnId?: string;
  blockingItem?: BlockingItem;
  idleExpiresAt?: string;
  createdAt: string;
  updatedAt: string;
}
```

Statuses:

```text
idle
running
waiting_input
waiting_approval
completed
failed
cancelled
expired
```

Rules:

- Creating a conversation never receives or reuses an old `cliSessionId`.
- First user message starts a new CLI process.
- While `running`, the adapter may emit a blocking input or approval request.
- While `waiting_input` or `waiting_approval`, the CLI process stays alive.
- The conversation has at most one blocking item at a time.
- Answering a question or responding to an approval returns the conversation to `running`.
- When the CLI completes a turn, the conversation enters `idle` and holds the process for an idle TTL.
- Idle TTL is configurable and defaults to 10 minutes.
- If idle TTL expires, daemon disposes the process but keeps the captured `cliSessionId` for the same conversation.
- If the same conversation continues after TTL or process exit, daemon resumes using that conversation's own `cliSessionId`.
- A new conversation never resumes a previous conversation's `cliSessionId`.

## 6. Blocking Items

Only one blocking item is allowed per conversation.

```ts
type BlockingItem = InputRequest | ApprovalRequest;

interface InputRequest {
  type: 'input_request';
  questionId: string;
  text: string;
  suggestions: string[];
  adapterRequestId?: string;
  createdAt: string;
}

interface ApprovalRequest {
  type: 'approval_request';
  approvalId: string;
  toolUseId?: string;
  toolName: string;
  input: Record<string, unknown>;
  summary: string;
  risk: 'low' | 'medium' | 'high' | 'unknown';
  adapterRequestId?: string;
  createdAt: string;
}
```

If a second blocking request arrives while one is active, daemon should not expose a second UI card. Phase 1 should record a protocol warning or adapter error and keep the first blocking item authoritative.

## 7. Normalized Event Protocol

The frontend consumes normalized events only. Raw provider JSON remains available for diagnostics, not normal transcript rendering.

Event types:

```text
conversation.started
conversation.status_changed
user.message
assistant.partial
assistant.message
assistant.question
approval.requested
approval.resolved
tool.started
tool.output
tool.completed
diff.summary
run.error
conversation.completed
conversation.cancelled
```

Semantics:

### `assistant.partial`

- Optional streaming text.
- Render only when the user enables streaming output.
- Does not become durable transcript history.

### `assistant.message`

- Complete assistant message in Markdown.
- Replaces any partial text for the same turn.
- Frontend should not parse raw Claude `result`, `message.content`, or `delta` fields.

### `assistant.question`

- A blocking user input request.
- Moves conversation to `waiting_input`.
- Includes `questionId`, text, suggestions, and required flag.

Example:

```json
{
  "type": "assistant.question",
  "questionId": "question_123",
  "text": "你希望这个 Python 脚本偏向哪个方向？",
  "suggestions": ["系统自动化工具", "异步并发脚本"],
  "required": true
}
```

### `approval.requested`

- A true tool permission request.
- Moves conversation to `waiting_approval`.
- Only real tools such as Bash/Read/Write/Edit should produce this.
- `AskUserQuestion` must not be displayed as permission approval.

Example:

```json
{
  "type": "approval.requested",
  "approvalId": "approval_123",
  "toolUseId": "toolu_123",
  "toolName": "Bash",
  "summary": "Check existing scripts directory",
  "risk": "medium",
  "input": { "command": "dir scripts" }
}
```

### Tool Events

Tool events correlate by `toolUseId`. Approval cards and tool cards must not duplicate each other. A tool card should evolve from started to completed when possible.

## 8. Claude Long-Lived Adapter

Phase 1 implements the full conversation adapter for Claude.

Suggested shape:

```ts
interface ConversationAdapter {
  startConversation(input: StartConversationInput): Promise<AdapterConversationHandle>;
}

interface AdapterConversationHandle {
  sendUserMessage(text: string): Promise<void>;
  answerQuestion(questionId: string, text: string): Promise<void>;
  respondApproval(approvalId: string, decision: 'allow' | 'deny'): Promise<void>;
  interrupt(): Promise<void>;
  cancel(): Promise<void>;
  dispose(): Promise<void>;
}
```

Claude should run in streaming input mode with stdin left open. This aligns with the official Claude Agent SDK model, where permission callbacks require streaming mode and control requests are answered through the control protocol.

The process should use Claude Code stream-json mode with permission prompt tooling enabled for default permission mode. The adapter owns provider-specific raw JSON parsing and emits normalized events to `ConversationManager`.

### AskUserQuestion Handling

`AskUserQuestion` is not a permission approval.

When Claude emits a question-like control request:

1. Adapter emits `assistant.question`.
2. Conversation moves to `waiting_input`.
3. Adapter stores the provider request id internally.
4. Frontend sends the user's answer via `answerQuestion(questionId, text)`.
5. Adapter writes the answer as a new `user` message to the same stdin stream.
6. If Claude requires a control response to unblock the protocol, adapter sends the minimal provider-specific acknowledgement, but the user's natural-language answer remains a user message rather than `updatedInput`.
7. Conversation returns to `running`.

This preserves user freedom: the user may answer in an unexpected way, ask a different question, or change direction.

### Permission Handling

For true tool permission requests:

1. Adapter emits `approval.requested`.
2. Conversation moves to `waiting_approval`.
3. Frontend responds through `respondApproval`.
4. Adapter writes a provider-specific control response with allow/deny.
5. Conversation returns to `running`.

## 9. Adapter Capability Model

Claude implements full phase-1 capabilities.

Codex and OpenCode should declare capabilities instead of pretending to support all states.

Example:

```json
{
  "adapter": "claude",
  "capabilities": {
    "longLivedProcess": true,
    "waitingInput": true,
    "waitingApproval": true,
    "resume": true,
    "partialOutput": true
  }
}
```

Adapters without `waitingInput` or `waitingApproval` may downgrade by completing the current turn and requiring a follow-up message, but the protocol should make the downgrade explicit.

## 10. Conversation API

New endpoints:

```text
POST   /api/conversations
GET    /api/conversations
GET    /api/conversations/:id
POST   /api/conversations/:id/messages
POST   /api/conversations/:id/input-response
POST   /api/conversations/:id/approvals/:approvalId/respond
POST   /api/conversations/:id/cancel
GET    /api/conversations/:id/events?afterSeq=123
```

### Create Conversation

```http
POST /api/conversations
Content-Type: application/json

{
  "workspaceId": "default",
  "adapter": "claude",
  "permissionMode": "default"
}
```

Returns an idle conversation with capabilities.

### Send Message

```http
POST /api/conversations/:id/messages
Content-Type: application/json

{ "text": "写一个 Python 高级脚本" }
```

Allowed in `idle`, `completed`, and active non-blocking continuation states. Rejected with 409 in `waiting_input` or `waiting_approval`.

### Answer Question

```http
POST /api/conversations/:id/input-response
Content-Type: application/json

{
  "questionId": "question_123",
  "text": "做一个技术社区热点聚合器"
}
```

Allowed only in `waiting_input` with matching `questionId`.

### Respond Approval

```http
POST /api/conversations/:id/approvals/:approvalId/respond
Content-Type: application/json

{ "decision": "allow" }
```

Allowed only in `waiting_approval` with matching `approvalId`.

### Event Polling

```http
GET /api/conversations/:id/events?afterSeq=0
```

Returns ordered normalized events. Phase 1 keeps polling; the event schema should allow future SSE/WebSocket transport.

## 11. Frontend Design

Add two focused frontend units.

### `ConversationClient`

Responsibilities:

- Create conversations.
- Send normal messages.
- Answer input requests.
- Respond to approvals.
- Cancel conversations.
- Fetch normalized events.

It replaces coding-workbench usage of `DaemonClient` run methods but can wrap the same HTTP infrastructure.

### `ConversationEventReducer`

A pure reducer converts normalized events into UI state.

```ts
ConversationUiState
- conversationId
- status
- messages[]
- activeQuestion?
- activeApproval?
- activeToolCards[]
- pendingText
- lastSeq
- error
```

Rules:

- `assistant.partial` updates one temporary assistant bubble only when stream output is enabled.
- `assistant.message` replaces partial output for the turn and becomes durable transcript history.
- `assistant.question` sets `activeQuestion` and status `waiting_input`.
- `approval.requested` sets `activeApproval` and status `waiting_approval`.
- `approval.resolved` clears `activeApproval`.
- `tool.started/tool.completed` update a single card keyed by `toolUseId`.
- `raw.output` is not a normal UI transcript event.

### Coding Workbench UI Behavior

- `running`: show compact pending sentinel and stop button.
- `waiting_input`: hide running sentinel; show one question card; composer placeholder becomes "回答这个问题..."; send calls `answerQuestion`.
- `waiting_approval`: show one approval card; composer does not send normal prompts.
- `idle/completed`: composer sends a normal conversation message.
- New session: create a new conversation and clear old reducer state.
- Conversation list: list conversations, not raw runs.

Phase 1 should not broadly split visual component files. Only extract `ConversationClient` and `ConversationEventReducer` to reduce risk.

## 12. Compatibility

- Keep `/api/runs` and `RunManager` for existing tests and old flows.
- Coding workbench migrates to `/api/conversations`.
- Existing adapter code can be reused internally where safe, but conversation logic should not depend on run state semantics.
- Existing tests for `/api/runs` should continue passing.

## 13. Testing Plan

### Daemon State Machine Tests

- New conversation starts idle with no `cliSessionId`.
- First message starts adapter and moves to running.
- Question event moves to `waiting_input` with one blocking item.
- Matching input response returns to running.
- Approval event moves to `waiting_approval` with one blocking item.
- Matching approval response returns to running.
- Wrong questionId/approvalId returns 409.
- Normal message during waiting state returns 409.
- Idle TTL disposes process and preserves same-conversation `cliSessionId`.
- New conversation does not reuse previous `cliSessionId`.

### Claude Adapter Simulated Tests

- Simulated `AskUserQuestion` emits `assistant.question`.
- Answer writes a new user message to the same stdin stream.
- Simulated Bash/Read/Write control request emits `approval.requested`.
- Approval writes correct control response.
- Result emits `assistant.message` and returns conversation to idle.
- Second blocking request while one is active does not produce duplicate UI-visible blocking cards.

### API Integration Tests

- Create/list/get conversation.
- Send message and fetch events by sequence.
- Answer question path.
- Approval response path.
- Cancel path.
- Auth and workspace authorization remain enforced.

### Flutter Tests

- `ConversationClient` serializes endpoints correctly.
- `ConversationEventReducer` handles running/waiting/idle transitions.
- Waiting input renders one question card and answer-mode composer.
- Waiting approval renders one approval card.
- Assistant final message replaces partial.
- Tool events merge by `toolUseId`.
- New conversation clears previous reducer state.

### Real Claude Smoke

Automated real smoke uses a safe prompt only:

- Create conversation.
- Send "你是谁？一句话回答".
- Confirm Claude CLI starts.
- Confirm an `assistant.message` arrives.
- Confirm conversation returns to idle/completed.

Real file access, real permission approval, and real `AskUserQuestion` are manual/optional validation in phase 1.

## 14. Migration Phases

### Phase 1A: Backend Core

- Add normalized conversation protocol.
- Add `ConversationManager`.
- Add conversation API endpoints.
- Add Claude conversation adapter with long-lived process and blocking item support.
- Add state machine and simulated adapter tests.

### Phase 1B: Frontend Switch

- Add `ConversationClient`.
- Add `ConversationEventReducer`.
- Switch coding workbench from run API to conversation API.
- Keep current UI components mostly intact.
- Add Flutter reducer and UI tests.

### Phase 1C: Real Smoke and Hardening

- Add safe real Claude smoke for conversation API.
- Add diagnostics for raw provider events.
- Add idle TTL configuration.
- Verify new conversation isolation and same-conversation resume.

## 15. Open Implementation Checks

Before implementing Claude `AskUserQuestion`, write a small harness to confirm the exact provider control behavior when a user answer is sent as a new user message while the original control request is pending. The design decision remains that the user's answer is a user message; the harness determines the minimal provider acknowledgement needed to unblock Claude, if any.

## 16. Acceptance Criteria

- Coding workbench uses `/api/conversations` instead of `/api/runs` for new conversations.
- New conversation never reuses prior conversation state, run id, event stream, pending item, or CLI session id.
- Same conversation can wait for user input or approval without killing the CLI process.
- Only one blocking card can be visible at a time.
- `AskUserQuestion` is displayed as an input request, not as permission approval.
- True tool permissions are displayed as approval requests.
- Frontend renders normalized events without parsing provider raw JSON.
- Existing `/api/runs` tests still pass.
- New conversation tests pass at daemon and Flutter levels.
- Safe real Claude smoke passes.
