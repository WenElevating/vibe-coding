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
