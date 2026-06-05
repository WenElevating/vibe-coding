# Codex App-Server Full API Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement product-grade daemon support for every official Codex app-server API method currently present in the committed schema, then add mobile consumption for the stable user-facing surfaces.

**Architecture:** Keep the schema fixture and capability matrix as the source of truth, but expose official methods only through typed daemon services and typed HTTP routes. App-server process reuse is physically separated by pool: passive discovery, active conversation, and mutation/high-risk operations do not share process handles. High-risk file/process/config/remote-control mutations require workspace authorization, explicit mobile approval or product policy authorization, controlled errors, and audit records. Mobile UI is the final phase, after daemon DTOs and tests are stable.

**Tech Stack:** Node.js CommonJS daemon, `CodexAppServerClient`, `CodexAppServerLifecycle`, JSON-RPC over stdio, `scripts/run-tests.js`, `npm run lint`, Flutter/Dart mobile repositories and ViewModels for the final phase.

---

## Current Baseline

Already supported by the Phase 1/2 foundation:

- Lifecycle: `initialize`, `initialized`
- Models: `model/list`
- Conversation thread/turn runtime: `thread/start`, `thread/resume`, `turn/start`, `turn/interrupt`
- Conversation notifications: `thread/started`, `turn/started`, `turn/completed`, `error`
- Streaming item notifications: `item/agentMessage/delta`, `item/commandExecution/outputDelta`
- Approval server requests: `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval`
- Partial notifications: `item/started`, `item/completed`, `turn/plan/updated`

Remaining official methods are currently `unsupported` in `daemon/src/codex-app-server/capability-matrix.js`. This plan moves them to one of:

- `supported`: implemented behind typed daemon APIs, tests, and risk controls.
- `partial`: consumed safely but not all schema variants are productized yet.
- `diagnostic-only`: exposed only in authenticated diagnostics routes with no mutation.
- `intentionally-blocked`: officially known but blocked for product/security reasons, with tests proving the block.

## Non-Negotiable Product Rules

- Do not add a raw arbitrary JSON-RPC route.
- Every route must authenticate the paired device before calling app-server.
- Every workspace-scoped route must resolve `workspaceId` through `WorkspaceRegistry.getAuthorized()`.
- App-server must receive the registry-resolved workspace root, never a client-provided path; relative paths must normalize inside that root before any app-server call.
- Every high-risk method must have a risk classification other than `unknown`, an audit record, and a controlled error path.
- Mutating file/process/config/account/remote-control operations must not share a passive discovery client.
- Conversation streaming deltas must remain unfiltered and uncompressed.
- Dense partial streams still need bounded persistence retention, replay windowing, and WebSocket backpressure; "do not filter" is not permission for unbounded daemon memory growth.
- Route capability metadata must be derived from the capability matrix; do not create a second handwritten source for mobile visibility.
- Account reads are sensitive reads and must be authenticated plus DTO-redacted, even when they are read-only.
- The app-server path must have a runtime kill-switch and basic spawn/cache/latency/error metrics before broad route rollout.
- High-risk and thread-mutation audits are append-only app SQLite records retained for at least 90 days with device id, workspace id, method, risk, decision, result, redacted error, and correlation id.
- Mobile UI work must stay feature-local; do not add new files under retired `mobile/lib/src/features`, `mobile/lib/src/widgets`, `mobile/lib/src/theme`, or `mobile/lib/src/state`.
- Keep schema drift checks strict: a changed official method surface must fail tests until the matrix and route plan are updated.

## File Structure

Create:

- `daemon/src/codex-app-server/service.js`
  - Owns process-scoped app-server clients for daemon routes.
  - Provides `withDiscoveryClient()`, `withWorkspaceClient()`, and `withMutationClient()`.
  - Implements physically separated discovery, conversation, and mutation pools; only the discovery pool uses TTL reuse.
  - Emits spawn/cache/latency/error metrics and evicts immediately on transport close.
- `daemon/src/codex-app-server/timeouts.js`
  - Classifies methods as instant RPC, long-lived stream, or inbound server request.
  - Prevents long turns and approval server requests from sharing one blunt method timeout.
- `daemon/src/codex-app-server/capability-routes.js`
  - Derives route metadata from capability matrix rows for mobile and diagnostics.
- `daemon/src/codex-app-server/streaming-policy.js`
  - Defines partial-event retention, replay window, and WebSocket backpressure constants used by tests.
- `daemon/src/codex-app-server/routes.js`
  - Registers `/api/codex-app-server/*` routes and delegates to typed services.
  - Keeps `server.js` small by exporting `tryHandleCodexAppServerRoute(context)`.
- `daemon/src/codex-app-server/dtos.js`
  - Normalizes official app-server responses into stable daemon DTOs.
  - Keeps raw official payloads only in `diagnostics.raw` fields where explicitly allowed.
- `daemon/src/codex-app-server/risk-policy.js`
  - Maps method names to `none`, `read`, `write`, `process`, `account`, `network`, `permission`, or temporary `unknown`.
  - Provides route guard helpers for read-only, workspace-scoped, and high-risk calls.
  - Keeps `process` and `marketplace` as machine categories when syncing matrix rows; do not collapse them into `command` or `plugin`.
- `daemon/src/codex-app-server/audit.js`
  - Centralizes audit record shape for app-server operations.
- `daemon/src/codex-app-server/high-risk-approval.js`
  - Reuses the existing blocking approval model for daemon routes that require mobile authorization.
- `daemon/test/fixtures/codex-app-server/responses/*.json`
  - Stable representative app-server responses for thread, discovery, config, process, fs, plugin, skill, account, sandbox, and remote-control routes.
- `mobile/lib/src/data/models/codex_app_server_models.dart`
  - Mobile DTOs for user-facing app-server discovery/history surfaces.
- `mobile/lib/src/data/repositories/codex_app_server_repository.dart`
  - Mobile repository for daemon app-server routes.
- `mobile/lib/src/domain/repositories/codex_app_server_repository.dart`
  - Domain abstraction used by mobile ViewModels.
- `mobile/lib/src/ui/features/codex_app_server/`
  - Feature-local UI for app-server history, discovery, account/config status, and operation approvals.

Modify:

- `daemon/src/codex-app-server/client.js`
  - Add typed helpers for every official client request method.
- `daemon/src/codex-app-server/capability-matrix.js`
  - Update rows as each API group becomes supported, partial, diagnostic-only, or intentionally-blocked.
- `daemon/src/main.js`
  - Construct `CodexAppServerService` and pass it into `createServer`.
  - Accept an optional `codexAppServerService` override in `createApp()` so route tests can inject a fake service before `server.js` captures route context.
- `daemon/src/server.js`
  - Delegate `/api/codex-app-server/*` to `routes.js` before falling through to `not found`.
- `scripts/run-tests.js`
  - Add fake transport tests, route tests, auth tests, workspace authorization tests, audit tests, and matrix status tests.
- `mobile/lib/src/services/conversation_client.dart`
  - Add typed route calls only after daemon routes are stable.
- `mobile/lib/src/app/app_dependencies.dart`
  - Wire mobile repository dependencies in the composition root.

## Test Harness Contract

Early daemon tasks must add one reusable route-test helper in `scripts/run-tests.js` and all later route tests must use it:

```javascript
async function createCodexAppServerRouteTestApp({ service = {}, workspace = null, auditLog = null } = {}) {
  const app = createApp({
    port: 0,
    appDbPath: tempConversationDbPath('app-server-route-'),
    codexAppServerProbe: false,
    codexAppServerModelLister: false,
    codexAppServerService: service,
    auditLog
  });
  const effectiveWorkspace = workspace || app.workspaces.add({ name: 'Repo', path: process.cwd() }, { id: 'owner', allowedWorkspaceIds: new Set() });
  const pair = app.auth.createPairingCode();
  const deviceId = `device_${Math.random().toString(16).slice(2)}`;
  const paired = app.auth.pair(pair.code, 'app-server-route', deviceId);
  app.auth.allowWorkspace(deviceId, effectiveWorkspace.id);
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const headers = { authorization: `Bearer ${paired.accessToken}` };
  const send = (httpMethod, route, body) => request(app.server.address().port, httpMethod, route, body, headers);
  return {
    app,
    workspace: effectiveWorkspace,
    get: (route) => send('GET', route),
    post: (route, body) => send('POST', route, body),
    patch: (route, body) => send('PATCH', route, body),
    delete: (route, body) => send('DELETE', route, body),
    close: async () => {
      app.server.close();
      app.appSqliteStore.close();
    }
  };
}
```

This helper depends on Task 1 adding a `createApp({ codexAppServerService })` injection point. Do not set `app.codexAppServerService` after `createApp()`; `server.js` captures the service value at construction time.

---

### Task 1: App-Server Route Service, Process Isolation, And Timeout Foundation

**Files:**
- Create: `daemon/src/codex-app-server/service.js`
- Create: `daemon/src/codex-app-server/risk-policy.js`
- Create: `daemon/src/codex-app-server/timeouts.js`
- Modify: `daemon/src/main.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing service lifecycle tests**

Add these tests near the existing app-server tests in `scripts/run-tests.js`:

```javascript
test('Codex app-server service reuses healthy read-only discovery client within TTL', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  const spawned = [];
  const service = new CodexAppServerService({
    ttlMs: 30000,
    lifecycle: {
      spawn() {
        const transport = new EventEmitter();
        transport.requests = [];
        transport.sendRequest = async (method) => {
          transport.requests.push(method);
          if (method === 'initialize') return {};
          if (method === 'model/list') return { data: [] };
          throw new Error(`unexpected ${method}`);
        };
        transport.sendNotification = () => {};
        const handle = { transport, shutdown: async () => { handle.shutdownCalled = true; } };
        spawned.push(handle);
        return handle;
      }
    },
    now: (() => {
      let value = 1000;
      return () => value;
    })()
  });

  await service.withDiscoveryClient((client) => client.listModels());
  await service.withDiscoveryClient((client) => client.listModels());

  assert.equal(spawned.length, 1);
  assert.deepEqual(spawned[0].transport.requests, ['initialize', 'model/list', 'model/list']);
});

test('Codex app-server service evicts discovery client on transport close', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  const spawned = [];
  const service = new CodexAppServerService({
    ttlMs: 30000,
    lifecycle: {
      spawn() {
        const transport = new EventEmitter();
        transport.sendRequest = async (method) => method === 'initialize' ? {} : { data: [] };
        transport.sendNotification = () => {};
        const handle = { transport, shutdown: async () => {} };
        spawned.push(handle);
        return handle;
      }
    }
  });

  await service.withDiscoveryClient((client) => client.listModels());
  spawned[0].transport.emit('closed', new Error('closed'));
  await service.withDiscoveryClient((client) => client.listModels());

  assert.equal(spawned.length, 2);
});

