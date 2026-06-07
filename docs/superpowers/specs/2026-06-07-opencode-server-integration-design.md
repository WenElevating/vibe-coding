# OpenCode Server Integration Design

- Status: approved design
- Date: 2026-06-07
- Scope: daemon OpenCode server-first conversation adapter and existing mobile Workbench projection

## Context

The product is a LAN/mobile control surface for AI CLI coding tools. The
stable product object is the daemon-owned conversation. Provider session ids
are adapter resume tokens and must not become mobile display identity.

The repository already exposes OpenCode in several places:

- `daemon/src/opencode-adapter.js` performs basic HTTP server capability checks
  for the legacy `/api/runs` path.
- `daemon/src/adapter-profiles.js` declares an `opencode` profile with
  server-mode and partial structured-event support.
- `daemon/src/conversation-protocol.js` includes `opencode` in
  `supportedConversationAdapters`.
- `daemon/src/main.js` still registers `opencode` conversations as
  `notImplementedConversationAdapter('OpenCode')`.
- Mobile already has adapter picker/test coverage and an OpenCode icon.

The first integration should therefore fill the daemon conversation adapter
gap instead of adding a new mobile protocol surface.

## Official Support Review

OpenCode officially supports these integration forms:

| Form | Entry point | Fit for this product |
| --- | --- | --- |
| TUI | `opencode` | Not suitable for daemon/mobile control. |
| Non-interactive CLI | `opencode run [message]` | Useful fallback research path, but weaker for session status, approvals, event streaming, and cancellation. |
| HTTP server | `opencode serve` | Best fit for daemon-owned conversations. |
| JS/TS SDK | Official SDK over the server API | Useful later, but not needed for the first implementation and would add a dependency. |
| ACP server | `opencode acp` | Better for editor/Agent Client Protocol hosts than this app's existing Workbench conversation protocol. |

Local verification on 2026-06-07 with `opencode 1.4.6` confirmed:

```powershell
opencode --version
opencode run --help
opencode serve --help
opencode acp --help
```

`opencode run` supports `--format json`, `--continue`, `--session`,
`--attach`, `--dir`, `--file`, `--model`, `--agent`, and
`--dangerously-skip-permissions`. `opencode serve` supports `--port`,
`--hostname`, `--mdns`, and `--cors`.

Local server smoke also confirmed:

- `GET /global/health` returns health and version.
- `GET /doc` returns an OpenAPI document for global routes and event schemas.
- `GET /global/event` is the documented server-sent event stream.
- `POST /session?directory=<workspacePath>` creates a session whose
  `directory` matches the requested workspace path.
- `POST /session` without `directory` creates a session in the server process
  cwd.
- `POST /session/{sessionID}/prompt_async` exists and rejects invalid request
  bodies with `400`.
- `POST /session/{sessionID}/abort` exists and returns `true` for a fresh
  session.
- `POST /session/{sessionID}/permissions/{permissionID}` exists and rejects an
  invalid permission id/body with `400`.

The OpenAPI document lists global routes and event schemas but does not expose
all session routes in the local 1.4.6 `/doc` output. The implementation plan
must start with a local server smoke that verifies the exact session request
bodies before adapter code depends on them.

Official references:

- <https://opencode.ai/docs/cli/>
- <https://opencode.ai/docs/server/>
- <https://opencode.ai/docs/sdk/>
- <https://opencode.ai/docs/permissions/>
- <https://opencode.ai/docs/acp/>

## Goals

- Add a real daemon conversation adapter for `opencode`.
- Use OpenCode server mode as the primary integration path.
- Preserve the existing Workbench conversation API and mobile reducer contract.
- Store the OpenCode session id as the daemon `cliSessionId`.
- Use `POST /session?directory=<workspacePath>` so workspace ownership remains
  explicit.
- Stream OpenCode server events into existing daemon conversation events.
- Support cancellation through the OpenCode server abort route.
- Support mobile approval callbacks when OpenCode emits permission requests.
- Keep user-visible mobile strings localized if any adapter-specific status or
  error text is surfaced in the Flutter UI.
- Avoid new runtime dependencies in the first implementation.

## Non-Goals

