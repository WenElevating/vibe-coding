# PRD: Flutter LAN AI CLI Control V1.1

## Metadata

- Slug: `flutter-lan-ai-cli-control-v1-1`
- Product: Flutter LAN AI CLI Control
- Previous milestone: V1 completed
- Target milestone: V1.1
- Status: Draft
- Date: 2026-04-30
- Primary platform: Android phone + Windows desktop daemon
- Primary mode: LAN-only
- Baseline architecture: Desktop Controller Daemon + HTTP REST + WebSocket + unified event protocol

---

## 1. Background

V1 has delivered the core LAN control loop:

- Windows desktop daemon
- Pairing and authenticated phone access
- Workspace whitelist
- Claude Code structured run control
- WebSocket event stream
- REST control endpoints
- SQLite-backed event persistence
- Flutter Android core screens
- Run detail timeline, approval cards, raw console fallback
- Reconnect with event replay

V1.1 should extend V1 from a Claude-first mobile controller into a practical multi-adapter local AI coding console.

V1.1 focuses on:

1. Codex CLI adapter.
2. OpenCode adapter.
3. Adapter capability detection.
4. Better approval and diff UX.
5. Android local notifications.
6. Configurable command shortcuts.
7. Stronger daemon diagnostics.
8. Secure token handling hardening.

Full unrestricted PTY remote terminal remains out of scope for V1.1.

---

## 2. Product Goal

Expand the product from a Claude Code controller into an adapter-ready LAN AI coding console that can operate Claude Code, Codex CLI, and OpenCode through one stable Flutter UI and daemon protocol.

The user should be able to:

- choose a workspace
- choose an AI CLI provider
- start a run
- observe structured progress
- inspect file changes and commands
- approve or deny risky actions
- receive notification for approvals/completion
- recover after disconnect
- switch tools without learning each CLI's native interface

---

## 3. Non-Goals

V1.1 intentionally does not include:

1. Full PTY remote terminal.
   - Reason: unrestricted PTY changes the security model and requires a separate ADR.

2. Public internet access.
   - Reason: LAN auth is not enough for WAN exposure.

3. Multi-user/team collaboration.
   - Reason: object-level authorization and audit semantics are not fully designed.

4. File upload/download/browser.
   - Reason: file permission model needs a dedicated design.

5. Cloud relay.
   - Reason: product remains LAN-only.

6. Arbitrary shell endpoint.
   - Reason: breaks the daemon safety boundary.

7. iOS support.
   - Reason: V1.1 remains Android-first.

---

## 4. Decision Summary

| Decision | Choice |
|---|---|
| Primary expansion | Add Codex + OpenCode adapters |
| UX expansion | Improve run detail, diff cards, notifications, shortcuts |
| Protocol | Keep `agent-control.v1`, add backward-compatible event types |
| Terminal | Continue raw output console only; no unrestricted PTY |
| Security | Maintain workspace whitelist and no arbitrary shell/cwd API |
| Notifications | Android local notifications only, no remote push |
| Storage | Secure token storage on Android; daemon stores token hashes |

---

## 5. Personas

### Primary Persona: Solo Developer

A developer is away from the desk but on the same LAN and wants to steer AI coding tasks from the phone.

Needs:

- start or continue a run
- see whether the agent is still working
- approve safe changes
- stop runaway tasks
- inspect diffs before approving
- switch between Claude, Codex, and OpenCode depending on task

### Secondary Persona: Power User

A developer wants to compare agent behavior across tools in the same workspace.

Needs:

- see which adapters are available
- know why an adapter is unavailable
- reuse command shortcuts
- view run history by tool/workspace
- inspect logs when a daemon or adapter fails

---

## 6. Success Metrics

V1.1 is successful if:

1. Codex adapter can start, stream, cancel, and resume/follow up a supported run through the same Flutter run detail UI.
2. OpenCode adapter can create or attach to a local OpenCode server session through the daemon.
3. Adapter capability detection accurately reports installed, unavailable, and misconfigured tools.
4. Android notification appears for approval-required and run-completed events when notification permission is granted.
5. Denied notification permission does not break in-app state recovery.
6. Diff cards are readable on a phone for common file edits.
7. Shortcut commands reduce repeated prompt typing for common actions: test, lint, review, fix, explain.
8. Event replay continues to work for V1 and V1.1 event types.
9. No V1.1 API accepts arbitrary local filesystem paths or arbitrary shell commands from the phone.
10. Existing V1 Claude runs remain compatible after upgrade.

---

## 7. Scope

### 7.1 V1.1 Must Have

#### Adapter Layer

1. Codex CLI adapter.
2. OpenCode adapter.
3. Adapter capability detection.
4. Adapter availability UI in Flutter.
5. Adapter-specific error normalization.

#### Run Control

6. Tool picker in run creation flow.
7. Run history filter by tool/workspace/status.
8. Cancel support for Codex/OpenCode where feasible.
9. Follow-up input support where adapter supports it.
10. Structured fallback to raw console when event parsing is incomplete.

#### UX

11. Improved diff cards.
12. Approval center page.
13. Pending approval badge.
14. Command shortcut buttons.
15. Better error cards for daemon/adapter/process failures.

#### Android

16. Runtime notification permission flow.
17. Local notifications for approval-required and run-completed.
18. Secure storage verification for device tokens.

#### Daemon

19. Adapter diagnostics endpoint.
20. Daemon status endpoint.
21. LAN binding status and visible security state.
22. Structured logs for adapter lifecycle.
23. Backward-compatible database migration.

### 7.2 V1.1 Should Have

1. OpenCode mDNS discovery support where available.
2. Per-workspace default tool.
3. Per-workspace shortcuts.
4. Notification deep link into the relevant run.
5. Export run event log as JSON for debugging.
6. Adapter version display.
7. Basic diff folding for large diffs.
8. Run list search.

### 7.3 V1.1 Won't Have

1. Full PTY control.
2. Arbitrary PowerShell session.
3. Internet access.
4. Cloud sync.
5. Multi-user permissions.
6. File browser/upload/download.
7. iOS support.
8. Voice input.
9. Multi-agent orchestration.

---

## 8. Functional Requirements

## 8.1 Adapter Capability Detection

Daemon must detect installed adapters and expose capabilities to Flutter.

Endpoint:

```http
GET /api/adapters
```

Example response:

```json
{
  "adapters": [
    {
      "id": "claude",
      "displayName": "Claude Code",
      "status": "available",
      "version": "x.y.z",
      "capabilities": {
        "structuredEvents": true,
        "rawOutput": true,
        "resume": true,
        "cancel": true,
        "approval": true,
        "diff": true
      }
    },
    {
      "id": "codex",
      "displayName": "Codex CLI",
      "status": "available",
      "version": "x.y.z",
      "capabilities": {
        "structuredEvents": true,
        "rawOutput": true,
        "resume": true,
        "cancel": true,
        "approval": true,
        "diff": "partial"
      }
    },
    {
      "id": "opencode",
      "displayName": "OpenCode",
      "status": "needs_configuration",
      "reason": "OpenCode server is not running",
      "capabilities": {
        "structuredEvents": "partial",
        "rawOutput": true,
        "resume": "unknown",
        "cancel": "partial",
        "approval": "partial",
        "diff": "partial"
      }
    }
  ]
}
```

Adapter status values:

```text
available
not_installed
needs_auth
needs_configuration
unsupported_version
error
```

Acceptance criteria:

- If Codex is not installed, Flutter shows "Codex CLI not installed" and disables selection.
- If OpenCode server is not reachable, Flutter shows setup guidance.
- If adapter version is unsupported, daemon reports `unsupported_version`.
- Adapter detection must not start a real coding run.