test('Codex app-server service does not reuse mutation clients', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  let spawnCount = 0;
  const service = new CodexAppServerService({
    lifecycle: {
      spawn() {
        spawnCount += 1;
        const transport = new EventEmitter();
        transport.sendRequest = async () => ({});
        transport.sendNotification = () => {};
        return { transport, shutdown: async () => {} };
      }
    }
  });

  await service.withMutationClient({ method: 'config/value/write' }, async () => {});
  await service.withMutationClient({ method: 'config/value/write' }, async () => {});

  assert.equal(spawnCount, 2);
});

test('Codex app-server service never shares discovery, conversation, and mutation pools', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  const spawned = [];
  const service = new CodexAppServerService({
    lifecycle: {
      spawn(scope) {
        const transport = new EventEmitter();
        transport.sendRequest = async (method) => method === 'initialize' ? {} : { ok: true };
        transport.sendNotification = () => {};
        const handle = { scope, transport, shutdown: async () => {} };
        spawned.push(handle);
        return handle;
      }
    }
  });

  await service.withDiscoveryClient((client) => client.listModels());
  await service.withConversationClient({ threadId: 'thread_1' }, async () => {});
  await service.withMutationClient({ method: 'fs/writeFile' }, async () => {});

  assert.deepEqual(spawned.map((handle) => handle.scope.pool), ['discovery', 'conversation', 'mutation']);
});

test('Codex app-server method timeout classes distinguish streams and server requests', () => {
  const { classifyCodexAppServerTimeout } = require('../daemon/src/codex-app-server/timeouts');
  assert.equal(classifyCodexAppServerTimeout('model/list').kind, 'instant-rpc');
  assert.equal(classifyCodexAppServerTimeout('turn/start').kind, 'long-lived-stream');
  assert.equal(classifyCodexAppServerTimeout('item/commandExecution/requestApproval').kind, 'inbound-server-request');
});

test('Codex app-server service returns controlled busy errors when pools are exhausted', async () => {
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  const service = new CodexAppServerService({
    poolLimits: { discovery: 0, conversation: 0, mutation: 0 },
    lifecycle: { spawn() { throw new Error('must not spawn when pool is full'); } }
  });

  await assert.rejects(
    () => service.withDiscoveryClient(async () => {}),
    (error) => error.code === 'CODEX_APP_SERVER_BUSY'
  );
  await assert.rejects(
    () => service.withConversationClient({ threadId: 'thread_1' }, async () => {}),
    (error) => error.code === 'CODEX_APP_SERVER_BUSY'
  );
  await assert.rejects(
    () => service.withMutationClient({ method: 'fs/writeFile' }, async () => {}),
    (error) => error.code === 'CODEX_APP_SERVER_BUSY'
  );
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
Cannot find module '../daemon/src/codex-app-server/service'
```

- [ ] **Step 3: Implement `risk-policy.js`**

Create `daemon/src/codex-app-server/risk-policy.js`:

```javascript
'use strict';

const HIGH_RISK_METHODS = new Set([
  'command/exec',
  'command/exec/resize',
  'command/exec/terminate',
  'command/exec/write',
  'config/batchWrite',
  'config/value/write',
  'environment/add',
  'fs/copy',
  'fs/createDirectory',
  'fs/remove',
  'fs/unwatch',
  'fs/watch',
  'fs/writeFile',
  'marketplace/add',
  'marketplace/remove',
  'marketplace/upgrade',
  'memory/reset',
  'plugin/install',
  'plugin/installed',
  'plugin/share/checkout',
  'plugin/share/delete',
  'plugin/share/save',
  'plugin/share/updateTargets',
  'plugin/uninstall',
  'process/kill',
  'process/resizePty',
  'process/spawn',
  'process/writeStdin',
  'remoteControl/client/revoke',
  'remoteControl/disable',
  'remoteControl/enable',
  'remoteControl/pairing/start',
  'skills/config/write',
  'skills/extraRoots/set',
  'thread/archive',
  'thread/backgroundTerminals/clean',
  'thread/compact/start',
  'thread/fork',
  'thread/goal/clear',
  'thread/goal/set',
  'thread/inject_items',
  'thread/memoryMode/set',
  'thread/metadata/update',
  'thread/name/set',
  'thread/realtime/appendAudio',
  'thread/realtime/appendText',
  'thread/realtime/start',
  'thread/realtime/stop',
  'thread/rollback',
  'thread/settings/update',
  'thread/shellCommand',
  'thread/unarchive',
  'turn/steer'
]);

function riskForCodexAppServerMethod(method) {
  const value = String(method || '');
  if (HIGH_RISK_METHODS.has(value)) {
    if (value.startsWith('fs/')) return 'write';
    if (value.startsWith('command/') || value.startsWith('process/')) return 'process';
    if (value.startsWith('remoteControl/')) return 'network';
    if (value.startsWith('config/') || value.startsWith('skills/') || value.startsWith('plugin/') || value.startsWith('marketplace/')) return 'write';
    return 'write';
  }
  if (value.startsWith('account/') || value.includes('login') || value.includes('logout')) return 'account';
  if (value.includes('oauth')) return 'account';
  if (value.startsWith('mcpServer/tool/call') || value === 'item/tool/call') return 'permission';
  return 'read';
}

function isHighRiskCodexAppServerMethod(method) {
  return HIGH_RISK_METHODS.has(String(method || '')) ||
    ['process', 'write', 'network'].includes(riskForCodexAppServerMethod(method));
}

module.exports = {
  isHighRiskCodexAppServerMethod,
  riskForCodexAppServerMethod
};
```

- [ ] **Step 4: Implement `service.js`**

Create `daemon/src/codex-app-server/service.js`:

```javascript
'use strict';

const { CodexAppServerClient } = require('./client');
const { isHighRiskCodexAppServerMethod } = require('./risk-policy');

class CodexAppServerService {
  constructor({ lifecycle, ttlMs = 30000, initializeTimeoutMs = 10000, requestTimeoutMs = 30000, now = () => Date.now() } = {}) {
    this.lifecycle = lifecycle;
    this.ttlMs = Math.max(0, Number(ttlMs) || 0);
    this.initializeTimeoutMs = Math.max(1, Number(initializeTimeoutMs) || 10000);
    this.requestTimeoutMs = Math.max(1, Number(requestTimeoutMs) || 30000);
    this.now = now;
    this.discovery = null;
  }

  async withDiscoveryClient(callback) {
    const scoped = await this.getDiscoveryClient();
    return callback(scoped.client);
  }

  async withWorkspaceClient(_workspace, callback) {
    const scoped = await this.createScopedClient();
    try {
      return await callback(scoped.client);
    } finally {
      await scoped.shutdown();
    }
  }

  async withMutationClient({ method }, callback) {
    if (!isHighRiskCodexAppServerMethod(method)) {
      const scoped = await this.createScopedClient();
      try {
        return await callback(scoped.client);
      } finally {
        await scoped.shutdown();
      }
    }
    const scoped = await this.createScopedClient();
    try {
      return await callback(scoped.client);
    } finally {
      await scoped.shutdown();
    }
  }

  async getDiscoveryClient() {
    if (this.discovery && this.discovery.expiresAt > this.now() && !this.discovery.client.invalidated) {
      return this.discovery;
    }
    await this.evictDiscovery();
    const scoped = await this.createScopedClient();
    scoped.expiresAt = this.now() + this.ttlMs;
    if (typeof scoped.handle.transport.on === 'function') {
      scoped.handle.transport.on('closed', () => {
        if (this.discovery === scoped) this.discovery = null;
      });
    }
    this.discovery = scoped;
    return scoped;
  }

  async createScopedClient() {
    if (!this.lifecycle || typeof this.lifecycle.spawn !== 'function') {
      const error = new Error('Codex app-server lifecycle is not configured');
      error.status = 503;
      error.code = 'CODEX_APP_SERVER_LIFECYCLE_MISSING';
      throw error;
    }
    const handle = this.lifecycle.spawn({ pool: 'discovery' });
    const client = new CodexAppServerClient({
      transport: handle.transport,
      initializeTimeoutMs: this.initializeTimeoutMs,
      requestTimeoutMs: this.requestTimeoutMs
    });
    await client.initialize();
    return {
      handle,
      client,
      expiresAt: 0,
      shutdown: async () => {
        if (handle && typeof handle.shutdown === 'function') await handle.shutdown();
      }
    };
  }

  async evictDiscovery() {
    const scoped = this.discovery;
    this.discovery = null;
    if (scoped) await scoped.shutdown();
  }

  async close() {
    await this.evictDiscovery();
  }
}

module.exports = {
  CodexAppServerService
};
```

Before running the tests, update the service implementation so:

- `createScopedClient(scope)` passes `scope` to `lifecycle.spawn(scope)`.
- `withDiscoveryClient()` calls `createScopedClient({ pool: 'discovery' })` and is the only path that caches by TTL.
- `withWorkspaceClient(workspace, callback)` calls `createScopedClient({ pool: 'discovery', workspaceId: workspace.id })` for read-only route calls.
- `withConversationClient(conversationScope, callback)` calls `createScopedClient({ pool: 'conversation', ...conversationScope })` and never uses the discovery cache.
- `withMutationClient({ method }, callback)` calls `createScopedClient({ pool: 'mutation', method })` and never uses the discovery cache, even for repeated requests.
- Default pool limits are discovery 2 per invocation key, conversation `CODEX_APP_SERVER_MAX_PROCESSES || 4`, and mutation 1 per workspace. Pool exhaustion returns `CODEX_APP_SERVER_BUSY`; conversation exhaustion may fall back to CLI only before the provider side-effect boundary.
- Metrics hooks record `codex_app_server_process_spawn_total`, discovery cache hit/miss, eviction reason, per-method latency, and per-method errors. The first implementation can use the existing diagnostics collector shape rather than adding a new metrics dependency.

- [ ] **Step 5: Implement `timeouts.js`**

Create `daemon/src/codex-app-server/timeouts.js`:

```javascript
'use strict';

const LONG_LIVED_STREAM_METHODS = new Set([
  'thread/start',
  'thread/resume',
  'turn/start',
  'thread/realtime/start',
  'thread/realtime/appendAudio',
  'thread/realtime/appendText',
  'command/exec',
  'process/spawn'
]);

const INBOUND_SERVER_REQUEST_METHODS = new Set([
  'item/commandExecution/requestApproval',
  'item/fileChange/requestApproval',
  'item/permissions/requestApproval',
  'item/tool/requestUserInput',
  'mcpServer/elicitation/request',
  'account/chatgptAuthTokens/refresh'
]);

function classifyCodexAppServerTimeout(method) {
  const value = String(method || '');
  if (INBOUND_SERVER_REQUEST_METHODS.has(value)) {
    return { kind: 'inbound-server-request', timeoutMs: 120000 };
  }
  if (LONG_LIVED_STREAM_METHODS.has(value)) {
    return { kind: 'long-lived-stream', startupTimeoutMs: 30000, idleTimeoutMs: 300000, heartbeatTimeoutMs: 60000 };
  }
  return { kind: 'instant-rpc', timeoutMs: 30000 };
}

module.exports = {
  classifyCodexAppServerTimeout
};
```

- [ ] **Step 6: Wire service from `main.js`**

In `daemon/src/main.js`, import:

```javascript
const { CodexAppServerService } = require('./codex-app-server/service');
```

Add `codexAppServerService = undefined` to the `createApp()` options. After `codexAppServerLifecycle` is created, add:

```javascript
  const effectiveCodexAppServerService = codexAppServerService !== undefined
    ? codexAppServerService
    : codexAppServerEnabled
    ? new CodexAppServerService({
      lifecycle: codexAppServerLifecycle,
      ttlMs: 30000
    })
    : null;
```

Update `createServer(...)` call:

```javascript
  const server = createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, slashCommandCatalog, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset, appUpdates, codexAppServerService: effectiveCodexAppServerService, auditLog });