- Do not build a TUI wrapper.
- Do not use `opencode run` as the primary Workbench adapter.
- Do not introduce the OpenCode SDK dependency in the first version.
- Do not expose raw OpenCode HTTP routes or OpenAPI payloads directly to mobile.
- Do not add a separate OpenCode mobile feature tab.
- Do not add arbitrary OpenCode config mutation, auth mutation, upgrade, or
  global dispose controls.
- Do not silently enable dangerous permission bypass for a mobile conversation.
- Do not make `/api/runs` the target workflow.

## Selected Approach

Implement a server-first `OpenCodeConversationAdapter` behind the existing
`opencode` adapter id.

Mobile continues to create conversations through the existing daemon
conversation endpoints:

```text
POST /api/conversations
POST /api/conversations/{id}/messages
GET  /api/conversations/{id}/events
POST /api/conversations/{id}/cancel
```

The daemon owns all OpenCode-specific behavior:

```text
Workbench mobile API
  -> ConversationManager
  -> OpenCodeConversationAdapter
  -> OpenCodeServerClient
  -> opencode serve
```

This preserves the product boundary: conversation identity, event persistence,
authorization, device access, title derivation, attachment redaction, and
blocking-item orchestration stay daemon-owned.

## Architecture

### `daemon/src/opencode-server-client.js`

Add a small HTTP/SSE client for OpenCode server routes. It should use Node
standard-library HTTP primitives, matching the existing daemon style and
avoiding a new dependency.

Responsibilities:

- Probe `GET /global/health`.
- Create sessions with `POST /session?directory=<encodedWorkspacePath>`.
- Send user prompts with the locally verified `prompt_async` request shape.
- Abort sessions with `POST /session/{sessionID}/abort`.
- Respond to permission requests with the locally verified permission response
  route and body.
- Subscribe to `GET /global/event` and parse server-sent events.
- Apply request timeouts and return structured errors with status, code, and
  safe messages.

The client should not know about daemon conversation ids, mobile event shapes,
or adapter capability projection.

### `daemon/src/opencode-server-lifecycle.js`

Add a daemon-owned server lifecycle helper.

Lifecycle modes:

| Mode | Trigger | Behavior |
| --- | --- | --- |
| External | `OPENCODE_SERVER_URL` is set | Connect to that server, never stop it, and report configuration errors if health fails. |
| Managed | No external URL is set | Start a local `opencode serve` child on an explicit daemon-selected loopback port, health-check it, and stop the child when the daemon shuts down. |

The first implementation can start one managed server per daemon process and
use `POST /session?directory=...` per workspace. If smoke testing shows
directory isolation is unreliable for any supported OpenCode version, use one
managed server per workspace path instead.

Managed startup should avoid depending on `--port 0` output parsing. The
preferred path is:

1. Pick an available loopback port in daemon code.
2. Start `opencode serve --hostname 127.0.0.1 --port <port>`.
3. Probe `GET /global/health` until it succeeds or startup times out.
4. If the port is already in use, retry with a new port and a new child.

If a future implementation uses `--port 0`, stdout/stderr parsing must be
version-aware and the parsed port must still be confirmed with
`GET /global/health`. Parsed output alone is not sufficient evidence that the
server is ready.

Managed lifecycle must:

- Resolve the `opencode` command through the existing CLI resolver patterns.
- Hide child windows on Windows.
- Avoid mDNS for daemon-managed local servers.
- Keep the server bound to `127.0.0.1`.
- Record lifecycle failures in adapter diagnostics.
- Clean up the child process on daemon shutdown. On Windows, use a process-tree
  terminator such as `taskkill /PID <pid> /T /F` after a short graceful wait;
  on POSIX, send `SIGTERM`, wait, then send `SIGKILL` if needed.

### `daemon/src/opencode-conversation-adapter.js`

Add the conversation adapter that implements the same interface as the Claude
and Codex conversation adapters.

Responsibilities:

- Detect OpenCode server availability.
- Expose capabilities that match server-first behavior.
- Create or resume the OpenCode session for a daemon conversation.
- Return a handle with `sendUserMessage`, `respondApproval`, `cancel`, and
  `dispose`.
- Bind OpenCode session ids through `event.sessionId` so
  `ConversationManager.confirmSessionBinding()` persists `cliSessionId`.
- Filter the shared SSE stream by a normalized session id before emitting
  events to a conversation.
