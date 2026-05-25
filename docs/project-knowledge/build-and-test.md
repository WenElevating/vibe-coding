# Build And Test

- Status: active seed
- Last verified: 2026-05-22

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
