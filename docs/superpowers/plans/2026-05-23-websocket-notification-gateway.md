# WebSocket Notification Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace workbench foreground event polling with a daemon WebSocket notification gateway that streams `conversation.events` and recovers through the existing `seq`-based REST backfill path.

**Architecture:** Add a topic-based `NotificationHub` to the Node daemon and keep persisted `conversation_events` as the reliability source. Add a Flutter notification client that exposes conversation event streams to the existing workbench reducer path, then remove the page-owned high-frequency poll timer while keeping REST fetch for reconnect repair and older daemons.

**Tech Stack:** Node.js `http` server plus `ws@8`, existing SQLite-backed `ConversationEventStore`, Flutter/Dart `dart:io` WebSocket wrapper, existing repository/ViewModel architecture, daemon tests in `scripts/run-tests.js`, Flutter tests under `mobile/test/`.

---

## Source Spec

- `docs/superpowers/specs/2026-05-23-websocket-notification-gateway-design.md`

The spec is the implementation authority for protocol frame shape, `scope`, replay ordering, replay truncation, token expiration, duplicate subscribe replacement, backpressure, reconnect defaults, and fallback behavior.

## File Structure

- Modify: `package.json`
  - Add `ws` runtime dependency.
- Modify: `package-lock.json`
  - Lock `ws@8`.
- Create: `daemon/src/notification-protocol.js`
  - Parse and validate client frames.
  - Create server frames.
  - Canonicalize `topic + scope` subscription keys.
- Create: `daemon/src/notification-hub.js`
  - Own WebSocket upgrade handling, authenticated connections, subscriptions, heartbeats, replay, fan-out, generation guards, and backpressure.
- Modify: `daemon/src/conversation-event-store.js`
  - Notify append listeners only after persistence succeeds.
- Modify: `daemon/src/main.js`
  - Construct `NotificationHub`, attach it to the existing HTTP server, and return it for tests.
- Modify: `daemon/src/version.js`
  - Reuse existing `versionInfo()` in the WebSocket `hello` frame.
- Modify: `scripts/run-tests.js`
  - Add daemon gateway, replay, auth, backpressure, and replacement tests.
- Create: `mobile/lib/src/data/services/notification_service.dart`
  - Define the data-layer contract for conversation event streams.
- Create: `mobile/lib/src/services/daemon_notification_client.dart`
  - Open WebSocket, parse frames, reconnect with backoff, handle `TOKEN_EXPIRED` and `REPLAY_TRUNCATED`, and fall back through REST.
- Modify: `mobile/lib/src/data/repositories/daemon_conversation_repository.dart`
  - Delegate `watchConversationEvents()` to the notification service when available.
- Modify: `mobile/lib/src/domain/repositories/conversation_repository.dart`
  - Add the `watchConversationEvents()` contract.
- Modify: `mobile/lib/src/data/services/conversation_service.dart`
  - Add an optional service-level stream method only if the implementation chooses to keep WebSocket on `DaemonClient`; otherwise leave HTTP service unchanged and keep WebSocket in `NotificationService`.
- Modify: `mobile/lib/src/services/daemon_client.dart`
  - Expose current token/base URI/proxy helpers needed by `DaemonNotificationClient`; keep HTTP fetch behavior intact.
- Modify: `mobile/lib/src/app/app_dependencies.dart`
  - Construct `DaemonNotificationClient` for connected daemon sessions and pass it into `DaemonConversationRepository`.
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
  - No new field is required if the repository owns `watchConversationEvents()`; add a field only if execution discovers a cleaner boundary is needed.
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
  - Expose `watchConversationEvents()` as a thin ViewModel pass-through if the page owns lifecycle subscription.
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
  - Replace `_poller` and `_pollEvents()` with a stream subscription, preserving terminal state drain through `seq` replay.
- Create: `mobile/test/daemon_notification_client_test.dart`
  - Unit-test URI conversion, protocol parsing, subscribe frames, reconnect, token expiry, replay truncation, and fallback.
- Modify: `mobile/test/coding_workbench_controller_test.dart`
  - Update fakes for the new repository contract and add ViewModel stream pass-through tests.
- Modify: `mobile/test/widget_test.dart`
  - Cover workbench page stream-driven transcript updates if page-level behavior changes.

---

### Task 1: Daemon Protocol Helpers

**Files:**
- Create: `daemon/src/notification-protocol.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing protocol tests**

Add this import near the other daemon imports in `scripts/run-tests.js`:

```javascript
const {
  notificationErrorCodes,
  canonicalScope,
  subscriptionKey,
  parseClientFrame,
  createHelloFrame,
  createSubscribedFrame,
  createEventFrame,
  createErrorFrame
} = require('../daemon/src/notification-protocol');
```

Add these tests near the conversation HTTP tests:

```javascript
test('notification protocol parses conversation subscribe frames', () => {
  const frame = parseClientFrame(JSON.stringify({
    type: 'subscribe',
    id: 'req_1',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 7
  }));

  assert.deepEqual(frame, {
    type: 'subscribe',
    id: 'req_1',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 7
  });
  assert.equal(canonicalScope(frame.scope), '{"conversationId":"conv_1"}');
  assert.equal(subscriptionKey(frame.topic, frame.scope), 'conversation.events|{"conversationId":"conv_1"}');
});

test('notification protocol rejects invalid subscribe frames', () => {
  assert.throws(
    () => parseClientFrame(JSON.stringify({
      type: 'subscribe',
      id: 'req_1',
      topic: 'conversation.events',
      scope: {},
      afterSeq: -1
    })),
    /INVALID_MESSAGE/
  );
});

