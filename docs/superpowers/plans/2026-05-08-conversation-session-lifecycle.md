# Conversation Session Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make stop/cancel affect only the active CLI executor while preserving the product conversation, visible messages, replay path, and trusted CLI resume binding.

**Architecture:** Treat `Conversation` as the only persisted product session and treat adapter handles as in-memory executor resources. Add explicit `sessionBinding` state beside `cliSessionId`, persist binding before emitting session-visible events, and update mobile session/list logic to preserve conversation-backed items through cancelled, failed, and interrupted states.

**Tech Stack:** Node.js daemon with CommonJS modules and SQLite-backed `AppSqliteStore`; Flutter/Dart mobile client; existing `scripts/run-tests.js`, `mobile/test/widget_test.dart`, `mobile/test/protocol_compatibility_test.dart`, and reducer/controller tests.

---

## File Structure

- Modify: `daemon/src/conversation-protocol.js` — define canonical session binding values and status grouping helpers.
- Modify: `daemon/src/conversation-manager.js` — persist session binding transitions, preserve conversations on cancel/watchdog errors, resume confirmed or drifted sessions with the original `cliSessionId`, and emit drift warnings.
- Modify: `daemon/src/app-sqlite-store.js` — add `session_binding` and `user_message_count` storage/migration support for `conversations` rows.
- Modify: `daemon/src/conversation-sqlite-store.js` — keep as compatibility export only unless tests require a direct helper export.
- Modify: `daemon/src/claude-conversation-adapter.js` — ensure adapter session events expose the received CLI session id consistently as `sessionId`.
- Modify: `scripts/run-tests.js` — add daemon regression tests for binding persistence, cancellation semantics, drift, resume, and no-progress watchdog behavior.
- Modify: `mobile/lib/src/models/protocol.dart` — parse `sessionBinding` and `userMessageCount` from `ConversationSummary`.
- Modify: `mobile/lib/src/features/sessions/session_item.dart` — keep a conversation-backed identity even when display uses `RunSummary`.
- Modify: `mobile/lib/src/features/sessions/session_list_view_model.dart` — do not degrade cancelled/failed/interrupted conversations into run-only items or hide legacy interrupted rows.
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart` — remove broad terminal-state clearing for reusable statuses, keep `_activeConversationId`, preserve messages on stop, and show binding/recoverability warnings.
- Modify: `mobile/lib/src/features/workbench/coding_workbench_controller.dart` — centralize reusable/active status helpers if existing controller tests need pure functions.
- Modify: `mobile/lib/src/state/conversation_reducer.dart` — keep messages on cancelled/failed/interrupted events and apply drift warnings without clearing timeline.
- Modify: `mobile/test/protocol_compatibility_test.dart` — cover new summary fields and backwards-compatible defaults.
- Modify: `mobile/test/conversation_reducer_test.dart` — cover status transitions preserving messages.
- Modify: `mobile/test/coding_workbench_controller_test.dart` — cover pure status helpers and send eligibility.
- Modify: `mobile/test/widget_test.dart` — cover stop preserving messages/id, session list preservation, replay reopening, daemon disconnect composer disable, send failure draft restoration, and reusable status send.

---

### Task 1: Protocol Status And Binding Helpers

**Files:**
- Modify: `daemon/src/conversation-protocol.js`
- Modify: `scripts/run-tests.js`
- Modify: `mobile/lib/src/models/protocol.dart`
- Modify: `mobile/test/protocol_compatibility_test.dart`

- [ ] **Step 1: Write daemon protocol helper tests**

Add this test near existing protocol normalization tests in `scripts/run-tests.js`.

```js
test('conversation protocol exposes session binding and reusable status helpers', () => {
  const {
    conversationSessionBindings,
    isConversationActiveStatus,
    isConversationReusableStatus,
    isConversationTerminalStatus
  } = require('../daemon/src/conversation-protocol');

  assert.equal(conversationSessionBindings.UNKNOWN, 'unknown');
  assert.equal(conversationSessionBindings.CONFIRMED, 'confirmed');
  assert.equal(conversationSessionBindings.DRIFTED, 'drifted');
  assert.equal(isConversationActiveStatus('running'), true);
  assert.equal(isConversationActiveStatus('waiting_input'), true);
  assert.equal(isConversationReusableStatus('cancelled'), true);
  assert.equal(isConversationReusableStatus('failed'), true);
  assert.equal(isConversationReusableStatus('interrupted'), true);
  assert.equal(isConversationReusableStatus('idle'), true);
  assert.equal(isConversationTerminalStatus('expired'), true);
  assert.equal(isConversationTerminalStatus('cancelled'), false);
});
```

- [ ] **Step 2: Run daemon test and verify it fails before helper export**

Run: `npm test`

Expected: FAIL with `conversationSessionBindings` or helper function missing.

- [ ] **Step 3: Add binding constants and status helpers**

Update `daemon/src/conversation-protocol.js` with these exports.

```js
const conversationSessionBindings = Object.freeze({
  UNKNOWN: 'unknown',
  CONFIRMED: 'confirmed',
  DRIFTED: 'drifted'
});

const activeConversationStatuses = new Set([
  conversationStatuses.RUNNING,
  conversationStatuses.WAITING_INPUT,
  conversationStatuses.WAITING_APPROVAL
]);

const reusableConversationStatuses = new Set([
  conversationStatuses.IDLE,
  conversationStatuses.CANCELLED,
  conversationStatuses.FAILED,
  conversationStatuses.INTERRUPTED
]);

const terminalConversationStatuses = new Set([
  conversationStatuses.COMPLETED,
  conversationStatuses.EXPIRED
]);

function isConversationActiveStatus(status) {
  return activeConversationStatuses.has(status);
}

function isConversationReusableStatus(status) {
  return reusableConversationStatuses.has(status);
}

