# SQLite Conversation Persistence Design

## Goal

Persist mobile coding conversations so the conversation list and message history survive app and daemon restarts. The persisted data must represent real CLI conversations and event replay, not a Flutter-only cache.

## Decisions

- Use SQLite instead of JSON files for query speed, indexing, and future growth.
- Store application runtime data under `data/`, not `.omx/`.
- Use `data/conversations/conversations.sqlite` as the default database path.
- Allow `CONVERSATION_DB_PATH` to override the database path for tests and deployments.
- On daemon restart, convert non-terminal live states to `interrupted` rather than pretending the old CLI process is still alive.

## Non-Goals

- Do not persist process handles or attempt to resurrect an OS process after daemon restart.
- Do not persist old approval prompts as actionable after restart.
- Do not redesign the existing HTTP conversation API unless required for `interrupted` status display.
- Do not migrate legacy run-based history in this phase.

## Storage Layout

Default layout:

```text
data/
  conversations/
    conversations.sqlite
```

The daemon creates the parent directory if it does not exist. Tests should use a temporary database path through `CONVERSATION_DB_PATH` or direct constructor injection.

## Database Driver

Use Node's built-in `node:sqlite` `DatabaseSync` driver on the current Node 24 runtime. This avoids a new native npm dependency such as `better-sqlite3`.

If `node:sqlite` becomes unavailable in a future runtime, the persistence module should fail with a clear startup error explaining that Node 24+ or an alternate SQLite backend is required.

## Schema

### `schema_migrations`

Tracks applied schema versions.

```sql
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
```

### `conversations`

Stores the public conversation state and enough internal metadata to resume safely.

```sql
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  workspace_path TEXT NOT NULL,
  adapter TEXT NOT NULL,
  permission_mode TEXT NOT NULL,
  device_id TEXT NOT NULL,
  status TEXT NOT NULL,
  cli_session_id TEXT,
  blocking_item_json TEXT,
  idle_expires_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  capabilities_json TEXT NOT NULL DEFAULT '{}'
);
```

Indexes:

```sql
CREATE INDEX idx_conversations_device_updated
ON conversations(device_id, updated_at DESC);

CREATE INDEX idx_conversations_workspace_updated
ON conversations(workspace_id, updated_at DESC);
```

### `conversation_events`

Stores the append-only event stream used by the mobile reducer.

```sql
CREATE TABLE conversation_events (
  conversation_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  type TEXT NOT NULL,
  created_at TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (conversation_id, seq),
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);
```

Indexes:

```sql
CREATE INDEX idx_conversation_events_type_created
ON conversation_events(type, created_at DESC);
```

## Runtime Architecture

### `ConversationSqliteStore`

Add a new daemon storage module responsible for:

- Opening the SQLite database.
- Running migrations.
- Creating the data directory.
- Saving conversation records.
- Updating conversation status and metadata.
- Appending conversation events.
- Listing conversations by device.
- Fetching events after a sequence number.

It should expose plain JavaScript objects so `ConversationManager` and `ConversationEventStore` remain easy to test.

### `ConversationEventStore`

Extend the existing event store with an optional persistence backend:

- Keep the in-memory `Map` for fast access during the daemon lifetime.
- On `append()`, write to SQLite immediately after constructing the event.
- On `list()`, prefer SQLite when a persistence backend exists so events survive daemon restart.
- Preserve sequence allocation as `max(seq) + 1` per conversation when restored from SQLite.

### `ConversationManager`

Extend the manager with an optional conversation persistence backend:

- On startup, load conversations from SQLite into the internal `Map`.
- Strip runtime-only `handle` fields on load.
- Convert `running`, `waiting_input`, and `waiting_approval` to `interrupted`.
- Clear `blockingItem` and `idleExpiresAt` when marking interrupted.
- Persist every create, status change, `cliSessionId`, blocking item, and timestamp change.

## Restart Semantics

Terminal states remain unchanged:

- `idle`
- `completed` if introduced later
- `failed`
- `cancelled`

Live states become `interrupted`:

- `running`
- `waiting_input`
- `waiting_approval`

The public conversation payload should include `status: "interrupted"`. The UI should show a neutral state such as “会话已中断，可继续发送新消息恢复上下文”.

When the user continues an interrupted conversation:

- If `cliSessionId` exists, pass it to the adapter as `sessionId` so Claude can resume.
- If `cliSessionId` is missing, start a fresh CLI process while preserving visible history.
- Do not reuse old `questionId` or `approvalId`; those belonged to a dead process.

## API Compatibility

Existing routes stay stable:

- `GET /api/conversations`
- `POST /api/conversations`
- `GET /api/conversations/:id/events?afterSeq=0`
- `POST /api/conversations/:id/messages`
- `POST /api/conversations/:id/questions/respond`
- `POST /api/conversations/:id/approvals/:approvalId/respond`
- `POST /api/conversations/:id/cancel`

Only the status enum expands to include `interrupted`.

## Error Handling

- Database open or migration failure should fail daemon startup with a clear message.
- Event append failures should fail the current request or adapter event path rather than silently dropping history.
- JSON parse failures while loading old rows should skip the broken row only if the error is isolated and logged; otherwise fail startup to avoid corrupt conversation state.
- If SQLite is locked, let the current operation fail loudly in this phase. Retry/backoff can be added after evidence shows lock contention.

## Testing Plan

### Daemon Unit Tests

- Create a temporary SQLite database, create a conversation, append events, recreate the store/manager, and verify the conversation is listed.
- Verify `GET events afterSeq=0` returns the full persisted event stream after restart.
- Verify `running`, `waiting_input`, and `waiting_approval` restore as `interrupted` with no blocking item.
- Verify `idle`, `failed`, and `cancelled` restore unchanged.
- Verify sequence numbers continue after restart instead of resetting to `1`.
- Verify `cliSessionId` persists and is passed back into `startConversation()` when continuing.

### Flutter Tests

- Parse and display `interrupted` status without crashing.
- Show interrupted copy instead of an infinite running spinner.
- Existing conversation reducer tests should continue to pass because event shapes are unchanged.

### Verification Commands

- `cmd.exe /c npm test`
- `cmd.exe /c flutter analyze`
- `cmd.exe /c flutter test`

## Rollout

1. Add SQLite persistence module and migrations.
2. Wire persistence into `createApp()` with default `data/conversations/conversations.sqlite`.
3. Update `ConversationEventStore` to persist and replay events.
4. Update `ConversationManager` to persist and restore conversation metadata.
5. Add `interrupted` to conversation status normalization and Flutter display logic.
6. Add daemon restart persistence tests.
7. Run backend and Flutter verification.

## Open Risks

- `node:sqlite` is currently experimental in Node 24, though it avoids native package installation.
- Synchronous SQLite writes are acceptable for local daemon usage, but high-frequency streaming events could need batching later.
- Interrupted resume quality depends on each CLI adapter's true session resume support.