test('notification protocol creates server frames with scope and capabilities', () => {
  assert.deepEqual(createHelloFrame({
    connectionId: 'ws_test',
    heartbeatIntervalMs: 25000,
    authExpiresAt: '2026-05-30T05:18:14.000Z',
    daemonVersion: '1.3.0',
    topics: ['conversation.events'],
    maxReplayEvents: 1000
  }), {
    type: 'hello',
    connectionId: 'ws_test',
    protocolVersion: 1,
    heartbeatIntervalMs: 25000,
    authExpiresAt: '2026-05-30T05:18:14.000Z',
    daemonVersion: '1.3.0',
    capabilities: {
      topics: ['conversation.events'],
      maxReplayEvents: 1000
    }
  });

  assert.deepEqual(createSubscribedFrame({
    id: 'req_1',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 7
  }), {
    type: 'subscribed',
    id: 'req_1',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 7
  });

  assert.deepEqual(createEventFrame({
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    event: { seq: 8, conversationId: 'conv_1', type: 'assistant.message', text: 'ok' }
  }), {
    type: 'event',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    seq: 8,
    payload: { seq: 8, conversationId: 'conv_1', type: 'assistant.message', text: 'ok' }
  });

  assert.deepEqual(createErrorFrame({
    id: 'req_1',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    code: notificationErrorCodes.FORBIDDEN,
    message: 'Device is not authorized for this conversation.'
  }), {
    type: 'error',
    id: 'req_1',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    code: 'FORBIDDEN',
    message: 'Device is not authorized for this conversation.'
  });
});
```

- [ ] **Step 2: Run the daemon tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected: FAIL because `daemon/src/notification-protocol.js` does not exist.

- [ ] **Step 3: Implement protocol helpers**

Create `daemon/src/notification-protocol.js`:

```javascript
'use strict';

const protocolVersion = 1;
const notificationTopics = Object.freeze({
  CONVERSATION_EVENTS: 'conversation.events'
});
const notificationErrorCodes = Object.freeze({
  AUTH_REQUIRED: 'AUTH_REQUIRED',
  TOKEN_EXPIRED: 'TOKEN_EXPIRED',
  FORBIDDEN: 'FORBIDDEN',
  UNKNOWN_TOPIC: 'UNKNOWN_TOPIC',
  INVALID_MESSAGE: 'INVALID_MESSAGE',
  REPLAY_TRUNCATED: 'REPLAY_TRUNCATED',
  BACKPRESSURE: 'BACKPRESSURE',
  INTERNAL_ERROR: 'INTERNAL_ERROR'
});

function parseClientFrame(raw) {
  let message;
  try {
    message = typeof raw === 'string' ? JSON.parse(raw) : JSON.parse(String(raw));
  } catch {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'WebSocket frame must be valid JSON.');
  }
  if (!message || typeof message !== 'object' || typeof message.type !== 'string') {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'WebSocket frame must contain a type.');
  }
  if (message.type === 'subscribe') return parseSubscribe(message);
  if (message.type === 'unsubscribe') return parseScopedRequest(message, 'unsubscribe');
  if (message.type === 'ack') return parseAck(message);
  if (message.type === 'ping') return { type: 'ping', id: stringOrNull(message.id) };
  throw protocolError(notificationErrorCodes.INVALID_MESSAGE, `Unsupported WebSocket frame type: ${message.type}`);
}

function parseSubscribe(message) {
  const frame = parseScopedRequest(message, 'subscribe');
  const afterSeq = Number(message.afterSeq || 0);
  if (!Number.isSafeInteger(afterSeq) || afterSeq < 0) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'afterSeq must be a non-negative integer.');
  }
  return { ...frame, afterSeq };
}

function parseScopedRequest(message, expectedType) {
  if (message.type !== expectedType) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, `Expected ${expectedType} frame.`);
  }
  if (typeof message.topic !== 'string' || message.topic.length === 0) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'topic is required.');
  }
  const scope = normalizeScope(message.scope);
  validateTopicScope(message.topic, scope);
  return {
    type: expectedType,
    id: stringOrNull(message.id),
    topic: message.topic,
    scope
  };
}

function parseAck(message) {
  const frame = parseScopedRequest(message, 'ack');
  const seq = Number(message.seq);
  if (!Number.isSafeInteger(seq) || seq < 0) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'ack seq must be a non-negative integer.');
  }
  return { ...frame, seq };
}

function normalizeScope(scope) {
  if (!scope || typeof scope !== 'object' || Array.isArray(scope)) return {};
  return Object.fromEntries(Object.keys(scope).sort().map((key) => [key, scope[key]]));
}

function validateTopicScope(topic, scope) {
  if (topic === notificationTopics.CONVERSATION_EVENTS) {
    if (typeof scope.conversationId !== 'string' || scope.conversationId.length === 0) {
      throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'conversation.events requires scope.conversationId.');
    }
    return;
  }
  throw protocolError(notificationErrorCodes.UNKNOWN_TOPIC, `Unknown notification topic: ${topic}`);
}

function canonicalScope(scope) {
  return JSON.stringify(normalizeScope(scope));
}

function subscriptionKey(topic, scope) {
  return `${topic}|${canonicalScope(scope)}`;
}

function createHelloFrame({ connectionId, heartbeatIntervalMs, authExpiresAt = null, daemonVersion, topics, maxReplayEvents }) {
  return {
    type: 'hello',
    connectionId,
    protocolVersion,
    heartbeatIntervalMs,
    authExpiresAt,
    daemonVersion,
    capabilities: { topics, maxReplayEvents }
  };
}

function createSubscribedFrame({ id, topic, scope, afterSeq }) {
  return { type: 'subscribed', id: stringOrNull(id), topic, scope: normalizeScope(scope), afterSeq };
}

function createEventFrame({ topic, scope, event }) {
  return { type: 'event', topic, scope: normalizeScope(scope), seq: event.seq, payload: event };
}

function createErrorFrame({ id = null, topic = null, scope = null, code, message }) {
  return {
    type: 'error',
    ...(id ? { id } : {}),
    ...(topic ? { topic } : {}),
    ...(scope ? { scope: normalizeScope(scope) } : {}),
    code,
    message
  };
}

function protocolError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function stringOrNull(value) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

