# Conversation First CLI Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class conversation architecture so new coding conversations are isolated, Claude runs as a long-lived interactive CLI session, and input/approval waits are normalized daemon states.

**Architecture:** Add daemon `ConversationManager` plus `/api/conversations` while preserving `/api/runs`. Implement Claude as the full long-lived adapter first; Codex/OpenCode expose capabilities and can fall back. Add Flutter `ConversationClient` and `ConversationEventReducer`, then switch the coding workbench to normalized conversation events.

**Tech Stack:** Node.js daemon with built-in `http`/`child_process`; Flutter/Dart mobile client with current `http`, `flutter_test`; no new dependencies.

---

## File Structure

- Create `daemon/src/conversation-protocol.js`: statuses, normalized event type constants, payload validators.
- Create `daemon/src/conversation-event-store.js`: ordered per-conversation event replay.
- Create `daemon/src/conversation-manager.js`: session lifecycle, one blocking item, idle TTL, adapter handle ownership.
- Create `daemon/src/claude-conversation-adapter.js`: long-lived Claude stream-json adapter.
- Modify `daemon/src/main.js`: instantiate conversation manager/store/adapters.
- Modify `daemon/src/server.js`: add `/api/conversations` routes.
- Modify `scripts/run-tests.js`: daemon protocol, manager, API, adapter tests.
- Modify `mobile/lib/src/models/protocol.dart`: conversation models/events.
- Create `mobile/lib/src/services/conversation_client.dart`: HTTP wrapper.
- Create `mobile/lib/src/state/conversation_reducer.dart`: pure normalized event reducer.
- Modify `mobile/lib/lan_ai_cli_control.dart`: export new client/reducer.
- Modify `mobile/lib/main.dart`: coding workbench uses conversation API/reducer; avoid broad UI splitting.
- Add `mobile/test/conversation_reducer_test.dart`; update existing Flutter tests.

---

## Task 1: Define Backend Conversation Protocol

**Files:**
- Create: `daemon/src/conversation-protocol.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing protocol tests**

Add to `scripts/run-tests.js`:

```js
test('conversation protocol validates statuses and blocking payloads', () => {
  const {
    conversationStatuses,
    conversationEventTypes,
    normalizeConversationCreate,
    normalizeMessagePayload,
    normalizeQuestionResponse,
    normalizeApprovalDecision
  } = require('../daemon/src/conversation-protocol');

  assert.equal(conversationStatuses.IDLE, 'idle');
  assert.equal(conversationStatuses.WAITING_INPUT, 'waiting_input');
  assert.equal(conversationStatuses.WAITING_APPROVAL, 'waiting_approval');
  assert.equal(conversationEventTypes.ASSISTANT_MESSAGE, 'assistant.message');
  assert.equal(conversationEventTypes.APPROVAL_REQUESTED, 'approval.requested');

  assert.deepEqual(normalizeConversationCreate({ workspaceId: 'default', adapter: 'claude', permissionMode: 'default' }), {
    workspaceId: 'default', adapter: 'claude', permissionMode: 'default'
  });
  assert.equal(normalizeMessagePayload({ text: ' hello ' }).text, 'hello');
  assert.equal(normalizeQuestionResponse({ questionId: 'q1', text: ' answer ' }).text, 'answer');
  assert.equal(normalizeApprovalDecision({ decision: 'allow' }).decision, 'allow');
  assert.throws(() => normalizeConversationCreate({ workspaceId: '', adapter: 'claude' }), /workspaceId is required/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: 'default', adapter: 'unknown' }), /unsupported adapter/);
  assert.throws(() => normalizeMessagePayload({ text: '' }), /text is required/);
  assert.throws(() => normalizeQuestionResponse({ questionId: 'q1', text: '' }), /text is required/);
  assert.throws(() => normalizeApprovalDecision({ decision: 'maybe' }), /decision must be allow or deny/);
});
```

- [ ] **Step 2: Run and confirm failure**

Run: `npm test`
Expected: fails with missing `conversation-protocol` module.

- [ ] **Step 3: Implement protocol module**

Create `daemon/src/conversation-protocol.js` with:

```js
'use strict';

