# PRD: Flutter LAN AI CLI Control V1.3

## Metadata

- Slug: `flutter-lan-ai-cli-control-v1-3`
- Product: Flutter LAN AI CLI Control
- Previous milestone: V1.2 completed
- Target milestone: V1.3
- Status: Draft
- Date: 2026-05-01
- Primary platform: Android phone + Windows desktop daemon
- Primary mode: LAN-only
- V1.3 theme: Productization, Release Readiness, and Mobile UX Completion
- Explicit decision: No PTY, no remote terminal, no arbitrary shell/cwd/args

---

## 1. Background

V1 delivered the initial safe LAN control architecture.

V1.1 expanded the system into a multi-adapter skeleton with adapter registry, Codex explicit-enable JSONL adapter, OpenCode attach-mode diagnostics, shortcuts, token revocation, and diff summary modeling.

V1.2 completed task-runner hardening:

- Adapter contract/profile.
- Dev-only synthetic adapters.
- Workspace run queue.
- Git change review.
- Command templates.
- Expanded protocol/error model.
- Mobile protocol/client/model expansion.
- README update.
- New APIs:
  - `GET /api/queue`
  - `GET /api/workspaces/{workspaceId}/git/status`
  - `GET /api/workspaces/{workspaceId}/git/diff`
  - `GET /api/command-templates`
  - `POST /api/command-templates`
  - `POST /api/command-templates/{id}/invoke`
- Validation:
  - `npm run lint` passed.
  - `npm test` passed with 17 tests.
  - Dart analysis passed with no issues.
  - Security scan confirmed no PTY and continued rejection of arbitrary shell/cwd/args.

V1.3 should not add another deep architecture layer. It should make the product feel complete and reliable for daily use.

---

## 2. Product Goal

V1.3 turns the current engineering-complete task runner into a usable private LAN product.

The user should be able to:

- install and start the Windows daemon without reading source code
- install and use the Android app with clear onboarding
- pair phone and desktop confidently
- see daemon/tool/workspace health at a glance
- create and monitor runs from a polished mobile UI
- inspect queue, console, git changes, and command templates
- recover from errors using actionable guidance
- export diagnostic bundles when something breaks
- update versions without corrupting local state
- trust that the app keeps the existing security boundary

---

## 3. Core Product Decision

V1.3 is a **release-readiness milestone**, not a capability-expansion milestone.

The priority order is:

1. UX completion.
2. Install/startup experience.
3. Diagnostics.
4. End-to-end test coverage.
5. Security and privacy hardening.
6. Packaging and release channels.
7. Documentation.

V1.3 does not add PTY, remote terminal, arbitrary shell, cloud relay, or file upload/download.

---

## 4. Non-Goals

V1.3 intentionally does not include:

1. PTY.
2. Remote terminal.
3. Arbitrary PowerShell/cmd/bash.
4. Arbitrary command execution endpoint.
5. Arbitrary cwd or CLI args from mobile.
6. Public internet access.
7. Cloud relay.
8. File upload/download/browser.
9. Multi-user/team collaboration.
10. iOS support.
11. Automatic git commit/push.
12. Marketplace/plugin system.
13. Provider credential management UI.
14. Remote push notifications.

---

## 5. Personas

### Primary Persona: Daily Solo User

A developer wants to use the app every day to start, monitor, and steer local AI CLI tasks from a phone.

Needs:

- simple pairing
- obvious connection state
- reliable run creation
- readable run timeline
- clear failures
- quick command templates
- git changes after each run
- safe defaults

### Secondary Persona: Debugging User

A developer wants to understand what went wrong when a run, adapter, daemon, or mobile connection fails.

Needs:

- diagnostics page
- adapter status
- daemon logs
- exportable diagnostic bundle
- error codes with suggested fixes
- E2E smoke test

### Tertiary Persona: Release Maintainer

A developer wants to package, distribute, and update the Windows daemon and Android app safely.

Needs:

- versioning
- changelog
- migration checks
- release build pipeline
- signing instructions
- test matrix
- rollback plan

---

## 6. Success Metrics

V1.3 is successful if:

1. A new user can install the daemon and Android app, pair them, and start a synthetic run within 5 minutes.
2. The mobile app displays adapter, daemon, queue, workspace, and connection health without needing logs.
3. All V1.2 APIs used by the app are covered by at least one E2E test or synthetic integration test.
4. The product has separate dev and release configurations for the Android app.
5. Diagnostic bundle export includes enough local state to debug without exposing tokens or provider API keys.
6. A run can be created, queued, streamed, cancelled, replayed, and inspected from the mobile UI.
7. Git status/diff and command templates are visible and usable from the mobile UI.
8. Daemon upgrade preserves existing paired devices, workspaces, runs, events, queue, templates, and adapter profiles.
9. Mobile secure storage and logs pass a security review against the V1/V1.1/V1.2 boundaries.
10. There is still no PTY, no arbitrary shell, no arbitrary cwd, and no arbitrary args.

---

## 7. Scope

### 7.1 V1.3 Must Have

#### Mobile UX Completion

1. Home dashboard.
2. Adapter health page.
3. Daemon diagnostics page.
4. Queue UI.
5. Git changes tab/page.
6. Command templates UI.
7. Improved run detail layout.
8. Better empty/error/loading states.
9. Pairing rework with clear trust and LAN messaging.
10. Settings page with device revoke/logout.

#### Product Readiness

11. Android dev/release flavor separation.
12. Windows daemon dev/release mode separation.
13. Version endpoint and mobile version display.
14. Database migration status display.
15. Changelog and release notes template.

#### Diagnostics

16. Diagnostic bundle export.
17. Health check summary endpoint.
18. E2E smoke test endpoint using synthetic adapter.
19. Structured daemon logs with redaction.
20. Mobile in-app diagnostic screen.

#### Testing

21. E2E test harness against synthetic adapter.
22. Mobile integration test for onboarding and run creation.
23. API contract tests for V1.2 endpoints.
24. Migration tests.
25. Security regression tests for rejected raw command/cwd/args.

#### Packaging

26. Windows daemon packaging plan.
27. Android release APK build plan.
28. Local installation documentation.
29. Upgrade/rollback documentation.
30. Release checklist.

---

### 7.2 V1.3 Should Have

1. QR pairing improvement.
2. Adapter setup wizard.
3. Run output search in mobile UI.
4. Diff hunk folding.
5. Diagnostic bundle redaction preview.
6. In-app first-run tutorial.
7. Windows tray helper or launcher.
8. Basic crash log capture.
9. Local-only changelog view.
10. Test data reset button in dev mode.

---

### 7.3 V1.3 Won't Have

1. Cloud sync.
2. Public server.
3. Remote access outside LAN.
4. iOS.
5. Browser app.
6. Remote desktop.
7. Plugin marketplace.
8. Provider auth setup UI.
9. Interactive terminal.
10. File transfer.

---

## 8. Functional Requirements

## 8.1 Home Dashboard

The app opens to a dashboard after pairing.

Dashboard cards:

- Daemon connection state.
- Active run count.
- Queue count.
- Pending approval count.
- Adapter health summary.
- Workspace quick start.
- Recent runs.
- Command template shortcuts.

Example state:

```json
{
  "daemon": {
    "status": "connected",
    "version": "1.3.0",
    "lanMode": true
  },
  "runs": {
    "active": 1,
    "queued": 2,
    "failedToday": 1
  },
  "adapters": {
    "available": 3,
    "attention": 1
  }
}
```

Acceptance criteria:

- User can understand whether the system is usable from one screen.
- Dashboard works when no runs exist.
- Dashboard works when daemon is disconnected.
- Dashboard never shows auth tokens or raw secrets.

---

## 8.2 Adapter Health Page

The adapter health page shows:

- adapter name
- enabled/disabled
- available/not installed/needs auth/needs config/error
- version
- invocation mode
- capabilities
- last detection time
- suggested fix

Supported adapters:

- Claude Code
- Codex
- OpenCode
- Aider experimental
- Synthetic dev-only

Acceptance criteria:

- Disabled adapters are clearly separated from broken adapters.
- OpenCode attach-mode diagnostics are visible.
- Codex explicit enablement is visible.
- Synthetic adapter is hidden unless dev mode is enabled.

---

## 8.3 Daemon Diagnostics Page

The mobile app exposes daemon diagnostics.

Endpoint:

```http
GET /api/health
```

Response:

```json
{
  "status": "ok",
  "daemonVersion": "1.3.0",
  "platform": "windows",
  "lanMode": true,
  "bindAddress": "0.0.0.0",
  "port": 7070,
  "database": {
    "status": "ok",
    "schemaVersion": 5,
    "lastMigration": "2026-05-01T10:00:00Z"
  },
  "counts": {
    "workspaces": 3,
    "pairedDevices": 1,
    "activeRuns": 1,
    "queuedRuns": 2
  },
  "security": {
    "ptyEnabled": false,
    "rawCommandApiEnabled": false,
    "tokenHashing": true
  }
}
```

Acceptance criteria:

- App shows status in human-readable cards.
- Failed components show recommended action.
- Health endpoint does not expose env vars or secrets.
- Security boundary is visible.

---

## 8.4 Diagnostic Bundle Export

Add a local diagnostic bundle export endpoint.

Endpoint:

```http
POST /api/diagnostics/export
```

Response:

```json
{
  "bundleId": "diag_123",
  "createdAt": "2026-05-01T10:00:00Z",
  "path": "local-daemon-path",
  "redacted": true,
  "items": [
    "daemon_status",
    "adapter_status",
    "recent_errors",
    "schema_version",
    "run_summary",
    "queue_summary"
  ]
}
```

Bundle contents:

- daemon version
- OS/platform info
- database schema version
- adapter statuses
- recent run summaries
- recent error codes
- queue summary
- command template summary
- redaction report

Must not include:

- device tokens
- provider API keys
- OpenCode basic auth password
- full environment variables
- full source code
- raw `.env`
- private keys
- complete raw console output by default

Acceptance criteria:

- User can create diagnostic bundle from mobile.
- Bundle path is shown on desktop/daemon side or copied.
- Bundle is redacted by default.
- Bundle export is audited.

---

## 8.5 Pairing UX Hardening

Pairing flow should make LAN trust clear.

Flow:

1. App opens unpaired state.
2. User taps "Pair desktop".
3. App explains that both devices must be on same LAN.
4. Daemon displays QR/code.
5. User scans or enters code.
6. App shows daemon name, host, LAN mode, and security summary.
7. User confirms trust.
8. Token is stored securely.
9. App lands on dashboard.

Acceptance criteria:

- Expired code fails with clear message.
- Wrong daemon host fails clearly.
- Re-pairing works after logout/revoke.
- App can forget device.
- Token is never displayed after pairing.

---

## 8.6 Queue UI

The app must expose V1.2 run queue.

Queue screen/card shows:

- queued runs
- active run
- workspace
- tool
- position
- reason
- cancel queued action

Acceptance criteria:

- Queued run is visible.
- Cancelling queued run updates state.
- Queue updates are reflected after reconnect.
- Queue status appears in run detail.

---

## 8.7 Git Changes UI

The app must expose git status and diff endpoints.

UI sections:

- branch
- ahead/behind
- changed files count
- file list
- additions/deletions
- diff preview
- truncation warning
- copy path

Acceptance criteria:

- Non-git workspace has clear empty state.
- Large diff shows truncation message.
- Path traversal is impossible from UI.
- Changed files link back to relevant run where available.

---

## 8.8 Command Templates UI

The app must expose command templates.

UI sections:

- global templates
- workspace templates
- template risk
- requires approval badge
- invoke button
- recent invocations