module.exports = {
  protocolVersion,
  notificationTopics,
  notificationErrorCodes,
  parseClientFrame,
  canonicalScope,
  subscriptionKey,
  createHelloFrame,
  createSubscribedFrame,
  createEventFrame,
  createErrorFrame,
  protocolError
};
```

- [ ] **Step 4: Run the protocol tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected: PASS for the new protocol tests. Other existing tests should remain PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts\run-tests.js daemon\src\notification-protocol.js
git commit -m "Add notification protocol helpers"
```

---

### Task 2: WebSocket Dependency And Authenticated Hello

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
- Create: `daemon/src/notification-hub.js`
- Modify: `daemon/src/main.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Add WebSocket dependency**

Run:

```powershell
npm install ws@8
```

Expected: `package.json` gains a `ws` dependency and `package-lock.json` updates.

- [ ] **Step 2: Write failing authenticated hello tests**

In `scripts/run-tests.js`, add this import:

```javascript
const WebSocket = require('ws');
```

Add helper functions near the existing HTTP `request` helpers:

```javascript
function wsUrl(port, path = '/api/notifications/ws') {
  return `ws://127.0.0.1:${port}${path}`;
}

function openNotificationSocket(port, token) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl(port), {
      headers: token ? { authorization: `Bearer ${token}` } : {}
    });
    socket.once('open', () => resolve(socket));
    socket.once('error', reject);
  });
}

function readWsJson(socket) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('timed out waiting for WebSocket message')), 1000);
    socket.once('message', (data) => {
      clearTimeout(timeout);
      resolve(JSON.parse(String(data)));
    });
    socket.once('error', (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
}

function waitForWsClose(socket) {
  return new Promise((resolve) => socket.once('close', resolve));
}
```

Add tests:

```javascript
test('notification websocket rejects missing bearer token', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-auth-missing-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const socket = new WebSocket(wsUrl(port));
    const closeCode = await new Promise((resolve) => socket.once('close', resolve));
    assert.equal(closeCode, 1008);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('notification websocket accepts bearer token and sends hello', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-hello-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-test', deviceId: 'ws-device-1' });
    socket = await openNotificationSocket(port, paired.body.token);
    const hello = await readWsJson(socket);
    assert.equal(hello.type, 'hello');
    assert.equal(hello.protocolVersion, 1);
    assert.equal(hello.daemonVersion, app.version.daemonVersion);
    assert.deepEqual(hello.capabilities.topics, ['conversation.events']);
    assert.equal(hello.capabilities.maxReplayEvents, 1000);
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected: FAIL because the WebSocket upgrade route and `NotificationHub` do not exist.

- [ ] **Step 4: Implement the basic hub**

Create `daemon/src/notification-hub.js` with this initial shape:

```javascript
'use strict';

const crypto = require('node:crypto');
const { WebSocketServer } = require('ws');
const {
  notificationTopics,
  notificationErrorCodes,
  createHelloFrame,
  createErrorFrame
} = require('./notification-protocol');

class NotificationHub {
  constructor({
    auth,
    conversations,
    version,
    heartbeatIntervalMs = 25000,
    maxReplayEvents = 1000,
    now = () => new Date()
  }) {
    this.auth = auth;
    this.conversations = conversations;
    this.version = version;
    this.heartbeatIntervalMs = heartbeatIntervalMs;
    this.maxReplayEvents = maxReplayEvents;
    this.now = now;
    this.connections = new Map();
    this.wss = new WebSocketServer({ noServer: true });
  }

  attach(server) {
    server.on('upgrade', (req, socket, head) => {
      if (!req.url || !req.url.startsWith('/api/notifications/ws')) {
        socket.destroy();
        return;
      }
      let device;
      try {
        device = this.auth.authenticate(req.headers.authorization);
      } catch {
        socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
        socket.destroy();
        return;
      }
      this.wss.handleUpgrade(req, socket, head, (ws) => {
        this.acceptConnection(ws, device);
      });
    });
  }

  acceptConnection(ws, device) {
    const connection = {
      id: `ws_${crypto.randomUUID()}`,
      ws,
      device,
      subscriptions: new Map(),
      generationCounter: 0,
      alive: true,
      authExpiresAt: null
    };
    this.connections.set(connection.id, connection);
    ws.on('pong', () => { connection.alive = true; });
    ws.on('close', () => this.closeConnection(connection));
    ws.on('error', () => this.closeConnection(connection));
    this.send(connection, createHelloFrame({
      connectionId: connection.id,
      heartbeatIntervalMs: this.heartbeatIntervalMs,
      authExpiresAt: connection.authExpiresAt,
      daemonVersion: this.version.daemonVersion,
      topics: [notificationTopics.CONVERSATION_EVENTS],
      maxReplayEvents: this.maxReplayEvents
    }));
  }

  closeConnection(connection) {
    this.connections.delete(connection.id);
    connection.subscriptions.clear();
  }

  send(connection, frame) {
    if (connection.ws.readyState !== connection.ws.OPEN) return false;
    connection.ws.send(JSON.stringify(frame));
    return true;
  }

  sendError(connection, options) {
    this.send(connection, createErrorFrame(options));
  }
}

module.exports = { NotificationHub };
```

Modify `daemon/src/main.js`:

```javascript
const { NotificationHub } = require('./notification-hub');
```

After creating `server`, attach the hub:

```javascript
const server = createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset });
const notificationHub = new NotificationHub({ auth, conversations, version });
notificationHub.attach(server);
return { server, auth, workspaces, eventStore, conversationEventStore, conversationSqliteStore, appSqliteStore, auditLog, adapterRegistry, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, migrationService, diagnostics, diagnosticBundle, runs, conversations, notificationHub, config, version, asrModelAsset, attachmentScratchCleanup };
```

- [ ] **Step 5: Run tests**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected: both pass.

- [ ] **Step 6: Commit**

```powershell
git add package.json package-lock.json scripts\run-tests.js daemon\src\notification-hub.js daemon\src\main.js
git commit -m "Add authenticated notification websocket"
```

---

### Task 3: Conversation Event Fan-Out With Replay Guards

**Files:**
- Modify: `daemon/src/conversation-event-store.js`
- Modify: `daemon/src/notification-hub.js`
- Modify: `daemon/src/main.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing replay and fan-out tests**

Add these tests:

```javascript
test('notification websocket subscribes and replays conversation events after sequence', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-replay-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-replay', deviceId: 'ws-device-replay' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', { workspacePath: process.cwd(), name: 'Default' }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'synthetic-text' }, token);
    const conversationId = created.body.conversation.id;
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'first' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'second' });

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_1',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: 1
    }));
    const subscribed = await readWsJson(socket);
    const replayed = await readWsJson(socket);
    assert.equal(subscribed.type, 'subscribed');
    assert.equal(replayed.type, 'event');
    assert.equal(replayed.seq, 2);
    assert.equal(replayed.payload.text, 'second');
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('notification websocket delivers live conversation events after subscribe', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-live-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-live', deviceId: 'ws-device-live' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', { workspacePath: process.cwd(), name: 'Default' }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'synthetic-text' }, token);
    const conversationId = created.body.conversation.id;

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_live',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: 0
    }));
    await readWsJson(socket);
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'live' });
    const event = await readWsJson(socket);
    assert.equal(event.type, 'event');
    assert.equal(event.payload.text, 'live');
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected: FAIL because subscribe frames are not handled and append listeners are not wired.

