# Codex App-Server Phase 1 Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce real Codex app-server smoke evidence, sanitized fixtures, and pass/fail gates before any production adapter implementation begins.

**Architecture:** This phase adds repo-local smoke documentation and fixture capture conventions around the local upstream Codex checkout at `D:\GithubProject\codex`. The smoke uses upstream-supported app-server commands first, records real JSON-RPC traffic, sanitizes it, and writes a gate report that later fake transport tests must consume. No production `CodexAppServerConversationAdapter` is added in this phase.

**Tech Stack:** Node.js scripts/docs in this repo, upstream Rust/Cargo Codex checkout, `codex-app-server-test-client`, JSON fixtures, `node scripts/check-project-knowledge.js`.

---

## Scope

This plan implements only Phase 1 from `docs/superpowers/specs/2026-06-03-codex-app-server-adapter-design.md`.

Do not create or modify:

- `daemon/src/codex-app-server-conversation-adapter.js`
- `daemon/src/main.js`
- `daemon/src/conversation-manager.js`
- `mobile/`

Those belong to later plans after Phase 1 fixtures and gates exist.

## File Structure

- Create: `docs/superpowers/fixtures/codex-app-server/README.md`
  - Defines fixture layout, redaction rules, and provenance requirements.
- Create: `docs/superpowers/fixtures/codex-app-server/manifest.json`
  - Machine-readable list of required Phase 1 evidence and pass/fail status.
- Create: `docs/superpowers/fixtures/codex-app-server/smoke-report-template.md`
  - Manual report template for real smoke evidence.
- Create: `docs/superpowers/fixtures/codex-app-server/samples/.gitkeep`
  - Keeps the sample directory present before real sanitized captures are added.
- Create: `docs/superpowers/plans/2026-06-03-codex-app-server-phase-1-smoke.md`
  - This plan.

---

### Task 1: Create Fixture Directory Contract

**Files:**
- Create: `docs/superpowers/fixtures/codex-app-server/README.md`
- Create: `docs/superpowers/fixtures/codex-app-server/samples/.gitkeep`

- [ ] **Step 1: Write the fixture README**

Create `docs/superpowers/fixtures/codex-app-server/README.md` with:

```markdown
# Codex App-Server Smoke Fixtures

These fixtures are the required Phase 1 evidence for the
`codex-app-server` adapter design.

## Source

- vibe-coding repo: `D:\AiProject\vibe-coding`
- Codex source checkout: `D:\GithubProject\codex`
- Codex commands run from: `D:\GithubProject\codex\codex-rs`

## Required Samples

Each sample must be captured from a real `codex app-server` run, not hand-written.

- initialize handshake
- lightweight model/list or equivalent non-turn request
- thread/start
- turn/start
- completed turn
- interrupted turn
- failed turn, if safely reproducible
- command approval request/response
- file-change approval request/response
- permissions approval request/response, if reproducible
- approval timeout or disconnect behavior
- transport close/disconnect

## Redaction Rules

Before committing a sample:

- replace local user home paths with `<USER_HOME>`
- replace repo-specific temporary paths with `<WORKSPACE>`
- replace auth tokens, cookies, API keys, and bearer strings with `<REDACTED_SECRET>`
- replace machine names and device ids with stable redaction tokens
- remove raw environment blocks
- remove unredacted stderr logs unless needed for a pass/fail gate

## Pass/Fail Rule

The `manifest.json` file is the gate. If any required gate is `fail` or
`unknown`, production app-server adapter implementation must not begin.
```

- [ ] **Step 2: Keep the samples directory**

Create `docs/superpowers/fixtures/codex-app-server/samples/.gitkeep` as an empty file.

- [ ] **Step 3: Verify files exist**

Run:

```powershell
Get-Content docs\superpowers\fixtures\codex-app-server\README.md
Get-ChildItem docs\superpowers\fixtures\codex-app-server\samples -Force
```

Expected:

```text
README.md content prints without mojibake
.gitkeep appears in the samples directory
```

- [ ] **Step 4: Commit**

```bash
git add -f docs/superpowers/fixtures/codex-app-server/README.md docs/superpowers/fixtures/codex-app-server/samples/.gitkeep
git commit -m "Document app-server smoke fixture contract"
```

---

### Task 2: Add Phase 1 Manifest

**Files:**
- Create: `docs/superpowers/fixtures/codex-app-server/manifest.json`

- [ ] **Step 1: Write manifest skeleton**

Create `docs/superpowers/fixtures/codex-app-server/manifest.json`:

```json
{
  "schemaVersion": 1,
  "status": "not_run",
  "vibeCodingRepo": "D:\\AiProject\\vibe-coding",
  "codexSourceCheckout": "D:\\GithubProject\\codex",
  "codexSourceCommit": null,
  "codexBinary": null,
  "transportTested": null,
  "startedAt": null,
  "completedAt": null,
  "gates": {
    "initializeWithin10s": "unknown",
    "tenSequentialTurns": "unknown",
    "threeApprovalRoundTrips": "unknown",
    "approvalLatencyP95Under2s": "unknown",
    "cancellationCleanupWithinDeadline": "unknown",
    "largeOutputNoPipeBlock": "unknown",
    "noOrphanProcesses": "unknown",
    "sideEffectFreeProbeCreatesNoThread": "unknown",
    "sessionScopeFieldIdentified": "unknown",
    "projectTrustBehaviorKnown": "unknown",
    "userInputRequestBehaviorKnown": "unknown"
  },
  "samples": [],
  "notes": []
}
```

- [ ] **Step 2: Validate JSON parses**

Run:

```powershell
node -e "const fs=require('node:fs'); JSON.parse(fs.readFileSync('docs/superpowers/fixtures/codex-app-server/manifest.json','utf8')); console.log('manifest ok')"
```

Expected:

```text
manifest ok
```

- [ ] **Step 3: Commit**

```bash
git add -f docs/superpowers/fixtures/codex-app-server/manifest.json
git commit -m "Add app-server smoke gate manifest"
```

---

### Task 3: Add Smoke Report Template

**Files:**
- Create: `docs/superpowers/fixtures/codex-app-server/smoke-report-template.md`

- [ ] **Step 1: Write report template**

Create `docs/superpowers/fixtures/codex-app-server/smoke-report-template.md`:

```markdown
# Codex App-Server Smoke Report

- Date:
- Operator:
- vibe-coding commit:
- Codex source commit:
- Codex binary:
- Transport:
- Workspace:

## Commands

```powershell
cd D:\GithubProject\codex\codex-rs
cargo build -p codex-cli --bin codex
cargo run -p codex-app-server-test-client -- --codex-bin .\target\debug\codex serve --listen ws://127.0.0.1:<PORT> --kill
cargo run -p codex-app-server-test-client -- --url ws://127.0.0.1:<PORT> model-list
cargo run -p codex-app-server-test-client -- --url ws://127.0.0.1:<PORT> watch
```

Use an isolated or reserved local port. Do not reuse `4222` blindly.

## Gate Results

| Gate | Result | Evidence |
| --- | --- | --- |
| initialize within 10s | unknown | |
| 10 sequential turns | unknown | |
| 3 approval round trips | unknown | |
| approval p95 latency under 2s | unknown | |
| cancellation cleanup deadline | unknown | |
| large output no pipe block | unknown | |
| no orphan processes | unknown | |
| side-effect-free probe creates no thread | unknown | |
| session scope field identified | unknown | |
| project trust behavior known | unknown | |
| user-input request behavior known | unknown | |

## Captured Samples

List each sanitized sample file under `samples/`.

## Decisions

- Transport selected for Phase 2:
- Capabilities to expose:
- Capabilities to lower or omit:
- App-server selectable:

## Follow-up

List only blockers that prevent Phase 2 adapter work.
```

- [ ] **Step 2: Verify template renders as plain markdown**

Run:

```powershell
Get-Content docs\superpowers\fixtures\codex-app-server\smoke-report-template.md
```

Expected:

```text
The file prints with command fences and no incomplete-marker text
```

- [ ] **Step 3: Commit**

```bash
git add -f docs/superpowers/fixtures/codex-app-server/smoke-report-template.md
git commit -m "Add app-server smoke report template"
```

---

### Task 4: Run Real Upstream Smoke

**Files:**
- Modify: `docs/superpowers/fixtures/codex-app-server/manifest.json`
- Create: `docs/superpowers/fixtures/codex-app-server/samples/<date>-*.json`
- Create: `docs/superpowers/fixtures/codex-app-server/smoke-report-<date>.md`

- [ ] **Step 1: Capture source commits**

Run:

```powershell
git status --short --branch
git -C D:\GithubProject\codex rev-parse HEAD
git -C D:\GithubProject\codex status --short --branch
```

Expected:

```text
vibe-coding status is understood before adding fixtures
Codex commit hash is recorded in the smoke report
Codex source dirty state is recorded if present
```

- [ ] **Step 2: Build upstream codex**

Run:

```powershell
cd D:\GithubProject\codex\codex-rs
cargo build -p codex-cli --bin codex
```

Expected:

```text
target\debug\codex.exe exists
```

- [ ] **Step 3: Start websocket smoke server on an isolated port**

Pick a free local port and record it as `<PORT>`.

Run:

```powershell
cd D:\GithubProject\codex\codex-rs
cargo run -p codex-app-server-test-client -- --codex-bin .\target\debug\codex serve --listen ws://127.0.0.1:<PORT> --kill
```