function isConversationTerminalStatus(status) {
  return terminalConversationStatuses.has(status);
}
```

Add these names to `module.exports`.

```js
conversationSessionBindings,
isConversationActiveStatus,
isConversationReusableStatus,
isConversationTerminalStatus
```

- [ ] **Step 4: Add mobile summary compatibility tests**

Add these tests to `mobile/test/protocol_compatibility_test.dart`.

```dart
test('ConversationSummary parses session binding and user message count', () {
  final summary = ConversationSummary.fromJson(const <String, Object?>{
    'id': 'conv_1',
    'workspaceId': 'workspace_1',
    'adapter': 'claude',
    'status': 'cancelled',
    'cliSessionId': 'claude-session-1',
    'sessionBinding': 'confirmed',
    'userMessageCount': 2,
    'createdAt': '2026-05-08T00:00:00.000Z',
    'updatedAt': '2026-05-08T00:00:01.000Z',
    'capabilities': <String, Object?>{'resume': true},
  });

  expect(summary.sessionBinding, 'confirmed');
  expect(summary.userMessageCount, 2);
  expect(summary.cliSessionId, 'claude-session-1');
});

test('ConversationSummary defaults legacy session binding safely', () {
  final summary = ConversationSummary.fromJson(const <String, Object?>{
    'id': 'conv_legacy',
    'workspaceId': 'workspace_1',
    'adapter': 'claude',
    'status': 'interrupted',
    'createdAt': '2026-05-08T00:00:00.000Z',
    'updatedAt': '2026-05-08T00:00:01.000Z',
    'capabilities': <String, Object?>{},
  });

  expect(summary.sessionBinding, 'unknown');
  expect(summary.userMessageCount, 0);
});
```

- [ ] **Step 5: Run mobile protocol test and verify it fails before model update**

Run: `cd mobile && flutter test test\protocol_compatibility_test.dart`

Expected: FAIL with missing `sessionBinding` or `userMessageCount` getter/constructor field.

- [ ] **Step 6: Add fields to `ConversationSummary`**

Update `mobile/lib/src/models/protocol.dart`.

```dart
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.workspaceId,
    required this.adapter,
    required this.status,
    required this.capabilities,
    required this.createdAt,
    required this.updatedAt,
    this.protocolVersion = 1,
    this.requestedPermissionMode = '',
    this.effectivePermissionMode = '',
    this.permissionSupport = const <String, Object?>{},
    this.cliSessionId,
    this.sessionBinding = 'unknown',
    this.userMessageCount = 0,
    this.blockingItem,
    this.idleExpiresAt,
  });

  final String sessionBinding;
  final int userMessageCount;
}
```

In `ConversationSummary.fromJson`, parse the fields like this.

```dart
sessionBinding: json['sessionBinding'] as String? ?? 'unknown',
userMessageCount: json['userMessageCount'] as int? ?? 0,
```

- [ ] **Step 7: Run protocol tests**

Run:

```bash
npm test
cd mobile && flutter test test\protocol_compatibility_test.dart
```

Expected: both pass.

- [ ] **Step 8: Commit protocol helpers**

Run:

```bash
git add daemon/src/conversation-protocol.js scripts/run-tests.js mobile/lib/src/models/protocol.dart mobile/test/protocol_compatibility_test.dart
git commit -m "Define conversation session lifecycle vocabulary" -m "Cancellation and resume behavior need explicit vocabulary for executor status and CLI session binding, so both daemon and mobile parse reusable statuses and binding reliability independently.\n\nConstraint: Existing mobile clients must parse legacy summaries without these fields.\nRejected: Treat cancelled as terminal | stopped conversations must remain reusable.\nConfidence: high\nScope-risk: moderate\nTested: npm test; cd mobile && flutter test test\\protocol_compatibility_test.dart"
```

---

### Task 2: Persist Session Binding And Legacy Metadata

**Files:**
- Modify: `daemon/src/app-sqlite-store.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write SQLite migration and round-trip tests**

Add this test near existing app SQLite conversation persistence tests in `scripts/run-tests.js`.

```js
test('app SQLite store persists session binding and user message count', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-lifecycle-'));
  const dbPath = path.join(dir, 'app.sqlite');
  const store = new AppSqliteStore({ dbPath, now: fixedNow });

  store.saveConversation({
    id: 'conv_binding',
    workspaceId: 'workspace_1',
    workspacePath: '/tmp/project',
    adapter: 'claude',
    permissionMode: 'default',
    deviceId: 'device_1',
    status: 'cancelled',
    cliSessionId: 'claude-session-1',
    sessionBinding: 'confirmed',
    userMessageCount: 3,
    blockingItem: null,
    idleExpiresAt: null,
    createdAt: '2026-05-08T00:00:00.000Z',
    updatedAt: '2026-05-08T00:00:01.000Z',
    capabilities: { resume: true }
  });

  const loaded = store.loadConversations()[0];
  assert.equal(loaded.sessionBinding, 'confirmed');
  assert.equal(loaded.userMessageCount, 3);
  assert.equal(loaded.cliSessionId, 'claude-session-1');
});
```

- [ ] **Step 2: Write legacy load normalization test**

Add a test that manually creates an older-looking row with a user message event and no session id.

```js
test('app SQLite store marks legacy message conversations as interrupted metadata', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-legacy-'));
  const dbPath = path.join(dir, 'app.sqlite');
  const store = new AppSqliteStore({ dbPath, now: fixedNow });
  store.saveConversation({
    id: 'conv_legacy',
    workspaceId: 'workspace_1',
    workspacePath: '/tmp/project',
    adapter: 'claude',
    permissionMode: 'default',
    deviceId: 'device_1',
    status: 'idle',
    cliSessionId: null,
    sessionBinding: 'unknown',
    userMessageCount: 0,
    blockingItem: null,
    idleExpiresAt: null,
    createdAt: '2026-05-08T00:00:00.000Z',
    updatedAt: '2026-05-08T00:00:01.000Z',
    capabilities: { resume: true }
  });
  store.appendEvent({
    conversationId: 'conv_legacy',
    seq: 1,
    type: 'user.message',
    createdAt: '2026-05-08T00:00:02.000Z',
    text: 'hello'
  });

  const loaded = store.loadConversations()[0];

  assert.equal(loaded.status, 'interrupted');
  assert.equal(loaded.sessionBinding, 'unknown');
  assert.equal(loaded.userMessageCount, 1);
});
```

- [ ] **Step 3: Run daemon tests and verify persistence failures**

Run: `npm test`