---

## 8.2 Codex CLI Adapter

Daemon supports Codex CLI as a V1.1 adapter.

Recommended execution path:

```bash
codex exec --json --sandbox workspace-write --ask-for-approval on-request "$PROMPT"
```

Resume/follow-up where supported:

```bash
codex exec resume "$SESSION_ID" "$PROMPT" --json
```

or:

```bash
codex exec resume --last "$PROMPT" --json
```

Event handling:

Codex JSONL events must be normalized into existing `run.event` messages.

```json
{
  "type": "assistant.delta",
  "runId": "run_123",
  "seq": 10,
  "payload": {
    "text": "..."
  }
}
```

Codex-specific requirements:

- Store Codex session ID when available.
- Respect workspace whitelist.
- Map Codex process errors to normalized daemon errors.
- Support raw console fallback.
- Support cancellation through process termination.
- Do not expose arbitrary Codex CLI arguments to Flutter.

Acceptance criteria:

- User can start a Codex run from Flutter.
- User can see Codex streaming output in run detail.
- User can cancel a Codex run.
- Codex run appears in history with tool label.
- Event replay works after reconnect.

---

## 8.3 OpenCode Adapter

Daemon supports OpenCode through an adapter.

Preferred V1.1 path:

```bash
opencode serve --hostname 127.0.0.1 --port 4096
```

Daemon connects to OpenCode server locally and exposes normalized events to Flutter.

LAN exposure rule:

Correct:

```text
Flutter -> Daemon -> OpenCode Server
```

Incorrect:

```text
Flutter -> OpenCode Server
```

OpenCode setup modes:

1. Attach to existing OpenCode server.
2. Optionally start managed OpenCode server if explicitly configured.

Authentication:

If OpenCode server uses basic auth, daemon stores the OpenCode credential locally and never sends it to Flutter.

Acceptance criteria:

- Flutter can select OpenCode when adapter status is available.
- If server is unavailable, Flutter shows a clear setup action.
- OpenCode run/session events are visible in run detail.
- Daemon does not expose OpenCode server credentials to Flutter.

---

## 8.4 Tool Picker

Run creation screen must include a tool picker.

Tool options:

- Claude Code
- Codex CLI
- OpenCode

Each option shows:

- status
- version
- capability summary
- unavailable reason if disabled

Example UI states:

```text
Claude Code     Available
Codex CLI       Available
OpenCode        Server not running
```

Acceptance criteria:

- Unavailable tools cannot be selected.
- Default tool is remembered per workspace.
- User can override the default tool before creating a run.

---

## 8.5 Improved Diff Cards

Run detail should render file changes as mobile-readable diff cards.

Card information:

- file path
- operation type: created / modified / deleted / renamed
- additions/deletions count
- collapsed preview
- expand full diff
- copy path
- approval linkage if relevant

Diff constraints:

- Large diffs must collapse automatically.
- Binary files show metadata only.
- Secrets should be redacted where feasible.
- Raw console remains available if structured diff parsing fails.

Acceptance criteria:

- User can inspect modified file path and summary.
- User can expand/collapse diff.
- Approval card can reference diff card.
- Large diff does not freeze UI.

---

## 8.6 Approval Center

Add a dedicated approval center page.

Purpose:

- show all pending approvals across active runs
- reduce missed approval requests
- allow quick approve/deny
- jump to run detail

Approval item fields:

```json
{
  "approvalId": "ap_123",
  "runId": "run_123",
  "tool": "claude",
  "workspace": "my-app",
  "risk": "medium",
  "action": "edit_file",
  "summary": "Modify tests/login_test.dart",
  "createdAt": "..."
}
```

Acceptance criteria:

- Pending approvals are visible from bottom nav or run list badge.
- Approving/denying updates both approval center and run timeline.
- Already-handled approvals move to history or disappear from pending list.
- Duplicate approval decisions are idempotent.

