# Codex App Server API Parity Design

Date: 2026-06-04
Status: Draft for review

## Problem

The `codex-app-server` adapter currently supports the minimum path needed for
mobile conversations: start or resume a thread, start or interrupt a turn, map
streaming item notifications into conversation events, answer approval server
requests, and expose `model/list` through `/api/adapters`.

That is not full parity with the official Codex app-server API. The official
app-server surface is a JSON-RPC API with generated TypeScript and JSON Schema
contracts, and it covers much more than conversation streaming. It includes
thread management, model discovery, command and file operations, MCP, skills,
plugins, apps, configuration, authentication or account status, remote control,
platform and sandbox capabilities, and experimental APIs.

The daemon needs a source-of-truth alignment layer so future work does not keep
adding one-off method calls such as `model/list` directly inside listing or
conversation adapters.

## Goals

- Track the complete official Codex app-server API surface in a daemon-owned
  capability matrix.
- Make the generated official schema the source of truth for method names,
  request shapes, response shapes, notifications, and server requests.
- Introduce a typed daemon service boundary for Codex app-server JSON-RPC calls.
- Preserve the existing mobile conversation contract and streaming behavior.
- Keep `assistant.partial` and other incremental output as first-class events.
- Define a phased implementation path that can align all official APIs without
  requiring immediate mobile UI support for every feature.
- Route high-risk app-server methods through existing daemon authorization,
  workspace ownership, approval, diagnostics, and audit boundaries.

## Non-Goals

- Do not implement the mobile UI for every app-server API in this design.
- Do not expose an unrestricted raw JSON-RPC tunnel to mobile clients.
- Do not remove the existing `codex` CLI adapter or local fallback behavior.
- Do not collapse app-server events into final assistant messages. Streaming
  deltas must stay available to mobile and persisted history.
- Do not rely on manually copied method lists as the long-term source of truth.
- Do not run quota-consuming or side-effecting app-server operations from
  passive diagnostics.

## Current Local State

Current local support is concentrated in these files:

- `daemon/src/codex-app-server-transport.js`
- `daemon/src/codex-app-server-lifecycle.js`
- `daemon/src/codex-app-server-availability.js`
- `daemon/src/codex-app-server-listing-adapter.js`
- `daemon/src/codex-app-server-conversation-adapter.js`
- `daemon/src/codex-app-server-bridge.js`
- `daemon/src/codex-app-server-approval.js`
- `daemon/src/main.js`

The adapter already covers:

- JSONL JSON-RPC transport with requests, notifications, server requests,
  responses, protocol warnings, and close handling.
- App-server process lifecycle and shutdown.
- `initialize` and `initialized`.
- `thread/start` and `thread/resume`.
- `turn/start` and `turn/interrupt`.
- `model/list` for adapter model capability.
- `item/agentMessage/delta` as `assistant.partial`.
- `item/commandExecution/outputDelta` as `tool.delta`.
- `thread/started`, `turn/started`, `turn/completed`,
  `turn/plan/updated`, `item/started`, `item/completed`, and `error`
  notification mapping.
- Approval server requests:
  `item/commandExecution/requestApproval`,
  `item/fileChange/requestApproval`, and
  `item/permissions/requestApproval`.

The current implementation does not model the full official API surface. It
also places some method knowledge directly in listing and conversation adapter
code instead of a reusable app-server client layer.

## Official Contract Source

Codex app-server exposes generated contracts. The daemon parity workflow should
depend on those generated artifacts rather than a hand-maintained method list.

The local development baseline verified for this design is:

```powershell
codex --version
# codex-cli 0.137.0
```

That version exposes and successfully runs the app-server protocol generators:

```powershell
codex app-server generate-ts --experimental --out <DIR>
codex app-server generate-json-schema --experimental --out <DIR>
```

`--experimental` is required for parity tracking because the official app-server
surface separates stable and experimental protocol members. The matrix must
record stability per method rather than silently excluding experimental rows.

The generated output should be checked into a daemon-local contract fixture or
used to update a committed capability manifest. The implementation can choose
the exact storage path, but it should keep generated source separate from
handwritten adapter code. A suitable layout is:

```text
daemon/src/codex-app-server/
  client.js
  methods.js
  normalizers.js
  capability-matrix.js
daemon/test/fixtures/codex-app-server/
  schema.json
  methods.json
```

