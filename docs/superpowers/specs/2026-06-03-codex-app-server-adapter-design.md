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

`GET /api/adapters` should list both when the feature is enabled and lightweight
probing says app-server is selectable. Mobile can render them as separate
choices during the validation period. Once app-server is stable, a future
design can merge them behind `codex` with app-server preferred and `exec
--json` as fallback.

When a user creates a conversation with `adapter=codex-app-server`, the daemon
should try to use app-server. If app-server capability detection or early
startup fails before any provider/project/thread side-effect boundary is
crossed, the daemon should automatically fall back to the existing `codex`
adapter. The public conversation should carry both requested and effective
adapter identity:

```text
adapter: codex-app-server
requestedAdapter: codex-app-server
effectiveAdapter: codex | codex-app-server
```

During the transition, `adapter` should preserve the user-requested adapter id
so mobile does not see the selected tool mutate after creation. Runtime
behavior, capabilities, and attachment handling should use `effectiveAdapter`.

Field authority:

| Field | Meaning | Authoritative for | Notes |
| --- | --- | --- | --- |
| `adapter` | Backward-compatible selected adapter id. During this migration it equals the requested adapter id. | Existing mobile display, filtering, and older clients. | Do not use for runtime capability decisions when `effectiveAdapter` exists. |
| `requestedAdapter` | Explicit adapter id requested by the caller. | Explaining fallback and preserving user intent. | New clients should prefer this over inferring requested intent from `adapter`. |
| `effectiveAdapter` | Adapter that actually owns the active handle and event/capability behavior. | Runtime capability, attachment handling, approval support, diagnostics, and test assertions. | If omitted for older conversations, consumers should treat `effectiveAdapter = adapter`. |

`adapter` and `requestedAdapter` are intentionally redundant at first to avoid
breaking older mobile clients while giving new clients an unambiguous field.
Once mobile and stored data no longer depend on the legacy ambiguity, a later
cleanup can decide whether `adapter` should become an alias, be deprecated, or
switch to effective identity.

Fallback boundary:

| Stage | Automatic fallback to `codex`? | Reason |
| --- | --- | --- |
| Feature disabled before probing | Yes | No app-server state exists. |
| App-server command missing or spawn fails | Yes | No provider/project/thread side effect exists. |
| Initialize fails before any other request | Yes | No thread or turn request has been sent. |
| Lightweight capability probe fails before `thread/start` | Yes | Probe must not create provider/project/thread state. |
| Any request that may create provider/project/thread state has been sent | No | App-server may already have persisted thread, trust, auth, or runtime state. |
| `thread/start` has been sent | No | Upstream docs say `thread/start` can persist project trust. |
| `turn/start` has been sent | No | Replaying can duplicate model/tool/file behavior. |
| `thread/started` has been received | No | Provider-side thread state exists. |
| Any approval request, tool event, file-change event, or mutation-related event has been seen | No | Replaying can cause double execution or inconsistent UI state. |

Once fallback is forbidden, the adapter should emit a generic `run.error`,
clean up transport state, and let the user explicitly retry or create a new
fallback conversation. It must not replay the same user request through `codex
exec --json`.

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

## Adapter Availability Contract

`GET /api/adapters` must distinguish install visibility from runtime
readiness. Listing adapters should not spawn a long-lived app-server, send
`thread/start`, call `turn/start`, or perform any request that can create
provider/project/thread side effects.

The adapter list may run a lightweight probe with a short TTL cache. The probe
may check command presence, version/schema availability, generated schema
support, and a bounded initialize-compatible health check only if it does not
create thread/project state. It must not keep the probe transport as a hidden
long-lived conversation handle.

`codex-app-server` adapter status should include:

```text
installed: boolean
protocolCompatible: boolean
transportHealthy: boolean
selectable: boolean
lastProbeAt: timestamp | null
unavailableReason: sanitized string | null
effectiveCapabilities: CapabilityBlock
```

Field meanings:

