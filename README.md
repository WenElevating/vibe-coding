<!-- DREAMFIELD_README_HEADER_START -->

<p align="center">
  <a href="https://www.dreamfield.top">
    <img src="https://www.dreamfield.top/dream-field/contest-readme/assets/dreamseed-readme-banner.png" alt="DreamSeed 种梦计划参赛作品" width="100%" />
  </a>
</p>

<!-- DREAMFIELD_README_HEADER_END -->

# Vibe Coding

[简体中文](README.zh-CN.md)

Vibe Coding is a LAN-first mobile control surface for AI coding CLIs. It lets a phone or another trusted LAN device start, resume, observe, and stop bounded coding conversations while Claude Code, Codex CLI, or OpenCode keeps running on the developer machine that owns the workspace.

It is not a remote terminal. The Node daemon keeps execution inside authorized desktop workspaces, owns pairing and token checks, validates attachments, persists events, and exposes only the HTTP/WebSocket surface needed by the Flutter workbench.

## Screenshots

| Codex conversation | Image prompt |
| --- | --- |
| ![Codex conversation in the mobile workbench](images/output/en/chat-codex.png) | ![Image attachment prompt in the mobile workbench](images/output/en/chat-with-image.png) |

## What It Does

- Connects a Flutter client to a local daemon through short-lived pairing codes, access tokens, and refresh tokens.
- Lets each paired device register, rename, list, and logically delete its trusted workspaces.
- Starts and resumes conversation-style coding sessions for Claude Code and Codex CLI.
- Keeps the workbench live with WebSocket conversation notifications, persisted event replay, and REST backfill.
- Shows assistant messages, thinking blocks, tool output, command cards, task progress, approval prompts, user questions, run errors, and attachment previews.
- Sends text prompts, image attachments, and supported text documents through capability-checked multipart requests.
- Keeps a bounded compatibility run surface for queues, shortcuts, command templates, Git status, Git diff, and OpenCode attach/run behavior.
- Provides mobile voice input through a daemon-hosted Sherpa ONNX ASR model with resumable downloads and final-text correction.
- Hosts a private Android APK update channel from the paired daemon with manifest checks, resumable downloads, SHA-256 verification, and Android installer handoff.
- Exports redacted diagnostics with trace ids for daemon and mobile failures.

## System Shape

```text
Flutter mobile app
  -> Node daemon HTTP API + WebSocket notifications
    -> pairing auth, device-scoped workspaces, SQLite state
      -> ConversationManager / RunManager
        -> Claude Code, Codex CLI, OpenCode, or synthetic adapters
          -> authorized desktop workspace path
```

Main directories:

- `daemon/`: Node.js daemon, HTTP API, WebSocket notification hub, auth, workspace registry, CLI adapters, attachment validation, SQLite persistence, diagnostics, ASR assets, and Android update hosting.
- `mobile/`: Flutter app, connection flow, repositories, ViewModels, workbench UI, attachment picker, voice input, app update workflow, localization, and tests.
- `scripts/`: daemon regression runner, static checks, and Android update packaging helpers.
- `docs/`: design notes, PRDs, project knowledge, release guides, and implementation plans.
- `images/output/`: README screenshots.
- `data/`: local runtime SQLite data. Do not commit generated runtime files.
- `.omx/`: local agent/runtime artifacts. Treat as generated output.

## Adapter Support

