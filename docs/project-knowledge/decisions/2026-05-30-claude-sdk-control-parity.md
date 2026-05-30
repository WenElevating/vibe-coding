# Decision: Claude Conversation Control Follows SDK Stdio Protocol

- Status: accepted
- Date: 2026-05-30
- Last verified: 2026-05-30

## Context

Claude long-lived conversations are controlled by the CLI stdio control
protocol. Mobile approval, question, model, permission-mode, and MCP controls
must match the Python SDK semantics rather than treating CLI approval prompts as
ordinary transcript output.

## Decision

Daemon Claude conversations always launch with `--permission-prompt-tool stdio`
and SDK-style process environment. Unknown incoming `control_request` subtypes
receive `control_response` errors. Mobile approval responses forward
`updatedInput`, `updatedPermissions`, and deny `interrupt` flags. Active Claude
conversations accept dynamic control requests through daemon manager/HTTP
methods instead of restarting the process when the SDK has a live control path.

Mobile settings persist the chosen permission mode locally and also update the
current active Claude conversation through the conversation repository boundary.

## Alternatives

- Restart active Claude conversations for setting/model changes: rejected
  because the SDK exposes live `set_permission_mode` and `set_model` control
  requests.
- Keep auto mode as the default: rejected because default approval mode is the
  reliable mobile-confirmation path; auto can still be selected explicitly.
- Expose arbitrary SDK environment overrides to mobile: rejected because process
  env is a daemon trust boundary.

## Evidence

- `daemon/src/claude-conversation-adapter.js`
- `daemon/src/conversation-manager.js`
- `mobile/lib/src/ui/features/settings/view_models/settings_view_model.dart`
- `scripts/run-tests.js`

## Verification

```powershell
npm test
npm run lint
node scripts/check-project-knowledge.js
cd mobile
dart analyze
dart run tool\check_architecture_imports.dart
flutter test --no-pub test\settings_view_model_test.dart test\daemon_client_test.dart test\cached_connected_repositories_test.dart test\adapter_model_test.dart test\coding_workbench_controller_test.dart test\main_route_overlay_test.dart -r expanded
```

## Re-evaluate When

Re-check against the upstream Claude SDK when the SDK changes control request
subtypes, approval response payloads, or CLI argument names.