- `installed`: the `codex` command and app-server subcommand are discoverable.
- `protocolCompatible`: the tested schema/version supports the stable methods
  this adapter requires.
- `transportHealthy`: the lightweight probe can initialize and close cleanly
  within its timeout without creating app-server thread state.
- `selectable`: mobile may show the adapter as a selectable option. It is true
  only when the feature flag is enabled and the other availability fields pass.
- `effectiveCapabilities`: the capability block mobile should use for this
  adapter status. It must be lowered when probes prove a target capability is
  unavailable.

Probe failures can still leave `codex-app-server` visible for diagnostics, but
not selectable. Conversation creation should not rely on mobile to retry with
`codex`; when creation requested `codex-app-server` and fallback is still inside
the side-effect-free boundary, daemon fallback remains responsible.

Auth/model/network failures after a turn starts are run failures, not adapter
unavailability. Auth/model/schema failures found by side-effect-free probes can
make `selectable=false` with a sanitized `unavailableReason`.

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

The `--kill` flag is used by the upstream test client to stop an existing test
server on the chosen websocket endpoint before starting a fresh one.
Because it can terminate an existing server on that endpoint, smoke runs should
use an isolated environment or a reserved/random local port instead of assuming
`4222` is free on a shared developer machine or CI host.

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
- terminal turn notifications for completed, interrupted, and failed turns,
  including whether each sequence should leave the conversation resumable,
  idle, completed, cancelled, or failed in this daemon's state model
- JSON-RPC error response
- transport close/disconnect

The output of this phase should be a small fixture set or documented transcript
under this repository, with secrets, local home paths, auth tokens, and raw
provider diagnostics redacted. Later fake transport tests must be based on
these real samples, not imagined protocol shapes.

The smoke phase must also answer:

- Whether stdio is sufficient for the daemon-owned private process path.
- Whether websocket is needed only for manual testing.
- Whether Windows stdio can sustain a long-lived initialized app-server
  connection without deadlocking, leaking child processes, corrupting JSONL
  framing, or losing server-initiated approval requests.
- Whether Windows stdio remains healthy across at least: one completed turn,
  one approval round trip, one cancellation, one resume, and one clean daemon
  disposal.
- If Windows stdio fails the stability check, the production adapter must not
  use stdio by default. The fallback transport decision should be: first try a
  private loopback websocket child process bound to `127.0.0.1` with a random
  port and daemon-owned lifetime; if that is not acceptable after smoke, keep
  app-server unavailable and use the existing `codex` exec fallback.
- Which initialize capabilities should be enabled. The default should be stable
  API only unless a required approval field is experimental.
- Whether `experimentalApi: true` is required for the metadata needed by mobile
  approvals.
- How app-server reports unsupported versions and unsupported methods.
- What app-server writes to stderr and how noisy logs should map to daemon
  diagnostics.

Phase 1 pass/fail thresholds:

- Run at least 10 sequential completed turns over the candidate transport with
  no deadlock, lost JSON-RPC response, dropped terminal notification, or
  orphaned child process.
- Run at least 3 approval round trips. Each request must appear in daemon logs,
  become exactly one blocking item, receive exactly one JSON-RPC response, and
  complete or fail the active turn deterministically.
- Approval response latency added by daemon transport handling should stay
  below 2 seconds at p95 in local smoke, excluding user think time and model
  time.
- Cancellation must send `turn/interrupt` and the app-server child must exit
  gracefully within 5 seconds on dispose, or be force-killed within a documented
  hard-kill deadline.
- Large stdout/stderr conditions must not block either pipe: run at least one
  command that emits enough output to exercise output caps, and verify stdout
  JSONL frames remain parseable while stderr is drained.
- Initialize must complete within a configured timeout, recommended initial
  value 10 seconds, or mark the probe failed.
- No app-server child process may remain after smoke cleanup. Record process ids
  before/after cleanup as evidence.
- Side-effect-free probes must not create a persisted app-server thread, mark a
  project trusted, or write conversation history.