| Adapter | Conversation support | Resume | Model selection | Attachments | Current notes |
| --- | --- | --- | --- | --- | --- |
| Claude Code | Yes | Yes | When detected CLI capabilities expose model selection | Images and text extraction; PDFs are validated but not dispatched | Image bytes are capped at 5 MB before base64 conversion. CLI questions and approval callbacks are projected into the workbench when emitted. |
| Codex CLI | Yes | Yes, through `codex exec resume --json` | When both `exec` and `resume` help expose model flags | Images only when the detected CLI supports image flags; text extraction is supported; PDFs are not dispatched | Codex is available in the conversation path and can also be exposed in the legacy run adapter list with `CODEX_ENABLED=1`. |
| OpenCode | Attach/run surface only | Follow-up requires an OpenCode session id | No mobile model picker in this path | Depends on the OpenCode server | `/api/conversations` intentionally returns not implemented for OpenCode today. Configure the attach/run adapter with `OPENCODE_SERVER_URL`. |
| Synthetic adapters | Development and tests | Test behavior | No | Test fixtures | Enabled with `DEV_ADAPTERS=1` for daemon/UI conformance checks and smoke tests. |

Attachment availability is derived from the selected adapter and model capability projection. The mobile app blocks obviously unsupported selections, and the daemon validates the multipart payload again before dispatching anything to a CLI. Attachment bytes are sniffed, written to scoped scratch storage, logged as metadata only, and cleaned up after terminal conversation events or relevant failures.

## Requirements

- Node.js 20 or newer.
- Flutter SDK with Dart `>=3.3.0 <4.0.0`.
- At least one local CLI for real coding sessions:
  - Claude Code available as `claude`.
  - Codex CLI available as `codex`.
  - OpenCode server when using the attach/run adapter.
- Optional voice input asset: `daemon/asset/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20-mobile.zip`.
- Optional Android update release signing: `mobile/android/key.properties` and the matching release keystore.

## Quick Start

Install daemon dependencies from the repository root:

```powershell
npm install
```

Start the daemon on loopback:

```powershell
npm run start:daemon
```

Enable Codex in adapter listing when you want the Codex run surface as well:

```powershell
$env:CODEX_ENABLED='1'
$env:CODEX_COMMAND='codex'
npm run start:daemon
```

Bind to the LAN only when another device needs to connect:

```powershell
$env:DAEMON_HOST='0.0.0.0'
$env:PORT='4317'
npm run start:daemon
```

There is also a Windows helper for local LAN development:

```powershell
.\start-daemon.bat
```

Run the Flutter app from `mobile/`:

```powershell
cd mobile
flutter pub get
flutter run -d windows
```

For Flutter/Dart commands that resolve packages or artifacts in mainland China network environments, use mirrors:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter pub get
flutter test
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `DAEMON_HOST` | `127.0.0.1` | HTTP bind host. Use `0.0.0.0` only on trusted LANs. |
| `PORT` | `4317` | Daemon HTTP port. |
| `DAEMON_MODE` | `dev` | Runtime mode. Development mode enables the smoke endpoint. |
| `APP_DB_PATH` | app data default | SQLite path for app, auth, workspace, conversation, exception, and related state. |
| `CONVERSATION_DB_PATH` | unset | Compatibility alias used when `APP_DB_PATH` is not set. |
| `AUTH_TOKEN_SECRET` | generated file secret | Token signing secret. Generated near the app DB when absent. |
| `DEVICE_ID_PEPPER` | generated file secret | Pepper used for hashed device identity. |
| `ACCESS_TOKEN_TTL_MS` | 7 days | Access-token lifetime. |
| `REFRESH_TOKEN_TTL_MS` | 30 days | Refresh-token lifetime. |
| `CLAUDE_COMMAND` | `claude` | Claude Code command or shim path. |
| `CODEX_COMMAND` | `codex` | Codex CLI command or shim path. |
| `CODEX_ENABLED` | disabled | Set to `1` to expose the Codex legacy run adapter in adapter listing. |
| `OPENCODE_SERVER_URL` | `http://127.0.0.1:4096` | OpenCode server URL for the attach/run adapter. |
| `DEV_ADAPTERS` | disabled | Set to `1` to add synthetic adapters for development and tests. |
| `CONVERSATION_IDLE_TTL_MS` | `600000` | Idle TTL used by conversation management. |
| `ANDROID_UPDATE_ARTIFACT_DIR` | `daemon/update-artifacts/android` | Directory containing Android update `latest.json`, APK, and `.sha256` artifacts. |

