# Codex App-Server Adapter Design

Date: 2026-06-03
Status: proposed

## Context

The current production Codex conversation adapter uses `codex exec --json`.
That path is stable enough to keep as the fallback, but it cannot support
responsive mobile approval callbacks because `exec` rejects app-server approval
and user-input server requests.

Recent validation added protocol mapping helpers:

- `daemon/src/codex-app-server-bridge.js`
- `daemon/src/codex-app-server-approval.js`

Those helpers prove that app-server events and approval requests can be
projected into the existing conversation event and approval contracts. They do
not prove production lifecycle, transport, auth/session behavior, or real
runtime event order.

The local Codex source checkout at `D:\GithubProject\codex` is the primary
reference for this design. Relevant upstream evidence includes:

- `D:\GithubProject\codex\codex-rs\app-server\README.md`
- `D:\GithubProject\codex\codex-rs\app-server-test-client\README.md`
- `D:\GithubProject\codex\codex-rs\app-server-test-client\src\lib.rs`
- `D:\GithubProject\codex\codex-rs\app-server-client\README.md`
- `D:\GithubProject\codex\codex-rs\app-server-client\src\remote.rs`
- `D:\GithubProject\codex\codex-rs\app-server-daemon\README.md`
- `D:\GithubProject\codex\codex-rs\app-server-protocol\schema\typescript\v2\`

Upstream app-server supports JSON-RPC 2.0 messages with the `jsonrpc` field
omitted on the wire. It supports stdio JSONL, websocket, unix-socket websocket,
and off transports. On Windows, the app-server daemon lifecycle path is not
available because upstream documents `codex-app-server-daemon` as Unix-only.
For this project, the first production-friendly transport should therefore be a
private stdio child process, while websocket remains useful for manual smoke
testing with the upstream test client.

## Goals

- Add an independently selectable `codex-app-server` conversation adapter.
- Preserve the existing `codex` adapter as the `codex exec --json` fallback.
- Do not require mobile UI or reducers to special-case the new adapter.
- Project app-server messages into the existing generic conversation event,
  blocking item, approval, and capability contracts.
- Start with a real `codex app-server` smoke/discovery stage before writing the
  production adapter.
- Use real app-server traffic captured from the local Codex checkout to drive
  later fake-transport regression tests.
- Keep the adapter easy to merge into the default `codex` adapter later, after
  app-server support is validated.

## Non-Goals

- Do not replace the default `codex` adapter in the first implementation.
- Do not add provider-specific UI branches for `codex-app-server`.
- Do not fake app-server behavior only with hand-written fixtures before a real
  app-server smoke has run.
- Do not depend on the upstream Unix-only app-server daemon lifecycle on
  Windows.
- Do not expose raw provider request payloads through normal mobile API events.
- Do not add support for app-server dynamic tools, realtime, remote control, or
  arbitrary process APIs in the first adapter.

## Selected Approach

Expose app-server as a separate conversation adapter id:

```text
codex-app-server
```

The existing adapter id remains:

```text
codex
```

`GET /api/adapters` should list both when available. Mobile can render them as
separate choices during the validation period. Once app-server is stable, a
future design can merge them behind `codex` with app-server preferred and
`exec --json` as fallback.

When a user creates a conversation with `adapter=codex-app-server`, the daemon
should try to use app-server. If app-server capability detection or early
startup fails before any user turn is sent, the daemon should automatically
fall back to the existing `codex` adapter. The public conversation should carry
both requested and effective adapter identity:

```text
adapter: codex-app-server
requestedAdapter: codex-app-server
effectiveAdapter: codex | codex-app-server
```

During the transition, `adapter` should preserve the user-requested adapter id
so mobile does not see the selected tool mutate after creation. Runtime
behavior, capabilities, and attachment handling should use `effectiveAdapter`.

If app-server fails after a turn has started, the daemon must not automatically
replay the user message through `codex exec --json`. Replaying after a turn has
begun can duplicate command execution or file writes. The adapter should emit a
generic `run.error`, clean up transport state, and let the user explicitly retry
or create a new fallback conversation.

## Universal UI Contract

The new adapter must not require mobile UI changes specific to
`codex-app-server`.

Mobile already understands generic conversation events such as:

- `assistant.message`
- `assistant.partial`
- `tool.started`
- `tool.delta`
- `tool.completed`
- `approval.requested`
- `approval.resolved`
- `task.progress.updated`
- `conversation.cancelled`
- `conversation.completed`
- `run.error`
- `protocol.warning`

The app-server adapter must project provider-specific messages into those
events. If app-server reveals a capability that is genuinely not representable,
the project should extend the generic daemon/mobile protocol rather than adding
adapter-specific UI branches.

Approval UI must render from generic approval metadata:

```text
ApprovalRequestOptions
  kind
  supportsSessionScope
  supportsCancel
  denyBehavior
  command
  cwd
  reason
  proposedExecPolicyAmendment
  proposedPermissions