The generated contract should be treated as the authority for:

- Client-to-server request method names and payload shapes.
- Server-to-client notification method names and payload shapes.
- Server request methods that require daemon responses.
- Stable versus experimental API classification.
- Deprecation or rename detection.

If a future local environment cannot run the generators, Phase 1 must not
silently proceed with stale method knowledge. The fallback is:

1. Record the installed `codex --version` and generator failure in the PR.
2. Use the latest committed fixture as the comparison base.
3. Mark the fixture source version and generation date in
   `daemon/test/fixtures/codex-app-server/README.md`.
4. Keep the matrix update test active against that fixture.
5. Treat generator recovery as required before claiming parity with a newer
   installed Codex version.

## Architecture

### `CodexAppServerClient`

Add a daemon-owned typed client around `CodexAppServerJsonlTransport`.

Responsibilities:

- Initialize the transport once per app-server process.
- Provide one method per supported official app-server operation.
- Apply method-specific timeouts and error normalization.
- Validate or normalize responses against generated schema where practical.
- Centralize method names so conversation/listing adapters do not hard-code
  JSON-RPC strings.
- Expose notification and server-request subscriptions without hiding raw
  payloads needed for forward-compatible event mapping.

The first implementation can stay CommonJS and lightweight. It does not need a
runtime schema validator for every request on day one, but the method registry
must make missing methods visible in tests.

Client lifetime is process-handle scoped, not a daemon singleton. Each
`CodexAppServerLifecycle.spawn()` handle owns one transport and one
`CodexAppServerClient`. The client becomes invalid when the transport closes or
the process handle shuts down. Reuse happens by reusing a live scoped process
handle, not by reattaching a client to a new transport.

If the app-server process exits, crashes, or is killed, pending client requests
fail, the owning adapter or service disposes the handle, and a future operation
creates a new process handle and client. The client must guard against duplicate
initialization by tracking an `initialize()` promise per process handle; parallel
callers share that promise, and failed initialization invalidates the client.
All callers waiting on a failed initialization receive the same rejection. They
must not retry through the invalidated client; retry is an upper-layer concern
that creates a new lifecycle process handle and client.

### Method Registry And Capability Matrix

Add a daemon registry that compares generated official methods against local
support status.

Each method entry should track:

- `method`: official JSON-RPC method name.
- `direction`: request, notification, or server request.
- `stability`: stable or experimental.
- `category`: lifecycle, model, thread, turn, item, command, file, MCP, skill,
  plugin, app, config, auth, sandbox, remote-control, diagnostics, or unknown.
- `localStatus`: supported, partial, planned, diagnostic-only, unsupported, or
  intentionally-blocked.
- `daemonOwner`: client, conversation adapter, listing adapter, server route,
  diagnostics, or none.
- `mobileStatus`: consumed, protocol-only, planned, or not planned.
- `risk`: none, read, write, process, account, network, or permission.
- `testRequirement`: unit, integration fake transport, route test, mobile
  contract test, or manual-only.

The matrix should be exposed in daemon diagnostics so app-server drift is
visible without reading code.

Matrix lifecycle rules:

- Generated schema is the input; handwritten matrix rows are the reviewed
  classification layer.
- A sync script should add newly discovered official methods with
  `localStatus: unsupported`, `mobileStatus: not planned`, `risk: unknown`, and
  `daemonOwner: none`.
- A PR may change `unsupported` to `planned`, `partial`, `supported`,
  `diagnostic-only`, or `intentionally-blocked` only with a short rationale.
- A PR that changes a row from `unsupported` to any more active status must also
  replace `risk: unknown` with a concrete risk classification. Matrix lint
  should fail active rows that still have unknown risk, even when the row is not
  mobile-accessible yet.
- Experimental methods are included by default when the generator output was
  produced with `--experimental`; their `stability` field must remain
  `experimental`.
- Deprecated or removed official methods should stay in the matrix for one
  release cycle as `intentionally-blocked` or `deprecated`, with the schema
  version that removed them, before deletion.
- Tests should fail on missing rows, duplicate method rows, invalid enum values,
  and any `risk: unknown` row that is marked mobile-accessible.

### Conversation Adapter

`CodexAppServerConversationAdapter` should remain the bridge between official
app-server conversation semantics and the product's conversation event model.

It should delegate JSON-RPC calls to `CodexAppServerClient`:

