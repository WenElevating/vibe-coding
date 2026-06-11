# Conversation CLI Selection Memory Design

## Goal

When a user reopens a previously used conversation, the workbench should show the CLI adapter that belongs to that conversation. The memory must survive app and daemon restarts.

## User-Approved Scope

- Use conversation-level memory only.
- If the user changes the CLI selector before a conversation exists, that selected adapter becomes the adapter for the conversation created by the next send.
- Once a conversation has started, the CLI adapter for that conversation cannot be changed from the UI.
- Reopening an existing conversation hydrates the workbench selector from that conversation's persisted adapter.

## Existing Architecture

- The daemon already persists each conversation's adapter in SQLite as `conversations.adapter`.
- Conversation summaries already expose `adapter` to Flutter through `/api/conversations`.
- Flutter already models this as `ConversationSummary.adapter`.
- New conversation creation already sends the currently selected adapter to the daemon.

The missing piece is UI state hydration and locking: the workbench currently computes a preferred adapter from available adapters on startup, but reopening a conversation should override that transient default with the conversation's persisted adapter.

## Data Flow

### New Conversation

1. User selects a CLI adapter while no active conversation is open.
2. `WorkbenchViewModel.selectedAdapter` updates locally.
3. User sends the first prompt.
4. Flutter calls `createConversation(adapter: selectedAdapter)`.
5. Daemon validates the adapter and saves it in `conversations.adapter`.
6. The returned `ConversationSummary.adapter` becomes the conversation's source of truth.

### Reopen Existing Conversation

1. Daemon loads conversations from SQLite after restart.
2. Flutter fetches conversation summaries through `/api/conversations`.
3. User opens a conversation from the session list.
4. Workbench activates that `ConversationSummary`.
5. Workbench sets the selected adapter display to `conversation.adapter`.
6. The adapter selector is locked because `activeConversationId != null`.

### Continue Existing Conversation

1. User sends another prompt in an active conversation.
2. Flutter sends only `conversationId` and message text.
3. Daemon uses the existing conversation record and its adapter.
4. UI continues showing the conversation adapter for consistency.

## UI Rules

- Adapter selection is enabled only when no active conversation exists.
- Adapter selection is disabled or ignored once a conversation is active.
- Opening a conversation must always display that conversation's adapter, even if it differs from the default preferred adapter.
- Starting a new conversation returns to the normal pre-conversation adapter selection behavior.

## ViewModel Rules

- `selectAdapter(adapter)` should no-op when an active conversation exists.
- `showConversation(item)` and `updateActiveConversation(conversation)` should synchronize `_selectedAdapter` from `conversation.adapter`.
- `clearActiveConversation()` should leave `_selectedAdapter` usable for the next new conversation; it may keep the last selected adapter if still available, but it must no longer be locked.
- Snapshot adapter refresh should not overwrite `_selectedAdapter` while a conversation is active.

## Persistence Rules

- No new database table is required.
- No new client-side persistent store is required.
- SQLite `conversations.adapter` remains the durable mapping from conversation to CLI adapter.
- Existing API responses remain sufficient as long as `ConversationSummary.adapter` is preserved.

## Test Plan

- Add or update Flutter ViewModel tests for:
  - Selecting an adapter before first send creates the conversation with that adapter.
  - Opening a `codex` conversation sets `selectedAdapter` to `codex`.
  - Opening a `claude` conversation sets `selectedAdapter` to `claude`.
  - Attempting to change adapter while a conversation is active does not change `selectedAdapter`.
  - Adapter refresh does not overwrite the active conversation's adapter.
- Add or verify daemon persistence coverage for:
  - Saved conversations retain `adapter` after store reload.

## Non-Goals

- Do not add workspace-level or global “last used CLI” preference.
- Do not allow mid-conversation CLI switching.
- Do not rewrite conversation protocol or adapter execution.
- Do not add a new dependency.

## Risks

- If an adapter used by an old conversation is no longer installed, the UI should still show the stored adapter identity. Sending should rely on daemon-side validation/error handling.
- If future UX wants per-workspace default CLI memory, that should be a separate preference layer and must not replace the conversation-level source of truth.
