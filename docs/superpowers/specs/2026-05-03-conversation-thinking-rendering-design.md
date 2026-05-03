# Conversation Thinking Rendering Design

## Problem

Claude stream-json output can contain separate assistant content blocks:

- `content[].type == "thinking"` with model reasoning text.
- `content[].type == "text"` with user-facing answer text.
- A terminal `result.result` string with the complete final answer.

The current daemon extracts only text-like blocks and drops thinking blocks. The mobile workbench also lets temporary partial/question content dominate the transcript, so the final user-facing answer can appear incomplete compared with the raw CLI JSON.

## Decision

The user chose option C: expose thinking through a setting, default folded/collapsed.

## Goals

- Preserve Claude thinking as a distinct normalized event, not mixed into the final answer.
- Render thinking in mobile as a collapsible "思考过程" message.
- Add a setting controlling whether thinking is expanded by default; default is collapsed.
- Keep final assistant text authoritative and complete.
- Prevent `assistant.question` fallback cards from replacing final text.

## Backend Design

Add `assistant.thinking` to the conversation protocol.

In `ClaudeConversationAdapter`:

- Parse assistant `message.content` blocks individually.
- Emit `assistant.thinking` for `type == "thinking"` and non-empty `thinking`/`text` content.
- Emit `assistant.partial` for `type == "text"` in assistant stream messages.
- Emit `assistant.message` for terminal `result.result`.

The legacy `ClaudeAdapter` can keep existing behavior unless touched by a test; this fix targets first-class conversations.

## Frontend Design

Extend `ConversationViewState`:

- Add a `thinking` role to `ConversationMessage`.
- `assistant.thinking` appends or updates a thinking message.
- Thinking does not affect `status`.
- `assistant.message` removes/replaces partial stream output and appends complete final assistant text.

Extend the coding workbench:

- Add a boolean setting for thinking expansion, default false.
- Convert `thinking` messages into a collapsible card labeled `思考过程`.
- When disabled/default, show collapsed preview only.
- When enabled, expand the thinking card by default.

## Acceptance Criteria

- Given the user's raw CLI JSON sample, the UI can represent both thinking and final text.
- Final text includes the full recommendations list.
- Thinking appears under `思考过程`, not inside the final assistant answer.
- With default settings, thinking is collapsed.
- Existing tests continue passing.