Expected: FAIL with missing `session_binding`, `user_message_count`, or normalization behavior.

- [ ] **Step 4: Extend schema migration**

Update conversation table setup in `daemon/src/app-sqlite-store.js` so new databases include these columns.

```sql
session_binding TEXT NOT NULL DEFAULT 'unknown',
user_message_count INTEGER NOT NULL DEFAULT 0,
```

After schema creation, add idempotent migration helpers.

```js
ensureColumn(this.db, 'conversations', 'session_binding', "TEXT NOT NULL DEFAULT 'unknown'");
ensureColumn(this.db, 'conversations', 'user_message_count', 'INTEGER NOT NULL DEFAULT 0');
```

Define `ensureColumn` in the same file if no equivalent exists.

```js
function ensureColumn(db, table, column, definition) {
  const rows = db.prepare(`PRAGMA table_info(${table})`).all();
  if (rows.some((row) => row.name === column)) return;
  db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
}
```

- [ ] **Step 5: Serialize and deserialize lifecycle metadata**

Update `saveConversation`, `serializeConversation`, and `deserializeConversation` in `daemon/src/app-sqlite-store.js`.

```js
session_binding,
user_message_count,
```

Serialization rules:

```js
session_binding: conversation.sessionBinding || 'unknown',
user_message_count: Number(conversation.userMessageCount || 0),
```

Deserialization rules:

```js
sessionBinding: row.session_binding || (row.cli_session_id ? 'confirmed' : 'unknown'),
userMessageCount: Number(row.user_message_count || 0),
```

- [ ] **Step 6: Normalize legacy user-message rows during load**

In `loadConversations()`, after `deserializeConversation(row)`, count user messages for rows with zero `userMessageCount`.

```js
const userMessageCount = this.db.prepare(`
  SELECT COUNT(*) AS count
  FROM conversation_events
  WHERE conversation_id = ? AND type = 'user.message'
`).get(conversation.id).count;
if (conversation.userMessageCount === 0 && userMessageCount > 0) {
  conversation.userMessageCount = userMessageCount;
}
if (!conversation.cliSessionId && conversation.userMessageCount > 0 && conversation.status === 'idle') {
  conversation.status = 'interrupted';
  conversation.sessionBinding = 'unknown';
}
return conversation;
```

- [ ] **Step 7: Run daemon tests**

Run: `npm test`

Expected: pass.

- [ ] **Step 8: Commit persistence changes**

Run:

```bash
git add daemon/src/app-sqlite-store.js scripts/run-tests.js
git commit -m "Persist conversation binding reliability" -m "Conversation summaries need enough persisted metadata to distinguish reusable stopped conversations from empty drafts, especially after restart or older partially-written rows.\n\nConstraint: Existing SQLite files may lack lifecycle columns.\nRejected: Per-row session-list event queries on mobile | slower and duplicates server knowledge.\nConfidence: high\nScope-risk: moderate\nTested: npm test"
```

---

### Task 3: Bind CLI Session IDs Atomically

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write binding persistence failure test**

Add this test near existing conversation manager tests in `scripts/run-tests.js`.

```js
test('session id binding persistence failure emits run.error and remains unknown', async () => {
  const fixture = createConversationManagerFixture();
  const { manager, device, adapter, eventStore } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  const originalSave = manager.persistentStore.saveConversation;
  manager.persistentStore.saveConversation = (conversation) => {
    if (conversation.cliSessionId === 'claude-session-1') throw new Error('db write failed');
    return originalSave.call(manager.persistentStore, conversation);
  };

  await manager.sendMessage(created.id, { text: 'hello' }, device);
  adapter.emit({ type: 'system.notice', sessionId: 'claude-session-1', text: 'started' });

  const summary = manager.getConversation(created.id, device);
  const events = eventStore.list(created.id, 0);
  assert.equal(summary.cliSessionId, null);
  assert.equal(summary.sessionBinding, 'unknown');
  assert.equal(events.some((event) => event.type === 'run.error' && /db write failed/.test(event.message)), true);
});
```

Use the repository's actual fixture helper names. The key expectations must remain: no confirmed binding, `run.error` emitted.

- [ ] **Step 2: Write drift detection test**

Add this daemon test.

```js
test('session id drift keeps original binding and emits warning', async () => {
  const fixture = createConversationManagerFixture();
  const { manager, device, adapter, eventStore } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(created.id, { text: 'first' }, device);
  adapter.emit({ type: 'system.notice', sessionId: 'original-session', text: 'started' });
  adapter.complete();
  await manager.sendMessage(created.id, { text: 'second' }, device);
  adapter.emit({ type: 'system.notice', sessionId: 'drifted-session', text: 'started again' });

  const summary = manager.getConversation(created.id, device);
  const warning = eventStore.list(created.id, 0).find((event) =>
    event.type === 'protocol.warning' && event.warning === 'session_id_drift');

  assert.equal(summary.cliSessionId, 'original-session');
  assert.equal(summary.sessionBinding, 'drifted');
  assert.equal(warning.expectedSessionId, 'original-session');
  assert.equal(warning.receivedSessionId, 'drifted-session');
});
```

- [ ] **Step 3: Run daemon tests and verify binding behavior fails**

Run: `npm test`

Expected: FAIL because manager currently sets `cliSessionId` before guaranteed persistence and does not track `sessionBinding` drift.

- [ ] **Step 4: Initialize session binding in new conversations**

In `daemon/src/conversation-manager.js`, import `conversationSessionBindings` and set this field in `createConversation`.

```js
sessionBinding: conversationSessionBindings.UNKNOWN,
userMessageCount: 0,
```

- [ ] **Step 5: Add atomic binding helper**

Add this method to `ConversationManager`.

