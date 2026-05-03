# PRD: Flutter LAN AI CLI Control V1.2

## Metadata

- Slug: `flutter-lan-ai-cli-control-v1-2`
- Product: Flutter LAN AI CLI Control
- Previous milestone: V1.1 completed
- Target milestone: V1.2
- Status: Draft
- Date: 2026-05-01
- Primary platform: Android phone + Windows desktop daemon
- Primary mode: LAN-only
- V1.2 theme: Multi-CLI Task Runner Hardening
- Explicit decision: No PTY / no remote terminal in V1.2

---

## 1. Background

V1 established the core local control architecture:

- Windows desktop daemon.
- Pairing and authenticated LAN access.
- Workspace whitelist.
- Claude Code structured run control.
- WebSocket event streaming.
- HTTP REST control plane.
- SQLite-backed run/event persistence.
- Flutter Android run creation, run detail, timeline, raw console fallback, approval cards, reconnect replay.

V1.1 expanded the system into a multi-adapter skeleton:

- Adapter registry.
- `/api/adapters`.
- Codex explicit-enable JSONL adapter.
- OpenCode attach-mode diagnostics.
- Run filters.
- Shortcuts.
- Token revocation.
- `diff.summary` event model.
- Mobile client/model/state expansion.
- Continued rejection of arbitrary `cmd`, `cwd`, `args`, shell, and PTY payloads.

V1.2 should harden the product as a **CLI task runner**, not turn it into a terminal emulator. The main job is to reliably invoke AI coding CLIs in their supported non-interactive/headless/server modes, normalize their output, and expose one consistent mobile workflow.

---

## 2. Product Goal

V1.2 upgrades the product from "multi-adapter skeleton" to a reliable **LAN AI CLI Task Runner**.

The user should be able to:

- select a workspace
- select Claude Code, Codex, OpenCode, or another supported CLI adapter
- start a coding task from the phone
- receive structured task progress
- see raw output fallback
- inspect git status and diffs
- approve risky actions where supported
- cancel or resume supported runs
- run safe command templates such as test/lint/build
- trust that no mobile API can execute arbitrary shell commands or escape the workspace

---

## 3. Core Product Decision

V1.2 does **not** implement PTY, terminal mirroring, or remote shell control.

V1.2 uses:

```text
Flutter App
  -> HTTP REST + WebSocket
Desktop Daemon
  -> Adapter Contract
    -> process-based CLI invocation
    -> HTTP/server-based adapter invocation
    -> SDK-based adapter invocation in the future
```

The product treats each CLI as a **task execution backend**, not a terminal UI.

---

## 4. Why No PTY

PTY is unnecessary for V1.2 because the target CLIs already expose automation-oriented execution paths:

- Claude Code supports headless `-p/--print` usage and structured/streaming JSON output.
- Codex supports non-interactive `codex exec`, JSON output, resume, sandbox, and approval flags.
- OpenCode supports `opencode serve` as a headless HTTP server with OpenAPI, and `opencode run` for non-interactive runs.
- Aider supports scripting through `--message`, processing one instruction and exiting.

PTY should only be considered later if the product explicitly wants interactive terminal/TUI mirroring, such as `vim`, `less`, `git add -p`, or arbitrary shell sessions. That is not the V1.2 product goal.

---

## 5. Non-Goals

V1.2 intentionally does not include:

1. PTY.
2. Remote terminal.
3. Arbitrary PowerShell / cmd / bash session.
4. Arbitrary shell command endpoint.
5. Arbitrary `cwd` from mobile.
6. Arbitrary CLI args from mobile.
7. Public internet access.
8. Cloud relay.
9. File upload/download/browser.
10. Multi-user collaboration.
11. iOS support.
12. Automatic commit/push.
13. Full IDE replacement.

---

## 6. Personas

### Primary Persona: Mobile Coding Task Operator

A developer on the same LAN wants to start and monitor AI coding tasks from Android without sitting at the desktop.

Needs:

- start a task quickly
- pick a tool
- see whether the task is running, blocked, failed, or done
- inspect output and diffs
- approve/deny supported actions
- cancel runaway tasks
- resume where supported

