# Claude Adapter Full Alignment Design

Date: 2026-05-04
Status: Draft for user review
Scope: Claude CLI adapter, conversation protocol/API, mobile conversation UI, daemon tests

## 1. Problem

The current Claude adapter only partially reflects the Claude Code CLI model described in `docs/claude-code-agent-guide.md`.

The gaps are visible at three layers:

- The daemon treats some Claude flags and permission modes as a coarse subset instead of a real capability matrix.
- The conversation protocol collapses Claude question prompts, approval requests, session identity, and system notices into too few states.
- The mobile app can render the current conversation flow, but it does not fully distinguish Claude input requests, approval requests, session resume state, and adapter warnings.

As a result, the system works for the common path, but it does not fully align with the documented Claude CLI behavior or expose enough structure for future adapter consistency.

## 2. Goals

- Align the Claude adapter with the documented CLI usage patterns in the guide.
- Model Claude permission behavior more accurately, including supported values and graceful fallback.
- Make Claude session identity, resume behavior, and blocking states explicit in the daemon conversation model.
- Normalize Claude stream-json events before they reach mobile UI code.
- Preserve a single conversation-centric API surface for the mobile app.
- Keep the change focused on the current daemon/mobile stack without introducing new dependencies.

## 3. Non-Goals

- Do not redesign the entire mobile UI.
- Do not add a new transport layer such as SSE or WebSocket.
- Do not rewrite unrelated adapters unless a shared protocol fix is required.
- Do not introduce a new persistence backend.
- Do not preserve every historical compatibility quirk if it blocks clearer Claude alignment.

## 4. Chosen Approach

Use a protocol-layer alignment approach.

The Claude adapter becomes responsible for:

- capability detection
- CLI flag construction
- stream-json parsing
- event translation
- protocol leak filtering

The conversation layer becomes responsible for:

- mapping adapter events into conversation states
- tracking one active blocking item at a time
- persisting Claude session identity
- exposing normalized conversation summaries and events through the API

The mobile app becomes responsible for:

- rendering normalized conversation state
- showing separate UI treatment for input requests, approvals, and system notices
- parsing the extended summary/event shapes without needing raw Claude protocol knowledge

This approach was chosen over a minimal patch because the guide describes multiple Claude behaviors that are currently distributed across several abstractions. Aligning only one layer would keep the semantic mismatch in place.

## 5. Claude Adapter Design

### 5.1 Capability Detection

The adapter must detect capabilities at runtime instead of assuming a single installation shape.

Required detection outputs:

- `available`
- `version`
- `print`
- `streamJson`
- `inputFormat`
- `verbose`
- `includePartialMessages`
- `resume`
- `bare`
- `permissionModes`

Rules:

- `--version` failure means the CLI is unavailable.
- `--help` output is advisory, not authoritative.
- `permissionModes` must be treated as a first-class capability field and cached in the capability object.
- Permission mode detection should use a two-step strategy:
  - first parse the `--permission-mode` candidate list from `--help` output when it is present
  - then verify uncertain modes by running a safe parse probe such as `claude --permission-mode auto --print --max-turns 0 true` and checking for a parse error
- `auto` must be treated as supported only when the detected installation supports it.
- If `auto` is requested but unsupported, the adapter must degrade to `default` and expose `effectivePermissionMode` in the conversation summary instead of silently hiding the fallback.

### 5.2 Launch Argument Builder

The adapter should build command arguments from structured input rather than assembling them inline.

Inputs to the builder:

- non-interactive print mode, which requires `--print`
- prompt text
- workspace path
- requested permission mode
- requested tools or tool restrictions
- session id or resume policy
- system prompt policy
- capability result

The builder must handle these flag groups:

- `--print`
- `--output-format stream-json`
- `--input-format stream-json`
- `--verbose`
- `--include-partial-messages`
- session controls: `--resume`, `--continue`, `--session-id`, `--fork-session`, `--name`
- permission controls: `--permission-mode`, `--permission-prompt-tool`
- tool controls: `--tools`, `--allowedTools`, `--disallowedTools`

Rules:

- When `--input-format stream-json` is set, `--permission-prompt-tool` must not be added.
- `default` mode should rely on stream-json `control_request` / `control_response` frames, not on the separate stdio permission prompt tool.
- `allowedTools` is for pre-approval, not hard restriction.
- `tools` is the hard restriction mechanism.
- `disallowedTools` takes precedence when a tool must be removed from model context.
- `bypassPermissions` and similarly permissive modes must not be combined with a false sense of tool restriction via `allowedTools`.

