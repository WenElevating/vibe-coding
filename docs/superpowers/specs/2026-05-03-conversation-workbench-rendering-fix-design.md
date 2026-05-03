# Conversation Workbench Rendering Fix Design

## Problem

The backend now exposes first-class conversations, but the mobile coding workbench still renders conversation data through the older run-oriented `AgentEvent` compatibility layer. This causes two visible defects:

1. Final assistant replies can be truncated or overwritten when `assistant.partial` and `assistant.message` are merged through run-era rules. In the reported screenshot, the assistant reply stops after `请帮我明确需求：` even though the Claude JSON contains additional recommendation content.
2. The workbench can keep showing the pending sentinel after a normal assistant reply because running state is inferred from synthetic run terminal events instead of the authoritative conversation status.

The user chose behavior A: only real `AskUserQuestion` / `assistant.question` events should enter a waiting-for-input state. A normal assistant reply that asks a question is still just an assistant message and must not lock the UI into a special question-answer flow.

## Goals

- Render complete final assistant messages from `assistant.message` without truncating content after headings, colons, or Markdown lists.
- Use native `ConversationEvent` and `ConversationSummary.status` in the coding workbench instead of converting to legacy `AgentEvent` for core chat rendering.
- Show the pending sentinel only when the conversation status is `running`.
- Treat `waiting_input` as a real `AskUserQuestion` state only, with answer submission routed to `/api/conversations/:id/questions/respond`.
- Treat `waiting_approval` as a permission state only, with approval submission routed to `/api/conversations/:id/approvals/:approvalId/respond`.
- Preserve existing mobile visual styling and avoid a broad UI redesign.

## Non-Goals

- Do not redesign message card visuals.
- Do not change Claude CLI invocation flags unless needed to preserve complete final text.
- Do not implement Codex/OpenCode conversation adapters in this fix.
- Do not persist conversations to disk; this remains in-memory as currently implemented.

## Proposed Approach

Introduce a conversation-native rendering path for the coding workbench.

The workbench will keep the old run UI components where practical, but its state source will become:

- `ConversationSummary` for lifecycle status, active adapter, workspace, blocking item, and session id.
- `ConversationEvent` for chat messages, assistant partials, questions, approvals, and terminal/error transitions.

The existing `_agentEventFromConversation()` bridge will be removed from the core workbench flow. It may remain temporarily for legacy helper tests only if needed, but it must not decide the visible chat transcript or running state.

## Data Flow

1. User starts a coding conversation.
2. Mobile calls `POST /api/conversations` with `workspaceId`, `adapter`, and `permissionMode`.
3. Mobile sends the first prompt with `POST /api/conversations/:id/messages`.
4. Mobile polls `GET /api/conversations/:id/events?afterSeq=n`.
5. The reducer applies events in sequence:
   - `user.message`: append user bubble.
   - `assistant.partial`: update a temporary stream bubble only when stream output is enabled.
   - `assistant.message`: remove temporary stream bubble for the same response and append/replace with the complete final assistant text.
   - `assistant.question`: append a question card and set UI input mode to question response.
   - `approval.requested`: append or replace one approval card per approval id.
   - `approval.resolved`: remove the pending approval card and show the approved command summary if useful.
   - `conversation.status_changed`: update status directly; `idle` stops pending animation.
6. Composer behavior follows current status:
   - `running`: stop button enabled, send disabled unless follow-up is intentionally allowed later.
   - `idle`: normal send starts or continues the conversation.
   - `waiting_input`: send button answers the pending question.
   - `waiting_approval`: approval card buttons answer the approval; composer remains normal text only after resolution.

## Message Completeness Rules

- `assistant.message.text` is authoritative final content.
- The final content must never be filtered only because it contains Markdown headings, numbered lists, bullet lists, Chinese punctuation, or a colon.
- Protocol filtering may still remove raw JSON protocol leaks, hook callback payloads, `control_response`, and `suppressOutput` objects.
- If `assistant.partial` exists and `assistant.message` later arrives, the final message replaces the partial display rather than concatenating duplicate content.
- If stream output is disabled, `assistant.partial` does not render, but `assistant.message` still renders fully.

## Waiting State Rules

- `assistant.question` is the only event that creates waiting-input UI.
- Normal assistant text that asks a question does not create `waiting_input`.
- `approval.requested` is the only event that creates permission approval UI.
- `idle`, `failed`, and `cancelled` all stop the pending sentinel.

## Components

- `ConversationViewState`: pure reducer state for messages, pending partial, last sequence, status, pending question, and pending approval ids.
- `ConversationMessage`: UI-friendly message model with role, text, event sequence, question id, approval id, suggestions, and command summary fields.
- `_CodingWorkbenchPage`: owns the active `ConversationSummary`, polls conversation events, applies reducer output, and submits messages through conversation endpoints.
- Existing cards: reused where possible, with thin adapters from `ConversationMessage` to the visual card props.

## Error Handling

- If polling fails, show the existing error card but do not discard current messages.
- If answering a question with a stale question id returns conflict, refresh events and show the latest state.
- If approval resolution returns conflict or not found, refresh events and remove already-resolved duplicate approval cards.
- If Claude emits an empty final result after partials, keep the existing partial as final fallback only if no complete final text exists.

## Testing

Add Flutter tests for:

- Complete final assistant text after `请帮我明确需求：` and following Markdown/list content renders in one assistant message.
- With stream output disabled, partial events are hidden but final assistant message is visible and complete.
- `assistant.message` moves status to `idle` and hides pending sentinel.
- Normal assistant question text does not create a question card or waiting-input state.
- `assistant.question` creates a question card and answer submission uses the question endpoint.
- Duplicate approval requests collapse and `approval.resolved` removes the pending approval card.

Add backend tests only if adapter output shape changes. The current backend protocol already distinguishes `assistant.message`, `assistant.question`, and `approval.requested`.

## Acceptance Criteria

- The screenshot scenario displays the full assistant response including content after `请帮我明确需求：`.
- The pending sentinel disappears once the conversation receives `status_changed: idle` or a final assistant message that marks the conversation idle.
- Ordinary assistant questions remain normal assistant bubbles.
- Real `AskUserQuestion` events remain interactive question cards.
- Existing tests plus new reducer/workbench tests pass.