## API Surface

The daemon intentionally exposes product-level operations instead of a general shell:

- Health and pairing: `GET /api/health`, `GET /api/version`, `POST /api/pairing-code`, `POST /api/pair`, `POST /api/token/refresh`.
- Workspaces and files: `/api/workspaces`, `/api/fs/roots`, `/api/fs/children`, and authorized workspace overview, tree, content, diagnostics, Git status, diff, and commits.
- Conversations: `/api/conversations`, `/api/conversations/:conversationId/events`, `/messages`, `/questions/respond`, `/approvals/:approvalId/respond`, `/cancel`, and `/model`.
- Live notifications: WebSocket upgrade at `/api/notifications/ws` with bearer-token auth and scoped `conversation.events` subscriptions.
- Compatibility runs: `/api/runs`, `/api/runs/:runId/events`, `/input`, `/cancel`, `/api/queue`, `/api/shortcuts`, and `/api/command-templates`.
- Diagnostics and client exceptions: `POST /api/diagnostics/export` and `POST /api/exceptions`.
- Private Android updates: `GET /api/app-updates/android/latest`, `HEAD /api/app-updates/android/apk/:versionCode`, and `GET /api/app-updates/android/apk/:versionCode`.
- Voice model assets: `GET /api/asr-model` and `GET /api/asr-model/download`.

`/api/conversations` is the main coding-session surface. `/api/runs` remains for bounded legacy task-runner and attach-style workflows.

## Security Model

- Mobile clients cannot send arbitrary shell commands.
- Mobile clients cannot choose arbitrary `cwd` values or pass raw CLI arguments.
- The API does not expose a persistent PTY.
- CLI execution is limited to daemon-authorized workspace paths.
- Workspace access is scoped by paired device.
- Pairing uses short-lived codes and token storage with hashed device identity.
- Attachments require capability versions and client message ids.
- Attachment diagnostics and adapter errors are redacted before they reach mobile or diagnostic bundles.
- Development-only smoke APIs are disabled outside development mode.

If the daemon is bound to a LAN interface, keep it on a trusted network. The daemon does not provide TLS by itself and should not be exposed directly to the public internet.

## Development Checks

Daemon checks from the repository root:

```powershell
npm run lint
npm test
node scripts/check-project-knowledge.js
git diff --check
```

Flutter checks from `mobile/`:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool/check_architecture_imports.dart
flutter analyze
flutter test
```

Windows debug build:

```powershell
cd mobile
flutter build windows --debug
```

Android update package:

```powershell
npm run package:android-update -- -VersionName 1.4.2 -VersionCode 4
```

## Documentation

- [Project knowledge index](docs/project-knowledge/index.md): durable architecture, build/test rules, decisions, risks, and troubleshooting routes.
- [Android online update release guide](docs/android-online-update-release-guide.md): private APK update packaging and manual smoke process.
- [AI CLI control command notes](docs/ai_cli_control_commands_claude_codex_opencode.md): adapter-oriented CLI behavior notes.
- [v1.3 PRD](docs/prd/flutter_lan_ai_cli_control_v1_3_prd.md): product requirements for the current mobile control surface generation.

## Current Limits

- The product is designed for local/LAN development workflows, not public hosting.
- OpenCode is currently an attach/run adapter, not a full conversation adapter.
- PDF files can be validated as attachments, but production conversation dispatch does not send PDFs to Claude or Codex.
- The ASR API requires the expected model ZIP under `daemon/asset/`; missing assets return a structured `ASR_MODEL_UNAVAILABLE` error.
- Android updates use normal Android installer confirmation. Silent install is not supported on ordinary devices.
- Runtime SQLite data, generated pairing secrets, `.omx/`, diagnostic bundles, APK artifacts, and build output should stay out of Git.

## License

This repository currently does not include a standalone `LICENSE` file.