- [ ] **Step 3: Add append listeners**

Modify `daemon/src/conversation-event-store.js`:

```javascript
class ConversationEventStore {
  constructor({ now = () => new Date(), persistentStore = null } = {}) {
    this.now = now;
    this.persistentStore = persistentStore;
    this.events = new Map();
    this.appendListeners = new Set();
  }

  onAppend(listener) {
    this.appendListeners.add(listener);
    return () => this.appendListeners.delete(listener);
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
    if (this.persistentStore) this.persistentStore.appendEvent(event);
    list.push(event);
    this.events.set(conversationId, list);
    for (const listener of this.appendListeners) listener(event);
    return event;
  }
}
```

- [ ] **Step 4: Implement subscribe, replay, generation guard, and live publish**

In `daemon/src/notification-hub.js`, add protocol imports:

```javascript
const {
  notificationTopics,
  notificationErrorCodes,
  parseClientFrame,
  subscriptionKey,
  createHelloFrame,
  createSubscribedFrame,
  createEventFrame,
  createErrorFrame
} = require('./notification-protocol');
```

Add constructor fields:

```javascript
this.conversationEventStore = conversationEventStore;
this.maxReplayEvents = maxReplayEvents;
this.replayBatchSize = replayBatchSize;
this.unsubscribeAppend = null;
```

Add `start()`:

```javascript
start() {
  this.unsubscribeAppend = this.conversationEventStore.onAppend((event) => {
    this.publishConversationEvent(event);
  });
}
```

Handle messages in `acceptConnection()`:

```javascript
ws.on('message', (raw) => this.handleMessage(connection, raw));
```

Implement the core methods:

```javascript
handleMessage(connection, raw) {
  let frame;
  try {
    frame = parseClientFrame(raw);
  } catch (error) {
    this.sendError(connection, {
      code: error.code || notificationErrorCodes.INVALID_MESSAGE,
      message: error.message
    });
    return;
  }
  if (frame.type === 'subscribe') {
    this.subscribe(connection, frame).catch((error) => {
      this.sendError(connection, {
        id: frame.id,
        topic: frame.topic,
        scope: frame.scope,
        code: error.code || notificationErrorCodes.INTERNAL_ERROR,
        message: error.message
      });
    });
    return;
  }
  if (frame.type === 'unsubscribe') {
    connection.subscriptions.delete(subscriptionKey(frame.topic, frame.scope));
  }
}

async subscribe(connection, frame) {
  const conversation = this.conversations.requireConversation(frame.scope.conversationId, connection.device);
  const key = subscriptionKey(frame.topic, frame.scope);
  const generation = ++connection.generationCounter;
  const subscription = {
    key,
    generation,
    topic: frame.topic,
    scope: frame.scope,
    conversationId: conversation.id,
    replaying: true,
    queuedLiveEvents: []
  };
  connection.subscriptions.set(key, subscription);
  this.send(connection, createSubscribedFrame(frame));
  const replayEvents = this.conversations.listEvents(conversation.id, frame.afterSeq, connection.device);
  if (replayEvents.length > this.maxReplayEvents) {
    connection.subscriptions.delete(key);
    this.sendError(connection, {
      id: frame.id,
      topic: frame.topic,
      scope: frame.scope,
      code: notificationErrorCodes.REPLAY_TRUNCATED,
      message: `Replay has ${replayEvents.length} events, which exceeds ${this.maxReplayEvents}.`
    });
    return;
  }
  await this.sendReplayBatches(connection, subscription, replayEvents);
}

async sendReplayBatches(connection, subscription, events) {
  const sentSeqs = new Set();
  for (let index = 0; index < events.length; index += this.replayBatchSize) {
    if (!this.isCurrentSubscription(connection, subscription)) return;
    for (const event of events.slice(index, index + this.replayBatchSize)) {
      sentSeqs.add(event.seq);
      this.send(connection, createEventFrame({ topic: subscription.topic, scope: subscription.scope, event }));
    }
    await new Promise((resolve) => setImmediate(resolve));
  }
  if (!this.isCurrentSubscription(connection, subscription)) return;
  subscription.replaying = false;
  const queued = subscription.queuedLiveEvents
    .filter((event) => !sentSeqs.has(event.seq))
    .sort((a, b) => a.seq - b.seq);
  subscription.queuedLiveEvents = [];
  for (const event of queued) {
    if (!this.isCurrentSubscription(connection, subscription)) return;
    this.send(connection, createEventFrame({ topic: subscription.topic, scope: subscription.scope, event }));
  }
}

isCurrentSubscription(connection, subscription) {
  return connection.subscriptions.get(subscription.key)?.generation === subscription.generation;
}

publishConversationEvent(event) {
  for (const connection of this.connections.values()) {
    const scope = { conversationId: event.conversationId };
    const key = subscriptionKey(notificationTopics.CONVERSATION_EVENTS, scope);
    const subscription = connection.subscriptions.get(key);
    if (!subscription) continue;
    if (subscription.replaying) {
      subscription.queuedLiveEvents.push(event);
      continue;
    }
    this.send(connection, createEventFrame({ topic: subscription.topic, scope: subscription.scope, event }));
  }
}
```