### 5.3 Event Translation

Claude stream-json events must be translated into normalized daemon events.

Important mappings:

- `assistant` frames become assistant message or partial events.
- `tool_*` frames become tool started/output/completed events.
- `control_request` becomes either an input request or approval request depending on the payload.
- `result` becomes the terminal run result and captures session identity and error state.
- `system` frames become protocol warnings, retry notices, or status notices.
- `stream_event` wrapper frames must be unwrapped before normal event mapping.

System frame rules:

- `subtype: 'api_retry'` becomes a non-blocking retry notice with attempt and delay information.
- `subtype: 'status'` becomes a non-blocking status notice.
- `subtype: 'session_start'` and `subtype: 'session_end'` are internal events and should not render in the normal UI.
- `session_start` should still be inspected for `session_id` so the daemon can capture Claude session identity.

The adapter must continue filtering internal protocol leakage before rendering user-visible text.

Examples of text that should be filtered:

- `control_request`
- `control_response`
- `hookSpecificOutput`
- `suppressOutput`
- `parent_tool_use_id`
- nested JSON that looks like an internal control envelope

### 5.4 Stdin Lifecycle

The adapter must manage stdin based on the effective permission mode.

Rules:

- For all modes, the adapter must complete the initialize handshake before sending the user prompt.
- The initialize handshake is: start the process, send a `control_request` with `subtype: 'initialize'`, wait for the matching `control_response`, then send the user prompt.
- If the mode expects a control request loop, stdin stays open until the interaction is complete.
- If the mode does not expect interactive approval or question exchange, the prompt is sent and stdin is closed.
- Late stdout/stderr noise after terminal completion must be ignored for transcript purposes.

## 6. Conversation Protocol Design

### 6.1 Summary Shape

The conversation summary must expose both requested and effective Claude runtime behavior.

Add or preserve these fields:

- `requestedPermissionMode`
- `effectivePermissionMode`
- `permissionSupport`
- `cliSessionId`
- `blockingItem`
- `capabilities`
- `status`

`permissionSupport` should include the adapter’s detected permission-mode support so the mobile UI can explain fallback behavior.

### 6.2 Blocking Items

The protocol must distinguish these blocking item types:

- `input_request`
- `approval_request`

Rules:

- Only one blocking item may be active at a time.
- A second blocking request while one is active should not spawn another UI card.
- The daemon should record a protocol warning when a conflicting blocking request arrives.
- System notices are not blocking items. Retry notices, status notices, and adapter warnings should flow through the event stream or a separate notices collection, because they do not require user response and Claude may continue without intervention.

Suggested blocking item fields:

- `type`
- `questionId` or `approvalId`
- `toolName`
- `text`
- `summary`
- `suggestions`
- `input`
- `createdAt`
- `adapterRequestId` when available

### 6.3 Conversation Status Mapping

The conversation state machine should map normalized events to clear statuses.

Recommended mappings:

- `conversation.started` → `idle` or `running` depending on whether a prompt is immediately dispatched
- `assistant.partial` → `running`
- `assistant.question` → `waiting_input`
- `approval.requested` → `waiting_approval`
- `input_request` response accepted → `running`
- `approval_request` allow accepted → `running`
- `approval_request` deny accepted → usually `running`, unless the adapter reports an interrupting failure
- `assistant.message` → `idle`
- `conversation.completed` → `idle` or `completed` based on terminal semantics
- `run.error` → `failed`
- `conversation.cancelled` → `cancelled`
- expired idle conversation → `expired`

The key requirement is that the status must describe the conversation’s current blocking reality, not just the latest raw CLI frame.

### 6.4 Session Identity

The conversation layer must keep Claude session identity explicit.

Rules:

- A newly created conversation starts with no prior Claude session id.
- The first observed `session_id` from the adapter is stored as `cliSessionId`.
- A resumed or continued turn reuses the same conversation’s `cliSessionId` when available.
- A new conversation must not inherit another conversation’s session id.

## 7. API Design

### 7.1 Conversation Creation

`POST /api/conversations` should accept the existing workspace and adapter selection plus the extended Claude intent fields.

Recommended request fields:

- `workspaceId`
- `adapter`
- `permissionMode`
- `requestedTools`
- `requestedToolPolicy`
- `resumePolicy`
- `systemPromptPolicy`

The API may ignore unsupported fields for non-Claude adapters, but it must preserve them in the conversation record where useful for future adapters.

### 7.2 Conversation Summary Responses

Conversation list and detail responses should include:

- adapter id
- workspace id
- status
- `cliSessionId`
- `blockingItem`
- capabilities
- requested/effective permission state
- timestamps

### 7.3 Event Responses

`GET /api/conversations/:id/events` should return normalized events only.

Raw Claude payloads may remain available in a debug field for diagnostics, but the normal transcript path should use normalized event fields.

### 7.4 Input and Approval Endpoints

The existing question and approval response endpoints remain, but their semantics should map cleanly to the new blocking item types.

Rules:

- question responses only resolve `input_request`
- approval responses only resolve `approval_request`
- a response with the wrong id or wrong blocking type must fail with a conflict
- blocking items must include `createdAt` and an explicit timeout policy, such as an `expiresAt` timestamp or daemon-level timeout duration
- if the underlying Claude process exits or times out while waiting for a response, the conversation should move to `failed` with a normalized timeout/error event rather than leaving a stale blocking item active

## 8. Mobile Design

### 8.1 Summary Parsing

The mobile protocol models should accept the extended conversation summary and event shapes without breaking older fields.

The UI should rely on:

- `status`
- `blockingItem`
- `cliSessionId`
- `capabilities`
- `effectivePermissionMode`

### 8.2 Blocking UI

The mobile app should present separate states for:

- Claude asking a question
- Claude waiting for approval
- Claude showing a non-actionable system notice

The UI should not conflate a question prompt with a permission prompt.

Suggested treatment:

- question card: prompt text plus answer field and suggestions
- multi-select question card: allow multiple options when `multiSelect: true`, plus custom text for an “Other” answer when supported by the payload
- approval card: tool name, summary, and allow/deny actions
- system notice: informational banner or inline status card

### 8.3 Session and Capability Visibility

The UI should show session identity and fallback behavior only where it helps the user.

Examples:

- show `cliSessionId` in debug or details view
- show permission fallback notices when `auto` degrades to `default`
- show capability badges only if the data is already surfaced in the current screen design

## 9. Migration and Compatibility

The migration should be incremental even if the protocol is being cleaned up.

Recommended sequence:

1. Add the new capability and normalized fields behind the daemon.
2. Expand mobile models to parse the new fields.
3. Add a protocol version field or capability flags to conversation summaries so mobile clients can detect the new render semantics before using them.
4. Update the mobile renderers to use the new blocking item distinctions.
5. Add or adjust tests for the new end-to-end Claude semantics.
6. Remove any now-redundant legacy translation code once the new flow is stable.

Compatibility stance:

- Keep old fields readable while the new fields are introduced.
- Prefer adding a field over repurposing one if the old meaning is still in use elsewhere.
- Do not keep a second, duplicated source of truth for status or blocking state.

## 10. Testing Strategy

### 10.1 Claude Adapter Tests

Add tests for:

- capability detection when the CLI is missing
- capability detection when `auto` is unsupported
- launch arg construction for each permission mode
- `tools` vs `allowedTools` vs `disallowedTools`
- resume/continue/session-id behavior
- stdin closing behavior for non-interactive modes
- initialize handshake sequencing and timeout fallback
- `stream_event` wrapper unwrapping
- protocol leak filtering
- late-noise suppression after terminal completion

### 10.2 Conversation Manager Tests

Add tests for:

- conversation creation with extended Claude intent fields
- effective permission mode fallback
- question vs approval blocking item separation
- session id capture and reuse
- wrong-id response conflicts
- blocking item timeout handling when Claude exits or stops waiting
- terminal state transitions from Claude result events

### 10.3 Mobile Tests

Add tests for:

- parsing the extended conversation summary
- rendering question vs approval vs notice as distinct UI states
- preserving old fields while reading new ones
- showing permission fallback or session detail where applicable

## 11. Risks

- The Claude CLI may have slightly different flag behavior across installation sources, so the runtime detection path must stay defensive.
- Over-eager protocol normalization could hide useful raw detail from debugging, so raw payload access should remain available in a debug path.
- Mobile UI changes could accidentally reintroduce question/approval conflation if the render logic is not separated carefully.
- The API migration may require a short compatibility window if other clients already depend on older summary shapes.

## 12. Acceptance Criteria

The work is complete when:

- Claude capability detection reflects the documented permission and stream-json behavior.
- Conversation summaries expose effective permission mode and Claude session identity.
- Question prompts and approval requests are distinct throughout daemon, API, and mobile.
- The mobile app renders the new blocking states correctly.
- Existing tests pass and new regression tests cover the new Claude-specific behavior.