- `initialize`
- `thread/start`
- `thread/resume`
- `turn/start`
- `turn/interrupt`
- approval responses

It should keep the existing side-effect boundary: fallback to the CLI adapter is
allowed before app-server provider side effects, but not after a thread start or
resume request has been sent.

The boundary is crossed when the daemon successfully writes a provider-side
request that may create, resume, mutate, interrupt, or otherwise affect a Codex
app-server thread or turn. For conversation startup, this means:

- `spawn` failure and `initialize` failure are pre-boundary and may fall back.
- Failure while building local request payloads is pre-boundary and may fall
  back.
- Once `thread/start` or `thread/resume` has been written to the transport,
  fallback is no longer allowed, even if the provider later returns a JSON-RPC
  error, times out, or closes before responding.

This preserves provider identity and avoids creating a second CLI conversation
after app-server may already have created or touched a thread.

It should keep streaming deltas unchanged. Dense `assistant.partial` history is
a mobile replay/windowing concern, not a daemon filtering concern.

### Listing And Capability Adapter

`CodexAppServerListingAdapter` should use the typed client for discovery calls,
starting with `model/list`.

Availability probes must remain cheap. They should prove app-server can start,
initialize, and speak the expected protocol, but they should not make expensive
or side-effecting discovery calls. Model listing can run when `/api/adapters`
needs model capability and the adapter is already selectable.

### Daemon HTTP Routes

Existing product routes such as `/api/adapters`, `/api/conversations`, and
`/api/conversations/:id/control` should stay product-level routes. They should
not become raw app-server mirrors.

For non-conversation APIs, add typed daemon routes only when a mobile or
diagnostic consumer needs them. Examples:

- `/api/adapters/codex-app-server/capability-matrix`
- `/api/codex-app-server/models`
- `/api/codex-app-server/threads`
- `/api/codex-app-server/mcp/servers`
- `/api/codex-app-server/skills`
- `/api/codex-app-server/plugins`
- `/api/codex-app-server/apps`
- `/api/codex-app-server/config`

Routes must enforce existing pairing auth and workspace authorization. Any
route that can read files, write files, run commands, alter process state,
change permissions, or expose account details needs an explicit risk review
before it becomes mobile-accessible.

`/api/adapters` remains the product-level adapter listing and model-picker
source. It should return normalized model choices suitable for existing mobile
UI. `/api/codex-app-server/models`, if added, is an app-server-specific
diagnostic or advanced discovery route that returns richer protocol metadata.
Both routes must call the same typed app-server model service so selected model
ids, labels, and availability cannot drift.

### Diagnostic Raw RPC

A restricted raw RPC endpoint may be added only for development diagnostics.

Rules:

- Disabled by default outside development mode.
- Requires paired device auth.
- Denies high-risk method categories unless an explicit allowlist enables them.
- Logs method name, category, risk, workspace id, and device id.
- Redacts secrets in errors and diagnostics.
- Never becomes the main mobile product contract.

### Process Reuse For Discovery

Discovery APIs should not blindly start a fresh app-server process for every
request once Phase 4 adds frequent routes such as models, MCP servers, skills,
plugins, apps, config, and sandbox discovery.

The service should support a small scoped process cache:

- Key by app-server invocation, workspace scope when required, and stability
  mode, including whether experimental methods are enabled.
- Reuse only initialized, healthy, idle clients.
- A client with an active conversation turn, pending high-risk operation, or
  unresolved server request is not idle.
- Use a short TTL, initially 30 seconds, for read-only discovery.
- Never reuse a discovery client for active conversation turns.
- Never share a high-risk operation process with passive discovery unless the
  implementation proves state isolation.
- On transport close or protocol error, evict the process handle immediately.

Phase 1 and Phase 2 can keep one short-lived process per operation. Phase 4 must
choose and test the reuse policy before adding frequently-polled discovery
routes.

## API Coverage Matrix

The exact rows should be generated or checked against official schema during
implementation. This design defines the required categories and initial local
status.

