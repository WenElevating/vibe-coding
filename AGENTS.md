# Repository Guidelines

## Project Structure & Module Organization

This repository contains a LAN/mobile control surface for AI CLI coding tools.

- `daemon/`: Node.js daemon, HTTP API, workspace management, adapter orchestration, and persistence.
- `mobile/`: Flutter client application, widgets, models, services, and mobile tests.
- `scripts/`: Node-based smoke and regression test entry points.
- `docs/`: Design notes, UI references, and implementation plans.
- `data/`: Runtime SQLite data such as `data/conversations/conversations.sqlite` and should not be committed.
- `.omx/`: Local agent/runtime artifacts; treat as generated and exclude from commits.

## Build, Test, and Development Commands

Run commands from the repository root unless noted.

- `npm test`: Runs daemon/API/adapter regression tests via `scripts/run-tests.js`.
- `npm run lint`: Runs JavaScript static checks with `scripts/check-js.js`.
- `npm run start:daemon`: Starts the local daemon.
- `cd mobile && flutter analyze`: Runs Flutter static analysis.
- `cd mobile && flutter test`: Runs Flutter unit and widget tests.
- `cd mobile && flutter build windows --debug`: Builds the Windows debug app.

## Coding Style & Naming Conventions

Use small, focused changes and keep behavior in existing modules unless a refactor is required. JavaScript uses CommonJS modules, `const`/`let`, two-space indentation, and descriptive function names. Dart code follows Flutter conventions: `UpperCamelCase` for widgets/classes, `lowerCamelCase` for fields/functions, and private members prefixed with `_`. Avoid broad rewrites and do not introduce new dependencies without a clear need.

## Text Encoding Safety

Treat all repository source, docs, and test files as UTF-8, especially files containing Chinese text. On Windows, do not rewrite source files with PowerShell `Set-Content`, `Out-File`, or `>` redirection unless you explicitly preserve UTF-8 without BOM and have verified the result. Prefer `apply_patch` for edits. For mechanical rewrites, use byte-preserving scripts or language tooling that reads and writes UTF-8 explicitly, then immediately run `rg`/format/analyze checks for garbled Chinese, replacement characters, or unterminated strings. Never “fix” mojibake by guessing; restore from git or inspect the original UTF-8 bytes first.

## Testing Guidelines

Add regression tests for bug fixes. Daemon behavior belongs in `scripts/run-tests.js` or `daemon/test/` when appropriate. Flutter UI/state behavior belongs in `mobile/test/`, especially `widget_test.dart`, `conversation_reducer_test.dart`, and protocol compatibility tests. Prefer tests that exercise real reducers/adapters over snapshot-only checks.

## Commit & Pull Request Guidelines

Commits should explain why the change exists, not only what changed. Follow the repository’s Lore-style trailer pattern when useful: `Constraint:`, `Rejected:`, `Confidence:`, `Scope-risk:`, `Tested:`, and `Not-tested:`. Pull requests should include a short problem statement, implementation summary, test evidence, screenshots for UI changes, and any known risks or follow-up work.

## Security & Configuration Tips

Never commit tokens, pairing secrets, SQLite runtime data, `.omx/`, build outputs, or manual smoke artifacts. Keep workspace execution bounded to authorized workspace paths. For CLI adapters, preserve explicit tests around cwd, permissions, stdin handling, and protocol filtering.