### Secondary Persona: Adapter Maintainer

A developer wants to add or stabilize CLI adapters.

Needs:

- one adapter contract
- conformance tests
- clear invocation profiles
- capability detection
- structured fallback behavior
- process lifecycle rules

### Tertiary Persona: Safety-Conscious Developer

A developer wants mobile convenience without turning the phone into an unrestricted remote shell.

Needs:

- no arbitrary shell execution
- workspace whitelist
- audit logs
- clear permission modes
- revocable devices
- no secrets in logs

---

## 7. Success Metrics

V1.2 is successful if:

1. Claude, Codex, and OpenCode adapters all conform to the same adapter contract.
2. A run can be started, streamed, cancelled, persisted, replayed, and listed using the same mobile UI regardless of adapter.
3. Adapter capability detection correctly reports supported output formats, resume, cancel, approval, diff, and server mode.
4. Run queue prevents unsafe concurrent writes in the same workspace by default.
5. Git status and diff review are visible before the user accepts or continues risky changes.
6. Command templates allow test/lint/build/review flows without arbitrary command payloads from mobile.
7. Raw output fallback works when structured parsing fails.
8. Adapter conformance tests run in CI without requiring real provider credentials where possible.
9. No V1.2 API accepts arbitrary `cmd`, `cwd`, shell path, or CLI args from the phone.
10. Existing V1/V1.1 data and flows remain backward-compatible.

---

## 8. Scope

## 8.1 V1.2 Must Have

### Adapter Contract

1. Define shared `CliTaskAdapter` interface.
2. Define adapter invocation profile schema.
3. Define adapter capability matrix.
4. Add adapter conformance test harness.
5. Normalize process/HTTP/server adapter outputs into unified events.

### Run Lifecycle

6. Add run queue per workspace.
7. Add run concurrency policy.
8. Add run cancellation contract.
9. Add run resume contract where supported.
10. Add normalized terminal status states: queued, running, blocked, cancelling, cancelled, failed, completed.

### Output Normalization

11. Support JSONL parser hardening.
12. Support plain text fallback.
13. Support stderr as first-class event source.
14. Support exit code normalization.
15. Support parse error events without killing the entire run where safe.

### CLI Adapters

16. Harden Claude Code adapter.
17. Harden Codex adapter.
18. Harden OpenCode adapter.
19. Add Aider adapter spike.
20. Add future Gemini adapter placeholder behind disabled flag.

### Git / Change Review

21. Add git status endpoint.
22. Add git diff endpoint.
23. Add changed files UI model.
24. Link diff summaries to run events.
25. Add large diff truncation.

### Command Templates

26. Add daemon-side command template schema.
27. Add safe template invocation endpoint.
28. Add default templates: test, lint, build, review changes, explain failure.
29. Deny raw command payloads.
30. Require approval for high-risk templates.

### Security / Audit

31. Add adapter invocation audit events.
32. Add run queue audit events.
33. Add command template audit events.
34. Ensure token revocation kills active WebSocket subscriptions.
35. Ensure logs redact tokens and obvious secrets.

---

## 8.2 V1.2 Should Have

1. Adapter version compatibility rules.
2. Adapter health check retry.
3. Workspace default adapter.
4. Per-workspace concurrency mode.
5. Diff hunk folding.
6. Run output search.
7. Export run log as JSON.
8. Export adapter diagnostic bundle.
9. Better mobile error cards.
10. Synthetic adapter for local tests.

---

## 8.3 V1.2 Won't Have

1. PTY.
2. Remote terminal.
3. Arbitrary shell.
4. Interactive TUI mirroring.
5. File upload/download.
6. Browser-based desktop UI.
7. Cloud relay.
8. Multi-device collaboration.
9. Automatic git commit/push.
10. Provider credential management UI.

---

## 9. Adapter Contract

### 9.1 Interface

