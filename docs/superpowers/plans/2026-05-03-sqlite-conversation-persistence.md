# SQLite Conversation Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist conversation-native mobile coding sessions in SQLite under `data/conversations/conversations.sqlite` so history survives daemon and app restarts.

**Architecture:** Add a focused SQLite repository for conversation metadata and event logs, then wire it into `ConversationManager` and `ConversationEventStore`. Runtime process handles remain memory-only; live states restore as `interrupted` so the UI never shows fake running/approval states after restart.

**Tech Stack:** Node 24 `node:sqlite` `DatabaseSync`, existing daemon HTTP API, Flutter conversation models/status rendering, existing `scripts/run-tests.js` and Flutter tests.

---

## File Structure

- Create: `daemon/src/conversation-sqlite-store.js`
  - Owns SQLite open, migration, serialization, conversation CRUD, event append/list, and restart-state normalization.
- Modify: `daemon/src/conversation-protocol.js`
  - Adds `conversationStatuses.INTERRUPTED`.
- Modify: `daemon/src/conversation-event-store.js`
  - Adds optional `persistentStore` backend while preserving the current in-memory store behavior for tests.
- Modify: `daemon/src/conversation-manager.js`
  - Loads persisted conversations at startup and saves metadata changes on create/touch/status/blocking/session updates.
- Modify: `daemon/src/main.js`
  - Creates `ConversationSqliteStore` with default path `data/conversations/conversations.sqlite` or `CONVERSATION_DB_PATH`.
- Modify: `scripts/run-tests.js`
  - Adds SQLite persistence and restart tests.
- Modify: `mobile/lib/src/models/protocol.dart`
  - Accepts `interrupted` status transparently through existing string parsing; no enum is present, so likely no code change needed unless tests reveal otherwise.
- Modify: `mobile/lib/main.dart`
  - Displays interrupted state copy and avoids infinite running spinner.
- Modify: `mobile/test/protocol_compatibility_test.dart` or `mobile/test/widget_test.dart`
  - Adds a status parsing/rendering regression for `interrupted`.

## Task 1: SQLite Store Module

**Files:**
- Create: `daemon/src/conversation-sqlite-store.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing store persistence test**

Add this test near the existing conversation store tests in `scripts/run-tests.js`:

```js
test('SQLite conversation store persists conversations and events across instances', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { ConversationSqliteStore } = require('../daemon/src/conversation-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-sqlite-'));
  const dbPath = path.join(dir, 'conversations.sqlite');
  const first = new ConversationSqliteStore({ dbPath, now: () => new Date('2026-05-03T00:00:00.000Z') });
  first.saveConversation({
    id: 'conv_1',
    workspaceId: 'default',
    workspacePath: 'D:/AiProject/vibe-coding',
    adapter: 'claude',
    permissionMode: 'default',
    deviceId: 'device_1',
    status: 'idle',
    cliSessionId: 'session_1',
    blockingItem: null,
    idleExpiresAt: null,
    createdAt: '2026-05-03T00:00:00.000Z',
    updatedAt: '2026-05-03T00:00:01.000Z',
    capabilities: { resume: true },
    handle: null
  });
  first.appendEvent({
    seq: 1,
    conversationId: 'conv_1',
    type: 'user.message',
    createdAt: '2026-05-03T00:00:02.000Z',
    text: 'hello'
  });
  first.close();

  const second = new ConversationSqliteStore({ dbPath });
  const conversations = second.loadConversations();
  assert.equal(conversations.length, 1);
  assert.equal(conversations[0].id, 'conv_1');
  assert.equal(conversations[0].cliSessionId, 'session_1');
  assert.deepEqual(conversations[0].capabilities, { resume: true });
  assert.equal(conversations[0].handle, null);
  assert.deepEqual(second.listEvents('conv_1', 0).map((event) => event.text), ['hello']);
  second.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cmd.exe /c npm test`

Expected: FAIL with `Cannot find module '../daemon/src/conversation-sqlite-store'`.

- [ ] **Step 3: Implement SQLite store**

Create `daemon/src/conversation-sqlite-store.js` with this shape:

```js
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const LIVE_STATUSES = new Set(['running', 'waiting_input', 'waiting_approval']);