const supportedConversationAdapters = Object.freeze(['claude', 'codex', 'opencode']);
const conversationStatuses = Object.freeze({
  IDLE: 'idle', RUNNING: 'running', WAITING_INPUT: 'waiting_input', WAITING_APPROVAL: 'waiting_approval',
  COMPLETED: 'completed', FAILED: 'failed', CANCELLED: 'cancelled', EXPIRED: 'expired'
});
const conversationEventTypes = Object.freeze({
  CONVERSATION_STARTED: 'conversation.started', STATUS_CHANGED: 'conversation.status_changed',
  USER_MESSAGE: 'user.message', ASSISTANT_PARTIAL: 'assistant.partial', ASSISTANT_MESSAGE: 'assistant.message',
  ASSISTANT_QUESTION: 'assistant.question', APPROVAL_REQUESTED: 'approval.requested', APPROVAL_RESOLVED: 'approval.resolved',
  TOOL_STARTED: 'tool.started', TOOL_OUTPUT: 'tool.output', TOOL_COMPLETED: 'tool.completed', DIFF_SUMMARY: 'diff.summary',
  RUN_ERROR: 'run.error', CONVERSATION_COMPLETED: 'conversation.completed', CONVERSATION_CANCELLED: 'conversation.cancelled',
  PROTOCOL_WARNING: 'protocol.warning'
});
function normalizeConversationCreate(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const workspaceId = str(payload.workspaceId).trim();
  if (!workspaceId) throw badRequest('workspaceId is required');
  const adapter = str(payload.adapter || payload.tool || 'claude').trim();
  if (!supportedConversationAdapters.includes(adapter)) throw badRequest(`unsupported adapter: ${adapter}`);
  return { workspaceId, adapter, permissionMode: normalizePermissionMode(payload.permissionMode) };
}
function normalizeMessagePayload(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const text = str(payload.text || payload.prompt).trim();
  if (!text) throw badRequest('text is required');
  return { text };
}
function normalizeQuestionResponse(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const questionId = str(payload.questionId).trim();
  const text = str(payload.text).trim();
  if (!questionId) throw badRequest('questionId is required');
  if (!text) throw badRequest('text is required');
  return { questionId, text };
}
function normalizeApprovalDecision(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const decision = str(payload.decision).trim();
  if (!['allow', 'deny'].includes(decision)) throw badRequest('decision must be allow or deny');
  return { decision };
}
function normalizePermissionMode(value) {
  if (value == null || value === '') return 'default';
  if (!['default', 'auto'].includes(value)) throw badRequest('permissionMode must be default or auto');
  return value;
}
function str(value) { return typeof value === 'string' ? value : ''; }
function badRequest(message) { const error = new Error(message); error.status = 400; error.code = 'BAD_REQUEST'; return error; }
module.exports = { supportedConversationAdapters, conversationStatuses, conversationEventTypes, normalizeConversationCreate, normalizeMessagePayload, normalizeQuestionResponse, normalizeApprovalDecision };
```

- [ ] **Step 4: Run and confirm pass**

Run: `npm test`
Expected: protocol test passes.

---

## Task 2: Add Conversation Event Store

**Files:**
- Create: `daemon/src/conversation-event-store.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing event store test**

```js
test('conversation event store appends and replays ordered events', () => {
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const { conversationEventTypes } = require('../daemon/src/conversation-protocol');
  const store = new ConversationEventStore();
  const first = store.append('conv_1', conversationEventTypes.USER_MESSAGE, { text: 'hello' });
  const second = store.append('conv_1', conversationEventTypes.ASSISTANT_MESSAGE, { text: 'hi' });
  store.append('conv_2', conversationEventTypes.USER_MESSAGE, { text: 'other' });
  assert.equal(first.seq, 1);
  assert.equal(second.seq, 2);
  assert.deepEqual(store.list('conv_1', 0).map((event) => event.seq), [1, 2]);
  assert.deepEqual(store.list('conv_1', 1).map((event) => event.seq), [2]);
  assert.equal(store.list('missing', 0).length, 0);
});
```

- [ ] **Step 2: Run and confirm failure**

Run: `npm test`
Expected: missing module failure.

- [ ] **Step 3: Implement store**

Create `daemon/src/conversation-event-store.js`:

```js
'use strict';
class ConversationEventStore {
  constructor({ now = () => new Date() } = {}) { this.now = now; this.events = new Map(); }
  append(conversationId, type, payload = {}) {
    if (!conversationId) throw new Error('conversationId is required');
    if (!type) throw new Error('event type is required');
    const list = this.events.get(conversationId) || [];
    const event = { seq: list.length + 1, conversationId, type, createdAt: this.now().toISOString(), ...payload };
    list.push(event);
    this.events.set(conversationId, list);
    return event;
  }
  list(conversationId, afterSeq = 0) {
    const seq = Number(afterSeq || 0);
    return (this.events.get(conversationId) || []).filter((event) => event.seq > seq);
  }
}
module.exports = { ConversationEventStore };
```