```ts
export interface CliTaskAdapter {
  id: string;
  displayName: string;

  detect(context: AdapterDetectContext): Promise<AdapterStatus>;

  startRun(input: AdapterStartRunInput): AsyncIterable<NormalizedRunEvent>;

  resumeRun?(
    input: AdapterResumeRunInput
  ): AsyncIterable<NormalizedRunEvent>;

  cancel(runId: string): Promise<AdapterCancelResult>;

  getCapabilities(): AdapterCapabilities;
}
```

### 9.2 Adapter Capabilities

```ts
export interface AdapterCapabilities {
  invocationMode: "process-jsonl" | "process-json" | "process-text" | "http-server" | "sdk";
  supportsStreaming: boolean;
  supportsStructuredEvents: boolean | "partial";
  supportsRawOutput: boolean;
  supportsResume: boolean | "partial";
  supportsCancel: boolean | "process-kill" | "api";
  supportsApproval: boolean | "partial";
  supportsDiff: boolean | "partial";
  supportsServerMode: boolean;
  supportsNonInteractive: boolean;
}
```

### 9.3 Adapter Status

```ts
export type AdapterStatus =
  | { status: "available"; version?: string; capabilities: AdapterCapabilities }
  | { status: "not_installed"; reason: string }
  | { status: "needs_auth"; reason: string }
  | { status: "needs_configuration"; reason: string }
  | { status: "unsupported_version"; version?: string; reason: string }
  | { status: "error"; reason: string };
```

Acceptance criteria:

- All adapters implement `detect`.
- All enabled adapters implement `startRun`.
- Unsupported optional features are explicit, not inferred.
- Flutter can render adapter availability without adapter-specific logic.

---

## 10. Adapter Invocation Profile

Each adapter must define an invocation profile.

### 10.1 Claude Code Profile

```json
{
  "adapterId": "claude",
  "invocationMode": "process-jsonl",
  "command": "claude",
  "argsTemplate": [
    "--bare",
    "-p",
    "{{prompt}}",
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages"
  ],
  "cwdPolicy": "workspace-root",
  "output": {
    "stdout": "jsonl",
    "stderr": "text"
  },
  "resume": {
    "supported": true,
    "argsTemplate": [
      "-p",
      "{{prompt}}",
      "--resume",
      "{{sessionId}}",
      "--output-format",
      "stream-json",
      "--verbose",
      "--include-partial-messages"
    ]
  }
}
```

### 10.2 Codex Profile

```json
{
  "adapterId": "codex",
  "invocationMode": "process-jsonl",
  "command": "codex",
  "argsTemplate": [
    "exec",
    "--json",
    "--sandbox",
    "{{sandbox}}",
    "--ask-for-approval",
    "{{approvalMode}}",
    "{{prompt}}"
  ],
  "cwdPolicy": "workspace-root",
  "output": {
    "stdout": "jsonl",
    "stderr": "text"
  },
  "resume": {
    "supported": true,
    "argsTemplate": [
      "exec",
      "resume",
      "{{sessionId}}",
      "{{prompt}}",
      "--json"
    ]
  }
}
```

### 10.3 OpenCode Profile

```json
{
  "adapterId": "opencode",
  "invocationMode": "http-server",
  "server": {
    "healthUrl": "http://127.0.0.1:4096",
    "auth": "daemon-local"
  },
  "fallbackInvocation": {
    "command": "opencode",
    "argsTemplate": ["run", "{{prompt}}"]
  },
  "cwdPolicy": "server-managed",
  "output": {
    "events": "http-stream-or-poll",
    "fallbackStdout": "text"
  }
}
```

### 10.4 Aider Profile

```json
{
  "adapterId": "aider",
  "invocationMode": "process-text",
  "command": "aider",
  "argsTemplate": [
    "--message",
    "{{prompt}}"
  ],
  "cwdPolicy": "workspace-root",
  "output": {
    "stdout": "text",
    "stderr": "text"
  },
  "resume": {
    "supported": false
  }
}
```

Rules:

- Mobile never sends raw command, cwd, shell path, or CLI args.
- Invocation profile is daemon-owned.
- Template expansion must validate every field.
- Args must be passed as argv array, not interpolated through shell string.