Modify `daemon/src/main.js` to pass `conversationEventStore` and call `start()`:

```javascript
const notificationHub = new NotificationHub({ auth, conversations, conversationEventStore, version });
notificationHub.attach(server);
notificationHub.start();
```

- [ ] **Step 5: Run tests**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected: both pass.

- [ ] **Step 6: Commit**

```powershell
git add scripts\run-tests.js daemon\src\conversation-event-store.js daemon\src\notification-hub.js daemon\src\main.js
git commit -m "Stream conversation events over notifications"
```

---

### Task 4: Daemon Edge Cases

**Files:**
- Modify: `daemon/src/notification-hub.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Add tests for duplicate subscribe, replay truncation, and backpressure**

Add this helper near the WebSocket helpers:

```javascript
function expectNoWsMessage(socket, timeoutMs = 100) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(resolve, timeoutMs);
    socket.once('message', (data) => {
      clearTimeout(timeout);
      reject(new Error(`unexpected WebSocket message: ${String(data)}`));
    });
  });
}
```

Add these tests:

```javascript
test('notification websocket replaces duplicate subscription for same topic and scope', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-duplicate-sub-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-duplicate', deviceId: 'ws-device-duplicate' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', { workspacePath: process.cwd(), name: 'Default' }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'synthetic-text' }, token);
    const conversationId = created.body.conversation.id;
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'old' });

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_first',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: 0
    }));
    await readWsJson(socket);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_second',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: 1
    }));
    await readWsJson(socket);
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'live-once' });
    const event = await readWsJson(socket);
    assert.equal(event.type, 'event');
    assert.equal(event.payload.text, 'live-once');
    await expectNoWsMessage(socket);
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('notification websocket reports replay truncation when afterSeq is too old', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-replay-truncated-') });
  app.notificationHub.maxReplayEvents = 2;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-truncated', deviceId: 'ws-device-truncated' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', { workspacePath: process.cwd(), name: 'Default' }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'synthetic-text' }, token);
    const conversationId = created.body.conversation.id;
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'one' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'two' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'three' });

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_truncated',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: 0
    }));
    await readWsJson(socket);
    const error = await readWsJson(socket);
    assert.equal(error.type, 'error');
    assert.equal(error.code, 'REPLAY_TRUNCATED');
    assert.deepEqual(error.scope, { conversationId });
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('notification websocket closes slow clients on backpressure', async () => {
  const { NotificationHub } = require('../daemon/src/notification-hub');
  const sentFrames = [];
  let closed = null;
  const ws = {
    OPEN: 1,
    readyState: 1,
    bufferedAmount: 2,
    send(data, callback) {
      sentFrames.push(JSON.parse(String(data)));
      if (callback) callback();
    },
    close(code, reason) {
      closed = { code, reason };
    }
  };
  const hub = new NotificationHub({
    auth: null,
    conversations: null,
    conversationEventStore: { onAppend() { return () => {}; } },
    version: { daemonVersion: '1.3.0' },
    maxBufferedBytes: 1,
    maxQueuedFrames: 500
  });
  const sent = hub.send({
    id: 'ws_test',
    ws,
    subscriptions: new Map(),
    pendingFrameCount: 0
  }, { type: 'event', payload: {} });

  assert.equal(sent, false);
  assert.equal(sentFrames[0].type, 'error');
  assert.equal(sentFrames[0].code, 'BACKPRESSURE');
  assert.deepEqual(closed, { code: 1013, reason: 'BACKPRESSURE' });
});
```

- [ ] **Step 2: Implement test hooks and edge behavior**

Add constructor options:

```javascript
maxBufferedBytes = 1024 * 1024,
maxQueuedFrames = 500,
websocketMaxConnectionAgeMs = 60 * 60 * 1000
```

Update `send()` and `sendError()` so `BACKPRESSURE` can still be emitted before close:

```javascript
send(connection, frame, { bypassBackpressure = false } = {}) {
  if (connection.ws.readyState !== connection.ws.OPEN) return false;
  if (!bypassBackpressure &&
      (connection.ws.bufferedAmount > this.maxBufferedBytes ||
       connection.pendingFrameCount > this.maxQueuedFrames)) {
    this.sendError(connection, {
      code: notificationErrorCodes.BACKPRESSURE,
      message: 'Notification connection is too far behind.'
    }, { bypassBackpressure: true });
    connection.ws.close(1013, 'BACKPRESSURE');
    return false;
  }
  connection.pendingFrameCount += 1;
  connection.ws.send(JSON.stringify(frame), () => {
    connection.pendingFrameCount = Math.max(0, connection.pendingFrameCount - 1);
  });
  return true;
}

sendError(connection, options, sendOptions = {}) {
  this.send(connection, createErrorFrame(options), sendOptions);
}
```

Add a connection age timer:

```javascript
connection.authTimer = setTimeout(() => {
  this.sendError(connection, {
    code: notificationErrorCodes.TOKEN_EXPIRED,
    message: 'Notification access token expired.'
  });
  connection.ws.close(1008, 'TOKEN_EXPIRED');
}, this.websocketMaxConnectionAgeMs);
```

Clear it in `closeConnection()`:

```javascript
if (connection.authTimer) clearTimeout(connection.authTimer);
```

- [ ] **Step 3: Run tests**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected: both pass.

- [ ] **Step 4: Commit**

```powershell
git add scripts\run-tests.js daemon\src\notification-hub.js
git commit -m "Harden notification websocket edge cases"
```

---

### Task 5: Mobile Notification Client

**Files:**
- Create: `mobile/lib/src/data/services/notification_service.dart`
- Create: `mobile/lib/src/services/daemon_notification_client.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Create: `mobile/test/daemon_notification_client_test.dart`