```

Mobile submits provider-neutral approval responses:

```text
ApprovalResponse
  decision: allow | deny | cancel
  scope: once | session
  updatedInput
  updatedPermissions
  interrupt
```

The adapter owns conversion to Codex-native decisions such as `accept`,
`acceptForSession`, `decline`, and `cancel`.

## Phase 1: Real App-Server Smoke And Contract Discovery

The first implementation phase is not production adapter code. It is a real
smoke/discovery harness against the local Codex checkout.

Run from:

```text
D:\GithubProject\codex\codex-rs
```

Use upstream-supported commands from
`codex-rs/app-server-test-client/README.md`:

```powershell
cargo build -p codex-cli --bin codex
cargo run -p codex-app-server-test-client -- --codex-bin .\target\debug\codex serve --listen ws://127.0.0.1:4222 --kill
cargo run -p codex-app-server-test-client -- model-list
cargo run -p codex-app-server-test-client -- watch
cargo run -p codex-app-server-test-client -- send-message-v2 "hello"
```

The smoke should capture and record real JSON-RPC traffic for:

- initialize request, initialize response, and initialized notification
- model listing or a minimal non-turn request
- `thread/start`
- `turn/start`
- `thread/started`
- `turn/started`
- assistant message delta and completion
- command execution start, output delta, completion
- command approval request and response
- file-change approval request and response
- permissions approval request and response, if reproducible
- cancellation through `turn/interrupt`
- JSON-RPC error response
- transport close/disconnect

The output of this phase should be a small fixture set or documented transcript
under this repository, with secrets, local home paths, auth tokens, and raw
provider diagnostics redacted. Later fake transport tests must be based on
these real samples, not imagined protocol shapes.

The smoke phase must also answer:

- Whether stdio is sufficient for the daemon-owned private process path.
- Whether websocket is needed only for manual testing.
- Which initialize capabilities should be enabled. The default should be stable
  API only unless a required approval field is experimental.
- Whether `experimentalApi: true` is required for the metadata needed by mobile
  approvals.
- How app-server reports unsupported versions and unsupported methods.
- What app-server writes to stderr and how noisy logs should map to daemon
  diagnostics.

## Phase 2: Adapter Architecture

After Phase 1 proves the real transport and event contract, add:

```text
daemon/src/codex-app-server-conversation-adapter.js
```

Primary responsibilities:

- detect `codex app-server` availability and minimum protocol support;
- spawn a private `codex app-server` child process over stdio JSONL;
- perform initialize and initialized handshake once per transport connection;
- create or resume threads with `thread/start` and `thread/resume`;
- start turns with `turn/start`;
- route JSON-RPC responses by request id;
- route server notifications through the generic event projection;
- route server requests through approval/input blocking flows;
- send approval responses back to app-server;
- send `turn/interrupt` on cancel;
- tear down child process and pending requests on dispose.

The adapter should reuse existing helpers where real smoke confirms their
shapes:

- `buildCodexAppServerThreadStartRequest`
- `buildCodexAppServerThreadResumeRequest`
- `buildCodexAppServerTurnStartRequest`
- `buildCodexAppServerTurnInterruptRequest`
- `mapCodexAppServerNotification`
- `mapCodexAppServerApprovalRequest`
- `buildCodexAppServerApprovalResponse`

If real app-server traffic differs from these helpers, fix the helpers before
building the handle.

## Phase 3: Daemon Registration And Fallback

Extend supported conversation adapters to include:

```text
codex-app-server
```

Register both conversation adapters:

```text
codex-app-server -> CodexAppServerConversationAdapter
codex -> CodexConversationAdapter
```

The daemon should expose `codex-app-server` in adapter capabilities with a
clear display name and effective approval support:

```text
longLivedProcess: true
waitingInput: false
waitingApproval: true
resume: true
partialOutput: true
toolEvents: true
mobileApprovalCallbacks: true
approval:
  mobileCallbacks: true
  scopes: [once, session]
  supportsCancel: true
  denyBehaviors: [interrupt, continue]
attachments:
  image: native
  textDocument: text_extract
  pdf: unsupported