Failing any threshold keeps `codex-app-server.selectable=false` until the spec
or implementation adds a mitigation and repeats the smoke.

## Phase 2: Adapter Architecture

After Phase 1 proves the real transport and event contract, add:

```text
daemon/src/codex-app-server-conversation-adapter.js
```

Primary responsibilities:

- detect `codex app-server` availability and minimum protocol support;
- spawn a private `codex app-server` child process over the transport selected
  by Phase 1. Prefer stdio only if Windows long-connection smoke passes;
  otherwise use the selected fallback transport or keep app-server unavailable;
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

Process lifecycle:

- Start with one private app-server child process per active
  `codex-app-server` conversation handle. Do not introduce a daemon-wide pool in
  the first adapter; pooling can be designed later after lifecycle and trust
  behavior are proven.
- Enforce a maximum concurrent app-server process limit, controlled by config.
  When the limit is reached, new `codex-app-server` conversations should fail
  before side effects or fall back only if still inside the side-effect-free
  boundary.
- Apply idle TTL to initialized but inactive handles. On expiry, gracefully
  dispose the app-server child and keep the persisted conversation resumable via
  provider session metadata.
- Always drain stdout and stderr. stdout carries protocol frames; stderr is
  diagnostic-only and must not enter ordinary conversation events. Stderr may be
  exposed only through diagnostics or sanitized protocol warnings.
- Use bounded parsers and output caps so large command output or logs cannot
  grow memory unboundedly or block the child process pipes.
- Shutdown ladder: send graceful termination/dispose, wait a short timeout,
  send process kill, then hard-kill the process tree on Windows if needed.
- On daemon startup, run orphan cleanup for app-server children that were
  started by this daemon and recorded in daemon-owned lifecycle metadata.
- Every pending JSON-RPC request must have a timeout. Initialize, probe, normal
  request, approval response, interrupt, and dispose timeouts should be separate
  config values.
- When transport closes, reject all pending JSON-RPC requests with sanitized
  errors, clear or resolve active blocking items according to their type, and
  emit a generic `run.error` if the active turn cannot continue safely.

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
The capability block above is a target upper-bound shape, not a static value to
copy before smoke. Phase 1 must verify each advertised capability. If session
scope, cancel, continue-deny behavior, native image input, or any other listed
capability is not reachable with the real app-server version, Phase 3 must
lower or omit that capability before exposing `codex-app-server`.
`waitingInput: false` means the first adapter does not expose app-server
user-input server requests to mobile, even though app-server may define that
request family. If a later phase supports user-input requests, this capability
must change and the generic blocking input flow must be tested.
If Phase 1 proves stable app-server can produce user-input server requests
during ordinary turns, and the first daemon adapter still does not support
generic user-input blocking flow, `codex-app-server.selectable` must be false
until the user-input path is implemented or the triggering capability can be
disabled safely.

Conversation responses should always include:

```text
requestedAdapter
effectiveAdapter
effectiveCapabilities
fallbackNotice
```

`effectiveCapabilities` is the capability block for the active handle, not
merely the requested adapter. `fallbackNotice` is null unless fallback happened.
Compatibility tests must prove older mobile reducers do not crash or render
provider-backed approval affordances incorrectly when `adapter=codex-app-server`
but `effectiveAdapter=codex`.

Fallback should happen only before the side-effect-free boundary is crossed. A
fallback conversation should emit a generic system notice such as:

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
- unavailable app-server falls back to `codex` only before the
  side-effect-free boundary is crossed;
- fallback records requested/effective adapter identity;
- fallback does not occur after a turn has started;
- stdio JSONL transport routes request ids correctly;
- notifications project into generic conversation events;
- approval server requests become generic blocking approval items;
- approval responses write correct JSON-RPC responses;
- approval timeout behavior is explicit: if mobile does not respond before the
  daemon approval TTL, the daemon resolves or rejects the app-server request in
  the configured safe way and emits a generic cancellation/error event;