- Preserve provider session metadata only through the existing
  `providerSession` field.

Initial capabilities:

```js
{
  longLivedProcess: true,
  waitingInput: false,
  waitingApproval: true,
  resume: true,
  partialOutput: true,
  toolEvents: true,
  approval: {
    mobileCallbacks: true,
    scopes: ['once', 'session'],
    supportsCancel: false,
    denyBehaviors: ['interrupt']
  },
  attachments: {
    image: 'unsupported',
    textDocument: 'text_extract',
    pdf: 'unsupported'
  }
}
```

These are conservative first-version capabilities. Image and PDF should stay
`unsupported` until real OpenCode server message payloads have been verified.
Text documents may use the existing `textAttachmentWrapper` extraction path
because it degrades to plain prompt text and does not depend on
provider-native attachment support. When smoke testing proves that OpenCode
server accepts a stable base64 image message body or file attachment body, the
adapter can upgrade image support through the existing capability enrichment
path without mobile-side API changes.

### `daemon/src/opencode-event-mapper.js`

Map OpenCode events into existing `conversationEventTypes`.

The mapper should be a pure module with fixture-driven tests. It should accept
raw OpenCode event objects and return zero or one normalized daemon event. If a
raw event is not understood, emit a non-visible `system.notice` with
`noticeKind: 'opencode_unknown_event'` and the bounded raw payload.

Initial mapping:

| OpenCode event | Daemon event |
| --- | --- |
| `session.created`, `session.updated` | Hidden `system.notice` with session metadata. |
| `session.status` | Hidden `system.notice`; terminal statuses may emit `conversation.completed` once verified. |
| `session.idle` | `conversation.completed` for the active turn unless already completed/cancelled/failed. |
| `session.error` | `run.error` with sanitized provider error details. |
| `message.part.delta` | `assistant.partial`, `assistant.thinking`, or `tool.delta` depending on part metadata. |
| `message.part.updated`, `message.updated` | `assistant.message`, `tool.started`, `tool.completed`, or hidden notice depending on role/part kind. |
| `message.part.removed`, `message.removed` | Hidden `system.notice`; the adapter may turn it into `blocking.request_cancelled` only when it can correlate the removed message/part to pending handle state. |
| `permission.asked` | `approval.requested`. |
| `permission.replied` | `approval.resolved`. |
| `session.diff` | `diff.summary` when the payload contains usable file diffs; otherwise visible `system.notice`. |
| `file.edited` | Visible `system.notice` with relative path, bounded to the authorized workspace. |
| `file.watcher.updated` | Hidden `system.notice`. |
| `project.updated` | Hidden `system.notice`. |

The mapper must normalize `sessionID`, `sessionId`, `session_id`, `messageID`,
`messageId`, `message_id`, `partID`, `partId`, `part_id`, permission ids, tool
call ids, paths, and error payloads without leaking absolute paths outside the
authorized workspace.

Critical session-scoped event families must carry a normalized session id before
they are allowed to reach a daemon conversation:

- `message.*`
- `permission.*`
- `session.status`
- `session.idle`
- `session.error`
- `session.diff`

If a critical event lacks a session id, the adapter must drop it from
conversation dispatch and record a bounded audit/protocol warning. It must not
broadcast the event to all active conversations. The real-server smoke must
verify field names for at least message, permission, status, idle, error, and
diff events before implementation relies on the shared `/global/event` stream.

## Event Stream Reliability

`/global/event` is a shared SSE stream. The adapter must treat it as an
observable transport, not as the source of conversation authority.

Reconnect policy when a stable reconciliation route has been smoke-verified:

- Reconnect only for transport failures, not for malformed event payloads.
- Use at most 3 reconnect attempts per disconnect.
- Use deterministic backoff delays of 250 ms, 1000 ms, and 3000 ms.
- Keep at most one active SSE connection per OpenCode server client.
- Pause new `prompt_async` sends while the event stream is disconnected.
- Emit `run.error` with code `OPENCODE_EVENT_STREAM_INTERRUPTED` after the
  reconnect budget is exhausted for an active conversation.

Recovery after reconnect is allowed only if the implementation can reconcile
the OpenCode session state through a verified read route or equivalent stable
server state. Reconciliation must prove:

- the session still exists;
- the session directory is still inside the authorized workspace;
- the current turn is still active, idle, errored, or waiting for the same
  permission id already shown to mobile.

If the adapter cannot prove those facts after reconnect, it must fail the
active turn with `OPENCODE_EVENT_STREAM_INTERRUPTED` instead of assuming that
no `session.idle`, `session.error`, or `permission.asked` event was missed.

If the real-server smoke does not verify a stable session read/reconcile route,
set the adapter's internal `supportsEventReconciliation` flag to false. In
that mode, reconnect is allowed only while no daemon conversation has an active
OpenCode turn. Any `/global/event` disconnect during `running` or
`waiting_approval` must fail the active turn immediately with
`OPENCODE_EVENT_STREAM_INTERRUPTED`; the implementation must not attempt to
resume and guess whether critical events were missed.

When a disconnect happens while `ConversationManager` is in
`waiting_approval`, the existing blocking item may remain visible only during
the reconnect budget. If reconnect is exhausted or reconciliation cannot prove
the same permission request is still pending, the adapter emits `run.error`.
That clears the blocking item through the existing conversation error path, so
the mobile approval UI must not hang indefinitely.

## Data Flow

### Create Conversation

1. Mobile calls `POST /api/conversations` with `adapter: 'opencode'`.
2. `ConversationManager` creates the daemon conversation as today.
3. No OpenCode session is created until the first message is dispatched.

### First Message

1. `ConversationManager.commitAndDispatchMessage()` persists the user event and
   marks the conversation `running`.
2. `OpenCodeConversationAdapter.startConversation()` obtains a healthy server
   from lifecycle.
3. The adapter creates an OpenCode session with
   `POST /session?directory=<workspacePath>`.
4. The adapter emits a hidden session-start notice carrying
   `sessionId: <OpenCode session id>`.
5. `ConversationManager.confirmSessionBinding()` persists that id as
   `cliSessionId`.
6. The handle sends the prompt through `prompt_async`.
7. OpenCode SSE events are mapped and appended to the daemon event store.

### Later Messages

Later messages reuse the stored `cliSessionId`. The adapter should verify that
the session still belongs to the requested workspace directory before sending.
If the session is missing or belongs to a different directory, the adapter must
follow these recovery rules before sending the prompt:

| Condition | Behavior |
| --- | --- |
| Stored session is missing, expired, or unreadable before prompt dispatch and no verified history replay/reconstruction path exists | Clear `cliSessionId`, mark session binding unknown, append a visible `opencode_session_expired` notice, fail the current turn with `run.error` code `OPENCODE_SESSION_MISSING`, and do not send the current prompt. |
| Stored session is missing, expired, or unreadable before prompt dispatch and a future verified history replay path exists | Recreate a session only after replaying enough daemon-persisted conversation history to preserve model context, append a visible `opencode_session_recreated` notice, then send the current prompt once. This replay path is not part of the first implementation. |
| Stored session exists but its directory is outside the authorized workspace | Clear `cliSessionId`, mark session binding drifted, fail the current turn with `run.error` code `OPENCODE_SESSION_DIRECTORY_MISMATCH`, and do not send the prompt. |
| Newly created replacement session returns a mismatched directory | Fail closed with `OPENCODE_SESSION_DIRECTORY_MISMATCH`; do not retry in the same turn. |

This avoids a retry dead loop where every later message reuses the same invalid
`cliSessionId`. It also avoids replaying a prompt into a session that may
belong to a different workspace. Implementing this requires a narrow internal
`ConversationManager` helper for clearing or marking provider session bindings;
the OpenCode adapter must not mutate stored conversation fields directly.

The first implementation must not silently create a replacement session for a
later message. A missing OpenCode session usually means provider-side context
has been lost. Sending the user's next prompt to a fresh session would look like
an unexplained memory reset. Until a replay design is implemented and verified,
the user-visible notice is required and the turn must fail before prompt
dispatch.

### ConversationManager Session Binding Helpers

OpenCode is the first adapter that needs to invalidate a stored provider
session before dispatch. Keep this authority in `ConversationManager`, not in
adapter code.

Add narrow internal helpers with this shape:

```js
clearSessionBinding(conversation, {
  expectedSessionId,
  reason,
  code,
  noticeKind,
  visible
})

markSessionBindingDrifted(conversation, {
  expectedSessionId,
  receivedSessionId,
  reason,
  code,
  clear
})
```

Behavior:

- `expectedSessionId` is optional but, when provided, must match the current
  `conversation.cliSessionId`; otherwise the helper must leave state unchanged
  and report a conflict to the caller.
- `clearSessionBinding` sets `cliSessionId` to null, sets
  `sessionBinding` to `unknown`, clears `providerSession` only when it belongs
  to the cleared provider session, persists the conversation, and appends a
  `system.notice`.
- `markSessionBindingDrifted` sets `sessionBinding` to `drifted`, persists the
  conversation, and appends a bounded `protocol.warning`. If `clear` is true,
  it also clears `cliSessionId` after recording the drift.
- Helpers must be internal methods, not new mobile API routes.
- Adapters may request these transitions through the start/dispatch path, but
  must not directly mutate `conversation.cliSessionId`, `sessionBinding`, or
  `providerSession`.

### Cancellation

Mobile cancellation continues to call the existing daemon conversation cancel
endpoint. The OpenCode handle calls `POST /session/{sessionID}/abort`, then
lets the `ConversationManager` record `conversation.cancelled`. If abort fails,
the daemon still transitions the conversation according to the existing
best-effort cancellation behavior and records an audit warning.

## Permission Handling

OpenCode permissions should map to the existing mobile blocking item model.

When OpenCode emits `permission.asked`, the mapper emits
`approval.requested` with:

- `approvalId`: OpenCode permission request id.
- `toolUseId`: OpenCode tool call id when provided.
- `toolName`: best available OpenCode permission/tool name.
- `summary`: command/path/pattern summary suitable for mobile display.
- `approvalOptions.kind`: `command`, `file_change`, or `generic`.
- `approvalOptions.supportsSessionScope`: true when OpenCode exposes an
  `always` or equivalent session-level choice.
- `approvalOptions.denyBehavior`: `interrupt`.

Mobile decisions map back to OpenCode replies:

| Mobile decision | OpenCode reply |
| --- | --- |
| `allow` + `scope: once` | `once` |
| `allow` + `scope: session` | `always` |
| `deny` | `reject` |
| `cancel` | `reject` plus daemon-side cancellation if the user requested interrupt/cancel semantics. |

Terminology boundary: mobile and daemon approval scopes remain `once` and
`session`. OpenCode's `always` value is only the provider reply corresponding
to daemon `scope: session`. Do not expose `always` as a mobile approval scope.

`approval.supportsCancel` means "the provider exposes a distinct cancellation
reply for this approval prompt." It does not refer to whole-conversation
cancellation, which is still available through the existing conversation cancel
endpoint. Because OpenCode's first-version approval mapping only has
`once`/`always`/`reject`, `supportsCancel` stays false and mobile should show
allow/deny approval actions. If a client still submits approval decision
`cancel`, the daemon treats it as `reject` and may additionally cancel the
whole conversation through the normal conversation-cancel path; that path is
defensive and should not be advertised by approval options.

The exact permission response body must be verified against the local server
before implementation. The route existence is verified; the accepted payload
shape is the remaining smoke prerequisite.

`permissionMode: auto` must not silently enable OpenCode's dangerous bypass.
For the first version, OpenCode should advertise only the default permission
mode unless a per-session, non-global server API for auto approval is verified.
If a caller requests `permissionMode: auto`, the adapter should fail clearly
with status `422` and code `OPENCODE_PERMISSION_MODE_UNSUPPORTED` rather than
downgrading silently.

## Model Handling

OpenCode model ids use `provider/model` format. The first implementation
should discover model capability from server configuration only if a stable
read route exposes it in the verified runtime. Otherwise:

- `canSelectModel` remains false.
- The mobile model picker does not show OpenCode model choices.
- A manually supplied model is rejected with the existing
  `CONVERSATION_MODEL_UNSUPPORTED` path.

If model discovery is verified, expose normalized model ids through the
existing adapter capability enrichment path. Do not add a mobile-specific
OpenCode model picker.

## Workspace And Security Boundaries

- Always create OpenCode sessions with the authorized workspace path from
  `ConversationManager`, never from mobile-provided raw paths.