---

## 8.7 Android Notifications

V1.1 adds local notifications for:

- approval required
- run completed
- run failed

Android 13+ requires runtime notification permission.

Behavior:

- On first relevant moment, app requests notification permission.
- If granted, app shows local notifications.
- If denied, app continues to work and shows missed state in-app.
- Notifications deep link into the relevant run where feasible.

Notification types:

```text
Approval required
Run completed
Run failed
Daemon disconnected
```

Acceptance criteria:

- Android 13+ permission flow works.
- Denied permission does not block core product behavior.
- Tapping notification opens relevant run or approval page.
- Duplicate notifications are avoided for same event seq.

---

## 8.8 Command Shortcuts

Add configurable command shortcuts to run creation and run detail.

Default shortcuts:

```text
Run tests
Fix failing tests
Review changes
Explain current error
Refactor safely
Generate commit summary
```

Shortcut schema:

```json
{
  "id": "fix-tests",
  "label": "Fix failing tests",
  "promptTemplate": "Find and fix the failing tests in this workspace. Explain the root cause and proposed changes before editing.",
  "tool": "default",
  "workspaceId": "optional"
}
```

Acceptance criteria:

- User can tap shortcut to prefill prompt.
- User can edit prompt before sending.
- Workspace-level shortcut overrides global shortcut.
- Shortcut does not bypass permission mode.

---

## 8.9 Daemon Status and Diagnostics

Add daemon diagnostics for troubleshooting.

Endpoint:

```http
GET /api/daemon/status
```

Example response:

```json
{
  "daemonVersion": "1.1.0",
  "lanMode": true,
  "bindAddress": "0.0.0.0",
  "port": 7070,
  "pairedDevices": 1,
  "activeRuns": 2,
  "database": {
    "status": "ok",
    "path": "..."
  },
  "adapters": {
    "claude": "available",
    "codex": "available",
    "opencode": "needs_configuration"
  }
}
```

Acceptance criteria:

- Flutter settings page shows daemon status.
- User can see LAN mode state.
- User can see adapter status.
- Diagnostics do not expose secrets.

---

## 8.10 Secure Token Handling

V1.1 hardens token handling.

Mobile:

- token stored in platform secure storage
- token not written to logs
- token not shown in crash reports
- token can be revoked by deleting paired device

Daemon:

- stores only token hash
- supports device revocation
- rejects unknown/revoked device tokens
- logs device ID, not token

Acceptance criteria:

- Logout removes local token.
- Revoked device can no longer access API/WebSocket.
- Token is never included in normal app logs.

---

## 9. Protocol Changes

V1.1 remains backward-compatible with `agent-control.v1`.

Add optional event types:

```text
adapter.status.changed
diff.summary
diff.chunk
notification.intent
approval.updated
daemon.status.changed
shortcut.invoked
```

### 9.1 Adapter Status Event

```json
{
  "protocol": "agent-control.v1",
  "type": "adapter.status.changed",
  "seq": 300,
  "timestamp": "2026-04-30T12:00:00Z",
  "payload": {
    "adapterId": "codex",
    "status": "available",
    "version": "x.y.z"
  }
}
```

### 9.2 Diff Summary Event

```json
{
  "protocol": "agent-control.v1",
  "type": "diff.summary",
  "runId": "run_123",
  "seq": 301,
  "timestamp": "2026-04-30T12:00:01Z",
  "payload": {
    "filePath": "tests/login_test.dart",
    "operation": "modified",
    "additions": 12,
    "deletions": 8,
    "truncated": false
  }
}
```

### 9.3 Approval Updated Event

```json
{
  "protocol": "agent-control.v1",
  "type": "approval.updated",
  "runId": "run_123",
  "seq": 302,
  "timestamp": "2026-04-30T12:00:02Z",
  "payload": {
    "approvalId": "ap_123",
    "status": "approved",
    "decidedAt": "2026-04-30T12:00:02Z"
  }
}
```