| Category | Examples | Current Local Status | Target |
| --- | --- | --- | --- |
| Lifecycle | `initialize`, `initialized` | supported | typed client wrapper |
| Models | `model/list` | supported after latest local changes | typed discovery API |
| Thread lifecycle | `thread/start`, `thread/resume` | supported | typed client wrapper |
| Thread management | list, read, fork, archive, metadata, settings, goal | mostly missing | daemon typed routes, no UI required initially |
| Turn lifecycle | `turn/start`, `turn/interrupt`, started/completed notifications | supported | typed client wrapper plus schema coverage |
| Turn history/control | compact, rollback, shell command, status/read variants | missing or unknown locally | matrix first, typed APIs by risk |
| Item stream | agent message deltas, command output deltas, item start/complete | partial | preserve raw payloads and expand mappings |
| Command/process | shell command, process status/control, output streaming | partial through conversation items only | high-risk typed APIs with approval gates |
| File operations | file change items and approval requests | partial | map official file APIs through workspace authorization |
| Approvals/permissions | command, file change, permission server requests | supported | schema-backed responses and timeout policy |
| MCP | servers, tools, resources, prompts, reconnect/toggle | missing for app-server; separate local controls exist | app-server MCP discovery and control APIs |
| Skills | skill list/discovery/invoke/config | missing | discovery first, execution only after risk review |
| Plugins | plugin list/status/config | missing | discovery/config route after schema alignment |
| Apps | app list/status/control | missing | discovery route first |
| Config | read/update app-server config | missing | read-only first, write requires explicit authorization |
| Auth/account | login/account/status/auth diagnostics | missing | read-only status only unless separately approved |
| Sandbox/platform | Windows sandbox, platform capability, policy details | partial hard-coded policy | typed policy builder and diagnostics |
| Remote control | remote command/control APIs | missing | diagnostic-only until product need is approved |
| Experimental APIs | generated experimental surface | not tracked | matrix rows default to planned or blocked |

## Phasing

### Phase 1: Contract And Matrix

- Generate or fixture official app-server TypeScript/JSON schema.
- Build method registry from generated schema.
- Add committed capability matrix with local status.
- Add tests that fail when official methods are missing from the matrix.
- Keep existing runtime behavior unchanged except for routing method constants
  through the registry where low-risk.
- Acceptance tests must prove generator output or fixture loading works,
  generated methods are fully represented in the matrix, new methods get safe
  default statuses, and invalid matrix enum values fail.

### Phase 2: Typed Client For Existing Behavior

- Introduce `CodexAppServerClient`.
- Move `initialize`, `model/list`, `thread/start`, `thread/resume`,
  `turn/start`, `turn/interrupt`, and approval response helpers behind the
  client.
- Keep existing fallback and side-effect-boundary behavior.
- Keep all current event mappings and streaming deltas.
- Acceptance tests must prove existing app-server conversation and model-list
  tests pass through the client, duplicate initialization is single-flight, and
  fallback is disallowed after a thread request is written.

### Phase 3: Thread And History Parity

- Add typed daemon support for non-side-effecting thread APIs such as list,
  read, metadata, settings read, and history fetch.
- Add support for fork/archive/unarchive only after workspace authorization
  semantics are explicit.
- Avoid mobile UI work except protocol DTOs or contract fixtures needed for
  tests.
- Acceptance tests must cover route auth, workspace authorization, response
  normalization, schema drift handling, and no UI dependency on these routes.

### Phase 4: Discovery Surfaces

- Add app-server MCP, skills, plugins, apps, model, config, sandbox, and platform
  discovery routes.
- Prefer read-only discovery first.
- Expose route-level capability metadata so mobile can hide unsupported controls
  until UI work catches up.
- Acceptance tests must cover discovery process reuse or explicit non-reuse,
  TTL eviction, transport-close eviction, shared model service behavior between
  `/api/adapters` and app-server model routes, and read-only enforcement.

### Phase 5: High-Risk Operations

- Add command, process, file write, config write, remote-control, and permission
  mutation APIs only behind explicit product authorization and approval flows.
- Reuse the existing conversation approval queue where possible.
- Add audit logging for device, workspace, method, decision, and result.
- Acceptance tests must cover default denial, approval-required paths, audit
  records, workspace isolation, secret redaction, and downstream failure
  behavior when the app-server returns JSON-RPC errors after the daemon has
  authorized an action. Authorized downstream failures must write an audit
  record and return a controlled, redacted error to mobile; they must not be
  swallowed or converted to success.

### Phase 6: Mobile Consumption