```js
confirmSessionBinding(conversation, receivedSessionId) {
  if (!receivedSessionId) return true;
  if (!conversation.cliSessionId) {
    const previousSessionId = conversation.cliSessionId;
    conversation.cliSessionId = receivedSessionId;
    conversation.sessionBinding = conversationSessionBindings.CONFIRMED;
    try {
      this.persistConversation(conversation);
      return true;
    } catch (error) {
      conversation.cliSessionId = previousSessionId || null;
      conversation.sessionBinding = conversationSessionBindings.UNKNOWN;
      conversation.status = conversationStatuses.FAILED;
      conversation.blockingItem = null;
      this.eventStore.append(conversation.id, conversationEventTypes.RUN_ERROR, {
        message: `Failed to persist CLI session binding: ${error.message}`,
        recoverable: true
      });
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, {
        status: conversation.status
      });
      return false;
    }
  }
  if (conversation.cliSessionId !== receivedSessionId) {
    conversation.sessionBinding = conversationSessionBindings.DRIFTED;
    this.persistConversation(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.PROTOCOL_WARNING, {
      warning: 'session_id_drift',
      conversationId: conversation.id,
      expectedSessionId: conversation.cliSessionId,
      receivedSessionId,
      adapter: conversation.adapter
    });
    return true;
  }
  if (conversation.sessionBinding !== conversationSessionBindings.DRIFTED) {
    conversation.sessionBinding = conversationSessionBindings.CONFIRMED;
  }
  return true;
}
```

- [ ] **Step 6: Use helper before appending session-visible events**

At the top of `recordAdapterEvent(conversation, event)`, replace direct assignment with this guard.

```js
if (event.sessionId) {
  const persisted = this.confirmSessionBinding(conversation, event.sessionId);
  if (!persisted) return;
}
```

Delete the old block that directly mutates `conversation.cliSessionId`.

- [ ] **Step 7: Include binding in public summaries**

Update `publicConversation(conversation)`.

```js
sessionBinding: conversation.sessionBinding || (conversation.cliSessionId ? 'confirmed' : 'unknown'),
userMessageCount: Number(conversation.userMessageCount || 0),
```

- [ ] **Step 8: Run daemon tests**

Run: `npm test`

Expected: pass.

- [ ] **Step 9: Commit binding manager changes**

Run:

```bash
git add daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Bind CLI sessions before exposing resume events" -m "A conversation must not advertise a confirmed CLI session unless the binding is persisted, and drift must not silently replace the original resume id.\n\nConstraint: Adapter session ids arrive asynchronously in event streams.\nRejected: Overwrite cliSessionId on every adapter event | would break resume continuity after drift.\nConfidence: high\nScope-risk: moderate\nTested: npm test"
```

---

### Task 4: Preserve Conversations On Cancel And Resume

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write cancel-after-confirmed test**

Add this daemon test.

```js
test('cancel with confirmed cliSessionId keeps conversation reusable and preserves binding', async () => {
  const fixture = createConversationManagerFixture();
  const { manager, device, adapter, eventStore } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(created.id, { text: 'hello' }, device);
  adapter.emit({ type: 'system.notice', sessionId: 'claude-session-1', text: 'started' });
  await manager.cancelConversation(created.id, device);

  const summary = manager.getConversation(created.id, device);
  const events = eventStore.list(created.id, 0);
  assert.equal(summary.status, 'cancelled');
  assert.equal(summary.cliSessionId, 'claude-session-1');
  assert.equal(summary.sessionBinding, 'confirmed');
  assert.equal(events.some((event) => event.type === 'conversation.cancelled'), true);
});
```

- [ ] **Step 2: Write cancel-before-session test**

```js
test('cancel before session id marks conversation interrupted', async () => {
  const fixture = createConversationManagerFixture();
  const { manager, device, eventStore } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(created.id, { text: 'hello' }, device);
  await manager.cancelConversation(created.id, device);

  const summary = manager.getConversation(created.id, device);
  const events = eventStore.list(created.id, 0);
  assert.equal(summary.status, 'interrupted');
  assert.equal(summary.cliSessionId, null);
  assert.equal(summary.sessionBinding, 'unknown');
  assert.equal(events.some((event) => event.type === 'conversation.status_changed' && event.status === 'interrupted'), true);
});
```

- [ ] **Step 3: Write resume-after-cancel test**

```js
test('next message after cancelled conversation resumes confirmed cliSessionId', async () => {
  const fixture = createConversationManagerFixture();
  const { manager, device, adapter } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(created.id, { text: 'first' }, device);
  adapter.emit({ type: 'system.notice', sessionId: 'claude-session-1', text: 'started' });
  await manager.cancelConversation(created.id, device);
  await manager.sendMessage(created.id, { text: 'second' }, device);

  assert.equal(adapter.startCalls.at(-1).sessionId, 'claude-session-1');
});
```

- [ ] **Step 4: Run daemon tests and verify cancel semantics fail before implementation**

Run: `npm test`

Expected: FAIL if cancel always sets `cancelled` without interrupted distinction or if handle reuse prevents resumed start call.

- [ ] **Step 5: Count user messages on send**

In `sendMessage`, increment before appending the user event and persist through `touch`.

```js
conversation.userMessageCount = Number(conversation.userMessageCount || 0) + 1;
```

The count must not decrement when a later send fails; it represents historical user messages.

- [ ] **Step 6: Make cancel preserve conversation and clear only executor state**

Update `cancelConversation`.

```js
async cancelConversation(conversationId, device) {
  const conversation = this.requireConversation(conversationId, device);
  if (conversation.handle && typeof conversation.handle.cancel === 'function') {
    await conversation.handle.cancel();
  }
  conversation.handle = null;
  conversation.status = conversation.cliSessionId
    ? conversationStatuses.CANCELLED
    : conversationStatuses.INTERRUPTED;
  conversation.blockingItem = null;
  conversation.idleExpiresAt = null;
  this.touch(conversation);
  this.eventStore.append(conversation.id, conversationEventTypes.CONVERSATION_CANCELLED, {
    status: conversation.status,
    cliSessionId: conversation.cliSessionId || null,
    sessionBinding: conversation.sessionBinding || 'unknown'
  });
  this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, {
    status: conversation.status
  });
  this.auditLog.record('conversation.cancel', {
    conversationId: conversation.id,
    deviceId: device.id,
    status: conversation.status
  });
  return publicConversation(conversation);
}
```

- [ ] **Step 7: Ensure reusable statuses can start a new executor**

In `sendMessage`, only reject active blocking statuses.