Acceptance criteria:

- Invocation profile exists for each enabled adapter.
- Invalid template variable fails before process start.
- No adapter uses shell string interpolation for user prompt.
- Adapter profile can be included in diagnostic output without secrets.

---

## 11. Run Queue

### 11.1 Purpose

Prevent multiple agents from concurrently editing the same workspace unless explicitly allowed.

### 11.2 Queue Policy

Default policy:

```text
one_writer_per_workspace
```

Supported policies:

```text
one_writer_per_workspace
allow_parallel_read_only
allow_parallel_all
manual_only
```

Run modes:

```text
read_only
workspace_write
dangerous
```

Queue behavior:

- `workspace_write` and `dangerous` runs are mutually exclusive per workspace by default.
- `read_only` runs may run concurrently if adapter supports it.
- User can cancel queued runs.
- User can reorder queued runs in a later version, not V1.2.

### 11.3 Run Status

```text
queued
starting
running
blocked
cancelling
cancelled
failed
completed
```

Acceptance criteria:

- Two write-capable runs in the same workspace do not run concurrently by default.
- Queued runs survive app reconnect.
- Cancelling queued run does not start process.
- Queue events are persisted.

---

## 12. Output Normalization

### 12.1 Normalized Events

All adapters emit these event families:

```text
run.started
run.queued
run.dequeued
assistant.delta
assistant.message
tool.started
tool.output
tool.completed
diff.summary
approval.required
adapter.raw_stdout
adapter.raw_stderr
adapter.parse_error
run.blocked
run.cancelling
run.cancelled
run.failed
run.completed
```

### 12.2 JSONL Parser Requirements

The JSONL parser must:

- handle chunk boundaries across multibyte UTF-8 characters
- handle partial lines
- handle empty lines
- handle parse errors without crashing daemon
- emit raw fallback when structured parsing fails
- preserve event order per stream

### 12.3 Plain Text Fallback

Adapters without structured output must emit:

```json
{
  "type": "assistant.message",
  "payload": {
    "text": "raw output or summary"
  }
}
```

and:

```json
{
  "type": "adapter.raw_stdout",
  "payload": {
    "text": "..."
  }
}
```

Acceptance criteria:

- Malformed JSONL line emits `adapter.parse_error`.
- Subsequent valid JSONL lines continue parsing.
- stderr appears in run detail console.
- exit code maps to completed/failed consistently.

---

## 13. Adapter-Specific Requirements

## 13.1 Claude Code Adapter

Requirements:

- Use `claude -p` or `claude --bare -p`.
- Prefer `--output-format stream-json --verbose --include-partial-messages`.
- Extract session ID when available.
- Support resume when session ID is available.
- Map permission modes to allowed tools / permission settings where supported.
- Support raw stdout/stderr fallback.
- Detect unsupported CLI version or missing stream-json support.

Acceptance criteria:

- Claude run streams assistant deltas.
- Claude run records session ID if present.
- Claude resume creates continued run or linked run.
- Claude parse errors do not break entire daemon.

---

## 13.2 Codex Adapter

Requirements:

- Use `codex exec --json`.
- Map sandbox mode:
  - read_only -> `--sandbox read-only`
  - workspace_write -> `--sandbox workspace-write`
  - dangerous -> disabled unless daemon config explicitly allows it
- Map approval mode:
  - default -> `--ask-for-approval on-request`
  - non-interactive safe mode -> `--ask-for-approval never` only when safe and documented
- Support `codex exec resume` where available.
- Reject `--dangerously-bypass-approvals-and-sandbox`.
- Store transcript/session ID when available.

Acceptance criteria:

- Codex adapter starts non-interactive run.
- Codex JSON output streams into normalized events.
- Codex resume works when session ID is known.
- Dangerous bypass flag is never passed by mobile request.

---

## 13.3 OpenCode Adapter

Requirements:

- Prefer attach to local `opencode serve`.
- Detect server reachability.
- Support basic auth configured daemon-side.
- Flutter never receives OpenCode server credentials.
- If server unavailable, return `needs_configuration`.
- Support `opencode run` fallback only if explicitly enabled.
- Normalize OpenCode events/session data where available.

