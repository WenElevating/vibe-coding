# OpenCode Server Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a production OpenCode conversation adapter that uses `opencode serve`, keeps the daemon conversation API stable, and projects OpenCode events into the existing mobile Workbench contract.

**Architecture:** The daemon owns all OpenCode server lifecycle, HTTP/SSE transport, session binding, event mapping, approval handling, cancellation, and diagnostics. Mobile continues to consume existing conversation DTOs and only receives localized generic Workbench states and notices. The first implementation is conservative: no raw OpenCode routes on mobile, no SDK dependency, no model picker until verified, and no silent provider-session recreation.

**Tech Stack:** Node.js CommonJS daemon, Node standard `http`/`child_process`/`net` modules, existing `ConversationManager`, existing `scripts/run-tests.js` harness, Flutter/Dart ARB localization and Workbench widget tests for visible strings.

---

## Source Design

Implement against:

```text
docs/superpowers/specs/2026-06-07-opencode-server-integration-design.md
```

Key decisions from the design:

- OpenCode integration is server-first through `opencode serve`.
- `conversationId` remains the product identity; OpenCode session id is only `cliSessionId`.
- Mobile must not call OpenCode APIs directly.
- `/global/event` is shared SSE and every critical conversation event must carry a normalized session id before dispatch.
- If no verified read/reconcile route exists, SSE disconnect during an active turn fails immediately.
- A missing stored OpenCode session before prompt dispatch fails with visible `opencode_session_expired`; it must not silently create a fresh memoryless session.
- `providerSession` is a single OpenCode session-scoped object and clears unconditionally with OpenCode session binding.

## File Structure

Create:

- `docs/superpowers/fixtures/opencode-server/README.md`
  - Explains the local OpenCode smoke contract and when real model-consuming smoke is allowed.
- `docs/superpowers/fixtures/opencode-server/manifest.json`
  - Records verified route, event, permission, reconnect, and terminal status gates.
- `docs/superpowers/fixtures/opencode-server/smoke-report-template.md`
  - Manual report shape for a real `opencode serve` run.
- `docs/superpowers/fixtures/opencode-server/samples/.gitkeep`
  - Keeps the sample directory tracked before real samples are captured.
- `scripts/smoke-opencode-server.js`
  - Optional real-runtime smoke runner. It must default to non-model-consuming checks and require `--allow-prompt-dispatch` before sending a prompt that could consume provider quota.
- `daemon/test/fakes/fake-opencode-server.js`
  - Deterministic fake server used by daemon tests.
- `daemon/src/opencode-event-mapper.js`
  - Pure OpenCode event to `conversationEventTypes` mapper.
- `daemon/src/opencode-server-client.js`
  - Node standard-library HTTP/SSE client for OpenCode server routes.
- `daemon/src/opencode-server-lifecycle.js`
  - External/managed server owner, explicit port selection, health probing, process cleanup.
- `daemon/src/opencode-conversation-adapter.js`
  - Conversation adapter and handle that implement `startConversation`, `sendUserMessage`, `respondApproval`, `cancel`, and `dispose`.

Modify:

- `daemon/src/main.js`
  - Wire `opencodeCommand`, optional `OPENCODE_SERVER_URL`, lifecycle, listing diagnostics, and `OpenCodeConversationAdapter`.
- `daemon/src/opencode-adapter.js`
  - Keep as adapter listing/probe surface, but align diagnostics with external vs managed lifecycle.
- `daemon/src/conversation-manager.js`
  - Add internal session binding helpers and pass narrow helper callbacks into adapters.
- `scripts/run-tests.js`
  - Add daemon regression tests for smoke fixtures, mapper, client, lifecycle, manager helpers, adapter integration, permission, cancellation, SSE failure, and diagnostics.
- `mobile/lib/l10n/app_en.arb`
  - Add English strings for visible OpenCode notices/errors.
- `mobile/lib/l10n/app_zh.arb`
  - Add Chinese strings for the same visible states.
- `mobile/lib/src/ui/features/workbench/messages/notice_event_card.dart`
  - Render visible OpenCode session recovery notices through localization.
- `mobile/lib/src/ui/features/workbench/widgets/workbench_run_error_card.dart`
  - Use localized label text when visible OpenCode error copy is rendered.
- `mobile/test/conversation_reducer_test.dart` or nearest Workbench message test
  - Cover visible OpenCode notice projection.
- `mobile/test/widget_test.dart` or nearest Workbench widget test
  - Cover localized notice/error rendering if new UI text is visible.

Do not create a new mobile OpenCode feature area. Do not add files under retired mobile roots: `mobile/lib/src/features`, `mobile/lib/src/widgets`, `mobile/lib/src/theme`, or `mobile/lib/src/state`.

---

### Task 1: OpenCode Smoke Fixture Contract

**Files:**
- Create: `docs/superpowers/fixtures/opencode-server/README.md`
- Create: `docs/superpowers/fixtures/opencode-server/manifest.json`
- Create: `docs/superpowers/fixtures/opencode-server/smoke-report-template.md`
- Create: `docs/superpowers/fixtures/opencode-server/samples/.gitkeep`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write the failing fixture test**

Add near the existing fixture/manifest tests in `scripts/run-tests.js`:

```javascript
test('OpenCode server smoke manifest has explicit gate results', () => {
  const manifestPath = path.join(
    __dirname,
    '..',
    'docs',
    'superpowers',
    'fixtures',
    'opencode-server',
    'manifest.json'
  );
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.schemaVersion, 1);
  assert.ok(['not_run', 'pass', 'fail', 'blocked'].includes(manifest.status));
  if (manifest.status === 'not_run') return;
  for (const [gate, result] of Object.entries(manifest.gates || {})) {
    assert.ok(['pass', 'fail', 'blocked'].includes(result), `${gate} has invalid result ${result}`);
  }
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
ENOENT ... docs\superpowers\fixtures\opencode-server\manifest.json
```

- [ ] **Step 3: Create the smoke fixture files**

Create `docs/superpowers/fixtures/opencode-server/manifest.json`:

```json
{
  "schemaVersion": 1,
  "adapter": "opencode",
  "status": "not_run",
  "verifiedAt": null,
  "opencodeVersion": null,
  "gates": {
    "health": "not_run",
    "doc": "not_run",
    "sessionCreateDirectory": "not_run",
    "promptAsyncBody": "not_run",
    "abort": "not_run",
    "permissionResponseBody": "not_run",
    "globalEventSse": "not_run",
    "sessionIdFieldNames": "not_run",
    "sessionReadReconcile": "not_run",
    "sessionStatusTerminalValues": "not_run",
    "historyReplay": "blocked"
  },
  "samples": []
}
```

Create `docs/superpowers/fixtures/opencode-server/README.md`:

```markdown
# OpenCode Server Smoke Fixtures

These fixtures record the local contract observed from `opencode serve`.
The daemon implementation must not rely on an OpenCode route body, event field,
permission reply shape, session reconciliation route, or terminal session status
until this fixture records it as `pass`.

The smoke runner defaults to non-model-consuming checks. A prompt dispatch check
requires an explicit `--allow-prompt-dispatch` flag.
```

Create `docs/superpowers/fixtures/opencode-server/smoke-report-template.md`:

```markdown
# OpenCode Server Smoke Report

- Date:
- OpenCode version:
- Command:
- Workspace:
- Prompt dispatch enabled:

## Gates

| Gate | Result | Evidence |
| --- | --- | --- |
| health |  |  |
| doc |  |  |
| sessionCreateDirectory |  |  |
| promptAsyncBody |  |  |
| abort |  |  |
| permissionResponseBody |  |  |
| globalEventSse |  |  |
| sessionIdFieldNames |  |  |
| sessionReadReconcile |  |  |
| sessionStatusTerminalValues |  |  |
| historyReplay | blocked | First implementation does not replay history into replacement sessions. |
```

Create empty file:

```text
docs/superpowers/fixtures/opencode-server/samples/.gitkeep
```

- [ ] **Step 4: Run the fixture test and commit**

Run:

```powershell
node scripts\run-tests.js
node scripts\check-project-knowledge.js
```

Expected:

```text
All tests passed
Project knowledge check passed
```

Commit:

```bash
git add -f docs/superpowers/fixtures/opencode-server scripts/run-tests.js
git commit -m "Add OpenCode server smoke fixture contract"
```

---

### Task 2: Real Smoke Helper And Fake Server