- [ ] **Step 1: Write failing mobile notification client tests**

Create `mobile/test/daemon_notification_client_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_notification_client.dart';

void main() {
  test('notification websocket uri converts http to ws', () {
    expect(
      daemonNotificationWebSocketUri(Uri.parse('http://127.0.0.1:4317')),
      Uri.parse('ws://127.0.0.1:4317/api/notifications/ws'),
    );
    expect(
      daemonNotificationWebSocketUri(Uri.parse('https://example.test/base')),
      Uri.parse('wss://example.test/api/notifications/ws'),
    );
  });

  test('subscribes with scope and afterSeq then emits conversation events', () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async => socket,
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      reconnectDelays: const <Duration>[Duration(milliseconds: 1)],
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    socket.serverAddJson(<String, Object?>{
      'type': 'hello',
      'connectionId': 'ws_test',
      'protocolVersion': 1,
      'heartbeatIntervalMs': 25000,
      'capabilities': <String, Object?>{
        'topics': <String>['conversation.events'],
        'maxReplayEvents': 1000,
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(socket.sentJson.single['type'], 'subscribe');
    expect(socket.sentJson.single['topic'], 'conversation.events');
    expect(socket.sentJson.single['scope'], <String, Object?>{'conversationId': 'conv_1'});
    expect(socket.sentJson.single['afterSeq'], 7);

    socket.serverAddJson(<String, Object?>{
      'type': 'event',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'seq': 8,
      'payload': <String, Object?>{
        'seq': 8,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-23T05:18:14.000Z',
        'text': 'hello',
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(events.single.seq, 8);
    expect(events.single.type, 'assistant.message');

    await subscription.cancel();
    await client.close();
  });
}

class FakeNotificationSocket implements NotificationSocket {
  final StreamController<Object?> _incoming = StreamController<Object?>();
  final List<Map<String, Object?>> sentJson = <Map<String, Object?>>[];

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  void add(String data) {
    sentJson.add(jsonObject(data));
  }

  void serverAddJson(Map<String, Object?> json) {
    _incoming.add(json);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _incoming.close();
  }
}

Map<String, Object?> jsonObject(String source) =>
    Map<String, Object?>.from(DaemonNotificationClient.decodeJson(source));
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\daemon_notification_client_test.dart -r expanded
```

Expected: FAIL because the notification client files do not exist.

- [ ] **Step 3: Add service contract**

Create `mobile/lib/src/data/services/notification_service.dart`:

```dart
import '../../models/protocol.dart';

abstract class NotificationService {
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  });
}
```

- [ ] **Step 4: Implement notification client**

Create `mobile/lib/src/services/daemon_notification_client.dart` with:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/services/notification_service.dart';
import '../models/protocol.dart';

typedef NotificationTokenProvider = String? Function();
typedef NotificationBackfillFetcher = Future<List<ConversationEvent>> Function(
  String conversationId, {
  required int afterSeq,
});
typedef NotificationSocketConnector = Future<NotificationSocket> Function(
  Uri uri,
  Map<String, String> headers,
);

abstract class NotificationSocket {
  Stream<Object?> get stream;
  void add(String data);
  Future<void> close([int? code, String? reason]);
}

class IoNotificationSocket implements NotificationSocket {
  IoNotificationSocket(this._socket);
  final WebSocket _socket;

  @override
  Stream<Object?> get stream => _socket;

  @override
  void add(String data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);
}

class DaemonNotificationClient implements NotificationService {
  DaemonNotificationClient({
    required this.baseUri,
    required this.tokenProvider,
    required this.fetchBackfill,
    NotificationSocketConnector? connector,
    this.reconnectDelays = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
  }) : _connector = connector ?? _connectIoSocket;

  final Uri baseUri;
  final NotificationTokenProvider tokenProvider;
  final NotificationBackfillFetcher fetchBackfill;
  final NotificationSocketConnector _connector;
  final List<Duration> reconnectDelays;
  bool _closed = false;

  static Object? decodeJson(String source) => jsonDecode(source);

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) async* {
    var cursor = afterSeq;
    var attempt = 0;
    while (!_closed) {
      NotificationSocket? socket;
      try {
        final token = tokenProvider();
        socket = await _connector(
          daemonNotificationWebSocketUri(baseUri),
          <String, String>{if (token != null) 'authorization': 'Bearer $token'},
        );
        socket.add(jsonEncode(<String, Object?>{
          'type': 'subscribe',
          'id': 'sub_$conversationId',
          'topic': 'conversation.events',
          'scope': <String, Object?>{'conversationId': conversationId},
          'afterSeq': cursor,
        }));
        attempt = 0;
        await for (final raw in socket.stream) {
          final decoded = raw is String ? jsonDecode(raw) : raw;
          if (decoded is! Map) continue;
          final frame = Map<String, Object?>.from(decoded);
          if (frame['type'] == 'event') {
            final payload = Map<String, Object?>.from(frame['payload'] as Map);
            final event = ConversationEvent.fromJson(payload);
            if (event.seq > cursor) cursor = event.seq;
            yield event;
          } else if (frame['type'] == 'error' &&
              frame['code'] == 'REPLAY_TRUNCATED') {
            final backfill = await fetchBackfill(conversationId, afterSeq: cursor);
            for (final event in backfill) {
              if (event.seq > cursor) cursor = event.seq;
              yield event;
            }
          } else if (frame['type'] == 'error' &&
              (frame['code'] == 'AUTH_REQUIRED' ||
                  frame['code'] == 'TOKEN_EXPIRED')) {
            break;
          }
        }
      } finally {
        await socket?.close();
      }
      if (_closed) break;
      final delay = reconnectDelays[attempt.clamp(0, reconnectDelays.length - 1)];
      attempt += 1;
      await Future<void>.delayed(delay);
    }
  }

  Future<void> close() async {
    _closed = true;
  }
}

Uri daemonNotificationWebSocketUri(Uri baseUri) {
  final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
  return baseUri.replace(scheme: scheme, path: '/api/notifications/ws', query: '');
}

