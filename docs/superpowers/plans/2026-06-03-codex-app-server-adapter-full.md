# Codex App-Server Adapter Full Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `codex-app-server` as a selectable conversation adapter with real app-server smoke gates, safe fallback to `codex exec --json`, generic mobile contracts, lifecycle controls, approval safety, diagnostics, and rollout switches.

**Architecture:** Implement in phases. Phase 1 captures real upstream app-server behavior and fixtures. Later phases add reusable transport/protocol helpers, adapter availability, side-effect-safe fallback, a production conversation adapter, provider session metadata, attachment conversion, approval handling, lifecycle management, metrics, and compatibility tests. The existing `codex` exec adapter remains unchanged and remains the fallback.

**Tech Stack:** Node.js daemon, CommonJS modules, existing `ConversationManager`, `AdapterRegistry`, `scripts/run-tests.js`, local upstream Codex checkout at `D:\GithubProject\codex`, Flutter/mobile only for compatibility tests if needed.

---

## Scope Rules

- Do not make `codex-app-server` the default Codex adapter in this plan.
- Do not add adapter-specific UI branches.
- Do not replay a user request through exec after `thread/start` or any other provider/project/thread side-effect boundary.
- Do not expose raw app-server provider payloads through normal mobile events.
- Keep `codex` exec behavior and tests stable.
- Keep every phase independently commit-sized and revertible.

## File Structure

- Create: `docs/superpowers/fixtures/codex-app-server/README.md`
- Create: `docs/superpowers/fixtures/codex-app-server/manifest.json`
- Create: `docs/superpowers/fixtures/codex-app-server/smoke-report-template.md`
- Create: `docs/superpowers/fixtures/codex-app-server/samples/.gitkeep`
- Create: `daemon/src/codex-app-server-availability.js`
  - Lightweight probe status, TTL cache shape, sanitized unavailable reasons.
- Create: `daemon/src/codex-app-server-transport.js`
  - JSON-RPC framing, request ids, timeouts, stdio/ws transport abstraction, pending request rejection.
- Create: `daemon/src/codex-app-server-lifecycle.js`
  - Child process ownership, limits, idle TTL, shutdown ladder, orphan cleanup metadata.
- Create: `daemon/src/codex-app-server-conversation-adapter.js`
  - Production conversation adapter and handle.
- Modify: `daemon/src/codex-app-server-bridge.js`
  - Adjust request/event mapping after real fixture comparison.
- Modify: `daemon/src/codex-app-server-approval.js`
  - Enforce safe approval defaults, idempotency, timeout policy, request-level capability derivation.
- Modify: `daemon/src/conversation-protocol.js`
  - Add `codex-app-server` to supported adapters and extend public conversation fields only if needed.
- Modify: `daemon/src/conversation-manager.js`
  - requested/effective adapter handling, fallback boundary, providerSession persistence, effectiveCapabilities/fallbackNotice, attachment lifetime.
- Modify: `daemon/src/adapter-registry.js`
  - Availability fields and effectiveCapabilities for adapter listing.
- Modify: `daemon/src/main.js`
  - Register `CodexAppServerConversationAdapter`, wire env flags.
- Modify: `daemon/src/app-sqlite-store.js`
  - Persist `requestedAdapter`, `effectiveAdapter`, `providerSession`, `fallbackNotice` if persistence requires schema support.
- Modify: `daemon/src/diagnostics.js` or nearest diagnostics service
  - Add app-server probe/lifecycle/approval counters to diagnostics output.
- Modify: `scripts/run-tests.js`
  - Add all daemon regression tests and fixture structural tests.
- Optional Modify: mobile data models/tests
  - Only if existing parsers reject added conversation fields.

---

### Task 1: Phase 1 Smoke Fixture Contract

**Files:**
- Create: `docs/superpowers/fixtures/codex-app-server/README.md`
- Create: `docs/superpowers/fixtures/codex-app-server/manifest.json`
- Create: `docs/superpowers/fixtures/codex-app-server/smoke-report-template.md`
- Create: `docs/superpowers/fixtures/codex-app-server/samples/.gitkeep`