```js
if (conversation.status === conversationStatuses.WAITING_INPUT) throw conflict('conversation is waiting for input response');
if (conversation.status === conversationStatuses.WAITING_APPROVAL) throw conflict('conversation is waiting for approval response');
```

Do not reject `cancelled`, `failed`, or `interrupted`.

- [ ] **Step 8: Ensure `ensureStarted` passes original resume id**

Keep this call shape.

```js
conversation.handle = await adapter.startConversation({
  conversationId: conversation.id,
  workspacePath: conversation.workspacePath,
  permissionMode: conversation.permissionMode,
  sessionId: conversation.cliSessionId,
  onEvent: (event) => this.recordAdapterEvent(conversation, event)
});
```

For `sessionBinding = drifted`, this must still pass `conversation.cliSessionId`, not a received drift id from any warning payload.

- [ ] **Step 9: Run daemon tests**

Run: `npm test`

Expected: pass.

- [ ] **Step 10: Commit cancel/resume behavior**

Run:

```bash
git add daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Keep conversations reusable after stop" -m "The stop action should terminate only the active executor, preserving the conversation identity, messages, and confirmed resume id for the next send.\n\nConstraint: A stop before any CLI session id is captured cannot honestly promise resume continuity.\nRejected: Clear conversation state on cancel | destroys replay and creates empty session rows.\nConfidence: high\nScope-risk: moderate\nTested: npm test"
```

---

### Task 5: Add Executor No-Progress Watchdog Semantics

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write watchdog progress reset tests**

Add tests near other manager executor tests.

```js
test('no-progress watchdog resets on repeated progress events', async () => {
  const clock = createManualClock('2026-05-08T00:00:00.000Z');
  const fixture = createConversationManagerFixture({ now: clock.now, noProgressTimeoutMs: 300000 });
  const { manager, device, adapter } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(created.id, { text: 'hello' }, device);
  clock.advance(240000);
  adapter.emit({ type: 'tool.output', toolUseId: 'tool_1', text: 'still working' });
  clock.advance(240000);
  manager.checkNoProgress();

  assert.equal(manager.getConversation(created.id, device).status, 'running');
});

test('no-progress watchdog pauses while waiting for user input', async () => {
  const clock = createManualClock('2026-05-08T00:00:00.000Z');
  const fixture = createConversationManagerFixture({ now: clock.now, noProgressTimeoutMs: 300000 });
  const { manager, device, adapter } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(created.id, { text: 'hello' }, device);
  adapter.emit({ type: 'assistant.question', questionId: 'q1', text: 'Need input?' });
  clock.advance(600000);
  manager.checkNoProgress();

  assert.equal(manager.getConversation(created.id, device).status, 'waiting_input');
});
```

- [ ] **Step 2: Write watchdog timeout test**

```js
test('no-progress watchdog kills executor and keeps conversation reusable', async () => {
  const clock = createManualClock('2026-05-08T00:00:00.000Z');
  const fixture = createConversationManagerFixture({ now: clock.now, noProgressTimeoutMs: 300000 });
  const { manager, device, adapter, eventStore } = fixture;
  const created = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(created.id, { text: 'hello' }, device);
  adapter.emit({ type: 'system.notice', sessionId: 'claude-session-1', text: 'started' });
  clock.advance(300001);
  manager.checkNoProgress();

  const summary = manager.getConversation(created.id, device);
  const events = eventStore.list(created.id, 0);
  assert.equal(summary.status, 'failed');
  assert.equal(summary.cliSessionId, 'claude-session-1');
  assert.equal(adapter.cancelCalls, 1);
  assert.equal(events.some((event) => event.type === 'run.error' && event.reason === 'no_progress_timeout'), true);
});
```

- [ ] **Step 3: Run daemon tests and verify watchdog missing**

Run: `npm test`

Expected: FAIL with missing `checkNoProgress`, clock helper, or no timeout state.

- [ ] **Step 4: Add watchdog constructor options and state fields**

Update the `ConversationManager` constructor signature.

```js
constructor({
  workspaces,
  eventStore,
  auditLog,
  adapters,
  persistentStore = null,
  idleTtlMs = 600000,
  noProgressTimeoutMs = 300000,
  now = () => new Date()
}) {
  this.noProgressTimeoutMs = noProgressTimeoutMs;
}
```

When a conversation sends a message or receives progress, set:

```js
conversation.lastProgressAt = this.now().toISOString();
```

- [ ] **Step 5: Reset watchdog on all progress events**

In `recordAdapterEvent`, reset progress for these event types.

```js
const progressEventTypes = new Set([
  conversationEventTypes.ASSISTANT_THINKING,
  conversationEventTypes.ASSISTANT_PARTIAL,
  conversationEventTypes.ASSISTANT_MESSAGE,
  conversationEventTypes.TOOL_STARTED,
  conversationEventTypes.TOOL_OUTPUT,
  conversationEventTypes.TOOL_COMPLETED,
  conversationEventTypes.SYSTEM_NOTICE,
  conversationEventTypes.DIFF_SUMMARY
]);
if (progressEventTypes.has(event.type)) {
  conversation.lastProgressAt = this.now().toISOString();
}
```

Repeated `tool.output` and repeated partial events count as progress even if text is identical.

- [ ] **Step 6: Implement watchdog check**

Add this method.

```js
checkNoProgress() {
  const nowMs = this.now().getTime();
  for (const conversation of this.conversations.values()) {
    if (!conversation.handle) continue;
    if (conversation.status === conversationStatuses.WAITING_INPUT ||
        conversation.status === conversationStatuses.WAITING_APPROVAL) {
      continue;
    }
    const lastProgressAt = conversation.lastProgressAt || conversation.updatedAt || conversation.createdAt;
    if (nowMs - new Date(lastProgressAt).getTime() <= this.noProgressTimeoutMs) continue;
    if (typeof conversation.handle.cancel === 'function') conversation.handle.cancel();
    conversation.handle = null;
    conversation.status = conversationStatuses.FAILED;
    conversation.blockingItem = null;
    conversation.idleExpiresAt = null;
    this.touch(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.RUN_ERROR, {
      reason: 'no_progress_timeout',
      message: 'Executor stopped after no progress for five minutes',
      recoverable: true
    });
    this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, {
      status: conversation.status
    });
  }
}
```