**Files:**
- Create: `scripts/smoke-opencode-server.js`
- Create: `daemon/test/fakes/fake-opencode-server.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing helper tests**

Add tests in `scripts/run-tests.js`:

```javascript
test('OpenCode smoke helper parses SSE events', () => {
  const { parseOpenCodeSseFrames } = require('./smoke-opencode-server');
  const frames = parseOpenCodeSseFrames([
    'event: message',
    'data: {"type":"session.idle","sessionID":"sess_1"}',
    '',
    'data: {"type":"permission.asked","session_id":"sess_1","id":"perm_1"}',
    ''
  ].join('\n'));

  assert.deepEqual(frames.map((frame) => frame.type), ['session.idle', 'permission.asked']);
  assert.equal(frames[0].sessionID, 'sess_1');
  assert.equal(frames[1].session_id, 'sess_1');
});

test('fake OpenCode server supports session, prompt, abort, permission, and SSE', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const baseUrl = fake.url;
    const health = await fetchJsonForTest(`${baseUrl}/global/health`);
    assert.equal(health.ok, true);

    const session = await fetchJsonForTest(`${baseUrl}/session?directory=${encodeURIComponent(process.cwd())}`, {
      method: 'POST',
      body: '{}'
    });
    assert.equal(session.directory, process.cwd());
    assert.ok(session.id);

    const prompt = await fetchJsonForTest(`${baseUrl}/session/${session.id}/prompt_async`, {
      method: 'POST',
      body: JSON.stringify({ parts: [{ type: 'text', text: 'hello' }] })
    });
    assert.equal(prompt.ok, true);

    const abort = await fetchJsonForTest(`${baseUrl}/session/${session.id}/abort`, {
      method: 'POST',
      body: '{}'
    });
    assert.equal(abort, true);

    fake.emitEvent({ type: 'session.idle', sessionID: session.id });
    assert.equal(fake.events.length, 1);
  } finally {
    await fake.close();
  }
});
```

Add this test helper once if no equivalent helper exists near the test:

```javascript
async function fetchJsonForTest(url, options = {}) {
  const parsed = new URL(url);
  const payload = options.body || '';
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: parsed.hostname,
      port: parsed.port,
      path: `${parsed.pathname}${parsed.search}`,
      method: options.method || 'GET',
      headers: payload ? {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload)
      } : undefined
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(text ? JSON.parse(text) : null);
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
Cannot find module './smoke-opencode-server'
```

- [ ] **Step 3: Implement smoke helper exports**

Create `scripts/smoke-opencode-server.js` with these exported pure helpers first:

```javascript
'use strict';

function parseOpenCodeSseFrames(text) {
  const frames = [];
  let dataLines = [];
  for (const rawLine of String(text || '').split(/\r?\n/)) {
    const line = rawLine.trimEnd();
    if (line === '') {
      pushFrame(frames, dataLines);
      dataLines = [];
      continue;
    }
    if (line.startsWith('data:')) dataLines.push(line.slice(5).trimStart());
  }
  pushFrame(frames, dataLines);
  return frames;
}

function pushFrame(frames, dataLines) {
  if (!dataLines.length) return;
  const text = dataLines.join('\n').trim();
  if (!text) return;
  try {
    frames.push(JSON.parse(text));
  } catch (error) {
    frames.push({ type: 'parse.error', message: error.message, raw: text.slice(0, 4096) });
  }
}

module.exports = {
  parseOpenCodeSseFrames
};

if (require.main === module) {
  console.log('OpenCode smoke helper loaded. Use the implementation task to add live route probes.');
}
```

- [ ] **Step 4: Implement fake OpenCode server**

Create `daemon/test/fakes/fake-opencode-server.js`:

```javascript
'use strict';

const http = require('node:http');
const { EventEmitter } = require('node:events');

class FakeOpenCodeServer extends EventEmitter {
  constructor() {
    super();
    this.sessions = new Map();
    this.events = [];
    this.permissionReplies = [];
    this.promptBodies = [];
    this.server = http.createServer((req, res) => this.handle(req, res));
    this.sseClients = new Set();
    this.nextSessionNumber = 1;
  }

  get url() {
    const address = this.server.address();
    return `http://127.0.0.1:${address.port}`;
  }

  listen() {
    return new Promise((resolve) => this.server.listen(0, '127.0.0.1', resolve));
  }

  close() {
    for (const res of this.sseClients) res.end();
    this.sseClients.clear();
    return new Promise((resolve) => this.server.close(resolve));
  }

  emitEvent(event) {
    this.events.push(event);
    const payload = `data: ${JSON.stringify(event)}\n\n`;
    for (const res of this.sseClients) res.write(payload);
  }

  async handle(req, res) {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (req.method === 'GET' && url.pathname === '/global/health') {
      return sendJson(res, 200, { ok: true, version: 'fake-opencode' });
    }
    if (req.method === 'GET' && url.pathname === '/doc') {
      return sendJson(res, 200, { openapi: '3.0.0', paths: { '/global/event': {} } });
    }
    if (req.method === 'GET' && url.pathname === '/global/event') {
      res.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'keep-alive'
      });
      this.sseClients.add(res);
      req.on('close', () => this.sseClients.delete(res));
      return;
    }
    if (req.method === 'POST' && url.pathname === '/session') {
      await readBody(req);
      const id = `sess_${this.nextSessionNumber++}`;
      const directory = url.searchParams.get('directory') || process.cwd();
      const session = { id, sessionID: id, directory };
      this.sessions.set(id, session);
      return sendJson(res, 200, session);
    }
    const promptMatch = url.pathname.match(/^\/session\/([^/]+)\/prompt_async$/);
    if (req.method === 'POST' && promptMatch) {
      const sessionId = decodeURIComponent(promptMatch[1]);
      if (!this.sessions.has(sessionId)) return sendJson(res, 404, { error: { code: 'SESSION_NOT_FOUND' } });
      const body = await readJson(req);
      this.promptBodies.push({ sessionId, body });
      return sendJson(res, 200, { ok: true });
    }
    const abortMatch = url.pathname.match(/^\/session\/([^/]+)\/abort$/);
    if (req.method === 'POST' && abortMatch) {
      await readBody(req);
      return sendJson(res, 200, true);
    }
    const permissionMatch = url.pathname.match(/^\/session\/([^/]+)\/permissions\/([^/]+)$/);
    if (req.method === 'POST' && permissionMatch) {
      const body = await readJson(req);
      this.permissionReplies.push({
        sessionId: decodeURIComponent(permissionMatch[1]),
        permissionId: decodeURIComponent(permissionMatch[2]),
        body
      });
      return sendJson(res, 200, { ok: true });
    }
    return sendJson(res, 404, { error: { code: 'NOT_FOUND' } });
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

async function readJson(req) {
  const text = await readBody(req);
  return text ? JSON.parse(text) : {};
}

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(payload)
  });
  res.end(payload);
}

module.exports = { FakeOpenCodeServer };
```

- [ ] **Step 5: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
All tests passed
```

Commit:

```bash
git add scripts/smoke-opencode-server.js daemon/test/fakes/fake-opencode-server.js scripts/run-tests.js
git commit -m "Add OpenCode server smoke helpers"
```

---

### Task 3: Pure OpenCode Event Mapper

**Files:**
- Create: `daemon/src/opencode-event-mapper.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing mapper tests**

Add tests:

```javascript
test('OpenCode event mapper maps idle, errors, assistant deltas, and permissions', () => {
  const { mapOpenCodeEvent } = require('../daemon/src/opencode-event-mapper');

  assert.deepEqual(mapOpenCodeEvent({ type: 'session.idle', sessionID: 'sess_1' }), {
    type: conversationEventTypes.CONVERSATION_COMPLETED,
    sessionId: 'sess_1',
    rawType: 'session.idle'
  });

  assert.deepEqual(mapOpenCodeEvent({
    type: 'message.part.delta',
    session_id: 'sess_1',
    part: { type: 'text', text: 'hello' }
  }), {
    type: conversationEventTypes.ASSISTANT_PARTIAL,
    sessionId: 'sess_1',
    text: 'hello',
    rawType: 'message.part.delta'
  });

  const approval = mapOpenCodeEvent({
    type: 'permission.asked',
    sessionID: 'sess_1',
    id: 'perm_1',
    toolCallID: 'tool_1',
    tool: 'bash',
    command: 'npm test'
  });
  assert.equal(approval.type, conversationEventTypes.APPROVAL_REQUESTED);
  assert.equal(approval.sessionId, 'sess_1');
  assert.equal(approval.approvalId, 'perm_1');
  assert.equal(approval.toolUseId, 'tool_1');
  assert.equal(approval.approvalOptions.kind, 'command');
  assert.equal(approval.approvalOptions.supportsSessionScope, true);
  assert.equal(approval.approvalOptions.supportsCancel, false);
});