Acceptance criteria:

- Adapter reports available when server is reachable.
- Adapter reports needs_configuration when server is down.
- Daemon never exposes OpenCode password to mobile.
- Flutter never connects directly to OpenCode server.

---

## 13.4 Aider Adapter Spike

Requirements:

- Disabled by default.
- Detect `aider` availability and version.
- Run `aider --message "{{prompt}}"` inside workspace.
- Capture stdout/stderr/exit code.
- Provide plain text output fallback.
- Do not enable auto-yes by default.
- Do not auto-commit by default unless daemon config explicitly enables it.

Acceptance criteria:

- Aider appears as experimental adapter.
- Aider run can execute one task and exit.
- Output appears in run console.
- Adapter cannot run outside workspace.

---

## 13.5 Future Gemini Adapter Placeholder

Requirements:

- Define adapter placeholder only.
- Do not enable by default.
- Detect CLI availability only if configured.
- Treat structured output as capability-detected, not assumed.
- Use plain text fallback as baseline.

Acceptance criteria:

- Gemini placeholder does not affect V1.2 release if unavailable.
- No Gemini-specific UI is required.

---

## 14. Git Change Review

### 14.1 Git Status Endpoint

```http
GET /api/workspaces/{workspaceId}/git/status
```

Response:

```json
{
  "workspaceId": "my_app",
  "isGitRepository": true,
  "branch": "main",
  "ahead": 0,
  "behind": 0,
  "files": [
    {
      "path": "lib/main.dart",
      "status": "modified",
      "additions": 12,
      "deletions": 4
    }
  ]
}
```

### 14.2 Git Diff Endpoint

```http
GET /api/workspaces/{workspaceId}/git/diff?path=lib/main.dart
```

Rules:

- Workspace must be whitelisted.
- Path must resolve inside workspace.
- Large diffs are truncated.
- Binary files return metadata only.
- Diff endpoint is read-only.

Acceptance criteria:

- Mobile can show changed files after a run.
- Diff view links to run and approval cards.
- Path traversal is rejected.
- Non-git workspace returns structured error.

---

## 15. Command Templates

### 15.1 Purpose

Allow common local tasks without exposing arbitrary shell execution.

Examples:

- Run tests.
- Run lint.
- Run build.
- Review current diff.
- Explain failing output.
- Generate commit summary.

### 15.2 Template Schema

```json
{
  "id": "run-tests",
  "workspaceId": "my_app",
  "label": "Run tests",
  "description": "Run the workspace test command",
  "command": "npm",
  "args": ["test"],
  "risk": "low",
  "requiresApproval": false,
  "enabled": true
}
```

### 15.3 Invocation

```http
POST /api/workspaces/{workspaceId}/command-templates/{templateId}/run
```

Request:

```json
{
  "attachRunId": "optional_run_id"
}
```

Rules:

- Mobile sends template ID only.
- Daemon owns command and args.
- Command runs in workspace root.
- High-risk templates create approval request.
- Templates cannot be edited from mobile in V1.2 unless explicitly enabled.

Acceptance criteria:

- User can run tests from mobile.
- Unknown template is rejected.
- Raw command payload is rejected.
- High-risk template requires approval.
- Command output appears in run console.

---

## 16. API Changes

### 16.1 Adapter Diagnostics

```http
GET /api/adapters
GET /api/adapters/{adapterId}
POST /api/adapters/{adapterId}/refresh
```

### 16.2 Runs

```http
GET /api/runs?workspaceId=&tool=&status=
POST /api/runs
POST /api/runs/{runId}/cancel
POST /api/runs/{runId}/resume
GET /api/runs/{runId}/events?afterSeq=
```

### 16.3 Queue

```http
GET /api/workspaces/{workspaceId}/queue
POST /api/runs/{runId}/cancel-queued
```

### 16.4 Git

```http
GET /api/workspaces/{workspaceId}/git/status
GET /api/workspaces/{workspaceId}/git/diff?path=
```