If production already has a timer loop, make it call `checkNoProgress()`; tests may call it directly.

- [ ] **Step 7: Run daemon tests**

Run: `npm test`

Expected: pass.

- [ ] **Step 8: Commit watchdog behavior**

Run:

```bash
git add daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Scope no-progress timeouts to executors" -m "The no-progress watchdog should stop stalled CLI executors without destroying their product conversation or trusted resume binding.\n\nConstraint: Waiting for user input or approval is not executor stalling.\nRejected: Timeout from run start only | long-running tools can produce periodic valid progress.\nConfidence: medium\nScope-risk: moderate\nTested: npm test"
```

---

### Task 6: Preserve Mobile Session List Identity

**Files:**
- Modify: `mobile/lib/src/features/sessions/session_list_view_model.dart`
- Modify: `mobile/lib/src/features/sessions/session_item.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write session list tests for reusable conversations**

Add this test near existing `debugMergeSessionIds` tests in `mobile/test/widget_test.dart`.

```dart
test('cancelled failed and interrupted conversations stay conversation backed in session list', () {
  const capabilities = ConversationCapabilities(resume: true, partialOutput: true);
  final conversations = <ConversationSummary>[
    _conversationSummary(
      id: 'conv_cancelled',
      workspaceId: 'workspace_1',
      status: 'cancelled',
      cliSessionId: 'claude-session-1',
      sessionBinding: 'confirmed',
      capabilities: capabilities,
    ),
    _conversationSummary(
      id: 'conv_failed',
      workspaceId: 'workspace_1',
      status: 'failed',
      cliSessionId: 'claude-session-2',
      sessionBinding: 'confirmed',
      capabilities: capabilities,
    ),
    _conversationSummary(
      id: 'conv_interrupted',
      workspaceId: 'workspace_1',
      status: 'interrupted',
      sessionBinding: 'unknown',
      userMessageCount: 1,
      capabilities: capabilities,
    ),
  ];

  final items = mergeSessionItems(const <SessionItem>[], conversations, const <RunSummary>[]);

  expect(items.map((item) => item.id), <String>['conv_cancelled', 'conv_failed', 'conv_interrupted']);
  expect(items.every((item) => item.conversation != null), isTrue);
});
```

- [ ] **Step 2: Write empty draft filtering test**

```dart
test('idle empty draft without messages remains hidden from session list', () {
  final items = mergeSessionItems(
    const <SessionItem>[],
    <ConversationSummary>[
      _conversationSummary(
        id: 'conv_empty',
        workspaceId: 'workspace_1',
        status: 'idle',
        sessionBinding: 'unknown',
        userMessageCount: 0,
      ),
    ],
    const <RunSummary>[],
  );

  expect(items, isEmpty);
});
```

- [ ] **Step 3: Run widget session list tests and verify failure**

Run: `cd mobile && flutter test test\widget_test.dart --plain-name "session list"`

Expected: FAIL if `ConversationSummary` helper lacks new fields or interrupted rows are hidden incorrectly.

- [ ] **Step 4: Update merge filtering**

In `mobile/lib/src/features/sessions/session_list_view_model.dart`, replace the `idle && cliSessionId == null` skip with this helper.

```dart
bool shouldShowConversationInSessionList(ConversationSummary conversation) {
  if (conversation.status == 'idle' &&
      conversation.cliSessionId == null &&
      conversation.userMessageCount == 0) {
    return false;
  }
  return true;
}
```

Use it in `mergeSessionItems`.

```dart
for (final conversation in snapshotConversations) {
  if (!shouldShowConversationInSessionList(conversation)) continue;
  if (seen.add(conversation.id)) {
    items.add(SessionItem(
      run: runSummaryFromConversation(conversation),
      conversation: conversation,
    ));
  }
}
```

- [ ] **Step 5: Update run status mapping**

In `runStatusFromConversation`, preserve reusable display statuses.

```dart
String runStatusFromConversation(String status) {
  if (status == 'idle') return 'completed';
  if (status == 'cancelled' || status == 'failed' || status == 'interrupted') {
    return status;
  }
  return 'running';
}
```

- [ ] **Step 6: Run widget tests**

Run: `cd mobile && flutter test test\widget_test.dart --plain-name "session list"`

Expected: pass.

- [ ] **Step 7: Commit session list identity changes**

Run:

```bash
git add mobile/lib/src/features/sessions/session_list_view_model.dart mobile/lib/src/features/sessions/session_item.dart mobile/test/widget_test.dart
git commit -m "Keep stopped conversations in the session list" -m "Stopped and interrupted conversations are still product conversations, so mobile must keep their conversation id and replay path instead of degrading them into run-only rows.\n\nConstraint: Empty idle drafts should still stay hidden.\nRejected: Query events per row on mobile | server now supplies userMessageCount.\nConfidence: high\nScope-risk: narrow\nTested: cd mobile && flutter test test\\widget_test.dart --plain-name \"session list\""
```

---

### Task 7: Preserve Workbench Messages And Active Conversation

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_controller.dart`
- Modify: `mobile/lib/src/state/conversation_reducer.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`
- Modify: `mobile/test/conversation_reducer_test.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write pure status helper tests**

Add to `mobile/test/coding_workbench_controller_test.dart`.

```dart
test('reusable conversation statuses can send another message', () {
  expect(canSendInConversationStatus('idle'), isTrue);
  expect(canSendInConversationStatus('cancelled'), isTrue);
  expect(canSendInConversationStatus('failed'), isTrue);
  expect(canSendInConversationStatus('interrupted'), isTrue);
  expect(canSendInConversationStatus('running'), isFalse);
  expect(canSendInConversationStatus('waiting_input'), isFalse);
  expect(canSendInConversationStatus('waiting_approval'), isFalse);
});
```

- [ ] **Step 2: Implement pure status helper**

Add to `mobile/lib/src/features/workbench/coding_workbench_controller.dart`.

```dart
bool canSendInConversationStatus(String? status) {
  return status == null ||
      status == 'idle' ||
      status == 'cancelled' ||
      status == 'failed' ||
      status == 'interrupted';
}