- Reject or fail a conversation if OpenCode returns a session directory outside
  the authorized workspace.
- Keep daemon-managed OpenCode servers bound to `127.0.0.1`.
- Do not expose OpenCode global config/auth/upgrade/dispose routes through the
  mobile API.
- Do not forward raw provider errors that include secrets, absolute external
  paths, or full attachment contents.
- Reuse the existing attachment dispatch redaction logic for adapter errors and
  protocol warnings.
- Bound raw payloads in unknown-event notices.

## Error Handling

| Failure | Behavior |
| --- | --- |
| OpenCode command missing | Adapter diagnostics show unavailable with actionable setup text. |
| External server unreachable | Adapter diagnostics show needs configuration with `OPENCODE_SERVER_URL`. |
| Managed server spawn fails | Conversation start fails before provider request; status becomes failed with a safe error. |
| Health probe fails | Adapter unavailable; no session is created. |
| Session create fails | Turn fails before prompt dispatch; no fallback to another adapter. |
| Stored session missing before later-message dispatch | Clear `cliSessionId`, mark binding unknown, append visible `opencode_session_expired`, and fail the current turn with `OPENCODE_SESSION_MISSING`; do not send the prompt unless a future verified replay path exists. |
| Session directory mismatch | Clear the invalid `cliSessionId`, mark binding drifted, and fail the current turn with `OPENCODE_SESSION_DIRECTORY_MISMATCH`. |
| Prompt dispatch fails | Turn fails with `run.error`; user may retry. |
| SSE disconnects during active turn with verified reconciliation | Attempt 3 reconnects with 250 ms, 1000 ms, and 3000 ms delays; if reconciliation cannot prove no critical event was missed, emit `run.error` code `OPENCODE_EVENT_STREAM_INTERRUPTED`. |
| SSE disconnects during active turn without verified reconciliation | Fail immediately with `OPENCODE_EVENT_STREAM_INTERRUPTED`; do not reconnect and guess. |
| Unknown event type | Hidden `system.notice` with bounded raw payload. |
| Permission response fails | Conversation returns to failed state and clears the blocking item. |
| Abort fails | Record audit warning; preserve daemon-side cancellation semantics. |

OpenCode integration should not automatically fall back to Codex or Claude.
Cross-provider replay can duplicate tool/file behavior and would violate the
conversation identity model.

## Mobile Impact

No new feature screen is required.

Mobile changes should be limited to:

- Ensuring `opencode` is selectable only when adapter capabilities say it is
  available.
- Rendering existing normalized events in Workbench.
- Localizing any new adapter status, permission, or error strings that become
  visible in Flutter.
- Keeping fallback text such as "not available", "unsupported permission mode",
  and "OpenCode server unavailable" in ARB files if they are surfaced by UI
  code.
- Localizing visible session recovery notices such as
  `opencode_session_expired` and any future `opencode_session_recreated`
  message.

The mobile UI must not branch on raw OpenCode event names. It should consume
the same `ConversationEvent` DTOs used by Claude and Codex.

## Testing

### Daemon Unit Tests

- `OpenCodeServerClient` parses JSON, HTTP errors, timeouts, and SSE frames.
- `OpenCodeEventMapper` maps session, message, permission, diff, file, and
  error fixtures.
- Unknown events become hidden bounded notices.
- Permission decisions produce the expected OpenCode reply payloads after the
  route body is smoke-verified.
- Missing stored sessions clear session binding, append a visible
  `opencode_session_expired` notice, and fail before prompt dispatch.
- Workspace directory mismatch clears invalid session binding and fails closed.
- SSE reconnect backoff, no-reconciliation immediate failure, exhausted
  reconnect, and waiting-approval disconnect paths are covered with fake
  timers.
- Critical events without normalized session ids are dropped from conversation
  dispatch and recorded as bounded warnings.
- Attachment capabilities remain conservative.

### Daemon Integration Tests

- `createConversationAdapters()` registers a real `opencode` conversation
  adapter.
- Creating an `opencode` conversation no longer returns the not-implemented
  placeholder.
- A fake OpenCode server can create a session, accept `prompt_async`, emit SSE
  events, and drive a full Workbench turn to `idle`.
- Fake permission events create blocking items and resolve through the
  existing approval endpoint.