```

Update the returned app object to include:

```javascript
codexAppServerService: effectiveCodexAppServerService
```

- [ ] **Step 7: Run service tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
tests passed
```

- [ ] **Step 8: Commit**

```bash
git add daemon/src/codex-app-server/service.js daemon/src/codex-app-server/risk-policy.js daemon/src/codex-app-server/timeouts.js daemon/src/main.js scripts/run-tests.js
git commit -m "Add Codex app-server route service foundation"
```

---

### Task 2: Route Dispatcher, Error Shape, And Capability Metadata

**Files:**
- Create: `daemon/src/codex-app-server/capability-routes.js`
- Create: `daemon/src/codex-app-server/routes.js`
- Create: `daemon/src/codex-app-server/dtos.js`
- Modify: `daemon/src/server.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing authenticated route tests**

Add tests:

```javascript
test('Codex app-server routes require authentication', async () => {
  const app = createApp({
    port: 0,
    codexAppServerProbe: false,
    codexAppServerModelLister: false,
    appDbPath: tempConversationDbPath('app-server-auth-')
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const response = await request(port, 'GET', '/api/codex-app-server/capabilities');
    assert.equal(response.status, 401);
  } finally {
    app.server.close();
    app.appSqliteStore.close();
  }
});

test('Codex app-server capabilities route returns matrix and route metadata', async () => {
  const app = createApp({
    port: 0,
    codexAppServerProbe: false,
    codexAppServerModelLister: false,
    appDbPath: tempConversationDbPath('app-server-capabilities-')
  });
  const pair = app.auth.createPairingCode();
  const paired = app.auth.pair(pair.code, 'test', 'device_capabilities');
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const response = await request(port, 'GET', '/api/codex-app-server/capabilities', null, {
      authorization: `Bearer ${paired.accessToken}`
    });
    assert.equal(response.status, 200);
    assert.ok(response.body.capabilityMatrix.totalMethods > 0);
    assert.equal(response.body.routes.some((route) => route.group === 'history' && route.readOnly), true);
    assert.equal(response.body.routes.some((route) => route.requiresApproval), true);
    assert.equal(response.body.routes.every((route) => route.source === 'capability-matrix'), true);
  } finally {
    app.server.close();
    app.appSqliteStore.close();
  }
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
404
```

- [ ] **Step 3: Implement matrix-derived route capability metadata**

Create `daemon/src/codex-app-server/capability-routes.js`:

```javascript
'use strict';

const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('./capability-matrix');

function buildCodexAppServerRouteCapabilities() {
  return CODEX_APP_SERVER_CAPABILITY_MATRIX
    .filter((row) => row.daemonOwner === 'server route' || row.mobileStatus === 'planned' || row.mobileStatus === 'consumed')
    .map((row) => ({
      method: row.method,
      group: routeGroupForMethod(row.method),
      localStatus: row.localStatus,
      mobileStatus: row.mobileStatus,
      risk: row.risk,
      readOnly: row.risk === 'none' || row.risk === 'read',
      requiresApproval: ['write', 'process', 'network', 'permission'].includes(row.risk),
      source: 'capability-matrix'
    }));
}

function routeGroupForMethod(method) {
  const value = String(method || '');
  if (value.startsWith('thread/') && (value.includes('/list') || value.includes('/read') || value.includes('/search'))) return 'history';
  if (value.startsWith('model/') || value.startsWith('mcpServer/') || value.startsWith('skills/') || value.startsWith('plugin/') || value.startsWith('app/')) return 'discovery';
  if (value.startsWith('account/')) return 'account';
  if (value.startsWith('fs/') || value.startsWith('process/') || value.startsWith('command/') || value.startsWith('remoteControl/')) return 'high-risk';
  return 'other';
}

module.exports = {
  buildCodexAppServerRouteCapabilities
};
```

- [ ] **Step 4: Implement route dispatcher**

Create `daemon/src/codex-app-server/routes.js`:

```javascript
'use strict';

const { summarizeCodexAppServerCapabilityMatrix } = require('./capability-matrix');
const { buildCodexAppServerRouteCapabilities } = require('./capability-routes');

async function tryHandleCodexAppServerRoute({ method, url, json, readJson, context }) {
  if (!url.pathname.startsWith('/api/codex-app-server')) return false;

  if (method === 'GET' && url.pathname === '/api/codex-app-server/capabilities') {
    return json(200, {
      capabilityMatrix: summarizeCodexAppServerCapabilityMatrix(),
      routes: buildCodexAppServerRouteCapabilities()
    });
  }

  throw Object.assign(new Error('Codex app-server route not found'), {
    status: 404,
    code: 'CODEX_APP_SERVER_ROUTE_NOT_FOUND'
  });
}

module.exports = {
  tryHandleCodexAppServerRoute
};
```

- [ ] **Step 5: Wire dispatcher into `server.js`**

Import:

```javascript
const { tryHandleCodexAppServerRoute } = require('./codex-app-server/routes');
```

Update `createServer` signature:

```javascript
function createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, slashCommandCatalog, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset, appUpdates, codexAppServerService, auditLog }) {
```

After authentication and before `/api/adapters`, add:

```javascript
      const handledCodexAppServer = await tryHandleCodexAppServerRoute({
        method,
        url,
        json: (status, body, headers) => json(res, status, body, headers),
        readJson: () => readJson(req),
        context: { device, workspaces, codexAppServerService, auditLog }
      });
      if (handledCodexAppServer) return;
```

- [ ] **Step 6: Run route tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
tests passed
```

- [ ] **Step 7: Commit**

```bash
git add daemon/src/codex-app-server/capability-routes.js daemon/src/codex-app-server/routes.js daemon/src/server.js scripts/run-tests.js
git commit -m "Add Codex app-server route dispatcher"
```

---

### Task 3: Thread And History Read APIs

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/dtos.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- `thread/list`
- `thread/loaded/list`
- `thread/read`
- `thread/search`
- `thread/turns/list`
- `thread/turns/items/list`
- `thread/goal/get`
- `thread/status/changed`
- `thread/tokenUsage/updated`

- [ ] **Step 1: Write failing typed client tests**

Add:

```javascript
test('Codex app-server client sends typed thread history read requests', async () => {
  const { CodexAppServerClient } = require('../daemon/src/codex-app-server/client');
  const calls = [];
  const transport = {
    sendRequest(method, params) {
      calls.push({ method, params });
      return Promise.resolve({ ok: true });
    },
    sendNotification() {}
  };
  const client = new CodexAppServerClient({ transport });

  await client.listThreads({ workspacePath: 'D:\\Repo', limit: 20 });
  await client.readThread({ threadId: 'thread_1' });
  await client.searchThreads({ query: 'auth', workspacePath: 'D:\\Repo' });
  await client.listThreadTurns({ threadId: 'thread_1', limit: 10 });
  await client.listThreadTurnItems({ threadId: 'thread_1', turnId: 'turn_1' });

  assert.deepEqual(calls.map((call) => call.method), [
    'thread/list',
    'thread/read',
    'thread/search',
    'thread/turns/list',
    'thread/turns/items/list'
  ]);
});
```

- [ ] **Step 2: Implement client helpers**

Add to `CodexAppServerClient`:

```javascript
  listThreads(options = {}) {
    return this.sendRequest('thread/list', compactObject({
      workspacePath: options.workspacePath,
      limit: options.limit,
      cursor: options.cursor,
      archived: options.archived
    }), options);
  }

  listLoadedThreads(options = {}) {
    return this.sendRequest('thread/loaded/list', compactObject({}, options), options);
  }

  readThread(options = {}) {
    return this.sendRequest('thread/read', compactObject({
      threadId: options.threadId
    }), options);
  }

  searchThreads(options = {}) {
    return this.sendRequest('thread/search', compactObject({
      query: options.query,
      workspacePath: options.workspacePath,
      limit: options.limit,
      cursor: options.cursor
    }), options);
  }

  listThreadTurns(options = {}) {
    return this.sendRequest('thread/turns/list', compactObject({
      threadId: options.threadId,
      limit: options.limit,
      cursor: options.cursor
    }), options);
  }

  listThreadTurnItems(options = {}) {
    return this.sendRequest('thread/turns/items/list', compactObject({
      threadId: options.threadId,
      turnId: options.turnId,
      limit: options.limit,
      cursor: options.cursor
    }), options);
  }

  getThreadGoal(options = {}) {
    return this.sendRequest('thread/goal/get', compactObject({
      threadId: options.threadId
    }), options);
  }
```

Add helper in `client.js`:

```javascript
function compactObject(value) {
  return Object.fromEntries(Object.entries(value || {}).filter(([, entry]) => entry !== undefined && entry !== null));
}
```

- [ ] **Step 3: Write failing route tests**

Add:

```javascript
test('Codex app-server thread history routes enforce workspace authorization and normalize list response', async () => {
  const calls = [];
  const app = await createCodexAppServerRouteTestApp({
    service: {
      withWorkspaceClient: async (_workspace, callback) => callback({
        listThreads: async (params) => {
          calls.push(params);
          return { threads: [{ id: 'thread_1', title: 'Fix auth', workspacePath: process.cwd() }], nextCursor: null };
        }
      })
    }
  });
  try {
    const response = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads?limit=20`);
    assert.equal(response.status, 200);
    assert.equal(response.body.threads[0].id, 'thread_1');
    assert.equal(response.body.nextCursor, null);
    assert.equal(calls[0].limit, 20);
  } finally {
    await app.close();
  }
});
```

- [ ] **Step 4: Implement history routes**

In `routes.js`, add:

```javascript
  const workspaceThreads = url.pathname.match(/^\/api\/codex-app-server\/workspaces\/([^/]+)\/threads$/);
  if (method === 'GET' && workspaceThreads) {
    const workspace = context.workspaces.getAuthorized(decodeURIComponent(workspaceThreads[1]), context.device);
    const limit = parseLimit(url.searchParams.get('limit'), 50);
    return json(200, await context.codexAppServerService.withWorkspaceClient(workspace, (client) => client.listThreads({
      workspacePath: workspace.path || workspace.workspacePath,
      limit,
      cursor: url.searchParams.get('cursor') || undefined,
      archived: parseBoolean(url.searchParams.get('archived'))
    })));
  }

  const threadRead = url.pathname.match(/^\/api\/codex-app-server\/threads\/([^/]+)$/);
  if (method === 'GET' && threadRead) {
    return json(200, await context.codexAppServerService.withDiscoveryClient((client) => client.readThread({
      threadId: decodeURIComponent(threadRead[1])
    })));
  }
