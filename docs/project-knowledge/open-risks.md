# Open Risks

- Status: active seed
- Last verified: 2026-05-22

## Risk: Local Flutter/Dart Commands May Timeout In Agent Runs

- Level: medium
- Impact: agent cannot always independently verify mobile changes.
- Evidence: targeted `flutter test` and `dart format` commands timed out in
  agent runs while the user later ran equivalent commands successfully.
- Mitigation: stop after first timeout, provide the exact mirror-configured
  command, and rely on user-run output only when explicitly provided.
- Related: [build-and-test.md](build-and-test.md)

## Risk: Project Knowledge Can Drift

- Level: medium
- Impact: agents may trust stale architecture or troubleshooting entries.
- Mitigation: every active entry carries `Last verified`; run
  `node scripts/check-project-knowledge.js` for cheap structural checks.
- Re-evaluate when: stale-date checks move from manual review to automation.

## Risk: Docs Are Ignored By Default

- Level: low
- Impact: intentional docs under `docs/` do not appear in normal `git status`.
- Evidence: `.gitignore` ignores `docs/`.
- Mitigation: use `git add -f` for intentional docs commits.

## Risk: Connection Bootstrap Perf Marks Need A Pre-Reporter Boundary

- Level: low
- Impact: `app.main.started` and `app.first_frame` use the two-slot startup
  buffer, but `daemon.health.loaded` and `workspace.list.loaded` occur during
  daemon connection before `MainPage` creates `PerformanceTraceReporter`.
  Recording those marks with exact timestamps needs an explicit connection
  bootstrap buffer or a narrower definition that records when data becomes
  available to the connected UI.
- Evidence: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart`
  loads health and initial data before `mobile/lib/src/ui/main/main_page.dart`
  creates the reporter; `docs/superpowers/specs/2026-06-06-performance-tracing-design.md`
  lists the marks, while the implementation intentionally keeps the startup
  buffer limited to two startup marks.
- Mitigation: do not expand the startup buffer casually. Add a dedicated
  connection bootstrap trace handoff if analysis later requires exact health
  and workspace-list timing.
- Last verified: 2026-06-07

## Risk: Codex App-Server Migration Is Not A Drop-In Adapter Swap

- Level: medium
- Impact: Codex mobile approval can be implemented through app-server, but a
  production default-route migration still needs conservative rollout and real
  file-change/permissions approval smoke evidence.
- Evidence: `daemon/src/codex-app-server-bridge.js` and
  `daemon/src/codex-app-server-conversation-adapter.js` validate
  protocol/request/event parity, fallback boundaries, lifecycle cleanup,
  approval timeout behavior, and structured provider session persistence.
  `docs/superpowers/fixtures/codex-app-server/smoke-report-2026-06-03.md`
  records real stdio smoke against installed `codex app-server`, including
  command approval, resume/rejoin with persisted thread id, and native
  `localImage` input.
- Mitigation: keep `codex-app-server` behind
  `CODEX_APP_SERVER_ENABLED=1`, `CODEX_APP_SERVER_EXPERIMENTAL_API=1`,
  stdio transport, and `CODEX_APP_SERVER_ROLLOUT_PERCENT>0`; keep
  `thread/start` and `thread/resume` read-only, and require remaining
  file-change/permissions approval smoke before making it the default `codex`
  route.
- Related: `docs/superpowers/specs/2026-06-03-codex-app-server-adapter-design.md`
- Last verified: 2026-06-03

## Risk: OpenCode Prompt Dispatch Can Race Provider Events

- Level: medium
- Impact: `opencode serve` emits turn events on the shared `/global/event`
  stream. If the daemon sends `prompt_async` before the SSE subscription is
  actually open, early `session.idle`, `permission.asked`, or error events can
  be missed and leave a conversation running or waiting incorrectly.
- Evidence: `daemon/src/opencode-server-client.js` exposes
  `subscription.opened`; `daemon/src/opencode-conversation-adapter.js` and
  `daemon/src/opencode-adapter.js` wait for that signal before prompt dispatch.
  `scripts/run-tests.js` includes deterministic regression tests for both the
  conversation adapter and legacy run path.
- Mitigation: preserve the SSE-open-before-prompt invariant when changing
  OpenCode client, adapter, lifecycle, or fake-server code.
- Last verified: 2026-06-09

## Risk: OpenCode Managed Shutdown Cleanup Can Fail By Platform API

- Level: low
- Impact: Windows process-tree cleanup (`taskkill`) or direct `child.kill` can
  fail during daemon shutdown. Those failures must not abort daemon resource
  cleanup or leave lifecycle status stuck in `stopping`.
- Evidence: `daemon/src/opencode-server-lifecycle.js` wraps process-tree
  termination and direct child kill as best-effort cleanup; `scripts/run-tests.js`
  covers thrown process-tree terminators and thrown `child.kill` calls.
- Mitigation: keep managed OpenCode child cleanup best-effort and preserve
  regression tests when changing lifecycle shutdown behavior.
- Last verified: 2026-06-09

## Risk: Provider IDs Can Contain URL-Reserved Characters

- Level: medium
- Impact: OpenCode permission ids and other provider-owned ids may contain
  characters such as `/`, spaces, or `%`. If mobile sends them as raw path text
  or daemon compares percent-encoded route captures directly, approvals can fail
  with a false id mismatch or miss the route entirely.
- Evidence: `daemon/src/server.js` decodes route path segments before comparing
  ids; `mobile/lib/src/services/daemon_client.dart` and
  `mobile/lib/src/services/conversation_client.dart` encode id path segments.
  `scripts/run-tests.js` covers an OpenCode approval id containing URL-reserved
  characters.
- Mitigation: encode every id inserted into mobile URL path segments and decode
  every daemon route segment before domain/service lookup.
- Last verified: 2026-06-09

## Risk: OpenCode Public Error Surfaces Can Leak Provider Diagnostics

- Level: medium
- Impact: lifecycle, SSE, or provider-client errors may contain local paths,
  query strings, or provider response bodies. Copying raw `error.message` or
  recursive `error.details` into adapter status or conversation timeline events
  can expose those values to paired mobile clients and diagnostic exports.
- Evidence: `daemon/src/opencode-conversation-adapter.js` projects lifecycle
  diagnostics, stream-error causes, and missing-session HTTP error details
  through allowlists; `scripts/run-tests.js` covers lifecycle diagnostics
  exceptions, active-turn stream errors, and stale provider session ids with
  secret path/body/query fixtures.
- Mitigation: preserve allowlist projection for OpenCode public diagnostics and
  conversation event details. Do not add raw provider exception messages/details
  to public status, timeline, or diagnostic-export surfaces.
- Last verified: 2026-06-09