- [ ] **Step 4: Run and confirm pass**

Run: `npm test`
Expected: event store test passes.

---
## Task 3: Implement Conversation Manager State Machine

**Files:**
- Create: `daemon/src/conversation-manager.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing manager test**

```js
test('conversation manager handles input and approval blocking states', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const fakeHandle = {
    sent: [], approvals: [],
    sendUserMessage(text) { this.sent.push(text); },
    answerQuestion(_questionId, text) { this.sent.push(text); },
    respondApproval(approvalId, decision) { this.approvals.push({ approvalId, decision }); },
    cancel() {}, dispose() {}
  };
  const adapter = {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true },
    async startConversation({ onEvent }) { adapter.onEvent = onEvent; return fakeHandle; }
  };
  const manager = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore(),
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    idleTtlMs: 600000
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  assert.equal(conversation.status, 'idle');
  assert.equal(conversation.cliSessionId, null);
  await manager.sendMessage(conversation.id, { text: 'hello' }, device);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.deepEqual(fakeHandle.sent, ['hello']);
  adapter.onEvent({ type: 'assistant.question', questionId: 'q1', text: 'Pick direction', suggestions: ['A'] });
  assert.equal(manager.getConversation(conversation.id, device).status, 'waiting_input');
  assert.throws(() => manager.sendMessage(conversation.id, { text: 'wrong path' }, device), /waiting for input response/);
  assert.throws(() => manager.answerQuestion(conversation.id, { questionId: 'bad', text: 'A' }, device), /questionId does not match/);
  await manager.answerQuestion(conversation.id, { questionId: 'q1', text: 'A' }, device);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.deepEqual(fakeHandle.sent, ['hello', 'A']);
  adapter.onEvent({ type: 'approval.requested', approvalId: 'ap1', toolName: 'Bash', input: { command: 'dir' }, summary: 'List files' });
  assert.equal(manager.getConversation(conversation.id, device).status, 'waiting_approval');
  assert.throws(() => manager.respondApproval(conversation.id, 'bad', { decision: 'allow' }, device), /approvalId does not match/);
  await manager.respondApproval(conversation.id, 'ap1', { decision: 'allow' }, device);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.deepEqual(fakeHandle.approvals, [{ approvalId: 'ap1', decision: 'allow' }]);
});
```

- [ ] **Step 2: Run and confirm failure**

Run: `npm test`
Expected: missing manager module.

- [ ] **Step 3: Implement manager**

Create `daemon/src/conversation-manager.js` with these exported methods:

```js
class ConversationManager {
  createConversation(payload, device) {}
  listConversations(device) {}
  getConversation(conversationId, device) {}
  async sendMessage(conversationId, payload, device) {}
  async answerQuestion(conversationId, payload, device) {}
  async respondApproval(conversationId, approvalId, payload, device) {}
  async cancelConversation(conversationId, device) {}
  listEvents(conversationId, afterSeq, device) {}
  recordAdapterEvent(conversation, event) {}
}
module.exports = { ConversationManager };
```

Implementation requirements:

- Use `crypto.randomUUID()` and ids prefixed with `conv_`.
- Use `normalizeConversationCreate`, `normalizeMessagePayload`, `normalizeQuestionResponse`, `normalizeApprovalDecision` from `conversation-protocol.js`.
- `publicConversation()` returns `id`, `workspaceId`, `adapter`, `status`, `cliSessionId`, `blockingItem`, `idleExpiresAt`, `createdAt`, `updatedAt`, `capabilities`.
- `sendMessage()` rejects `waiting_input` with `409 conversation is waiting for input response`.
- `sendMessage()` rejects `waiting_approval` with `409 conversation is waiting for approval response`.
- `recordAdapterEvent()` maps `assistant.question` to one `input_request` blocking item and `waiting_input`.
- `recordAdapterEvent()` maps `approval.requested` to one `approval_request` blocking item and `waiting_approval`.
- `recordAdapterEvent()` maps `assistant.message` to event store and status `idle` with `idleExpiresAt = now + idleTtlMs`.
- If a second blocking request arrives, append `protocol.warning` and keep the existing blocking item.

- [ ] **Step 4: Run and confirm pass**

Run: `npm test`
Expected: manager test passes.

---

## Task 4: Add Conversation API Routes

**Files:**
- Modify: `daemon/src/main.js`
- Modify: `daemon/src/server.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing HTTP API test**