test('OpenCode event mapper drops critical events without session id', () => {
  const { mapOpenCodeEvent } = require('../daemon/src/opencode-event-mapper');
  const event = mapOpenCodeEvent({ type: 'permission.asked', id: 'perm_missing' });
  assert.equal(event.type, conversationEventTypes.PROTOCOL_WARNING);
  assert.equal(event.warning, 'opencode_critical_event_missing_session_id');
  assert.equal(event.dispatchable, false);
});

test('OpenCode session.status does not complete until terminal whitelist is configured', () => {
  const { mapOpenCodeEvent } = require('../daemon/src/opencode-event-mapper');
  const event = mapOpenCodeEvent({ type: 'session.status', sessionID: 'sess_1', status: 'done' });
  assert.equal(event.type, conversationEventTypes.SYSTEM_NOTICE);
  assert.equal(event.visible, false);
  assert.equal(event.noticeKind, 'opencode_session_status');
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
Cannot find module '../daemon/src/opencode-event-mapper'
```

- [ ] **Step 3: Implement mapper**

Create `daemon/src/opencode-event-mapper.js`:

```javascript
'use strict';

const path = require('node:path');
const { conversationEventTypes } = require('./conversation-protocol');

const CRITICAL_PREFIXES = ['message.', 'permission.', 'session.status', 'session.idle', 'session.error', 'session.diff'];

function mapOpenCodeEvent(raw, { workspacePath = null, terminalSessionStatuses = [] } = {}) {
  if (!plainObject(raw)) return null;
  const rawType = stringValue(raw.type || raw.event || raw.kind);
  if (!rawType) return unknownNotice(raw, 'opencode_unknown_event');
  const sessionId = normalizeId(raw, ['sessionID', 'sessionId', 'session_id', 'session']);
  if (isCritical(rawType) && !sessionId) {
    return {
      type: conversationEventTypes.PROTOCOL_WARNING,
      warning: 'opencode_critical_event_missing_session_id',
      dispatchable: false,
      rawType,
      raw: boundRaw(raw)
    };
  }
  if (rawType === 'session.idle') {
    return { type: conversationEventTypes.CONVERSATION_COMPLETED, sessionId, rawType };
  }
  if (rawType === 'session.error') {
    const message = stringValue(raw.message || raw.error?.message) || 'OpenCode session error';
    return { type: conversationEventTypes.RUN_ERROR, sessionId, message, code: stringValue(raw.code || raw.error?.code) || 'OPENCODE_SESSION_ERROR', rawType };
  }
  if (rawType === 'session.status') {
    const status = stringValue(raw.status);
    if (status && terminalSessionStatuses.includes(status)) {
      return { type: conversationEventTypes.CONVERSATION_COMPLETED, sessionId, status, rawType };
    }
    return {
      type: conversationEventTypes.SYSTEM_NOTICE,
      noticeKind: 'opencode_session_status',
      visible: false,
      sessionId,
      status,
      rawType
    };
  }
  if (rawType === 'message.part.delta') {
    const text = stringValue(raw.delta || raw.text || raw.part?.text || raw.part?.delta);
    const partKind = stringValue(raw.part?.type || raw.partType || raw.kind);
    if (!text) return hiddenNotice(raw, sessionId, rawType);
    if (/thinking|reasoning/i.test(partKind)) {
      return { type: conversationEventTypes.ASSISTANT_THINKING, sessionId, text, rawType };
    }
    return { type: conversationEventTypes.ASSISTANT_PARTIAL, sessionId, text, rawType };
  }
  if (rawType === 'message.updated' || rawType === 'message.part.updated') {
    const text = stringValue(raw.message?.text || raw.part?.text || raw.text);
    if (text) return { type: conversationEventTypes.ASSISTANT_MESSAGE, sessionId, text, rawType };
    return hiddenNotice(raw, sessionId, rawType);
  }
  if (rawType === 'permission.asked') {
    return mapPermissionAsked(raw, sessionId, rawType);
  }
  if (rawType === 'permission.replied') {
    return {
      type: conversationEventTypes.APPROVAL_RESOLVED,
      sessionId,
      approvalId: normalizeId(raw, ['permissionID', 'permissionId', 'permission_id', 'id']),
      decision: stringValue(raw.decision || raw.reply || raw.status) || 'resolved',
      rawType
    };
  }
  if (rawType === 'session.diff') {
    return mapDiff(raw, sessionId, rawType);
  }
  if (rawType === 'file.edited') {
    return mapFileEdited(raw, sessionId, rawType, workspacePath);
  }
  return unknownNotice(raw, 'opencode_unknown_event', sessionId, rawType);
}

function mapPermissionAsked(raw, sessionId, rawType) {
  const approvalId = normalizeId(raw, ['permissionID', 'permissionId', 'permission_id', 'id']);
  const toolUseId = normalizeId(raw, ['toolCallID', 'toolCallId', 'tool_call_id', 'toolUseId']);
  const toolName = stringValue(raw.tool || raw.toolName || raw.name) || 'OpenCode permission';
  const command = stringValue(raw.command || raw.input?.command);
  const filePath = stringValue(raw.path || raw.filePath || raw.input?.path || raw.input?.file_path);
  const kind = command ? 'command' : filePath ? 'file_change' : 'generic';
  return {
    type: conversationEventTypes.APPROVAL_REQUESTED,
    sessionId,
    approvalId,
    toolUseId,
    toolName,
    summary: command || filePath || toolName,
    input: plainObject(raw.input) ? raw.input : {},
    approvalOptions: {
      kind,
      command: command || undefined,
      supportsSessionScope: true,
      supportsCancel: false,
      denyBehavior: 'interrupt'
    },
    rawType
  };
}

function mapDiff(raw, sessionId, rawType) {
  const files = Array.isArray(raw.files) ? raw.files : [];
  if (!files.length) return hiddenNotice(raw, sessionId, rawType);
  return {
    type: conversationEventTypes.DIFF_SUMMARY,
    sessionId,
    files: files.map((file) => ({
      path: stringValue(file.path),
      additions: Number.isInteger(file.additions) ? file.additions : 0,
      deletions: Number.isInteger(file.deletions) ? file.deletions : 0
    })),
    rawType
  };
}

function mapFileEdited(raw, sessionId, rawType, workspacePath) {
  const filePath = stringValue(raw.path || raw.filePath);
  const relativePath = workspacePath ? safeRelativePath(workspacePath, filePath) : filePath;
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    noticeKind: 'opencode_file_edited',
    visible: true,
    sessionId,
    text: relativePath ? `OpenCode edited ${relativePath}` : 'OpenCode edited a file',
    rawType
  };
}

function hiddenNotice(raw, sessionId, rawType) {
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    noticeKind: 'opencode_hidden_event',
    visible: false,
    sessionId,
    rawType,
    raw: boundRaw(raw)
  };
}

function unknownNotice(raw, noticeKind, sessionId = null, rawType = '') {
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    noticeKind,
    visible: false,
    ...(sessionId ? { sessionId } : {}),
    ...(rawType ? { rawType } : {}),
    raw: boundRaw(raw)
  };
}

function normalizeId(raw, keys) {
  for (const key of keys) {
    const value = key === 'session' && plainObject(raw.session) ? raw.session.id : raw[key];
    const text = stringValue(value);
    if (text) return text;
  }
  return null;
}

function safeRelativePath(workspacePath, filePath) {
  if (!filePath) return '';
  const relative = path.relative(workspacePath, filePath);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) return path.basename(filePath);
  return relative;
}

function isCritical(rawType) {
  return CRITICAL_PREFIXES.some((prefix) => rawType === prefix || rawType.startsWith(prefix));
}

function boundRaw(raw) {
  const text = JSON.stringify(raw);
  return JSON.parse(text.length > 4096 ? `${text.slice(0, 4093)}...` : text);
}

function plainObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function stringValue(value) {
  if (typeof value !== 'string' && typeof value !== 'number') return '';
  return String(value).trim();
}

module.exports = {
  mapOpenCodeEvent
};
```

- [ ] **Step 4: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected:

```text
All tests passed
No lint errors
```

Commit:

```bash
git add daemon/src/opencode-event-mapper.js scripts/run-tests.js
git commit -m "Map OpenCode server events to conversation events"
```

---

### Task 4: OpenCode Server HTTP/SSE Client

**Files:**
- Create: `daemon/src/opencode-server-client.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing client tests**