---

## 10. Database Changes

Add tables:

```sql
CREATE TABLE adapters (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL,
  version TEXT,
  capabilities_json TEXT NOT NULL,
  last_checked_at TEXT NOT NULL,
  error_message TEXT
);

CREATE TABLE shortcuts (
  id TEXT PRIMARY KEY,
  workspace_id TEXT,
  label TEXT NOT NULL,
  prompt_template TEXT NOT NULL,
  tool TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  event_id TEXT NOT NULL,
  run_id TEXT,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  shown_at TEXT
);
```

Migration requirements:

- preserve V1 runs/events
- preserve V1 paired devices
- no destructive migration
- rollback plan documented

---

## 11. UX Requirements

### 11.1 Updated Navigation

Recommended bottom nav:

```text
Home
Runs
Approvals
Workspaces
Settings
```

Home:

- daemon status
- active runs
- pending approvals
- quick actions

Runs:

- filter by active/completed/failed
- filter by tool
- search by workspace or prompt

Approvals:

- pending approvals
- approval history
- jump to run

Workspaces:

- list registered workspaces
- default tool
- shortcuts

Settings:

- paired daemon
- notification permission
- adapter diagnostics
- LAN/security status

### 11.2 Run Detail Tabs

Run detail should have:

```text
Timeline
Diffs
Console
Details
```

Timeline:

- assistant messages
- tool calls
- approval cards
- errors

Diffs:

- file changes
- grouped by file
- expand/collapse

Console:

- raw output
- stdout/stderr labels
- copy output

Details:

- tool
- workspace
- mode
- session ID if safe
- timestamps
- daemon/adapter version

---

## 12. Error Model

Normalize all adapter errors into:

```json
{
  "code": "ADAPTER_NOT_INSTALLED",
  "message": "Codex CLI is not installed",
  "adapterId": "codex",
  "recoverable": true,
  "userAction": "Install Codex CLI and run adapter detection again"
}
```

Error codes:

```text
ADAPTER_NOT_INSTALLED
ADAPTER_NEEDS_AUTH
ADAPTER_UNSUPPORTED_VERSION
ADAPTER_PROCESS_EXITED
ADAPTER_PARSE_ERROR
ADAPTER_SERVER_UNREACHABLE
WORKSPACE_NOT_FOUND
WORKSPACE_ACCESS_DENIED
TOKEN_REVOKED
NOTIFICATION_PERMISSION_DENIED
```

---

## 13. Security Requirements

V1.1 must preserve all V1 security constraints.

Additional requirements:

1. Adapter selection must not allow arbitrary CLI args.
2. OpenCode credentials never leave daemon.
3. Codex/Claude/OpenCode auth state is never exposed to Flutter except coarse status.
4. Notification content must avoid leaking sensitive code by default.
5. Diff preview should redact obvious secrets where feasible.
6. Logs must not contain mobile auth token.
7. Device revocation must invalidate WebSocket and REST access.
8. Adapter diagnostics must not include environment variables or API keys.

---

## 14. Observability

Daemon logs should include:

- adapter detection result
- adapter process start/exit
- run lifecycle
- approval decisions
- notification creation status
- WebSocket reconnect/backfill
- database migration result

Logs should not include:

- device token
- provider API key
- raw secret-looking values
- full `.env` content
- private key material

---

## 15. Acceptance Tests

### Adapter Detection

- Given Codex is installed, `/api/adapters` returns Codex available.
- Given Codex is missing, `/api/adapters` returns Codex `not_installed`.
- Given OpenCode server is unreachable, `/api/adapters` returns `needs_configuration`.

### Codex Run

- Given available Codex adapter, user creates Codex run.
- Then run starts, events stream, history persists.
- When user cancels, daemon terminates process and emits terminal event.

### OpenCode Run

