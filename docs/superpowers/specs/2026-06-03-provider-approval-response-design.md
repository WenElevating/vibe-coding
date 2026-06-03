# Provider Approval Response Design

Date: 2026-06-03
Status: proposed

## Context

The mobile workbench approval UI currently models an approval response as a
plain string decision, usually `allow` or `deny`. That is too small for the
providers we support.

The daemon already accepts richer conversation approval payloads through
`normalizeApprovalDecision()`: `decision`, `updatedInput`,
`updatedPermissions`, and `interrupt`. The Claude conversation adapter can
forward these richer values into the SDK control response. The mobile client,
however, still sends only `{ decision: string }`.

Codex was incorrectly treated as if it had no provider-side approval callback.
That is only true for the current `codex exec --json` adapter path in this
repository. Codex app-server exposes JSON-RPC approval requests and responses.
The locally generated stable TypeScript bindings from
`codex app-server generate-ts` include:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`
- `CommandExecutionApprovalDecision = "accept" | "acceptForSession" | ... | "decline" | "cancel"`
- `FileChangeApprovalDecision = "accept" | "acceptForSession" | "decline" | "cancel"`
- `PermissionGrantScope = "turn" | "session"`

The design must not hard-code the UI around the current CLI adapter limitation.
It should represent provider capabilities honestly and map user intent to each
provider's native protocol.

## Goals

- Render a Codex-style mobile approval prompt: question text, command or change
  preview, numbered options, and bottom actions for skip and submit.
- Support one-time approval, session-scoped approval, denial, and cancellation
  as distinct user intents.
- Gate session-scoped choices on provider capabilities and request metadata.
- Preserve provider-native approval metadata in daemon events so mobile can
  present the right options.
- Keep current `codex exec --json` behavior explicit: it does not support
  mobile approval callbacks.
- Add a path for a future Codex app-server-backed adapter that does support
  mobile callbacks.

## Non-Goals

- Do not fake `acceptForSession` for the existing `codex exec --json` adapter.
- Do not expose session-scoped approval UI when the provider did not offer or
  cannot honor that decision.
- Do not merge Claude and Codex native permission payloads into one lossy field.
- Do not rewrite unrelated workbench transcript or command-card behavior as part
  of this change.

## Selected Approach

Use a provider-neutral approval response model in mobile and daemon APIs, then
map it to provider-native decisions inside each adapter. Mobile must not send
provider-native decision names or objects.

This is preferred over a UI-only fix because the current two-button/string
contract cannot represent the behavior the UI is supposed to show. It is also
preferred over immediately replacing the Codex adapter because app-server
integration is a larger adapter change and should be isolated behind the same
approval contract.

## User Experience

When an approval is pending, the composer area is replaced by an approval panel.
The panel shows:

1. A direct question, for example "Allow this command?"
2. A command, file-change, or permission preview.
3. Numbered choices.
4. Bottom actions: skip and submit.

Default choices:

- `1. Yes` maps to a one-time allow.
- `2. Yes, do not ask again for similar requests this session` maps to a
  session-scoped allow. It is visible only when the event says the provider can
  honor session scope.
- `3. No, tell the assistant what to change` maps to deny with interrupt.

For providers that only support one-time allow or deny, the second option is
omitted and numbering remains compact.

Skip is shown only when the approval request advertises a native cancel
decision. If cancel is not available, the skip action is hidden instead of being
remapped to denial. This keeps one visible action from having different
provider-dependent behavior.

## Data Model

Add a mobile/domain approval response value object:

```text
ApprovalResponse
  decision: allow | deny | cancel
  scope?: once | session
  updatedInput: optional object
  updatedPermissions: optional list<object>
  interrupt: optional bool