```

Add helpers:

```javascript
function parseLimit(value, fallback) {
  if (value === null || value === undefined || value === '') return fallback;
  if (!/^\d+$/.test(String(value))) throw Object.assign(new Error('limit must be a positive integer'), { status: 400, code: 'BAD_REQUEST' });
  return Math.max(1, Math.min(Number(value), 200));
}

function parseBoolean(value) {
  if (value === null || value === undefined || value === '') return undefined;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw Object.assign(new Error('boolean query must be true or false'), { status: 400, code: 'BAD_REQUEST' });
}
```

- [ ] **Step 5: Update capability matrix**

Change these rows to `supported`, `daemonOwner: 'server route'`, `mobileStatus: 'planned'`, `risk: 'read'`, `testRequirement: 'route test'`:

```text
thread/list
thread/loaded/list
thread/read
thread/search
thread/turns/list
thread/turns/items/list
thread/goal/get
thread/status/changed
thread/tokenUsage/updated
```

Keep `thread/fork`, `thread/archive`, `thread/unarchive`, and `thread/rollback` unsupported until Task 7.

- [ ] **Step 6: Run history tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
tests passed
```

- [ ] **Step 7: Commit**

```bash
git add daemon/src/codex-app-server/client.js daemon/src/codex-app-server/routes.js daemon/src/codex-app-server/dtos.js daemon/src/codex-app-server/capability-matrix.js scripts/run-tests.js
git commit -m "Add Codex app-server thread history routes"
```

---

### Task 4: Read-Only Discovery APIs

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/dtos.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- `modelProvider/capabilities/read`
- `permissionProfile/list`
- `app/list`, `app/list/updated`
- `mcpServerStatus/list`, `mcpServer/resource/read`, `mcpServer/startupStatus/updated`
- `skills/list`, `skills/changed`
- `plugin/list`, `plugin/read`, `plugin/skill/read`, `plugin/share/list`
- `hooks/list`, `hook/started`, `hook/completed`
- `collaborationMode/list`
- `experimentalFeature/list`
- `externalAgentConfig/detect`
- `config/read`, `configRequirements/read`, `configWarning`
- `windowsSandbox/readiness`, `windowsSandbox/setupCompleted`, `windows/worldWritableWarning`
- `deprecationNotice`, `warning`, `guardianWarning`, `model/rerouted`, `model/verification`

- [ ] **Step 1: Write failing discovery client tests**

Add:

```javascript
test('Codex app-server client sends typed read-only discovery requests', async () => {
  const { CodexAppServerClient } = require('../daemon/src/codex-app-server/client');
  const methods = [];
  const client = new CodexAppServerClient({
    transport: {
      sendRequest(method) {
        methods.push(method);
        return Promise.resolve({});
      },
      sendNotification() {}
    }
  });

  await client.readConfig();
  await client.listMcpServerStatus();
  await client.listSkills();
  await client.listPlugins();
  await client.listApps();
  await client.listPermissionProfiles();
  await client.readWindowsSandboxReadiness();

  assert.deepEqual(methods, [
    'config/read',
    'mcpServerStatus/list',
    'skills/list',
    'plugin/list',
    'app/list',
    'permissionProfile/list',
    'windowsSandbox/readiness'
  ]);
});
```

- [ ] **Step 2: Implement discovery helpers**

Add helper methods to `CodexAppServerClient`:

```javascript
  readConfig(options = {}) { return this.sendRequest('config/read', {}, options); }
  readConfigRequirements(options = {}) { return this.sendRequest('configRequirements/read', {}, options); }
  listMcpServerStatus(options = {}) { return this.sendRequest('mcpServerStatus/list', compactObject({ cursor: options.cursor }), options); }
  readMcpServerResource(options = {}) { return this.sendRequest('mcpServer/resource/read', compactObject({ serverId: options.serverId, uri: options.uri }), options); }
  listSkills(options = {}) { return this.sendRequest('skills/list', compactObject({ cursor: options.cursor }), options); }
  listPlugins(options = {}) { return this.sendRequest('plugin/list', compactObject({ cursor: options.cursor }), options); }
  readPlugin(options = {}) { return this.sendRequest('plugin/read', compactObject({ pluginId: options.pluginId }), options); }
  readPluginSkill(options = {}) { return this.sendRequest('plugin/skill/read', compactObject({ pluginId: options.pluginId, skillId: options.skillId }), options); }
  listPluginShares(options = {}) { return this.sendRequest('plugin/share/list', compactObject({ cursor: options.cursor }), options); }
  listApps(options = {}) { return this.sendRequest('app/list', compactObject({ cursor: options.cursor }), options); }
  listHooks(options = {}) { return this.sendRequest('hooks/list', {}, options); }
  listCollaborationModes(options = {}) { return this.sendRequest('collaborationMode/list', {}, options); }
  listExperimentalFeatures(options = {}) { return this.sendRequest('experimentalFeature/list', {}, options); }
  detectExternalAgentConfig(options = {}) { return this.sendRequest('externalAgentConfig/detect', {}, options); }
  listPermissionProfiles(options = {}) { return this.sendRequest('permissionProfile/list', {}, options); }
  readModelProviderCapabilities(options = {}) { return this.sendRequest('modelProvider/capabilities/read', {}, options); }
  readWindowsSandboxReadiness(options = {}) { return this.sendRequest('windowsSandbox/readiness', {}, options); }
```

- [ ] **Step 3: Add discovery routes**

Add routes:

```text
GET /api/codex-app-server/config
GET /api/codex-app-server/config/requirements
GET /api/codex-app-server/mcp/servers
GET /api/codex-app-server/mcp/resources?serverId=...&uri=...
GET /api/codex-app-server/skills
GET /api/codex-app-server/plugins
GET /api/codex-app-server/plugins/:pluginId
GET /api/codex-app-server/plugins/:pluginId/skills/:skillId
GET /api/codex-app-server/plugin-shares
GET /api/codex-app-server/apps
GET /api/codex-app-server/hooks
GET /api/codex-app-server/collaboration-modes
GET /api/codex-app-server/experimental-features
GET /api/codex-app-server/external-agent-config
GET /api/codex-app-server/permission-profiles
GET /api/codex-app-server/model-provider-capabilities
GET /api/codex-app-server/windows-sandbox/readiness
```

Each route must call `context.codexAppServerService.withDiscoveryClient((client) => ...)`.

- [ ] **Step 4: Add route tests**

Add one table-driven test:

```javascript
test('Codex app-server discovery routes call read-only typed methods', async () => {
  const methodByPath = {
    '/api/codex-app-server/config': 'config/read',
    '/api/codex-app-server/config/requirements': 'configRequirements/read',
    '/api/codex-app-server/mcp/servers': 'mcpServerStatus/list',
    '/api/codex-app-server/skills': 'skills/list',
    '/api/codex-app-server/plugins': 'plugin/list',
    '/api/codex-app-server/apps': 'app/list',
    '/api/codex-app-server/permission-profiles': 'permissionProfile/list',
    '/api/codex-app-server/windows-sandbox/readiness': 'windowsSandbox/readiness'
  };
  for (const [route, rpcMethod] of Object.entries(methodByPath)) {
    const result = await exerciseCodexAppServerRoute(route);
    assert.equal(result.calls[0], rpcMethod);
    assert.equal(result.response.status, 200);
  }
});
```

Create helper in `scripts/run-tests.js`:

```javascript
async function exerciseCodexAppServerRoute(route) {
  const calls = [];
  const methodNameByClientProperty = {
    readConfig: 'config/read',
    readConfigRequirements: 'configRequirements/read',
    listMcpServers: 'mcpServerStatus/list',
    listSkills: 'skills/list',
    listPlugins: 'plugin/list',
    listApps: 'app/list',
    listPermissionProfiles: 'permissionProfile/list',
    readWindowsSandboxReadiness: 'windowsSandbox/readiness'
  };
  const app = await createCodexAppServerRouteTestApp({
    service: {
      withDiscoveryClient: async (callback) => callback(new Proxy({}, {
        get(_target, property) {
          return async () => {
            const method = methodNameByClientProperty[String(property)];
            if (!method) throw new Error(`missing test mapping for ${String(property)}`);
            calls.push(method);
            return { ok: true };
          };
        }
      }))
    }
  });
  try {
    const response = await app.get(route);
    return { calls, response };
  } finally {
    await app.close();
  }
}
```

This helper intentionally maps client property names, not route names, so a misspelled route handler method fails the test with a clear missing mapping error.

- [ ] **Step 5: Update matrix**

Mark all Task 4 methods as:

```text
localStatus: supported
daemonOwner: server route
mobileStatus: planned
risk: read
testRequirement: route test
```

Notifications in this group should be `partial` until they are consumed by an event sink:

```text
app/list/updated
mcpServer/startupStatus/updated
skills/changed
hook/started
hook/completed
configWarning
deprecationNotice
warning
guardianWarning
model/rerouted
model/verification
windowsSandbox/setupCompleted
windows/worldWritableWarning
```