```

The scopes and deny behaviors are upper bounds. Each approval request must still
derive request-level metadata from app-server-native decisions.

Fallback should happen only before any app-server turn is sent. A fallback
conversation should emit a generic system notice such as:

```text
noticeKind: adapter_fallback
requestedAdapter: codex-app-server
effectiveAdapter: codex
reason: <sanitized reason>
```

The notice should be generic so future adapters can reuse it.

## Phase 4: Regression Tests

After real smoke samples exist, add fake transport tests to default
`node scripts/run-tests.js`.

Required daemon tests:

- capability detection marks `codex-app-server` available only when initialize
  and required methods are supported;
- unavailable app-server falls back to `codex` before first turn;
- fallback records requested/effective adapter identity;
- fallback does not occur after a turn has started;
- stdio JSONL transport routes request ids correctly;
- notifications project into generic conversation events;
- approval server requests become generic blocking approval items;
- approval responses write correct JSON-RPC responses;
- cancel sends `turn/interrupt`;
- app-server transport errors map to `run.error` or `protocol.warning`;
- raw provider payloads are not persisted into normal conversation events.

Required compatibility tests:

- existing `codex` exec adapter behavior remains unchanged;
- existing mobile reducers can consume app-server-projected generic events;
- older mobile parsers ignore added conversation fields such as
  `requestedAdapter` and `effectiveAdapter`;
- attachment capability versioning remains stable for `codex` and distinct for
  `codex-app-server`.

Real app-server smoke should remain opt-in and environment-gated because it
depends on the local Codex checkout, Rust build state, auth, and network/model
availability.

## Data Flow

New conversation, app-server available:

1. Mobile creates a conversation with `adapter=codex-app-server`.
2. Daemon detects app-server capability.
3. Daemon starts private app-server transport and initializes it.
4. First user message sends `thread/start`, stores returned or notified
   `threadId` as `cliSessionId`, then sends `turn/start`.
5. App-server notifications are projected into generic conversation events.
6. Completion moves the conversation to a reusable idle/completed state.

Resume:

1. The conversation has `cliSessionId=<app-server thread id>`.
2. The adapter sends `thread/resume`.
3. The adapter sends `turn/start` for the new user message.
4. Notifications continue through the same projection.

Approval:

1. App-server sends a server-initiated approval request.
2. Adapter maps it to `approval.requested` with generic options.
3. ConversationManager enters `waiting_approval`.
4. Mobile sends provider-neutral approval response.
5. Adapter converts it to Codex-native JSON-RPC response and resolves the
   pending server request.

Fallback:

1. Mobile creates a conversation with `adapter=codex-app-server`.
2. Capability or early startup fails before a turn is sent.
3. Daemon starts the existing `codex` adapter instead.
4. Public conversation retains `adapter/requestedAdapter=codex-app-server` and
   sets `effectiveAdapter=codex`.
5. Mobile uses generic capabilities and events from the effective adapter.

## Error Handling

- `codex app-server` command missing: fallback before first turn.
- initialize rejected: fallback before first turn.
- app-server version lacks required stable methods: fallback before first turn.
- app-server requires experimental API for fields we need: mark unsupported
  unless the design explicitly enables `experimentalApi` after smoke proves it
  is safe.
- transport closes before first turn: fallback.
- transport closes after first turn: `run.error`, no replay.
- unsupported server request: reject the JSON-RPC request with a sanitized
  error and emit `protocol.warning` unless it blocks the active turn.
- approval request cannot be mapped safely: reject the request and emit
  `run.error` for the active turn.
- stderr logs: preserve in daemon diagnostics; only emit `protocol.warning` for
  actionable non-secret protocol noise.
- cancellation while transport is alive: send `turn/interrupt`.
- cancellation after transport is gone: clean local state and emit
  `conversation.cancelled`.

## Security

- Do not expose raw provider approval payloads in normal mobile events.
- Redact local home paths, auth tokens, environment blocks, and raw provider
  diagnostics from fixtures and persisted events.
- Do not show session-scoped approval unless request-level metadata proves the
  app-server can honor it.
- Do not map `cancel` to `deny` unless request-level metadata says native
  cancel is unavailable.
- Do not enable experimental app-server APIs by default. Enable only if Phase 1
  proves a required stable field is missing and the risk is accepted.
- Treat `thread/start` project trust side effects as a migration risk:
  upstream docs say app-server can mark a project trusted when `cwd` and
  elevated sandbox are used. This must be accepted or mitigated before making
  app-server the default Codex adapter.

## Open Questions For Phase 1

- Does stdio app-server on Windows behave cleanly enough for long-lived daemon
  use, including shutdown and stderr handling?
- Which app-server response or generated schema should be used as the minimum
  version/capability gate?
- Is stable API sufficient for command approval, file approval, permissions
  approval, image input, model selection, and cancellation?
- What exact app-server message sequence represents a successful completed
  turn?
- What exact message sequence represents an interrupted turn?
- What happens when app-server requests approval and the client disconnects?
- Does app-server preserve enough thread/session metadata to make
  `cliSessionId` a reliable resume token?

## Completion Criteria

The adapter is ready to become selectable when:

- real app-server smoke has produced sanitized fixtures;
- fake transport regression tests are based on those fixtures;
- default `npm test` passes;
- `codex` exec adapter tests still pass unchanged;
- mobile can select `codex-app-server` without adapter-specific UI branches;
- fallback to `codex` works before first turn;
- no automatic fallback happens after a turn starts;
- approval requests round-trip through mobile and back to app-server;
- cancellation sends `turn/interrupt` and cleans local resources;
- project trust behavior has a documented accepted mitigation or risk.

## Future Merge Path

After the standalone adapter is stable, a later design can make `codex` the
single public adapter id. At that point:

- `codex` can prefer app-server when capability detection passes;
- `codex` can fall back to `exec --json` when app-server is unavailable;
- mobile can hide `codex-app-server` from normal adapter selection;
- existing conversations with `adapter=codex-app-server` remain readable
  because event storage uses generic event contracts.