- concurrent approval behavior is explicit: if app-server can send multiple
  approval requests in one turn, the daemon queues or rejects them according to
  ConversationManager blocking semantics without losing request ids;
- cancel sends `turn/interrupt`;
- thread resume failure for stale or invalid `cliSessionId` maps to a generic
  recoverable error or fresh-start policy, and never silently starts an
  unrelated thread;
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

## Provider Session Contract

`cliSessionId` can remain as a backward-compatible display/resume token, but
app-server should persist structured provider session metadata:

```text
providerSession:
  provider: codex-app-server
  threadId: string
  protocolVersion: string
  cwd: string
  model: string | null
  sandboxProfile: string
  createdAt: timestamp
```

Resume must validate this metadata before sending `thread/resume`. If cwd,
protocol version, sandbox profile, or model constraints make resume unsafe, the
adapter should emit a recoverable generic error or require explicit fresh-start
behavior. It must not silently resume or start an unrelated thread.

## Attachment Contract

The target attachment capability block is:

```text
attachments:
  image: native
  textDocument: text_extract
  pdf: unsupported
```

Phase 1 must verify app-server `UserInput` support for local image paths,
including accepted MIME types, maximum file size, and maximum image count per
turn. Until those limits are known, `codex-app-server` should either inherit
the stricter current Codex image limits or mark native image input unavailable.

Text documents should continue to use daemon-side text extraction and the
existing `textAttachmentWrapper`, then send the result as text input. PDF is
unsupported and should be rejected by the generic attachment capability check
before upload/send when possible; if a stale client sends a PDF anyway, the
daemon should reject before `thread/start` or `turn/start`.

If a conversation falls back to `codex`, `effectiveCapabilities.attachments`
must switch to the existing `codex` attachment capabilities. Mobile should rely
on `effectiveCapabilities`, not the requested adapter name.

## Data Flow

New conversation, app-server available:

1. Mobile creates a conversation with `adapter=codex-app-server`.
2. Daemon detects app-server capability.
3. Daemon starts private app-server transport and initializes it.
4. First user message sends `thread/start`, stores returned or notified
   `threadId` as `cliSessionId`, then sends `turn/start`.
5. App-server notifications are projected into generic conversation events.
6. Terminal turn notifications move the conversation to the mapped daemon
   state. Phase 1 must distinguish resumable idle/completed outcomes from
   non-reusable failed/cancelled/interrupted outcomes instead of treating all
   terminal app-server statuses as one generic completion.

Resume:

1. The conversation has `cliSessionId=<app-server thread id>`.
2. The adapter sends `thread/resume`.
3. The adapter sends `turn/start` for the new user message.
4. Notifications continue through the same projection.

Approval:

1. App-server sends a server-initiated approval request.
2. Adapter maps it to `approval.requested` with generic options.
3. ConversationManager enters `waiting_approval`.
4. While waiting, non-blocking app-server notifications for the same turn
   should still be projected and persisted in order if they do not resolve or
   replace the blocking item. They must not clear `waiting_approval`. If Phase
   1 shows app-server can emit such notifications, tests must cover the exact
   ordering.
5. Mobile sends provider-neutral approval response.
6. Adapter converts it to Codex-native JSON-RPC response and resolves the
   pending server request.

Approval safety defaults:

- If an approval request cannot be mapped safely, do not show approval UI, do
  not downgrade it to allow/deny heuristics, reject the provider request, and
  emit `run.error` for the active turn.
- If mobile does not respond before the daemon approval TTL, default to the
  safest provider response proven by Phase 1. Prefer native `cancel` when
  available; otherwise prefer `decline`; otherwise reject the JSON-RPC request
  with a sanitized error. The chosen timeout policy must be documented in the
  Phase 1 fixture notes.
- If multiple approval requests arrive concurrently for the same turn, the
  first implementation should queue them only if ConversationManager can
  preserve request ids and blocking order. Otherwise reject later concurrent
  requests with a sanitized error and emit a protocol warning or run error
  according to whether the request is blocking.
