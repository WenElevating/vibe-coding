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