- Given reachable OpenCode server, user creates OpenCode run.
- Then daemon normalizes OpenCode events into run timeline.
- Flutter never connects directly to OpenCode server.

### Notification

- Given Android notification permission granted, `approval.required` emits local notification.
- Given permission denied, `approval.required` remains visible in app.
- Given user taps notification, app opens relevant run or approval page.

### Diff Card

- Given `diff.summary` events, run detail shows file path and additions/deletions.
- Given large diff, UI collapses automatically.
- Given binary diff, UI shows metadata only.

### Reconnect

- Given app receives events 1..10 and disconnects, daemon emits 11..20.
- When app reconnects with `afterSeq=10`, app receives 11..20 once.

### Security

- Unknown workspaceId is rejected.
- Arbitrary cwd is rejected.
- Arbitrary CLI args are rejected.
- Revoked device token cannot access REST or WebSocket.

---

## 16. Release Plan

### Phase 1: Adapter Diagnostics

- implement `/api/adapters`
- implement daemon status endpoint
- implement Flutter adapter status UI

### Phase 2: Codex Adapter

- implement Codex process runner
- parse JSONL events
- normalize events
- support cancel
- add run creation tool picker

### Phase 3: OpenCode Adapter

- support attach to existing server
- add setup diagnostics
- normalize basic session/events
- add status UI

### Phase 4: UX Upgrade

- approval center
- diff tab/cards
- run filters
- shortcuts

### Phase 5: Android Notifications

- permission flow
- local notification events
- notification deep link

### Phase 6: Hardening

- token revocation
- log redaction review
- migration testing
- reconnect regression tests

---

## 17. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Codex event schema changes | Broken structured UI | Raw console fallback, adapter version detection |
| OpenCode server API changes | Adapter failure | Capability detection, attach-mode diagnostics |
| Android notifications denied | Missed approvals | In-app approval center and reconnect state |
| Large diffs freeze UI | Poor UX | Truncation, folding, lazy rendering |
| Multi-adapter scope creep | Delayed release | Claude remains baseline; Codex first, OpenCode second |
| Credentials leak in logs/notifications | Severe security issue | Redaction, notification privacy defaults |
| LAN service exposed accidentally | Security risk | Visible LAN state, explicit enablement, auth required |

---

## 18. Open Decisions

1. Should Codex adapter be enabled by default when installed, or require explicit user enablement?
2. Should OpenCode be managed by daemon, or only attached to an already running OpenCode server in V1.1?
3. Should notification content show prompt/file names, or use privacy-preserving generic text?
4. Should shortcuts be stored daemon-side, mobile-side, or both?
5. How much diff parsing should be done daemon-side versus Flutter-side?

Recommended answers:

1. Codex requires explicit enablement in Settings.
2. OpenCode V1.1 should attach only; managed start can be V1.2.
3. Notifications should default to privacy-preserving generic text.
4. Shortcuts should be daemon-side so multiple phones share workspace config later.
5. Daemon should compute diff summaries; Flutter should render.

---

## 19. References

- Codex CLI reference: https://developers.openai.com/codex/cli/reference
- Codex App Server: https://developers.openai.com/codex/app-server
- OpenCode Server: https://opencode.ai/docs/server/
- OpenCode Config: https://opencode.ai/docs/config/
- Android notification runtime permission: https://developer.android.com/develop/ui/views/notifications/notification-permission
- Flutter secure storage: https://pub.dev/packages/flutter_secure_storage

---

## 20. Final Recommendation

Ship V1.1 as a practical multi-adapter upgrade, not a terminal rewrite.

Priority order:

1. Adapter diagnostics.
2. Codex adapter.
3. Tool picker and run filters.
4. Approval center.
5. Improved diff cards.
6. Android notifications.
7. OpenCode attach-mode adapter.
8. Shortcut commands.
9. Security hardening and token revocation.

Do not add full PTY control in V1.1.