- If transport closes while an approval UI is visible, resolve the blocking item
  with a generic cancellation/error event and prevent later mobile responses
  from being forwarded to a dead transport.
- Approval response submission should be idempotent by approval id/request id.
  Retrying the same response after successful resolution should return the
  stored result; retrying with a different response should return a conflict.
- If native cancel is unavailable for a request, mobile-visible
  `supportsCancel` must be false and the UI should hide cancel rather than map
  cancel to deny.

Fallback:

1. Mobile creates a conversation with `adapter=codex-app-server`.
2. Capability or early startup fails before any request that can create
   provider/project/thread side effects is sent.
3. Daemon starts the existing `codex` adapter instead.
4. Public conversation retains `adapter/requestedAdapter=codex-app-server` and
   sets `effectiveAdapter=codex`.
5. Mobile uses generic capabilities and events from the effective adapter.

## Error Handling

- `codex app-server` command missing: fallback before side effects.
- initialize rejected before any other request: fallback before side effects.
- app-server version lacks required stable methods during side-effect-free
  probe: fallback before side effects.
- app-server requires experimental API for fields we need: mark unsupported
  unless the design explicitly enables `experimentalApi` after smoke proves it
  is safe.
- transport closes before side effects: fallback.
- transport closes after `thread/start`, `turn/start`, or any provider event:
  `run.error`, no replay.
- unsupported server request: reject the JSON-RPC request with a sanitized
  error and emit `protocol.warning` unless it blocks the active turn. A request
  is considered blocking when it has the active `threadId`/`turnId` and belongs
  to a method family that requires a client response before Codex can continue
  the turn, such as approval, user input, attestation, or future elicitation
  requests. Unsupported blocking requests should become `run.error` for the
  active turn after the adapter rejects them.
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
- Do not show session-scoped approval unless both adapter-level capability and
  request-level metadata prove the app-server can honor it. For command and
  file-change approvals, the request must include `availableDecisions` with
  `acceptForSession`, or Phase 1 must document a stable non-experimental field
  that is equivalent. For permissions approvals, the request/response contract
  must support `scope: "session"` for that request kind. If the decisive field
  is absent, mobile-visible `supportsSessionScope` must be false.
- Do not map `cancel` to `deny` unless request-level metadata says native
  cancel is unavailable.
- Do not enable experimental app-server APIs by default. Enable only if Phase 1
  proves a required stable field is missing and the risk is accepted.
- Treat `thread/start` project trust side effects as a migration risk:
  upstream docs say app-server can mark a project trusted when `cwd` and
  elevated sandbox are used.
- App-server must not become the default Codex adapter until project trust side
  effects have one of these verified outcomes:
  - app-server can start turns with a sandbox/permission profile that does not
    persist project trust for the daemon's normal workspace-write flow;
  - the adapter can detect and prevent trust-persisting starts unless the user
    has explicitly opted in;
  - product policy explicitly accepts trust persistence for selected workspaces,
    and the daemon records an audit-visible notice when it may occur.
- The default production sandbox policy must be workspace-scoped and must not
  request full access or elevated persistent trust unless the user selected an
  explicit mode that already permits that behavior.

## Rollout And Kill Switches

The adapter must be guarded by daemon-side flags:

```text
CODEX_APP_SERVER_ENABLED=false
CODEX_APP_SERVER_TRANSPORT=auto|stdio|ws|off
CODEX_APP_SERVER_EXPERIMENTAL_API=false
CODEX_APP_SERVER_ROLLOUT_PERCENT=0
CODEX_APP_SERVER_MAX_PROCESSES=<bounded integer>
```

Defaults keep app-server disabled even after Phase 1. Selection requires all
of: `CODEX_APP_SERVER_ENABLED=1`, `CODEX_APP_SERVER_EXPERIMENTAL_API=1`,
`CODEX_APP_SERVER_TRANSPORT=auto|stdio`, and
`CODEX_APP_SERVER_ROLLOUT_PERCENT>0`. Operators can disable selection
immediately without changing mobile code. When disabled, `codex-app-server` may
appear as installed/unselectable for diagnostics, but normal mobile selection
should hide or disable it.