```

`ApprovalResponse` is mobile-facing and provider-neutral. Mobile sets user
intent only. It never sets Codex-specific values such as `acceptForSession`,
Claude SDK behavior names, or provider-native policy amendment objects. Provider
native decisions are computed in daemon adapter code after the response is
validated against request metadata.

`scope` is meaningful only when `decision` is `allow`. If an allow response
omits `scope`, the daemon treats it as `once` for backward compatibility. The
daemon ignores and does not validate `scope` for `deny` or `cancel`.

Add approval request metadata to conversation events and blocking items:

```text
ApprovalRequestOptions
  kind: command | file_change | permissions | generic
  supportsSessionScope: bool
  supportsCancel: bool
  denyBehavior: interrupt | continue
  command: optional string
  cwd: optional string
  reason: optional string
  proposedExecPolicyAmendment: optional list<string>
  proposedPermissions: optional object
```

The daemon API remains backward-compatible by accepting a string decision or the
new object shape. New mobile code should send the object shape.

`ApprovalRequestOptions` is a sanitized presentation contract. It must contain
only fields mobile needs to render and submit an approval. It must not include
raw provider payloads, environment blocks, full process invocation metadata,
credentials, or unredacted diagnostic data.

Provider-native decision lists, such as Codex `acceptForSession` or `cancel`,
remain daemon/adapter-internal. The daemon derives the semantic booleans
`supportsSessionScope` and `supportsCancel` from provider-native data before it
builds mobile-facing events. Mobile renders from those semantic fields, not from
provider names.

Provider raw requests may be held in daemon memory while the approval is
pending. If diagnostics need raw provider data, the daemon should expose a
separate redacted diagnostic artifact with an allowlist per provider. Raw
provider payloads are not part of the mobile API and are not persisted in normal
conversation events.

## Daemon Mapping

The conversation manager normalizes the new approval payload and stores a
resolved event that includes the selected decision and scope. It passes the
full normalized response to the adapter.

Claude mapping:

- `allow` + `once` maps to SDK behavior `allow`.
- `allow` + `session` maps to SDK behavior `allow` with
  `updatedPermissions` when the request includes provider suggestions.
- `deny` maps to SDK behavior `deny`. The default interrupt behavior comes from
  approval request metadata. Interactive "No, tell the assistant what to
  change" prompts use `interrupt: true`; silent or batch denial flows may use
  `interrupt: false` if the provider request explicitly allows continuing.
- `cancel` maps to deny with interrupt unless Claude exposes a more precise
  cancellation behavior for the specific request.

Current Codex CLI mapping:

- The existing `codex exec --json` adapter keeps `mobileApprovalCallbacks:
  false`.
- It must not receive mobile approval responses and continues to return a 409 if
  one is sent.
- The UI should not show provider-backed approval options for this adapter.

Future Codex app-server mapping:

- `allow` + `once` maps to `accept`.
- `allow` + `session` maps to `acceptForSession` only when the adapter's
  provider-native request state has confirmed session approval support.
- Provider-specific exec policy choices map to
  `acceptWithExecpolicyAmendment`.
- Network policy choices map to `applyNetworkPolicyAmendment`.
- `deny` maps to `decline`.
- `cancel` maps to `cancel`.
- Permission approval maps to `PermissionsRequestApprovalResponse` with
  `scope: "turn"` or `scope: "session"`.

Codex generated bindings use the spelling `proposedExecpolicyAmendment` for the
provider wire field. The daemon and mobile presentation model use
`proposedExecPolicyAmendment` to keep project-facing JSON casing consistent.
Adapter mapping owns the spelling conversion.

## Adapter Capability Contract

Extend adapter capabilities with explicit approval information:

```text
approval:
  mobileCallbacks: bool
  responseShape: string | object
  scopes: list<once | session>
  supportsCancel: bool
  denyBehaviors: list<interrupt | continue>