bool isActiveConversationStatus(String? status) {
  return status == 'running' ||
      status == 'waiting_input' ||
      status == 'waiting_approval';
}
```

- [ ] **Step 3: Write reducer test for cancel preserving messages**

Add to `mobile/test/conversation_reducer_test.dart`.

```dart
test('conversation cancelled status preserves existing messages', () {
  final state = reduceConversationEvents(
    const ConversationViewState(),
    <ConversationEvent>[
      ConversationEvent(
        type: 'user.message',
        seq: 1,
        conversationId: 'conv_1',
        createdAt: DateTime.parse('2026-05-08T00:00:00.000Z'),
        text: 'hello',
      ),
      ConversationEvent(
        type: 'assistant.partial',
        seq: 2,
        conversationId: 'conv_1',
        createdAt: DateTime.parse('2026-05-08T00:00:01.000Z'),
        text: 'working',
      ),
      ConversationEvent(
        type: 'conversation.cancelled',
        seq: 3,
        conversationId: 'conv_1',
        createdAt: DateTime.parse('2026-05-08T00:00:02.000Z'),
      ),
    ],
  );

  expect(state.messages.map((message) => message.role), containsAll(<String>['user', 'assistant']));
  expect(state.status, 'cancelled');
});
```

- [ ] **Step 4: Write widget tests for stop preserving active conversation**

Add to `mobile/test/widget_test.dart` using existing fake workbench/client helpers.

```dart
testWidgets('stopping active conversation keeps messages visible and active id', (tester) async {
  final client = FakeDaemonClient.withConversation(
    _conversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      status: 'running',
      cliSessionId: 'claude-session-1',
      sessionBinding: 'confirmed',
    ),
    events: <Map<String, Object?>>[
      {
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'user.message',
        'createdAt': '2026-05-08T00:00:00.000Z',
        'text': 'hello'
      },
      {
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'assistant.partial',
        'createdAt': '2026-05-08T00:00:01.000Z',
        'text': 'working'
      }
    ],
  );
  await pumpWorkbench(tester, client: client);

  await tester.tap(find.text('Stop'));
  await tester.pumpAndSettle();

  expect(find.textContaining('hello'), findsOneWidget);
  expect(find.textContaining('working'), findsOneWidget);
  expect(debugActiveConversationId(tester), 'conv_1');
});
```

If `debugActiveConversationId` does not exist, expose a `@visibleForTesting` getter on `CodingWorkbenchPageState`.

- [ ] **Step 5: Run focused mobile tests and verify failures**

Run:

```bash
cd mobile && flutter test test\coding_workbench_controller_test.dart
cd mobile && flutter test test\conversation_reducer_test.dart
cd mobile && flutter test test\widget_test.dart --plain-name "stopping active conversation"
```

Expected: FAIL before helpers/workbench changes are implemented.

- [ ] **Step 6: Use reusable helper in send eligibility**

In `CodingWorkbenchPageState`, replace broad `_isTerminal` or terminal checks that block sending after cancelled/failed/interrupted with `canSendInConversationStatus(_activeConversation?.status)`.

```dart
final canSend = canSendInConversationStatus(_activeConversation?.status) &&
    !_sending &&
    _selectedWorkspace.id.isNotEmpty;
```

Do not clear `_activeConversationId`, `_activeConversation`, `_messages`, or `_conversationEvents` when status becomes `cancelled`, `failed`, or `interrupted`.

- [ ] **Step 7: Update cancel status application**

In `_applyConversationStatusEvent`, preserve messages and set only status/blocking item.

```dart
} else if (event.type == 'conversation.cancelled') {
  status = event.raw['status'] as String? ?? 'cancelled';
  blockingItem = null;
} else if (event.type == 'run.error') {
  status = 'failed';
  blockingItem = null;
}
```

- [ ] **Step 8: Preserve draft text on send failure before persistence**

In `_sendPrompt`, capture prompt before clearing and restore on create/send failure.

```dart
final draft = _prompt.text;
try {
  _prompt.clear();
  // existing create/send flow
} catch (error) {
  if (_prompt.text.isEmpty) {
    _prompt.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }
  setState(() => _error = error.toString());
}
```

- [ ] **Step 9: Disable composer when daemon is disconnected**

Use the existing connection state or client availability flag. The final composer call should compute:

```dart
final daemonConnected = widget.data.daemon.connected;
final canSend = daemonConnected &&
    canSendInConversationStatus(_activeConversation?.status) &&
    !_sending &&
    _selectedWorkspace.id.isNotEmpty;
```

If `AppSnapshot` has a different connection field, use that field and document it in the test name.

- [ ] **Step 10: Show drift/interrupted recoverability warning**

When `_activeConversation?.sessionBinding == 'drifted'`, show a non-blocking inline status card.

```dart
if (_activeConversation?.sessionBinding == 'drifted')
  const WorkbenchInlineStatus(
    tone: WorkbenchStatusTone.warning,
    title: 'Session resume may have changed',
    message: 'Continuing will use the original CLI session id, but diagnostics include the drift warning.',
  );