- Cancellation calls the fake abort route.
- Missing OpenCode sessions do not silently continue in a fresh provider
  session.
- External server diagnostics, managed server spawn failures, explicit-port
  health probing, and Windows process-tree cleanup are covered.

### Mobile Tests

Mobile tests should be added only for visible behavior. Likely targets:

- Adapter picker availability for OpenCode.
- Workbench rendering of OpenCode-normalized assistant/tool/approval events if
  existing generic tests do not already cover them.
- ARB localization coverage for any new visible strings.

### Manual Smoke

Before implementing beyond the client boundary, run a local smoke against the
installed OpenCode version:

```powershell
opencode --version
opencode serve --hostname 127.0.0.1 --port <free-loopback-port>
```

Verify:

- health route;
- session creation with `directory`;
- `prompt_async` accepted request body;
- abort route;
- permission response body with a controlled fake or harmless permission;
- `/global/event` SSE framing and event shape;
- consistent session id field names for message, permission, status, idle,
  error, and diff events;
- a reconnect scenario, including whether any stable read route can reconcile
  active or waiting-permission state.

Do not run a model-consuming prompt smoke unless the user explicitly asks for
it or a test account/runtime is configured for that purpose.

## Verification Commands

Run from repository root:

```powershell
npm test
npm run lint
node scripts/check-project-knowledge.js
```

For mobile-visible changes, CI should prefer cross-platform commands:

```bash
cd mobile
dart run tool/check_architecture_imports.dart
dart analyze
flutter test --no-pub
```

Local Windows/Codex runs may use the repository guidance's direct Dart SDK path
to avoid Flutter wrapper/cache-lock stalls:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
flutter test --no-pub
```

## Implementation Sequence

1. Add a local OpenCode server smoke script that launches the real installed
   `opencode serve` and records the verified session, prompt, abort,
   permission, SSE, session-id-field, reconnect, session-read, and history
   replay contracts.
2. Add a fake OpenCode server for deterministic unit/integration tests based
   on the smoke findings, not assumptions.
3. Add pure event mapping tests and `opencode-event-mapper`.
4. Add `OpenCodeServerClient` with fake-server tests.
5. Add server lifecycle for external URL first, then managed local server with
   explicit-port health probing and platform-specific process-tree cleanup.
6. Add the narrow `ConversationManager` session-binding clear/mark helper
   needed for invalid OpenCode session recovery.
7. Add `OpenCodeConversationAdapter` and replace the placeholder in
   `createConversationAdapters()`.
8. Add conversation integration tests for session binding, events, permission,
   cancellation, and failure states.
9. Add mobile localization/test changes only for visible strings or behavior.

## Acceptance Criteria

- `opencode` is a selectable conversation adapter when the server is available.
- A daemon conversation using `opencode` can send at least one message and
  persist the OpenCode session id as `cliSessionId`.
- OpenCode server events are normalized into existing Workbench event DTOs.
- Permission requests appear as existing mobile approval blocking items.
- Cancelling an active OpenCode turn calls the OpenCode abort route.
- Missing/unhealthy OpenCode server states produce actionable diagnostics.
- Mobile has no raw OpenCode API dependency.
- New visible strings are localized.
- Tests cover success, cancellation, permission, unknown events, and key
  failure modes.
- SSE disconnects cannot leave a mobile blocking item hanging indefinitely.
- A missing OpenCode provider session cannot silently turn a later message into
  a memoryless fresh-session prompt.

## Remaining Risks

- OpenCode's session routes exist in the verified runtime but are not fully
  listed in the local `/doc` OpenAPI output. The implementation must lock the
  exact request bodies with smoke tests before relying on them.
- Event payload structure may change across OpenCode versions. The mapper must
  fail soft for unknown events, require normalized session ids for critical
  events, and keep raw payloads bounded.
- Permission semantics may not exactly match the current mobile approval model.
  The first version should prefer conservative deny/once/session mapping over
  broad auto-approval.
- If no stable session read/reconcile route exists, SSE disconnect during an
  active turn must fail immediately.
- Historical replay into a replacement OpenCode session is intentionally out
  of scope for the first implementation.
- Managed server lifecycle on Windows needs process-tree cleanup rather than
  relying on plain `child.kill()`.