- [x] **Step 1: Implement the fixture files**

Use the detailed plan in:

```text
docs/superpowers/plans/2026-06-03-codex-app-server-phase-1-smoke.md
```

- [x] **Step 2: Run project knowledge check**

Run:

```powershell
node scripts\check-project-knowledge.js
```

Expected:

```text
Project knowledge check passed
```

- [x] **Step 3: Commit**

```bash
git add -f docs/superpowers/fixtures/codex-app-server
git commit -m "Add app-server smoke fixture contract"
```

---

### Task 2: Run Phase 1 Real App-Server Smoke

**Files:**
- Modify: `docs/superpowers/fixtures/codex-app-server/manifest.json`
- Create: `docs/superpowers/fixtures/codex-app-server/smoke-report-<date>.md`
- Create: `docs/superpowers/fixtures/codex-app-server/samples/<date>-*.json`

- [x] **Step 1: Run the upstream smoke**

Follow the commands and thresholds in:

```text
docs/superpowers/plans/2026-06-03-codex-app-server-phase-1-smoke.md
```

- [x] **Step 2: Mark every manifest gate**

Set every `manifest.json.gates` value to one of:

```json
"pass"
"fail"
"blocked"
```

Expected:

```text
No gate remains "unknown"
```

- [x] **Step 3: Commit the evidence**

```bash
git add -f docs/superpowers/fixtures/codex-app-server
git commit -m "Capture app-server smoke evidence"
```

---

### Task 3: Add Fixture Structural Test

**Files:**
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Add the manifest test**

Append near existing adapter/fixture tests:

```javascript
test('Codex app-server smoke manifest has no unknown gates after Phase 1', () => {
  const manifestPath = path.join(
    __dirname,
    '..',
    'docs',
    'superpowers',
    'fixtures',
    'codex-app-server',
    'manifest.json'
  );
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.schemaVersion, 1);
  assert.ok(['pass', 'fail', 'blocked', 'not_run'].includes(manifest.status));
  if (manifest.status === 'not_run') return;
  for (const [gate, result] of Object.entries(manifest.gates || {})) {
    assert.ok(['pass', 'fail', 'blocked'].includes(result), `${gate} has invalid result ${result}`);
  }
});
```

- [x] **Step 2: Run tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

- [x] **Step 3: Commit**

```bash
git add scripts/run-tests.js
git commit -m "Check app-server smoke manifest"
```

---

### Task 4: Add Availability Model

**Files:**
- Create: `daemon/src/codex-app-server-availability.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write failing availability tests**

Add tests:

```javascript
test('Codex app-server availability marks disabled adapter unselectable', () => {
  const { buildCodexAppServerAvailability } = require('../daemon/src/codex-app-server-availability');
  const status = buildCodexAppServerAvailability({ enabled: false });
  assert.equal(status.installed, false);
  assert.equal(status.protocolCompatible, false);
  assert.equal(status.transportHealthy, false);
  assert.equal(status.selectable, false);
  assert.equal(status.effectiveCapabilities.approval.mobileCallbacks, false);
});

test('Codex app-server availability exposes sanitized selectable status', () => {
  const { buildCodexAppServerAvailability } = require('../daemon/src/codex-app-server-availability');
  const status = buildCodexAppServerAvailability({
    enabled: true,
    installed: true,
    protocolCompatible: true,
    transportHealthy: true,
    lastProbeAt: '2026-06-03T00:00:00.000Z'
  });
  assert.equal(status.selectable, true);
  assert.equal(status.unavailableReason, null);
  assert.equal(status.effectiveCapabilities.mobileApprovalCallbacks, true);
  assert.deepEqual(status.effectiveCapabilities.approval.scopes, ['once', 'session']);
});
```

- [x] **Step 2: Run tests to verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
FAIL because daemon/src/codex-app-server-availability.js does not exist
```

