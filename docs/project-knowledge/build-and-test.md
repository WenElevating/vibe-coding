# Build And Test

- Status: active seed
- Last verified: 2026-05-29

## Daemon Checks

Run from repo root:

```powershell
node scripts/run-tests.js
node scripts/check-project-knowledge.js
npm run lint
git diff --check
```

`node scripts/run-tests.js`, `node scripts/check-project-knowledge.js`, and
`npm run lint` were verified on 2026-05-22.

## OpenCode Server Smoke Helper

Run against an already running `opencode serve` process:

```powershell
node scripts/smoke-opencode-server.js --server-url http://127.0.0.1:4096 --workspace D:\AIProject\vibe-coding
```

The default smoke checks are non-model-consuming: health, doc, session create,
session read, SSE open, and abort. Prompt dispatch is intentionally opt-in:

```powershell
node scripts/smoke-opencode-server.js --server-url http://127.0.0.1:4096 --workspace D:\AIProject\vibe-coding --allow-prompt-dispatch
```

Last verified: 2026-06-09

## Codex App-Server Parity Release Gate

Run from repo root before shipping app-server parity changes:

```powershell
node scripts/run-tests.js
npm run lint
node scripts/check-project-knowledge.js
node scripts/check-codex-app-server-fixture-drift.js
```

`scripts/run-tests.js` includes the release smoke gates for full parity matrix
completion, supported route coverage, route process isolation, high-risk
approval/audit behavior, kill-switch behavior, and per-adapter model
normalization isolation. A malformed `codex-app-server` model list must not
break `/api/adapters` for other adapters.

`scripts/check-codex-app-server-fixture-drift.js` is the contract drift gate. It
compares committed app-server schema fixtures against schemas generated from the
real `codex` binary when that generator is available. A skip means the local
binary or generator is unavailable; it is acceptable for local development but
not enough evidence for a release branch.

Operational expectations:

- Passive discovery, active conversation, and mutation/high-risk routes use
  separate app-server process pools.
- High-risk operations require workspace authorization, approval or product
  policy, controlled errors, and append-only audit records.
- Streaming `assistant.partial` and output deltas stay unfiltered; bounded
  retention, durable snapshots, and WebSocket backpressure provide the resource
  controls.
- Mobile should consume app-server data through daemon repositories and route
  metadata derived from the capability matrix, not raw JSON-RPC.

Last verified: 2026-06-05

## Flutter/Dart Environment

For Flutter/Dart commands under `mobile/`, use mainland China mirrors and local
proxy bypass:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
```

Architecture boundary check:

```powershell
dart run tool\check_architecture_imports.dart
```

## Android Update Packaging

Package a release APK and daemon update manifest from the repository root:

```powershell
npm run package:android-update -- -VersionName 1.4.0 -VersionCode 2
```

The script reads `mobile/android/key.properties`, builds the release APK with
Flutter China mirrors, then writes `daemon/update-artifacts/android/latest.json`,
the copied APK, and its `.sha256` file. Use `-SkipBuild -ApkPath <apk>` only for
testing or repackaging an already-built APK.

Last verified: 2026-05-25

Targeted widget/unit tests:

```powershell
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "<test name>"
flutter test --no-pub test\daemon_client_test.dart test\widget_test.dart -r expanded --plain-name "stable conversation title"
```

## Timeout Rule

If a Flutter/Dart command times out on the first attempt, stop retrying
automatically. Tell the user the command timed out and provide the exact
mirror-configured command for manual execution.

This rule exists because local Dart/Flutter tool invocations have timed out in
agent runs while passing when the user ran the same command manually.

Observed root cause: the Flutter Windows wrappers (`dart.bat` and
`flutter.bat`) acquire `bin/cache/flutter.bat.lock` under the Flutter SDK
directory before launching the tool. In the agent's default sandbox, the
workspace is writable but `D:\sdk\flutter_sdk\flutter\bin\cache` is not, so the
wrapper can wait until the tool call times out. Running the same command in the
user's PowerShell, or running it with explicit escalation, can succeed because it
is allowed to write the SDK cache lock. Pure Dart formatting can also bypass the
wrapper by invoking `D:\sdk\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe`
directly, but Flutter commands still need the wrapper and should be escalated.

When running Flutter/Dart commands through the agent tool, keep the executable
as the top-level command (for example, `flutter test ...` or `dart analyze ...`)
instead of prefixing PowerShell environment assignments in the same command
string. Composite commands such as `$env:NAME='value'; flutter test ...` may not
match the approved command prefix, causing Flutter to run in the sandbox and
fail or hang while opening the SDK cache lockfile outside the workspace. If a
one-off command truly needs inline environment setup, run it with explicit
escalation instead of relying on the approved prefix.

If `flutter test` is allowed outside the sandbox but still appears to hang with
no test output, inspect child Dart processes. Flutter may be stuck before test
execution in its implicit package resolution step:

```text
dart pub --suppress-analytics --directory . get --example
```

When `mobile/.dart_tool/package_config.json` already exists and dependencies are
not being changed, run targeted agent tests with `--no-pub` and the same mirror
environment:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\coding_workbench_controller_test.dart -r expanded
```

Run package resolution explicitly only when dependencies, generated package
metadata, or Flutter artifacts actually need to change.

## Knowledge Check

Run from repo root:

```powershell
node scripts/check-project-knowledge.js
```

The first version performs cheap structural checks only:

- relative Markdown link targets exist;
- `index.md` does not route normal tasks to archive;
- active entries missing `Last verified` are reported as notices, not failures.

It should not run Flutter, daemon, network, or expensive checks.
