# Codex Task Progress Card Design

## Context

The mobile workbench currently renders CLI execution as conversation messages and command cards. Codex CLI also emits structured TODO progress events in JSONL output, and those should render as a compact task progress card instead of noisy generic notices or plain assistant text.

Observed Codex CLI output from `codex exec --json`:

```json
{"type":"item.started","item":{"id":"item_1","type":"todo_list","items":[{"text":"Inspect repo","completed":false},{"text":"Run tests","completed":false},{"text":"Summarize findings","completed":false}]}}
{"type":"item.completed","item":{"id":"item_1","type":"todo_list","items":[{"text":"Inspect repo","completed":false},{"text":"Run tests","completed":false},{"text":"Summarize findings","completed":false}]}}
```

The implementation must not infer tasks from free-form natural language and must not group ordinary tool calls into task progress.

## Goals

- Render structured Codex `todo_list` events as a refined task progress card matching the reference style.
- Keep normal tool calls as command cards.
- Keep the daemon protocol adapter-owned so mobile does not depend on raw Codex JSON shapes.
- Accept known Codex TODO shapes conservatively and ignore malformed TODO payloads.
- Leave Claude `TodoWrite` support as a follow-up using the same normalized event type.

## Non-Goals

- No natural-language TODO parsing.
- No automatic grouping of `tool.started` / `tool.output` into task lists.
- No Claude `TodoWrite` implementation in this slice.
- No persistent task database; task progress is conversation event projection only.

## Normalized Event

Add a conversation event type:

```json
{
  "type": "task.progress.updated",
  "taskId": "item_1",
  "source": "codex",
  "items": [
    { "id": "item_1_0", "title": "Inspect repo", "status": "pending" },
    { "id": "item_1_1", "title": "Run tests", "status": "in_progress" },
    { "id": "item_1_2", "title": "Summarize findings", "status": "completed" }
  ],
  "completedCount": 1,
  "totalCount": 3,
  "raw": { "type": "item.started", "item": { "type": "todo_list" } }
}
```

Allowed item statuses are `pending`, `in_progress`, and `completed`.

## Codex Mapping Rules

`daemon/src/codex-conversation-adapter.js` maps a raw event when all conditions hold:

- `raw.type` is `item.started`, `item.updated`, or `item.completed`.
- `raw.item.type` is `todo_list`.
- The item contains a non-empty list in one of these supported shapes:
  - Observed Codex CLI shape: `item.items[].text` plus `item.items[].completed`.
  - Compatibility shape: `item.todos[].content` plus `item.todos[].status`.

Status normalization:

- `completed: true` maps to `completed`.
- `status: "completed"` maps to `completed`.
- `status: "in_progress"` maps to `in_progress`.
- Otherwise maps to `pending`.

When the observed `items[].completed` shape contains no explicit in-progress item, all incomplete items stay `pending`. The UI should still show the current task card and progress count rather than inventing an active step.

Malformed TODO lists return `null` from the mapper so they do not render as unknown system notices.

## Mobile Projection

`mobile/lib/src/ui/features/workbench/conversation_reducer.dart` handles `task.progress.updated` by upserting a single task progress message per `taskId`.

Reducer behavior:

- Repeated updates for the same `taskId` replace the previous task progress message.
- Different `taskId` values can produce separate cards if the CLI creates independent lists.
- `lastSeq` still advances for every accepted event.
- Task progress messages are non-blocking and do not change conversation status.

## UI Card

Add a dedicated task progress card under the workbench message renderer.

Visual rules:

- Card title: `任务进度` in Chinese UI and `Task Progress` in English UI.
- Right badge: `{completedCount} / {totalCount} 完成` or localized equivalent.
- Thin horizontal progress bar uses completed ratio.
- Step rows show:
  - Completed: green check icon, dimmed title, optional duration/detail when available.
  - In progress: blue active dot/ring, stronger title, secondary text `正在执行` / `In progress`.
  - Pending: neutral ring, muted title, secondary text `等待执行` / `Pending`.
- Footer legend shows completed / in progress / pending dots only if it does not crowd small screens.
- The card should be compact and consistent with existing glass-card styling.

## Testing Strategy

- Daemon unit test: Codex mapper converts observed `item.started` `todo_list.items[]` into `task.progress.updated`.
- Daemon unit test: Codex mapper converts compatibility `todo_list.todos[]` statuses.
- Daemon unit test: malformed `todo_list` returns `null` or otherwise does not become a visible unknown notice.
- Mobile reducer test: `task.progress.updated` creates one task progress message with counts and item statuses.
- Mobile reducer test: later update with the same `taskId` replaces the old card.
- Widget test: task progress card renders title, progress badge, and completed/in-progress/pending rows.

## Risks

- Codex TODO JSON shape may continue evolving. The mapper must be shape-tolerant but not text-guessy.
- Some Codex events may emit only `pending`/`completed` without explicit `in_progress`; the UI must not fabricate state.
- Adding a new event type requires model parsing updates in mobile protocol models and tests.

## Rollout Plan

1. Add normalized protocol event fields and Codex mapper tests.
2. Add mobile event/model parsing and reducer projection tests.
3. Add task progress card UI and widget test.
4. Verify with `npm test`, architecture import check, focused Flutter tests, and manual Codex JSONL sample if needed.
