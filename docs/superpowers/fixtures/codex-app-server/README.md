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