- [x] **Step 3: Implement availability module**

Create `daemon/src/codex-app-server-availability.js`:

```javascript
'use strict';

const unavailableCapabilities = Object.freeze({
  longLivedProcess: false,
  waitingInput: false,
  waitingApproval: false,
  resume: false,
  partialOutput: false,
  toolEvents: false,
  mobileApprovalCallbacks: false,
  approval: {
    mobileCallbacks: false,
    scopes: [],
    supportsCancel: false,
    denyBehaviors: []
  },
  attachments: {
    image: 'unsupported',
    textDocument: 'text_extract',
    pdf: 'unsupported'
  }
});

const targetCapabilities = Object.freeze({
  longLivedProcess: true,
  waitingInput: false,
  waitingApproval: true,
  resume: true,
  partialOutput: true,
  toolEvents: true,
  mobileApprovalCallbacks: true,
  approval: {
    mobileCallbacks: true,
    scopes: ['once', 'session'],
    supportsCancel: true,
    denyBehaviors: ['interrupt', 'continue']
  },
  attachments: {
    image: 'native',
    textDocument: 'text_extract',
    pdf: 'unsupported'
  }
});

function buildCodexAppServerAvailability(input = {}) {
  const installed = input.installed === true;
  const protocolCompatible = input.protocolCompatible === true;
  const transportHealthy = input.transportHealthy === true;
  const selectable = input.enabled === true && installed && protocolCompatible && transportHealthy;
  return {
    installed,
    protocolCompatible,
    transportHealthy,
    selectable,
    lastProbeAt: typeof input.lastProbeAt === 'string' ? input.lastProbeAt : null,
    unavailableReason: selectable ? null : sanitizedReason(input.unavailableReason || 'codex app-server is not selectable'),
    effectiveCapabilities: selectable ? clone(targetCapabilities) : clone(unavailableCapabilities)
  };
}

function sanitizedReason(value) {
  return String(value || 'codex app-server unavailable')
    .replace(/[A-Za-z]:\\Users\\[^\\\s]+/g, '<USER_HOME>')
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer <REDACTED_SECRET>');
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

module.exports = {
  buildCodexAppServerAvailability,
  unavailableCapabilities,
  targetCapabilities
};
```

- [x] **Step 4: Run tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

- [x] **Step 5: Commit**

```bash
git add daemon/src/codex-app-server-availability.js scripts/run-tests.js
git commit -m "Add app-server availability model"
```

---

### Task 5: Add JSON-RPC Transport

**Files:**
- Create: `daemon/src/codex-app-server-transport.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write failing transport tests**

Add tests:

```javascript
test('Codex app-server transport parses JSONL frames and resolves request ids', async () => {
  const { createCodexAppServerJsonRpcClient } = require('../daemon/src/codex-app-server-transport');
  const writes = [];
  const client = createCodexAppServerJsonRpcClient({
    writeLine: (line) => writes.push(line),
    now: () => new Date('2026-06-03T00:00:00.000Z')
  });
  const pending = client.request('model/list', {});
  assert.equal(JSON.parse(writes[0]).method, 'model/list');
  client.acceptLine(JSON.stringify({ id: 1, result: { models: [] } }));
  assert.deepEqual(await pending, { models: [] });
});

test('Codex app-server transport rejects pending requests on close', async () => {
  const { createCodexAppServerJsonRpcClient } = require('../daemon/src/codex-app-server-transport');
  const client = createCodexAppServerJsonRpcClient({ writeLine: () => {} });
  const pending = client.request('thread/start', {});
  client.close(new Error('transport closed'));
  await assert.rejects(pending, /transport closed/);
});
```

- [x] **Step 2: Run tests to verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
FAIL because daemon/src/codex-app-server-transport.js does not exist
```

- [x] **Step 3: Implement minimal transport**

Create `daemon/src/codex-app-server-transport.js`:

```javascript
'use strict';

function createCodexAppServerJsonRpcClient({ writeLine, onNotification = () => {}, onServerRequest = () => {}, now = () => new Date() } = {}) {
  if (typeof writeLine !== 'function') throw new Error('writeLine is required');
  let nextId = 1;
  let closed = false;
  const pending = new Map();
  return {
    request(method, params) {
      if (closed) return Promise.reject(new Error('transport closed'));
      const id = nextId++;
      const message = { id, method, params: params || {} };
      const promise = new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject, method, createdAt: now().toISOString() });
      });
      writeLine(JSON.stringify(message));
      return promise;
    },
    acceptLine(line) {
      if (closed) return;
      const message = JSON.parse(String(line));
      if (Object.prototype.hasOwnProperty.call(message, 'id') && (message.result || message.error)) {
        const item = pending.get(message.id);
        if (!item) return;
        pending.delete(message.id);
        if (message.error) item.reject(new Error(message.error.message || 'app-server request failed'));
        else item.resolve(message.result);
        return;
      }
      if (Object.prototype.hasOwnProperty.call(message, 'id') && message.method) {
        onServerRequest(message);
        return;
      }
      if (message.method) onNotification(message);
    },
    close(error = new Error('transport closed')) {
      closed = true;
      for (const item of pending.values()) item.reject(error);
      pending.clear();
    },
    pendingCount() {
      return pending.size;
    }
  };
}

module.exports = { createCodexAppServerJsonRpcClient };
```

- [x] **Step 4: Run tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

- [x] **Step 5: Commit**

```bash
git add daemon/src/codex-app-server-transport.js scripts/run-tests.js
git commit -m "Add app-server JSON-RPC transport"
```

---

### Task 6: Add Lifecycle Manager

**Files:**
- Create: `daemon/src/codex-app-server-lifecycle.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write lifecycle tests**

Add tests:

```javascript
test('Codex app-server lifecycle enforces process limit', async () => {
  const { CodexAppServerLifecycle } = require('../daemon/src/codex-app-server-lifecycle');
  const lifecycle = new CodexAppServerLifecycle({ maxProcesses: 1, spawnFn: () => ({ pid: 1, stdout: null, stderr: null, stdin: null, kill() {} }) });
  await lifecycle.start({ conversationId: 'one' });
  await assert.rejects(() => lifecycle.start({ conversationId: 'two' }), /process limit/);
});

test('Codex app-server lifecycle escalates dispose to kill', async () => {
  const killed = [];
  const child = { pid: 99, kill: (signal) => killed.push(signal) };
  const { CodexAppServerLifecycle } = require('../daemon/src/codex-app-server-lifecycle');
  const lifecycle = new CodexAppServerLifecycle({ maxProcesses: 1, spawnFn: () => child });
  const handle = await lifecycle.start({ conversationId: 'one' });
  await lifecycle.dispose(handle);
  assert.deepEqual(killed, ['SIGTERM']);
});
```

- [x] **Step 2: Implement lifecycle manager**

Create `daemon/src/codex-app-server-lifecycle.js`:

```javascript
'use strict';

const { spawn } = require('node:child_process');

class CodexAppServerLifecycle {
  constructor({ command = 'codex', spawnFn = spawn, maxProcesses = 1 } = {}) {
    this.command = command;
    this.spawnFn = spawnFn;
    this.maxProcesses = maxProcesses;
    this.active = new Map();
  }

  async start({ conversationId }) {
    if (this.active.size >= this.maxProcesses) throw new Error('codex app-server process limit reached');
    const child = this.spawnFn(this.command, ['app-server'], { windowsHide: true });
    const handle = { conversationId, child, sideEffectBoundaryCrossed: false };
    this.active.set(conversationId, handle);
    return handle;
  }

  async dispose(handle) {
    if (!handle) return;
    this.active.delete(handle.conversationId);
    if (handle.child && typeof handle.child.kill === 'function') handle.child.kill('SIGTERM');
  }
}

module.exports = { CodexAppServerLifecycle };
```

- [x] **Step 3: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/codex-app-server-lifecycle.js scripts/run-tests.js
git commit -m "Add app-server lifecycle guard"
```