```js
test('conversation HTTP API creates, sends, and replays events', async () => {
  const app = createApp({ port: 0 });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'conversation-test' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId: 'default', adapter: 'claude' }, token);
    assert.equal(created.status, 201);
    assert.equal(created.body.conversation.status, 'idle');
    assert.equal(created.body.conversation.cliSessionId, null);
    const listed = await request(port, 'GET', '/api/conversations', null, token);
    assert.equal(listed.body.conversations.some((conversation) => conversation.id === created.body.conversation.id), true);
    const sent = await request(port, 'POST', `/api/conversations/${created.body.conversation.id}/messages`, { text: 'hello' }, token);
    assert.equal(sent.status, 200);
    const events = await request(port, 'GET', `/api/conversations/${created.body.conversation.id}/events?afterSeq=0`, null, token);
    assert.equal(events.body.events.some((event) => event.type === 'user.message'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});
```

- [ ] **Step 2: Run and confirm failure**

Run: `npm test`
Expected: `/api/conversations` not found or `conversations` undefined.

- [ ] **Step 3: Wire app root**

Modify `daemon/src/main.js`:

```js
const { ConversationEventStore } = require('./conversation-event-store');
const { ConversationManager } = require('./conversation-manager');
```

Create `conversationEventStore` and `conversations`. Initially use a deterministic synthetic conversation adapter so API tests do not depend on Claude:

```js
const conversationEventStore = new ConversationEventStore();
const conversationAdapters = new Map([
  ['claude', {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true },
    async startConversation({ onEvent }) {
      return {
        async sendUserMessage(text) { onEvent({ type: 'assistant.message', text: `synthetic conversation response: ${text}` }); },
        async answerQuestion(_questionId, text) { onEvent({ type: 'assistant.message', text: `synthetic question response: ${text}` }); },
        async respondApproval() {}, async cancel() {}, async dispose() {}
      };
    }
  }]
]);
const conversations = new ConversationManager({ workspaces, eventStore: conversationEventStore, auditLog, adapters: conversationAdapters, idleTtlMs: Number(process.env.CONVERSATION_IDLE_TTL_MS || 600000) });
```

Pass `conversations` to `createServer()` and return it from `createApp()`.

- [ ] **Step 4: Add routes**

Modify `daemon/src/server.js` to accept `conversations`. Add routes before `/api/runs`:

```js
if (method === 'POST' && url.pathname === '/api/conversations') return json(res, 201, { conversation: conversations.createConversation(await readJson(req), requireAuth(req)) });
if (method === 'GET' && url.pathname === '/api/conversations') return json(res, 200, { conversations: conversations.listConversations(requireAuth(req)) });
const conversationEvents = url.pathname.match(/^\/api\/conversations\/([^/]+)\/events$/);
if (method === 'GET' && conversationEvents) return json(res, 200, { events: conversations.listEvents(conversationEvents[1], Number(url.searchParams.get('afterSeq') || 0), requireAuth(req)) });
const conversationMessages = url.pathname.match(/^\/api\/conversations\/([^/]+)\/messages$/);
if (method === 'POST' && conversationMessages) return json(res, 200, { conversation: await conversations.sendMessage(conversationMessages[1], await readJson(req), requireAuth(req)) });
const conversationInput = url.pathname.match(/^\/api\/conversations\/([^/]+)\/input-response$/);
if (method === 'POST' && conversationInput) return json(res, 200, { conversation: await conversations.answerQuestion(conversationInput[1], await readJson(req), requireAuth(req)) });
const conversationApproval = url.pathname.match(/^\/api\/conversations\/([^/]+)\/approvals\/([^/]+)\/respond$/);
if (method === 'POST' && conversationApproval) return json(res, 200, { conversation: await conversations.respondApproval(conversationApproval[1], conversationApproval[2], await readJson(req), requireAuth(req)) });
const conversationCancel = url.pathname.match(/^\/api\/conversations\/([^/]+)\/cancel$/);
if (method === 'POST' && conversationCancel) return json(res, 200, { conversation: await conversations.cancelConversation(conversationCancel[1], requireAuth(req)) });
const conversationDetail = url.pathname.match(/^\/api\/conversations\/([^/]+)$/);
if (method === 'GET' && conversationDetail) return json(res, 200, { conversation: conversations.getConversation(conversationDetail[1], requireAuth(req)) });
```