- [ ] **Step 6: Run discovery tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
tests passed
```

- [ ] **Step 7: Commit**

```bash
git add daemon/src/codex-app-server/client.js daemon/src/codex-app-server/routes.js daemon/src/codex-app-server/dtos.js daemon/src/codex-app-server/capability-matrix.js scripts/run-tests.js
git commit -m "Add Codex app-server discovery routes"
```

---

### Task 5: Account And Authentication Status APIs

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- Read/status: `account/read`, `account/rateLimits/read`, `account/updated`, `account/rateLimits/updated`
- Login/logout flow: `account/login/start`, `account/login/cancel`, `account/login/completed`, `account/logout`
- Token server request: `account/chatgptAuthTokens/refresh`
- Email nudge: `account/sendAddCreditsNudgeEmail`
- OAuth: `mcpServer/oauth/login`, `mcpServer/oauthLogin/completed`

- [ ] **Step 1: Add account client helpers**

Add:

```javascript
  readAccount(options = {}) { return this.sendRequest('account/read', {}, options); }
  readAccountRateLimits(options = {}) { return this.sendRequest('account/rateLimits/read', {}, options); }
  startAccountLogin(options = {}) { return this.sendRequest('account/login/start', compactObject({ provider: options.provider }), options); }
  cancelAccountLogin(options = {}) { return this.sendRequest('account/login/cancel', compactObject({ loginId: options.loginId }), options); }
  logoutAccount(options = {}) { return this.sendRequest('account/logout', {}, options); }
  sendAddCreditsNudgeEmail(options = {}) { return this.sendRequest('account/sendAddCreditsNudgeEmail', {}, options); }
  startMcpServerOauthLogin(options = {}) { return this.sendRequest('mcpServer/oauth/login', compactObject({ serverId: options.serverId }), options); }
```

- [ ] **Step 2: Add account routes**

Routes:

```text
GET /api/codex-app-server/account
GET /api/codex-app-server/account/rate-limits
POST /api/codex-app-server/account/login/start
POST /api/codex-app-server/account/login/cancel
POST /api/codex-app-server/account/logout
POST /api/codex-app-server/account/add-credits-email
POST /api/codex-app-server/mcp/servers/:serverId/oauth/login
```

Read routes use `withDiscoveryClient`. Mutating account routes use `withMutationClient` and audit.
Account read DTOs must redact bearer tokens, refresh tokens, raw email fields unless explicitly needed by UI, and local account file paths. Treat account reads as `risk: account`, not plain `risk: read`.

- [ ] **Step 3: Add tests for read and mutation separation**

Add:

```javascript
test('Codex app-server account read routes are discovery scoped and login routes are mutation scoped', async () => {
  const calls = [];
  const app = createCodexAppServerRouteTestApp({
    service: {
      withDiscoveryClient: async (callback) => callback({
        readAccount: async () => {
          calls.push('discovery:account/read');
          return { account: { id: 'acct_1' } };
        }
      }),
      withMutationClient: async ({ method }, callback) => callback({
        startAccountLogin: async () => {
          calls.push(`mutation:${method}`);
          return { loginId: 'login_1' };
        }
      })
    }
  });
  const read = await app.get('/api/codex-app-server/account');
  const login = await app.post('/api/codex-app-server/account/login/start', {});
  assert.equal(read.status, 200);
  assert.equal(login.status, 200);
  assert.deepEqual(calls, ['discovery:account/read', 'mutation:account/login/start']);
  await app.close();
});

test('Codex app-server account read DTO redacts sensitive token fields', async () => {
  const app = createCodexAppServerRouteTestApp({
    service: {
      withDiscoveryClient: async (callback) => callback({
        readAccount: async () => ({
          account: {
            id: 'acct_1',
            email: 'person@example.com',
            accessToken: 'secret_access',
            refreshToken: 'secret_refresh'
          }
        })
      })
    }
  });
  const response = await app.get('/api/codex-app-server/account');
  const serialized = JSON.stringify(response.body);
  assert.equal(response.status, 200);
  assert.equal(serialized.includes('secret_access'), false);
  assert.equal(serialized.includes('secret_refresh'), false);
  await app.close();
});
```

- [ ] **Step 4: Add token server request handling**

In `CodexAppServerConversationHandle.handleServerRequest()`, map `account/chatgptAuthTokens/refresh` to fail closed until a product auth token provider exists:

```javascript
if (message?.method === 'account/chatgptAuthTokens/refresh') {
  this.failClosedServerRequest(message, 'account token refresh is not available through the mobile daemon');
  return;
}
```

This method should be `intentionally-blocked` with rationale:

```text
Token refresh requires an explicit secure token provider; daemon must not synthesize or expose account tokens.
```

- [ ] **Step 5: Update matrix**

Mark read account routes as `supported`, account mutations as `supported` only if audit tests pass, token refresh as `intentionally-blocked`, and notifications as `partial`.

- [ ] **Step 6: Run tests and commit**

```powershell
node scripts\run-tests.js
npm run lint
git add daemon/src/codex-app-server daemon/src/codex-app-server-conversation-adapter.js scripts/run-tests.js
git commit -m "Add Codex app-server account routes"
```

---

### Task 6: File-System Read APIs And Watch Diagnostics

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/risk-policy.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- Read: `fs/getMetadata`, `fs/readDirectory`, `fs/readFile`
- Watch diagnostics: `fs/watch`, `fs/unwatch`, `fs/changed`
- Writes deferred to Task 8: `fs/copy`, `fs/createDirectory`, `fs/remove`, `fs/writeFile`

- [ ] **Step 1: Add typed client helpers**

```javascript
  getFileMetadata(options = {}) { return this.sendRequest('fs/getMetadata', compactObject({ path: options.path }), options); }
  readDirectory(options = {}) { return this.sendRequest('fs/readDirectory', compactObject({ path: options.path }), options); }
  readFile(options = {}) { return this.sendRequest('fs/readFile', compactObject({ path: options.path, encoding: options.encoding }), options); }
  watchFileSystem(options = {}) { return this.sendRequest('fs/watch', compactObject({ path: options.path }), options); }
  unwatchFileSystem(options = {}) { return this.sendRequest('fs/unwatch', compactObject({ watchId: options.watchId }), options); }
```

- [ ] **Step 2: Add workspace path guard tests**

```javascript
test('Codex app-server fs read routes reject paths outside authorized workspace', async () => {
  const app = createCodexAppServerRouteTestApp({ service: { withWorkspaceClient: async () => { throw new Error('must not call app-server'); } } });
  const response = await app.get('/api/codex-app-server/workspaces/default/fs/read-file?path=C%3A%5CWindows%5Cwin.ini');
  assert.equal(response.status, 403);
  assert.equal(response.body.error.code, 'FORBIDDEN');
  await app.close();
});
```

- [ ] **Step 3: Add routes**

```text
GET /api/codex-app-server/workspaces/:workspaceId/fs/metadata?path=relative/path
GET /api/codex-app-server/workspaces/:workspaceId/fs/directory?path=relative/path
GET /api/codex-app-server/workspaces/:workspaceId/fs/read-file?path=relative/path
POST /api/codex-app-server/workspaces/:workspaceId/fs/watch
POST /api/codex-app-server/workspaces/:workspaceId/fs/unwatch
```

Resolve the target path:

```javascript
function resolveWorkspaceRelativePath(workspace, relativePath) {
  const root = workspace.path || workspace.workspacePath;
  const resolved = require('node:path').resolve(root, relativePath || '.');
  if (resolved !== root && !resolved.startsWith(root + require('node:path').sep)) {
    throw Object.assign(new Error('path outside authorized workspace'), { status: 403, code: 'FORBIDDEN' });
  }
  return resolved;
}
```

- [ ] **Step 4: Update matrix**

Mark `fs/getMetadata`, `fs/readDirectory`, and `fs/readFile` as supported/read. Mark `fs/watch`, `fs/unwatch`, and `fs/changed` as diagnostic-only until the mobile file watcher UX exists.

- [ ] **Step 5: Run and commit**

```powershell
node scripts\run-tests.js
git add daemon/src/codex-app-server scripts/run-tests.js
git commit -m "Add Codex app-server filesystem read routes"
```

---

### Task 7: Thread Management Mutations

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/audit.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- `thread/fork`
- `thread/archive`
- `thread/unarchive`
- `thread/rollback`
- `thread/metadata/update`
- `thread/name/set`
- `thread/settings/update`
- `thread/memoryMode/set`
- `thread/goal/set`
- `thread/goal/clear`
- `thread/inject_items`
- `thread/unsubscribe`
- `thread/compact/start`
- `thread/backgroundTerminals/clean`
- `thread/approveGuardianDeniedAction`
- `thread/increment_elicitation`
- `thread/decrement_elicitation`
- Related notifications: `thread/archived`, `thread/unarchived`, `thread/name/updated`, `thread/settings/updated`, `thread/goal/updated`, `thread/goal/cleared`, `thread/closed`, `thread/compacted`

- [ ] **Step 1: Add mutation client helpers**

Add helpers matching official method names:

```javascript
  forkThread(options = {}) { return this.sendRequest('thread/fork', compactObject({ threadId: options.threadId, workspacePath: options.workspacePath, fromTurnId: options.fromTurnId }), options); }
  archiveThread(options = {}) { return this.sendRequest('thread/archive', compactObject({ threadId: options.threadId }), options); }
  unarchiveThread(options = {}) { return this.sendRequest('thread/unarchive', compactObject({ threadId: options.threadId }), options); }
  rollbackThread(options = {}) { return this.sendRequest('thread/rollback', compactObject({ threadId: options.threadId, turnId: options.turnId, itemId: options.itemId }), options); }
  updateThreadMetadata(options = {}) { return this.sendRequest('thread/metadata/update', compactObject({ threadId: options.threadId, metadata: options.metadata }), options); }
  setThreadName(options = {}) { return this.sendRequest('thread/name/set', compactObject({ threadId: options.threadId, name: options.name }), options); }
  updateThreadSettings(options = {}) { return this.sendRequest('thread/settings/update', compactObject({ threadId: options.threadId, settings: options.settings }), options); }
  setThreadMemoryMode(options = {}) { return this.sendRequest('thread/memoryMode/set', compactObject({ threadId: options.threadId, memoryMode: options.memoryMode }), options); }
  setThreadGoal(options = {}) { return this.sendRequest('thread/goal/set', compactObject({ threadId: options.threadId, goal: options.goal }), options); }
  clearThreadGoal(options = {}) { return this.sendRequest('thread/goal/clear', compactObject({ threadId: options.threadId }), options); }
```

- [ ] **Step 2: Add audit helper**

Create `daemon/src/codex-app-server/audit.js`:

```javascript
'use strict';

function recordCodexAppServerAudit(auditLog, event, details) {
  if (!auditLog || typeof auditLog.record !== 'function') return;
  auditLog.record(`codex_app_server.${event}`, {
    timestamp: new Date().toISOString(),
    method: details.method,
    workspaceId: details.workspaceId || null,
    threadId: details.threadId || null,
    deviceId: details.deviceId || null,
    risk: details.risk || null,
    decision: details.decision || null,
    result: details.result || (details.ok === true ? 'success' : 'failure'),
    errorCode: details.errorCode || null,
    correlationId: details.correlationId || null
  });
}