---

### Task 7: Register Adapter Id And Feature Flags

**Files:**
- Modify: `daemon/src/conversation-protocol.js`
- Modify: `daemon/src/main.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write tests**

Add tests:

```javascript
test('conversation protocol accepts codex-app-server adapter id', () => {
  const { normalizeConversationCreate } = require('../daemon/src/conversation-protocol');
  const input = normalizeConversationCreate({ workspaceId: 'default', adapter: 'codex-app-server' });
  assert.equal(input.adapter, 'codex-app-server');
});
```

- [x] **Step 2: Modify protocol**

Change:

```javascript
const supportedConversationAdapters = Object.freeze(['claude', 'codex', 'opencode']);
```

to:

```javascript
const supportedConversationAdapters = Object.freeze(['claude', 'codex', 'codex-app-server', 'opencode']);
```

- [x] **Step 3: Wire flags in `main.js`**

Add config reads:

```javascript
codexAppServerEnabled = process.env.CODEX_APP_SERVER_ENABLED === '1',
codexAppServerTransport = process.env.CODEX_APP_SERVER_TRANSPORT || 'auto',
codexAppServerExperimentalApi = process.env.CODEX_APP_SERVER_EXPERIMENTAL_API === '1',
codexAppServerRolloutPercent = Number(process.env.CODEX_APP_SERVER_ROLLOUT_PERCENT || 0),
codexAppServerMaxProcesses = Number(process.env.CODEX_APP_SERVER_MAX_PROCESSES || 1),
```

Keep defaults disabled.

- [x] **Step 4: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/conversation-protocol.js daemon/src/main.js scripts/run-tests.js
git commit -m "Register app-server adapter id behind flags"
```

---

### Task 8: Add Conversation Fallback Fields

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/app-sqlite-store.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write tests**

Add tests:

```javascript
test('conversation exposes requested and effective adapter fields', () => {
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([['codex-app-server', { capabilities: {}, async startConversation() {} }]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex-app-server' }, device);
  assert.equal(conversation.adapter, 'codex-app-server');
  assert.equal(conversation.requestedAdapter, 'codex-app-server');
  assert.equal(conversation.effectiveAdapter, 'codex-app-server');
  assert.deepEqual(conversation.fallbackNotice, null);
});
```

- [x] **Step 2: Add fields to conversation object**

In `createConversation`, add:

```javascript
requestedAdapter: input.adapter,
effectiveAdapter: input.adapter,
effectiveCapabilities: adapter.capabilities || {},
fallbackNotice: null,
providerSession: null,
```

- [x] **Step 3: Add fields to `publicConversation`**

Return:

```javascript
requestedAdapter: conversation.requestedAdapter || conversation.adapter,
effectiveAdapter: conversation.effectiveAdapter || conversation.adapter,
effectiveCapabilities: conversation.effectiveCapabilities || conversation.capabilities || {},
fallbackNotice: conversation.fallbackNotice || null,
providerSession: conversation.providerSession || null,
```

- [x] **Step 4: Persist fields**

Update SQLite persistence to store these fields as JSON/text. If schema migration helpers exist in `app-sqlite-store.js`, add a migration. If not, add nullable columns guarded by existing migration style.