Add tests:

```javascript
test('OpenCode server client probes health, creates sessions, prompts, aborts, and replies to permissions', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const health = await client.health();
    assert.equal(health.ok, true);
    const session = await client.createSession({ directory: process.cwd() });
    assert.equal(session.id, 'sess_1');
    await client.promptAsync({ sessionId: session.id, text: 'hello' });
    assert.deepEqual(fake.promptBodies[0].body, { parts: [{ type: 'text', text: 'hello' }] });
    await client.replyPermission({ sessionId: session.id, permissionId: 'perm_1', decision: 'allow', scope: 'session' });
    assert.deepEqual(fake.permissionReplies[0].body, { response: 'always' });
    const aborted = await client.abortSession({ sessionId: session.id });
    assert.equal(aborted, true);
  } finally {
    await fake.close();
  }
});

test('OpenCode server client subscribes to shared SSE stream', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const events = [];
    const subscription = client.subscribeEvents((event) => events.push(event));
    await waitForCondition(() => fake.sseClients.size === 1);
    fake.emitEvent({ type: 'session.idle', sessionID: 'sess_1' });
    await waitForCondition(() => events.length === 1);
    assert.equal(events[0].type, 'session.idle');
    subscription.close();
  } finally {
    await fake.close();
  }
});
```

Add once if no equivalent helper exists:

```javascript
async function waitForCondition(predicate, timeoutMs = 1000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error('condition was not met before timeout');
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
Cannot find module '../daemon/src/opencode-server-client'
```

- [ ] **Step 3: Implement client**

Create `daemon/src/opencode-server-client.js` with these public methods:

```javascript
class OpenCodeServerClient {
  constructor({ baseUrl, requestTimeoutMs = 30000, httpRequest = requestJson, httpStream = requestStream } = {}) {}
  health() {}
  createSession({ directory }) {}
  readSession({ sessionId }) {}
  promptAsync({ sessionId, text }) {}
  abortSession({ sessionId }) {}
  replyPermission({ sessionId, permissionId, decision, scope }) {}
  subscribeEvents(onEvent, onError) {}
}
```

The request body builders must be:

```javascript
function buildPromptAsyncBody(text) {
  return { parts: [{ type: 'text', text: String(text || '') }] };
}

function buildPermissionReplyBody(decision, scope) {
  if (decision === 'allow' && scope === 'session') return { response: 'always' };
  if (decision === 'allow') return { response: 'once' };
  return { response: 'reject' };
}
```

The error factory must preserve safe status/code:

```javascript
function opencodeHttpError(status, payload, fallbackMessage) {
  const provider = payload && typeof payload === 'object' ? payload.error || payload : {};
  const error = new Error(String(provider.message || fallbackMessage || `OpenCode HTTP ${status}`));
  error.status = status;
  error.code = String(provider.code || `OPENCODE_HTTP_${status}`);
  error.details = { status, code: error.code };
  return error;
}
```

The SSE subscription must parse `data:` frames incrementally and expose:

```javascript
return {
  close() {
    closed = true;
    req.destroy();
  }
};
```

Use only Node standard modules. Do not add an HTTP/SSE package.

- [ ] **Step 4: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected:

```text
All tests passed
No lint errors
```

Commit:

```bash
git add daemon/src/opencode-server-client.js scripts/run-tests.js
git commit -m "Add OpenCode server HTTP client"
```

---

### Task 5: OpenCode Server Lifecycle

**Files:**
- Create: `daemon/src/opencode-server-lifecycle.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing lifecycle tests**

Add tests:

```javascript
test('OpenCode lifecycle uses external server URL without spawning', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerLifecycle } = require('../daemon/src/opencode-server-lifecycle');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const lifecycle = new OpenCodeServerLifecycle({
      externalUrl: fake.url,
      spawnFn: () => { throw new Error('must not spawn for external server'); }
    });
    const client = await lifecycle.getClient();
    const health = await client.health();
    assert.equal(health.ok, true);
  } finally {
    await fake.close();
  }
});

test('OpenCode lifecycle retries managed port at most three times', async () => {
  const { OpenCodeServerLifecycle } = require('../daemon/src/opencode-server-lifecycle');
  let spawnCount = 0;
  const lifecycle = new OpenCodeServerLifecycle({
    command: 'opencode',
    spawnFn() {
      spawnCount += 1;
      return fakeNeverHealthyChild(spawnCount);
    },
    pickPort: (() => {
      let port = 43000;
      return async () => port++;
    })(),
    sleep: async () => {},
    healthTimeoutMs: 5
  });
  await assert.rejects(
    () => lifecycle.getClient(),
    (error) => error.code === 'OPENCODE_SERVER_PORT_UNAVAILABLE'
  );
  assert.equal(spawnCount, 3);
});

test('OpenCode lifecycle hides managed server window and disables mdns', async () => {
  const { OpenCodeServerLifecycle } = require('../daemon/src/opencode-server-lifecycle');
  const calls = [];
  const lifecycle = new OpenCodeServerLifecycle({
    command: 'opencode',
    spawnFn(command, args, options) {
      calls.push({ command, args, options });
      return fakeNeverHealthyChild(1);
    },
    pickPort: async () => 43199,
    sleep: async () => {},
    healthTimeoutMs: 5
  });
  await assert.rejects(() => lifecycle.getClient());
  assert.equal(calls[0].command, 'opencode');
  assert.deepEqual(calls[0].args, ['serve', '--hostname', '127.0.0.1', '--port', '43199']);
  assert.equal(calls[0].options.windowsHide, true);
});
```

Add the fake child helper:

```javascript
function fakeNeverHealthyChild(pid = 1) {
  const child = new EventEmitter();
  child.pid = pid;
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.kill = (signal) => {
    setImmediate(() => child.emit('exit', null, signal));
    return true;
  };
  return child;
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
Cannot find module '../daemon/src/opencode-server-lifecycle'
```

- [ ] **Step 3: Implement lifecycle**

Create `daemon/src/opencode-server-lifecycle.js` with:

```javascript
class OpenCodeServerLifecycle {
  constructor({
    externalUrl = process.env.OPENCODE_SERVER_URL || null,
    command = process.env.OPENCODE_COMMAND || 'opencode',
    spawnFn = spawn,
    spawnSyncFn = spawnSync,
    pickPort = pickLoopbackPort,
    sleep = delay,
    requestTimeoutMs = 30000,
    healthTimeoutMs = 5000,
    maxPortAttempts = 3,
    cleanupDelayMs = 250,
    processTreeTerminator = defaultOpenCodeProcessTreeTerminator
  } = {}) {}

  async getClient() {}
  async shutdown() {}
}
```

Managed startup must:

```javascript
const child = spawnFn(command, ['serve', '--hostname', '127.0.0.1', '--port', String(port)], {
  stdio: ['ignore', 'pipe', 'pipe'],
  windowsHide: true
});
```

The retry loop must:

```javascript
for (let attempt = 1; attempt <= maxPortAttempts; attempt += 1) {
  const port = await pickPort();
  const child = spawnManaged(port);
  try {
    const client = new OpenCodeServerClient({ baseUrl: `http://127.0.0.1:${port}`, requestTimeoutMs });
    await waitForHealth(client, healthTimeoutMs);
    this.child = child;
    this.client = client;
    return client;
  } catch (error) {
    await terminateChildTree(child, processTreeTerminator);
    await sleep(cleanupDelayMs);
    lastError = error;
  }
}
const error = new Error('OpenCode managed server port unavailable after 3 attempts');
error.status = 503;
error.code = 'OPENCODE_SERVER_PORT_UNAVAILABLE';
error.cause = lastError;
throw error;
```

Windows process cleanup must call `taskkill /PID <pid> /T /F` through `spawnSync` after a short graceful wait when the child is still alive.

- [ ] **Step 4: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected:

```text
All tests passed
No lint errors
```

Commit:

```bash
git add daemon/src/opencode-server-lifecycle.js scripts/run-tests.js
git commit -m "Manage OpenCode server lifecycle"
```

---

### Task 6: ConversationManager Session Binding Helpers

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing manager helper tests**

Add tests:

```javascript
test('ConversationManager clearSessionBinding clears OpenCode provider session', () => {
  const manager = createTestConversationManager();
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'opencode' }, device);
  const internal = manager.conversations.get(conversation.id);
  internal.cliSessionId = 'sess_1';
  internal.sessionBinding = 'confirmed';
  internal.providerSession = { provider: 'opencode', threadId: 'sess_1', cwd: process.cwd() };

  const result = manager.clearSessionBinding(internal, {
    expectedSessionId: 'sess_1',
    reason: 'missing',
    code: 'OPENCODE_SESSION_MISSING',
    noticeKind: 'opencode_session_expired',
    visible: true
  });

  assert.equal(result.cleared, true);
  assert.equal(internal.cliSessionId, null);
  assert.equal(internal.sessionBinding, 'unknown');
  assert.equal(internal.providerSession, null);
  const events = manager.eventStore.list(internal.id, 0);
  assert.equal(events.some((event) => event.type === conversationEventTypes.SYSTEM_NOTICE && event.noticeKind === 'opencode_session_expired'), true);
});