Rules:

- Mobile invokes by template ID only.
- Mobile cannot edit raw command by default.
- High-risk templates create approval flow.
- Template output is linked to run/console.

Acceptance criteria:

- User can invoke test/lint/build templates.
- Unknown template returns clear error.
- Raw command input is not present in release UI.
- High-risk template approval appears in approval center.

---

## 8.9 Run Detail Polish

Run detail should become the primary daily-use screen.

Tabs:

```text
Timeline
Console
Changes
Details
```

Timeline:

- assistant messages
- tool calls
- approvals
- queue state
- errors
- command template events

Console:

- stdout/stderr
- parse errors
- search
- copy
- collapsed noisy output

Changes:

- git status
- diff summaries
- file changes
- approval links

Details:

- run ID short form
- adapter
- adapter version
- invocation mode
- workspace
- mode
- status
- timestamps
- queue info
- session ID if safe

Acceptance criteria:

- Run detail remains usable with long output.
- Errors have suggested actions.
- Console can search text.
- Details expose enough debug context without secrets.

---

## 8.10 Release Flavors and Modes

Add dev/release separation.

Android flavors:

```text
dev
release
```

Dev flavor:

- dev app name/icon suffix
- synthetic adapter visible
- verbose logs allowed
- test reset tools visible
- localhost/mock endpoints easier to configure

Release flavor:

- production app name/icon
- synthetic adapter hidden
- verbose logs disabled by default
- diagnostic export redacted
- no debug-only controls

Daemon modes:

```text
development
release
```

Development mode:

- synthetic adapter enabled
- more logs
- reset tools
- local test helpers

Release mode:

- synthetic adapter hidden
- stricter logs
- no test reset API
- diagnostics redacted

Acceptance criteria:

- User can distinguish dev and release builds.
- Release build does not expose synthetic adapter.
- Release build keeps security checks enabled.
- Dev-only endpoints are disabled in release mode.

---

## 9. API Changes

### 9.1 Health

```http
GET /api/health
```

### 9.2 Diagnostics

```http
POST /api/diagnostics/export
GET /api/diagnostics/bundles
GET /api/diagnostics/bundles/{bundleId}
```

### 9.3 Version

```http
GET /api/version
```

Example:

```json
{
  "daemonVersion": "1.3.0",
  "protocolVersion": "agent-control.v1",
  "schemaVersion": 5,
  "build": {
    "channel": "dev",
    "commit": "abc123",
    "builtAt": "2026-05-01T10:00:00Z"
  }
}
```

### 9.4 E2E Smoke

Dev mode only:

```http
POST /api/dev/smoke-test
```

Rules:

- disabled in release mode
- uses synthetic adapter only
- does not touch real workspaces unless explicitly configured

---

## 10. Protocol Events

New events:

```text
daemon.health.changed
diagnostics.bundle.created
mobile.sync.completed
app.version.mismatch
queue.summary.updated
release.mode.changed
```

Example:

```json
{
  "protocol": "agent-control.v1",
  "type": "daemon.health.changed",
  "seq": 200,
  "timestamp": "2026-05-01T10:00:00Z",
  "payload": {
    "status": "degraded",
    "reason": "opencode_needs_configuration"
  }
}
```

Backward compatibility:

- V1/V1.1/V1.2 clients ignore unknown V1.3 events.
- V1.3 app still handles V1.2 daemon responses where possible.
- Version mismatch produces warning, not crash.

---

## 11. Database Changes

Add or modify:

```sql
CREATE TABLE diagnostic_bundles (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL,
  redacted INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  metadata_json TEXT NOT NULL
);

CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  checksum TEXT
);

CREATE TABLE health_snapshots (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);
```

Migration requirements:

- Preserve all V1/V1.1/V1.2 data.
- Add schema version display.
- Add migration validation.
- Add rollback notes.
- Do not enable new risky features during migration.

---

## 12. Mobile UX Requirements

### 12.1 Navigation