## Diagnostics And Metrics

At minimum, daemon diagnostics should record counters or structured log fields
for:

- `app_server_probe_success`
- `app_server_probe_failure`
- `app_server_spawn_failure`
- `app_server_initialize_latency`
- `fallback_before_first_request_count`
- `run_error_after_side_effect_boundary_count`
- `approval_requested_count`
- `approval_timeout_count`
- `approval_round_trip_latency`
- `transport_close_count`
- `orphan_process_cleanup_count`

These diagnostics should use sanitized reasons and must not include raw
provider payloads, credentials, environment blocks, or unredacted local paths.

## Open Questions For Phase 1

- Does stdio app-server on Windows behave cleanly enough for long-lived daemon
  use, including shutdown and stderr handling? Closed by Phase 1 stdio smoke:
  10 sequential turns, approval round trips, cancellation, large output, and
  child-process cleanup passed.
- Which app-server response or generated schema should be used as the minimum
  version/capability gate? Closed for first rollout by initialize plus
  `model/list`; selection is still controlled by explicit experimental and
  rollout flags rather than implicit adapter listing probes.
- Is stable API sufficient for command approval, file approval, permissions
  approval, image input, model selection, and cancellation? Partially closed:
  command approval, model list, turn start/completion, cancellation, and native
  image input are verified; file-change approval and permissions approval remain
  regression-covered by schema/bridge tests but need real server-request smoke
  before default rollout.
- What exact app-server message sequence represents a successful completed
  turn? Closed by `2026-06-03-stdio-basic-turn.json` and
  `2026-06-03-stdio-sequential-turns.json`.
- What exact message sequence represents an interrupted turn? Closed by
  `2026-06-03-stdio-cancellation.json`.
- What happens when app-server requests approval and the client disconnects?
  Closed for daemon behavior by fake-transport regression: transport close
  cancels visible blocking approval and emits `run.error`. A real disconnect
  smoke remains a pre-default-rollout hardening task.
- Does app-server preserve enough thread/session metadata to make
  `cliSessionId` a reliable resume token? Closed for the standalone adapter by
  `2026-06-03-stdio-resume-rejoin.json`, structured `providerSession`
  persistence, and resume-failure cleanup tests. Re-check this before merging
  the standalone route into the default `codex` adapter id.

## Completion Criteria

The adapter is ready to become selectable when:

- real app-server smoke has produced sanitized fixtures;
- fake transport regression tests are based on those fixtures;
- default `npm test` passes;
- `codex` exec adapter tests still pass unchanged;
- mobile can select `codex-app-server` without adapter-specific UI branches;
- fallback to `codex` works only before the side-effect-free boundary;
- no automatic fallback happens after a turn starts;
- approval requests round-trip through mobile and back to app-server;
- cancellation sends `turn/interrupt` and cleans local resources;
- project trust behavior has a verified mitigation, explicit opt-in gate, or
  accepted product policy plus audit-visible notice;
- session-scope approval rendering is backed by a concrete app-server field or
  capability documented by Phase 1;
- Windows stdio either passes the long-connection smoke or the adapter uses a
  documented fallback transport/unavailable policy.

## Future Merge Path

After the standalone adapter is stable, a later design can make `codex` the
single public adapter id. At that point:

- `codex` can prefer app-server when capability detection passes;
- `codex` can fall back to `exec --json` when app-server is unavailable;
- mobile can hide `codex-app-server` from normal adapter selection;
- existing conversations with `adapter=codex-app-server` remain readable
  because event storage uses generic event contracts.
- the `codex-app-server` adapter id should remain as a compatibility route for
  stored conversations and old clients until a migration explicitly proves no
  persisted conversation, shortcut, or mobile cache still references it.