- [ ] **Step 5: Run and confirm pass**

Run: `npm test`
Expected: API test passes and existing `/api/runs` tests still pass.

---

## Task 5: Implement Claude Conversation Adapter

**Files:**
- Create: `daemon/src/claude-conversation-adapter.js`
- Modify: `daemon/src/main.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing simulated adapter tests**

Add tests for:

```js
const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
```

Test 1 expectations:
- `startConversation()` spawns Claude with `--output-format stream-json`, `--input-format stream-json`, `--permission-prompt-tool stdio` in default mode.
- `sendUserMessage('hello')` writes a JSON line with `type: 'user'` and content `hello`.
- Simulated `AskUserQuestion` control request emits `assistant.question`.
- `answerQuestion(questionId, 'A')` writes another `type: 'user'` JSON line containing `A` and does not close stdin.

Test 2 expectations:
- Simulated Bash `can_use_tool` emits `approval.requested`.
- `respondApproval(approvalId, 'allow')` writes a `control_response` with `behavior: 'allow'`.

- [ ] **Step 2: Run and confirm failure**

Run: `npm test`
Expected: missing `claude-conversation-adapter`.

- [ ] **Step 3: Implement adapter**

Create `daemon/src/claude-conversation-adapter.js` with:

```js
class ClaudeConversationAdapter {
  constructor({ command = 'claude', spawnFn = spawn, spawnSyncFn = spawnSync } = {}) {}
  async startConversation({ conversationId, workspacePath, permissionMode = 'default', sessionId, onEvent }) {}
}
module.exports = { ClaudeConversationAdapter };
```

Implementation requirements:

- Spawn args include stream-json output, verbose, print, empty system prompt, include partial messages, input-format stream-json.
- If `sessionId` is provided, add `--resume <sessionId>`.
- In `default` mode add `--permission-prompt-tool stdio --permission-mode default`.
- Keep stdin open.
- Parse stdout JSONL.
- `result` with text emits `assistant.message` with `sessionId`.
- `assistant` content emits `assistant.partial`.
- `control_request` with `tool_name: AskUserQuestion` emits `assistant.question` and stores request id.
- `answerQuestion()` writes a new `user` message to stdin; if Claude requires ack, also write minimal successful `control_response` for the pending request.
- Other `can_use_tool` requests emit `approval.requested` and store request id.
- `respondApproval()` writes provider `control_response` allow/deny.
- `cancel()` and `dispose()` kill the child process.

- [ ] **Step 4: Replace synthetic adapter in `main.js`**

Use:

```js
const { ClaudeConversationAdapter } = require('./claude-conversation-adapter');
const conversationAdapters = new Map([
  ['claude', new ClaudeConversationAdapter({ command: claudeCommand })],
  ['codex', { capabilities: { longLivedProcess: false, waitingInput: false, waitingApproval: false, resume: false, partialOutput: true }, async startConversation() { throw Object.assign(new Error('Codex conversation adapter is not implemented yet'), { status: 501 }); } }],
  ['opencode', { capabilities: { longLivedProcess: false, waitingInput: false, waitingApproval: false, resume: false, partialOutput: true }, async startConversation() { throw Object.assign(new Error('OpenCode conversation adapter is not implemented yet'), { status: 501 }); } }]
]);
```

If this breaks deterministic API tests, inject fake adapters into `createApp({ conversationAdapters })` for tests.

- [ ] **Step 5: Run and confirm pass**

Run: `npm test`
Expected: all daemon tests pass.

---
## Task 6: Add Flutter Conversation Models and Client

**Files:**
- Modify: `mobile/lib/src/models/protocol.dart`
- Create: `mobile/lib/src/services/conversation_client.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`
- Test: `mobile/test/protocol_compatibility_test.dart`

- [ ] **Step 1: Write failing model tests**

Add to `mobile/test/protocol_compatibility_test.dart`:

```dart
test('Conversation models parse daemon conversation payloads', () {
  final summary = ConversationSummary.fromJson(const <String, Object?>{
    'id': 'conv_1', 'workspaceId': 'default', 'adapter': 'claude', 'status': 'waiting_input', 'cliSessionId': 'session_1',
    'capabilities': {'waitingInput': true, 'waitingApproval': true},
    'blockingItem': {'type': 'input_request', 'questionId': 'q1', 'text': 'Pick one', 'suggestions': ['A', 'B']}
  });
  expect(summary.id, 'conv_1');
  expect(summary.status, 'waiting_input');
  expect(summary.blockingItem?.type, 'input_request');
  expect(summary.blockingItem?.suggestions, const <String>['A', 'B']);
  expect(summary.capabilities.waitingInput, true);
});

