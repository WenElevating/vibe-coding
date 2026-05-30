# Project Knowledge Index

- Status: active seed
- Last verified: 2026-05-22

This directory is the versioned project knowledge source for future agents. Use
it to recover architecture, boundaries, build/test rules, troubleshooting
patterns, conventions, risks, glossary terms, and accepted decisions without
starting from zero.

## Source Rules

- Current code and tests are the authority for implementation facts.
- This directory is the authority for durable project conventions and accepted
  decisions.
- `docs/superpowers/specs/` keeps detailed design rationale linked from this
  index or decisions.
- Local agent memory can suggest where to look, but drift-prone facts must be
  verified before use.

## Routing

Read this file first, then choose the smallest relevant slice.

1. Bug, failing test, hang, freeze, regression, unexpected behavior:
   `troubleshooting-playbook.md`, `build-and-test.md`.
2. State ownership, data flow, module placement, daemon/mobile boundaries:
   `architecture.md`, `module-boundaries.md`, relevant `decisions/`.
3. Build, test, CI, Flutter/Dart, Node, proxy, dependency, SDK, environment:
   `build-and-test.md`, `conventions.md`, `open-risks.md`.
4. Feature work in a known area: `architecture.md` plus relevant decisions or
   troubleshooting entries named by the feature.
5. Naming, error handling, logging, commit style, code consistency:
   `conventions.md`.
6. Ambiguous task: read at most `index.md`, `architecture.md`, and
   `troubleshooting-playbook.md`, then inspect code before loading more.

Rules 1-5 are exact routes and may be combined. The three-file limit applies
only to rule 6. If exact routes exceed five files, inspect the most likely code
boundary first before loading more knowledge.

## Active Slices

- [architecture.md](architecture.md)
- [module-boundaries.md](module-boundaries.md)
- [build-and-test.md](build-and-test.md)
- [troubleshooting-playbook.md](troubleshooting-playbook.md)
- [conventions.md](conventions.md)
- [glossary.md](glossary.md)
- [open-risks.md](open-risks.md)
- [decisions/README.md](decisions/README.md)

## Current Accepted Decisions

- [Conversation title is daemon-owned metadata](decisions/2026-05-22-stable-conversation-title.md)
- [Workbench transcript is bottom anchored](decisions/2026-05-22-bottom-anchored-transcript.md)
- [Attachment previews are mobile-owned cache](decisions/2026-05-22-mobile-owned-attachment-preview-cache.md)
- [Voice input post-processing is final-text only](decisions/2026-05-23-voice-input-final-text-post-processing.md)
- [Workbench conversation events use WebSocket notifications](decisions/2026-05-23-websocket-notification-gateway.md)
- [Private Android APK update channel](decisions/2026-05-24-private-android-apk-update-channel.md)
- [Claude conversation control follows SDK stdio protocol](decisions/2026-05-30-claude-sdk-control-parity.md)

## Verification

Useful quick checks:

```powershell
node scripts/run-tests.js
npm run lint
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
```