### 16.5 Command Templates

```http
GET /api/workspaces/{workspaceId}/command-templates
POST /api/workspaces/{workspaceId}/command-templates/{templateId}/run
```

Rules:

- All endpoints require authenticated device token.
- Every workspace/run/template ID requires object-level authorization.
- No endpoint accepts raw cwd/cmd/args from mobile.

---

## 17. Protocol Events

New or hardened event types:

```text
adapter.detected
adapter.status.changed
run.queued
run.dequeued
run.blocked
run.cancelling
run.cancelled
adapter.raw_stdout
adapter.raw_stderr
adapter.parse_error
queue.updated
git.status.updated
command_template.started
command_template.output
command_template.completed
command_template.failed
```

Example:

```json
{
  "protocol": "agent-control.v1",
  "type": "run.queued",
  "seq": 41,
  "runId": "run_123",
  "timestamp": "2026-05-01T10:00:00Z",
  "payload": {
    "workspaceId": "my_app",
    "reason": "workspace_write_run_active",
    "position": 2
  }
}
```

Example parse error:

```json
{
  "protocol": "agent-control.v1",
  "type": "adapter.parse_error",
  "seq": 42,
  "runId": "run_123",
  "timestamp": "2026-05-01T10:00:01Z",
  "payload": {
    "adapterId": "codex",
    "stream": "stdout",
    "linePreview": "{bad json...",
    "recoverable": true
  }
}
```

---

## 18. Database Changes

Add or modify tables:

```sql
CREATE TABLE adapter_profiles (
  id TEXT PRIMARY KEY,
  adapter_id TEXT NOT NULL,
  invocation_mode TEXT NOT NULL,
  profile_json TEXT NOT NULL,
  enabled INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE run_queue (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  workspace_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  status TEXT NOT NULL,
  reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE command_templates (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  label TEXT NOT NULL,
  description TEXT,
  command TEXT NOT NULL,
  args_json TEXT NOT NULL,
  risk TEXT NOT NULL,
  requires_approval INTEGER NOT NULL,
  enabled INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE adapter_conformance_results (
  id TEXT PRIMARY KEY,
  adapter_id TEXT NOT NULL,
  test_name TEXT NOT NULL,
  status TEXT NOT NULL,
  details_json TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE audit_events (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  device_id TEXT,
  workspace_id TEXT,
  run_id TEXT,
  metadata_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);
```

Migration requirements:

- Preserve V1/V1.1 runs/events/devices.
- No destructive migration.
- Queue defaults to empty.
- Adapter profiles must be generated from current daemon config.
- Rollback plan must be documented.

---

## 19. Mobile UX Requirements

### 19.1 Run Create

Add:

- tool selector
- adapter capability badge
- permission mode
- queue warning
- shortcut/template section
- recent prompts

### 19.2 Run List

Add filters:

- workspace
- tool
- status
- queued/running/completed/failed
- date

### 19.3 Run Detail

Tabs:

```text
Timeline
Console
Changes
Details
```

Timeline:

- structured events
- assistant messages
- tool calls
- approval cards
- queue state

Console:

- raw stdout/stderr
- parse errors
- copy output
- search output

Changes:

- git status
- changed files
- diff preview
- additions/deletions
- truncation warning

Details:

- adapter
- adapter version
- invocation mode
- run mode
- queue info
- session ID if safe
- timestamps

### 19.4 Settings

Add:

- adapter diagnostics
- adapter enablement
- command templates
- queue policy
- device revocation
- diagnostic bundle export

---

## 20. Security Requirements

V1.2 must preserve all V1/V1.1 safety boundaries.

Requirements:

1. No PTY.
2. No arbitrary shell endpoint.
3. No arbitrary cwd from mobile.
4. No arbitrary CLI args from mobile.
5. Args passed as array to process spawn, not shell string.
6. Workspace ID maps to daemon-owned canonical path.
7. Path traversal rejected.
8. Command templates are daemon-owned.
9. Dangerous command templates require approval.
10. Adapter profiles cannot be modified from mobile in V1.2.
11. OpenCode credentials never leave daemon.
12. Provider auth state is exposed only as coarse status.
13. Logs must not include device token or provider API keys.
14. Token revocation invalidates REST and WebSocket access.
15. Queue prevents unsafe concurrent workspace writes by default.
16. Adapter diagnostics must not expose env vars or secrets.

---

## 21. Error Model

Add or harden these error codes:

```text
ADAPTER_NOT_INSTALLED
ADAPTER_NEEDS_AUTH
ADAPTER_NEEDS_CONFIGURATION
ADAPTER_UNSUPPORTED_VERSION
ADAPTER_INVOCATION_FAILED
ADAPTER_PARSE_ERROR
ADAPTER_CAPABILITY_MISSING
RUN_QUEUED
RUN_CANCELLED
RUN_RESUME_NOT_SUPPORTED
WORKSPACE_BUSY
WORKSPACE_NOT_FOUND
WORKSPACE_ACCESS_DENIED
COMMAND_TEMPLATE_NOT_FOUND
COMMAND_TEMPLATE_REQUIRES_APPROVAL
RAW_COMMAND_REJECTED
RAW_CWD_REJECTED
RAW_ARGS_REJECTED
GIT_NOT_REPOSITORY
GIT_PATH_OUTSIDE_WORKSPACE
GIT_DIFF_TOO_LARGE
TOKEN_REVOKED
```

Example:

```json
{
  "code": "RAW_COMMAND_REJECTED",
  "message": "Raw command execution is not allowed from mobile.",
  "recoverable": true,
  "userAction": "Use a configured command template instead."
}
```

---

## 22. Observability

Daemon logs should include:

- adapter detection result
- invocation profile selected
- process start/exit
- server adapter health check
- run queue enqueue/dequeue
- run cancellation
- parse errors
- command template invocation
- git status/diff errors
- token revocation

Daemon logs must not include:

- auth tokens
- provider API keys
- OpenCode basic auth password
- full environment variables
- raw secrets from `.env`
- private key material

---

## 23. Adapter Conformance Tests

Every adapter must be tested against the same behavior set.

### 23.1 Required Tests

```text
detect.available_or_unavailable
startRun.emits_started
startRun.emits_output
startRun.emits_terminal_status
cancel.supported_or_explicitly_not_supported
resume.supported_or_explicitly_not_supported
parse.malformed_output_does_not_crash
security.no_raw_cwd
security.no_raw_args
security.workspace_required
```

### 23.2 Synthetic Adapter

Add a synthetic adapter for CI:

```text
synthetic-jsonl
synthetic-text
synthetic-error
synthetic-slow
```

Purpose:

- test parser
- test queue
- test cancellation
- test replay
- test mobile UI without provider credentials

Acceptance criteria:

- Conformance tests can run without Claude/Codex/OpenCode installed.
- Real adapter tests are optional/integration tier.
- Synthetic adapter is never exposed in production UI unless dev mode is enabled.

---

## 24. Acceptance Tests

### Adapter Contract

- Given enabled adapter, `detect` returns explicit status.
- Given adapter without resume, UI does not show resume action.
- Given adapter parse error, run continues with raw fallback where safe.

### Run Queue

- Given active write run in workspace, second write run is queued.
- Given active read-only run, second read-only run can run if policy allows.
- Given queued run is cancelled, no process starts.
- Given running run completes, next queued run starts.

### Claude

- Given Claude available, run starts with stream-json.
- Given malformed Claude JSONL line, parser emits parse error and continues.
- Given session ID, resume action is available.

### Codex

- Given Codex available, run starts with `codex exec --json`.
- Given dangerous mode, daemon does not pass bypass sandbox flag.
- Given Codex resume supported, resume uses `codex exec resume`.

### OpenCode

- Given OpenCode server reachable, adapter is available.
- Given server unavailable, adapter is needs_configuration.
- Given OpenCode credentials configured, credentials are not exposed to Flutter.

### Aider