module.exports = {
  recordCodexAppServerAudit
};
```

The concrete audit backend is the app SQLite audit log. Rows are append-only at the application layer and retained for at least 90 days. Minimum payload fields are timestamp, paired device id, workspace id, method, risk, decision, result, redacted error code, and request correlation id.

- [ ] **Step 3: Add route tests for workspace authorization and audit**

```javascript
test('Codex app-server thread archive requires workspace authorization and audits result', async () => {
  const auditEvents = [];
  const app = createCodexAppServerRouteTestApp({
    auditLog: { record: (event, payload) => auditEvents.push({ event, payload }) },
    service: {
      withMutationClient: async ({ method }, callback) => callback({
        archiveThread: async (params) => ({ threadId: params.threadId, archived: true, method })
      })
    }
  });
  const response = await app.post('/api/codex-app-server/workspaces/default/threads/thread_1/archive', {});
  assert.equal(response.status, 200);
  assert.equal(response.body.archived, true);
  assert.equal(auditEvents.some((event) => event.event === 'codex_app_server.thread_mutation' && event.payload.method === 'thread/archive'), true);
  await app.close();
});
```

- [ ] **Step 4: Add routes**

```text
POST /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/fork
POST /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/archive
POST /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/unarchive
POST /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/rollback
PATCH /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/metadata
PATCH /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/name
PATCH /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/settings
PATCH /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/memory-mode
PUT /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/goal
DELETE /api/codex-app-server/workspaces/:workspaceId/threads/:threadId/goal
```

Each route:

1. Authenticates device through server.
2. Resolves workspace through `getAuthorized`.
3. Sends only the registry-resolved workspace root to app-server.
4. Verifies thread metadata belongs to the authorized workspace before fork/archive/unarchive/rollback when app-server exposes that metadata; otherwise keeps the route `planned`.
5. Calls `withMutationClient`.
6. Records audit success or failure in the append-only app SQLite audit log.
7. Returns redacted controlled errors on app-server JSON-RPC failures.

- [ ] **Step 5: Update matrix**

Mark implemented methods as supported/write. Mark `thread/inject_items`, `thread/approveGuardianDeniedAction`, `thread/increment_elicitation`, and `thread/decrement_elicitation` as `diagnostic-only` unless product UX for these exists in this phase.

- [ ] **Step 6: Run and commit**

```powershell
node scripts\run-tests.js
git add daemon/src/codex-app-server scripts/run-tests.js
git commit -m "Add Codex app-server thread management routes"
```

---

### Task 8: High-Risk File, Process, Command, Config, Plugin, Marketplace, Skills, Environment, And Remote-Control Operations

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/high-risk-approval.js`
- Modify: `daemon/src/codex-app-server/audit.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- File writes: `fs/copy`, `fs/createDirectory`, `fs/remove`, `fs/writeFile`
- Process/command: `process/spawn`, `process/kill`, `process/resizePty`, `process/writeStdin`, `process/exited`, `process/outputDelta`, `command/exec`, `command/exec/resize`, `command/exec/terminate`, `command/exec/write`, `command/exec/outputDelta`
- Config/environment: `config/value/write`, `config/batchWrite`, `config/mcpServer/reload`, `environment/add`
- Plugins/marketplace/skills: `plugin/install`, `plugin/installed`, `plugin/uninstall`, `plugin/share/checkout`, `plugin/share/delete`, `plugin/share/save`, `plugin/share/updateTargets`, `marketplace/add`, `marketplace/remove`, `marketplace/upgrade`, `skills/config/write`, `skills/extraRoots/set`
- Remote control: `remoteControl/status/read`, `remoteControl/client/list`, `remoteControl/client/revoke`, `remoteControl/enable`, `remoteControl/disable`, `remoteControl/pairing/start`, `remoteControl/status/changed`

- [ ] **Step 1: Default-deny tests**

Add:

```javascript
test('Codex app-server high-risk routes default deny without approval policy', async () => {
  const app = createCodexAppServerRouteTestApp({
    service: { withMutationClient: async () => { throw new Error('must not call app-server'); } }
  });
  const response = await app.post('/api/codex-app-server/workspaces/default/fs/write-file', {
    path: 'README.md',
    content: 'unsafe'
  });
  assert.equal(response.status, 403);
  assert.equal(response.body.error.code, 'CODEX_APP_SERVER_APPROVAL_REQUIRED');
  await app.close();
});
```

- [ ] **Step 2: Approval-required success tests**

Add:

```javascript
test('Codex app-server high-risk routes audit authorized downstream failures', async () => {
  const auditEvents = [];
  const app = createCodexAppServerRouteTestApp({
    approvalPolicy: { allowHighRiskForTests: true },
    auditLog: { record: (event, payload) => auditEvents.push({ event, payload }) },
    service: {
      withMutationClient: async ({ method }, callback) => callback({
        writeFile: async () => {
          const error = new Error('provider write failed with token sk-secret');
          error.code = 'JSON_RPC_ERROR';
          throw error;
        }
      })
    }
  });
  const response = await app.post('/api/codex-app-server/workspaces/default/fs/write-file', {
    path: 'README.md',
    content: 'safe'
  });
  assert.equal(response.status, 502);
  assert.equal(response.body.error.message.includes('sk-secret'), false);
  assert.equal(auditEvents.some((event) => event.event === 'codex_app_server.high_risk_failure' && event.payload.method === 'fs/writeFile'), true);
  await app.close();
});
```

- [ ] **Step 3: Implement approval helper**

Create `daemon/src/codex-app-server/high-risk-approval.js`:

```javascript
'use strict';

function requireHighRiskApproval({ method, approvalPolicy }) {
  if (approvalPolicy && approvalPolicy.allowHighRiskForTests === true) return { decision: 'allow', source: 'test-policy' };
  const error = new Error(`Codex app-server method ${method} requires explicit approval`);
  error.status = 403;
  error.code = 'CODEX_APP_SERVER_APPROVAL_REQUIRED';
  error.recoverable = true;
  error.userAction = 'Approve this app-server operation before retrying.';
  throw error;
}

function redactCodexAppServerError(error) {
  return String(error?.message || 'Codex app-server operation failed')
    .replace(/sk-[A-Za-z0-9_-]+/g, 'sk-REDACTED')
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer REDACTED');
}

module.exports = {
  redactCodexAppServerError,
  requireHighRiskApproval
};
```

- [ ] **Step 4: Implement typed helpers and routes**

Add one typed client helper per method, for example:

```javascript
  writeFile(options = {}) { return this.sendRequest('fs/writeFile', compactObject({ path: options.path, content: options.content, encoding: options.encoding }), options); }
  spawnProcess(options = {}) { return this.sendRequest('process/spawn', compactObject({ command: options.command, args: options.args, cwd: options.cwd }), options); }
  executeCommand(options = {}) { return this.sendRequest('command/exec', compactObject({ command: options.command, cwd: options.cwd }), options); }
  writeConfigValue(options = {}) { return this.sendRequest('config/value/write', compactObject({ key: options.key, value: options.value }), options); }
  installPlugin(options = {}) { return this.sendRequest('plugin/install', compactObject({ pluginId: options.pluginId }), options); }
  enableRemoteControl(options = {}) { return this.sendRequest('remoteControl/enable', {}, options); }
