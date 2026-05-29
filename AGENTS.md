# Repository Guidelines

## Project Structure & Module Organization

This repository contains a LAN/mobile control surface for AI CLI coding tools.

- `daemon/`: Node.js daemon, HTTP API, workspace management, adapter orchestration, and persistence.
- `mobile/`: Flutter client application, widgets, models, services, and mobile tests.
- `scripts/`: Node-based smoke and regression test entry points.
- `docs/`: Design notes, UI references, and implementation plans.
- `data/`: Runtime SQLite data such as `data/conversations/conversations.sqlite` and should not be committed.
- `.omx/`: Local agent/runtime artifacts; treat as generated and exclude from commits.

## Project Knowledge

For non-trivial work, read `docs/project-knowledge/index.md` and the linked task-specific slice before deep exploration. Update project knowledge only when the task creates durable architecture, debugging, testing, decision, risk, or environment lessons.

## Build, Test, and Development Commands

Run commands from the repository root unless noted.

- `npm test`: Runs daemon/API/adapter regression tests via `scripts/run-tests.js`.
- `npm run lint`: Runs JavaScript static checks with `scripts/check-js.js`.
- `node scripts/check-project-knowledge.js`: Runs lightweight structural checks for `docs/project-knowledge/`.
- `npm run start:daemon`: Starts the local daemon.
- `cd mobile && flutter analyze`: Runs Flutter static analysis.
- `cd mobile && flutter test`: Runs Flutter unit and widget tests.
- `cd mobile && flutter build windows --debug`: Builds the Windows debug app.
- For any Flutter/Dart command that touches package resolution, artifact download, build, analyze, test, or run flows under `mobile/`, use mainland China mirrors by default: set `PUB_HOSTED_URL=https://pub.flutter-io.cn` and `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` for that command invocation.
- In this Windows/Codex environment, prefer the direct Dart SDK for Dart-only mobile checks to avoid Flutter wrapper/cache-lock stalls: from `mobile/`, run `& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze`, `& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart`, and `& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' format ...`.
- For Flutter tests in this environment, keep the top-level command as `flutter test` so command approval matches. When `mobile/.dart_tool/package_config.json` exists, use `flutter test --no-pub ...` and do not prepend inline PowerShell `$env:` assignments to the same command; use mirror environment variables only when package resolution or artifact download is required.
- If a Flutter/Dart command times out on the first attempt, stop retrying automatically, tell the user the command timed out, and provide the exact mirror-configured command for the user to run manually.

## Coding Style & Naming Conventions

Use small, focused changes and keep behavior in existing modules unless a refactor is required. JavaScript uses CommonJS modules, `const`/`let`, two-space indentation, and descriptive function names. Dart code follows Flutter conventions: `UpperCamelCase` for widgets/classes, `lowerCamelCase` for fields/functions, and private members prefixed with `_`. Avoid broad rewrites and do not introduce new dependencies without a clear need.

## Flutter Mobile Architecture

The Flutter app in `mobile/` follows a standard layered architecture. Preserve the current boundaries when adding or moving code.

- `mobile/lib/main.dart` should stay thin and only bootstrap the app from `src/app/`.
- `mobile/lib/src/app/` is the composition root for app setup, localization, theme wiring, and dependency construction. `AppDependencies` should stay grouped into network/data/domain/feature dependency groups instead of becoming a flat service locator.
- `mobile/lib/src/data/` owns API/daemon DTOs, repository implementations, and data-facing service contracts. Data code may depend on infrastructure clients such as `DaemonClient` and implements domain repository interfaces.
- `mobile/lib/src/domain/` owns repository abstractions, use-case contracts, workflow-facing business models, and pure domain decisions. Domain code must not import Flutter, HTTP clients, SharedPreferences, UI code, or the concrete `DaemonClient`.
- `mobile/lib/src/ui/` owns presentation. Keep shared design primitives in `ui/core/`; keep feature views, feature ViewModels, and feature-local UI state in `ui/features/<feature>/`. Views should stay lean; ViewModels expose immutable state snapshots and receive repositories/use cases through constructors.
- `mobile/lib/src/workflows/` owns multi-step application flows that coordinate validation, persistence, daemon calls, refreshes, or other side effects across more than one repository/service. Do not bury these flows inside widgets.
- `mobile/lib/src/services/` contains infrastructure and platform adapters such as daemon HTTP clients, device identity, ASR, and local stores. Use it from data/workflow/composition code, not as a shortcut from arbitrary UI widgets.
- `mobile/lib/src/testing/` contains fake implementations, builders, fixtures, and debug helpers for tests. Production code must not import it; tests may import it explicitly.
- The legacy roots `mobile/lib/src/features`, `mobile/lib/src/widgets`, `mobile/lib/src/theme`, and `mobile/lib/src/state` are migration-only/retired. Do not add new files or imports there.
- `mobile/lib/src/models/protocol.dart` is a compatibility barrel for protocol models. Prefer new model ownership under `data/models/` and avoid expanding the barrel unless preserving a deliberate public import surface.
- Create a UseCase only when logic crosses two or more repositories, is reused by multiple ViewModels, or contains an ordered side-effect sequence such as validate -> write -> refresh/notify. Simple CRUD should usually remain in a Repository.
- Before claiming a Flutter architecture change is complete, run `cd mobile && dart run tool/check_architecture_imports.dart` plus the relevant `dart analyze`/`flutter test` target.

## Text Encoding Safety

Treat all repository source, docs, and test files as UTF-8, especially files containing Chinese text. On Windows, do not rewrite source files with PowerShell `Set-Content`, `Out-File`, or `>` redirection unless you explicitly preserve UTF-8 without BOM and have verified the result. Prefer `apply_patch` for edits. For mechanical rewrites, use byte-preserving scripts or language tooling that reads and writes UTF-8 explicitly, then immediately run `rg`/format/analyze checks for garbled Chinese, replacement characters, or unterminated strings. Never “fix” mojibake by guessing; restore from git or inspect the original UTF-8 bytes first.

## Testing Guidelines

Add regression tests for bug fixes. Daemon behavior belongs in `scripts/run-tests.js` or `daemon/test/` when appropriate. Flutter UI/state behavior belongs in `mobile/test/`, especially `widget_test.dart`, `conversation_reducer_test.dart`, and protocol compatibility tests. Prefer tests that exercise real reducers/adapters over snapshot-only checks.

## Commit & Pull Request Guidelines

Commits should explain why the change exists, not only what changed. Follow the repository’s Lore-style trailer pattern when useful: `Constraint:`, `Rejected:`, `Confidence:`, `Scope-risk:`, `Tested:`, and `Not-tested:`. Pull requests should include a short problem statement, implementation summary, test evidence, screenshots for UI changes, and any known risks or follow-up work.

## Security & Configuration Tips

Never commit tokens, pairing secrets, SQLite runtime data, `.omx/`, build outputs, or manual smoke artifacts. Keep workspace execution bounded to authorized workspace paths. For CLI adapters, preserve explicit tests around cwd, permissions, stdin handling, and protocol filtering.