test('ConversationEvent parses normalized assistant and approval events', () {
  final question = ConversationEvent.fromJson(const <String, Object?>{
    'seq': 1, 'conversationId': 'conv_1', 'type': 'assistant.question', 'createdAt': '2026-05-03T00:00:00.000Z',
    'questionId': 'q1', 'text': 'Pick one', 'suggestions': ['A']
  });
  final approval = ConversationEvent.fromJson(const <String, Object?>{
    'seq': 2, 'conversationId': 'conv_1', 'type': 'approval.requested', 'createdAt': '2026-05-03T00:00:01.000Z',
    'approvalId': 'ap1', 'toolName': 'Bash', 'summary': 'dir scripts', 'input': {'command': 'dir scripts'}
  });
  expect(question.questionId, 'q1');
  expect(question.suggestions, const <String>['A']);
  expect(approval.approvalId, 'ap1');
  expect(approval.summary, 'dir scripts');
});
```

- [ ] **Step 2: Run and confirm failure**

Run from `mobile/`: `flutter test test/protocol_compatibility_test.dart`
Expected: undefined conversation model classes.

- [ ] **Step 3: Add models**

Add `ConversationCapabilities`, `BlockingItemSummary`, `ConversationSummary`, and `ConversationEvent` to `mobile/lib/src/models/protocol.dart`.

Required fields:

```dart
ConversationCapabilities: longLivedProcess, waitingInput, waitingApproval, resume, partialOutput
BlockingItemSummary: type, questionId, approvalId, toolName, text, summary, suggestions, input
ConversationSummary: id, workspaceId, adapter, status, cliSessionId, capabilities, blockingItem
ConversationEvent: seq, conversationId, type, createdAt, text, questionId, approvalId, toolUseId, toolName, summary, status, suggestions, input, raw
```

Each class needs a `fromJson(Map<String, Object?> json)` factory matching the test payloads.

- [ ] **Step 4: Add public HTTP helpers to `DaemonClient`**

In `mobile/lib/src/services/daemon_client.dart`, add:

```dart
Future<Map<String, Object?>> getJson(String path) => _get(path);
Future<Map<String, Object?>> postJson(String path, Map<String, Object?> body) => _post(path, body);
```

- [ ] **Step 5: Create `ConversationClient`**

Create `mobile/lib/src/services/conversation_client.dart` with methods:

```dart
Future<ConversationSummary> createConversation({required String workspaceId, required String adapter, required String permissionMode})
Future<List<ConversationSummary>> listConversations()
Future<ConversationSummary> sendMessage(String conversationId, String text)
Future<ConversationSummary> answerQuestion(String conversationId, String questionId, String text)
Future<ConversationSummary> respondApproval(String conversationId, String approvalId, String decision)
Future<ConversationSummary> cancelConversation(String conversationId)
Future<List<ConversationEvent>> fetchEvents(String conversationId, {required int afterSeq})
```

Use `DaemonClient.getJson/postJson` and parse response envelopes: `conversation`, `conversations`, `events`.

- [ ] **Step 6: Export client**

Modify `mobile/lib/lan_ai_cli_control.dart`:

```dart
export 'src/services/conversation_client.dart';
```

- [ ] **Step 7: Run and confirm pass**

Run from `mobile/`: `flutter test test/protocol_compatibility_test.dart`
Expected: PASS.

---

## Task 7: Add Frontend Conversation Reducer

**Files:**
- Create: `mobile/lib/src/state/conversation_reducer.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`
- Test: `mobile/test/conversation_reducer_test.dart`

- [ ] **Step 1: Write failing reducer tests**

Create `mobile/test/conversation_reducer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/lan_ai_cli_control.dart';