- Add mobile repositories and UI only after daemon APIs are stable.
- Keep mobile changes feature-local under `mobile/lib/src/ui/features`.
- Do not expand mobile protocol barrels unless preserving existing public import
  surfaces requires it.
- Acceptance tests must cover repository DTO parsing, ViewModel state for each
  consumed route, and preservation of existing conversation/model-picker flows.

## Data Flow

### Conversation Flow

1. Mobile calls existing conversation routes.
2. `ConversationManager` selects `codex-app-server`.
3. `CodexAppServerConversationAdapter` obtains a process handle from lifecycle.
4. The adapter creates `CodexAppServerClient`.
5. The client initializes the app-server transport.
6. The adapter starts or resumes a thread.
7. The adapter starts turns and maps notifications/server requests to daemon
   conversation events.
8. `EventStore` persists visible and hidden events unchanged.
9. Mobile reads events through existing REST and WebSocket notification paths.

### Discovery Flow

1. Mobile or diagnostics calls a typed daemon route.
2. The route authenticates the paired device and resolves workspace scope where
   needed.
3. The app-server service reuses or starts a scoped app-server process according
   to the discovery process reuse policy.
4. The typed client calls a read-only official method.
5. The daemon normalizes the response into product DTOs and includes raw method
   metadata only in diagnostics-safe fields.

### High-Risk Operation Flow

1. Mobile calls a typed daemon route.
2. The route checks workspace ownership and method risk category.
3. If the operation can mutate files, run commands, alter process state, change
   permissions, or expose account data, the route requires an explicit approval
   policy.
4. The app-server client sends the official request only after policy checks.
5. Results and failures are audited and redacted before returning to mobile.

## Error Handling

- Transport-level failures should include method name, timeout, and sanitized
  stderr snippets.
- Official JSON-RPC errors should preserve error code and safe data fields.
- Schema mismatch should become a protocol warning for notifications and a
  request failure for direct method calls.
- Unknown official notifications should remain persisted in raw diagnostic
  payloads until mapped or intentionally ignored.
- Unsupported server requests should fail closed and produce visible run errors
  for active conversations.
- Side-effect boundary rules must remain explicit for fallback behavior.

## Security And Authorization

- All mobile-facing routes require existing daemon auth.
- Workspace-scoped methods require workspace authorization for the paired device.
- Raw app-server RPC is disabled by default and development-only.
- Account/auth/config endpoints are read-only until separately approved.
- File write, command, process, remote-control, sandbox mutation, and permission
  mutation endpoints require explicit risk entries in the capability matrix.
- Errors and diagnostics must redact API keys, bearer tokens, user-home paths,
  and other local secrets.
- Passive diagnostics must not execute quota-consuming, network-heavy, or
  side-effecting app-server operations.

## Testing

Daemon tests should cover:

- Method registry generation or fixture loading.
- Every official method appears in the capability matrix.
- Existing app-server conversation tests continue passing through the typed
  client.
- `model/list` still initializes app-server and normalizes model capability.
- Availability probes stay cheap and avoid model/discovery RPCs.
- Unknown notifications are preserved as diagnostics without breaking streams.
- Unsupported server requests fail closed.
- High-risk methods are blocked unless explicitly allowed.
- Raw diagnostic RPC is disabled outside development mode.
- Sanitization redacts secrets in app-server errors and metrics.
- Phase 3 thread/history routes enforce auth and normalize schema-backed
  responses.
- Phase 4 discovery routes share source services with product routes, enforce
  read-only behavior, and test process reuse or TTL eviction.
- Phase 5 high-risk operation routes deny by default, require approval where
  configured, write audit records, and redact sensitive error data.

Mobile tests are deferred unless daemon route DTOs change existing mobile
contracts. Later mobile phases should add repository and ViewModel tests for
each consumed daemon route.

## Verification Commands

Commands in this document are written for the project's verified Windows
PowerShell environment. Cross-platform CI or developer workflows can use the
same Node and Dart entry points with platform-native path separators.

For daemon-only phases:

```powershell
node scripts/run-tests.js
npm run lint
node scripts/check-project-knowledge.js
```

For later mobile-consuming phases:

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\widget_test.dart
```

## Open Implementation Notes

- The implementation plan should inspect the generated app-server schema before
  writing the final method rows. The category table in this design is the
  required shape, not a substitute for the generated contract.
- If official method names differ from the examples above, the generated schema
  wins and the matrix should use official names.