Future<NotificationSocket> _connectIoSocket(
  Uri uri,
  Map<String, String> headers,
) async {
  final socket = await WebSocket.connect(uri.toString(), headers: headers);
  return IoNotificationSocket(socket);
}
```

- [ ] **Step 5: Run client tests**

Run:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\daemon_notification_client_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add mobile\lib\src\data\services\notification_service.dart mobile\lib\src\services\daemon_notification_client.dart mobile\test\daemon_notification_client_test.dart
git commit -m "Add mobile notification websocket client"
```

---

### Task 6: Mobile Repository And Workbench Subscription Integration

**Files:**
- Modify: `mobile/lib/src/domain/repositories/conversation_repository.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_conversation_repository.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`

- [ ] **Step 1: Add failing repository stream tests**

In `mobile/test/coding_workbench_controller_test.dart`, update `_FakeConversationRepository` to expose a controller and add this test:

```dart
test('workbench view model watches conversation events after sequence', () async {
  final repository = _FakeConversationRepository();
  final viewModel = WorkbenchViewModel(
    initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
    conversationRepository: repository,
  );

  final emitted = <ConversationEvent>[];
  final subscription = viewModel
      .watchConversationEvents(conversationId: 'conv_existing', afterSeq: 7)
      .listen(emitted.add);

  repository.emitConversationEvent(const ConversationEvent(
    seq: 8,
    conversationId: 'conv_existing',
    type: 'assistant.message',
    createdAt: '2026-05-23T05:18:14.000Z',
    text: 'streamed',
  ));
  await Future<void>.delayed(Duration.zero);

  expect(repository.calls, <String>['watchEvents:conv_existing:7']);
  expect(emitted.single.seq, 8);
  await subscription.cancel();
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\coding_workbench_controller_test.dart -r expanded --plain-name "workbench view model watches conversation events after sequence"
```

Expected: FAIL because repository and ViewModel contracts do not expose `watchConversationEvents()`.

- [ ] **Step 3: Add repository stream contract**

Add to `mobile/lib/src/domain/repositories/conversation_repository.dart`:

```dart
Stream<ConversationEvent> watchConversationEvents(
  String conversationId, {
  required int afterSeq,
});
```

Update `DaemonConversationRepository` constructor:

```dart
DaemonConversationRepository({
  required DaemonClient client,
  NotificationService? notificationService,
})  : _client = client,
      _notificationService = notificationService;

final NotificationService? _notificationService;
```

Add method:

```dart
@override
Stream<ConversationEvent> watchConversationEvents(
  String conversationId, {
  required int afterSeq,
}) {
  final service = _notificationService;
  if (service == null) {
    return Stream<List<ConversationEvent>>.periodic(
      const Duration(seconds: 5),
    ).asyncMap((_) => fetchConversationEvents(conversationId, afterSeq: afterSeq))
        .expand((events) => events);
  }
  return service.watchConversationEvents(conversationId, afterSeq: afterSeq);
}
```

Use the fallback only as a compatibility bridge. The page must not run its old 900 ms timer after the stream path is integrated.

- [ ] **Step 4: Wire app dependencies**

In `mobile/lib/src/app/app_dependencies.dart`, import:

```dart
import '../services/daemon_notification_client.dart';
```

When constructing `DaemonConversationRepository`, pass:

```dart
conversationRepository: DaemonConversationRepository(
  client: client,
  notificationService: DaemonNotificationClient(
    baseUri: client.baseUri,
    tokenProvider: () => client.currentToken,
    fetchBackfill: (conversationId, {required afterSeq}) =>
        client.fetchConversationEvents(conversationId, afterSeq: afterSeq),
  ),
),
```

- [ ] **Step 5: Expose ViewModel stream**

Add to `WorkbenchViewModel`:

```dart
Stream<ConversationEvent> watchConversationEvents({
  required String conversationId,
  required int afterSeq,
}) =>
    _requireConversationRepository().watchConversationEvents(
      conversationId,
      afterSeq: afterSeq,
    );
```

- [ ] **Step 6: Replace page polling with subscription**

In `CodingWorkbenchPage`, replace:

```dart
Timer? _poller;
bool _pollInFlight = false;
```

with:

```dart
StreamSubscription<ConversationEvent>? _conversationEventSubscription;
```

Replace `_restartConversationPolling()` with `_restartConversationEventSubscription()`:

```dart
Future<void> _restartConversationEventSubscription() async {
  await _conversationEventSubscription?.cancel();
  final runId = _activeRunId;
  final conversationId = _activeConversationId;
  if (!mounted || runId == null || conversationId == null) return;
  final afterSeq = _workbenchViewModel.lastSeq;
  _conversationEventSubscription = _workbenchViewModel
      .watchConversationEvents(conversationId: conversationId, afterSeq: afterSeq)
      .listen((event) async {
    if (!mounted ||
        conversationId != _activeConversationId ||
        runId != _activeRunId) {
      return;
    }
    await _workbenchViewModel.applyConversationEventsAsync(
      <ConversationEvent>[event],
      streamOutput: widget.streamOutput,
      notify: true,
    );
  }, onError: (Object error, StackTrace stack) {
    unawaited(_workbenchViewModel.recordException(
      message: error.toString(),
      stack: stack.toString(),
      path: '/api/notifications/ws',
      conversationId: conversationId,
      runId: runId,
      operation: 'watchConversationEvents',
    ));
  });
}
```

Update all internal callers of `_restartConversationPolling()` to `_restartConversationEventSubscription()`. In `dispose()`, cancel `_conversationEventSubscription`.

- [ ] **Step 7: Run targeted Flutter tests**