void main() {
  test('conversation reducer handles question and final message', () {
    var state = const ConversationUiState(conversationId: 'conv_1');
    state = reduceConversationEvent(state, ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1, 'conversationId': 'conv_1', 'type': 'user.message', 'createdAt': '2026-05-03T00:00:00.000Z', 'text': '写脚本'
    }));
    state = reduceConversationEvent(state, ConversationEvent.fromJson(const <String, Object?>{
      'seq': 2, 'conversationId': 'conv_1', 'type': 'assistant.question', 'createdAt': '2026-05-03T00:00:01.000Z',
      'questionId': 'q1', 'text': '什么方向？', 'suggestions': ['自动化']
    }));
    expect(state.status, 'waiting_input');
    expect(state.activeQuestion?.questionId, 'q1');
    expect(state.messages.map((m) => m.role), contains('question'));
    state = reduceConversationEvent(state, ConversationEvent.fromJson(const <String, Object?>{
      'seq': 3, 'conversationId': 'conv_1', 'type': 'assistant.message', 'createdAt': '2026-05-03T00:00:02.000Z', 'text': '完整回答'
    }));
    expect(state.status, 'idle');
    expect(state.activeQuestion, isNull);
    expect(state.messages.where((m) => m.role == 'question'), isEmpty);
    expect(state.messages.last.body, '完整回答');
  });

  test('conversation reducer keeps one active approval', () {
    var state = const ConversationUiState(conversationId: 'conv_1');
    state = reduceConversationEvent(state, ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1, 'conversationId': 'conv_1', 'type': 'approval.requested', 'createdAt': '2026-05-03T00:00:00.000Z',
      'approvalId': 'ap1', 'toolName': 'Bash', 'summary': 'dir scripts'
    }));
    expect(state.status, 'waiting_approval');
    expect(state.activeApproval?.approvalId, 'ap1');
    state = reduceConversationEvent(state, ConversationEvent.fromJson(const <String, Object?>{
      'seq': 2, 'conversationId': 'conv_1', 'type': 'approval.resolved', 'createdAt': '2026-05-03T00:00:01.000Z',
      'approvalId': 'ap1', 'decision': 'allow'
    }));
    expect(state.activeApproval, isNull);
    expect(state.status, 'running');
  });
}
```

- [ ] **Step 2: Run and confirm failure**

Run from `mobile/`: `flutter test test/conversation_reducer_test.dart`
Expected: undefined reducer classes.

- [ ] **Step 3: Implement reducer**

Create `mobile/lib/src/state/conversation_reducer.dart` with:

```dart
class ConversationUiMessage { final String role; final String body; final ConversationEvent? event; }
class ConversationUiState { conversationId, status, messages, activeQuestion, activeApproval, lastSeq, error }
ConversationUiState reduceConversationEvent(ConversationUiState state, ConversationEvent event, {bool streamOutput = false})
```

Reducer behavior:

- `user.message`: append user message, status `running`.
- `assistant.partial`: if `streamOutput`, replace one `assistant_partial` message.
- `assistant.message`: remove `assistant_partial` and `question`, append final assistant message, clear blocking state, status `idle`.
- `assistant.question`: replace existing question, set `activeQuestion`, status `waiting_input`.
- `approval.requested`: set `activeApproval`, status `waiting_approval`.
- `approval.resolved`: clear `activeApproval`, status `running`.
- `conversation.cancelled`: status `cancelled`, clear blocking state.
- `run.error`: status `failed`, set error.

- [ ] **Step 4: Export reducer**

Modify `mobile/lib/lan_ai_cli_control.dart`:

```dart
export 'src/state/conversation_reducer.dart';
```

- [ ] **Step 5: Run and confirm pass**

Run from `mobile/`: `flutter test test/conversation_reducer_test.dart`
Expected: PASS.

---

## Task 8: Switch Coding Workbench to Conversation API

**Files:**
- Modify: `mobile/lib/main.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add regression test for reducer-driven waiting mode**

Add to `mobile/test/widget_test.dart`:

```dart
test('conversation state enters answer mode for assistant question', () {
  var state = const ConversationUiState(conversationId: 'conv_1');
  state = reduceConversationEvent(state, ConversationEvent.fromJson(const <String, Object?>{
    'seq': 1, 'conversationId': 'conv_1', 'type': 'assistant.question', 'createdAt': '2026-05-03T00:00:00.000Z',
    'questionId': 'q1', 'text': '请选择方向', 'suggestions': ['自动化']
  }));
  expect(state.status, 'waiting_input');
  expect(state.activeQuestion?.questionId, 'q1');
});
```

- [ ] **Step 2: Run test baseline**

Run from `mobile/`: `flutter test test/widget_test.dart`
Expected: PASS before UI wiring.

- [ ] **Step 3: Add conversation state fields**

In `_CodingWorkbenchPageState` in `mobile/lib/main.dart`, add:

```dart
late final ConversationClient _conversationClient;
ConversationSummary? _activeConversation;
ConversationUiState? _conversationState;
```

Initialize in `initState()`:

```dart
_conversationClient = ConversationClient(widget.client);
```

- [ ] **Step 4: Add reset helper**

Add:

```dart
void _resetConversationState() {
  _activeConversation = null;
  _conversationState = null;
  _messages.clear();
  _events.clear();
  _resolvedApprovalIds.clear();
  _activeRunId = null;
  _lastSeq = 0;
  _error = null;
}
```

Use this helper in new session and workspace switching paths.

- [ ] **Step 5: Change send path**

In `_sendPrompt()`:

- If there is no active conversation, call `_conversationClient.createConversation(...)`.
- If `_conversationState?.status == 'waiting_input'`, call `answerQuestion()` with active question id.
- Otherwise call `sendMessage()`.
- Keep run API as fallback only if conversation API throws a version/404 error during transition.

- [ ] **Step 6: Poll conversation events**

Add `_pollConversationEvents()` that calls `_conversationClient.fetchEvents(conversation.id, afterSeq: state.lastSeq)`, reduces events through `reduceConversationEvent`, and mirrors reducer messages to existing `_WorkbenchMessage` cards.

- [ ] **Step 7: Route approval/cancel through conversation API**

- If `_activeConversation != null`, `_respondApproval()` uses `_conversationClient.respondApproval()`.
- If `_activeConversation != null`, `_cancelActiveRun()` uses `_conversationClient.cancelConversation()`.
- Keep old run methods as fallback only for legacy active runs.

- [ ] **Step 8: Update running/waiting UI rules**

- Pending sentinel shows only when conversation status is `running`.
- `waiting_input` shows question card and answer-mode placeholder.
- `waiting_approval` shows only one approval card and blocks normal message sending.

- [ ] **Step 9: Run Flutter tests**

Run from `mobile/`: `flutter test`
Expected: PASS.

---

## Task 9: Add Safe Real Claude Conversation Smoke

**Files:**
- Create: `scripts/smoke-claude-conversation.js`
- Optional modify: `package.json`

- [ ] **Step 1: Create smoke script**

Create `scripts/smoke-claude-conversation.js` that:

- Starts `createApp({ port: 0, mode: 'dev' })`.
- Pairs a test device.
- Creates a `claude` conversation with `permissionMode: 'auto'`.
- Sends `你是谁？一句话回答`.
- Polls `/api/conversations/:id/events` for up to 60 seconds.
- Succeeds when `assistant.message` arrives.
- Prints `{ ok: true, conversationId, eventCount }`.

- [ ] **Step 2: Add package script**

In `package.json`:

```json
"smoke:conversation:claude": "node scripts/smoke-claude-conversation.js"
```

- [ ] **Step 3: Run manually when Claude env is ready**

Run: `node scripts/smoke-claude-conversation.js`
Expected: `{ "ok": true }`.

If Claude external service fails, record provider/environment failure and do not block unit completion.

---

## Task 10: Final Verification

**Files:**
- Modify docs only if implementation changes the design.

- [ ] **Step 1: Run daemon tests**

Run: `npm test`
Expected: all tests pass.

- [ ] **Step 2: Run Flutter analyze**

Run from `mobile/`: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run Flutter tests**

Run from `mobile/`: `flutter test`
Expected: all tests pass.

- [ ] **Step 4: Optional Windows build**

Run from `mobile/`: `flutter build windows --debug`
Expected: build succeeds. If `LNK1168`, close/kill `lan_ai_cli_control.exe` and rerun.

- [ ] **Step 5: Optional safe real Claude smoke**

Run: `node scripts/smoke-claude-conversation.js`
Expected: `{ "ok": true }` or documented external provider failure.

- [ ] **Step 6: Acceptance checklist**

Confirm:

```text
[ ] Coding workbench uses /api/conversations.
[ ] New conversation has fresh conversationId and null cliSessionId.
[ ] Same conversation supports waiting_input.
[ ] Same conversation supports waiting_approval.
[ ] AskUserQuestion is not approval UI.
[ ] One blocking item visible at a time.
[ ] assistant.message is complete final Markdown.
[ ] /api/runs tests still pass.
```

---

## Commit Guidance

This workspace is currently not a git repository. If it becomes one, commit after each task using the repo's Lore Commit Protocol. If not, skip commit steps and record tests run after each task.