```

Routes must be typed product routes, not raw RPC routes. Use route names:

```text
POST /api/codex-app-server/workspaces/:workspaceId/fs/write-file
POST /api/codex-app-server/workspaces/:workspaceId/fs/copy
POST /api/codex-app-server/workspaces/:workspaceId/fs/create-directory
DELETE /api/codex-app-server/workspaces/:workspaceId/fs/remove
POST /api/codex-app-server/workspaces/:workspaceId/processes
POST /api/codex-app-server/workspaces/:workspaceId/processes/:processId/kill
POST /api/codex-app-server/workspaces/:workspaceId/commands/exec
PATCH /api/codex-app-server/config/value
PATCH /api/codex-app-server/config/batch
POST /api/codex-app-server/config/mcp-server/reload
POST /api/codex-app-server/environment
POST /api/codex-app-server/plugins/install
POST /api/codex-app-server/plugins/:pluginId/uninstall
POST /api/codex-app-server/marketplace/add
POST /api/codex-app-server/marketplace/remove
POST /api/codex-app-server/marketplace/upgrade
PATCH /api/codex-app-server/skills/config
PATCH /api/codex-app-server/skills/extra-roots
GET /api/codex-app-server/remote-control/status
GET /api/codex-app-server/remote-control/clients
POST /api/codex-app-server/remote-control/enable
POST /api/codex-app-server/remote-control/disable
POST /api/codex-app-server/remote-control/pairing/start
POST /api/codex-app-server/remote-control/clients/:clientId/revoke
```

- [ ] **Step 5: Update matrix**

Mark implemented high-risk methods as `supported`, with exact risk:

- `write`: file/config/plugin/marketplace/skills/environment writes
- `process`: process and command execution
- `network`: remote control enable/pair/revoke

Mark process and command output notifications as `partial` until a route-level stream is implemented:

```text
process/exited
process/outputDelta
command/exec/outputDelta
```

- [ ] **Step 6: Run and commit**

```powershell
node scripts\run-tests.js
npm run lint
git add daemon/src/codex-app-server scripts/run-tests.js
git commit -m "Add guarded Codex app-server high-risk routes"
```

---

### Task 9: MCP Tool Calls, Dynamic Tools, Review, Attestation, Fuzzy Search, Feedback, And Experimental Methods

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- MCP/tool server requests and routes:
  - `mcpServer/tool/call`
  - `item/tool/call`
  - `item/tool/requestUserInput`
  - `mcpServer/elicitation/request`
  - `serverRequest/resolved`
- Review/attestation:
  - `review/start`
  - `attestation/generate`
  - `applyPatchApproval`
  - `execCommandApproval`
- Fuzzy file search:
  - `fuzzyFileSearch`
  - `fuzzyFileSearch/sessionStart`
  - `fuzzyFileSearch/sessionUpdate`
  - `fuzzyFileSearch/sessionStop`
  - `fuzzyFileSearch/sessionCompleted`
  - `fuzzyFileSearch/sessionUpdated`
- Feedback and experimental:
  - `feedback/upload`
  - `experimentalFeature/enablement/set`
  - `mock/experimentalMethod`
- Item rich notifications:
  - `item/autoApprovalReview/started`
  - `item/autoApprovalReview/completed`
  - `item/commandExecution/terminalInteraction`
  - `item/fileChange/outputDelta`
  - `item/fileChange/patchUpdated`
  - `item/mcpToolCall/progress`
  - `item/plan/delta`
  - `item/reasoning/summaryPartAdded`
  - `item/reasoning/summaryTextDelta`
  - `item/reasoning/textDelta`
  - `turn/diff/updated`

- [ ] **Step 1: Decide supported vs intentionally-blocked rows**

Update matrix before routes:

- `fuzzyFileSearch*`: `supported`, `risk: read`, `daemonOwner: server route`.
- `feedback/upload`: `diagnostic-only`, `risk: network`.
- `experimentalFeature/enablement/set`: `intentionally-blocked`, `risk: write`, rationale: "Product feature flags require a first-party settings UX."
- `mock/experimentalMethod`: `intentionally-blocked`, `risk: none`, rationale: "Generated protocol test method; never productized."
- `attestation/generate`: `diagnostic-only`, `risk: permission`.
- `review/start`: `supported` only if route returns structured review output and audit exists.
- `applyPatchApproval`, `execCommandApproval`: `partial` or `intentionally-blocked` unless mapped to existing mobile approval queue.
- rich item notifications: `partial` until mapped into stable mobile events.

- [ ] **Step 2: Add fuzzy search routes and tests**

Routes:

```text
GET /api/codex-app-server/workspaces/:workspaceId/fuzzy-file-search?q=...
POST /api/codex-app-server/workspaces/:workspaceId/fuzzy-file-search/sessions
PATCH /api/codex-app-server/workspaces/:workspaceId/fuzzy-file-search/sessions/:sessionId
DELETE /api/codex-app-server/workspaces/:workspaceId/fuzzy-file-search/sessions/:sessionId
```

Test:

```javascript
test('Codex app-server fuzzy search is workspace scoped and read-only', async () => {
  const calls = [];
  const app = createCodexAppServerRouteTestApp({
    service: {
      withWorkspaceClient: async (workspace, callback) => callback({
        fuzzyFileSearch: async (params) => {
          calls.push({ workspacePath: workspace.path || workspace.workspacePath, params });
          return { matches: [{ path: 'src/main.js' }] };
        }
      })
    }
  });
  const response = await app.get('/api/codex-app-server/workspaces/default/fuzzy-file-search?q=main');
  assert.equal(response.status, 200);
  assert.equal(response.body.matches[0].path, 'src/main.js');
  assert.equal(calls[0].params.query, 'main');
  await app.close();
});
```

- [ ] **Step 3: Add tool call and elicitation fail-closed handling**

In conversation adapter server request handling:

```javascript
if (message?.method === 'item/tool/requestUserInput' || message?.method === 'mcpServer/elicitation/request') {
  this.failClosedServerRequest(message, 'interactive app-server tool request is not supported yet');
  return;
}
```

Add tests proving the daemon responds with JSON-RPC error and emits `run.error`.

- [ ] **Step 4: Add review and attestation diagnostic routes**

Routes:

```text
POST /api/codex-app-server/workspaces/:workspaceId/review/start
POST /api/codex-app-server/workspaces/:workspaceId/attestation/generate
```

Both require audit. `review/start` is high-value but can be expensive, so include `maxItems` and request size validation.

- [ ] **Step 5: Run and commit**

```powershell
node scripts\run-tests.js
npm run lint
git add daemon/src/codex-app-server daemon/src/codex-app-server-conversation-adapter.js scripts/run-tests.js
git commit -m "Add Codex app-server advanced tool and search APIs"
```

---

### Task 10: Realtime And Audio APIs

**Files:**
- Modify: `daemon/src/codex-app-server/client.js`
- Modify: `daemon/src/codex-app-server/routes.js`
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `scripts/run-tests.js`

APIs covered:

- `thread/realtime/start`
- `thread/realtime/appendAudio`
- `thread/realtime/appendText`
- `thread/realtime/stop`
- `thread/realtime/listVoices`
- `thread/realtime/started`
- `thread/realtime/closed`
- `thread/realtime/error`
- `thread/realtime/itemAdded`
- `thread/realtime/outputAudio/delta`
- `thread/realtime/sdp`
- `thread/realtime/transcript/delta`
- `thread/realtime/transcript/done`

- [ ] **Step 1: Mark initial status**

Set:

```text
thread/realtime/listVoices -> supported, read
thread/realtime/start -> diagnostic-only, network
thread/realtime/appendText -> diagnostic-only, write
thread/realtime/appendAudio -> diagnostic-only, write
thread/realtime/stop -> diagnostic-only, write
realtime notifications -> partial
```

Reason: realtime requires stream transport and mobile audio UX; daemon can expose capability diagnostics first without pretending full product support.

- [ ] **Step 2: Add voice list route**

Route:

```text
GET /api/codex-app-server/realtime/voices
```

Client helper:

```javascript
  listRealtimeVoices(options = {}) { return this.sendRequest('thread/realtime/listVoices', {}, options); }
```

- [ ] **Step 3: Add diagnostic-only blocked route tests**

```javascript
test('Codex app-server realtime start is diagnostic-only until streaming transport exists', async () => {
  const app = createCodexAppServerRouteTestApp({});
  const response = await app.post('/api/codex-app-server/workspaces/default/realtime/start', {});
  assert.equal(response.status, 409);
  assert.equal(response.body.error.code, 'CODEX_APP_SERVER_DIAGNOSTIC_ONLY');
  await app.close();
});
```

- [ ] **Step 4: Run and commit**

```powershell
node scripts\run-tests.js
git add daemon/src/codex-app-server scripts/run-tests.js
git commit -m "Classify Codex app-server realtime APIs"
```

---

### Task 11: Matrix Completion Gate

**Files:**
- Modify: `daemon/src/codex-app-server/capability-matrix.js`
- Modify: `daemon/src/codex-app-server/methods.js`
- Create or modify: `scripts/check-codex-app-server-fixture-drift.js`
- Modify: `scripts/run-tests.js`
- Modify: `docs/superpowers/specs/2026-06-04-codex-app-server-api-parity-design.md`

- [ ] **Step 1: Add no-unknown-risk completion test**

Add:

```javascript
test('Codex app-server full parity has no unsupported unknown-risk rows', () => {
  const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('../daemon/src/codex-app-server/capability-matrix');
  const unfinished = CODEX_APP_SERVER_CAPABILITY_MATRIX.filter((row) => row.localStatus === 'unsupported' || row.risk === 'unknown');
  assert.deepEqual(unfinished.map((row) => `${row.localStatus}:${row.risk}:${row.method}`), []);
});
```

- [ ] **Step 2: Update all remaining rows**

Every official method must be one of:

```text
supported
partial
diagnostic-only
intentionally-blocked
```

No row may remain:

```text
localStatus: unsupported
risk: unknown
```

- [ ] **Step 3: Add route coverage matrix test**

Add:

```javascript
test('Codex app-server supported route methods have route coverage', () => {
  const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('../daemon/src/codex-app-server/capability-matrix');
  const routeOwned = CODEX_APP_SERVER_CAPABILITY_MATRIX
    .filter((row) => row.daemonOwner === 'server route' && row.localStatus === 'supported')
    .map((row) => row.method);
  const knownRouteMethods = require('../daemon/src/codex-app-server/routes').SUPPORTED_ROUTE_METHODS;
  for (const method of routeOwned) {
    assert.equal(knownRouteMethods.has(method), true, `${method} missing route coverage`);
  }
});
```

- [ ] **Step 4: Add rename/remove and fixture drift tests**

Add matrix validation tests:

```javascript
test('Codex app-server removed or renamed rows keep explicit review metadata', () => {
  const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('../daemon/src/codex-app-server/capability-matrix');
  for (const row of CODEX_APP_SERVER_CAPABILITY_MATRIX) {
    if (row.localStatus === 'intentionally-blocked' && row.removedInSchemaVersion) {
      assert.equal(typeof row.rationale, 'string', `${row.method} missing removal rationale`);
      assert.ok(row.rationale.length > 0, `${row.method} missing removal rationale`);
    }
    if (row.renamedFrom) {
      assert.equal(typeof row.renamedFrom, 'string', `${row.method} renamedFrom must be a string`);
      assert.notEqual(row.renamedFrom, row.method);
    }
  }
});
```

Create `scripts/check-codex-app-server-fixture-drift.js` as a release-gate script. It should:

- Run the real `codex` app-server schema generator when available.
- Compare generated TypeScript/JSON schema method sets with committed fixtures.
- Exit `0` with a clear skip message only when `codex` or the generator is unavailable.
- Exit non-zero when the generator succeeds and fixtures differ.

The normal `node scripts\run-tests.js` suite may keep using fixtures; this drift script is for scheduled CI or manual release validation so fixture staleness becomes visible.

- [ ] **Step 5: Update design spec**

In `docs/superpowers/specs/2026-06-04-codex-app-server-api-parity-design.md`, add a “Full Parity Completion” section:

```markdown
## Full Parity Completion

Full daemon parity means every official schema method is classified with a concrete risk and one of `supported`, `partial`, `diagnostic-only`, or `intentionally-blocked`. It does not mean every high-risk operation is silently available; high-risk support requires typed routes, authorization, approval or product policy, audit, and redacted errors. Unsupported/unknown rows are not allowed after the full parity plan lands.
```

- [ ] **Step 6: Run and commit**

```powershell
node scripts\run-tests.js
npm run lint
node scripts\check-project-knowledge.js
node scripts\check-codex-app-server-fixture-drift.js
git add daemon/src/codex-app-server scripts/run-tests.js scripts/check-codex-app-server-fixture-drift.js docs/superpowers/specs/2026-06-04-codex-app-server-api-parity-design.md
git commit -m "Complete Codex app-server API parity matrix"
```

---

### Task 12: Streaming Retention, Backpressure, Kill-Switch, And Metrics

**Files:**
- Create: `daemon/src/codex-app-server/streaming-policy.js`
- Modify: `daemon/src/server.js`
- Modify: `daemon/src/main.js`
- Modify: `daemon/src/codex-app-server/service.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Add bounded streaming and kill-switch tests**

Add:

```javascript
test('Codex app-server streaming policy keeps raw partials but bounds live websocket queues', () => {
  const { CODEX_APP_SERVER_STREAMING_POLICY } = require('../daemon/src/codex-app-server/streaming-policy');
  assert.equal(CODEX_APP_SERVER_STREAMING_POLICY.persistRawDeltas, true);
  assert.equal(CODEX_APP_SERVER_STREAMING_POLICY.semanticCompression, false);
  assert.equal(CODEX_APP_SERVER_STREAMING_POLICY.maxWebSocketQueueEvents > 0, true);
  assert.equal(CODEX_APP_SERVER_STREAMING_POLICY.rawDeltaRetentionDays > 0, true);
});

test('Codex app-server kill-switch disables app-server routes without disabling CLI fallback', async () => {
  const app = createApp({
    port: 0,
    codexAppServerEnabled: false,
    codexAppServerProbe: false,
    codexAppServerModelLister: false,
    appDbPath: tempConversationDbPath('app-server-disabled-')
  });
  const pair = app.auth.createPairingCode();
  const paired = app.auth.pair(pair.code, 'disabled', 'device_disabled');
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await request(app.server.address().port, 'GET', '/api/codex-app-server/capabilities', null, {
      authorization: `Bearer ${paired.accessToken}`
    });
    assert.equal(response.status, 503);
    assert.equal(response.body.error.code, 'CODEX_APP_SERVER_DISABLED');
  } finally {
    app.server.close();
    app.appSqliteStore.close();
  }
});
```