Run:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\daemon_notification_client_test.dart test\coding_workbench_controller_test.dart -r expanded
```

Expected: architecture check, analyze, and tests pass.

- [ ] **Step 8: Commit**

```powershell
git add mobile\lib\src\domain\repositories\conversation_repository.dart mobile\lib\src\data\repositories\daemon_conversation_repository.dart mobile\lib\src\app\app_dependencies.dart mobile\lib\src\ui\features\workbench\view_models\workbench_view_model.dart mobile\lib\src\ui\features\workbench\coding_workbench_page.dart mobile\test\coding_workbench_controller_test.dart
git commit -m "Use notification stream for workbench events"
```

---

### Task 7: End-To-End Recovery And Diagnostics

**Files:**
- Modify: `daemon/src/notification-hub.js`
- Modify: `mobile/lib/src/services/daemon_notification_client.dart`
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Modify: `mobile/test/daemon_notification_client_test.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`
- Modify: `scripts/run-tests.js`
- Modify: `docs/project-knowledge/troubleshooting-playbook.md`

- [ ] **Step 1: Add recovery tests**

Add this daemon test for the replay/live gap:

```javascript
test('notification websocket queues live events appended during replay', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-replay-gap-') });
  app.notificationHub.replayBatchSize = 1;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-replay-gap', deviceId: 'ws-device-replay-gap' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', { workspacePath: process.cwd(), name: 'Default' }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'synthetic-text' }, token);
    const conversationId = created.body.conversation.id;
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'one' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'two' });

    let appendedDuringReplay = false;
    app.notificationHub.onReplayBatchSent = ({ subscription }) => {
      if (!appendedDuringReplay && subscription.conversationId === conversationId) {
        appendedDuringReplay = true;
        app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'three' });
      }
    };

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_gap',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: 0
    }));
    await readWsJson(socket);
    const first = await readWsJson(socket);
    const second = await readWsJson(socket);
    const third = await readWsJson(socket);
    assert.deepEqual(
      [first.payload.text, second.payload.text, third.payload.text],
      ['one', 'two', 'three']
    );
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});
```

Add mobile test assertions for fallback:

```dart
test('uses REST backfill after replay truncated error', () async {
  final socket = FakeNotificationSocket();
  final backfillCalls = <String>[];
  final client = DaemonNotificationClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenProvider: () => 'token_1',
    connector: (_, __) async => socket,
    fetchBackfill: (conversationId, {required afterSeq}) async {
      backfillCalls.add('$conversationId:$afterSeq');
      return <ConversationEvent>[
        const ConversationEvent(
          seq: 9,
          conversationId: 'conv_1',
          type: 'assistant.message',
          createdAt: '2026-05-23T05:18:14.000Z',
          text: 'backfilled',
        ),
      ];
    },
  );
  final events = <ConversationEvent>[];
  final subscription = client.watchConversationEvents('conv_1', afterSeq: 8).listen(events.add);
  socket.serverAddJson(<String, Object?>{
    'type': 'error',
    'topic': 'conversation.events',
    'scope': <String, Object?>{'conversationId': 'conv_1'},
    'code': 'REPLAY_TRUNCATED',
    'message': 'Replay too large.',
  });
  await Future<void>.delayed(Duration.zero);
  expect(backfillCalls, <String>['conv_1:8']);
  expect(events.single.text, 'backfilled');
  await subscription.cancel();
  await client.close();
});
```

- [ ] **Step 2: Implement missing recovery behavior**

Ensure daemon replay uses generation id and live queue exactly as the spec states. Add the test-only hook used above to `NotificationHub` without affecting production behavior:

```javascript
this.onReplayBatchSent = null;
```

Call it after each replay batch:

```javascript
if (this.onReplayBatchSent) {
  this.onReplayBatchSent({ connection, subscription });
}
```

Ensure mobile handles:

```dart
AUTH_REQUIRED
TOKEN_EXPIRED
REPLAY_TRUNCATED
```

by refreshing through existing HTTP flow where available, using REST backfill for truncation, and reconnecting with the latest applied `seq`.

- [ ] **Step 3: Update troubleshooting knowledge**

Append a concise entry to `docs/project-knowledge/troubleshooting-playbook.md`:

```markdown
## Symptom: Workbench WebSocket Stream Appears Stalled

- Symptom: daemon persists later `conversation_events`, but the foreground transcript does not update over the WebSocket notification path.
- Action: inspect WebSocket notification trace rows first. Confirm the active `topic + scope`, latest applied `seq`, reconnect status, and whether REST backfill ran after `REPLAY_TRUNCATED`, `TOKEN_EXPIRED`, or socket close. If persisted seq advances while mobile seq does not, force reconnect from the last applied seq before changing reducer logic.
- Verification:

```powershell
node scripts/run-tests.js
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\daemon_notification_client_test.dart test\coding_workbench_controller_test.dart -r expanded
```

- Last verified: 2026-05-23
```

- [ ] **Step 4: Run full validation**

Run:

```powershell
node scripts\run-tests.js
npm run lint
node scripts\check-project-knowledge.js
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\daemon_notification_client_test.dart test\coding_workbench_controller_test.dart -r expanded
```

Expected: all commands pass. If the first Flutter/Dart command times out, stop retrying automatically and ask the user to run the exact mirror-configured command manually.

- [ ] **Step 5: Commit**

```powershell
git add scripts\run-tests.js daemon\src\notification-hub.js mobile\lib\src\services\daemon_notification_client.dart mobile\lib\src\ui\features\workbench\view_models\workbench_view_model.dart mobile\test\daemon_notification_client_test.dart mobile\test\coding_workbench_controller_test.dart docs\project-knowledge\troubleshooting-playbook.md
git commit -m "Verify notification stream recovery"
```

---

## Final Verification

- [ ] Run daemon tests:

```powershell
node scripts\run-tests.js
```

- [ ] Run daemon lint:

```powershell
npm run lint
```

- [ ] Run project knowledge check:

```powershell
node scripts\check-project-knowledge.js
```

- [ ] Run Flutter architecture and analysis:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze lib test
```

- [ ] Run targeted Flutter tests:

```powershell
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\daemon_notification_client_test.dart test\coding_workbench_controller_test.dart -r expanded
```

- [ ] Check Git state:

```powershell
git status -sb
```

Expected: clean worktree after final commit, or only intentional uncommitted local artifacts.
