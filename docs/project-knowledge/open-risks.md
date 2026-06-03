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
  production migration still needs daemon lifecycle, transport, auth/session,
  capability listing, and project-trust behavior work.
- Evidence: `daemon/src/codex-app-server-bridge.js` and
  `scripts/run-tests.js` validate protocol/request/event parity; local Codex
  source shows `exec` rejects responsive approval requests while app-server
  defines them.
- Mitigation: implement a fake-transport adapter-handle integration test before
  replacing `codex exec --json`; then smoke test against real `codex
  app-server`.
- Related: `docs/codex-app-server-replacement-validation.md`
- Last verified: 2026-06-03
