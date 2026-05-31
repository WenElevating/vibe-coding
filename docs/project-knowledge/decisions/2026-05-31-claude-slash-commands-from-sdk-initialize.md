# Decision: Claude slash commands come from SDK initialize

- Status: accepted
- Date: 2026-05-31
- Last verified: 2026-05-31

## Context

The mobile workbench shows slash command suggestions for the selected CLI.
Claude Code slash commands are workspace-sensitive because user/project
settings, plugins, and `.claude/commands/` affect the available command set.
A static daemon table drifted from Claude Code and exposed `/vim`, which is not
an SDK/mobile-dispatchable command.

## Decision

For Claude, the daemon slash command catalog prefers the Claude SDK initialize
protocol over the static profile. It starts Claude in SDK-style stream-json
mode for the authorized workspace, sends the `initialize` control request, and
reads command data from the initialize control response (`commands`) or the
`system/init` message (`slash_commands`). The static Claude profile is only a
fallback when discovery fails or no workspace context is available.

Mobile passes the current `workspaceId` when loading slash commands and caches
commands by adapter plus workspace.

## Evidence

- `D:\AiProject\claude-agent-sdk-python\src\claude_agent_sdk\_internal\query.py`
  stores the initialize control response as the source of supported commands.
- `D:\AiProject\claude-agent-sdk-python\examples\setting_sources.py` reads
  `SystemMessage.data["slash_commands"]` for available slash commands.
- `daemon/src/slash-command-catalog.js` implements the same protocol shape.

## Verification

```powershell
node scripts/run-tests.js
flutter test --no-pub test\slash_command_catalog_repository_test.dart -r expanded
```

## Re-evaluate When

Claude Code exposes a stable standalone command-list endpoint, or the SDK
initialize protocol changes the command field shape.