Expected:

```text
started codex app-server
```

- [ ] **Step 4: Watch raw messages**

In another terminal, run:

```powershell
cd D:\GithubProject\codex\codex-rs
cargo run -p codex-app-server-test-client -- --url ws://127.0.0.1:<PORT> watch
```

Expected:

```text
initialize response is printed
inbound JSON-RPC messages stream until interrupted
```

- [ ] **Step 5: Exercise stable non-turn request**

Run:

```powershell
cd D:\GithubProject\codex\codex-rs
cargo run -p codex-app-server-test-client -- --url ws://127.0.0.1:<PORT> model-list
```

Expected:

```text
model list request succeeds or a sanitized auth/model error is captured
```

- [ ] **Step 6: Exercise completed turn**

Run:

```powershell
cd D:\GithubProject\codex\codex-rs
cargo run -p codex-app-server-test-client -- --url ws://127.0.0.1:<PORT> send-message-v2 "Reply with exactly: app-server smoke ok"
```

Expected:

```text
thread/start, turn/start, turn/started, assistant item events, and turn/completed are captured
```

- [ ] **Step 7: Exercise resume/rejoin**

Run:

```powershell
cd D:\GithubProject\codex\codex-rs
cargo run -p codex-app-server-test-client -- --url ws://127.0.0.1:<PORT> thread-list --limit 5
cargo run -p codex-app-server-test-client -- --url ws://127.0.0.1:<PORT> resume-message-v2 <THREAD_ID> "Reply with exactly: resumed smoke ok"
```

Expected:

```text
The same app-server thread id can be resumed or a documented recoverable error is captured
```

- [ ] **Step 8: Exercise approval and cancellation cases**

Use prompts that safely trigger approval in a temporary workspace. Record exact prompts in the smoke report.

Expected:

```text
At least 3 approval request/response flows are captured, or blockers are documented with upstream source citations
Cancellation emits an interrupt/cancel sequence and process cleanup evidence is recorded
```

- [ ] **Step 9: Sanitize samples**

For every captured JSON sample, replace secrets and paths according to `README.md`.

Expected:

```text
No raw token, home directory, temp directory, machine id, or environment block remains in committed samples
```

- [ ] **Step 10: Update manifest and report**

Set `manifest.json.status` to `pass`, `fail`, or `blocked`. Fill every gate with `pass`, `fail`, or `blocked`.

Expected:

```text
No gate remains "unknown"
```

- [ ] **Step 11: Commit smoke evidence**

```bash
git add -f docs/superpowers/fixtures/codex-app-server
git commit -m "Capture codex app-server phase one smoke evidence"
```

---

### Task 5: Add Fixture Structural Check

**Files:**
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Add failing test for manifest completeness**

Append a test near existing documentation/fixture tests in `scripts/run-tests.js`:

```javascript
test('Codex app-server smoke manifest has no unknown gates after Phase 1', () => {
  const manifestPath = path.join(__dirname, '..', 'docs', 'superpowers', 'fixtures', 'codex-app-server', 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.schemaVersion, 1);
  assert.ok(['pass', 'fail', 'blocked', 'not_run'].includes(manifest.status));
  if (manifest.status === 'not_run') return;
  for (const [gate, result] of Object.entries(manifest.gates || {})) {
    assert.ok(['pass', 'fail', 'blocked'].includes(result), `${gate} has invalid result ${result}`);
  }
});
```

- [ ] **Step 2: Run test to verify current expected behavior**

Run:

```powershell
node scripts\run-tests.js
```

Expected before real smoke:

```text
All tests pass because status is not_run and gates may remain unknown
```

Expected after real smoke:

```text
All tests pass only when every gate is pass, fail, or blocked
```

- [ ] **Step 3: Commit structural check**

```bash
git add scripts/run-tests.js
git commit -m "Check app-server smoke manifest structure"
```

---

## Final Verification

- [ ] **Step 1: Run project knowledge check**

```powershell
node scripts\check-project-knowledge.js
```

Expected:

```text
Project knowledge check passed
```

- [ ] **Step 2: Run daemon regression tests**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

- [ ] **Step 3: Confirm git state**

```powershell
git status --short --branch
```

Expected:

```text
No unstaged files from Phase 1 remain
```

## Handoff Criteria

Phase 2 adapter planning may begin only when:

- `manifest.json.status` is `pass`, or `blocked` with an explicit decision not to continue implementation;
- every gate is `pass`, `fail`, or `blocked`;
- real sanitized samples exist for every supported app-server path the adapter will implement;
- the report states whether `codex-app-server` can be selectable;
- the report states the selected transport or says app-server remains unavailable.