test('ConversationManager clearSessionBinding refuses stale expected session id', () => {
  const manager = createTestConversationManager();
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'opencode' }, device);
  const internal = manager.conversations.get(conversation.id);
  internal.cliSessionId = 'sess_current';
  const result = manager.clearSessionBinding(internal, { expectedSessionId: 'sess_old', reason: 'stale' });
  assert.equal(result.cleared, false);
  assert.equal(result.conflict, true);
  assert.equal(internal.cliSessionId, 'sess_current');
});
```

Use an existing test manager helper if present. If not, add:

```javascript
function createTestConversationManager({ adapters = null } = {}) {
  const workspaces = new WorkspaceRegistry();
  const device = { id: 'device_seed', allowedWorkspaceIds: new Set() };
  workspaces.seedDefault({ id: 'default', name: 'Default', workspacePath: process.cwd() }, device);
  return new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore(),
    auditLog: new AuditLog(),
    adapters: adapters || new Map([
      ['opencode', { capabilities: {}, startConversation: async () => ({ sendUserMessage: async () => {} }) }]
    ])
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
manager.clearSessionBinding is not a function
```

- [ ] **Step 3: Add helpers and adapter callback wiring**

Add methods to `ConversationManager`:

```javascript
clearSessionBinding(conversation, {
  expectedSessionId = null,
  reason = 'cleared',
  code = 'SESSION_BINDING_CLEARED',
  noticeKind = 'session_binding_cleared',
  visible = false
} = {}) {
  if (expectedSessionId && conversation.cliSessionId && conversation.cliSessionId !== expectedSessionId) {
    return { cleared: false, conflict: true, currentSessionId: conversation.cliSessionId };
  }
  const clearedSessionId = conversation.cliSessionId || null;
  conversation.cliSessionId = null;
  conversation.sessionBinding = conversationSessionBindings.UNKNOWN;
  conversation.providerSession = null;
  this.touch(conversation);
  this.eventStore.append(conversation.id, conversationEventTypes.SYSTEM_NOTICE, {
    noticeKind,
    visible,
    reason,
    code,
    clearedSessionId
  });
  return { cleared: true, clearedSessionId };
}

markSessionBindingDrifted(conversation, {
  expectedSessionId = null,
  receivedSessionId = null,
  reason = 'session_binding_drifted',
  code = 'SESSION_BINDING_DRIFTED',
  clear = false
} = {}) {
  if (expectedSessionId && conversation.cliSessionId && conversation.cliSessionId !== expectedSessionId) {
    return { marked: false, conflict: true, currentSessionId: conversation.cliSessionId };
  }
  conversation.sessionBinding = conversationSessionBindings.DRIFTED;
  if (clear) {
    conversation.cliSessionId = null;
    conversation.providerSession = null;
  }
  this.touch(conversation);
  this.eventStore.append(conversation.id, conversationEventTypes.PROTOCOL_WARNING, {
    warning: reason,
    code,
    expectedSessionId,
    receivedSessionId,
    cleared: clear === true
  });
  return { marked: true };
}
```

Modify `startConversationWithAdapter()` to pass only narrow callbacks:

```javascript
sessionBinding: {
  clear: (options) => this.clearSessionBinding(conversation, options),
  markDrifted: (options) => this.markSessionBindingDrifted(conversation, options)
}
```

Adapters must use those callbacks and must not mutate `conversation.cliSessionId`, `sessionBinding`, or `providerSession` directly.

- [ ] **Step 4: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected:

```text
All tests passed
No lint errors
```

Commit:

```bash
git add daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Add conversation session binding helpers"
```

---

### Task 7: OpenCode Conversation Adapter

**Files:**
- Create: `daemon/src/opencode-conversation-adapter.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing adapter tests**

Add tests:

```javascript
test('OpenCode conversation adapter creates session, binds provider session, sends prompt, and completes on idle', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const { OpenCodeConversationAdapter } = require('../daemon/src/opencode-conversation-adapter');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const events = [];
    const adapter = new OpenCodeConversationAdapter({ lifecycle: { getClient: async () => client } });
    const handle = await adapter.startConversation({
      conversationId: 'conv_1',
      workspacePath: process.cwd(),
      permissionMode: 'default',
      onEvent: (event) => events.push(event)
    });
    await waitForCondition(() => fake.sseClients.size === 1);
    await handle.sendUserMessage('hello');
    assert.equal(fake.promptBodies[0].sessionId, 'sess_1');
    fake.emitEvent({ type: 'session.idle', sessionID: 'sess_1' });
    await waitForCondition(() => events.some((event) => event.type === conversationEventTypes.CONVERSATION_COMPLETED));
    assert.equal(events.some((event) => event.sessionId === 'sess_1'), true);
    assert.equal(events.some((event) => event.providerSession?.provider === 'opencode'), true);
  } finally {
    await fake.close();
  }
});

test('OpenCode conversation adapter fails auto permission mode clearly', async () => {
  const { OpenCodeConversationAdapter } = require('../daemon/src/opencode-conversation-adapter');
  const adapter = new OpenCodeConversationAdapter({ lifecycle: { getClient: async () => ({}) } });
  await assert.rejects(
    () => adapter.startConversation({ workspacePath: process.cwd(), permissionMode: 'auto', onEvent: () => {} }),
    (error) => error.status === 422 && error.code === 'OPENCODE_PERMISSION_MODE_UNSUPPORTED'
  );
});

test('OpenCode conversation adapter rejects missing stored session before prompt dispatch', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const { OpenCodeConversationAdapter } = require('../daemon/src/opencode-conversation-adapter');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const cleared = [];
    const adapter = new OpenCodeConversationAdapter({ lifecycle: { getClient: async () => client } });
    const handle = await adapter.startConversation({
      conversationId: 'conv_1',
      workspacePath: process.cwd(),
      sessionId: 'missing_session',
      sessionBinding: {
        clear: (options) => cleared.push(options) && { cleared: true }
      },
      onEvent: () => {}
    });
    await assert.rejects(
      () => handle.sendUserMessage('do not send'),
      (error) => error.code === 'OPENCODE_SESSION_MISSING'
    );
    assert.equal(fake.promptBodies.length, 0);
    assert.equal(cleared[0].noticeKind, 'opencode_session_expired');
  } finally {
    await fake.close();
  }
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
Cannot find module '../daemon/src/opencode-conversation-adapter'
```

- [ ] **Step 3: Implement adapter capabilities and constructor**

Create `daemon/src/opencode-conversation-adapter.js`:

```javascript
'use strict';

const { conversationEventTypes } = require('./conversation-protocol');
const { mapOpenCodeEvent } = require('./opencode-event-mapper');

const OPENCODE_CAPABILITIES = Object.freeze({
  longLivedProcess: true,
  waitingInput: false,
  waitingApproval: true,
  resume: true,
  partialOutput: true,
  toolEvents: true,
  approval: {
    mobileCallbacks: true,
    scopes: ['once', 'session'],
    supportsCancel: false,
    denyBehaviors: ['interrupt']
  },
  attachments: {
    image: 'unsupported',
    textDocument: 'text_extract',
    pdf: 'unsupported'
  }
});

class OpenCodeConversationAdapter {
  constructor({ lifecycle, terminalSessionStatuses = [], supportsEventReconciliation = false } = {}) {
    this.name = 'opencode';
    this.lifecycle = lifecycle;
    this.terminalSessionStatuses = terminalSessionStatuses;
    this.supportsEventReconciliation = supportsEventReconciliation === true;
    this.capabilities = OPENCODE_CAPABILITIES;
  }

  getCapabilities() {
    return this.capabilities;
  }

  async detectCapabilities() {
    if (!this.lifecycle || typeof this.lifecycle.getClient !== 'function') {
      return { adapter: this.name, available: false, status: 'unavailable', capabilities: this.capabilities };
    }
    try {
      const client = await this.lifecycle.getClient();
      const health = await client.health();
      return { adapter: this.name, available: true, status: 'available', version: health.version || null, capabilities: this.capabilities };
    } catch (error) {
      return { adapter: this.name, available: false, status: 'unavailable', error: error.message, capabilities: this.capabilities };
    }
  }

  async startConversation(options = {}) {
    if ((options.permissionMode || 'default') === 'auto') {
      const error = new Error('OpenCode permissionMode auto is not supported');
      error.status = 422;
      error.code = 'OPENCODE_PERMISSION_MODE_UNSUPPORTED';
      throw error;
    }
    if (!options.workspacePath || !String(options.workspacePath).trim()) throw new Error('workspacePath is required');
    const client = await this.lifecycle.getClient();
    return new OpenCodeConversationHandle({
      adapter: this,
      client,
      conversationId: options.conversationId || null,
      workspacePath: options.workspacePath,
      sessionId: options.sessionId || null,
      sessionBinding: options.sessionBinding || {},
      onEvent: typeof options.onEvent === 'function' ? options.onEvent : () => {}
    });
  }
}
```

- [ ] **Step 4: Implement handle session checks and event filtering**

The handle must:

```javascript
class OpenCodeConversationHandle {
  constructor({ adapter, client, conversationId, workspacePath, sessionId, sessionBinding, onEvent }) {
    this.adapter = adapter;
    this.client = client;
    this.conversationId = conversationId;
    this.workspacePath = workspacePath;
    this.sessionId = sessionId;
    this.sessionBinding = sessionBinding;
    this.onEvent = onEvent;
    this.active = false;
    this.disposed = false;
    this.pendingApprovals = new Map();
    this.subscription = client.subscribeEvents(
      (raw) => this.handleServerEvent(raw),
      (error) => this.handleStreamError(error)
    );
  }

  async sendUserMessage(text) {
    if (this.active) {
      const error = new Error('OpenCode turn is already running');
      error.status = 409;
      throw error;
    }
    await this.ensureSessionBeforePrompt();
    this.active = true;
    await this.client.promptAsync({ sessionId: this.sessionId, text });
  }

  async ensureSessionBeforePrompt() {
    if (!this.sessionId) {
      const session = await this.client.createSession({ directory: this.workspacePath });
      this.bindSession(session);
      return;
    }
    let session;
    try {
      session = await this.client.readSession({ sessionId: this.sessionId });
    } catch (error) {
      if (this.sessionBinding && typeof this.sessionBinding.clear === 'function') {
        this.sessionBinding.clear({
          expectedSessionId: this.sessionId,
          reason: 'opencode_session_missing',
          code: 'OPENCODE_SESSION_MISSING',
          noticeKind: 'opencode_session_expired',
          visible: true
        });
      }
      const missing = new Error('OpenCode session is missing or expired');
      missing.status = 409;
      missing.code = 'OPENCODE_SESSION_MISSING';
      throw missing;
    }
    this.assertSessionDirectory(session);
  }

  bindSession(session) {
    const id = session.id || session.sessionID || session.sessionId || session.session_id;
    if (!id) throw new Error('OpenCode session create did not return an id');
    this.sessionId = id;
    this.assertSessionDirectory(session);
    this.onEvent({
      type: conversationEventTypes.SYSTEM_NOTICE,
      noticeKind: 'opencode_session_started',
      visible: false,
      sessionId: id,
      providerSession: {
        provider: 'opencode',
        threadId: id,
        cwd: this.workspacePath,
        protocolVersion: 1,
        createdAt: new Date().toISOString()
      }
    });
  }

  assertSessionDirectory(session) {
    const directory = String(session.directory || session.cwd || '');
    if (directory && directory !== this.workspacePath) {
      if (this.sessionBinding && typeof this.sessionBinding.markDrifted === 'function') {
        this.sessionBinding.markDrifted({
          expectedSessionId: this.sessionId,
          receivedSessionId: this.sessionId,
          reason: 'opencode_session_directory_mismatch',
          code: 'OPENCODE_SESSION_DIRECTORY_MISMATCH',
          clear: true
        });
      }
      const error = new Error('OpenCode session directory does not match workspace');
      error.status = 409;
      error.code = 'OPENCODE_SESSION_DIRECTORY_MISMATCH';
      throw error;
    }
  }
}
```

Event handling must call `mapOpenCodeEvent(raw, { workspacePath, terminalSessionStatuses })`, drop mapped warnings with `dispatchable === false` from conversation dispatch after recording the warning, and only emit events whose `sessionId` matches `this.sessionId`.

- [ ] **Step 5: Implement approval, cancellation, and stream failure**

Approval reply mapping:

```javascript
async respondApproval(approvalId, decision) {
  await this.client.replyPermission({
    sessionId: this.sessionId,
    permissionId: approvalId,
    decision: decision.decision,
    scope: decision.scope || 'once'
  });
}
```

Cancellation:

```javascript
async cancel() {
  if (!this.sessionId) return;
  try {
    await this.client.abortSession({ sessionId: this.sessionId });
  } catch (error) {
    this.onEvent({
      type: conversationEventTypes.PROTOCOL_WARNING,
      warning: 'opencode_abort_failed',
      message: error.message
    });
  }
}
```

No-reconciliation stream failure:

```javascript
handleStreamError(error) {
  if (!this.active) return;
  this.onEvent({
    type: conversationEventTypes.RUN_ERROR,
    code: 'OPENCODE_EVENT_STREAM_INTERRUPTED',
    message: error.message || 'OpenCode event stream interrupted'
  });
}
```

The reconnect path is enabled only when `supportsEventReconciliation === true` and `readSession()` proves the same active or waiting permission state. If that proof is absent, emit `OPENCODE_EVENT_STREAM_INTERRUPTED`.

- [ ] **Step 6: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected:

```text
All tests passed
No lint errors
```

Commit:

```bash
git add daemon/src/opencode-conversation-adapter.js scripts/run-tests.js
git commit -m "Add OpenCode conversation adapter"
```

---

### Task 8: Register OpenCode Adapter And Integration Tests

**Files:**
- Modify: `daemon/src/main.js`
- Modify: `daemon/src/opencode-adapter.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing registration and conversation tests**

Add tests:

```javascript
test('createConversationAdapters registers real OpenCode conversation adapter', () => {
  const { createConversationAdapters } = require('../daemon/src/main');
  const adapters = createConversationAdapters({
    claudeCommand: 'claude',
    codexCommand: 'codex',
    opencodeLifecycle: { getClient: async () => ({}) }
  });
  assert.equal(typeof adapters.get('opencode').startConversation, 'function');
  assert.notEqual(String(adapters.get('opencode').startConversation), String(/not implemented/));
});

test('OpenCode conversation runs through ConversationManager with fake server', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const { OpenCodeConversationAdapter } = require('../daemon/src/opencode-conversation-adapter');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const manager = createTestConversationManager({
      adapters: new Map([
        ['opencode', new OpenCodeConversationAdapter({ lifecycle: { getClient: async () => client } })]
      ])
    });
    const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
    const created = manager.createConversation({ workspaceId: 'default', adapter: 'opencode' }, device);
    await manager.sendMessage(created.id, { text: 'hello' }, device);
    await waitForCondition(() => fake.promptBodies.length === 1);
    fake.emitEvent({ type: 'session.idle', sessionID: 'sess_1' });
    await waitForCondition(() => manager.getConversation(created.id, device).status === 'idle');
    const summary = manager.getConversation(created.id, device);
    assert.equal(summary.cliSessionId, 'sess_1');
    assert.equal(summary.providerSession.provider, 'opencode');
  } finally {
    await fake.close();
  }
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
node scripts\run-tests.js
```

Expected:

```text
OpenCode conversation adapter is not implemented yet
```

- [ ] **Step 3: Wire dependencies in `main.js`**

Change `createApp()` defaults:

```javascript
opencodeCommand = process.env.OPENCODE_COMMAND || 'opencode',
opencodeServerUrl = process.env.OPENCODE_SERVER_URL || null,
opencodeLifecycle = undefined,
```

Create lifecycle once:

```javascript
const effectiveOpenCodeLifecycle = opencodeLifecycle || new OpenCodeServerLifecycle({
  externalUrl: opencodeServerUrl,
  command: opencodeCommand
});
```

Register listing adapter with lifecycle-aware diagnostics:

```javascript
const adapters = [
  new ClaudeAdapter({ command: claudeCommand }),
  createCodexAdapter({ command: codexCommand, explicitEnabled: codexEnabled }),
  new OpenCodeAdapter({ lifecycle: effectiveOpenCodeLifecycle, serverUrl: opencodeServerUrl })
];
```

Pass lifecycle into conversation adapter creation:

```javascript
conversationAdapters || createConversationAdapters({
  claudeCommand,
  codexCommand,
  codexToolTimeoutSec,
  opencodeLifecycle: effectiveOpenCodeLifecycle,
  ...
})
```

Change `createConversationAdapters()` signature and registration:

```javascript
function createConversationAdapters({
  claudeCommand,
  codexCommand,
  codexToolTimeoutSec,
  opencodeLifecycle = null,
  ...
}) {
  const adapters = new Map([
    ['claude', new ClaudeConversationAdapter({ command: claudeCommand })],
    ['codex', new CodexConversationAdapter({ command: codexCommand, toolTimeoutSec: codexToolTimeoutSec })],
    ['opencode', new OpenCodeConversationAdapter({ lifecycle: opencodeLifecycle })]
  ]);
  ...
}
```

Export `createConversationAdapters` if it is not already exported:

```javascript
module.exports = {
  createApp,
  createConversationAdapters,
  ...
};
```

- [ ] **Step 4: Align `opencode-adapter.js` diagnostics**

`OpenCodeAdapter.detectCapabilities()` must return:

```javascript
{
  adapter: 'opencode',
  available: true,
  status: 'available',
  serverMode: 'external' | 'managed',
  capabilities: OPENCODE_CAPABILITIES
}
```

When external URL health fails:

```javascript
{
  available: false,
  status: 'needs_configuration',
  error: 'OpenCode server unreachable at ...',
  actionable: 'Start opencode serve or update OPENCODE_SERVER_URL.'
}
```

When managed command probe fails:

```javascript
{
  available: false,
  status: 'unavailable',
  error: 'OpenCode CLI unavailable. Install opencode or set OPENCODE_COMMAND.'
}
```

- [ ] **Step 5: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected:

```text
All tests passed
No lint errors
```

Commit:

```bash
git add daemon/src/main.js daemon/src/opencode-adapter.js scripts/run-tests.js
git commit -m "Register OpenCode conversation adapter"
```

---

### Task 9: Failure Mode And Reliability Tests

**Files:**
- Modify: `daemon/src/opencode-conversation-adapter.js`
- Modify: `daemon/src/opencode-server-client.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Add failure-mode tests**

Add tests:

```javascript
test('OpenCode critical events without session id do not broadcast to active conversation', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const { OpenCodeConversationAdapter } = require('../daemon/src/opencode-conversation-adapter');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const events = [];
    const adapter = new OpenCodeConversationAdapter({ lifecycle: { getClient: async () => client } });
    const handle = await adapter.startConversation({ workspacePath: process.cwd(), onEvent: (event) => events.push(event) });
    await handle.sendUserMessage('hello');
    fake.emitEvent({ type: 'permission.asked', id: 'perm_without_session' });
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(events.some((event) => event.type === conversationEventTypes.APPROVAL_REQUESTED), false);
    assert.equal(events.some((event) => event.warning === 'opencode_critical_event_missing_session_id'), true);
  } finally {
    await fake.close();
  }
});

test('OpenCode event stream interruption clears active turn with run error', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const { OpenCodeConversationAdapter } = require('../daemon/src/opencode-conversation-adapter');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const events = [];
    const adapter = new OpenCodeConversationAdapter({ lifecycle: { getClient: async () => client } });
    const handle = await adapter.startConversation({ workspacePath: process.cwd(), onEvent: (event) => events.push(event) });
    await handle.sendUserMessage('hello');
    await fake.close();
    await waitForCondition(() => events.some((event) => event.code === 'OPENCODE_EVENT_STREAM_INTERRUPTED'));
  } catch (error) {
    await fake.close().catch(() => {});
    throw error;
  }
});

test('OpenCode permission request resolves through existing approval path', async () => {
  const { FakeOpenCodeServer } = require('../daemon/test/fakes/fake-opencode-server');
  const { OpenCodeServerClient } = require('../daemon/src/opencode-server-client');
  const { OpenCodeConversationAdapter } = require('../daemon/src/opencode-conversation-adapter');
  const fake = new FakeOpenCodeServer();
  await fake.listen();
  try {
    const client = new OpenCodeServerClient({ baseUrl: fake.url, requestTimeoutMs: 1000 });
    const manager = createTestConversationManager({
      adapters: new Map([
        ['opencode', new OpenCodeConversationAdapter({ lifecycle: { getClient: async () => client } })]
      ])
    });
    const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
    const created = manager.createConversation({ workspaceId: 'default', adapter: 'opencode' }, device);
    await manager.sendMessage(created.id, { text: 'needs permission' }, device);
    fake.emitEvent({ type: 'permission.asked', sessionID: 'sess_1', id: 'perm_1', command: 'npm test' });
    await waitForCondition(() => manager.getConversation(created.id, device).status === 'waiting_approval');
    await manager.respondApproval(created.id, 'perm_1', { decision: 'allow', scope: 'session' }, device);
    assert.deepEqual(fake.permissionReplies[0].body, { response: 'always' });
  } finally {
    await fake.close();
  }
});
```

- [ ] **Step 2: Run tests and verify failures**

Run:

```powershell
node scripts\run-tests.js
```

Expected failure names:

```text
OpenCode critical events without session id do not broadcast to active conversation
OpenCode event stream interruption clears active turn with run error
OpenCode permission request resolves through existing approval path
```

- [ ] **Step 3: Fix the adapter/client until these tests pass**

Required behaviors:

- The adapter emits `PROTOCOL_WARNING` for missing session id but does not emit `APPROVAL_REQUESTED`.
- The adapter emits `RUN_ERROR` with `code: 'OPENCODE_EVENT_STREAM_INTERRUPTED'` when the active event stream closes before `session.idle`.
- `respondApproval()` maps daemon `allow + session` to OpenCode `{ response: 'always' }`, `allow + once` to `{ response: 'once' }`, and deny/cancel to `{ response: 'reject' }`.
- A `cancel` approval decision remains a defensive daemon path; approval capability still advertises `supportsCancel: false`.

- [ ] **Step 4: Run tests and commit**

Run:

```powershell
node scripts\run-tests.js
npm run lint
```

Expected:

```text
All tests passed
No lint errors
```

Commit:

```bash
git add daemon/src/opencode-conversation-adapter.js daemon/src/opencode-server-client.js scripts/run-tests.js
git commit -m "Harden OpenCode conversation failure handling"
```

---

### Task 10: Mobile Localization For Visible OpenCode States

**Files:**
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Modify: `mobile/lib/src/ui/features/workbench/messages/notice_event_card.dart`
- Modify: `mobile/lib/src/ui/features/workbench/widgets/workbench_run_error_card.dart`
- Modify: `mobile/test/conversation_reducer_test.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write failing localization/widget tests**

Add a reducer or widget test that exercises a visible notice:

```dart
testWidgets('OpenCode expired session notice is localized', (tester) async {
  final message = WorkbenchMessage.systemNotice(
    body: 'opencode_session_expired',
    event: const ConversationEvent(
      type: 'system.notice',
      seq: 1,
      conversationId: 'conv_1',
      createdAt: DateTime(2026, 6, 7),
      raw: <String, Object?>{
        'noticeKind': 'opencode_session_expired',
        'visible': true,
      },
    ),
  );

  await tester.pumpWidget(buildLocalizedWorkbenchMessage(message, locale: const Locale('en')));
  expect(find.text('OpenCode session expired'), findsOneWidget);
  expect(find.textContaining('The provider session was no longer available'), findsOneWidget);
});
```

If the existing test builders use different constructors, adapt the object construction to the nearest existing `WorkbenchMessage` fixture. The assertion must check localized rendered copy, not raw provider strings.

- [ ] **Step 2: Run the targeted test and verify failure**

Run from `mobile/`:

```powershell
flutter test --no-pub test\widget_test.dart --plain-name "OpenCode expired session notice is localized"
```

Expected:

```text
Expected: exactly one matching candidate
Actual: _TextWidgetFinder:<Found 0 widgets with text "OpenCode session expired">
```

- [ ] **Step 3: Add ARB strings**

Add to `mobile/lib/l10n/app_en.arb`:

```json
"workbenchNoticeOpenCodeSessionExpiredTitle": "OpenCode session expired",
"workbenchNoticeOpenCodeSessionExpiredMeta": "Session reset",
"workbenchNoticeOpenCodeSessionExpiredBody": "The provider session was no longer available. Your message was not sent, so start a new turn after the daemon creates a fresh OpenCode session.",
"workbenchRunErrorOpenCodeUnavailable": "OpenCode server unavailable",
"workbenchRunErrorUnsupportedPermissionMode": "OpenCode does not support automatic permission mode yet"
```

Add to `mobile/lib/l10n/app_zh.arb`:

```json
"workbenchNoticeOpenCodeSessionExpiredTitle": "OpenCode 会话已过期",
"workbenchNoticeOpenCodeSessionExpiredMeta": "会话已重置",
"workbenchNoticeOpenCodeSessionExpiredBody": "Provider 侧会话已不可用。本次消息没有发送；请重新发送，让 daemon 创建新的 OpenCode 会话。",
"workbenchRunErrorOpenCodeUnavailable": "OpenCode server 暂不可用",
"workbenchRunErrorUnsupportedPermissionMode": "OpenCode 暂不支持自动权限模式"
```

Regenerate localizations through the project’s existing Flutter generation flow. If generated localization files are committed in this repository, include the generated `app_localizations*.dart` changes in the same commit.

- [ ] **Step 4: Render OpenCode notice kind through l10n**

In `notice_event_card.dart`, extend `_noticeCopy()`:

```dart
if (noticeKind == 'opencode_session_expired') {
  return _NoticeCopy(
    title: l10n.workbenchNoticeOpenCodeSessionExpiredTitle,
    meta: l10n.workbenchNoticeOpenCodeSessionExpiredMeta,
    body: l10n.workbenchNoticeOpenCodeSessionExpiredBody,
  );
}
```

Keep unknown OpenCode notice kinds on the generic system notice path.

- [ ] **Step 5: Localize visible run error labels**

If `WorkbenchRunErrorCard` receives raw error codes in `error`, map only these stable daemon error codes:

```dart
String _localizedRunError(BuildContext context, String error) {
  final l10n = AppLocalizations.of(context);
  if (error.contains('OPENCODE_SERVER_PORT_UNAVAILABLE') ||
      error.contains('OPENCODE_EVENT_STREAM_INTERRUPTED')) {
    return l10n.workbenchRunErrorOpenCodeUnavailable;
  }
  if (error.contains('OPENCODE_PERMISSION_MODE_UNSUPPORTED')) {
    return l10n.workbenchRunErrorUnsupportedPermissionMode;
  }
  return error;
}
```

Use `AppLocalizations` in `WorkbenchRunErrorCard` and replace the hardcoded label:

```dart
Text('${l10n.workbenchRunErrorPrefix}: ${_localizedRunError(context, error)}', ...)
```

If `workbenchRunErrorPrefix` does not exist, add it to both ARB files:

```json
"workbenchRunErrorPrefix": "Run error"
```

```json
"workbenchRunErrorPrefix": "运行错误"
```

- [ ] **Step 6: Run mobile checks and commit**

Run from `mobile/`:

```powershell
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
flutter test --no-pub test\widget_test.dart test\conversation_reducer_test.dart
```

Expected:

```text
Architecture import check passed
No issues found
All tests passed
```

Commit:

```bash
git add mobile/lib/l10n mobile/lib/src/ui/features/workbench/messages/notice_event_card.dart mobile/lib/src/ui/features/workbench/widgets/workbench_run_error_card.dart mobile/test/conversation_reducer_test.dart mobile/test/widget_test.dart
git commit -m "Localize visible OpenCode Workbench states"
```

---

### Task 11: End-To-End Verification And Knowledge Closeout

**Files:**
- Modify: `docs/project-knowledge/build-and-test.md` or `docs/project-knowledge/open-risks.md` only if the implementation creates durable operational knowledge.

- [ ] **Step 1: Run full daemon verification**

Run from repository root:

```powershell
node scripts\run-tests.js
npm run lint
node scripts\check-project-knowledge.js
git diff --check
```

Expected:

```text
All tests passed
No lint errors
Project knowledge check passed
```

- [ ] **Step 2: Run mobile verification if Task 10 changed mobile code**

Run from `mobile/`:

```powershell
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
flutter test --no-pub
```

Expected:

```text
Architecture import check passed
No issues found
All tests passed
```

- [ ] **Step 3: Run optional real OpenCode smoke**

Run only when a local OpenCode binary is installed and the user accepts any model-consuming prompt check:

```powershell
node scripts\smoke-opencode-server.js --workspace D:\AiProject\vibe-coding
```

For prompt dispatch evidence:

```powershell
node scripts\smoke-opencode-server.js --workspace D:\AiProject\vibe-coding --allow-prompt-dispatch
```

Expected for non-model-consuming smoke:

```text
health: pass
doc: pass
sessionCreateDirectory: pass
abort: pass
globalEventSse: pass
```

If session read/reconciliation is not verified, confirm the manifest keeps:

```json
"sessionReadReconcile": "blocked"
```

and the adapter keeps active-turn SSE disconnect fail-fast behavior.

- [ ] **Step 4: Update project knowledge only for durable findings**

Update project knowledge if implementation produces durable operational facts, such as:

- exact OpenCode version support boundaries;
- a reproducible Windows process-tree cleanup issue;
- a verified session read/reconcile route;
- a verified terminal `session.status` enum.

Do not promote ordinary command logs or raw smoke payloads to project knowledge. Keep raw evidence in `docs/superpowers/fixtures/opencode-server/`.

- [ ] **Step 5: Final commit**

Commit knowledge updates or final verification gate changes:

```bash
git add docs/project-knowledge docs/superpowers/fixtures/opencode-server scripts/run-tests.js
git commit -m "Document OpenCode integration verification evidence"
```

Skip this commit when there are no knowledge or fixture changes after verification.

---

## Acceptance Checklist

- [ ] `opencode` conversation creation no longer returns the not-implemented adapter.
- [ ] First OpenCode message creates a session with `directory=<authorized workspace path>`.
- [ ] `cliSessionId` stores the OpenCode session id after `opencode_session_started`.
- [ ] `providerSession` is cleared when OpenCode session binding is cleared.
- [ ] Later-message missing session fails before prompt dispatch with `OPENCODE_SESSION_MISSING`.
- [ ] Session directory mismatch fails closed with `OPENCODE_SESSION_DIRECTORY_MISMATCH`.
- [ ] Shared SSE events are filtered by normalized session id.
- [ ] Critical events without session id are not broadcast to conversations.
- [ ] Permission requests become existing mobile approval blocking items.
- [ ] Approval `allow + session` maps to OpenCode `always`; mobile never exposes `always` as a scope.
- [ ] Conversation cancel calls OpenCode abort route.
- [ ] Active-turn SSE disconnect cannot leave a blocking item hanging indefinitely.
- [ ] Managed server startup tries at most 3 ports and reports `OPENCODE_SERVER_PORT_UNAVAILABLE`.
- [ ] No mobile raw OpenCode API is introduced.
- [ ] New visible strings are present in English and Chinese ARB files.

## Self-Review

Spec coverage:

- Official support review and server-first choice: Tasks 1, 2, 4, 5, 8.
- Daemon-owned architecture and Workbench API preservation: Tasks 6, 7, 8, 9.
- Event stream reliability: Tasks 3, 4, 7, 9, 11.
- Session reset and providerSession semantics: Tasks 6, 7, 9.
- Permission handling: Tasks 3, 4, 7, 9.
- Managed lifecycle and Windows cleanup: Task 5.
- Mobile impact and internationalization: Task 10.
- Verification and smoke evidence: Tasks 1, 2, 11.

Type consistency:

- Adapter name is `opencode`.
- OpenCode session id is passed as `sessionId` in daemon events and persisted as `cliSessionId`.
- `sessionBinding.clear()` and `sessionBinding.markDrifted()` are callback names passed to adapters; `ConversationManager` owns the stored fields.
- User-visible missing session code is `OPENCODE_SESSION_MISSING`; visible notice kind is `opencode_session_expired`.
- Managed port exhaustion code is `OPENCODE_SERVER_PORT_UNAVAILABLE`.
- Active event stream interruption code is `OPENCODE_EVENT_STREAM_INTERRUPTED`.

No separate mobile OpenCode feature, raw provider route, SDK dependency, silent replacement session, or broad provider fallback is included.