- [ ] **Step 2: Implement streaming policy constants**

Create `daemon/src/codex-app-server/streaming-policy.js`:

```javascript
'use strict';

const CODEX_APP_SERVER_STREAMING_POLICY = {
  persistRawDeltas: true,
  semanticCompression: false,
  rawDeltaRetentionDays: 30,
  derivedSnapshotAfterEvents: 500,
  durableSnapshotTriggers: ['turn/completed', 'derivedSnapshotAfterEvents'],
  maxWebSocketQueueEvents: 2000,
  slowConsumerSignal: 'conversation.replay_required'
};

module.exports = {
  CODEX_APP_SERVER_STREAMING_POLICY
};
```

The policy does not filter or compress live `assistant.partial` data. It defines the daemon-side bounds that later EventStore/WebSocket work must enforce. Raw delta pruning is allowed only after a durable conversation snapshot is committed to the app database with the last included event sequence; pruning before that committed snapshot exists is a correctness bug.

- [ ] **Step 3: Add kill-switch and metrics expectations**

`createApp()` should treat `codexAppServerEnabled: false` as a runtime kill-switch for app-server route service creation and app-server adapter selection, while preserving existing CLI adapter fallback before side-effect boundaries. The kill-switch affects new provider selections and new app-server routes only. It must not forcibly terminate already-running app-server turns that crossed the side-effect boundary; those continue until completion, user interrupt, or provider failure.

`CodexAppServerService` metrics must expose at least:

```text
codex_app_server_process_spawn_total{pool}
codex_app_server_discovery_cache_hit_total
codex_app_server_discovery_cache_miss_total
codex_app_server_process_eviction_total{pool,reason}
codex_app_server_method_latency_ms{method,pool}
codex_app_server_method_error_total{method,pool}
```

- [ ] **Step 4: Run and commit**

```powershell
node scripts\run-tests.js
npm run lint
git add daemon/src/codex-app-server/streaming-policy.js daemon/src/codex-app-server/service.js daemon/src/main.js daemon/src/server.js scripts/run-tests.js
git commit -m "Add Codex app-server operational safety gates"
```

---

### Task 13: Mobile Data Layer For Stable App-Server APIs

**Files:**
- Create: `mobile/lib/src/domain/repositories/codex_app_server_repository.dart`
- Create: `mobile/lib/src/data/repositories/codex_app_server_repository.dart`
- Create: `mobile/lib/src/data/models/codex_app_server_models.dart`
- Modify: `mobile/lib/src/services/conversation_client.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Add tests under `mobile/test/`

- [ ] **Step 1: Add domain repository**

Create:

```dart
abstract class CodexAppServerRepository {
  Future<CodexAppServerCapabilities> loadCapabilities();
  Future<CodexAppServerThreadPage> listThreads(String workspaceId, {int limit = 50});
  Future<CodexAppServerThreadDetail> readThread(String threadId);
  Future<CodexAppServerDiscoverySnapshot> loadDiscovery();
}
```

- [ ] **Step 2: Add DTO parsing tests**

Create `mobile/test/codex_app_server_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_coding/src/data/models/codex_app_server_models.dart';

void main() {
  test('CodexAppServerThreadSummary parses stable daemon DTO', () {
    final summary = CodexAppServerThreadSummary.fromJson({
      'id': 'thread_1',
      'title': 'Fix auth',
      'workspacePath': 'D:/Repo',
      'archived': false,
    });

    expect(summary.id, 'thread_1');
    expect(summary.title, 'Fix auth');
    expect(summary.archived, false);
  });
}
```

- [ ] **Step 3: Implement mobile data repository**

Use existing `DaemonClient` HTTP helpers. Add methods:

```dart
Future<Map<String, Object?>> getCodexAppServerCapabilities();
Future<Map<String, Object?>> listCodexAppServerThreads(String workspaceId, {int limit = 50});
Future<Map<String, Object?>> readCodexAppServerThread(String threadId);
```

- [ ] **Step 4: Run mobile tests**

Run from `mobile/`:

```powershell
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
flutter test --no-pub test\codex_app_server_models_test.dart
```

Expected:

```text
No issues found
All tests passed
```

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/src/domain/repositories/codex_app_server_repository.dart mobile/lib/src/data/repositories/codex_app_server_repository.dart mobile/lib/src/data/models/codex_app_server_models.dart mobile/lib/src/services/conversation_client.dart mobile/lib/src/app/app_dependencies.dart mobile/test/codex_app_server_models_test.dart
git commit -m "Add mobile Codex app-server data layer"
```

---

### Task 14: Mobile UI For History And Discovery

**Files:**
- Create: `mobile/lib/src/ui/features/codex_app_server/codex_app_server_page.dart`
- Create: `mobile/lib/src/ui/features/codex_app_server/view_models/codex_app_server_view_model.dart`
- Create: `mobile/lib/src/ui/features/codex_app_server/widgets/*.dart`
- Modify: relevant navigation/shell file under `mobile/lib/src/ui/main/`
- Add widget tests under `mobile/test/`

- [ ] **Step 1: Add ViewModel tests**

Create `mobile/test/codex_app_server_view_model_test.dart`:

```dart
test('CodexAppServerViewModel loads capabilities and thread history', () async {
  final repository = FakeCodexAppServerRepository(
    capabilities: CodexAppServerCapabilities(totalMethods: 187),
    threads: [CodexAppServerThreadSummary(id: 'thread_1', title: 'Fix auth', archived: false)],
  );
  final viewModel = CodexAppServerViewModel(repository: repository);

  await viewModel.load(workspaceId: 'default');

  expect(viewModel.state.capabilities.totalMethods, 187);
  expect(viewModel.state.threads.single.id, 'thread_1');
});
```

- [ ] **Step 2: Implement ViewModel**

Expose immutable state:

```dart
class CodexAppServerState {
  const CodexAppServerState({
    this.loading = false,
    this.error,
    this.capabilities,
    this.threads = const <CodexAppServerThreadSummary>[],
  });

  final bool loading;
  final String? error;
  final CodexAppServerCapabilities? capabilities;
  final List<CodexAppServerThreadSummary> threads;
}
```

- [ ] **Step 3: Implement feature-local UI**

The first screen should be a work surface, not a landing page:

- Tabs: `History`, `Discovery`, `Risk Controls`
- History list: thread title, updated time, archived state, open action.
- Discovery: cards or tables for MCP servers, skills, plugins, apps, config status.
- Risk Controls: show high-risk categories and whether approval is required.

- [ ] **Step 4: Add widget tests**

Add:

```dart
testWidgets('Codex app-server page renders history and discovery tabs', (tester) async {
  await tester.pumpWidget(buildCodexAppServerPageForTest());
  expect(find.text('History'), findsOneWidget);
  expect(find.text('Discovery'), findsOneWidget);
  expect(find.text('Risk Controls'), findsOneWidget);
});
```

- [ ] **Step 5: Run mobile checks**

```powershell
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
flutter test --no-pub test\codex_app_server_view_model_test.dart
flutter test --no-pub test\widget_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/src/ui/features/codex_app_server mobile/lib/src/ui/main mobile/test
git commit -m "Add mobile Codex app-server management UI"
```

---

### Task 15: End-To-End Verification And Release Gate

**Files:**
- Modify: `scripts/run-tests.js`
- Modify: `docs/project-knowledge/troubleshooting-playbook.md`
- Modify: `docs/project-knowledge/build-and-test.md`

- [ ] **Step 1: Add full parity smoke test**

Add a daemon test that asserts:

```javascript
test('Codex app-server full parity smoke gate is satisfied', () => {
  const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('../daemon/src/codex-app-server/capability-matrix');
  assert.equal(CODEX_APP_SERVER_CAPABILITY_MATRIX.some((row) => row.localStatus === 'unsupported'), false);
  assert.equal(CODEX_APP_SERVER_CAPABILITY_MATRIX.some((row) => row.risk === 'unknown'), false);
  assert.equal(CODEX_APP_SERVER_CAPABILITY_MATRIX.filter((row) => row.localStatus === 'supported').length > 100, true);
});

test('Codex app-server model normalization failure is isolated to that adapter', async () => {
  const app = createApp({
    port: 0,
    codexAppServerProbe: false,
    codexAppServerModelLister: async () => ({ data: [{ id: null, name: {} }] }),
    appDbPath: tempConversationDbPath('app-server-model-isolation-')
  });
  const pair = app.auth.createPairingCode();
  const paired = app.auth.pair(pair.code, 'models', 'device_models');
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await request(app.server.address().port, 'GET', '/api/adapters', null, {
      authorization: `Bearer ${paired.accessToken}`
    });
    assert.equal(response.status, 200);
    assert.ok(Array.isArray(response.body.adapters));
    assert.ok(response.body.adapters.some((adapter) => adapter.id !== 'codex-app-server'));
  } finally {
    app.server.close();
    app.appSqliteStore.close();
  }
});
```

- [ ] **Step 2: Run full daemon verification**

```powershell
node scripts\run-tests.js
npm run lint
node scripts\check-project-knowledge.js
```

Expected:

```text
tests passed
No lint errors
Project knowledge check passed
```

- [ ] **Step 3: Run mobile verification**

From `mobile/`:

```powershell
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
flutter test --no-pub
```

Expected:

```text
No issues found
All tests passed
```

- [ ] **Step 4: Update project knowledge**

Add a troubleshooting entry explaining:

- app-server route service process reuse policy
- high-risk approval/audit flow
- schema drift matrix update steps
- how mobile should consume daemon app-server APIs

- [ ] **Step 5: Commit**

```bash
git add scripts/run-tests.js docs/project-knowledge/troubleshooting-playbook.md docs/project-knowledge/build-and-test.md
git commit -m "Add Codex app-server full parity release gate"
```

---

## Self-Review

Spec coverage:

- Contract and matrix: preserved and tightened through Task 11.
- Typed client: extended in Tasks 3-10.
- Thread/history: Task 3 and Task 7.
- Discovery: Task 4 and Task 5.
- High-risk operations: Task 8 and Task 9.
- Operational safety gates: Task 12.
- Mobile consumption: Task 13 and Task 14.
- Testing and release gate: Task 15.

No raw RPC route is introduced. Every high-risk method is routed through typed service boundaries, authorization, approval/policy, audit, and controlled errors. The plan intentionally keeps some APIs `diagnostic-only` or `intentionally-blocked` when full product semantics require dedicated UX or security ownership; Task 11 ensures none remain `unsupported` or `unknown`.