- [x] **Step 5: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/conversation-manager.js daemon/src/app-sqlite-store.js scripts/run-tests.js
git commit -m "Expose requested and effective conversation adapters"
```

---

### Task 9: Implement Side-Effect-Safe Fallback

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write fallback tests**

Add tests:

```javascript
test('codex-app-server falls back to codex before side-effect boundary', async () => {
  const events = [];
  const appServer = {
    capabilities: {},
    async startConversation() {
      const error = new Error('initialize failed');
      error.code = 'CODEX_APP_SERVER_UNAVAILABLE';
      error.sideEffectBoundaryCrossed = false;
      throw error;
    }
  };
  const codex = {
    capabilities: { mobileApprovalCallbacks: false },
    async startConversation({ onEvent }) {
      return { async sendUserMessage() { onEvent({ type: 'conversation.completed' }); } };
    }
  };
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([['codex-app-server', appServer], ['codex', codex]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex-app-server' }, device);
  await manager.sendMessage(conversation.id, { text: 'hello' }, device);
  const current = manager.getConversation(conversation.id, device);
  assert.equal(current.requestedAdapter, 'codex-app-server');
  assert.equal(current.effectiveAdapter, 'codex');
  assert.equal(current.fallbackNotice.noticeKind, 'adapter_fallback');
});

test('codex-app-server does not fall back after side-effect boundary', async () => {
  const appServer = {
    capabilities: {},
    async startConversation() {
      const error = new Error('thread/start failed after side effect');
      error.sideEffectBoundaryCrossed = true;
      throw error;
    }
  };
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([['codex-app-server', appServer], ['codex', { capabilities: {}, async startConversation() { throw new Error('must not fallback'); } }]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex-app-server' }, device);
  await assert.rejects(() => manager.sendMessage(conversation.id, { text: 'hello' }, device), /thread\/start failed/);
});
```

- [x] **Step 2: Implement fallback path**

In `ensureStarted` or the nearest startup path, catch app-server startup errors only when:

```javascript
conversation.requestedAdapter === 'codex-app-server' &&
conversation.effectiveAdapter === 'codex-app-server' &&
error.sideEffectBoundaryCrossed !== true
```

Then switch to `codex`, set `fallbackNotice`, and start the codex handle.

- [x] **Step 3: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Fallback app-server before side effects"
```

---

### Task 10: Implement App-Server Conversation Adapter Skeleton

**Files:**
- Create: `daemon/src/codex-app-server-conversation-adapter.js`
- Modify: `daemon/src/main.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write adapter skeleton tests**

Add tests:

```javascript
test('Codex app-server conversation adapter is unavailable when disabled', () => {
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const adapter = new CodexAppServerConversationAdapter({ enabled: false });
  const capability = adapter.detectCapabilities();
  assert.equal(adapter.name, 'codex-app-server');
  assert.equal(capability.selectable, false);
});
```

- [x] **Step 2: Implement skeleton**

Create:

```javascript
'use strict';

const { buildCodexAppServerAvailability } = require('./codex-app-server-availability');

class CodexAppServerConversationAdapter {
  constructor({ enabled = false, command = 'codex', transport = 'auto', experimentalApi = false, maxProcesses = 1 } = {}) {
    this.name = 'codex-app-server';
    this.displayName = 'Codex App Server';
    this.enabled = enabled;
    this.command = command;
    this.transport = transport;
    this.experimentalApi = experimentalApi;
    this.maxProcesses = maxProcesses;
    this.capability = null;
    this.capabilities = buildCodexAppServerAvailability({ enabled: false }).effectiveCapabilities;
  }

  detectCapabilities() {
    this.capability = buildCodexAppServerAvailability({
      enabled: this.enabled,
      installed: false,
      protocolCompatible: false,
      transportHealthy: false,
      unavailableReason: this.enabled ? 'codex app-server probe is not implemented' : 'codex app-server disabled'
    });
    this.capabilities = this.capability.effectiveCapabilities;
    return {
      adapter: this.name,
      available: this.capability.selectable,
      status: this.capability.selectable ? 'available' : 'unavailable',
      displayName: this.displayName,
      ...this.capability,
      capabilities: this.capability.effectiveCapabilities
    };
  }

  async startConversation() {
    const error = new Error('Codex app-server adapter is unavailable');
    error.status = 503;
    error.code = 'CODEX_APP_SERVER_UNAVAILABLE';
    error.sideEffectBoundaryCrossed = false;
    throw error;
  }
}

module.exports = { CodexAppServerConversationAdapter };
```

- [x] **Step 3: Register in `main.js`**

Add import and register in `createConversationAdapters`.

- [x] **Step 4: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/codex-app-server-conversation-adapter.js daemon/src/main.js scripts/run-tests.js
git commit -m "Add app-server conversation adapter shell"
```

---

### Task 11: Implement Real Initialize And Probe

**Files:**
- Modify: `daemon/src/codex-app-server-conversation-adapter.js`
- Modify: `daemon/src/codex-app-server-lifecycle.js`
- Modify: `daemon/src/codex-app-server-transport.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write probe tests with fake child transport**

Test selectable true only when fake initialize succeeds and no side-effect request is sent.

- [x] **Step 2: Implement lightweight probe**

Probe sequence:

```text
spawn app-server transport
send initialize
send initialized notification
optionally send stable non-thread capability request proven by Phase 1
close transport
return availability
```

Do not send:

```text
thread/start
thread/resume
turn/start
```

- [x] **Step 3: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/codex-app-server-conversation-adapter.js daemon/src/codex-app-server-lifecycle.js daemon/src/codex-app-server-transport.js scripts/run-tests.js
git commit -m "Probe app-server without side effects"
```

---

### Task 12: Implement Thread And Turn Flow

**Files:**
- Modify: `daemon/src/codex-app-server-conversation-adapter.js`
- Modify: `daemon/src/codex-app-server-bridge.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write fake fixture-driven tests**

Use sanitized Phase 1 samples to test:

```text
thread/start -> providerSession.threadId
turn/start -> turn active
turn/completed -> conversation.completed or mapped reusable state
turn/interrupted -> conversation.cancelled
turn/failed -> run.error
```

- [x] **Step 2: Implement `CodexAppServerConversationHandle`**

Required methods:

```javascript
async sendUserMessage(message) {}
async respondApproval(approvalId, decision) {}
async cancel() {}
async dispose() {}
```

- [x] **Step 3: Set side-effect boundary before sending `thread/start`**

Before writing `thread/start` to transport:

```javascript
this.sideEffectBoundaryCrossed = true;
```

- [x] **Step 4: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/codex-app-server-conversation-adapter.js daemon/src/codex-app-server-bridge.js scripts/run-tests.js
git commit -m "Run app-server thread and turn flow"
```

---

### Task 13: Implement Approval Flow

**Files:**
- Modify: `daemon/src/codex-app-server-approval.js`
- Modify: `daemon/src/codex-app-server-conversation-adapter.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write tests for safe defaults**

Cover:

```text
unknown approval request -> no UI, reject provider, run.error
timeout -> cancel if available, else decline, else JSON-RPC error
duplicate same response -> idempotent stored result
duplicate different response -> conflict
cancel unavailable -> supportsCancel false
session scope absent -> supportsSessionScope false
```

- [x] **Step 2: Implement approval pending map**

Use key:

```text
approvalId/requestId
```

Store:

```text
context
resolvedResponse
createdAt
timeout
```

- [x] **Step 3: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/codex-app-server-approval.js daemon/src/codex-app-server-conversation-adapter.js scripts/run-tests.js
git commit -m "Handle app-server approvals safely"
```

---

### Task 14: Implement Provider Session Persistence

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/app-sqlite-store.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write persistence tests**

Test restored conversation preserves:

```json
{
  "provider": "codex-app-server",
  "threadId": "thread_1",
  "protocolVersion": "v2",
  "cwd": "D:\\Repo",
  "model": "gpt-5.4",
  "sandboxProfile": "workspace-write",
  "createdAt": "2026-06-03T00:00:00.000Z"
}
```

- [x] **Step 2: Persist providerSession**

Add JSON storage following existing capabilities JSON patterns.

- [x] **Step 3: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/conversation-manager.js daemon/src/app-sqlite-store.js scripts/run-tests.js
git commit -m "Persist app-server provider sessions"
```

---

### Task 15: Implement Attachment Contract

**Files:**
- Modify: `daemon/src/codex-app-server-conversation-adapter.js`
- Modify: `daemon/src/conversation-manager.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write attachment tests**

Cover:

```text
textDocument -> text wrapper -> app-server UserInput text
native image -> localImage input if Phase 1 proved support
pdf unsupported -> rejected before thread/start/turn/start
fallback to codex -> effectiveCapabilities attachments switch to codex
```

- [x] **Step 2: Implement conversion**

Use existing `buildAdapterUserMessage()` behavior and app-server `UserInput` helper.

- [x] **Step 3: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/codex-app-server-conversation-adapter.js daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Map attachments into app-server input"
```

---

### Task 16: Add Diagnostics And Metrics

**Files:**
- Modify: nearest diagnostics service under `daemon/src/diagnostics.js`
- Modify: `daemon/src/codex-app-server-conversation-adapter.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write diagnostics tests**

Assert diagnostics expose sanitized counters:

```text
app_server_probe_success
app_server_probe_failure
app_server_spawn_failure
app_server_initialize_latency
fallback_before_first_request_count
run_error_after_side_effect_boundary_count
approval_requested_count
approval_timeout_count
approval_round_trip_latency
transport_close_count
orphan_process_cleanup_count
```

- [x] **Step 2: Implement metric increments**

Keep raw provider payloads out of metrics.

- [x] **Step 3: Run tests and commit**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

```bash
git add daemon/src/diagnostics.js daemon/src/codex-app-server-conversation-adapter.js scripts/run-tests.js
git commit -m "Report app-server adapter diagnostics"
```

---

### Task 17: Add Mobile Compatibility Tests

**Files:**
- Modify: `mobile/test/protocol_compatibility_test.dart`
- Modify: mobile data models only if tests fail

- [x] **Step 1: Write compatibility test**

Add a test that parses a conversation containing:

```json
{
  "adapter": "codex-app-server",
  "requestedAdapter": "codex-app-server",
  "effectiveAdapter": "codex",
  "effectiveCapabilities": {
    "mobileApprovalCallbacks": false,
    "approval": {
      "mobileCallbacks": false,
      "scopes": [],
      "supportsCancel": false,
      "denyBehaviors": []
    }
  },
  "fallbackNotice": {
    "noticeKind": "adapter_fallback",
    "requestedAdapter": "codex-app-server",
    "effectiveAdapter": "codex"
  }
}
```

- [x] **Step 2: Run targeted Flutter test**

Run from `mobile`:

```powershell
flutter test --no-pub test\protocol_compatibility_test.dart
```

Expected:

```text
All tests pass
```

- [x] **Step 3: Fix model parsing only if needed**

If parsing fails, update only data model fields necessary to ignore or preserve the new daemon fields.

- [x] **Step 4: Commit**

```bash
git add mobile/test/protocol_compatibility_test.dart mobile/lib/src/data/models
git commit -m "Accept app-server fallback conversation fields"
```

---

### Task 18: Final Verification

**Files:**
- No new files unless verification reveals a bug.

- [x] **Step 1: Run daemon tests**

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests pass
```

- [x] **Step 2: Run lint**

```powershell
npm run lint
```

Expected:

```text
No JavaScript lint failures
```

- [x] **Step 3: Run project knowledge check**

```powershell
node scripts\check-project-knowledge.js
```

Expected:

```text
Project knowledge check passed
```

- [x] **Step 4: Run mobile compatibility test if mobile changed**

```powershell
cd mobile
flutter test --no-pub test\protocol_compatibility_test.dart
```

Expected:

```text
All tests pass
```

- [x] **Step 5: Inspect git status**

```powershell
git status --short --branch
```

Expected:

```text
No unstaged or untracked implementation files
```

## Final Handoff

Implementation is complete only when:

- Phase 1 manifest gates are not unknown;
- app-server is selectable only when probes pass;
- fallback is impossible after `thread/start`;
- existing `codex` exec tests pass unchanged;
- approval defaults fail closed;
- process lifecycle tests cover cleanup;
- diagnostics expose sanitized app-server metrics;
- mobile compatibility tests pass or mobile is unchanged because it already ignores new fields.