- Given Aider installed and enabled, `aider --message` runs one task.
- Given Aider exits non-zero, run is failed with stderr captured.
- Given Aider not installed, adapter is not_installed.

### Git

- Given git repo, status endpoint returns branch and changed files.
- Given path traversal in diff path, request is rejected.
- Given large diff, response is truncated.

### Command Templates

- Given template ID, command executes.
- Given raw command payload, request is rejected.
- Given high-risk template, approval is required.

### Security

- Mobile cannot set cwd.
- Mobile cannot pass arbitrary args.
- Mobile cannot invoke shell path.
- Revoked token loses API and WebSocket access.

---

## 25. Release Plan

### Phase 1: Contract and Profiles

- Define `CliTaskAdapter`.
- Define adapter capabilities.
- Define invocation profile schema.
- Add synthetic adapter.

### Phase 2: Output Normalization

- Harden JSONL parser.
- Add raw stdout/stderr event source.
- Add parse error events.
- Normalize exit codes.

### Phase 3: Run Queue

- Add workspace queue.
- Add concurrency policy.
- Add queue UI state.
- Add queue tests.

### Phase 4: Adapter Hardening

- Claude adapter conformance.
- Codex adapter conformance.
- OpenCode adapter conformance.
- Aider experimental adapter.

### Phase 5: Git / Changes

- Add git status endpoint.
- Add git diff endpoint.
- Add mobile Changes tab.
- Link diffs to run events.

### Phase 6: Command Templates

- Add template schema and APIs.
- Add default templates.
- Add mobile command buttons.
- Add approval rules.

### Phase 7: Security and Release

- Add audit events.
- Add diagnostic bundle.
- Add migration tests.
- Add redaction tests.
- Verify no PTY/shell/raw command API exists.

---

## 26. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Adapter output formats drift | Broken structured UI | Capability detection, conformance tests, raw fallback |
| Multiple agents edit same workspace | Conflicts/data loss | Run queue and one-writer default |
| Raw command sneaks into API | Security regression | Explicit reject tests and schema validation |
| CLI prompts require auth | Confusing failures | Adapter status `needs_auth` |
| OpenCode server API changes | Adapter failure | Health checks and version diagnostics |
| Aider changes output format | Poor UX | Plain text fallback only |
| Large diffs slow mobile UI | Poor performance | Truncation and hunk folding |
| Logs leak secrets | Security incident | Redaction and limited diagnostic export |

---

## 27. Open Decisions

1. Should Aider be included as experimental in V1.2, or only documented as future adapter?
2. Should run queue be strict by default for all adapters, or only write-capable modes?
3. Should command templates be editable from mobile, or daemon config only?
4. Should OpenCode use server mode only, or allow `opencode run` fallback?
5. Should git diff be generated by `git` CLI only, or support non-git file snapshots later?

Recommended answers:

1. Include Aider as disabled experimental adapter.
2. Strict one-writer default; allow parallel read-only.
3. Daemon config only for V1.2.
4. Server mode primary; `opencode run` fallback explicitly enabled only.
5. Git CLI only for V1.2.

---

## 28. References

- Claude Code headless / programmatic usage:
  - https://code.claude.com/docs/en/headless
  - https://code.claude.com/docs/en/common-workflows

- Codex CLI:
  - https://developers.openai.com/codex/cli/reference
  - https://developers.openai.com/codex/cli/features

- OpenCode:
  - https://opencode.ai/docs/server/
  - https://opencode.ai/docs/cli/

- Aider scripting:
  - https://aider.chat/docs/scripting.html

---

## 29. Final Recommendation

Ship V1.2 as **Multi-CLI Task Runner Hardening**.

Priority order:

1. Adapter contract.
2. Invocation profiles.
3. Output normalization.
4. Run queue.
5. Claude/Codex/OpenCode conformance.
6. Git status/diff review.
7. Command templates.
8. Aider experimental adapter.
9. Security and audit hardening.
10. Diagnostic bundle and release polish.

Do not implement PTY in V1.2.

Guiding rule:

> The phone creates and controls coding tasks; it does not become a remote shell.