```

When status is `interrupted`, show:

```dart
const WorkbenchInlineStatus(
  tone: WorkbenchStatusTone.warning,
  title: 'Interrupted',
  message: 'The CLI session binding was not confirmed. You can continue, but the next run may start fresh.',
);
```

- [ ] **Step 11: Run focused mobile tests**

Run:

```bash
cd mobile && flutter test test\coding_workbench_controller_test.dart
cd mobile && flutter test test\conversation_reducer_test.dart
cd mobile && flutter test test\widget_test.dart --plain-name "stopping active conversation"
```

Expected: pass.

- [ ] **Step 12: Commit workbench lifecycle changes**

Run:

```bash
git add mobile/lib/src/features/workbench/coding_workbench_page.dart mobile/lib/src/features/workbench/coding_workbench_controller.dart mobile/lib/src/state/conversation_reducer.dart mobile/test/coding_workbench_controller_test.dart mobile/test/conversation_reducer_test.dart mobile/test/widget_test.dart
git commit -m "Preserve mobile conversations after stop" -m "Mobile stop handling should reflect daemon semantics: executor state changes, but conversation identity, visible messages, replay events, and prompt recovery remain intact.\n\nConstraint: Reusable stopped states must allow follow-up sends.\nRejected: Clear active conversation on any non-running status | causes empty session rows and lost replay path.\nConfidence: medium\nScope-risk: moderate\nTested: cd mobile && flutter test test\\coding_workbench_controller_test.dart; cd mobile && flutter test test\\conversation_reducer_test.dart; cd mobile && flutter test test\\widget_test.dart --plain-name \"stopping active conversation\""
```

---

### Task 8: End-To-End Lifecycle Verification

**Files:**
- Modify: `scripts/run-tests.js`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add backend HTTP lifecycle regression test**

Add to `scripts/run-tests.js` near conversation HTTP API tests.

```js
test('conversation HTTP cancel preserves replay and allows follow-up send', async () => {
  const app = createTestAppWithConversationAdapter();
  const port = await listen(app.server);
  try {
    const paired = await pairDevice(port);
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId: 'default',
      adapter: 'claude'
    }, token);
    await request(port, 'POST', `/api/conversations/${created.body.id}/messages`, { text: 'first' }, token);
    app.adapter.emit({ type: 'system.notice', sessionId: 'claude-session-1', text: 'started' });
    const cancelled = await request(port, 'POST', `/api/conversations/${created.body.id}/cancel`, {}, token);
    assert.equal(cancelled.body.id, created.body.id);
    assert.equal(cancelled.body.cliSessionId, 'claude-session-1');
    await request(port, 'POST', `/api/conversations/${created.body.id}/messages`, { text: 'second' }, token);
    const events = await request(port, 'GET', `/api/conversations/${created.body.id}/events?afterSeq=0`, null, token);
    assert.equal(events.body.events.filter((event) => event.type === 'user.message').length, 2);
    assert.equal(app.adapter.startCalls.at(-1).sessionId, 'claude-session-1');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});
```

- [ ] **Step 2: Add mobile reopen replay test**

Add to `mobile/test/widget_test.dart`.

```dart
testWidgets('reopening cancelled conversation loads historical messages from events', (tester) async {
  final conversation = _conversationSummary(
    id: 'conv_cancelled',
    workspaceId: 'workspace_1',
    status: 'cancelled',
    cliSessionId: 'claude-session-1',
    sessionBinding: 'confirmed',
    userMessageCount: 1,
  );
  final client = FakeDaemonClient.withConversation(conversation, events: <Map<String, Object?>>[
    {
      'seq': 1,
      'conversationId': 'conv_cancelled',
      'type': 'user.message',
      'createdAt': '2026-05-08T00:00:00.000Z',
      'text': 'first prompt'
    },
    {
      'seq': 2,
      'conversationId': 'conv_cancelled',
      'type': 'assistant.message',
      'createdAt': '2026-05-08T00:00:01.000Z',
      'text': 'partial answer before stop'
    }
  ]);

  await pumpSessionList(tester, client: client, conversations: <ConversationSummary>[conversation]);
  await tester.tap(find.textContaining('Claude'));
  await tester.pumpAndSettle();

  expect(find.textContaining('first prompt'), findsOneWidget);
  expect(find.textContaining('partial answer before stop'), findsOneWidget);
});
```

- [ ] **Step 3: Run end-to-end focused tests**

Run:

```bash
npm test
cd mobile && flutter test test\widget_test.dart --plain-name "reopening cancelled conversation"
```

Expected: pass.

- [ ] **Step 4: Run full project verification**

Run:

```bash
npm run lint
npm test
cd mobile && flutter analyze --no-pub
cd mobile && flutter test test\protocol_compatibility_test.dart test\conversation_reducer_test.dart test\coding_workbench_controller_test.dart
cd mobile && flutter test test\widget_test.dart --plain-name "session list"
cd mobile && flutter test test\widget_test.dart --plain-name "coding composer"
cd mobile && flutter build windows --debug
```

Expected: all commands pass. If `flutter analyze` without `--no-pub` is required by CI, run it after dependencies are reachable.

- [ ] **Step 5: Manual mobile smoke test**

Run the daemon and mobile app, then verify these exact behaviors:

- Start a conversation and wait until a CLI session id is captured.
- Tap stop while assistant output is visible.
- Confirm messages remain visible and the session list row remains the same conversation.
- Send another message in the same conversation and verify daemon logs show resume with the original `cliSessionId`.
- Start a conversation and stop before any session id appears; verify UI shows interrupted warning and follow-up send remains possible.
- Restart mobile; reopen the stopped conversation; verify historical messages replay from events.

- [ ] **Step 6: Commit end-to-end tests**

Run:

```bash
git add scripts/run-tests.js mobile/test/widget_test.dart
git commit -m "Cover conversation stop lifecycle end to end" -m "The lifecycle regression needs backend and mobile coverage proving stopped conversations keep replayable history and can continue with the original resume binding.\n\nConstraint: The bug appears only after cancel followed by another send and stop.\nRejected: Unit-only coverage | would miss session-list and replay regressions.\nConfidence: high\nScope-risk: narrow\nTested: npm run lint; npm test; cd mobile && flutter analyze --no-pub; focused Flutter tests; cd mobile && flutter build windows --debug"
```

---

## Self-Review

- Spec coverage: Tasks cover stable `conversationId <-> cliSessionId`, `sessionBinding` values, atomic binding persistence, drift warnings, resume with original id, cancellation preserving conversation/messages/id, interrupted before binding, no-progress watchdog semantics, mobile reusable statuses, session list identity, legacy row normalization, draft restoration, daemon disconnect send disable, and replay after restart.
- Wording scan: No unresolved fill-in wording remains. Helper names such as `createConversationManagerFixture`, `FakeDaemonClient`, and `pumpWorkbench` refer to existing test harness concepts and must be adapted to the exact local helper names during implementation.
- Type consistency: `sessionBinding`, `userMessageCount`, `conversationSessionBindings`, `canSendInConversationStatus`, and `isActiveConversationStatus` are used consistently across daemon/mobile tasks.
- Scope check: The spec spans daemon lifecycle, persistence, and mobile UI. The plan keeps these in one sequence because each phase produces working behavior and later mobile tasks depend on backend summary fields.