class ConversationSqliteStore {
  constructor({ dbPath = defaultDbPath(), now = () => new Date() } = {}) {
    this.dbPath = dbPath;
    this.now = now;
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    this.db = new DatabaseSync(dbPath);
    this.db.exec('PRAGMA foreign_keys = ON');
    this.migrate();
  }

  migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS conversations (
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
      CREATE INDEX IF NOT EXISTS idx_conversations_device_updated
        ON conversations(device_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_conversations_workspace_updated
        ON conversations(workspace_id, updated_at DESC);
      CREATE TABLE IF NOT EXISTS conversation_events (
        conversation_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (conversation_id, seq),
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_conversation_events_type_created
        ON conversation_events(type, created_at DESC);
    `);
    this.db.prepare('INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (?, ?)')
      .run(1, this.now().toISOString());
  }

  saveConversation(conversation) {
    const row = serializeConversation(conversation);
    this.db.prepare(`
      INSERT INTO conversations (
        id, workspace_id, workspace_path, adapter, permission_mode, device_id,
        status, cli_session_id, blocking_item_json, idle_expires_at,
        created_at, updated_at, capabilities_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        workspace_id = excluded.workspace_id,
        workspace_path = excluded.workspace_path,
        adapter = excluded.adapter,
        permission_mode = excluded.permission_mode,
        device_id = excluded.device_id,
        status = excluded.status,
        cli_session_id = excluded.cli_session_id,
        blocking_item_json = excluded.blocking_item_json,
        idle_expires_at = excluded.idle_expires_at,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        capabilities_json = excluded.capabilities_json
    `).run(
      row.id, row.workspace_id, row.workspace_path, row.adapter, row.permission_mode,
      row.device_id, row.status, row.cli_session_id, row.blocking_item_json,
      row.idle_expires_at, row.created_at, row.updated_at, row.capabilities_json
    );
  }

  loadConversations() {
    return this.db.prepare('SELECT * FROM conversations ORDER BY updated_at DESC')
      .all()
      .map(deserializeConversation);
  }

  appendEvent(event) {
    const { conversationId, seq, type, createdAt, ...payload } = event;
    this.db.prepare(`
      INSERT OR REPLACE INTO conversation_events(conversation_id, seq, type, created_at, payload_json)
      VALUES (?, ?, ?, ?, ?)
    `).run(conversationId, seq, type, createdAt, JSON.stringify(payload));
  }

  listEvents(conversationId, afterSeq = 0) {
    return this.db.prepare(`
      SELECT conversation_id, seq, type, created_at, payload_json
      FROM conversation_events
      WHERE conversation_id = ? AND seq > ?
      ORDER BY seq ASC
    `).all(conversationId, Number(afterSeq || 0)).map(deserializeEvent);
  }

  nextEventSeq(conversationId) {
    const row = this.db.prepare('SELECT COALESCE(MAX(seq), 0) + 1 AS next_seq FROM conversation_events WHERE conversation_id = ?')
      .get(conversationId);
    return row.next_seq;
  }

  close() {
    this.db.close();
  }
}

function defaultDbPath() {
  return path.join(process.cwd(), 'data', 'conversations', 'conversations.sqlite');
}

function serializeConversation(conversation) {
  return {
    id: conversation.id,
    workspace_id: conversation.workspaceId,
    workspace_path: conversation.workspacePath,
    adapter: conversation.adapter,
    permission_mode: conversation.permissionMode,
    device_id: conversation.deviceId,
    status: conversation.status,
    cli_session_id: conversation.cliSessionId || null,
    blocking_item_json: conversation.blockingItem ? JSON.stringify(conversation.blockingItem) : null,
    idle_expires_at: conversation.idleExpiresAt || null,
    created_at: conversation.createdAt,
    updated_at: conversation.updatedAt,
    capabilities_json: JSON.stringify(conversation.capabilities || {})
  };
}

function deserializeConversation(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    workspacePath: row.workspace_path,
    adapter: row.adapter,
    permissionMode: row.permission_mode,
    deviceId: row.device_id,
    status: LIVE_STATUSES.has(row.status) ? 'interrupted' : row.status,
    cliSessionId: row.cli_session_id || null,
    blockingItem: LIVE_STATUSES.has(row.status) ? null : parseJson(row.blocking_item_json, null),
    idleExpiresAt: LIVE_STATUSES.has(row.status) ? null : row.idle_expires_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    capabilities: parseJson(row.capabilities_json, {}),
    handle: null
  };
}

function deserializeEvent(row) {
  return {
    seq: row.seq,
    conversationId: row.conversation_id,
    type: row.type,
    createdAt: row.created_at,
    ...parseJson(row.payload_json, {})
  };
}

function parseJson(value, fallback) {
  if (!value) return fallback;
  return JSON.parse(value);
}

module.exports = { ConversationSqliteStore, defaultDbPath };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cmd.exe /c npm test`

Expected: The new SQLite store test passes; later tasks may still be needed for manager restart behavior.

## Task 2: Persistent Event Store

**Files:**
- Modify: `daemon/src/conversation-event-store.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing event store restart test**

Add this test after `conversation event store appends and replays ordered events`:

```js
test('conversation event store continues sequence numbers from SQLite', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const { ConversationSqliteStore } = require('../daemon/src/conversation-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-events-'));
  const dbPath = path.join(dir, 'conversations.sqlite');
  const sqlite = new ConversationSqliteStore({ dbPath, now: () => new Date('2026-05-03T00:00:00.000Z') });
  sqlite.saveConversation({
    id: 'conv_1', workspaceId: 'default', workspacePath: '.', adapter: 'claude',
    permissionMode: 'default', deviceId: 'device_1', status: 'idle', cliSessionId: null,
    blockingItem: null, idleExpiresAt: null, createdAt: '2026-05-03T00:00:00.000Z',
    updatedAt: '2026-05-03T00:00:00.000Z', capabilities: {}, handle: null
  });
  const first = new ConversationEventStore({ persistentStore: sqlite, now: () => new Date('2026-05-03T00:00:01.000Z') });
  first.append('conv_1', 'user.message', { text: 'one' });

  const second = new ConversationEventStore({ persistentStore: sqlite, now: () => new Date('2026-05-03T00:00:02.000Z') });
  const secondEvent = second.append('conv_1', 'assistant.message', { text: 'two' });
  assert.equal(secondEvent.seq, 2);
  assert.deepEqual(second.list('conv_1', 0).map((event) => event.text), ['one', 'two']);
  sqlite.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cmd.exe /c npm test`

Expected: FAIL because `ConversationEventStore` ignores `persistentStore`.

- [ ] **Step 3: Implement persistent event backend**

Update `ConversationEventStore` constructor and methods:

```js
class ConversationEventStore {
  constructor({ now = () => new Date(), persistentStore = null } = {}) {
    this.now = now;
    this.persistentStore = persistentStore;
    this.events = new Map();
  }

  append(conversationId, type, payload = {}) {
    if (!conversationId) throw new Error('conversationId is required');
    if (!type) throw new Error('event type is required');
    const list = this.events.get(conversationId) || [];
    const seq = this.persistentStore
      ? this.persistentStore.nextEventSeq(conversationId)
      : list.length + 1;
    const event = {
      seq,
      conversationId,
      type,
      createdAt: this.now().toISOString(),
      ...payload
    };
    list.push(event);
    this.events.set(conversationId, list);
    if (this.persistentStore) this.persistentStore.appendEvent(event);
    return event;
  }

  list(conversationId, afterSeq = 0) {
    if (this.persistentStore) return this.persistentStore.listEvents(conversationId, afterSeq);
    const seq = Number(afterSeq || 0);
    return (this.events.get(conversationId) || []).filter((event) => event.seq > seq);
  }
}
```

- [ ] **Step 4: Run backend tests**

Run: `cmd.exe /c npm test`

Expected: PASS for event store tests.

## Task 3: Conversation Manager Persistence and Restart Semantics

**Files:**
- Modify: `daemon/src/conversation-protocol.js`
- Modify: `daemon/src/conversation-manager.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing manager restart test**

Add this test near existing conversation manager tests:

```js
test('conversation manager restores persisted live conversation as interrupted', () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const { WorkspaceRegistry } = require('../daemon/src/workspace');
  const { AuditLog } = require('../daemon/src/audit');
  const { conversationStatuses } = require('../daemon/src/conversation-protocol');

  const persisted = [];
  const persistentStore = {
    loadConversations: () => persisted,
    saveConversation: (conversation) => {
      const snapshot = JSON.parse(JSON.stringify({ ...conversation, handle: null }));
      const index = persisted.findIndex((item) => item.id === snapshot.id);
      if (index >= 0) persisted[index] = snapshot;
      else persisted.push(snapshot);
    }
  };
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const adapters = new Map([['claude', { capabilities: { resume: true }, async startConversation() { throw new Error('not needed'); } }]]);
  const device = { id: 'device_1' };
  const first = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore(),
    auditLog: new AuditLog(),
    adapters,
    persistentStore,
    now: () => new Date('2026-05-03T00:00:00.000Z')
  });
  const conversation = first.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  const raw = persisted.find((item) => item.id === conversation.id);
  raw.status = conversationStatuses.WAITING_APPROVAL;
  raw.blockingItem = { type: 'approval_request', approvalId: 'ap1' };
  raw.idleExpiresAt = null;

  const restored = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore(),
    auditLog: new AuditLog(),
    adapters,
    persistentStore,
    now: () => new Date('2026-05-03T00:00:01.000Z')
  }).getConversation(conversation.id, device);

  assert.equal(restored.status, conversationStatuses.INTERRUPTED);
  assert.equal(restored.blockingItem, null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cmd.exe /c npm test`

Expected: FAIL because `INTERRUPTED` and manager load/persistence are not implemented.

- [ ] **Step 3: Add interrupted protocol status**

Modify `daemon/src/conversation-protocol.js`:

```js
const conversationStatuses = Object.freeze({
  IDLE: 'idle',
  RUNNING: 'running',
  WAITING_INPUT: 'waiting_input',
  WAITING_APPROVAL: 'waiting_approval',
  INTERRUPTED: 'interrupted',
  COMPLETED: 'completed',
  FAILED: 'failed',
  CANCELLED: 'cancelled',
  EXPIRED: 'expired'
});
```

Update the existing protocol test assertion:

```js
assert.equal(conversationStatuses.INTERRUPTED, 'interrupted');
```

- [ ] **Step 4: Wire persistent store into ConversationManager**

Change constructor signature to include `persistentStore = null`, store it, and load persisted conversations:

```js
constructor({ workspaces, eventStore, auditLog, adapters, persistentStore = null, idleTtlMs = 600000, now = () => new Date() }) {
  this.workspaces = workspaces;
  this.eventStore = eventStore;
  this.auditLog = auditLog;
  this.adapters = adapters;
  this.persistentStore = persistentStore;
  this.idleTtlMs = idleTtlMs;
  this.now = now;
  this.conversations = new Map();
  this.loadPersistedConversations();
}
```

Add methods:

```js
loadPersistedConversations() {
  if (!this.persistentStore) return;
  for (const loaded of this.persistentStore.loadConversations()) {
    const conversation = this.normalizeRestoredConversation(loaded);
    this.conversations.set(conversation.id, conversation);
    if (conversation.status !== loaded.status || loaded.blockingItem || loaded.idleExpiresAt) {
      this.persistConversation(conversation);
    }
  }
}

normalizeRestoredConversation(conversation) {
  const restored = { ...conversation, handle: null };
  if ([conversationStatuses.RUNNING, conversationStatuses.WAITING_INPUT, conversationStatuses.WAITING_APPROVAL].includes(restored.status)) {
    restored.status = conversationStatuses.INTERRUPTED;
    restored.blockingItem = null;
    restored.idleExpiresAt = null;
    restored.updatedAt = this.now().toISOString();
  }
  return restored;
}

persistConversation(conversation) {
  if (this.persistentStore) this.persistentStore.saveConversation(conversation);
}
```

Call `this.persistConversation(conversation)` after:

- Creating a conversation.
- `touch(conversation)` updates `updatedAt`.
- `setBlockingItem()` changes blocking state.
- `recordAdapterEvent()` changes `cliSessionId`, status, blocking item, or idle expiry.

Implement the simplest safe version by calling `persistConversation()` inside `touch(conversation)`:

```js
touch(conversation) {
  conversation.updatedAt = this.now().toISOString();
  this.persistConversation(conversation);
}
```

Also call it once at the end of `createConversation()` after `this.conversations.set(...)` and before returning.

- [ ] **Step 5: Run backend tests**

Run: `cmd.exe /c npm test`

Expected: PASS for manager restart tests.

## Task 4: App Wiring and Default Database Path

**Files:**
- Modify: `daemon/src/main.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing createApp wiring test**

Add this test near server/createApp tests:

```js
test('createApp wires SQLite conversation persistence from environment path', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { createApp } = require('../daemon/src/main');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-app-'));
  const dbPath = path.join(dir, 'nested', 'conversations.sqlite');
  const app = createApp({ conversationDbPath: dbPath, devAdapters: false });
  assert.equal(fs.existsSync(dbPath), true);
  app.conversationSqliteStore.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cmd.exe /c npm test`

Expected: FAIL because `conversationDbPath` and `conversationSqliteStore` are not wired.

- [ ] **Step 3: Wire store in main**

Modify imports in `daemon/src/main.js`:

```js
const { ConversationSqliteStore, defaultDbPath } = require('./conversation-sqlite-store');
```

Add option to `createApp`:

```js
conversationDbPath = process.env.CONVERSATION_DB_PATH || defaultDbPath(),
```

Create the store before `ConversationEventStore`:

```js
const conversationSqliteStore = new ConversationSqliteStore({ dbPath: conversationDbPath });
const conversationEventStore = new ConversationEventStore({ persistentStore: conversationSqliteStore });
```

Pass it to manager:

```js
persistentStore: conversationSqliteStore,
```

Return it from `createApp()`:

```js
return { server, auth, workspaces, eventStore, conversationEventStore, conversationSqliteStore, ... };
```

- [ ] **Step 4: Run backend tests**

Run: `cmd.exe /c npm test`

Expected: PASS.

## Task 5: End-to-End Restart Persistence Test

**Files:**
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing API-level restart test**

Add a test using existing `request()` helper:

```js
test('conversation API lists persisted conversations and replays events after app restart', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { createApp } = require('../daemon/src/main');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-api-'));
  const dbPath = path.join(dir, 'conversations.sqlite');
  const first = createApp({ conversationDbPath: dbPath, devAdapters: true });
  const token = first.auth.issuePairingCode().token;
  const created = await request(first.config.port, 'POST', '/api/conversations', {
    workspaceId: 'default', adapter: 'claude', permissionMode: 'default'
  }, token, first.server);
  const conversationId = created.body.conversation.id;
  first.conversationEventStore.append(conversationId, 'user.message', { text: 'persist me' });
  first.conversationSqliteStore.close();

  const second = createApp({ conversationDbPath: dbPath, devAdapters: true });
  const token2 = second.auth.issuePairingCode().token;
  const listed = await request(second.config.port, 'GET', '/api/conversations', null, token2, second.server);
  assert.equal(listed.body.conversations.some((item) => item.id === conversationId), true);
  const events = await request(second.config.port, 'GET', `/api/conversations/${conversationId}/events?afterSeq=0`, null, token2, second.server);
  assert.equal(events.body.events.some((event) => event.text === 'persist me'), true);
  second.conversationSqliteStore.close();
});
```

If the existing `request()` helper does not accept a direct server parameter, adapt this test to follow the repo's current server test pattern exactly instead of changing the helper globally.

- [ ] **Step 2: Run test to verify behavior**

Run: `cmd.exe /c npm test`

Expected: PASS after prior tasks, or FAIL only due to helper mismatch.

- [ ] **Step 3: Fix helper mismatch if needed**

If the helper cannot call an unlistened server directly, use the existing pattern in `scripts/run-tests.js` that starts a server on a random/local test port. Keep both app instances closed after assertions.

- [ ] **Step 4: Run backend tests again**

Run: `cmd.exe /c npm test`

Expected: PASS.

## Task 6: Flutter Interrupted Status Display

**Files:**
- Modify: `mobile/lib/main.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write failing interrupted status test**

Add a test that exercises the visible status helper or widget path already used for pending status tests. If a direct helper does not exist, add a small `@visibleForTesting` helper:

```dart
@visibleForTesting
String debugConversationPendingStatusText(String status) =>
    _conversationPendingStatusText(status, const <ConversationEvent>[]);
```

Test:

```dart
test('interrupted conversation status uses recoverable copy', () {
  expect(debugConversationPendingStatusText('interrupted'),
      contains('会话已中断'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cmd.exe /c flutter test`

Expected: FAIL because interrupted status copy is missing.

- [ ] **Step 3: Implement interrupted copy**

Extract the pending status text logic around `_pendingStatusText` in `mobile/lib/main.dart` into a helper:

```dart
String _conversationPendingStatusText(
    String status, Iterable<ConversationEvent> events) {
  if (status == 'interrupted') return '会话已中断，可继续发送新消息恢复上下文';
  if (status == 'waiting_input') return '等待你回复问题…';
  if (status == 'waiting_approval') return '等待你确认权限请求…';
  if (events.isEmpty) return '正在启动 CLI 会话…';
  for (final event in events.toList().reversed) {
    if (event.type == 'assistant.partial') return '正在生成回复…';
    if (event.type == 'tool.started') {
      return '正在执行 ${event.toolName ?? '工具调用'}…';
    }
    if (event.type == 'tool.output') return '正在接收工具输出…';
    if (event.type == 'diff.summary') return '正在汇总文件变更…';
    if (event.type == 'conversation.started') {
      return 'CLI 会话已启动，正在读取上下文…';
    }
  }
  return '等待下一条事件…';
}
```

Then `_pendingStatusText` returns:

```dart
String get _pendingStatusText => _conversationPendingStatusText(
    _activeConversation?.status ?? _conversationState.status,
    _conversationEvents);
```

Ensure `_isRunningCli` treats `interrupted` as not running.

- [ ] **Step 4: Run Flutter tests**

Run: `cmd.exe /c flutter test`

Expected: PASS.

## Task 7: Final Verification

**Files:**
- Verify only unless tests reveal small fixes.

- [ ] **Step 1: Run backend tests**

Run: `cmd.exe /c npm test`

Expected: All tests pass.

- [ ] **Step 2: Run Flutter analyze and tests**

Run: `cmd.exe /c dart format lib\main.dart test\widget_test.dart && flutter analyze && flutter test`

Expected: `No issues found!` and all Flutter tests pass.

- [ ] **Step 3: Optional Windows build**

Run only if `lan_ai_cli_control.exe` is closed:

```cmd
flutter build windows --debug
```

Expected: Build succeeds. If it fails with `LNK1168`, close the running app and rerun.

## Self-Review

- Spec coverage: SQLite path, data directory, status `interrupted`, event replay, session resume metadata, API compatibility, and tests are covered.
- Placeholder scan: No `TBD` or open-ended implementation steps remain; Task 5 includes a bounded helper contingency because the existing helper shape must be inspected during implementation.
- Type consistency: Store methods are consistently named `saveConversation`, `loadConversations`, `appendEvent`, `listEvents`, and `nextEventSeq` across tasks.