Recommended bottom navigation:

```text
Home
Runs
Queue
Workspaces
Settings
```

Secondary pages:

- Adapter Health
- Diagnostics
- Command Templates
- Changes
- Device Management

### 12.2 Empty States

Every page must have empty states:

- no daemon paired
- daemon disconnected
- no workspace
- no adapters available
- no runs
- no queue
- no git repository
- no command templates

### 12.3 Error States

Every error card must include:

- plain language message
- error code
- affected component
- suggested action
- copy diagnostics action where relevant

### 12.4 Loading States

Use skeleton or compact spinners for:

- dashboard
- run list
- adapter status
- diagnostics
- git status
- command templates

---

## 13. Security Requirements

V1.3 must preserve all prior security boundaries.

Requirements:

1. No PTY.
2. No remote terminal.
3. No arbitrary shell endpoint.
4. No arbitrary cwd from mobile.
5. No arbitrary CLI args from mobile.
6. Release build hides synthetic adapter.
7. Diagnostic bundle redacts secrets.
8. Diagnostic bundle excludes full env vars.
9. Tokens are never logged.
10. Device revocation invalidates REST and WebSocket access.
11. Dev-only endpoints disabled in release mode.
12. Build channel is visible.
13. Android token storage remains secure.
14. App logs avoid sensitive values.
15. Backup/export behavior must not leak tokens.
16. Health endpoint must not expose sensitive local paths beyond necessary diagnostics.

---

## 14. Privacy and Local Data

The product is LAN-only and local-first.

Local data includes:

- paired device token on Android
- daemon token hash
- workspaces
- run metadata
- run events
- adapter status
- command templates
- diagnostic bundles

Privacy rules:

- no telemetry in V1.3
- no cloud sync
- no remote analytics
- diagnostic bundles are user-triggered
- diagnostic bundles are local files
- sensitive values are redacted by default

---

## 15. Testing Requirements

### 15.1 Backend

Required tests:

- health endpoint
- version endpoint
- diagnostic bundle redaction
- release mode hides dev APIs
- synthetic smoke test in dev mode
- migration validation
- token revocation
- raw command/cwd/args rejection
- queue API
- git API
- command template API

### 15.2 Mobile

Required tests:

- pairing flow
- dashboard renders connected/disconnected states
- run creation with synthetic adapter
- queue display
- git changes display
- command template invocation
- adapter health page
- diagnostics page
- logout/revoke state
- version mismatch warning

### 15.3 E2E

Required E2E smoke path:

1. Start daemon in dev mode.
2. Pair app.
3. Load dashboard.
4. Run synthetic adapter task.
5. Receive streamed output.
6. Queue second run.
7. Cancel queued run.
8. View git status mock or fixture.
9. Invoke command template.
10. Export diagnostic bundle.
11. Revoke device.
12. Verify API/WebSocket access is denied.

---

## 16. Packaging and Release

### 16.1 Windows Daemon

V1.3 should define packaging plan for Windows.

Required:

- release build command
- version embedding
- config location
- database location
- log location
- launch instructions
- firewall/LAN note
- uninstall/reset instructions

Should have:

- installer or zip distribution
- tray launcher
- start-on-login option
- upgrade notes

### 16.2 Android App

Required:

- dev flavor
- release flavor
- release APK build command
- signing documentation
- version name/code
- changelog
- installation instructions

Suggested commands:

```bash
flutter build apk --flavor release
```

and for dev:

```bash
flutter run --flavor dev
```

### 16.3 Release Checklist

Before release:

- backend tests pass
- mobile analysis passes
- mobile integration tests pass
- security scan passes
- no TODO/FIXME/debugger in release paths
- no PTY references
- no raw command/cwd/args APIs
- diagnostic redaction test passes
- migration test passes
- release notes written
- rollback plan written

---

## 17. Error Model

Add or harden:

```text
DAEMON_UNHEALTHY
DAEMON_VERSION_MISMATCH
SCHEMA_MIGRATION_FAILED
DIAGNOSTIC_EXPORT_FAILED
DIAGNOSTIC_REDACTION_FAILED
DEV_API_DISABLED
RELEASE_MODE_REQUIRED
MOBILE_VERSION_UNSUPPORTED
PAIRING_CODE_EXPIRED
PAIRING_DAEMON_MISMATCH
ADAPTER_SETUP_REQUIRED
SYNTHETIC_ADAPTER_HIDDEN
```

Example:

```json
{
  "code": "DEV_API_DISABLED",
  "message": "This endpoint is only available in daemon development mode.",
  "recoverable": false,
  "userAction": "Use a development daemon build to run smoke tests."
}
```

---

## 18. Observability

Daemon logs should include:

- startup mode
- version
- schema migration result
- health status changes
- adapter detection changes
- pairing attempts
- device revocation
- run lifecycle
- queue lifecycle
- diagnostic export
- redaction failures

Daemon logs must not include:

- device token
- provider API keys
- OpenCode auth password
- full environment variables
- full `.env`
- private key material
- unredacted diagnostic bundle content

Mobile logs should include:

- screen-level errors
- API error codes
- daemon connection state
- version mismatch

Mobile logs must not include:

- device token
- provider secrets
- raw console output by default
- diagnostic bundle content

---

## 19. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Product remains engineering-only | Low adoption | V1.3 focuses on UX, onboarding, diagnostics |
| Release mode accidentally exposes dev tools | Security regression | build mode checks and tests |
| Diagnostic bundle leaks secrets | Severe security issue | redaction tests and preview |
| Version mismatch breaks app | Poor UX | explicit version endpoint and warning |
| Migration corrupts data | Data loss | migration tests and rollback notes |
| Packaging complexity delays release | Slower adoption | start with zip/APK, installer later |
| Mobile UI hides important failure | Debugging friction | health dashboard and error action cards |

---

## 20. Open Decisions

1. Should Windows daemon V1.3 ship as zip, installer, or both?
2. Should tray launcher be V1.3 must-have or V1.4?
3. Should diagnostic bundle be generated on daemon filesystem only, or downloadable to mobile?
4. Should release Android app be sideload-only for now?
5. Should dev/release flavor use different app IDs?

Recommended answers:

1. Ship zip first; installer can be V1.4 if packaging slows progress.
2. Tray launcher should be V1.3 should-have, not must-have.
3. Generate on daemon filesystem only for V1.3 to avoid sensitive mobile transfer.
4. Sideload-only is fine for private LAN tool.
5. Yes, use separate app IDs for dev and release.

---

## 21. References

- Flutter flavors:
  - https://docs.flutter.dev/deployment/flavors
- Flutter integration testing:
  - https://docs.flutter.dev/testing/integration-tests
  - https://docs.flutter.dev/cookbook/testing/integration/introduction
- Android build variants:
  - https://developer.android.com/build/build-variants
- OWASP MASVS:
  - https://mas.owasp.org/MASVS/
  - https://mas.owasp.org/MASVS/05-MASVS-STORAGE/
  - https://mas.owasp.org/MASVS/07-MASVS-AUTH/
- Electron auto update references if daemon UI/tray becomes Electron-based later:
  - https://www.electron.build/auto-update.html
  - https://electronjs.org/docs/latest/tutorial/updates

---

## 22. Final Recommendation

Ship V1.3 as **Productization and Release Readiness**.

Priority order:

1. Home dashboard.
2. Adapter health and daemon diagnostics.
3. Queue, git changes, command templates UI.
4. Diagnostic bundle export.
5. Dev/release modes and Android flavors.
6. E2E smoke tests with synthetic adapter.
7. Migration and security regression tests.
8. Packaging docs.
9. Release checklist.
10. UX polish and error states.

Do not expand into PTY or remote terminal.

Guiding rule:

> V1.3 should make the existing task-runner architecture dependable, understandable, and shippable.