```

This replaces ambiguous UI inference from `waitingApproval` alone. A provider
can support waiting for approval but still only offer one-time decisions.
Provider-native decision names stay out of the mobile capability contract.

## Implementation Stages

Stage 1: Contract and UI correction

- Add approval response/request models in mobile data and domain layers.
- Update the daemon client and repositories to send the object shape.
- Update approval prompt UI to render Codex-style numbered options from request
  metadata and capability gates.
- Keep current Codex CLI adapter capability as no mobile callbacks.

Stage 2: Claude session approval parity

- Preserve Claude permission suggestion metadata in approval events.
- Map mobile session approval to Claude `updatedPermissions`.
- Add regression tests for one-time allow, session allow, deny, and cancel.

Stage 3: Codex app-server adapter

- Add a new app-server-backed Codex conversation path or adapter mode.
- Handle server requests for command, file-change, and permissions approvals.
- Convert app-server events into the existing conversation event projection.
- Keep `codex exec --json` as a fallback until app-server behavior is validated.
- Do not start Stage 3 until its blockers are resolved.

## Stage 3 Blockers

Codex app-server integration is not only an approval mapping task. It must not
begin as production implementation until these blockers have explicit answers:

- Lifecycle ownership: how the daemon starts, reuses, monitors, and stops
  app-server processes per user/session/workspace.
- Transport choice: whether the daemon uses stdio, websocket, or the local
  app-server daemon/proxy path, and how reconnect/resume works.
- Authentication and authorization: how websocket tokens or local control
  sockets are protected on the LAN/mobile control surface.
- Event contract coverage: how app-server thread, turn, item, command output,
  diff, file change, and completion notifications map into existing
  conversation events.
- Test harness: a fake JSON-RPC app-server transport must exist before using
  the real CLI in regression tests.
- Security review: provider raw request redaction and permission escalation
  behavior must be reviewed before any app-server approval callback is exposed
  to mobile.

## Testing

- Daemon tests for approval payload normalization and adapter mapping.
- Daemon API compatibility tests for legacy `{ decision: "allow" }` and
  `{ decision: "deny" }` requests from older mobile clients.
- Mobile model tests for backward-compatible string and object parsing.
- Workbench widget tests for:
  - one-time approval only
  - session option visible
  - session option hidden
  - skip/cancel visible only when native cancel is available
  - missing approval id disabled state
- Stage 2 integration tests for Claude session approval:
  - session allow with provider suggestions passes `updatedPermissions`
    through daemon to adapter.
  - session allow without provider suggestions does not crash and degrades to a
    one-time allow.
  - deny with `interrupt: true` and deny with `interrupt: false` both map
    correctly through daemon to adapter.
- Protocol compatibility tests that older mobile-shaped parsers ignore added
  approval request option fields when connected to a newer daemon.
- Codex app-server adapter tests with a fake JSON-RPC transport before using the
  real CLI.
- Existing architecture import checks for mobile.

## Risks

- Codex app-server is a deeper integration than `exec --json`. Lifecycle,
  transport, authentication, event mapping, test harness, and security review
  are Stage 3 blockers, not routine implementation risks.
- Provider-native permission payloads can drift. Keep raw provider request data
  available only in daemon memory or redacted diagnostics, and keep public
  mobile state provider-neutral.
- Showing a session option without a provider guarantee is a security bug. The
  UI must be capability-gated.
- Older mobile clients may connect to a newer daemon and receive approval events
  with extra option fields. The mobile JSON models must ignore unknown fields,
  and protocol compatibility tests should cover this shape.
- The existing dirty UI work should be reconciled before implementation begins
  so the final patch does not mix visual cleanup with protocol changes.

## Decisions

- Codex app-server ships first as an opt-in adapter path or adapter mode. The
  existing `codex exec --json` adapter remains the default fallback until
  app-server transport, lifecycle, and event mapping are validated.
- The first mobile implementation does not expose provider-specific advanced
  approval choices as separate UI rows. It shows one-time allow, session allow,
  deny, and cancel. Provider-specific amendments are used only when the daemon
  can safely map the selected user intent to an offered native decision.
