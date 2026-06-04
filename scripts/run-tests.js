'use strict';

process.env.AUTH_TOKEN_SECRET = process.env.AUTH_TOKEN_SECRET || 'test-only-auth-token-secret';
process.env.DEVICE_ID_PEPPER = process.env.DEVICE_ID_PEPPER || 'test-only-device-id-pepper';

const assert = require('node:assert/strict');
const nodeCrypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const WebSocket = require('ws');
const { AuthManager, hashDeviceId, verifyToken } = require('../daemon/src/auth');
const { validateRunCreate, assertNoV1TerminalRequest, eventTypes } = require('../daemon/src/protocol');
const { EventStore } = require('../daemon/src/event-store');
const { WorkspaceRegistry } = require('../daemon/src/workspace');
const { AuditLog, redact } = require('../daemon/src/audit');
const { ClaudeAdapter, mapClaudeEvent, buildClaudeArgs, resolvePermissionMode, detectClaudeCodeInstallation } = require('../daemon/src/claude-adapter');
const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
const { CodexAppServerListingAdapter } = require('../daemon/src/codex-app-server-listing-adapter');
const { CodexConversationAdapter, mapCodexEvent } = require('../daemon/src/codex-conversation-adapter');
const { ConversationManager } = require('../daemon/src/conversation-manager');
const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
const { NotificationHub } = require('../daemon/src/notification-hub');
const { createCodexAdapter } = require('../daemon/src/jsonline-adapter');
const { resolveCliInvocation } = require('../daemon/src/cli-resolver');
const { AdapterRegistry } = require('../daemon/src/adapter-registry');
const { createApp } = require('../daemon/src/main');
const { AsrModelAsset } = require('../daemon/src/asr-model-asset');
const { MODEL_CATALOG_MAX_BYTES, MODEL_SOURCES, discoverConfiguredModels, parseTomlScalarConfig } = require('../daemon/src/model-discovery');
const { conversationEventTypes } = require('../daemon/src/conversation-protocol');
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

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

function createKnowledgeFixture(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'project-knowledge-check-'));
  for (const [relativePath, content] of Object.entries(files)) {
    const filePath = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content, 'utf8');
  }
  return root;
}

function tempConversationDbPath(prefix = 'conversation-app-') {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), prefix)), 'conversations.sqlite');
}

function createAndroidUpdateFixture({ root = null, versionCode = 2, apkBytes = Buffer.from('fake-apk-v2') } = {}) {
  root = root || fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-fixture-'));
  const apkName = `lan_ai_cli_control-1.4.0+${versionCode}.apk`;
  const apkPath = path.join(root, apkName);
  fs.writeFileSync(apkPath, apkBytes);
  const sha256 = nodeCrypto.createHash('sha256').update(apkBytes).digest('hex');
  const manifest = {
    schemaVersion: 1,
    platform: 'android',
    packageName: 'com.example.lan_ai_cli_control',
    versionName: '1.4.0',
    versionCode,
    minSupportedVersionCode: 1,
    mandatory: false,
    apkUrl: `/api/app-updates/android/apk/${versionCode}`,
    sha256,
    sizeBytes: apkBytes.length,
    etag: `"android-apk-${versionCode}-${sha256.slice(0, 12)}"`,
    releaseNotes: 'test update',
    publishedAt: '2026-05-24T10:00:00.000Z',
    fileName: apkName
  };
  fs.writeFileSync(path.join(root, 'latest.json'), JSON.stringify(manifest, null, 2), 'utf8');
  fs.writeFileSync(path.join(root, `${apkName}.sha256`), `${sha256}  ${apkName}\n`, 'utf8');
  return { root, apkBytes, manifest };
}

test('project knowledge check validates links and active entry metadata', () => {
  const fs = require('node:fs');
  const { checkProjectKnowledge } = require('./check-project-knowledge');
  const root = createKnowledgeFixture({
    'docs/project-knowledge/index.md': [
      '# Project Knowledge Index',
      '',
      '- Last verified: 2026-05-22',
      '',
      '## Routing',
      '',
      'Read [architecture.md](architecture.md).',
      '',
      '## Active Slices',
      '',
      '- [architecture.md](architecture.md)'
    ].join('\n'),
    'docs/project-knowledge/architecture.md': [
      '# Architecture',
      '',
      '- Last verified: 2026-05-22',
      '',
      'Related file: [example.js](../../daemon/src/example.js)'
    ].join('\n'),
    'daemon/src/example.js': "'use strict';\n"
  });

  try {
    const result = checkProjectKnowledge({ rootDir: root });
    assert.deepEqual(result.errors, []);
    assert.deepEqual(result.notices, []);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('project knowledge check fails missing relative links and archive routes', () => {
  const fs = require('node:fs');
  const { checkProjectKnowledge } = require('./check-project-knowledge');
  const root = createKnowledgeFixture({
    'docs/project-knowledge/index.md': [
      '# Project Knowledge Index',
      '',
      '- Last verified: 2026-05-22',
      '',
      '## Routing',
      '',
      'Bug route: [old note](archive/old.md).',
      '',
      '## Active Slices',
      '',
      '- [architecture.md](architecture.md)'
    ].join('\n'),
    'docs/project-knowledge/architecture.md': [
      '# Architecture',
      '',
      '- Last verified: 2026-05-22',
      '',
      'Related file: [missing.js](../../daemon/src/missing.js)'
    ].join('\n')
  });

  try {
    const result = checkProjectKnowledge({ rootDir: root });
    assert.equal(result.errors.some((error) => error.includes('Missing link target')), true);
    assert.equal(result.errors.some((error) => error.includes('Routing section links to archive')), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('project knowledge check reports missing Last verified as notice', () => {
  const fs = require('node:fs');
  const { checkProjectKnowledge } = require('./check-project-knowledge');
  const root = createKnowledgeFixture({
    'docs/project-knowledge/index.md': [
      '# Project Knowledge Index',
      '',
      '## Routing',
      '',
      'Read [architecture.md](architecture.md).'
    ].join('\n'),
    'docs/project-knowledge/architecture.md': [
      '# Architecture',
      '',
      'No verification marker yet.'
    ].join('\n')
  });

  try {
    const result = checkProjectKnowledge({ rootDir: root });
    assert.deepEqual(result.errors, []);
    assert.equal(result.notices.some((notice) => notice.includes('Missing Last verified')), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('project knowledge check passes current repository seed', () => {
  const { checkProjectKnowledge } = require('./check-project-knowledge');
  const result = checkProjectKnowledge({ rootDir: process.cwd() });
  assert.deepEqual(result.errors, []);
});

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
  assert.ok(Array.isArray(manifest.samples));
  assert.ok(manifest.samples.length > 0);
});

test('Codex app-server availability marks disabled adapter unselectable', () => {
  const { buildCodexAppServerAvailability } = require('../daemon/src/codex-app-server-availability');
  const status = buildCodexAppServerAvailability({ enabled: false });
  assert.equal(status.installed, false);
  assert.equal(status.protocolCompatible, false);
  assert.equal(status.transportHealthy, false);
  assert.equal(status.selectable, false);
  assert.equal(status.unavailableReason, 'disabled');
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
  assert.equal(status.installed, true);
  assert.equal(status.protocolCompatible, true);
  assert.equal(status.transportHealthy, true);
  assert.equal(status.selectable, true);
  assert.equal(status.unavailableReason, null);
  assert.equal(status.effectiveCapabilities.mobileApprovalCallbacks, true);
  assert.deepEqual(status.effectiveCapabilities.approval.scopes, ['once', 'session']);
});

test('Codex app-server availability sanitizes unavailable reasons', () => {
  const { buildCodexAppServerAvailability } = require('../daemon/src/codex-app-server-availability');
  const status = buildCodexAppServerAvailability({
    enabled: true,
    installed: true,
    protocolCompatible: false,
    transportHealthy: false,
    unavailableReason: 'Failed with sk-test-secret at C:\\Users\\Alice\\repo'
  });
  assert.equal(status.selectable, false);
  assert.equal(status.unavailableReason.includes('sk-test-secret'), false);
  assert.equal(status.unavailableReason.includes('Alice'), false);
});

test('Codex app-server JSONL transport resolves responses and emits notifications', async () => {
  const { PassThrough } = require('node:stream');
  const { CodexAppServerJsonlTransport } = require('../daemon/src/codex-app-server-transport');
  const stdin = new PassThrough();
  const stdout = new PassThrough();
  const written = [];
  stdin.on('data', (chunk) => written.push(chunk.toString('utf8')));
  const transport = new CodexAppServerJsonlTransport({ stdin, stdout, requestTimeoutMs: 1000 });
  const notifications = [];
  transport.on('notification', (message) => notifications.push(message));
  const pending = transport.sendRequest('model/list', { limit: 1 });
  const request = JSON.parse(written.join('').trim());
  assert.equal(request.method, 'model/list');
  assert.equal(request.params.limit, 1);
  stdout.write(`${JSON.stringify({ method: 'thread/status/changed', params: { status: 'running' } })}\n`);
  stdout.write(`${JSON.stringify({ id: request.id, result: { data: [] } })}\n`);
  assert.deepEqual(await pending, { data: [] });
  assert.equal(notifications[0].method, 'thread/status/changed');
  transport.close();
  stdin.destroy();
  stdout.destroy();
});

test('Codex app-server JSONL transport rejects pending requests on close', async () => {
  const { PassThrough } = require('node:stream');
  const { CodexAppServerJsonlTransport } = require('../daemon/src/codex-app-server-transport');
  const stdin = new PassThrough();
  const stdout = new PassThrough();
  const transport = new CodexAppServerJsonlTransport({ stdin, stdout, requestTimeoutMs: 1000 });
  const pending = transport.sendRequest('thread/start', {});
  stdout.emit('close');
  await assert.rejects(pending, /transport closed/);
  stdin.destroy();
  stdout.destroy();
});

test('Codex app-server JSONL transport emits server requests and writes results', async () => {
  const { PassThrough } = require('node:stream');
  const { CodexAppServerJsonlTransport } = require('../daemon/src/codex-app-server-transport');
  const stdin = new PassThrough();
  const stdout = new PassThrough();
  const written = [];
  stdin.on('data', (chunk) => written.push(chunk.toString('utf8')));
  const transport = new CodexAppServerJsonlTransport({ stdin, stdout, requestTimeoutMs: 1000 });
  const serverRequests = [];
  transport.on('serverRequest', (message) => {
    serverRequests.push(message);
    transport.sendResult(message.id, { decision: 'decline' });
  });
  stdout.write(`${JSON.stringify({ id: 'approval-1', method: 'item/commandExecution/requestApproval', params: { itemId: 'item_1' } })}\n`);
  assert.equal(serverRequests.length, 1);
  const response = JSON.parse(written.join('').trim());
  assert.deepEqual(response, { id: 'approval-1', result: { decision: 'decline' } });
  transport.close();
  stdin.destroy();
  stdout.destroy();
});

test('Codex app-server method extractor reads schema request surfaces', () => {
  const {
    defaultCodexAppServerSchemaDir,
    loadCodexAppServerMethods
  } = require('../daemon/src/codex-app-server/methods');
  const methods = loadCodexAppServerMethods(defaultCodexAppServerSchemaDir());
  assert.equal(methods.requests.has('initialize'), true);
  assert.equal(methods.requests.has('thread/start'), true);
  assert.equal(methods.requests.has('thread/resume'), true);
  assert.equal(methods.requests.has('turn/start'), true);
  assert.equal(methods.requests.has('turn/interrupt'), true);
  assert.equal(methods.requests.has('model/list'), true);
  assert.equal(methods.clientNotifications.has('initialized'), true);
  assert.equal(methods.serverRequests.has('item/commandExecution/requestApproval'), true);
  assert.equal(methods.serverRequests.has('item/fileChange/requestApproval'), true);
  assert.equal(methods.serverNotifications.has('thread/started'), true);
  assert.equal(methods.serverNotifications.has('turn/completed'), true);
});

test('Codex app-server capability matrix covers generated methods', () => {
  const {
    CODEX_APP_SERVER_CAPABILITY_MATRIX,
    codexAppServerMethodSurfaceSignature,
    validateCodexAppServerCapabilityMatrix
  } = require('../daemon/src/codex-app-server/capability-matrix');
  const result = validateCodexAppServerCapabilityMatrix(CODEX_APP_SERVER_CAPABILITY_MATRIX);
  assert.deepEqual(result.errors, []);
  assert.equal(codexAppServerMethodSurfaceSignature(), 'd73ae1187282b17fa5620a414460f1e7fc7916be5b22dc2b6d693fe68aa8dbb1');
  const rowByMethod = new Map(CODEX_APP_SERVER_CAPABILITY_MATRIX.map((row) => [row.method, row]));
  assert.equal(rowByMethod.get('initialize').localStatus, 'supported');
  assert.equal(rowByMethod.get('initialized').localStatus, 'supported');
  assert.equal(rowByMethod.get('model/list').localStatus, 'supported');
  assert.equal(rowByMethod.get('thread/start').localStatus, 'supported');
  assert.equal(rowByMethod.get('turn/interrupt').risk, 'write');
  assert.equal(rowByMethod.get('item/commandExecution/requestApproval').direction, 'serverRequest');
});

test('Codex app-server capability matrix rejects unreviewed official method surfaces', () => {
  const {
    CODEX_APP_SERVER_CAPABILITY_MATRIX,
    validateCodexAppServerCapabilityMatrix
  } = require('../daemon/src/codex-app-server/capability-matrix');
  const methods = {
    clientRequests: new Set(['initialize', 'example/newOfficialMethod']),
    clientNotifications: new Set(['initialized']),
    serverRequests: new Set(),
    serverNotifications: new Set()
  };
  const result = validateCodexAppServerCapabilityMatrix(CODEX_APP_SERVER_CAPABILITY_MATRIX, methods);
  assert.equal(result.errors.some((error) => error.includes('official method surface changed')), true);
  assert.equal(result.errors.some((error) => error.includes('example/newOfficialMethod') && error.includes('missing client request row')), true);
});

test('Codex app-server capability matrix rejects active unknown risk rows', () => {
  const {
    CODEX_APP_SERVER_CAPABILITY_MATRIX,
    validateCodexAppServerCapabilityMatrix
  } = require('../daemon/src/codex-app-server/capability-matrix');
  const invalid = CODEX_APP_SERVER_CAPABILITY_MATRIX.map((row) => ({ ...row }));
  invalid.push({
    method: 'example/activeUnknownRisk',
    direction: 'request',
    stability: 'stable',
    category: 'diagnostics',
    localStatus: 'planned',
    daemonOwner: 'server route',
    mobileStatus: 'not planned',
    risk: 'unknown',
    testRequirement: 'unit',
    rationale: 'invalid fixture row'
  });
  const result = validateCodexAppServerCapabilityMatrix(invalid);
  assert.equal(result.errors.some((error) => error.includes('example/activeUnknownRisk') && error.includes('unknown risk')), true);
});

test('Codex app-server client initializes once for concurrent callers', async () => {
  const { CodexAppServerClient } = require('../daemon/src/codex-app-server/client');
  const calls = [];
  const transport = {
    sendRequest(method, params) {
      calls.push({ method, params });
      return Promise.resolve(method === 'model/list' ? { data: [] } : {});
    },
    sendNotification(method, params) {
      calls.push({ notification: method, params });
    }
  };
  const client = new CodexAppServerClient({ transport });
  await Promise.all([client.initialize(), client.initialize()]);
  assert.deepEqual(calls.map((call) => call.method || `notification:${call.notification}`), [
    'initialize',
    'notification:initialized'
  ]);
});

test('Codex app-server client invalidates after failed initialize', async () => {
  const { CodexAppServerClient } = require('../daemon/src/codex-app-server/client');
  let attempts = 0;
  const transport = {
    sendRequest(method) {
      attempts += 1;
      throw new Error(`${method} failed`);
    },
    sendNotification() {}
  };
  const client = new CodexAppServerClient({ transport });
  await assert.rejects(() => Promise.all([client.initialize(), client.initialize()]), /initialize failed/);
  assert.equal(attempts, 1);
  await assert.rejects(() => client.initialize(), /invalidated/);
});

test('Codex app-server client invalidates when transport closes', async () => {
  const { CodexAppServerClient } = require('../daemon/src/codex-app-server/client');
  const transport = new EventEmitter();
  transport.sendRequest = () => Promise.resolve({});
  transport.sendNotification = () => {};
  const client = new CodexAppServerClient({ transport });
  await client.initialize();

  transport.emit('closed', new Error('process exited'));

  await assert.rejects(() => client.initialize(), /process exited/);
  await assert.rejects(() => client.listModels(), /process exited/);
});

test('Codex app-server client sends typed conversation requests', async () => {
  const { CodexAppServerClient } = require('../daemon/src/codex-app-server/client');
  const calls = [];
  const transport = {
    sendRequest(method, params) {
      calls.push({ method, params });
      if (method === 'thread/start') return Promise.resolve({ thread: { id: 'thread_client' } });
      if (method === 'turn/start') return Promise.resolve({ turn: { id: 'turn_client' } });
      if (method === 'turn/interrupt') return Promise.resolve({});
      return Promise.resolve({});
    },
    sendNotification() {}
  };
  const client = new CodexAppServerClient({ transport });
  assert.equal((await client.startThread({ workspacePath: process.cwd(), permissionMode: 'default' })).thread.id, 'thread_client');
  assert.equal((await client.startTurn({ threadId: 'thread_client', workspacePath: process.cwd(), message: 'hello' })).turn.id, 'turn_client');
  await client.interruptTurn({ threadId: 'thread_client', turnId: 'turn_client' });
  assert.deepEqual(calls.map((call) => call.method), ['thread/start', 'turn/start', 'turn/interrupt']);
});

test('Codex app-server client sends typed thread history requests', async () => {
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

  await client.listThreads({ workspacePath: process.cwd(), limit: 20, cursor: null, archived: false });
  await client.listLoadedThreads();
  await client.readThread({ threadId: 'thread_client' });
  await client.searchThreads({ query: 'needle', workspacePath: process.cwd(), limit: undefined, cursor: 'next' });
  await client.listThreadTurns({ threadId: 'thread_client', limit: 10 });
  await client.listThreadTurnItems({ threadId: 'thread_client', turnId: 'turn_client', cursor: undefined });
  await client.getThreadGoal({ threadId: 'thread_client' });

  assert.deepEqual(calls, [
    { method: 'thread/list', params: { workspacePath: process.cwd(), limit: 20, archived: false } },
    { method: 'thread/loaded/list', params: {} },
    { method: 'thread/read', params: { threadId: 'thread_client' } },
    { method: 'thread/search', params: { query: 'needle', workspacePath: process.cwd(), cursor: 'next' } },
    { method: 'thread/turns/list', params: { threadId: 'thread_client', limit: 10 } },
    { method: 'thread/turns/items/list', params: { threadId: 'thread_client', turnId: 'turn_client' } },
    { method: 'thread/goal/get', params: { threadId: 'thread_client' } }
  ]);
});

test('Codex app-server client sends typed discovery requests', async () => {
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

  await client.readConfig();
  await client.readConfigRequirements();
  await client.listMcpServerStatus({ cursor: 'mcp_next', ignored: 'nope' });
  await client.readMcpServerResource({ serverId: 'server_1', uri: 'file://one', cursor: 'ignored' });
  await client.listSkills({ cursor: 'skill_next' });
  await client.listPlugins({ cursor: 'plugin_next' });
  await client.readPlugin({ pluginId: 'plugin_1', cursor: 'ignored' });
  await client.readPluginSkill({ pluginId: 'plugin_1', skillId: 'skill_1' });
  await client.listPluginShares({ cursor: 'share_next' });
  await client.listApps({ cursor: 'app_next' });
  await client.listHooks();
  await client.listCollaborationModes();
  await client.listExperimentalFeatures();
  await client.detectExternalAgentConfig();
  await client.listPermissionProfiles();
  await client.readModelProviderCapabilities();
  await client.readWindowsSandboxReadiness();

  assert.deepEqual(calls, [
    { method: 'config/read', params: {} },
    { method: 'configRequirements/read', params: {} },
    { method: 'mcpServerStatus/list', params: { cursor: 'mcp_next' } },
    { method: 'mcpServer/resource/read', params: { serverId: 'server_1', uri: 'file://one' } },
    { method: 'skills/list', params: { cursor: 'skill_next' } },
    { method: 'plugin/list', params: { cursor: 'plugin_next' } },
    { method: 'plugin/read', params: { pluginId: 'plugin_1' } },
    { method: 'plugin/skill/read', params: { pluginId: 'plugin_1', skillId: 'skill_1' } },
    { method: 'plugin/share/list', params: { cursor: 'share_next' } },
    { method: 'app/list', params: { cursor: 'app_next' } },
    { method: 'hooks/list', params: {} },
    { method: 'collaborationMode/list', params: {} },
    { method: 'experimentalFeature/list', params: {} },
    { method: 'externalAgentConfig/detect', params: {} },
    { method: 'permissionProfile/list', params: {} },
    { method: 'modelProvider/capabilities/read', params: {} },
    { method: 'windowsSandbox/readiness', params: {} }
  ]);
});

test('Codex app-server service reuses healthy read-only discovery client within TTL', async () => {
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
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('Codex app-server route context receives production audit log', () => {
  const app = createApp({
    port: 0,
    codexAppServerProbe: false,
    codexAppServerModelLister: false,
    codexAppServerService: {},
    appDbPath: tempConversationDbPath('app-server-audit-context-')
  });
  try {
    assert.equal(app.server.context.auditLog, app.auditLog);
    assert.ok(app.server.context.auditLog);
  } finally {
    app.appSqliteStore.close();
  }
});

test('Codex app-server capabilities route returns matrix and route metadata', async () => {
  const { summarizeCodexAppServerCapabilityMatrix } = require('../daemon/src/codex-app-server/capability-matrix');
  const { buildCodexAppServerRouteCapabilities } = require('../daemon/src/codex-app-server/capability-routes');
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
    const response = await request(port, 'GET', '/api/codex-app-server/capabilities', null, paired.token);
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.capabilityMatrix, summarizeCodexAppServerCapabilityMatrix());
    assert.deepEqual(response.body.routes, buildCodexAppServerRouteCapabilities());
    assert.equal(response.body.routes.some((route) => route.group === 'history' && route.readOnly), true);
    assert.equal(response.body.routes.some((route) => route.requiresApproval), true);
    assert.equal(response.body.routes.every((route) => route.source === 'capability-matrix'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('Codex app-server unknown routes return controlled not found errors', async () => {
  const app = createApp({
    port: 0,
    codexAppServerProbe: false,
    codexAppServerModelLister: false,
    appDbPath: tempConversationDbPath('app-server-route-not-found-')
  });
  const pair = app.auth.createPairingCode();
  const paired = app.auth.pair(pair.code, 'test', 'device_unknown_route');
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const response = await request(port, 'GET', '/api/codex-app-server/unknown', null, paired.token);
    assert.equal(response.status, 404);
    assert.equal(response.body.error.code, 'CODEX_APP_SERVER_ROUTE_NOT_FOUND');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('Codex app-server workspace threads route authorizes workspace and normalizes list response', async () => {
  const calls = [];
  const service = {
    async withWorkspaceClient(workspace, callback) {
      calls.push({ workspace });
      return callback({
        async listThreads(options) {
          calls.push({ method: 'listThreads', options });
          return {
            data: [
              { id: 'thread_1', title: 'Thread One', workspacePath: options.workspacePath, archived: false, extra: 'kept' }
            ],
            nextCursor: 'cursor_2',
            ignoredByNormalizer: false
          };
        }
      });
    }
  };
  const app = await createCodexAppServerRouteTestApp({ service });

  try {
    const response = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads?limit=20&cursor=abc&archived=false`);

    assert.equal(response.status, 200);
    assert.deepEqual(response.body.threads, [
      { id: 'thread_1', title: 'Thread One', workspacePath: app.workspace.path, archived: false, extra: 'kept' }
    ]);
    assert.equal(response.body.nextCursor, 'cursor_2');
    assert.deepEqual(calls[0].workspace, app.workspace);
    assert.deepEqual(calls[1], {
      method: 'listThreads',
      options: { workspacePath: app.workspace.path, limit: 20, cursor: 'abc', archived: false }
    });
  } finally {
    await app.close();
  }
});

test('Codex app-server workspace threads route rejects invalid limit', async () => {
  const app = await createCodexAppServerRouteTestApp({
    service: {
      async withWorkspaceClient() {
        throw new Error('must not call service for invalid query');
      }
    }
  });

  try {
    const response = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads?limit=bad`);

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'BAD_REQUEST');
  } finally {
    await app.close();
  }
});

test('Codex app-server workspace threads route rejects invalid archived flag', async () => {
  const app = await createCodexAppServerRouteTestApp({
    service: {
      async withWorkspaceClient() {
        throw new Error('must not call service for invalid query');
      }
    }
  });

  try {
    const response = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads?archived=yes`);

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'BAD_REQUEST');
  } finally {
    await app.close();
  }
});

test('Codex app-server thread history routes require workspace scope and normalize responses', async () => {
  const calls = [];
  const service = {
    async withDiscoveryClient(callback) {
      return callback({
        async listLoadedThreads() {
          calls.push({ method: 'listLoadedThreads' });
          return { threads: [{ id: 'loaded_1', title: 'Loaded' }], nextCursor: 'loaded_next' };
        }
      });
    },
    async withWorkspaceClient(workspace, callback) {
      calls.push({ method: 'withWorkspaceClient', workspace });
      return callback({
        async readThread(options) {
          calls.push({ method: 'readThread', options });
          return { thread: { id: options.threadId, title: 'Read', metadata: { source: 'test' } } };
        },
        async listThreadTurns(options) {
          calls.push({ method: 'listThreadTurns', options });
          return { turns: [{ id: 'turn_1', status: 'completed' }], nextCursor: 'turn_next' };
        },
        async listThreadTurnItems(options) {
          calls.push({ method: 'listThreadTurnItems', options });
          return { items: [{ id: 'item_1', kind: 'agentMessage' }], nextCursor: 'item_next' };
        },
        async getThreadGoal(options) {
          calls.push({ method: 'getThreadGoal', options });
          return { goal: { threadId: options.threadId, status: 'active', objective: 'ship' } };
        },
        async searchThreads(options) {
          calls.push({ method: 'searchThreads', workspace, options });
          return { threads: [{ id: 'search_1', title: 'Found', workspacePath: options.workspacePath }], nextCursor: 'search_next' };
        }
      });
    }
  };
  const app = await createCodexAppServerRouteTestApp({ service });

  try {
    const loaded = await app.get('/api/codex-app-server/threads/loaded');
    const read = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads/thread_1`);
    const search = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads/search?query=needle&limit=5&cursor=next`);
    const turns = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads/thread_1/turns?limit=3&cursor=turn_cursor`);
    const items = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads/thread_1/turns/turn_1/items?limit=2`);
    const goal = await app.get(`/api/codex-app-server/workspaces/${app.workspace.id}/threads/thread_1/goal`);

    assert.equal(loaded.status, 200);
    assert.deepEqual(loaded.body.threads, [{ id: 'loaded_1', title: 'Loaded' }]);
    assert.equal(read.status, 200);
    assert.deepEqual(read.body.thread, { id: 'thread_1', title: 'Read', metadata: { source: 'test' } });
    assert.equal(search.status, 200);
    assert.deepEqual(search.body.threads, [{ id: 'search_1', title: 'Found', workspacePath: app.workspace.path }]);
    assert.equal(turns.status, 200);
    assert.deepEqual(turns.body.turns, [{ id: 'turn_1', status: 'completed' }]);
    assert.equal(items.status, 200);
    assert.deepEqual(items.body.items, [{ id: 'item_1', kind: 'agentMessage' }]);
    assert.equal(goal.status, 200);
    assert.deepEqual(goal.body.goal, { threadId: 'thread_1', status: 'active', objective: 'ship' });
    assert.deepEqual(calls, [
      { method: 'listLoadedThreads' },
      { method: 'withWorkspaceClient', workspace: app.workspace },
      { method: 'readThread', options: { threadId: 'thread_1' } },
      { method: 'withWorkspaceClient', workspace: app.workspace },
      { method: 'searchThreads', workspace: app.workspace, options: { query: 'needle', workspacePath: app.workspace.path, limit: 5, cursor: 'next' } },
      { method: 'withWorkspaceClient', workspace: app.workspace },
      { method: 'listThreadTurns', options: { threadId: 'thread_1', limit: 3, cursor: 'turn_cursor' } },
      { method: 'withWorkspaceClient', workspace: app.workspace },
      { method: 'listThreadTurnItems', options: { threadId: 'thread_1', turnId: 'turn_1', limit: 2 } },
      { method: 'withWorkspaceClient', workspace: app.workspace },
      { method: 'getThreadGoal', options: { threadId: 'thread_1' } }
    ]);
  } finally {
    await app.close();
  }
});

test('Codex app-server unscoped thread history routes no longer expose thread reads', async () => {
  const service = {
    async withDiscoveryClient(callback) {
      return callback({
        async listLoadedThreads() {
          return { threads: [] };
        },
        async readThread() {
          throw new Error('must not read unscoped thread');
        },
        async listThreadTurns() {
          throw new Error('must not list unscoped turns');
        },
        async listThreadTurnItems() {
          throw new Error('must not list unscoped items');
        },
        async getThreadGoal() {
          throw new Error('must not get unscoped goal');
        }
      });
    }
  };
  const app = await createCodexAppServerRouteTestApp({ service });

  try {
    const read = await app.get('/api/codex-app-server/threads/thread_1');
    const turns = await app.get('/api/codex-app-server/threads/thread_1/turns');
    const items = await app.get('/api/codex-app-server/threads/thread_1/turns/turn_1/items');
    const goal = await app.get('/api/codex-app-server/threads/thread_1/goal');

    for (const response of [read, turns, items, goal]) {
      assert.equal(response.status, 404);
      assert.equal(response.body.error.code, 'CODEX_APP_SERVER_ROUTE_NOT_FOUND');
    }
  } finally {
    await app.close();
  }
});

test('Codex app-server workspace thread read rejects unauthorized workspace before service access', async () => {
  let serviceCalls = 0;
  const app = await createCodexAppServerRouteTestApp({
    service: {
      async withWorkspaceClient() {
        serviceCalls += 1;
        throw new Error('must not call service for unauthorized workspace');
      }
    }
  });

  try {
    const response = await app.get('/api/codex-app-server/workspaces/workspace_not_allowed/threads/thread_1');

    assert.equal(response.status, 404);
    assert.equal(response.body.error.code, 'WORKSPACE_NOT_FOUND');
    assert.equal(serviceCalls, 0);
  } finally {
    await app.close();
  }
});

test('Codex app-server routes return controlled bad request for malformed path encoding', async () => {
  let serviceCalls = 0;
  const app = await createCodexAppServerRouteTestApp({
    service: {
      async withWorkspaceClient() {
        serviceCalls += 1;
        throw new Error('must not call service for malformed path');
      }
    }
  });

  try {
    const response = await app.get('/api/codex-app-server/workspaces/%E0%A4%A/threads/thread_1');

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'BAD_REQUEST');
    assert.equal(serviceCalls, 0);
  } finally {
    await app.close();
  }
});

test('Codex app-server discovery routes use discovery client and normalize responses', async () => {
  const calls = [];
  const routeCases = [
    { path: '/api/codex-app-server/config', clientMethod: 'readConfig', payload: { config: { model: 'gpt-5' }, extra: 'kept' } },
    { path: '/api/codex-app-server/config/requirements', clientMethod: 'readConfigRequirements', payload: { requirements: [{ id: 'apiKey' }], nextCursor: 'ignored' } },
    { path: '/api/codex-app-server/mcp/servers?cursor=next', clientMethod: 'listMcpServerStatus', options: { cursor: 'next' }, payload: { data: [{ id: 'server_1', status: 'running' }], nextCursor: 'mcp_more', source: 'fixture' }, expectedBody: { servers: [{ id: 'server_1', status: 'running' }], nextCursor: 'mcp_more', source: 'fixture' } },
    { path: '/api/codex-app-server/mcp/resources?serverId=server_1&uri=file%3A%2F%2Fone', clientMethod: 'readMcpServerResource', options: { serverId: 'server_1', uri: 'file://one' }, payload: { resource: { uri: 'file://one', text: 'hello' }, serverId: 'server_1' } },
    { path: '/api/codex-app-server/skills?cursor=skill_next', clientMethod: 'listSkills', options: { cursor: 'skill_next' }, payload: { data: [{ id: 'skill_1', title: 'Skill' }], nextCursor: 'skill_more' }, expectedBody: { skills: [{ id: 'skill_1', title: 'Skill' }], nextCursor: 'skill_more' } },
    { path: '/api/codex-app-server/plugins?cursor=plugin_next', clientMethod: 'listPlugins', options: { cursor: 'plugin_next' }, payload: { items: [{ id: 'plugin_1', name: 'Plugin' }], nextCursor: 'plugin_more' }, expectedBody: { plugins: [{ id: 'plugin_1', name: 'Plugin' }], nextCursor: 'plugin_more' } },
    { path: '/api/codex-app-server/plugins/plugin%2Fone', clientMethod: 'readPlugin', options: { pluginId: 'plugin/one' }, payload: { plugin: { id: 'plugin/one', enabled: true }, extra: 'kept' } },
    { path: '/api/codex-app-server/plugins/plugin%2Fone/skills/skill%2Fone', clientMethod: 'readPluginSkill', options: { pluginId: 'plugin/one', skillId: 'skill/one' }, payload: { skill: { id: 'skill/one', pluginId: 'plugin/one' } } },
    { path: '/api/codex-app-server/plugin-shares?cursor=share_next', clientMethod: 'listPluginShares', options: { cursor: 'share_next' }, payload: { shares: [{ id: 'share_1' }], nextCursor: 'share_more' } },
    { path: '/api/codex-app-server/apps?cursor=app_next', clientMethod: 'listApps', options: { cursor: 'app_next' }, payload: { apps: [{ id: 'app_1' }], nextCursor: 'app_more' } },
    { path: '/api/codex-app-server/hooks', clientMethod: 'listHooks', payload: { hooks: [{ id: 'hook_1' }] } },
    { path: '/api/codex-app-server/collaboration-modes', clientMethod: 'listCollaborationModes', payload: { modes: [{ id: 'solo' }] } },
    { path: '/api/codex-app-server/experimental-features', clientMethod: 'listExperimentalFeatures', payload: { features: [{ id: 'exp_1' }] } },
    { path: '/api/codex-app-server/external-agent-config', clientMethod: 'detectExternalAgentConfig', payload: { config: { detected: true } } },
    { path: '/api/codex-app-server/permission-profiles', clientMethod: 'listPermissionProfiles', payload: { profiles: [{ id: 'default' }] } },
    { path: '/api/codex-app-server/model-provider-capabilities', clientMethod: 'readModelProviderCapabilities', payload: { providers: [{ id: 'openai' }] } },
    { path: '/api/codex-app-server/windows-sandbox/readiness', clientMethod: 'readWindowsSandboxReadiness', payload: { readiness: { ready: false }, warning: 'needs setup' } }
  ];
  let currentCase = null;
  const client = {};
  for (const routeCase of routeCases) {
    client[routeCase.clientMethod] = async (options) => {
      calls.push({ method: routeCase.clientMethod, options });
      return routeCase.payload;
    };
  }
  const service = {
    async withDiscoveryClient(callback) {
      calls.push({ method: 'withDiscoveryClient', path: currentCase.path });
      return callback(client);
    },
    async withMutationClient() {
      throw new Error('discovery route must not use mutation pool');
    }
  };
  const app = await createCodexAppServerRouteTestApp({ service });

  try {
    for (const routeCase of routeCases) {
      currentCase = routeCase;
      const response = await app.get(routeCase.path);
      assert.equal(response.status, 200, routeCase.path);
      assert.deepEqual(response.body, routeCase.expectedBody || routeCase.payload, routeCase.path);
    }

    assert.deepEqual(
      calls.filter((call) => call.method !== 'withDiscoveryClient'),
      routeCases.map((routeCase) => ({
        method: routeCase.clientMethod,
        options: routeCase.options
      }))
    );
    assert.equal(calls.filter((call) => call.method === 'withDiscoveryClient').length, routeCases.length);
  } finally {
    await app.close();
  }
});

test('Codex app-server mcp resource route rejects missing query params before service access', async () => {
  let serviceCalls = 0;
  const app = await createCodexAppServerRouteTestApp({
    service: {
      async withDiscoveryClient() {
        serviceCalls += 1;
        throw new Error('must not call service for invalid mcp resource query');
      }
    }
  });

  try {
    for (const path of [
      '/api/codex-app-server/mcp/resources',
      '/api/codex-app-server/mcp/resources?serverId=server_1',
      '/api/codex-app-server/mcp/resources?uri=file%3A%2F%2Fone',
      '/api/codex-app-server/mcp/resources?serverId=%20&uri=file%3A%2F%2Fone',
      '/api/codex-app-server/mcp/resources?serverId=server_1&uri=%20'
    ]) {
      const response = await app.get(path);
      assert.equal(response.status, 400, path);
      assert.equal(response.body.error.code, 'BAD_REQUEST', path);
    }
    assert.equal(serviceCalls, 0);
  } finally {
    await app.close();
  }
});

test('Codex app-server plugin discovery routes reject malformed path encoding before service access', async () => {
  let serviceCalls = 0;
  const app = await createCodexAppServerRouteTestApp({
    service: {
      async withDiscoveryClient() {
        serviceCalls += 1;
        throw new Error('must not call service for malformed plugin path');
      }
    }
  });

  try {
    const plugin = await app.get('/api/codex-app-server/plugins/%E0%A4%A');
    const skill = await app.get('/api/codex-app-server/plugins/plugin_1/skills/%E0%A4%A');

    assert.equal(plugin.status, 400);
    assert.equal(plugin.body.error.code, 'BAD_REQUEST');
    assert.equal(skill.status, 400);
    assert.equal(skill.body.error.code, 'BAD_REQUEST');
    assert.equal(serviceCalls, 0);
  } finally {
    await app.close();
  }
});

test('Codex app-server dispatcher ignores non app-server paths', async () => {
  const { tryHandleCodexAppServerRoute } = require('../daemon/src/codex-app-server/routes');
  let writes = 0;
  const handled = await tryHandleCodexAppServerRoute({
    method: 'GET',
    url: new URL('http://localhost/api/adapters'),
    json: () => {
      writes += 1;
      throw new Error('should not write a response');
    },
    readJson: async () => ({}),
    context: {}
  });
  assert.equal(handled, false);
  assert.equal(writes, 0);
});

test('Codex app-server dispatcher ignores same-prefix non namespace paths', async () => {
  const { tryHandleCodexAppServerRoute } = require('../daemon/src/codex-app-server/routes');
  let writes = 0;
  const handled = await tryHandleCodexAppServerRoute({
    method: 'GET',
    url: new URL('http://localhost/api/codex-app-server-v2'),
    json: () => {
      writes += 1;
      throw new Error('should not write a response');
    },
    readJson: async () => ({}),
    context: {}
  });
  assert.equal(handled, false);
  assert.equal(writes, 0);
});

test('Codex app-server capability route metadata is derived from matrix rows', () => {
  const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('../daemon/src/codex-app-server/capability-matrix');
  const { buildCodexAppServerRouteCapabilities } = require('../daemon/src/codex-app-server/capability-routes');
  const selectedRows = CODEX_APP_SERVER_CAPABILITY_MATRIX.filter((row) => row.daemonOwner === 'server route' || row.mobileStatus === 'planned' || row.mobileStatus === 'consumed');
  const routes = buildCodexAppServerRouteCapabilities();
  assert.equal(routes.length, selectedRows.length);
  for (const route of routes) {
    const row = selectedRows.find((candidate) => candidate.method === route.method);
    assert.ok(row, `${route.method} must be backed by a matrix row`);
    assert.equal(route.localStatus, row.localStatus);
    assert.equal(route.mobileStatus, row.mobileStatus);
    assert.equal(route.risk, row.risk);
    assert.equal(route.source, 'capability-matrix');
  }
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

test('Codex app-server conversation pool reserves capacity before callback completes', async () => {
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  let releaseFirst;
  let firstEntered;
  const firstEnteredPromise = new Promise((resolve) => { firstEntered = resolve; });
  const service = new CodexAppServerService({
    poolLimits: { conversation: 1 },
    lifecycle: {
      spawn() {
        const transport = new EventEmitter();
        transport.sendRequest = async () => ({});
        transport.sendNotification = () => {};
        return { transport, shutdown: async () => {} };
      }
    }
  });

  const first = service.withConversationClient({ threadId: 'thread_1' }, async () => {
    firstEntered();
    await new Promise((resolve) => { releaseFirst = resolve; });
  });
  await firstEnteredPromise;

  await assert.rejects(
    () => service.withConversationClient({ threadId: 'thread_2' }, async () => {}),
    (error) => error.code === 'CODEX_APP_SERVER_BUSY'
  );

  releaseFirst();
  await first;
});

test('Codex app-server mutation pool reserves workspace capacity before callback completes', async () => {
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  let releaseFirst;
  let firstEntered;
  const firstEnteredPromise = new Promise((resolve) => { firstEntered = resolve; });
  const service = new CodexAppServerService({
    poolLimits: { mutation: 1 },
    lifecycle: {
      spawn() {
        const transport = new EventEmitter();
        transport.sendRequest = async () => ({});
        transport.sendNotification = () => {};
        return { transport, shutdown: async () => {} };
      }
    }
  });

  const first = service.withMutationClient({ method: 'fs/writeFile', workspaceId: 'workspace_1' }, async () => {
    firstEntered();
    await new Promise((resolve) => { releaseFirst = resolve; });
  });
  await firstEnteredPromise;

  await assert.rejects(
    () => service.withMutationClient({ method: 'fs/remove', workspaceId: 'workspace_1' }, async () => {}),
    (error) => error.code === 'CODEX_APP_SERVER_BUSY'
  );

  releaseFirst();
  await first;
});

test('Codex app-server discovery pool counts in-flight distinct invocation keys', async () => {
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  let releaseInitialize;
  const service = new CodexAppServerService({
    poolLimits: { discovery: 1 },
    lifecycle: {
      spawn() {
        const transport = new EventEmitter();
        transport.sendRequest = async (method) => {
          if (method === 'initialize') {
            await new Promise((resolve) => { releaseInitialize = resolve; });
            return {};
          }
          return { data: [] };
        };
        transport.sendNotification = () => {};
        return { transport, shutdown: async () => {} };
      }
    }
  });

  const first = service.withDiscoveryClient({ invocationKey: 'workspace_1' }, (client) => client.listModels());
  await assert.rejects(
    () => service.withDiscoveryClient({ invocationKey: 'workspace_2' }, (client) => client.listModels()),
    (error) => error.code === 'CODEX_APP_SERVER_BUSY'
  );

  releaseInitialize();
  await first;
});

test('Codex app-server workspace client uses discovery pool with workspace scope', async () => {
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  const spawned = [];
  const service = new CodexAppServerService({
    lifecycle: {
      spawn(scope) {
        const transport = new EventEmitter();
        transport.sendRequest = async (method) => method === 'initialize' ? {} : { data: [] };
        transport.sendNotification = () => {};
        const handle = { scope, transport, shutdown: async () => {} };
        spawned.push(handle);
        return handle;
      }
    }
  });

  await service.withWorkspaceClient({ id: 'workspace_1', workspacePath: process.cwd() }, (client) => client.listModels());

  assert.equal(spawned.length, 1);
  assert.equal(spawned[0].scope.pool, 'discovery');
  assert.equal(spawned[0].scope.workspaceId, 'workspace_1');
  assert.equal(spawned[0].scope.workspacePath, process.cwd());
});

test('Codex app-server service shuts down spawned handle when initialization fails', async () => {
  const { CodexAppServerService } = require('../daemon/src/codex-app-server/service');
  const spawned = [];
  const service = new CodexAppServerService({
    lifecycle: {
      spawn() {
        const transport = new EventEmitter();
        transport.sendRequest = async (method) => {
          if (method === 'initialize') throw new Error('initialize failed');
          return {};
        };
        transport.sendNotification = () => {};
        const handle = {
          transport,
          shutdownCalled: false,
          shutdown: async () => { handle.shutdownCalled = true; }
        };
        spawned.push(handle);
        return handle;
      }
    }
  });

  await assert.rejects(
    () => service.withDiscoveryClient((client) => client.listModels()),
    /initialize failed/
  );

  assert.equal(spawned.length, 1);
  assert.equal(spawned[0].shutdownCalled, true);
});

test('Codex app-server model service normalizes model/list responses', () => {
  const { normalizeCodexAppServerModelCapability } = require('../daemon/src/codex-app-server/models');
  const capability = normalizeCodexAppServerModelCapability({
    data: [
      { id: 'gpt-5-codex', displayName: 'GPT-5 Codex', isDefault: true, inputModalities: ['text', 'image'] },
      { id: 'hidden-model', hidden: true },
      { id: 'gpt-5-codex' }
    ]
  });
  assert.deepEqual(capability, {
    models: [
      {
        id: 'gpt-5-codex',
        label: 'GPT-5 Codex',
        source: 'app_server',
        selected: true,
        inputModalities: ['text', 'image']
      }
    ],
    selectedModel: 'gpt-5-codex',
    canSelectModel: true
  });
});

test('Codex app-server lifecycle enforces max process limit', async () => {
  const { CodexAppServerLifecycle } = require('../daemon/src/codex-app-server-lifecycle');
  const children = [];
  const lifecycle = new CodexAppServerLifecycle({
    maxProcesses: 1,
    spawnAppServer: () => {
      const child = createFakeAppServerChild({ pid: 1234 + children.length });
      children.push(child);
      return child;
    }
  });
  const first = lifecycle.spawn();
  assert.equal(first.pid, 1234);
  assert.throws(() => lifecycle.spawn(), /maximum Codex app-server process limit reached/);
  first.child.emit('exit', 0, null);
  const second = lifecycle.spawn();
  assert.equal(second.pid, 1235);
  await second.shutdown();
});

test('Codex app-server lifecycle escalates shutdown after grace timeout', async () => {
  const { CodexAppServerLifecycle } = require('../daemon/src/codex-app-server-lifecycle');
  const signals = [];
  const child = createFakeAppServerChild({
    pid: 4321,
    kill(signal) {
      signals.push(signal || 'SIGTERM');
      if (signal === 'SIGKILL') setImmediate(() => child.emit('exit', null, 'SIGKILL'));
      return true;
    }
  });
  const lifecycle = new CodexAppServerLifecycle({
    maxProcesses: 1,
    gracefulShutdownMs: 5,
    spawnAppServer: () => child
  });
  const handle = lifecycle.spawn();
  await handle.shutdown();
  assert.deepEqual(signals, ['SIGTERM', 'SIGKILL']);
});

test('Codex app-server lifecycle can terminate a Windows process tree before direct child kill', async () => {
  const { CodexAppServerLifecycle } = require('../daemon/src/codex-app-server-lifecycle');
  const terminations = [];
  const signals = [];
  const child = createFakeAppServerChild({
    pid: 9876,
    kill(signal) {
      signals.push(signal || 'SIGTERM');
      return true;
    }
  });
  const lifecycle = new CodexAppServerLifecycle({
    maxProcesses: 1,
    gracefulShutdownMs: 5,
    spawnAppServer: () => child,
    processTreeTerminator(pid, options) {
      terminations.push({ pid, force: options.force, signal: options.signal });
      if (options.force) setImmediate(() => child.emit('exit', null, 'SIGKILL'));
      return true;
    }
  });
  const handle = lifecycle.spawn();
  await handle.shutdown();
  assert.deepEqual(terminations, [
    { pid: 9876, force: false, signal: 'SIGTERM' },
    { pid: 9876, force: true, signal: 'SIGKILL' }
  ]);
  assert.deepEqual(signals, []);
  assert.equal(lifecycle.metrics.orphanProcessCleanupCount, 1);
});

test('Codex app-server lifecycle rejects pending requests on child spawn error', async () => {
  const { CodexAppServerLifecycle } = require('../daemon/src/codex-app-server-lifecycle');
  const child = createFakeAppServerChild({ pid: null, kill: () => false });
  const lifecycle = new CodexAppServerLifecycle({
    maxProcesses: 1,
    spawnAppServer: () => child
  });
  const handle = lifecycle.spawn();
  const pending = handle.transport.sendRequest('initialize', {});
  child.emit('error', Object.assign(new Error('spawn codex ENOENT'), { code: 'ENOENT' }));
  await assert.rejects(pending, /spawn codex ENOENT/);
  assert.equal(handle.exited, true);
  assert.equal(lifecycle.handles.size, 0);
});

function createConversationManagerForTest({ adapters } = {}) {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-09T00:00:00.000Z') });
  const auditLog = new AuditLog();
  const defaultAdapters = new Map([['codex', {
    capabilities: { resume: true },
    async getModelCapability() {
      return {
        canSelectModel: true,
        selectedModel: 'gpt-5',
        models: [
          { id: 'gpt-5', label: 'GPT-5' },
          { id: 'gpt-5.5', label: 'GPT-5.5' }
        ]
      };
    },
    async startConversation() {
      throw new Error('not needed');
    }
  }]]);
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog,
    adapters: adapters || defaultAdapters,
    now: () => new Date('2026-05-09T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  return { manager, device, auditLog, eventStore };
}

test('pairing issues a token and stores only token hash', () => {
  const auth = new AuthManager({ now: () => 1000 });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone');
  const device = auth.authenticate(`Bearer ${paired.token}`);
  assert.equal(device.id, paired.deviceId);
  assert.equal(device.tokenHash.includes(paired.token), false);
  assert.equal(verifyToken(paired.token, device.tokenHash), true);
});

test('pairing stores hashed device identity without plaintext credentials', () => {
  const auth = new AuthManager({ now: () => 1000, deviceIdPepper: 'test-pepper' });
  const pairing = auth.createPairingCode();
  const paired = auth.pair(pairing.code, 'phone', 'device-123');
  const device = auth.authenticate(`Bearer ${paired.token}`);

  assert.equal(device.deviceIdHash, hashDeviceId('device-123', 'test-pepper'));
  assert.notEqual(device.deviceIdHash, 'device-123');
  assert.equal(device.deviceIdHash.includes('device-123'), false);
  assert.equal(device.tokenHash.includes(paired.token), false);
  assert.equal(device.refreshTokenHash.includes(paired.refreshToken), false);
});

test('expired pairing code fails', () => {
  let now = 1000;
  const auth = new AuthManager({ now: () => now });
  const pairing = auth.createPairingCode(10);
  now = 2000;
  assert.throws(() => auth.pair(pairing.code), /expired/);
});

test('V1 rejects arbitrary shell and PTY payloads', () => {
  assert.throws(() => assertNoV1TerminalRequest({ command: 'dir' }), /V1\.2 rejects/);
  assert.throws(() => assertNoV1TerminalRequest({ cwd: 'C:\\Users' }), /V1\.2 rejects/);
  assert.throws(() => assertNoV1TerminalRequest({ pty: true }), /V1\.2 rejects/);
  assert.doesNotThrow(() => validateRunCreate({ tool: 'claude', workspaceId: 'w1', prompt: 'hello' }));
});

test('conversation protocol validates statuses and blocking payloads', () => {
  const {
    conversationStatuses,
    conversationSessionBindings,
    conversationEventTypes,
    normalizeConversationCreate,
    normalizeConversationModelUpdate,
    normalizeMessagePayload,
    normalizeQuestionResponse,
    normalizeApprovalDecision,
    isConversationActiveStatus,
    isConversationReusableStatus,
    isConversationTerminalStatus
  } = require('../daemon/src/conversation-protocol');

  assert.equal(conversationStatuses.IDLE, 'idle');
  assert.equal(conversationStatuses.WAITING_INPUT, 'waiting_input');
  assert.equal(conversationStatuses.WAITING_APPROVAL, 'waiting_approval');
  assert.equal(conversationStatuses.INTERRUPTED, 'interrupted');
  assert.equal(conversationSessionBindings.UNKNOWN, 'unknown');
  assert.equal(conversationSessionBindings.CONFIRMED, 'confirmed');
  assert.equal(conversationSessionBindings.DRIFTED, 'drifted');
  assert.equal(isConversationActiveStatus('running'), true);
  assert.equal(isConversationActiveStatus('waiting_approval'), true);
  assert.equal(isConversationReusableStatus('cancelled'), true);
  assert.equal(isConversationReusableStatus('failed'), true);
  assert.equal(isConversationReusableStatus('interrupted'), true);
  assert.equal(isConversationTerminalStatus('expired'), true);
  assert.equal(isConversationTerminalStatus('cancelled'), false);
  assert.equal(conversationEventTypes.ASSISTANT_MESSAGE, 'assistant.message');
  assert.equal(conversationEventTypes.APPROVAL_REQUESTED, 'approval.requested');
  assert.equal(conversationEventTypes.MODEL_CHANGED, 'conversation.model_changed');

  const defaultConversationCreate = normalizeConversationCreate({
    workspaceId: 'default',
    adapter: 'claude',
    permissionMode: 'default'
  });
  assert.deepEqual(defaultConversationCreate, {
    workspaceId: 'default',
    adapter: 'claude',
    model: null,
    permissionMode: 'default',
    requestedTools: [],
    requestedToolPolicy: { tools: [], allowedTools: [], disallowedTools: [] },
    resumePolicy: { type: 'fresh' },
    systemPromptPolicy: { type: 'none' },
    claudeOptions: {}
  });
  const extendedConversationCreate = normalizeConversationCreate({
    workspaceId: 'default',
    adapter: 'claude',
    permissionMode: 'auto',
    requestedTools: ['Read', ' ', 'Glob', 42],
    requestedToolPolicy: {
      tools: ['Read', 'Glob', 'Grep'],
      allowedTools: ['Read'],
      disallowedTools: ['Bash']
    },
    resumePolicy: { type: 'resume', sessionId: 'claude-session-1', name: 'bugfix' },
    systemPromptPolicy: { type: 'append', text: 'Keep responses concise.' },
    claudeOptions: {
      tools: ['Task', 'Read'],
      allowedTools: ['Read'],
      disallowedTools: ['Bash'],
      systemPrompt: 'You are concise.',
      maxTurns: 4,
      maxBudgetUsd: 1.5,
      extraArgs: { debug: null, color: 'never' },
      env: { SHOULD_NOT_PASS: '1' }
    }
  });
  assert.deepEqual(extendedConversationCreate, {
    workspaceId: 'default',
    adapter: 'claude',
    model: null,
    permissionMode: 'auto',
    requestedTools: ['Read', 'Glob'],
    requestedToolPolicy: { tools: ['Read', 'Glob', 'Grep'], allowedTools: ['Read'], disallowedTools: ['Bash'] },
    resumePolicy: { type: 'resume', sessionId: 'claude-session-1', name: 'bugfix' },
    systemPromptPolicy: { type: 'append', text: 'Keep responses concise.' },
    claudeOptions: {
      tools: ['Task', 'Read'],
      allowedTools: ['Read'],
      disallowedTools: ['Bash'],
      systemPrompt: 'You are concise.',
      maxTurns: 4,
      maxBudgetUsd: 1.5,
      extraArgs: { debug: null, color: 'never' }
    }
  });
  assert.deepEqual(normalizeApprovalDecision({ decision: 'deny' }), { decision: 'deny', interrupt: true });
  assert.deepEqual(normalizeApprovalDecision({ decision: 'deny', interrupt: false }), { decision: 'deny', interrupt: false });
  assert.deepEqual(normalizeApprovalDecision('allow'), {
    decision: 'allow',
    scope: 'once'
  });
  assert.deepEqual(normalizeApprovalDecision({ decision: 'allow' }), {
    decision: 'allow',
    scope: 'once'
  });
  assert.deepEqual(normalizeApprovalDecision({
    decision: 'allow',
    scope: 'session',
    updatedPermissions: [{ tool: 'Bash', rule: 'allow' }]
  }), {
    decision: 'allow',
    scope: 'session',
    updatedPermissions: [{ tool: 'Bash', rule: 'allow' }]
  });
  assert.deepEqual(normalizeApprovalDecision({ decision: 'deny', scope: 'session' }), {
    decision: 'deny',
    interrupt: true
  });
  assert.deepEqual(normalizeApprovalDecision({ decision: 'cancel', scope: 'session' }), {
    decision: 'cancel'
  });
  assert.deepEqual(normalizeApprovalDecision({
    decision: 'allow',
    updatedInput: { command: 'npm test' },
    updatedPermissions: [{ tool: 'Bash', rule: 'allow' }]
  }), {
    decision: 'allow',
    scope: 'once',
    updatedInput: { command: 'npm test' },
    updatedPermissions: [{ tool: 'Bash', rule: 'allow' }]
  });
  assert.equal(normalizeConversationCreate({ workspaceId: 'default', model: ' gpt-5.5 ' }).model, 'gpt-5.5');
  assert.equal(normalizeConversationCreate({ workspaceId: 'default', model: '   ' }).model, null);
  assert.equal(normalizeConversationCreate({ workspaceId: 'default', model: 42 }).model, null);
  assert.deepEqual(normalizeConversationModelUpdate({ model: ' gpt-5.5 ' }), { model: 'gpt-5.5' });
  assert.deepEqual(normalizeConversationModelUpdate({ model: '   ' }), { model: null });
  assert.deepEqual(normalizeConversationModelUpdate({ model: null }), { model: null });
  assert.throws(() => normalizeConversationModelUpdate(null), /payload must be an object/);
  assert.throws(() => normalizeConversationModelUpdate({}), /model is required/);
  assert.throws(() => normalizeConversationModelUpdate({ model: 42 }), /model must be a string or null/);
  assert.equal(normalizeMessagePayload({ text: ' hello ' }).text, 'hello');
  assert.equal(normalizeQuestionResponse({ questionId: 'q1', text: ' answer ' }).text, 'answer');
  assert.equal(normalizeApprovalDecision({ decision: 'allow' }).decision, 'allow');
  assert.throws(() => normalizeApprovalDecision({ decision: 'allow', scope: 'forever' }), /scope must be once or session/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: '', adapter: 'claude' }), /workspaceId is required/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: 'default', adapter: 'unknown' }), /unsupported adapter/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: 'default', resumePolicy: { type: 'sideways' } }), /resumePolicy.type is invalid/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: 'default', systemPromptPolicy: { type: 'replace' } }), /systemPromptPolicy.type is invalid/);
  assert.throws(() => normalizeMessagePayload({ text: '' }), /text or attachments are required/);
  assert.equal(normalizeMessagePayload({ text: '', attachments: [{ name: 'a.txt' }] }).attachments.length, 1);
  assert.throws(() => normalizeQuestionResponse({ questionId: 'q1', text: '' }), /text is required/);
  assert.throws(() => normalizeApprovalDecision({ decision: 'maybe' }), /decision must be allow, deny, or cancel/);
});

test('conversation event store appends and replays ordered events', () => {
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const { conversationEventTypes } = require('../daemon/src/conversation-protocol');
  const store = new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') });

  const first = store.append('conv_1', conversationEventTypes.USER_MESSAGE, { text: 'hello' });
  const second = store.append('conv_1', conversationEventTypes.ASSISTANT_MESSAGE, { text: 'hi' });
  store.append('conv_2', conversationEventTypes.USER_MESSAGE, { text: 'other' });

  assert.equal(first.seq, 1);
  assert.equal(second.seq, 2);
  assert.equal(first.createdAt, '2026-05-03T00:00:00.000Z');
  assert.deepEqual(store.list('conv_1', 0).map((event) => event.seq), [1, 2]);
  assert.deepEqual(store.list('conv_1', 1).map((event) => event.seq), [2]);
  assert.equal(store.list('missing', 0).length, 0);
});

test('conversation event store tail returns the latest events in ascending order', () => {
  const store = new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') });

  for (let index = 1; index <= 6; index += 1) {
    store.append('conv_1', 'assistant.message', { text: `event ${index}` });
  }

  const page = store.listTail('conv_1', 3);

  assert.deepEqual(page.events.map((event) => event.seq), [4, 5, 6]);
  assert.equal(page.oldestSeq, 4);
  assert.equal(page.newestSeq, 6);
  assert.equal(page.hasMoreBefore, true);
});

test('conversation event store clamps page limits to supported bounds', () => {
  const store = new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') });

  for (let index = 1; index <= 3; index += 1) {
    store.append('conv_1', 'assistant.message', { text: `event ${index}` });
  }

  assert.deepEqual(store.listTail('conv_1', 0).events.map((event) => event.seq), [3]);
  assert.deepEqual(store.listBefore('conv_1', 3, -10).events.map((event) => event.seq), [2]);
  assert.deepEqual(store.listTail('conv_1', 'bad').events.map((event) => event.seq), [1, 2, 3]);
  assert.deepEqual(store.listTail('conv_1', undefined).events.map((event) => event.seq), [1, 2, 3]);
  assert.deepEqual(store.listTail('conv_1', null).events.map((event) => event.seq), [1, 2, 3]);
  assert.deepEqual(store.listTail('conv_1', '').events.map((event) => event.seq), [1, 2, 3]);
  assert.deepEqual(store.listBefore('conv_1', 3, '   ').events.map((event) => event.seq), [1, 2]);
});

test('conversation event store before page supports SQLite sequence gaps', () => {
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const sqlite = new AppSqliteStore({ dbPath: tempConversationDbPath('conversation-events-gap-') });
  sqlite.saveConversation({
    id: 'conv_gap', workspaceId: 'default', workspacePath: process.cwd(), adapter: 'claude',
    permissionMode: 'default', deviceId: 'device_1', status: 'idle', cliSessionId: null,
    sessionBinding: 'unknown', userMessageCount: 0, blockingItem: null, idleExpiresAt: null,
    createdAt: '2026-05-03T00:00:00.000Z', updatedAt: '2026-05-03T00:00:00.000Z',
    capabilities: {}, handle: null
  });
  for (const seq of [10, 20, 30]) {
    sqlite.appendEvent({
      seq,
      conversationId: 'conv_gap',
      type: 'assistant.message',
      createdAt: '2026-05-03T00:00:00.000Z',
      text: `event ${seq}`
    });
  }
  const store = new ConversationEventStore({ persistentStore: sqlite });

  assert.deepEqual(store.listAfter('conv_gap', 0).map((event) => event.seq), [10, 20, 30]);

  const page = store.listBefore('conv_gap', 30, 1);
  assert.deepEqual(page.events.map((event) => event.seq), [20]);
  assert.equal(page.hasMoreBefore, true);
  assert.deepEqual(store.listTail('conv_gap', undefined).events.map((event) => event.seq), [10, 20, 30]);
  assert.deepEqual(store.listTail('conv_gap', null).events.map((event) => event.seq), [10, 20, 30]);
  assert.deepEqual(store.listTail('conv_gap', '').events.map((event) => event.seq), [10, 20, 30]);
  assert.deepEqual(store.listBefore('conv_gap', 30, '   ').events.map((event) => event.seq), [10, 20]);
  sqlite.close();
});

test('conversation event store isolates append listener failures', () => {
  const store = new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') });
  const observed = [];
  store.onAppend(() => {
    observed.push('first');
    throw new Error('listener failed');
  });
  store.onAppend((event) => {
    observed.push(`second:${event.seq}`);
  });

  assert.doesNotThrow(() => store.append('conv_1', 'assistant.message', { text: 'hello' }));
  assert.deepEqual(observed, ['first', 'second:1']);
  assert.equal(store.list('conv_1', 0)[0].text, 'hello');
});

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

test('default app DB path uses app-level name', () => {
  const path = require('node:path');
  const { defaultAppDbPath } = require('../daemon/src/app-sqlite-store');

  assert.equal(
    defaultAppDbPath(),
    path.join(process.cwd(), 'data', 'app', 'app.sqlite')
  );
});

test('createApp prefers APP_DB_PATH over CONVERSATION_DB_PATH compatibility alias', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const appDbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-primary-')), 'app.sqlite');
  const conversationDbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-db-alias-')), 'conversations.sqlite');

  const app = createApp({ port: 0, appDbPath, conversationDbPath, devAdapters: false });
  assert.equal(app.appSqliteStore.dbPath, appDbPath);
  app.appSqliteStore.close();
});

test('createApp defaults daemon binding to loopback for local-only access', () => {
  const originalHost = process.env.DAEMON_HOST;
  delete process.env.DAEMON_HOST;
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-loopback-default-'), devAdapters: false });
  try {
    assert.equal(app.config.host, '127.0.0.1');
  } finally {
    app.appSqliteStore.close();
    if (originalHost === undefined) delete process.env.DAEMON_HOST;
    else process.env.DAEMON_HOST = originalHost;
  }
});

test('createApp preserves explicit daemon host override', () => {
  const app = createApp({ host: '127.0.0.1', port: 0, appDbPath: tempConversationDbPath('app-db-loopback-'), devAdapters: false });
  try {
    assert.equal(app.config.host, '127.0.0.1');
  } finally {
    app.appSqliteStore.close();
  }
});

test('createApp does not expose synthetic adapters unless explicitly enabled', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const appDbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-adapters-')), 'app.sqlite');

  const app = createApp({ port: 0, mode: 'dev', appDbPath });
  try {
    const adapterNames = Array.from(app.adapterRegistry.adapters.keys());
    assert.equal(adapterNames.includes('synthetic-jsonl'), false);
    assert.equal(adapterNames.includes('synthetic-text'), false);
    assert.equal(adapterNames.includes('claude'), true);
  } finally {
    app.appSqliteStore.close();
  }
});

test('createApp exposes codex-app-server by default behind probe gate and kill switch', async () => {
  const appDbPath = tempConversationDbPath('app-server-listing-');
  const defaultApp = createApp({
    port: 0,
    appDbPath,
    codexAppServerProbe: false,
    codexAppServerModelLister: false
  });
  try {
    const adapters = await defaultApp.adapterRegistry.listCapabilities();
    const appServer = adapters.find((adapter) => adapter.adapter === 'codex-app-server' || adapter.name === 'codex-app-server');
    assert.ok(appServer);
    assert.equal(appServer.selectable, false);
    assert.equal(appServer.unavailableReason, 'probe_not_run');
    assert.equal(defaultApp.conversations.adapters.has('codex-app-server'), true);
  } finally {
    defaultApp.appSqliteStore.close();
    fs.rmSync(path.dirname(appDbPath), { recursive: true, force: true });
  }

  const disabledDbPath = tempConversationDbPath('app-server-listing-disabled-');
  const disabled = createApp({ port: 0, appDbPath: disabledDbPath, codexAppServerEnabled: false });
  try {
    const adapters = await disabled.adapterRegistry.listCapabilities();
    assert.equal(adapters.some((adapter) => adapter.adapter === 'codex-app-server' || adapter.name === 'codex-app-server'), false);
    assert.equal(disabled.conversations.adapters.has('codex-app-server'), false);
  } finally {
    disabled.appSqliteStore.close();
    fs.rmSync(path.dirname(disabledDbPath), { recursive: true, force: true });
  }

  const experimentalDisabledDbPath = tempConversationDbPath('app-server-listing-experimental-disabled-');
  const experimentalDisabled = createApp({
    port: 0,
    appDbPath: experimentalDisabledDbPath,
    codexAppServerExperimentalApi: false,
    codexAppServerModelLister: false
  });
  try {
    const adapters = await experimentalDisabled.adapterRegistry.listCapabilities();
    const appServer = adapters.find((adapter) => adapter.adapter === 'codex-app-server' || adapter.name === 'codex-app-server');
    assert.ok(appServer);
    assert.equal(appServer.selectable, false);
    assert.equal(appServer.unavailableReason, 'experimental_api_disabled');
    assert.equal(appServer.effectiveCapabilities.approval.mobileCallbacks, false);
  } finally {
    experimentalDisabled.appSqliteStore.close();
    fs.rmSync(path.dirname(experimentalDisabledDbPath), { recursive: true, force: true });
  }

  const rolloutDisabledDbPath = tempConversationDbPath('app-server-listing-rollout-disabled-');
  const rolloutDisabled = createApp({
    port: 0,
    appDbPath: rolloutDisabledDbPath,
    codexAppServerRolloutPercent: 0,
    codexAppServerTransport: 'stdio',
    codexAppServerModelLister: false
  });
  try {
    const adapters = await rolloutDisabled.adapterRegistry.listCapabilities();
    const appServer = adapters.find((adapter) => adapter.adapter === 'codex-app-server' || adapter.name === 'codex-app-server');
    assert.ok(appServer);
    assert.equal(appServer.selectable, false);
    assert.equal(appServer.unavailableReason, 'rollout_disabled');
  } finally {
    rolloutDisabled.appSqliteStore.close();
    fs.rmSync(path.dirname(rolloutDisabledDbPath), { recursive: true, force: true });
  }

  const selectableDbPath = tempConversationDbPath('app-server-listing-selectable-');
  const selectable = createApp({
    port: 0,
    appDbPath: selectableDbPath,
    codexAppServerTransport: 'stdio',
    codexAppServerProbe: false,
    codexAppServerModelLister: false
  });
  try {
    const adapters = await selectable.adapterRegistry.listCapabilities();
    const appServer = adapters.find((adapter) => adapter.adapter === 'codex-app-server' || adapter.name === 'codex-app-server');
    assert.ok(appServer);
    assert.equal(appServer.selectable, false);
    assert.equal(appServer.unavailableReason, 'probe_not_run');
    assert.equal(selectable.conversations.adapters.get('codex-app-server').detectCapabilities().selectable, false);
  } finally {
    selectable.appSqliteStore.close();
    fs.rmSync(path.dirname(selectableDbPath), { recursive: true, force: true });
  }

  const probedDbPath = tempConversationDbPath('app-server-listing-probed-');
  const probeCalls = [];
  const probed = createApp({
    port: 0,
    appDbPath: probedDbPath,
    codexAppServerTransport: 'stdio',
    codexAppServerModelLister: false,
    codexAppServerProbe: async () => {
      probeCalls.push('probe');
      return {
        installed: true,
        protocolCompatible: true,
        transportHealthy: true,
        unavailableReason: null,
        lastProbeAt: '2026-06-03T00:00:00.000Z'
      };
    }
  });
  try {
    const adapters = await probed.adapterRegistry.listCapabilities();
    const appServer = adapters.find((adapter) => adapter.adapter === 'codex-app-server' || adapter.name === 'codex-app-server');
    assert.ok(appServer);
    assert.equal(probeCalls.length, 1);
    assert.equal(appServer.selectable, true);
    assert.equal(appServer.available, true);
    assert.equal(appServer.status, 'available');
    assert.equal(appServer.transportHealthy, true);
    assert.equal(appServer.effectiveCapabilities.mobileApprovalCallbacks, true);
    assert.equal(appServer.capabilities.mobileApprovalCallbacks, true);
    assert.deepEqual(appServer.capabilities.attachments, {
      image: 'native',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    });
    assert.equal(probed.conversations.adapters.get('codex-app-server').detectCapabilities().selectable, true);
  } finally {
    probed.appSqliteStore.close();
    fs.rmSync(path.dirname(probedDbPath), { recursive: true, force: true });
  }
});

test('Codex app-server default probe avoids slow model list request', async () => {
  const { createCodexAppServerProbe } = require('../daemon/src/main');
  const sent = [];
  let shutdownOptions = null;
  const probe = createCodexAppServerProbe({
    shutdownGraceMs: 123,
    lifecycle: {
      spawn() {
        return {
          transport: {
            sendRequest(method, params, options) {
              sent.push({ kind: 'request', method, params, options });
              return Promise.resolve({});
            },
            sendNotification(method, params) {
              sent.push({ kind: 'notification', method, params });
            }
          },
          async shutdown(options) {
            shutdownOptions = options;
          }
        };
      }
    }
  });

  const availability = await probe();

  assert.equal(availability.transportHealthy, true);
  assert.deepEqual(shutdownOptions, {
    gracefulShutdownMs: 123,
    hardKillGraceMs: 123
  });
  assert.deepEqual(sent.map((message) => `${message.kind}:${message.method}`), [
    'request:initialize',
    'notification:initialized'
  ]);
});

test('Codex app-server probe initializes through typed client', async () => {
  const { createCodexAppServerProbe } = require('../daemon/src/main');
  const calls = [];
  const probe = createCodexAppServerProbe({
    lifecycle: {
      spawn() {
        return {
          transport: {
            sendRequest(method, params, options) {
              calls.push({ method, params, options });
              return Promise.resolve({});
            },
            sendNotification(method, params) {
              calls.push({ notification: method, params });
            }
          },
          shutdown() {
            calls.push({ shutdown: true });
            return Promise.resolve();
          }
        };
      }
    }
  });

  const status = await probe();

  assert.equal(status.transportHealthy, true);
  assert.deepEqual(calls.map((call) => {
    if (call.shutdown) return 'shutdown';
    return call.method || `notification:${call.notification}`;
  }), [
    'initialize',
    'notification:initialized',
    'shutdown'
  ]);
  assert.equal(calls[0].options.timeoutMs, 10000);
});

test('Codex app-server listing adapter exposes app-server model list', async () => {
  const adapter = new CodexAppServerListingAdapter({
    enabled: true,
    installed: true,
    protocolCompatible: true,
    transportHealthy: true,
    unavailableReason: null,
    modelLister: async () => ({
      canSelectModel: true,
      selectedModel: 'gpt-5.5',
      models: [
        { id: 'gpt-5.5', label: 'GPT-5.5', source: 'app_server', selected: true },
        { id: 'gpt-5-codex', label: 'GPT-5 Codex', source: 'app_server', selected: false }
      ]
    })
  });

  const status = await adapter.detectCapabilities();
  const modelCapability = await adapter.getModelCapability(status);

  assert.equal(status.selectable, true);
  assert.equal(modelCapability.canSelectModel, true);
  assert.equal(modelCapability.selectedModel, 'gpt-5.5');
  assert.deepEqual(modelCapability.models.map((model) => model.id), ['gpt-5.5', 'gpt-5-codex']);
});

test('createApp exposes app-server model list through adapter registry', async () => {
  const dbPath = tempConversationDbPath('app-server-model-registry-');
  const app = createApp({
    port: 0,
    appDbPath: dbPath,
    codexAppServerTransport: 'stdio',
    codexAppServerProbe: async () => ({
      installed: true,
      protocolCompatible: true,
      transportHealthy: true,
      unavailableReason: null,
      lastProbeAt: '2026-06-04T00:00:00.000Z'
    }),
    codexAppServerModelLister: async () => ({
      canSelectModel: true,
      selectedModel: 'gpt-5.5',
      models: [
        { id: 'gpt-5.5', label: 'GPT-5.5', source: 'app_server', selected: true },
        { id: 'gpt-5-codex', label: 'GPT-5 Codex', source: 'app_server', selected: false }
      ]
    })
  });
  try {
    const adapters = await app.adapterRegistry.listCapabilities();
    const appServer = adapters.find((adapter) => adapter.adapter === 'codex-app-server' || adapter.name === 'codex-app-server');
    assert.ok(appServer);
    assert.equal(appServer.selectable, true);
    assert.equal(appServer.canSelectModel, true);
    assert.equal(appServer.selectedModel, 'gpt-5.5');
    assert.deepEqual(appServer.models.map((model) => model.id).sort(), ['gpt-5-codex', 'gpt-5.5']);
  } finally {
    app.appSqliteStore.close();
    fs.rmSync(path.dirname(dbPath), { recursive: true, force: true });
  }
});

test('Codex app-server model lister initializes and normalizes model/list', async () => {
  const { createCodexAppServerModelLister } = require('../daemon/src/main');
  const sent = [];
  let shutdownOptions = null;
  const lister = createCodexAppServerModelLister({
    shutdownGraceMs: 123,
    lifecycle: {
      spawn() {
        return {
          transport: {
            sendRequest(method, params, options) {
              sent.push({ kind: 'request', method, params, options });
              if (method === 'model/list') {
                return Promise.resolve({
                  data: [
                    { id: 'gpt-5.5', displayName: 'GPT-5.5', isDefault: true, inputModalities: ['text', 'image'] },
                    { id: 'hidden-model', displayName: 'Hidden', hidden: true },
                    { id: 'gpt-5-codex', displayName: 'GPT-5 Codex' }
                  ],
                  nextCursor: null
                });
              }
              return Promise.resolve({});
            },
            sendNotification(method, params) {
              sent.push({ kind: 'notification', method, params });
            }
          },
          async shutdown(options) {
            shutdownOptions = options;
          }
        };
      }
    }
  });

  const modelCapability = await lister();

  assert.deepEqual(shutdownOptions, {
    gracefulShutdownMs: 123,
    hardKillGraceMs: 123
  });
  assert.deepEqual(sent.map((message) => `${message.kind}:${message.method}`), [
    'request:initialize',
    'notification:initialized',
    'request:model/list'
  ]);
  assert.equal(modelCapability.canSelectModel, true);
  assert.equal(modelCapability.selectedModel, 'gpt-5.5');
  assert.deepEqual(modelCapability.models.map((model) => model.id), ['gpt-5.5', 'gpt-5-codex']);
  assert.deepEqual(modelCapability.models[0].inputModalities, ['text', 'image']);
});

test('Codex app-server listing adapter falls back to configured Codex models when model/list fails', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-app-server-models-'));
  const homeDir = path.join(root, 'home');
  fs.mkdirSync(path.join(homeDir, '.codex'), { recursive: true });
  fs.writeFileSync(
    path.join(homeDir, '.codex', 'config.toml'),
    'model = "gpt-5-codex"\n',
    'utf8'
  );
  const adapter = new CodexAppServerListingAdapter({
    enabled: true,
    installed: true,
    protocolCompatible: true,
    transportHealthy: true,
    unavailableReason: null,
    modelLister: async () => {
      throw new Error('model/list unavailable');
    },
    modelDiscoveryOptions: {
      homeDir,
      workspacePath: root,
      env: {}
    }
  });

  try {
    const status = await adapter.detectCapabilities();
    const modelCapability = await adapter.getModelCapability(status);

    assert.equal(status.selectable, true);
    assert.equal(modelCapability.canSelectModel, true);
    assert.equal(modelCapability.selectedModel, 'gpt-5-codex');
    assert.deepEqual(modelCapability.models.map((model) => model.id), ['gpt-5-codex']);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('Codex app-server listing diagnostics include capability matrix summary', async () => {
  const adapter = new CodexAppServerListingAdapter({
    availabilityState: {
      current: {
        enabled: true,
        installed: true,
        protocolCompatible: true,
        transportHealthy: true
      }
    }
  });

  const status = await adapter.detectCapabilities();

  assert.ok(status.diagnostics.capabilityMatrix.totalMethods > 0);
  assert.ok(status.diagnostics.capabilityMatrix.supportedMethods > 0);
  assert.equal(status.diagnostics.capabilityMatrix.invalidRows, 0);
});

test('diagnostics include sanitized codex app-server adapter metrics', async () => {
  const dbPath = tempConversationDbPath('app-server-diagnostics-');
  const app = createApp({
    port: 0,
    appDbPath: dbPath,
    codexAppServerEnabled: true,
    codexAppServerExperimentalApi: true,
    codexAppServerRolloutPercent: 100,
    codexAppServerTransport: 'stdio',
    codexAppServerModelLister: false,
    codexAppServerProbe: async () => ({
      installed: true,
      protocolCompatible: true,
      transportHealthy: true,
      unavailableReason: null,
      lastProbeAt: '2026-06-03T00:00:00.000Z'
    })
  });
  try {
    const status = await app.diagnostics.status({ includeAdapters: true });
    const appServer = status.adapters.find((adapter) => adapter.adapter === 'codex-app-server');
    assert.ok(appServer);
    const metrics = appServer.diagnostics.metrics;
    for (const key of [
      'app_server_probe_success',
      'app_server_probe_failure',
      'app_server_spawn_failure',
      'app_server_initialize_latency',
      'fallback_before_first_request_count',
      'run_error_after_side_effect_boundary_count',
      'approval_requested_count',
      'approval_timeout_count',
      'approval_round_trip_latency',
      'transport_close_count',
      'orphan_process_cleanup_count'
    ]) {
      assert.ok(Object.prototype.hasOwnProperty.call(metrics, key), `${key} is missing`);
    }
    assert.equal(typeof metrics.fallback_before_first_request_count, 'number');
    assert.equal(Array.isArray(metrics.approval_round_trip_latency), true);
  } finally {
    app.appSqliteStore.close();
    fs.rmSync(path.dirname(dbPath), { recursive: true, force: true });
  }
});

test('Windows sleep inhibitor starts a scoped power request process', () => {
  const { createWindowsSleepInhibitor } = require('../daemon/src/windows-sleep-inhibitor');
  const calls = [];
  const child = {
    killed: false,
    unrefCalled: false,
    kill() { this.killed = true; },
    unref() { this.unrefCalled = true; }
  };
  const inhibitor = createWindowsSleepInhibitor({
    platform: 'win32',
    pid: 1234,
    env: {},
    spawnFn(command, args, options) {
      calls.push({ command, args, options });
      return child;
    },
    logger: { warn() {}, log() {} }
  });

  const result = inhibitor.start();

  assert.equal(result.active, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, 'powershell.exe');
  assert.equal(calls[0].options.windowsHide, true);
  assert.equal(calls[0].options.stdio, 'ignore');
  assert.match(calls[0].args.join(' '), /SetThreadExecutionState/);
  assert.match(calls[0].args.join(' '), /1234/);
  assert.equal(child.unrefCalled, true);

  inhibitor.stop();
  assert.equal(child.killed, true);
});

test('Windows sleep inhibitor stays inactive when unsupported or disabled', () => {
  const { createWindowsSleepInhibitor } = require('../daemon/src/windows-sleep-inhibitor');
  let spawnCount = 0;
  const spawnFn = () => {
    spawnCount += 1;
    return { kill() {} };
  };

  const unsupported = createWindowsSleepInhibitor({
    platform: 'linux',
    env: {},
    spawnFn,
    logger: { warn() {}, log() {} }
  });
  assert.equal(unsupported.start().active, false);

  const disabled = createWindowsSleepInhibitor({
    platform: 'win32',
    env: { DAEMON_PREVENT_SLEEP: '0' },
    spawnFn,
    logger: { warn() {}, log() {} }
  });
  assert.equal(disabled.start().active, false);
  assert.equal(spawnCount, 0);
});

test('daemon self-protection detects commands targeting daemon pid or port', () => {
  const { daemonSelfProtectionForCommand } = require('../daemon/src/daemon-self-protection');

  assert.equal(daemonSelfProtectionForCommand('taskkill /F /PID 43170', {
    daemonPid: 43170,
    daemonPort: 4317
  }).blocked, true);
  assert.equal(daemonSelfProtectionForCommand('netstat -ano | findstr :4317 | taskkill /F /PID', {
    daemonPid: 100,
    daemonPort: 4317
  }).blocked, true);
  assert.equal(daemonSelfProtectionForCommand('taskkill /F /PID 30010', {
    daemonPid: 43170,
    daemonPort: 4317
  }).blocked, false);
});

test('start-daemon batch restarts unexpected daemon exits', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'start-daemon.bat'), 'utf8');
  assert.match(source, /:start_daemon/);
  assert.match(source, /goto start_daemon/);
  assert.match(source, /DAEMON_WATCHDOG/);
  assert.match(source, /process exited with code/);
});

test('npm daemon start uses watchdog supervisor', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));
  const source = fs.readFileSync(path.join(__dirname, 'start-daemon-watchdog.js'), 'utf8');
  assert.equal(packageJson.scripts['start:daemon'], 'node scripts/start-daemon-watchdog.js');
  assert.match(source, /spawn\(process\.execPath/);
  assert.match(source, /daemonEntry/);
  assert.match(source, /main\.js/);
  assert.match(source, /restarting in/);
});

test('notification websocket rejects missing bearer token', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-auth-missing-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const socket = new WebSocket(wsUrl(port));
    const closeCode = await waitForWsClose(socket);
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
    assert.equal(hello.authExpiresAt, paired.body.accessTokenExpiresAt);
    assert.deepEqual(hello.capabilities.topics, ['conversation.events']);
    assert.equal(hello.capabilities.maxReplayEvents, 1000);
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('notification websocket closes when the access token expires', async () => {
  const app = createApp({
    port: 0,
    devAdapters: true,
    accessTokenTtlMs: 200,
    appDbPath: tempConversationDbPath('app-db-ws-token-expiry-')
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-token-expiry', deviceId: 'ws-device-token-expiry' });
    socket = await openNotificationSocket(port, paired.body.token);
    const hello = await readWsJson(socket);
    const error = await readWsJson(socket);
    const closeCode = await waitForWsClose(socket);

    assert.equal(hello.type, 'hello');
    assert.equal(hello.authExpiresAt, paired.body.accessTokenExpiresAt);
    assert.equal(error.type, 'error');
    assert.equal(error.code, notificationErrorCodes.TOKEN_EXPIRED);
    assert.equal(closeCode, 1008);
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('notification websocket hub closes active connections during teardown', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-close-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-close-test', deviceId: 'ws-device-close-1' });
    socket = await openNotificationSocket(port, paired.body.token);
    const hello = await readWsJson(socket);
    assert.equal(hello.type, 'hello');
    assert.equal(app.notificationHub.connections.size, 1);

    app.notificationHub.close();

    assert.equal(app.notificationHub.connections.size, 0);
    assert.doesNotThrow(() => app.notificationHub.close());
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

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
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'claude' }, token);
    const conversationId = created.body.conversation.id;
    const first = app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'first' });
    const second = app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'second' });

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_1',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: first.seq
    }));
    const subscribed = await readWsJson(socket);
    const replayed = await readWsJson(socket);
    assert.equal(subscribed.type, 'subscribed');
    assert.equal(replayed.type, 'event');
    assert.equal(replayed.seq, second.seq);
    assert.equal(replayed.payload.text, 'second');
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
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'claude' }, token);
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
    const subscribed = await readWsJson(socket);
    const error = await readWsJson(socket);
    assert.equal(subscribed.type, 'subscribed');
    assert.equal(error.type, 'error');
    assert.equal(error.code, 'REPLAY_TRUNCATED');
    assert.deepEqual(error.scope, { conversationId });
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

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
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'claude' }, token);
    const conversationId = created.body.conversation.id;
    const startedSeq = app.conversationEventStore.list(conversationId, 0).at(-1).seq;
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
      afterSeq: startedSeq
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
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'claude' }, token);
    const conversationId = created.body.conversation.id;
    const afterSeq = app.conversationEventStore.list(conversationId, 0).at(-1).seq;

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_live',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq
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
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'claude' }, token);
    const conversationId = created.body.conversation.id;
    const old = app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'old' });

    socket = await openNotificationSocket(port, token);
    await readWsJson(socket);
    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_first',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: old.seq - 1
    }));
    const firstSubscribed = await readWsJson(socket);
    const replayed = await readWsJson(socket);
    assert.equal(firstSubscribed.type, 'subscribed');
    assert.equal(replayed.type, 'event');
    assert.equal(replayed.payload.text, 'old');

    socket.send(JSON.stringify({
      type: 'subscribe',
      id: 'req_second',
      topic: 'conversation.events',
      scope: { conversationId },
      afterSeq: old.seq
    }));
    const secondSubscribed = await readWsJson(socket);
    assert.equal(secondSubscribed.type, 'subscribed');
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

test('notification hub queues live appends during replay and flushes without missing sequence', async () => {
  const replayEvents = [
    { seq: 2, conversationId: 'conv_1', type: 'assistant.message', createdAt: '2026-05-23T00:00:00.000Z', text: 'replay-1' },
    { seq: 3, conversationId: 'conv_1', type: 'assistant.message', createdAt: '2026-05-23T00:00:01.000Z', text: 'replay-2' }
  ];
  const liveEvent = {
    seq: 4,
    conversationId: 'conv_1',
    type: 'assistant.message',
    createdAt: '2026-05-23T00:00:02.000Z',
    text: 'live-during-replay'
  };
  const hub = new NotificationHub({
    conversations: {
      requireConversation: () => ({ id: 'conv_1' }),
      listEvents: () => replayEvents
    },
    version: { daemonVersion: 'test' },
    replayBatchSize: 1
  });
  const connection = createNotificationHubTestConnection();
  hub.connections.set(connection.id, connection);
  let publishedLive = false;
  hub.send = (_connection, frame) => {
    connection.sentFrames.push(frame);
    if (frame.type === 'event' && frame.seq === 2 && !publishedLive) {
      publishedLive = true;
      hub.publishConversationEvent(liveEvent);
    }
    return true;
  };

  await hub.subscribe(connection, {
    type: 'subscribe',
    id: 'req_replay_live',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 1
  });

  assert.deepEqual(
    connection.sentFrames.filter((frame) => frame.type === 'event').map((frame) => frame.seq),
    [2, 3, 4]
  );
});

test('notification hub duplicate subscribe stops stale replay generation', async () => {
  const replayEvents = [
    { seq: 2, conversationId: 'conv_1', type: 'assistant.message', createdAt: '2026-05-23T00:00:00.000Z', text: 'old-1' },
    { seq: 3, conversationId: 'conv_1', type: 'assistant.message', createdAt: '2026-05-23T00:00:01.000Z', text: 'old-2' }
  ];
  const hub = new NotificationHub({
    conversations: {
      requireConversation: () => ({ id: 'conv_1' }),
      listEvents: (_conversationId, afterSeq) => (afterSeq >= 3 ? [] : replayEvents)
    },
    version: { daemonVersion: 'test' },
    replayBatchSize: 1
  });
  const connection = createNotificationHubTestConnection();
  let replacementSubscribe = null;
  hub.send = (_connection, frame) => {
    connection.sentFrames.push(frame);
    if (frame.type === 'event' && frame.seq === 2 && !replacementSubscribe) {
      replacementSubscribe = hub.subscribe(connection, {
        type: 'subscribe',
        id: 'req_new',
        topic: 'conversation.events',
        scope: { conversationId: 'conv_1' },
        afterSeq: 3
      });
    }
    return true;
  };

  await hub.subscribe(connection, {
    type: 'subscribe',
    id: 'req_old',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 1
  });
  if (replacementSubscribe) await replacementSubscribe;

  assert.deepEqual(
    connection.sentFrames.filter((frame) => frame.type === 'subscribed').map((frame) => frame.id),
    ['req_old', 'req_new']
  );
  assert.deepEqual(
    connection.sentFrames.filter((frame) => frame.type === 'event').map((frame) => frame.seq),
    [2]
  );
});

test('notification hub live publish only touches subscribers for the conversation', async () => {
  const hub = new NotificationHub({
    conversations: {
      requireConversation: (_conversationId) => ({ id: _conversationId }),
      listEvents: () => []
    },
    version: { daemonVersion: 'test' }
  });
  const subscribed = createNotificationHubTestConnection();
  subscribed.id = 'ws_subscribed';
  const unrelated = createNotificationHubTestConnection();
  unrelated.id = 'ws_unrelated';
  let unrelatedSubscriptionLookups = 0;
  unrelated.subscriptions = {
    get() {
      unrelatedSubscriptionLookups += 1;
      return undefined;
    }
  };
  hub.connections.set(subscribed.id, subscribed);
  hub.connections.set(unrelated.id, unrelated);
  hub.send = (connection, frame) => {
    connection.sentFrames.push(frame);
    return true;
  };

  await hub.subscribe(subscribed, {
    type: 'subscribe',
    id: 'req_sub',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 0
  });
  hub.publishConversationEvent({
    seq: 1,
    conversationId: 'conv_1',
    type: 'assistant.message',
    createdAt: '2026-05-23T00:00:00.000Z',
    text: 'live'
  });

  assert.equal(unrelatedSubscriptionLookups, 0);
  assert.deepEqual(
    subscribed.sentFrames.filter((frame) => frame.type === 'event').map((frame) => frame.seq),
    [1]
  );
});

test('notification hub removes live subscription and sends forbidden when access is revoked', () => {
  let authorized = true;
  const hub = new NotificationHub({
    conversations: {
      requireConversation: () => {
        if (!authorized) {
          const error = new Error('conversation not found');
          error.status = 404;
          throw error;
        }
        return { id: 'conv_1' };
      },
      listEvents: () => []
    },
    version: { daemonVersion: 'test' }
  });
  const connection = createNotificationHubTestConnection();
  let closed = null;
  connection.ws.close = (code, reason) => {
    closed = { code, reason };
  };
  hub.send = (_connection, frame) => {
    connection.sentFrames.push(frame);
    return true;
  };
  const subscription = {
    key: subscriptionKey('conversation.events', { conversationId: 'conv_1' }),
    generation: 1,
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    conversationId: 'conv_1',
    replaying: false,
    queuedLiveEvents: []
  };
  hub.addSubscription(connection, subscription);
  hub.connections.set(connection.id, connection);

  authorized = false;
  hub.publishConversationEvent({
    seq: 2,
    conversationId: 'conv_1',
    type: 'assistant.message',
    createdAt: '2026-05-23T00:00:00.000Z',
    text: 'blocked'
  });

  assert.equal(connection.subscriptions.has(subscription.key), false);
  assert.deepEqual(connection.sentFrames.map((frame) => frame.type), ['error']);
  assert.equal(connection.sentFrames[0].code, notificationErrorCodes.FORBIDDEN);
  assert.deepEqual(connection.sentFrames[0].scope, { conversationId: 'conv_1' });
  assert.equal(closed, null);
});

test('notification hub maps initial subscription access failures to forbidden', async () => {
  const hub = new NotificationHub({
    conversations: {
      requireConversation: () => {
        const error = new Error('conversation not found');
        error.status = 404;
        error.code = 'NOT_FOUND';
        throw error;
      },
      listEvents: () => []
    },
    version: { daemonVersion: 'test' }
  });
  const connection = createNotificationHubTestConnection();
  let closed = null;
  connection.ws.close = (code, reason) => {
    closed = { code, reason };
  };
  hub.send = (_connection, frame) => {
    connection.sentFrames.push(frame);
    return true;
  };

  hub.handleMessage(connection, JSON.stringify({
    type: 'subscribe',
    id: 'req_missing',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_missing' },
    afterSeq: 0
  }));
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(connection.subscriptions.size, 0);
  assert.deepEqual(connection.sentFrames.map((frame) => frame.type), ['error']);
  assert.equal(connection.sentFrames[0].id, 'req_missing');
  assert.equal(connection.sentFrames[0].code, notificationErrorCodes.FORBIDDEN);
  assert.deepEqual(connection.sentFrames[0].scope, { conversationId: 'conv_missing' });
  assert.equal(closed, null);
});

test('notification hub removes subscription when replay lookup fails', async () => {
  const hub = new NotificationHub({
    conversations: {
      requireConversation: () => ({ id: 'conv_1' }),
      listEvents: () => {
        const error = new Error('database is busy');
        error.code = 'SQLITE_BUSY';
        throw error;
      }
    },
    version: { daemonVersion: 'test' }
  });
  const connection = createNotificationHubTestConnection();
  let closed = null;
  connection.ws.close = (code, reason) => {
    closed = { code, reason };
  };
  hub.send = (_connection, frame) => {
    connection.sentFrames.push(frame);
    return true;
  };

  hub.handleMessage(connection, JSON.stringify({
    type: 'subscribe',
    id: 'req_replay_failure',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    afterSeq: 0
  }));
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(connection.subscriptions.size, 0);
  assert.equal(hub.conversationSubscriptions.has('conv_1'), false);
  assert.deepEqual(
    connection.sentFrames.map((frame) => frame.type),
    ['subscribed', 'error']
  );
  assert.equal(connection.sentFrames[1].id, 'req_replay_failure');
  assert.equal(connection.sentFrames[1].code, notificationErrorCodes.INTERNAL_ERROR);
  assert.deepEqual(connection.sentFrames[1].scope, { conversationId: 'conv_1' });
  assert.deepEqual(closed, {
    code: 1011,
    reason: notificationErrorCodes.INTERNAL_ERROR
  });
});

test('notification hub heartbeat terminates missed-pong connections and removes subscriptions', () => {
  let pingCalls = 0;
  let terminateCalls = 0;
  const hub = new NotificationHub({
    conversations: null,
    conversationEventStore: { onAppend() { return () => {}; } },
    version: { daemonVersion: 'test' },
    heartbeatIntervalMs: 25000
  });
  const connection = createNotificationHubTestConnection();
  connection.ws = {
    readyState: WebSocket.OPEN,
    ping() {
      pingCalls += 1;
    },
    terminate() {
      terminateCalls += 1;
    }
  };
  connection.alive = true;
  connection.closed = false;
  connection.subscriptions.set(
    subscriptionKey('conversation.events', { conversationId: 'conv_1' }),
    { topic: 'conversation.events' }
  );
  hub.connections.set(connection.id, connection);

  hub.runHeartbeat();

  assert.equal(pingCalls, 1);
  assert.equal(terminateCalls, 0);
  assert.equal(connection.alive, false);
  assert.equal(hub.connections.size, 1);

  hub.runHeartbeat();

  assert.equal(pingCalls, 1);
  assert.equal(terminateCalls, 1);
  assert.equal(hub.connections.size, 0);
  assert.equal(connection.subscriptions.size, 0);
});

test('notification websocket closes slow clients on backpressure', async () => {
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

test('notification websocket closes clients at queued frame limit without buffered bytes', async () => {
  const sentFrames = [];
  let closed = null;
  const ws = {
    OPEN: 1,
    readyState: 1,
    bufferedAmount: 0,
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
    maxBufferedBytes: 1024 * 1024,
    maxQueuedFrames: 1
  });
  const sent = hub.send({
    id: 'ws_queue_limit',
    ws,
    subscriptions: new Map(),
    pendingFrameCount: 1
  }, { type: 'event', payload: {} });

  assert.equal(sent, false);
  assert.equal(sentFrames.length, 1);
  assert.equal(sentFrames[0].type, 'error');
  assert.equal(sentFrames[0].code, 'BACKPRESSURE');
  assert.deepEqual(closed, { code: 1013, reason: 'BACKPRESSURE' });
});

test('notification websocket closes connections after max connection age', async () => {
  const app = createApp({ port: 0, devAdapters: true, appDbPath: tempConversationDbPath('app-db-ws-auth-age-') });
  app.notificationHub.websocketMaxConnectionAgeMs = 20;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let socket;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'ws-auth-age', deviceId: 'ws-device-auth-age' });
    socket = await openNotificationSocket(port, paired.body.token);
    const hello = await readWsJson(socket);
    const error = await readWsJson(socket);
    const closeCode = await waitForWsClose(socket);

    assert.equal(hello.type, 'hello');
    assert.equal(error.type, 'error');
    assert.equal(error.code, 'TOKEN_EXPIRED');
    assert.equal(closeCode, 1008);
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('app SQLite store persists workspaces and device authorizations', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspaces-'));
  const dbPath = path.join(dir, 'app.sqlite');
  const first = new AppSqliteStore({ dbPath, now: () => new Date('2026-05-05T00:00:00.000Z') });
  const workspace = first.saveWorkspaceForDevice({
    deviceId: 'device_1',
    workspacePath: path.join(dir, 'project'),
    name: 'Project'
  });
  first.close();

  const second = new AppSqliteStore({ dbPath, now: () => new Date('2026-05-05T00:00:01.000Z') });
  const listed = second.listWorkspacesForDevice('device_1');
  assert.equal(listed.length, 1);
  assert.equal(listed[0].id, workspace.id);
  assert.equal(listed[0].name, 'Project');
  assert.equal(listed[0].path, path.resolve(path.join(dir, 'project')));
  assert.deepEqual(second.listWorkspacesForDevice('device_2'), []);
  second.close();
});

test('app SQLite store repairs missing owner workspace authorizations on startup', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspace-auth-repair-'));
  const dbPath = path.join(dir, 'app.sqlite');
  const workspacePath = path.join(dir, 'project');
  const first = new AppSqliteStore({ dbPath, now: () => new Date('2026-05-05T00:00:00.000Z') });
  const workspace = first.saveWorkspaceForDevice({
    deviceId: 'device_1',
    workspacePath,
    name: 'Project'
  });
  first.db.prepare(`
    DELETE FROM workspace_device_authorizations
    WHERE device_id = ? AND workspace_id = ?
  `).run('device_1', workspace.id);
  assert.deepEqual(first.listWorkspacesForDevice('device_1'), []);
  first.close();

  const repaired = new AppSqliteStore({ dbPath, now: () => new Date('2026-05-05T00:00:01.000Z') });
  const listed = repaired.listWorkspacesForDevice('device_1');
  assert.deepEqual(listed.map((item) => item.id), [workspace.id]);
  assert.equal(listed[0].name, 'Project');
  assert.equal(listed[0].path, path.resolve(workspacePath));
  repaired.close();
});

test('app SQLite store scopes duplicate workspace paths by owner device without create-time rename', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-device-scope-'));
  const store = new AppSqliteStore({ dbPath: path.join(dir, 'app.sqlite') });
  const workspacePath = path.join(dir, 'shared-name');
  const first = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'One' });
  const renamed = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'Renamed' });
  const second = store.saveWorkspaceForDevice({ deviceId: 'device_2', workspacePath, name: 'Two' });

  assert.equal(first.id, renamed.id);
  assert.notEqual(first.id, second.id);
  assert.equal(store.listWorkspacesForDevice('device_1').length, 1);
  assert.equal(store.listWorkspacesForDevice('device_1')[0].name, 'One');
  assert.equal(store.listWorkspacesForDevice('device_2').length, 1);
  assert.equal(store.listWorkspacesForDevice('device_2')[0].name, 'Two');
  store.close();
});

test('app SQLite store logically deletes workspaces and re-adds same path as new id', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspace-delete-'));
  const store = new AppSqliteStore({
    dbPath: path.join(dir, 'app.sqlite'),
    now: (() => {
      const dates = [
        new Date('2026-05-11T00:00:00.000Z'),
        new Date('2026-05-11T00:00:01.000Z'),
        new Date('2026-05-11T00:00:02.000Z')
      ];
      return () => dates.shift() || new Date('2026-05-11T00:00:03.000Z');
    })()
  });
  const workspacePath = path.join(dir, 'project');
  const first = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'First' });

  const deleted = store.markWorkspaceDeletedForDevice({ deviceId: 'device_1', workspaceId: first.id });
  const afterDelete = store.listWorkspacesForDevice('device_1');
  const second = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'Second' });

  assert.equal(deleted.id, first.id);
  assert.deepEqual(afterDelete, []);
  assert.notEqual(second.id, first.id);
  assert.equal(second.name, 'Second');
  assert.equal(second.path, path.resolve(workspacePath));
  assert.deepEqual(store.listWorkspacesForDevice('device_1').map((item) => item.id), [second.id]);
  assert.equal(store.getWorkspaceForDevice(first.id, 'device_1'), null);
  store.close();
});

test('app SQLite store renames active workspaces and rejects deleted workspaces', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspace-rename-'));
  const store = new AppSqliteStore({ dbPath: path.join(dir, 'app.sqlite') });
  const workspace = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath: path.join(dir, 'project'), name: 'Before' });

  const renamed = store.renameWorkspaceForDevice({ deviceId: 'device_1', workspaceId: workspace.id, name: 'After' });
  store.markWorkspaceDeletedForDevice({ deviceId: 'device_1', workspaceId: workspace.id });

  assert.equal(renamed.id, workspace.id);
  assert.equal(renamed.name, 'After');
  assert.equal(renamed.path, workspace.path);
  assert.equal(store.renameWorkspaceForDevice({ deviceId: 'device_1', workspaceId: workspace.id, name: 'Hidden' }), null);
  assert.equal(store.renameWorkspaceForDevice({ deviceId: 'device_1', workspaceId: workspace.id, name: '   ' }), null);
  store.close();
});

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

test('app SQLite store persists session binding and user message count', () => {
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const sqlite = new AppSqliteStore({ dbPath: tempConversationDbPath('conversation-binding-') });
  sqlite.saveConversation({
    id: 'conv_binding', workspaceId: 'default', workspacePath: process.cwd(), adapter: 'claude',
    permissionMode: 'default', deviceId: 'device_1', status: 'cancelled', cliSessionId: 'claude-session-1',
    sessionBinding: 'confirmed', userMessageCount: 3, blockingItem: null, idleExpiresAt: null,
    createdAt: '2026-05-08T00:00:00.000Z', updatedAt: '2026-05-08T00:00:01.000Z', model: 'gpt-5.5', capabilities: { resume: true }, handle: null
  });

  const loaded = sqlite.loadConversations()[0];
  assert.equal(loaded.sessionBinding, 'confirmed');
  assert.equal(loaded.userMessageCount, 3);
  assert.equal(loaded.cliSessionId, 'claude-session-1');
  assert.equal(loaded.model, 'gpt-5.5');
  sqlite.close();
});

test('app SQLite store persists requested and effective adapter metadata', () => {
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const sqlite = new AppSqliteStore({ dbPath: tempConversationDbPath('conversation-adapter-metadata-') });
  sqlite.saveConversation({
    id: 'conv_adapter_meta',
    workspaceId: 'default',
    workspacePath: process.cwd(),
    adapter: 'codex-app-server',
    requestedAdapter: 'codex-app-server',
    effectiveAdapter: 'codex',
    effectiveCapabilities: { resume: true, waitingApproval: false },
    fallbackNotice: { reason: 'probe_failed', at: '2026-06-03T00:00:00.000Z' },
    providerSession: {
      provider: 'codex-app-server',
      threadId: 'thread_1',
      protocolVersion: '0.136.0',
      cwd: process.cwd(),
      model: 'gpt-5.5',
      sandboxProfile: 'read-only',
      createdAt: '2026-06-03T00:00:00.000Z'
    },
    permissionMode: 'default',
    deviceId: 'device_1',
    status: 'idle',
    cliSessionId: 'thread_1',
    sessionBinding: 'confirmed',
    userMessageCount: 1,
    blockingItem: null,
    idleExpiresAt: null,
    createdAt: '2026-06-03T00:00:00.000Z',
    updatedAt: '2026-06-03T00:00:01.000Z',
    model: 'gpt-5.5',
    capabilities: { resume: false, waitingApproval: true },
    handle: null
  });

  const loaded = sqlite.loadConversations()[0];
  assert.equal(loaded.requestedAdapter, 'codex-app-server');
  assert.equal(loaded.effectiveAdapter, 'codex');
  assert.deepEqual(loaded.effectiveCapabilities, { resume: true, waitingApproval: false });
  assert.deepEqual(loaded.fallbackNotice, { reason: 'probe_failed', at: '2026-06-03T00:00:00.000Z' });
  assert.equal(loaded.providerSession.threadId, 'thread_1');
  assert.equal(loaded.providerSession.provider, 'codex-app-server');
  sqlite.close();
});

test('app SQLite store restores legacy user-message conversations as interrupted', () => {
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const sqlite = new AppSqliteStore({ dbPath: tempConversationDbPath('conversation-legacy-') });
  sqlite.saveConversation({
    id: 'conv_legacy', workspaceId: 'default', workspacePath: process.cwd(), adapter: 'claude',
    permissionMode: 'default', deviceId: 'device_1', status: 'idle', cliSessionId: null,
    sessionBinding: 'unknown', userMessageCount: 0, blockingItem: null, idleExpiresAt: null,
    createdAt: '2026-05-08T00:00:00.000Z', updatedAt: '2026-05-08T00:00:01.000Z', capabilities: { resume: true }, handle: null
  });
  const events = new ConversationEventStore({ persistentStore: sqlite, now: () => new Date('2026-05-08T00:00:02.000Z') });
  events.append('conv_legacy', 'user.message', { text: 'hello' });

  const loaded = sqlite.loadConversations()[0];
  assert.equal(loaded.status, 'interrupted');
  assert.equal(loaded.sessionBinding, 'unknown');
  assert.equal(loaded.userMessageCount, 1);
  sqlite.close();
});

test('app SQLite store backfills conversation title from first user message', () => {
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const sqlite = new AppSqliteStore({ dbPath: tempConversationDbPath('conversation-title-backfill-') });
  sqlite.saveConversation({
    id: 'conv_title_backfill', workspaceId: 'default', workspacePath: process.cwd(), adapter: 'codex',
    permissionMode: 'default', deviceId: 'device_1', status: 'idle', cliSessionId: 'thread_1',
    sessionBinding: 'confirmed', userMessageCount: 0, blockingItem: null, idleExpiresAt: null,
    createdAt: '2026-05-08T00:00:00.000Z', updatedAt: '2026-05-08T00:00:01.000Z', capabilities: { resume: true }, handle: null
  });
  const events = new ConversationEventStore({ persistentStore: sqlite, now: () => new Date('2026-05-08T00:00:02.000Z') });
  events.append('conv_title_backfill', 'user.message', { text: '  first line\nsecond line  ' });
  events.append('conv_title_backfill', 'user.message', { text: 'newer message should not win' });

  const loaded = sqlite.loadConversations()[0];
  assert.equal(loaded.title, 'first line second line');
  assert.equal(
    sqlite.db.prepare('SELECT title FROM conversations WHERE id = ?').get('conv_title_backfill').title,
    'first line second line'
  );
  sqlite.close();
});

test('conversation manager handles input and approval blocking states', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const fakeHandle = {
    sent: [],
    approvals: [],
    sendUserMessage(text) { this.sent.push(text); },
    answerQuestion(_questionId, text) { this.sent.push(text); },
    respondApproval(approvalId, decision) { this.approvals.push({ approvalId, decision }); },
    cancel() {},
    dispose() {}
  };
  const adapter = {
    capabilities: {
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
      approval: {
        mobileCallbacks: true,
        scopes: ['once', 'session'],
        supportsCancel: false,
        denyBehaviors: ['interrupt', 'continue']
      }
    },
    async startConversation({ onEvent }) { adapter.onEvent = onEvent; return fakeHandle; }
  };
  const manager = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') }),
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    idleTtlMs: 600000,
    now: () => new Date('2026-05-03T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({
    workspaceId: 'default',
    adapter: 'claude',
    permissionMode: 'auto',
    requestedTools: ['Read', 'Glob'],
    requestedToolPolicy: { tools: ['Read'], allowedTools: ['Read'], disallowedTools: ['Bash'] },
    resumePolicy: { type: 'resume', sessionId: 'claude-session-1' },
    systemPromptPolicy: { type: 'append', text: 'Keep responses concise.' }
  }, device);

  assert.equal(conversation.status, 'idle');
  assert.equal(conversation.cliSessionId, null);
  assert.equal(conversation.protocolVersion, 2);
  assert.equal(conversation.requestedPermissionMode, 'auto');
  assert.equal(conversation.effectivePermissionMode, 'auto');
  assert.deepEqual(conversation.requestedTools, ['Read', 'Glob']);
  assert.deepEqual(conversation.requestedToolPolicy, { tools: ['Read'], allowedTools: ['Read'], disallowedTools: ['Bash'] });
  assert.deepEqual(conversation.resumePolicy, { type: 'resume', sessionId: 'claude-session-1' });
  assert.deepEqual(conversation.systemPromptPolicy, { type: 'append', text: 'Keep responses concise.' });
  assert.deepEqual(conversation.permissionSupport, {});
  assert.deepEqual(conversation.notices, []);
  await manager.sendMessage(conversation.id, { text: 'hello' }, device);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.deepEqual(fakeHandle.sent, ['hello']);

  adapter.onEvent({ type: 'assistant.question', questionId: 'q1', text: 'Pick direction', suggestions: ['A'], multiSelect: true, input: { multiSelect: true } });
  const waitingInput = manager.getConversation(conversation.id, device);
  assert.equal(waitingInput.status, 'waiting_input');
  assert.equal(waitingInput.blockingItem.type, 'input_request');
  assert.equal(waitingInput.blockingItem.multiSelect, true);
  assert.equal(waitingInput.blockingItem.createdAt, '2026-05-03T00:00:00.000Z');
  assert.equal(waitingInput.blockingItem.expiresAt, '2026-05-03T00:10:00.000Z');
  await assert.rejects(() => manager.sendMessage(conversation.id, { text: 'wrong path' }, device), /waiting for input response/);
  await assert.rejects(() => manager.answerQuestion(conversation.id, { questionId: 'bad', text: 'A' }, device), /questionId does not match/);
  await manager.answerQuestion(conversation.id, { questionId: 'q1', text: 'A' }, device);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.deepEqual(fakeHandle.sent, ['hello', 'A']);

  adapter.onEvent({
    type: 'approval.requested',
    approvalId: 'ap1',
    toolName: 'Bash',
    toolUseId: 'toolu_1',
    input: { command: 'dir' },
    summary: 'List files',
    approvalOptions: {
      kind: 'command',
      supportsSessionScope: true,
      supportsCancel: true,
      denyBehavior: 'continue',
      command: 'dir',
      rawProviderRequest: { env: { SECRET: 'nope' } }
    }
  });
  const waitingApproval = manager.getConversation(conversation.id, device);
  assert.equal(waitingApproval.status, 'waiting_approval');
  assert.equal(waitingApproval.blockingItem.toolUseId, 'toolu_1');
  assert.deepEqual(waitingApproval.blockingItem.approvalOptions, {
    kind: 'command',
    supportsSessionScope: true,
    supportsCancel: false,
    denyBehavior: 'continue',
    command: 'dir'
  });
  await assert.rejects(() => manager.respondApproval(conversation.id, 'bad', { decision: 'allow' }, device), /approvalId does not match/);
  await manager.respondApproval(conversation.id, 'ap1', { decision: 'allow' }, device);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.deepEqual(fakeHandle.approvals, [{ approvalId: 'ap1', decision: { decision: 'allow', scope: 'once' } }]);
  const resolvedApproval = manager.listEvents(conversation.id, 0, device)
    .find((event) => event.type === 'approval.resolved');
  assert.equal(resolvedApproval.toolUseId, 'toolu_1');
  assert.equal(resolvedApproval.scope, 'once');
  assert.equal(resolvedApproval.approvalOptions.rawProviderRequest, undefined);

  adapter.onEvent({ type: 'system.notice', text: 'Claude retry 1/3', noticeKind: 'retry' });
  const events = manager.listEvents(conversation.id, 0, device);
  assert.equal(events.at(-1).type, 'system.notice');
  assert.equal(events.at(-1).text, 'Claude retry 1/3');
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');

  adapter.onEvent({ type: 'system.notice', text: 'hidden lifecycle', visible: false });
  const hidden = manager.listEvents(conversation.id, 0, device).find((event) => event.text === 'hidden lifecycle');
  assert.ok(hidden);
  assert.equal(hidden.visible, false);
});

test('conversation manager queues concurrent blocking approvals', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const fakeHandle = {
    approvals: [],
    sendUserMessage() {},
    respondApproval(approvalId, decision) { this.approvals.push({ approvalId, decision }); }
  };
  const adapter = {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true },
    async startConversation({ onEvent }) { adapter.onEvent = onEvent; return fakeHandle; }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    idleTtlMs: 600000,
    now: () => new Date('2026-05-03T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  await manager.sendMessage(conversation.id, { text: 'research UI' }, device);

  adapter.onEvent({
    type: 'approval.requested',
    approvalId: 'ap_web_1',
    toolName: 'WebSearch',
    toolUseId: 'tool_web_1',
    input: { query: 'modern dashboard UI' },
    summary: 'WebSearch'
  });
  adapter.onEvent({
    type: 'approval.requested',
    approvalId: 'ap_web_2',
    toolName: 'WebSearch',
    toolUseId: 'tool_web_2',
    input: { query: 'developer monitoring dashboard' },
    summary: 'WebSearch'
  });

  let current = manager.getConversation(conversation.id, device);
  assert.equal(current.status, 'waiting_approval');
  assert.equal(current.blockingItem.approvalId, 'ap_web_1');
  assert.equal(eventStore.list(conversation.id, 0).filter((event) => event.type === 'approval.requested').length, 1);
  assert.equal(eventStore.list(conversation.id, 0).some((event) => event.warning === 'blocking request ignored because another blocking item is pending'), false);

  await manager.respondApproval(conversation.id, 'ap_web_1', { decision: 'allow' }, device);

  current = manager.getConversation(conversation.id, device);
  assert.equal(current.status, 'waiting_approval');
  assert.equal(current.blockingItem.approvalId, 'ap_web_2');
  assert.deepEqual(fakeHandle.approvals, [{ approvalId: 'ap_web_1', decision: { decision: 'allow', scope: 'once' } }]);
  assert.deepEqual(
    eventStore.list(conversation.id, 0)
      .filter((event) => event.type === 'approval.requested')
      .map((event) => event.approvalId),
    ['ap_web_1', 'ap_web_2']
  );

  await manager.respondApproval(conversation.id, 'ap_web_2', { decision: 'allow' }, device);

  current = manager.getConversation(conversation.id, device);
  assert.equal(current.status, 'running');
  assert.deepEqual(fakeHandle.approvals.map((item) => item.approvalId), ['ap_web_1', 'ap_web_2']);
});

test('conversation manager fails conversation when blocking response write fails', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const fakeHandle = {
    sendUserMessage() {},
    answerQuestion() { throw new Error('stdin closed'); },
    respondApproval() { throw new Error('stdin closed'); }
  };
  const adapter = {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true },
    async startConversation({ onEvent }) { adapter.onEvent = onEvent; return fakeHandle; }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    now: () => new Date('2026-05-03T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const questionConversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  await manager.sendMessage(questionConversation.id, { text: 'hello' }, device);
  adapter.onEvent({ type: 'assistant.question', questionId: 'q1', text: 'Continue?' });

  await assert.rejects(
    () => manager.answerQuestion(questionConversation.id, { questionId: 'q1', text: 'yes' }, device),
    /stdin closed/
  );

  assert.equal(manager.getConversation(questionConversation.id, device).status, 'failed');
  assert.equal(eventStore.list(questionConversation.id, 0).at(-2).type, 'run.error');
  assert.equal(eventStore.list(questionConversation.id, 0).at(-1).type, 'conversation.status_changed');

  const approvalConversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  await manager.sendMessage(approvalConversation.id, { text: 'run command' }, device);
  adapter.onEvent({ type: 'approval.requested', approvalId: 'ap1', toolName: 'Bash', input: { command: 'dir' } });

  await assert.rejects(
    () => manager.respondApproval(approvalConversation.id, 'ap1', { decision: 'allow' }, device),
    /stdin closed/
  );

  assert.equal(manager.getConversation(approvalConversation.id, device).status, 'failed');
  assert.equal(eventStore.list(approvalConversation.id, 0).at(-2).type, 'run.error');
  assert.equal(eventStore.list(approvalConversation.id, 0).at(-1).status, 'failed');
});

test('conversation manager controls active Claude conversation dynamically', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const calls = [];
  const fakeHandle = {
    sendUserMessage() {},
    setPermissionMode(mode) { calls.push(['permission', mode]); },
    setModel(model) { calls.push(['model', model]); },
    interrupt() { calls.push(['interrupt']); },
    getContextUsage() { calls.push(['context']); return { tokens: 12 }; },
    getMcpStatus() { calls.push(['mcpStatus']); return { servers: [] }; },
    reconnectMcpServer(name) { calls.push(['mcpReconnect', name]); },
    toggleMcpServer(name, enabled) { calls.push(['mcpToggle', name, enabled]); },
    stopTask(taskId) { calls.push(['stopTask', taskId]); }
  };
  const adapter = {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true },
    getModelCapability() {
      return { canSelectModel: true, models: [{ id: 'claude-sonnet' }, { id: 'claude-opus' }] };
    },
    async startConversation() { return fakeHandle; }
  };
  const manager = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore(),
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]])
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude', model: 'claude-sonnet' }, device);
  await manager.sendMessage(conversation.id, { text: 'hello' }, device);

  await manager.updatePermissionMode(conversation.id, { permissionMode: 'auto' }, device);
  await manager.updateModel(conversation.id, { model: 'claude-opus' }, device);
  assert.deepEqual((await manager.controlConversation(conversation.id, { action: 'get_context_usage' }, device)).result, { tokens: 12 });
  await manager.controlConversation(conversation.id, { action: 'interrupt' }, device);
  await manager.controlConversation(conversation.id, { action: 'get_mcp_status' }, device);
  await manager.controlConversation(conversation.id, { action: 'reconnect_mcp_server', name: 'fs' }, device);
  await manager.controlConversation(conversation.id, { action: 'toggle_mcp_server', name: 'fs', enabled: false }, device);
  await manager.controlConversation(conversation.id, { action: 'stop_task', taskId: 'task_1' }, device);

  assert.deepEqual(calls, [
    ['permission', 'auto'],
    ['model', 'claude-opus'],
    ['context'],
    ['interrupt'],
    ['mcpStatus'],
    ['mcpReconnect', 'fs'],
    ['mcpToggle', 'fs', false],
    ['stopTask', 'task_1']
  ]);
  assert.equal(manager.getConversation(conversation.id, device).effectivePermissionMode, 'auto');
  assert.equal(manager.getConversation(conversation.id, device).model, 'claude-opus');
});

test('conversation manager seeds restarted Claude conversations with recovered task titles', async () => {
  const startCalls = [];
  const adapter = {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true },
    async startConversation(input) {
      startCalls.push(input);
      return {
        async sendUserMessage() {},
        async answerQuestion() {},
        async respondApproval() {},
        async cancel() {},
        async dispose() {}
      };
    }
  };
  const { manager, device, eventStore } = createConversationManagerForTest({
    adapters: new Map([['claude', adapter]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  eventStore.append(conversation.id, conversationEventTypes.TASK_PROGRESS_UPDATED, {
    taskId: 'claude_tasks',
    source: 'claude',
    items: [
      { id: '2', title: 'Task 3-6: Server API Routes + Entry Point', status: 'pending' }
    ],
    completedCount: 0,
    totalCount: 1
  });
  eventStore.append(conversation.id, conversationEventTypes.TASK_PROGRESS_UPDATED, {
    taskId: 'claude_tasks',
    source: 'claude',
    items: [
      { id: '2', title: 'Task #2', status: 'in_progress' }
    ],
    completedCount: 0,
    totalCount: 1,
    raw: {
      type: 'assistant',
      message: {
        content: [
          { type: 'tool_use', name: 'TaskUpdate', input: { taskId: '2', status: 'in_progress' } }
        ]
      }
    }
  });

  await manager.sendMessage(conversation.id, { text: 'continue' }, device);

  assert.equal(startCalls.length, 1);
  assert.deepEqual(startCalls[0].initialTaskProgress.items, [
    { id: '2', title: 'Task 3-6: Server API Routes + Entry Point', status: 'in_progress' }
  ]);
});

test('conversation manager clears blocking item when adapter cancels blocking request', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const adapter = {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true },
    async startConversation({ onEvent }) {
      adapter.onEvent = onEvent;
      return {
        sendUserMessage() {},
        answerQuestion() {},
        respondApproval() {},
        cancel() {},
        dispose() {}
      };
    }
  };
  const manager = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore({ now: () => new Date('2026-05-03T00:00:00.000Z') }),
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    idleTtlMs: 600000,
    now: () => new Date('2026-05-03T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude', permissionMode: 'default' }, device);

  await manager.sendMessage(conversation.id, { text: 'hello' }, device);
  adapter.onEvent({ type: 'approval.requested', approvalId: 'ap_cancel', toolName: 'Bash', toolUseId: 'toolu_cancel', input: { command: 'git push --force' }, summary: 'git push --force' });
  assert.equal(manager.getConversation(conversation.id, device).status, 'waiting_approval');

  adapter.onEvent({ type: 'blocking.request_cancelled', approvalId: 'ap_cancel', requestId: 'ap_cancel', blockingType: 'approval_request', toolUseId: 'toolu_cancel', toolName: 'Bash' });

  const current = manager.getConversation(conversation.id, device);
  assert.equal(current.status, 'running');
  assert.equal(current.blockingItem, null);
  const events = manager.listEvents(conversation.id, 0, device);
  assert.equal(events.at(-2).type, 'blocking.request_cancelled');
  assert.equal(events.at(-1).type, 'conversation.status_changed');
  assert.equal(events.at(-1).status, 'running');
});

test('conversation manager keeps non-terminal assistant messages running until completion', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const adapter = {
    capabilities: { longLivedProcess: false, resume: true, partialOutput: true, toolEvents: true },
    async startConversation({ onEvent }) {
      adapter.onEvent = onEvent;
      return {
        sendUserMessage() {},
        cancel() {},
        dispose() {}
      };
    }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-09T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['codex', adapter]]),
    now: () => new Date('2026-05-09T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);

  await manager.sendMessage(conversation.id, { text: '你是谁？' }, device);
  adapter.onEvent({ type: 'assistant.message', text: '先读取规则。', turnFinal: false });
  adapter.onEvent({ type: 'tool.started', toolUseId: 'item_1', toolName: 'command_execution', input: { command: 'pwsh Get-Content' } });
  adapter.onEvent({ type: 'tool.output', toolUseId: 'item_1', toolName: 'command_execution', text: '---skill---', exitCode: 0 });

  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.equal(eventStore.list(conversation.id, 0).some((event) => event.type === 'conversation.status_changed' && event.status === 'idle'), false);

  adapter.onEvent({ type: 'assistant.message', text: '我是 Codex。', turnFinal: false });
  adapter.onEvent({ type: 'conversation.completed' });

  const events = eventStore.list(conversation.id, 0);
  assert.equal(manager.getConversation(conversation.id, device).status, 'idle');
  assert.deepEqual(events.filter((event) => event.type === 'assistant.message').map((event) => event.text), ['先读取规则。', '我是 Codex。']);
  assert.equal(events.some((event) => event.type === 'tool.started' && event.toolUseId === 'item_1'), true);
  assert.equal(events.some((event) => event.type === 'tool.output' && event.text === '---skill---'), true);
  assert.equal(events.at(-1).type, 'conversation.status_changed');
  assert.equal(events.at(-1).status, 'idle');
});

test('conversation manager publishes user message before slow adapter startup', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  let releaseStart;
  const adapter = {
    capabilities: { resume: true },
    startConversation() {
      return new Promise((resolve) => {
        releaseStart = () => resolve({
          sendUserMessage() {},
          cancel() {},
          dispose() {}
        });
      });
    }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-09T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['codex', adapter]]),
    now: () => new Date('2026-05-09T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);

  const send = manager.sendMessage(conversation.id, { text: 'hello' }, device);
  await Promise.resolve();

  const events = eventStore.list(conversation.id, 0);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.equal(events.some((event) => event.type === 'user.message' && event.text === 'hello'), true);
  assert.equal(events.some((event) => event.type === 'conversation.status_changed' && event.status === 'running'), true);

  releaseStart();
  await send;
});

test('conversation manager passes selected model into adapter startup', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const startCalls = [];
  const adapter = {
    capabilities: { resume: true },
    async startConversation(input) {
      startCalls.push(input);
      return {
        sendUserMessage() {},
        cancel() {},
        dispose() {}
      };
    }
  };
  const manager = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore({ now: () => new Date('2026-05-09T00:00:00.000Z') }),
    auditLog: new AuditLog(),
    adapters: new Map([['codex', adapter]]),
    now: () => new Date('2026-05-09T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex', model: ' gpt-5.5 ' }, device);

  assert.equal(conversation.model, 'gpt-5.5');
  await manager.sendMessage(conversation.id, { text: 'hello' }, device);

  assert.equal(manager.getConversation(conversation.id, device).model, 'gpt-5.5');
  assert.equal(startCalls.length, 1);
  assert.equal(startCalls[0].model, 'gpt-5.5');
});

test('conversation public shape exposes requested and effective adapter fields', () => {
  const { manager, device } = createConversationManagerForTest();
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);
  assert.equal(conversation.adapter, 'codex');
  assert.equal(conversation.requestedAdapter, 'codex');
  assert.equal(conversation.effectiveAdapter, 'codex');
  assert.deepEqual(conversation.effectiveCapabilities, conversation.capabilities);
  assert.equal(conversation.fallbackNotice, null);
  assert.equal(conversation.providerSession, null);
});

test('Codex app-server conversation adapter rejects sends before selectable probe', async () => {
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  let spawnCount = 0;
  const adapter = new CodexAppServerConversationAdapter({
    availability: {
      selectable: false,
      unavailableReason: 'probe_not_run',
      effectiveCapabilities: { longLivedProcess: false, waitingApproval: false }
    },
    lifecycle: {
      spawn() {
        spawnCount += 1;
        throw new Error('must not spawn');
      }
    }
  });
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([['codex-app-server', adapter]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex-app-server' }, device);
  assert.equal(conversation.adapter, 'codex-app-server');
  assert.equal(conversation.effectiveAdapter, 'codex-app-server');
  await assert.rejects(
    () => manager.sendMessage(conversation.id, { text: 'hello' }, device),
    /Codex app-server adapter is not selectable: probe_not_run/
  );
  assert.equal(spawnCount, 0);
});

test('Codex app-server conversation diagnostics include capability matrix summary', () => {
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const { buildCodexAppServerAvailability } = require('../daemon/src/codex-app-server-availability');
  const adapter = new CodexAppServerConversationAdapter({
    availability: buildCodexAppServerAvailability({
      enabled: true,
      installed: true,
      protocolCompatible: true,
      transportHealthy: true
    }),
    lifecycle: { spawn() { throw new Error('not used'); } }
  });

  const status = adapter.detectCapabilities();

  assert.ok(status.diagnostics.capabilityMatrix.totalMethods > 0);
  assert.ok(status.diagnostics.capabilityMatrix.supportedMethods > 0);
  assert.equal(status.diagnostics.capabilityMatrix.invalidRows, 0);
});

test('codex-app-server falls back to codex before provider side effects when unavailable', async () => {
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  let spawnCount = 0;
  const appServer = new CodexAppServerConversationAdapter({
    availability: {
      selectable: false,
      unavailableReason: 'probe_not_run',
      effectiveCapabilities: { longLivedProcess: false, waitingApproval: false }
    },
    lifecycle: {
      spawn() {
        spawnCount += 1;
        throw new Error('must not spawn');
      }
    }
  });
  const startCalls = [];
  const codex = {
    capabilities: {
      resume: true,
      waitingApproval: true,
      attachments: { image: 'native', textDocument: 'text_extract', pdf: 'unsupported' }
    },
    async startConversation(input) {
      startCalls.push(input);
      return {
        async sendUserMessage() {},
        async dispose() {}
      };
    }
  };
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([
      ['codex', codex],
      ['codex-app-server', appServer]
    ])
  });

  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex-app-server' }, device);
  assert.equal(conversation.adapter, 'codex-app-server');
  assert.equal(conversation.requestedAdapter, 'codex-app-server');
  assert.equal(conversation.effectiveAdapter, 'codex');
  assert.deepEqual(conversation.effectiveCapabilities, codex.capabilities);
  assert.equal(conversation.fallbackNotice.from, 'codex-app-server');
  assert.equal(conversation.fallbackNotice.to, 'codex');
  assert.equal(conversation.fallbackNotice.reason, 'probe_not_run');
  assert.equal(conversation.fallbackNotice.boundary, 'before_provider_request');

  await manager.sendMessage(conversation.id, { text: 'hello' }, device);

  assert.equal(spawnCount, 0);
  assert.equal(startCalls.length, 1);
  assert.equal(startCalls[0].conversationId, conversation.id);
  assert.equal(appServer.detectCapabilities().diagnostics.metrics.fallback_before_first_request_count, 1);
});

test('codex-app-server falls back to codex when initialize fails before side effects', async () => {
  const appServerError = new Error('initialize failed');
  appServerError.codexAppServerFallbackAllowed = true;
  let fallbackCount = 0;
  const appServer = {
    getCapabilities() {
      return { longLivedProcess: true, waitingApproval: true };
    },
    detectCapabilities() {
      return { selectable: true, effectiveCapabilities: this.getCapabilities() };
    },
    recordFallbackBeforeFirstRequest() {
      fallbackCount += 1;
    },
    async startConversation() {
      throw appServerError;
    }
  };
  const startCalls = [];
  const codex = {
    capabilities: { resume: true, waitingApproval: true },
    async startConversation(input) {
      startCalls.push(input);
      return {
        async sendUserMessage() {},
        async dispose() {}
      };
    }
  };
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([
      ['codex', codex],
      ['codex-app-server', appServer]
    ])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex-app-server' }, device);

  await manager.sendMessage(conversation.id, { text: 'hello' }, device);
  const updated = manager.getConversation(conversation.id, device);

  assert.equal(updated.adapter, 'codex-app-server');
  assert.equal(updated.requestedAdapter, 'codex-app-server');
  assert.equal(updated.effectiveAdapter, 'codex');
  assert.equal(updated.fallbackNotice.reason, 'initialize failed');
  assert.equal(updated.fallbackNotice.boundary, 'before_provider_request');
  assert.equal(startCalls.length, 1);
  assert.equal(fallbackCount, 1);
  const events = manager.eventStore.list(conversation.id, 0);
  assert.equal(events.some((event) => event.type === conversationEventTypes.SYSTEM_NOTICE && event.noticeKind === 'adapter_fallback'), true);
});

test('codex-app-server does not fall back after side-effect boundary failure', async () => {
  const appServerError = new Error('thread/start failed after boundary');
  appServerError.codexAppServerFallbackAllowed = false;
  const appServer = {
    getCapabilities() {
      return { longLivedProcess: true, waitingApproval: true };
    },
    detectCapabilities() {
      return { selectable: true, effectiveCapabilities: this.getCapabilities() };
    },
    async startConversation() {
      throw appServerError;
    }
  };
  let codexStarted = false;
  const codex = {
    capabilities: { resume: true },
    async startConversation() {
      codexStarted = true;
      return { async sendUserMessage() {} };
    }
  };
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([
      ['codex', codex],
      ['codex-app-server', appServer]
    ])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex-app-server' }, device);

  await assert.rejects(
    () => manager.sendMessage(conversation.id, { text: 'hello' }, device),
    /thread\/start failed after boundary/
  );
  const updated = manager.getConversation(conversation.id, device);
  assert.equal(updated.effectiveAdapter, 'codex-app-server');
  assert.equal(codexStarted, false);
});

test('Codex app-server conversation fallback is blocked after thread request write', async () => {
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const { buildCodexAppServerAvailability } = require('../daemon/src/codex-app-server-availability');
  const lifecycle = {
    spawn() {
      const transport = new EventEmitter();
      transport.sendRequest = async (method) => {
        if (method === 'initialize') return {};
        if (method === 'thread/start') throw new Error('provider rejected thread');
        throw new Error(`unexpected request ${method}`);
      };
      transport.sendNotification = () => {};
      return {
        transport,
        shutdown: async () => {}
      };
    }
  };
  const adapter = new CodexAppServerConversationAdapter({
    availability: buildCodexAppServerAvailability({
      enabled: true,
      installed: true,
      protocolCompatible: true,
      transportHealthy: true
    }),
    lifecycle
  });

  await assert.rejects(
    () => adapter.startConversation({ workspacePath: process.cwd(), onEvent() {} }),
    (error) => {
      assert.equal(error.codexAppServerFallbackAllowed, false);
      return /provider rejected thread/.test(error.message);
    }
  );
});

test('Codex app-server conversation adapter runs stdio thread and turn lifecycle', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const transport = new EventEmitter();
  transport.requests = [];
  transport.notifications = [];
  transport.results = [];
  transport.sendRequest = async (method, params) => {
    transport.requests.push({ method, params });
    if (method === 'initialize') return { protocolVersion: '0.1.0' };
    if (method === 'thread/start') return { thread: { id: 'thread_app_1' } };
    if (method === 'turn/start') return { turn: { id: 'turn_app_1' } };
    throw new Error(`unexpected request ${method}`);
  };
  transport.sendNotification = (method, params) => transport.notifications.push({ method, params });
  transport.sendResult = (id, result) => transport.results.push({ id, result });
  transport.sendError = (id, error) => transport.results.push({ id, error });
  const shutdowns = [];
  const adapter = new CodexAppServerConversationAdapter({
    availability: {
      selectable: true,
      effectiveCapabilities: { longLivedProcess: true, waitingApproval: true }
    },
    lifecycle: {
      spawn() {
        return {
          transport,
          pid: 123,
          shutdown: async () => {
            shutdowns.push(true);
            transport.emit('closed', new Error('closed'));
          }
        };
      }
    },
    toolTimeoutSec: 900
  });
  const events = [];

  const handle = await adapter.startConversation({
    conversationId: 'conv_app_lifecycle',
    workspacePath: 'D:\\Repo',
    permissionMode: 'default',
    model: 'gpt-5.5',
    onEvent: (event) => events.push(event)
  });
  await handle.sendUserMessage({ text: 'Inspect this.', clientMessageId: 'client_1' });
  transport.emit('notification', {
    method: 'item/completed',
    params: {
      item: { id: 'msg_1', type: 'agentMessage', text: 'done' },
      threadId: 'thread_app_1',
      turnId: 'turn_app_1'
    }
  });
  transport.emit('notification', {
    method: 'turn/completed',
    params: {
      threadId: 'thread_app_1',
      turn: { id: 'turn_app_1', status: 'completed' }
    }
  });

  assert.deepEqual(transport.requests.map((request) => request.method), ['initialize', 'thread/start', 'turn/start']);
  assert.deepEqual(transport.notifications, [{ method: 'initialized', params: {} }]);
  assert.equal(transport.requests[1].params.sandbox, 'read-only');
  assert.equal(transport.requests[2].params.sandboxPolicy.type, 'workspaceWrite');
  assert.equal(transport.requests[2].params.input[0].text, 'Inspect this.');
  assert.equal(events[0].sessionId, 'thread_app_1');
  assert.equal(events[0].providerSession.provider, 'codex-app-server');
  assert.equal(events.some((event) => event.type === conversationEventTypes.ASSISTANT_MESSAGE && event.text === 'done'), true);
  assert.equal(events.some((event) => event.type === conversationEventTypes.CONVERSATION_COMPLETED), true);

  await handle.dispose();
  assert.equal(shutdowns.length, 1);
});

test('Codex app-server conversation adapter maps approval request and response over JSON-RPC', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const transport = new EventEmitter();
  transport.requests = [];
  transport.results = [];
  transport.sendRequest = async (method, params) => {
    transport.requests.push({ method, params });
    if (method === 'initialize') return {};
    if (method === 'thread/start') return { thread: { id: 'thread_app_approval' } };
    if (method === 'turn/start') return { turn: { id: 'turn_app_approval' } };
    throw new Error(`unexpected request ${method}`);
  };
  transport.sendNotification = () => {};
  transport.sendResult = (id, result) => transport.results.push({ id, result });
  transport.sendError = (id, error) => transport.results.push({ id, error });
  const adapter = new CodexAppServerConversationAdapter({
    availability: { selectable: true, effectiveCapabilities: { waitingApproval: true } },
    lifecycle: { spawn: () => ({ transport, shutdown: async () => {} }) }
  });
  const events = [];
  const handle = await adapter.startConversation({
    conversationId: 'conv_app_approval',
    workspacePath: 'D:\\Repo',
    onEvent: (event) => events.push(event)
  });
  await handle.sendUserMessage('run tests');

  transport.emit('serverRequest', {
    id: 7,
    method: 'item/commandExecution/requestApproval',
    params: {
      threadId: 'thread_app_approval',
      turnId: 'turn_app_approval',
      itemId: 'cmd_1',
      command: 'npm test',
      availableDecisions: ['accept', 'cancel']
    }
  });
  const approval = events.find((event) => event.type === conversationEventTypes.APPROVAL_REQUESTED);
  assert.equal(approval.approvalId, 'cmd_1');
  assert.equal(approval.approvalOptions.supportsSessionScope, false);
  assert.equal(approval.approvalOptions.supportsCancel, true);

  await handle.respondApproval('cmd_1', { decision: 'allow', scope: 'session' });
  assert.deepEqual(transport.results, [{ id: 7, result: { decision: 'accept' } }]);
  await handle.respondApproval('cmd_1', { decision: 'allow' });
  assert.deepEqual(transport.results, [{ id: 7, result: { decision: 'accept' } }]);
});

test('Codex app-server conversation adapter cancels pending approval on transport close', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const transport = new EventEmitter();
  transport.sendRequest = async (method) => {
    if (method === 'initialize') return {};
    if (method === 'thread/start') return { thread: { id: 'thread_app_close' } };
    if (method === 'turn/start') return { turn: { id: 'turn_app_close' } };
    throw new Error(`unexpected request ${method}`);
  };
  transport.sendNotification = () => {};
  transport.sendResult = () => {};
  transport.sendError = () => {};
  const adapter = new CodexAppServerConversationAdapter({
    availability: { selectable: true, effectiveCapabilities: { waitingApproval: true } },
    lifecycle: { spawn: () => ({ transport, shutdown: async () => {} }) }
  });
  const events = [];
  const handle = await adapter.startConversation({
    conversationId: 'conv_app_close',
    workspacePath: 'D:\\Repo',
    onEvent: (event) => events.push(event)
  });
  await handle.sendUserMessage('run tests');
  transport.emit('serverRequest', {
    id: 8,
    method: 'item/commandExecution/requestApproval',
    params: { itemId: 'cmd_close', command: 'npm test', availableDecisions: ['accept', 'cancel'] }
  });
  transport.emit('closed', new Error('transport closed'));

  assert.equal(events.some((event) => event.type === conversationEventTypes.APPROVAL_REQUESTED), true);
  assert.equal(events.some((event) => event.type === conversationEventTypes.BLOCKING_REQUEST_CANCELLED && event.approvalId === 'cmd_close'), true);
  assert.equal(events.some((event) => event.type === conversationEventTypes.RUN_ERROR && /transport closed/.test(event.message)), true);
  const diagnostics = adapter.detectCapabilities().diagnostics.metrics;
  assert.equal(diagnostics.transportCloseCount, 1);
  assert.equal(diagnostics.runErrorAfterTurnStartedCount, 1);
});

test('Codex app-server conversation adapter shuts down process on thread resume failure', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const transport = new EventEmitter();
  transport.sendRequest = async (method) => {
    if (method === 'initialize') return {};
    if (method === 'thread/resume') throw new Error('resume token expired');
    throw new Error(`unexpected request ${method}`);
  };
  transport.sendNotification = () => {};
  const shutdowns = [];
  const adapter = new CodexAppServerConversationAdapter({
    availability: { selectable: true, effectiveCapabilities: { resume: true } },
    lifecycle: {
      spawn: () => ({
        transport,
        shutdown: async () => {
          shutdowns.push(true);
        }
      })
    }
  });

  await assert.rejects(
    () => adapter.startConversation({
      conversationId: 'conv_app_resume_fail',
      workspacePath: 'D:\\Repo',
      sessionId: 'thread_missing',
      onEvent: () => {}
    }),
    /resume token expired/
  );
  assert.equal(shutdowns.length, 1);
});

test('Codex app-server conversation adapter times out pending approval fail closed', async () => {
  const { EventEmitter } = require('node:events');
  const { CodexAppServerConversationAdapter } = require('../daemon/src/codex-app-server-conversation-adapter');
  const transport = new EventEmitter();
  transport.results = [];
  transport.sendRequest = async (method) => {
    if (method === 'initialize') return {};
    if (method === 'thread/start') return { thread: { id: 'thread_app_timeout' } };
    if (method === 'turn/start') return { turn: { id: 'turn_app_timeout' } };
    throw new Error(`unexpected request ${method}`);
  };
  transport.sendNotification = () => {};
  transport.sendResult = (id, result) => transport.results.push({ id, result });
  transport.sendError = (id, error) => transport.results.push({ id, error });
  const adapter = new CodexAppServerConversationAdapter({
    availability: { selectable: true, effectiveCapabilities: { waitingApproval: true } },
    approvalTimeoutMs: 5,
    lifecycle: { spawn: () => ({ transport, shutdown: async () => {} }) }
  });
  const events = [];
  const handle = await adapter.startConversation({
    conversationId: 'conv_app_timeout',
    workspacePath: 'D:\\Repo',
    onEvent: (event) => events.push(event)
  });
  await handle.sendUserMessage('run tests');
  transport.emit('serverRequest', {
    id: 9,
    method: 'item/commandExecution/requestApproval',
    params: {
      itemId: 'cmd_timeout',
      command: 'npm test',
      availableDecisions: ['accept', 'cancel']
    }
  });
  await new Promise((resolve) => setTimeout(resolve, 25));

  assert.deepEqual(transport.results, [{ id: 9, result: { decision: 'cancel' } }]);
  assert.equal(events.some((event) => event.type === conversationEventTypes.APPROVAL_RESOLVED && event.approvalId === 'cmd_timeout' && event.timedOut === true), true);
  const metrics = adapter.detectCapabilities().diagnostics.metrics;
  assert.equal(metrics.approvalRequestedCount, 1);
  assert.equal(metrics.approvalTimeoutCount, 1);
  assert.equal(metrics.approvalRoundTripLatencyMs.length, 1);
});

test('conversation manager validates model update capability', async () => {
  const codex = {
    capabilities: { resume: true },
    async getModelCapability() {
      return {
        canSelectModel: true,
        selectedModel: 'gpt-5',
        models: [{ id: 'gpt-5', label: 'GPT-5' }]
      };
    },
    async startConversation() {
      throw new Error('not needed');
    }
  };
  const claude = {
    capabilities: { resume: true },
    async getModelCapability() {
      return {
        canSelectModel: false,
        selectedModel: null,
        models: []
      };
    },
    async startConversation() {
      throw new Error('not needed');
    }
  };
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([['codex', codex], ['claude', claude]])
  });

  const codexConversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex', model: 'gpt-5' }, device);
  await assert.rejects(
    () => manager.updateModel(codexConversation.id, { model: 'unknown-model' }, device),
    (error) => error.status === 422 && /not available/.test(error.message)
  );

  const claudeConversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);
  await assert.rejects(
    () => manager.updateModel(claudeConversation.id, { model: 'claude-opus' }, device),
    (error) => error.status === 422 && /does not support model selection/.test(error.message)
  );
  const cleared = await manager.updateModel(claudeConversation.id, { model: null }, device);
  assert.equal(cleared.model, null);
});

test('PATCH conversation model disposal failure detaches handle without changing model', async () => {
  const { manager, device, auditLog } = createConversationManagerForTest();
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex', model: 'gpt-5' }, device);
  const internal = manager.requireConversation(conversation.id, device);
  internal.cliSessionId = 'thread_1';
  internal.handle = {
    async dispose() {
      throw new Error('dispose failed');
    }
  };

  await assert.rejects(
    () => manager.updateModel(conversation.id, { model: 'gpt-5.5' }, device),
    /dispose failed/
  );

  assert.equal(internal.model, 'gpt-5');
  assert.equal(internal.handle, null);
  assert.equal(internal.cliSessionId, 'thread_1');
  assert.equal(auditLog.list().some((record) => record.type === 'conversation.model_handle_dispose_error'), true);
});

test('PATCH conversation model persistence failure restores in-memory model and skips event', async () => {
  const { manager, device } = createConversationManagerForTest();
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex', model: 'gpt-5' }, device);
  const internal = manager.requireConversation(conversation.id, device);
  internal.handle = { disposed: false, async dispose() { this.disposed = true; } };
  const originalPersist = manager.persistConversation.bind(manager);
  manager.persistConversation = (item) => {
    if (item.id === conversation.id && item.model === 'gpt-5.5') throw new Error('persist failed');
    originalPersist(item);
  };

  await assert.rejects(
    () => manager.updateModel(conversation.id, { model: 'gpt-5.5' }, device),
    /persist failed/
  );

  assert.equal(internal.model, 'gpt-5');
  assert.equal(internal.handle, null);
  assert.equal(manager.listEvents(conversation.id, 0, device).some((event) => event.type === conversationEventTypes.MODEL_CHANGED), false);
});

test('PATCH conversation model event append failure keeps persisted model', async () => {
  const { manager, device, auditLog } = createConversationManagerForTest();
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex', model: 'gpt-5' }, device);
  const originalAppend = manager.eventStore.append.bind(manager.eventStore);
  manager.eventStore.append = (conversationId, type, payload) => {
    if (type === conversationEventTypes.MODEL_CHANGED) throw new Error('event failed');
    return originalAppend(conversationId, type, payload);
  };

  const updated = await manager.updateModel(conversation.id, { model: 'gpt-5.5' }, device);

  assert.equal(updated.model, 'gpt-5.5');
  assert.equal(manager.requireConversation(conversation.id, device).model, 'gpt-5.5');
  assert.equal(auditLog.list().some((record) => record.type === 'conversation.model_change_event_error'), true);
});

test('conversation manager titles from first user message and keeps it stable', async () => {
  const sent = [];
  const adapter = {
    capabilities: { resume: true },
    async startConversation() {
      return {
        async sendUserMessage(message) {
          sent.push(message);
        },
        cancel() {},
        dispose() {}
      };
    }
  };
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([['codex', adapter]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);
  assert.equal(conversation.title, null);

  const first = await manager.sendMessage(conversation.id, { text: '  first line\nsecond line  ' }, device);
  const second = await manager.sendMessage(conversation.id, { text: 'newer message should not win' }, device);

  assert.deepEqual(sent, ['first line\nsecond line', 'newer message should not win']);
  assert.equal(first.title, 'first line second line');
  assert.equal(second.title, 'first line second line');
  assert.equal(manager.getConversation(conversation.id, device).title, 'first line second line');
});

test('conversation model update and send locks reject crossing operations', async () => {
  const { manager, device } = createConversationManagerForTest();
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);
  const internal = manager.requireConversation(conversation.id, device);

  internal.sendLock = true;
  await assert.rejects(
    () => manager.updateModel(conversation.id, { model: 'gpt-5' }, device),
    (error) => error.status === 409
  );
  internal.sendLock = false;

  internal.modelUpdateLock = true;
  await assert.rejects(
    () => manager.sendMessage(conversation.id, { text: 'hello' }, device),
    (error) => error.status === 409
  );
});

test('conversation manager preserves selected model after SQLite reload', async () => {
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const sqlite = new AppSqliteStore({ dbPath: tempConversationDbPath('conversation-model-reload-') });
  const workspaces = new WorkspaceRegistry({ store: sqlite });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set() };
  const workspace = workspaces.add({ name: 'Default', workspacePath: process.cwd() }, device);
  const firstAdapter = {
    capabilities: { resume: true },
    async startConversation() {
      throw new Error('first manager should not start adapter');
    }
  };
  const first = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore({ persistentStore: sqlite }),
    auditLog: new AuditLog(),
    adapters: new Map([['codex', firstAdapter]]),
    persistentStore: sqlite,
    now: () => new Date('2026-05-09T00:00:00.000Z')
  });
  const conversation = first.createConversation({ workspaceId: workspace.id, adapter: 'codex', model: 'gpt-5.5' }, device);
  const startCalls = [];
  const secondAdapter = {
    capabilities: { resume: true },
    async startConversation(input) {
      startCalls.push(input);
      return {
        sendUserMessage() {},
        cancel() {},
        dispose() {}
      };
    }
  };
  const second = new ConversationManager({
    workspaces,
    eventStore: new ConversationEventStore({ persistentStore: sqlite }),
    auditLog: new AuditLog(),
    adapters: new Map([['codex', secondAdapter]]),
    persistentStore: sqlite,
    now: () => new Date('2026-05-09T00:00:01.000Z')
  });

  assert.equal(second.getConversation(conversation.id, device).model, 'gpt-5.5');
  await second.sendMessage(conversation.id, { text: 'after reload' }, device);

  assert.equal(startCalls.length, 1);
  assert.equal(startCalls[0].model, 'gpt-5.5');
  sqlite.close();
});

test('conversation cancel preserves confirmed CLI session and resumes next message', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const handles = [];
  const adapter = {
    capabilities: { longLivedProcess: true, resume: true, partialOutput: true },
    startCalls: [],
    async startConversation(input) {
      adapter.startCalls.push({ sessionId: input.sessionId || null });
      const handle = {
        sent: [],
        cancelled: false,
        sendUserMessage(text) { this.sent.push(text); },
        cancel() { this.cancelled = true; },
        dispose() {}
      };
      handles.push(handle);
      adapter.onEvent = input.onEvent;
      return handle;
    }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-08T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    now: () => new Date('2026-05-08T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(conversation.id, { text: 'first' }, device);
  adapter.onEvent({ type: 'system.notice', sessionId: 'claude-session-1', text: 'started' });
  const cancelled = await manager.cancelConversation(conversation.id, device);
  await manager.sendMessage(conversation.id, { text: 'second' }, device);

  assert.equal(cancelled.status, 'cancelled');
  assert.equal(cancelled.cliSessionId, 'claude-session-1');
  assert.equal(cancelled.sessionBinding, 'confirmed');
  assert.equal(handles[0].cancelled, true);
  assert.deepEqual(adapter.startCalls.map((call) => call.sessionId), [null, 'claude-session-1']);
  assert.equal(eventStore.list(conversation.id, 0).some((event) => event.type === 'conversation.cancelled' && event.status === 'cancelled'), true);
});

test('conversation resend after cancel returns idle when resumed process completes without text', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  const handles = [];
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const adapter = {
    capabilities: { longLivedProcess: true, resume: true, partialOutput: true },
    startCalls: [],
    async startConversation(input) {
      adapter.startCalls.push({ sessionId: input.sessionId || null });
      const handle = {
        sent: [],
        cancelled: false,
        sendUserMessage(text) { this.sent.push(text); },
        cancel() { this.cancelled = true; },
        dispose() {}
      };
      handles.push(handle);
      adapter.onEvent = input.onEvent;
      return handle;
    }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-08T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    now: () => new Date('2026-05-08T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(conversation.id, { text: 'first' }, device);
  adapter.onEvent({ type: 'system.notice', sessionId: 'claude-session-1', text: 'started' });
  await manager.cancelConversation(conversation.id, device);
  await manager.sendMessage(conversation.id, { text: 'second' }, device);
  adapter.onEvent({ type: 'assistant.partial', text: 'partial response', sessionId: 'claude-session-1' });
  adapter.onEvent({ type: 'conversation.completed', sessionId: 'claude-session-1' });

  const summary = manager.getConversation(conversation.id, device);
  const events = eventStore.list(conversation.id, 0);

  assert.equal(summary.status, 'idle');
  assert.deepEqual(adapter.startCalls.map((call) => call.sessionId), [null, 'claude-session-1']);
  assert.equal(handles[0].cancelled, true);
  assert.equal(events.some((event) => event.type === 'conversation.status_changed' && event.status === 'idle'), true);

  await manager.sendMessage(conversation.id, { text: 'third' }, device);

  assert.deepEqual(adapter.startCalls.map((call) => call.sessionId), [null, 'claude-session-1', 'claude-session-1']);
  assert.deepEqual(handles.map((handle) => handle.sent), [['first'], ['second'], ['third']]);
});

test('conversation cancel before session id marks interrupted without clearing history', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const adapter = {
    capabilities: { longLivedProcess: true, resume: true },
    async startConversation() {
      return { sendUserMessage() {}, cancel() {}, dispose() {} };
    }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-08T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    now: () => new Date('2026-05-08T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(conversation.id, { text: 'first' }, device);
  const cancelled = await manager.cancelConversation(conversation.id, device);
  const events = eventStore.list(conversation.id, 0);

  assert.equal(cancelled.status, 'interrupted');
  assert.equal(cancelled.cliSessionId, null);
  assert.equal(cancelled.sessionBinding, 'unknown');
  assert.equal(events.some((event) => event.type === 'user.message' && event.text === 'first'), true);
});

test('conversation session drift keeps original CLI session id', async () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Default', workspacePath: process.cwd() });
  const adapter = {
    capabilities: { longLivedProcess: true, resume: true },
    async startConversation({ onEvent }) {
      adapter.onEvent = onEvent;
      return { sendUserMessage() {}, cancel() {}, dispose() {} };
    }
  };
  const eventStore = new ConversationEventStore({ now: () => new Date('2026-05-08T00:00:00.000Z') });
  const manager = new ConversationManager({
    workspaces,
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['claude', adapter]]),
    now: () => new Date('2026-05-08T00:00:00.000Z')
  });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await manager.sendMessage(conversation.id, { text: 'first' }, device);
  adapter.onEvent({ type: 'system.notice', sessionId: 'original-session', text: 'started' });
  adapter.onEvent({ type: 'system.notice', sessionId: 'drifted-session', text: 'started elsewhere' });

  const summary = manager.getConversation(conversation.id, device);
  const warning = eventStore.list(conversation.id, 0).find((event) => event.type === 'protocol.warning' && event.warning === 'session_id_drift');
  assert.equal(summary.cliSessionId, 'original-session');
  assert.equal(summary.sessionBinding, 'drifted');
  assert.equal(warning.expectedSessionId, 'original-session');
  assert.equal(warning.receivedSessionId, 'drifted-session');
});

test('conversation manager restores persisted live conversation as interrupted', () => {
  const { ConversationManager } = require('../daemon/src/conversation-manager');
  const { ConversationEventStore } = require('../daemon/src/conversation-event-store');
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
  const device = { id: 'device_1', allowedWorkspaceIds: new Set(['default']) };
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

test('workspace object authorization is enforced', () => {
  const registry = new WorkspaceRegistry();
  registry.add({ id: 'w1', name: 'one', workspacePath: '.' });
  const device = { id: 'd1', allowedWorkspaceIds: new Set() };
  assert.throws(() => registry.getAuthorized('w1', device), /not authorized/);
  device.allowedWorkspaceIds.add('w1');
  assert.equal(registry.getAuthorized('w1', device).id, 'w1');
});

test('workspace registry lists database-backed workspaces for authorized device', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-registry-db-'));
  const store = new AppSqliteStore({ dbPath: path.join(dir, 'app.sqlite') });
  const registry = new WorkspaceRegistry({ store });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set() };
  const workspace = registry.add({ name: 'Saved', workspacePath: path.join(dir, 'saved') }, device);

  assert.equal(device.allowedWorkspaceIds.has(workspace.id), true);
  assert.equal(registry.listForDevice(device).some((item) => item.id === workspace.id), true);
  assert.equal(registry.getAuthorized(workspace.id, device).path, workspace.path);
  store.close();
});

test('workspace registry persists created workspaces for the same authorized device', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const { WorkspaceRegistry } = require('../daemon/src/workspace');

  const appDbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-registry-persist-')), 'app.sqlite');
  const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-registry-folder-'));
  const device = { id: 'device_1', allowedWorkspaceIds: new Set() };

  const firstStore = new AppSqliteStore({ dbPath: appDbPath });
  const firstRegistry = new WorkspaceRegistry({ store: firstStore });
  const created = firstRegistry.add({ workspacePath, name: 'Persisted' }, device);
  firstStore.close();

  const secondStore = new AppSqliteStore({ dbPath: appDbPath });
  const secondRegistry = new WorkspaceRegistry({ store: secondStore });
  assert.equal(secondRegistry.listForDevice(device).some((workspace) => workspace.id === created.id), true);
  assert.deepEqual(secondRegistry.listForDevice({ id: 'device_2', allowedWorkspaceIds: new Set() }), []);
  secondStore.close();
});

test('workspace registry deduplicates visible workspaces by path for a device', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const { WorkspaceRegistry } = require('../daemon/src/workspace');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-registry-dedupe-'));
  const store = new AppSqliteStore({ dbPath: path.join(dir, 'app.sqlite') });
  const registry = new WorkspaceRegistry({ store });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set() };
  const workspacePath = path.join(dir, 'same');

  registry.add({ id: 'workspace_a', workspacePath, name: 'First' }, device);
  registry.add({ id: 'workspace_b', workspacePath, name: 'Second' }, device);

  const listed = registry.listForDevice(device);
  assert.equal(listed.length, 1);
  assert.equal(listed[0].path, path.resolve(workspacePath));
  store.close();
});

test('event replay returns ordered events after sequence', () => {
  const store = new EventStore();
  store.append('run1', 'run.started');
  store.append('run1', 'assistant.delta', { text: 'a' });
  store.append('run1', 'run.completed');
  assert.deepEqual(store.list('run1', 1).map((event) => event.seq), [2, 3]);
});

test('audit redacts token-like fields', () => {
  const audit = new AuditLog();
  const record = audit.record('pair', { token: 'secret', nested: { apiKey: 'abc', ok: true } });
  assert.equal(record.token, '[REDACTED]');
  assert.equal(record.nested.apiKey, '[REDACTED]');
  assert.equal(redact({ password: 'x' }).password, '[REDACTED]');
});

test('Claude capability detection marks adapter unavailable on missing CLI', () => {
  const adapter = new ClaudeAdapter({
    command: 'claude',
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: () => ({ status: 1, stdout: '', stderr: 'not found' })
  });
  const capability = adapter.detectCapabilities();
  assert.equal(capability.available, false);
  assert.equal(capability.capabilities.streamJson, false);
});

test('Claude capability detection requires stream json flags', () => {
  const adapter = new ClaudeAdapter({
    command: 'claude',
    spawnSyncFn: (_cmd, args) => args.includes('--version')
      ? { status: 0, stdout: '1.2.3', stderr: '' }
      : { status: 0, stdout: '-p --bare --output-format stream-json --verbose --include-partial-messages --resume', stderr: '' }
  });
  const capability = adapter.detectCapabilities();
  assert.equal(capability.available, true);
  assert.equal(capability.capabilities.bare, true);
  assert.equal(capability.capabilities.streamJson, true);
});

test('Claude capability detection records permission modes from help text', () => {
  const adapter = new ClaudeAdapter({
    command: 'claude',
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '2.1.119', stderr: '' };
      if (args.includes('--help')) {
        return { status: 0, stdout: '-p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-mode MODE', stderr: '' };
      }
      return { status: 0, stdout: '', stderr: '' };
    }
  });
  const capability = adapter.detectCapabilities();
  assert.deepEqual(capability.capabilities.permissionModes, ['default', 'auto']);
});

test('Claude detection exposes model flag support from help text', () => {
  const detection = detectClaudeCodeInstallation({
    command: 'claude',
    invocation: { command: 'claude', argsPrefix: [] },
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '2.1.119', stderr: '' };
      if (args.includes('--help')) return { status: 0, stdout: '-p --model <MODEL> --output-format stream-json', stderr: '' };
      return { status: 1, stdout: '', stderr: 'unexpected probe' };
    }
  });

  assert.equal(detection.installed, true);
  assert.equal(detection.supportsModelFlag, true);
});

test('Claude capability detection probes help once and reports missing model flag', () => {
  let helpCalls = 0;
  const adapter = new ClaudeAdapter({
    command: 'claude',
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '2.1.119', stderr: '' };
      if (args.includes('--help')) {
        helpCalls++;
        return { status: 0, stdout: '-p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume', stderr: '' };
      }
      return { status: 1, stdout: '', stderr: 'unexpected probe' };
    }
  });

  const capability = adapter.detectCapabilities();

  assert.equal(helpCalls, 1);
  assert.equal(capability.capabilities.supportsModelFlag, false);
  assert.equal(capability.canSelectModel, false);
});

test('Claude permission mode resolver falls back from unsupported auto to default', () => {
  const capability = { capabilities: { permissionModes: ['default', 'plan'] } };
  assert.equal(resolvePermissionMode('auto', capability).effectivePermissionMode, 'default');
  assert.equal(resolvePermissionMode('plan', capability).effectivePermissionMode, 'plan');
});

test('Claude launch args use stream-json permission protocol without prompt tool', () => {
  const launch = buildClaudeArgs({ permissionMode: 'default', prompt: 'hello' }, {
    capabilities: { permissionModes: ['default'], inputFormat: true }
  });
  assert.equal(launch.args.includes('--input-format'), true);
  assert.equal(launch.args.includes('stream-json'), true);
  assert.equal(launch.args.includes('--permission-prompt-tool'), false);
  assert.deepEqual(launch.args.slice(launch.args.indexOf('--permission-mode'), launch.args.indexOf('--permission-mode') + 2), ['--permission-mode', 'default']);
});

test('Claude launch args keep tools restrictions distinct from pre-approvals', () => {
  const launch = buildClaudeArgs({
    permissionMode: 'auto',
    requestedToolPolicy: {
      tools: ['Read', 'Glob'],
      allowedTools: ['Read'],
      disallowedTools: ['Bash']
    }
  }, { capabilities: { permissionModes: ['default', 'auto'] } });
  assert.deepEqual(launch.args.slice(launch.args.indexOf('--tools'), launch.args.indexOf('--tools') + 2), ['--tools', 'Read,Glob']);
  assert.deepEqual(launch.args.slice(launch.args.indexOf('--allowedTools'), launch.args.indexOf('--allowedTools') + 2), ['--allowedTools', 'Read']);
  assert.deepEqual(launch.args.slice(launch.args.indexOf('--disallowedTools'), launch.args.indexOf('--disallowedTools') + 2), ['--disallowedTools', 'Bash']);
});

test('Claude capability detection uses SDK permission mode contract instead of parsing help choices', () => {
  let probeCalls = 0;
  const adapter = new ClaudeAdapter({
    command: 'claude',
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '2.1.159', stderr: '' };
      if (args.includes('--help')) {
        return { status: 0, stdout: '-p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-mode MODE', stderr: '' };
      }
      if (args.includes('--permission-mode')) {
        probeCalls++;
        return { status: 1, stdout: '', stderr: 'unexpected permission mode probe' };
      }
      return { status: 1, stdout: '', stderr: 'unexpected probe' };
    }
  });

  const capability = adapter.detectCapabilities();

  assert.equal(probeCalls, 0);
  assert.deepEqual(capability.capabilities.permissionModes, ['default', 'auto']);
});

test('Claude capability detection does not probe permission modes when help omits the flag', () => {
  let probeCalls = 0;
  const adapter = new ClaudeAdapter({
    command: 'claude',
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '2.1.159', stderr: '' };
      if (args.includes('--help')) {
        return { status: 0, stdout: '-p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume', stderr: '' };
      }
      if (args.includes('--permission-mode')) {
        probeCalls++;
        return { status: 1, stdout: '', stderr: 'unexpected permission mode probe' };
      }
      return { status: 1, stdout: '', stderr: 'unexpected probe' };
    }
  });

  const capability = adapter.detectCapabilities();

  assert.equal(probeCalls, 0);
  assert.deepEqual(capability.capabilities.permissionModes, ['default', 'auto']);
});

test('Claude events map to unified event types', () => {
  assert.equal(mapClaudeEvent({ type: 'assistant', text: 'hi' }).type, eventTypes.ASSISTANT_DELTA);
  assert.equal(mapClaudeEvent({ type: 'tool_start', name: 'bash' }).type, eventTypes.TOOL_STARTED);
  assert.equal(mapClaudeEvent({ type: 'tool_result', text: 'ok' }).type, eventTypes.TOOL_OUTPUT);
  assert.equal(mapClaudeEvent({ type: 'stream_event', event: { type: 'assistant', text: 'wrapped' } }).text, 'wrapped');
  assert.equal(mapClaudeEvent({ type: 'system', subtype: 'api_retry', attempt: 1, max_retries: 3, retry_delay_ms: 500 }).text.includes('retry 1/3'), true);
  assert.equal(mapClaudeEvent({ type: 'system', subtype: 'status', status: 'thinking' }).text, 'Claude thinking');
  assert.equal(mapClaudeEvent({ type: 'system', subtype: 'session_start', session_id: 's1' }).sessionId, 's1');
  assert.equal(mapClaudeEvent({ type: 'unknown', text: 'raw' }).type, eventTypes.RAW_OUTPUT);
});

test('Claude startRun waits for initialize response before prompt', async () => {
  const writes = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    writable: true,
    write(data) { writes.push(data); },
    end() { this.destroyed = true; }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeAdapter({ spawnSyncFn: fakeSpawnSync, spawnFn: () => child });

  adapter.startRun({ prompt: 'handshake prompt', workspacePath: 'D:\\AiProject\\vibe-coding', permissionMode: 'default', onEvent: () => {} });
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(writes.some((line) => line.includes('"subtype":"initialize"')), true);
  assert.equal(writes.some((line) => line.includes('handshake prompt')), false);
  const init = JSON.parse(writes.find((line) => line.includes('"subtype":"initialize"')));
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: init.request_id, subtype: 'success', response: {} } })}\n`);
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(writes.some((line) => line.includes('handshake prompt')), true);
});

test('startRun emits actionable unavailable error before spawning', () => {
  const adapter = new ClaudeAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: () => ({ status: 1, stdout: '', stderr: 'missing' }),
    spawnFn: () => new EventEmitter()
  });
  assert.throws(() => adapter.startRun({ prompt: 'x', workspacePath: '.', onEvent: () => {} }), /Unable to inspect Claude CLI/);
});

test('Claude adapter treats result as terminal and suppresses late noise', async () => {
  const events = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) {
      if (data.includes('"initialize"')) {
        const req = JSON.parse(data.trim());
        setImmediate(() => {
          child.stdout.emit('data', Buffer.from(`${JSON.stringify({
            type: 'control_response',
            response: { request_id: req.request_id, subtype: 'success', response: {} }
          })}\n`));
        });
        return;
      }
      if (!data.includes('"late noise smoke"')) return;
      setImmediate(() => {
        child.stdout.emit('data', Buffer.from(`${JSON.stringify({
          type: 'result',
          subtype: 'success',
          is_error: false,
          result: 'done',
          session_id: 'claude-session-late-noise'
        })}\n`));
        child.stdout.emit('data', Buffer.from(`${JSON.stringify({
          type: 'system',
          subtype: 'status',
          status: 'requesting',
          session_id: 'claude-session-late-noise'
        })}\n`));
        child.emit('exit', 0, null);
      });
    },
    end() { this.destroyed = true; }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeAdapter({ spawnSyncFn: fakeSpawnSync, spawnFn: () => child });

  adapter.startRun({ prompt: 'late noise smoke', workspacePath: '.', permissionMode: 'auto', onEvent: (event) => events.push(event) });
  await new Promise((resolve) => setTimeout(resolve, 50));

  assert.equal(events.filter((event) => event.type === eventTypes.RUN_COMPLETED).length, 1);
  assert.equal(events.some((event) => event.text === 'Claude requesting'), false);
  assert.equal(events.at(-1).type, eventTypes.RUN_COMPLETED);
});

test('Claude adapter filters escaped protocol payloads from assistant text', () => {
  const event = mapClaudeEvent({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [{
        type: 'text',
        text: '\\n"Fix this bug" → debugging first.\\n\\n## Skill Types\\n\\nRigid (TDD, debugging): Follow exactly.'
      }]
    },
    parent_tool_use_id: null,
    session_id: 'leaked-session'
  });

  assert.equal(event.type, eventTypes.ASSISTANT_DELTA);
  assert.equal(event.text, '');
});

test('Claude adapter starts CLI directly in workspace cwd', async () => {
  let spawnCommand = null;
  let spawnArgs = null;
  let spawnOptions = null;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {}, end() { this.destroyed = true; } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const workspacePath = 'D:\\AiProject\\vibe-coding';
  const adapter = new ClaudeAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeSpawnSync,
    spawnFn: (cmd, args, options) => {
      spawnCommand = cmd;
      spawnArgs = args;
      spawnOptions = options;
      return child;
    }
  });

  adapter.startRun({ prompt: 'cwd smoke', workspacePath, permissionMode: 'auto', onEvent: () => {} });
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(spawnCommand, 'claude');
  assert.equal(spawnArgs.includes('--input-format'), true);
  assert.equal(spawnArgs.includes('stream-json'), true);
  assert.equal(spawnArgs.join(' ').includes('cd /d'), false);
  assert.equal(spawnOptions.cwd, workspacePath);
  assert.equal(spawnOptions.env.PWD, workspacePath);
});

test('Claude conversation adapter starts long-lived CLI directly in workspace cwd', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  let spawnCommand = null;
  let spawnArgs = null;
  let spawnOptions = null;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {}, end() { this.destroyed = true; } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const workspacePath = 'D:\\AiProject\\vibe-coding';
  const adapter = new ClaudeConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeSpawnSync,
    spawnFn: (cmd, args, options) => {
      spawnCommand = cmd;
      spawnArgs = args;
      spawnOptions = options;
      return child;
    }
  });

  await adapter.startConversation({ conversationId: 'conv_cwd', workspacePath, onEvent: () => {} });

  assert.equal(spawnCommand, 'claude');
  assert.equal(spawnArgs.includes('--input-format'), true);
  assert.equal(spawnArgs.includes('stream-json'), true);
  assert.deepEqual(spawnArgs.slice(spawnArgs.indexOf('--permission-prompt-tool'), spawnArgs.indexOf('--permission-prompt-tool') + 2), ['--permission-prompt-tool', 'stdio']);
  assert.equal(spawnArgs.join(' ').includes('cd /d'), false);
  assert.equal(spawnOptions.cwd, workspacePath);
  assert.equal(spawnOptions.env.PWD, workspacePath);
  assert.equal(spawnOptions.env.CLAUDE_CODE_ENTRYPOINT, 'sdk-js');
  assert.equal(spawnOptions.env.CLAUDE_AGENT_SDK_VERSION, require('../package.json').version);
  assert.equal(Object.prototype.hasOwnProperty.call(spawnOptions.env, 'CLAUDECODE'), false);
});

test('Claude conversation adapter maps SDK-style Claude options to CLI arguments', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  let spawnArgs = null;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: (_cmd, args) => {
      spawnArgs = args;
      return child;
    }
  });

  await adapter.startConversation({
    conversationId: 'conv_claude_options',
    workspacePath: '.',
    permissionMode: 'default',
    model: 'claude-sonnet',
    requestedToolPolicy: { tools: ['Read'], allowedTools: ['Read'], disallowedTools: ['Bash'] },
    claudeOptions: {
      tools: ['Task', 'Read'],
      allowedTools: ['Read', 'Grep'],
      disallowedTools: ['Bash'],
      systemPrompt: 'System text',
      appendSystemPrompt: 'Append text',
      maxTurns: 3,
      maxBudgetUsd: 1.25,
      taskBudgetTotal: 7,
      fallbackModel: 'claude-haiku',
      betas: ['beta-a'],
      settings: '{"permissions":{}}',
      addDirs: ['D:\\Extra'],
      mcpConfig: { local: { command: 'node', args: ['server.js'] } },
      forkSession: true,
      settingSources: ['user', 'project'],
      skills: ['code-review'],
      sandbox: { enabled: true },
      plugins: [{ type: 'local', path: 'D:\\Plugin' }],
      extraArgs: { color: 'never', debug: null },
      thinking: { type: 'enabled', budgetTokens: 1024 },
      effort: 'high',
      outputFormat: { type: 'json_schema', schema: { type: 'object' } },
      env: { SHOULD_NOT_PASS: '1' }
    },
    onEvent: () => {}
  });

  const joined = spawnArgs.join('\n');
  assert.match(joined, /--tools\nTask,Read/);
  assert.match(joined, /--allowedTools\nRead,Grep/);
  assert.match(joined, /--disallowedTools\nBash/);
  assert.match(joined, /--system-prompt\nSystem text/);
  assert.match(joined, /--append-system-prompt\nAppend text/);
  assert.match(joined, /--max-turns\n3/);
  assert.match(joined, /--max-budget-usd\n1.25/);
  assert.match(joined, /--task-budget\n7/);
  assert.match(joined, /--fallback-model\nclaude-haiku/);
  assert.match(joined, /--betas\nbeta-a/);
  assert.match(joined, /--settings\n\{"permissions":\{\}\}/);
  assert.match(joined, /--add-dir\nD:\\Extra/);
  assert.match(joined, /--mcp-config\n\{"mcpServers":/);
  assert.equal(spawnArgs.includes('--fork-session'), true);
  assert.equal(spawnArgs.includes('--setting-sources=user,project'), true);
  assert.match(joined, /--plugin-dir\nD:\\Plugin/);
  assert.match(joined, /--color\nnever/);
  assert.equal(spawnArgs.includes('--debug'), true);
  assert.match(joined, /--max-thinking-tokens\n1024/);
  assert.match(joined, /--effort\nhigh/);
  assert.match(joined, /--json-schema\n\{"type":"object"\}/);
  assert.equal(joined.includes('SHOULD_NOT_PASS'), false);
});

test('Claude conversation adapter enables stdio permission prompt tool in auto mode', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  let spawnArgs = null;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {}, end() { this.destroyed = true; } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeSpawnSync,
    spawnFn: (_cmd, args) => {
      spawnArgs = args;
      return child;
    }
  });

  await adapter.startConversation({ conversationId: 'conv_auto_prompt_tool', workspacePath: '.', permissionMode: 'auto', onEvent: () => {} });

  assert.deepEqual(spawnArgs.slice(spawnArgs.indexOf('--permission-prompt-tool'), spawnArgs.indexOf('--permission-prompt-tool') + 2), ['--permission-prompt-tool', 'stdio']);
  assert.deepEqual(spawnArgs.slice(spawnArgs.indexOf('--permission-mode'), spawnArgs.indexOf('--permission-mode') + 2), ['--permission-mode', 'auto']);
  assert.equal(spawnArgs.includes('--allowedTools'), true);
});

test('Claude conversation adapter uses SDK initialize timeout defaults', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const originalSetTimeout = global.setTimeout;
  const originalTimeout = process.env.CLAUDE_CODE_STREAM_CLOSE_TIMEOUT;
  const delays = [];
  global.setTimeout = (fn, delay) => {
    delays.push(delay);
    return { fn, delay };
  };
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  try {
    delete process.env.CLAUDE_CODE_STREAM_CLOSE_TIMEOUT;
    await adapter.startConversation({ conversationId: 'conv_init_timeout_default', workspacePath: '.', onEvent: () => {} });
    process.env.CLAUDE_CODE_STREAM_CLOSE_TIMEOUT = '1000';
    await adapter.startConversation({ conversationId: 'conv_init_timeout_min', workspacePath: '.', onEvent: () => {} });
    process.env.CLAUDE_CODE_STREAM_CLOSE_TIMEOUT = '75000';
    await adapter.startConversation({ conversationId: 'conv_init_timeout_env', workspacePath: '.', onEvent: () => {} });
  } finally {
    if (originalTimeout == null) delete process.env.CLAUDE_CODE_STREAM_CLOSE_TIMEOUT;
    else process.env.CLAUDE_CODE_STREAM_CLOSE_TIMEOUT = originalTimeout;
    global.setTimeout = originalSetTimeout;
  }

  assert.deepEqual(delays, [60000, 60000, 75000]);
});

test('Claude conversation adapter adds model flag only when supported', async () => {
  const spawnArgsBySupport = [];
  for (const supportsModel of [true, false]) {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.stdin = { destroyed: false, write() {}, end() { this.destroyed = true; } };
    child.kill = () => child.emit('exit', null, 'SIGTERM');
    const adapter = new ClaudeConversationAdapter({
      cliResolverOptions: { platform: 'linux' },
      spawnSyncFn: (_cmd, args) => {
        if (args.includes('--version')) return { status: 0, stdout: '2.1.119', stderr: '' };
        if (args.includes('--help')) {
          return {
            status: 0,
            stdout: supportsModel ? '-p --model <MODEL> --output-format stream-json' : '-p --output-format stream-json',
            stderr: ''
          };
        }
        return { status: 0, stdout: '', stderr: '' };
      },
      spawnFn: (_cmd, args) => {
        spawnArgsBySupport.push({ supportsModel, args });
        return child;
      }
    });

    await adapter.startConversation({ conversationId: `conv_claude_model_${supportsModel}`, workspacePath: '.', model: 'claude-sonnet-4.5', onEvent: () => {} });
  }

  const supportedArgs = spawnArgsBySupport.find((call) => call.supportsModel).args;
  const unsupportedArgs = spawnArgsBySupport.find((call) => !call.supportsModel).args;
  assert.deepEqual(supportedArgs.slice(supportedArgs.indexOf('--model'), supportedArgs.indexOf('--model') + 2), ['--model', 'claude-sonnet-4.5']);
  assert.equal(unsupportedArgs.includes('--model'), false);
});

test('Claude conversation adapter waits for initialize response before sending messages', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const writes = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write(data) { writes.push(data.trim()); }, end() { this.destroyed = true; } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeConversationAdapter({
    spawnSyncFn: fakeSpawnSync,
    spawnFn: () => child
  });

  const handle = await adapter.startConversation({ conversationId: 'conv_init_gate', workspacePath: '.', onEvent: () => {} });
  const sendPromise = handle.sendUserMessage('after init');
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(writes.some((line) => line.includes('"subtype":"initialize"')), true);
  assert.equal(writes.some((line) => line.includes('after init')), false);
  const init = JSON.parse(writes.find((line) => line.includes('"subtype":"initialize"')));
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: init.request_id, subtype: 'success', response: {} } })}\n`);
  await sendPromise;

  assert.equal(writes.some((line) => line.includes('after init')), true);
});

test('Claude attachment dispatch builds stream-json content blocks', () => {
  const { buildClaudeUserContent } = require('../daemon/src/claude-conversation-adapter');

  const content = buildClaudeUserContent({
    text: 'Inspect this.',
    attachments: [
      { kind: 'image', handling: 'native', bytes: Buffer.from('abc'), mimeType: 'image/png', name: 'a.png', sizeBytes: 3 },
      { kind: 'textDocument', handling: 'text_extract', text: 'alpha', mimeType: 'text/plain', name: 'a.txt' }
    ]
  });

  assert.deepEqual(content[0], { type: 'text', text: 'Inspect this.' });
  assert.equal(content[1].type, 'image');
  assert.equal(content[1].source.type, 'base64');
  assert.equal(content[1].source.media_type, 'image/png');
  assert.equal(content[1].source.data, Buffer.from('abc').toString('base64'));
  assert.equal(content[2].type, 'text');
  assert.match(content[2].text, /<attachment name="a.txt" mime="text\/plain">/);
  assert.match(content[2].text, /alpha/);
});

test('Claude attachment dispatch rejects images over 5MB before base64 conversion', () => {
  const { buildClaudeUserContent } = require('../daemon/src/claude-conversation-adapter');

  assert.throws(
    () => buildClaudeUserContent({
      text: 'Inspect this.',
      attachments: [
        { kind: 'image', handling: 'native', bytes: Buffer.alloc(0), mimeType: 'image/png', name: 'large.png', sizeBytes: (5 * 1024 * 1024) + 1 }
      ]
    }),
    (error) => error.status === 413 && error.code === 'ATTACHMENT_LIMIT_EXCEEDED'
  );
});

test('Claude conversation adapter emits completion when long-lived process exits cleanly', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const events = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {}, end() { this.destroyed = true; } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeConversationAdapter({
    spawnSyncFn: fakeSpawnSync,
    spawnFn: () => child
  });

  await adapter.startConversation({
    conversationId: 'conv_exit_complete',
    workspacePath: '.',
    onEvent: (event) => events.push(event)
  });
  child.stdout.emit('data', `${JSON.stringify({ type: 'assistant', text: 'partial only', session_id: 's1' })}\n`);
  child.emit('exit', 0, null);
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(events.some((event) => event.type === 'assistant.partial' && event.text === 'partial only'), true);
  assert.equal(events.some((event) => event.type === 'conversation.completed'), true);
});

test('Claude conversation adapter emits file change notice after successful Edit tool', async () => {
  const { spawnSync } = require('node:child_process');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-file-change-diff-'));
  const gitAvailable = spawnSync('git', ['--version'], { encoding: 'utf8' });
  if (gitAvailable.status !== 0) return;
  const runGit = (args) => spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  if (runGit(['init']).status !== 0) return;
  fs.writeFileSync(path.join(root, 'example.txt'), 'old line\n', 'utf8');
  if (runGit(['add', 'example.txt']).status !== 0) return;
  if (runGit(['-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', 'init']).status !== 0) return;
  fs.writeFileSync(path.join(root, 'example.txt'), 'new line\n', 'utf8');

  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: (command, args, options) => {
      if (command === 'git') return spawnSync(command, args, options);
      return { status: 0, stdout: '2.1.119', stderr: '' };
    },
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_claude_file_change', workspacePath: root, onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_edit',
    name: 'Edit',
    input: { file_path: path.join(root, 'example.txt'), old_string: 'old line', new_string: 'new line' }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_edit',
    content: 'Updated example.txt',
    is_error: false
  })}\n`);

  const notice = events.find((event) => event.noticeKind === 'codex_file_change');
  assert.equal(notice.type, 'system.notice');
  assert.equal(notice.visible, true);
  assert.deepEqual(notice.changes.map((change) => change.path), ['example.txt']);
  assert.equal(notice.changes[0].kind, 'update');
  assert.match(notice.changes[0].diff, /@@/);
  assert.match(notice.changes[0].diff, /-old line/);
  assert.match(notice.changes[0].diff, /\+new line/);
});

test('Claude conversation adapter previews Edit input when git diff is empty', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-file-change-edit-preview-'));
  fs.mkdirSync(path.join(root, 'docs'), { recursive: true });
  fs.writeFileSync(path.join(root, 'docs', 'note.md'), '# New title\nbody\n', 'utf8');

  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: (command) => {
      if (command === 'git') return { status: 0, stdout: '', stderr: '' };
      return { status: 0, stdout: '2.1.119', stderr: '' };
    },
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_claude_edit_preview', workspacePath: root, onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_edit_preview',
    name: 'Edit',
    input: {
      file_path: path.join(root, 'docs', 'note.md'),
      old_string: '# Old title\nbody\n',
      new_string: '# New title\nbody\n'
    }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_edit_preview',
    content: 'Updated docs/note.md',
    is_error: false
  })}\n`);

  const notice = events.find((event) => event.noticeKind === 'codex_file_change');
  assert.equal(notice.type, 'system.notice');
  assert.deepEqual(notice.changes.map((change) => change.path), ['docs/note.md']);
  assert.match(notice.changes[0].diff, /@@ edit preview @@/);
  assert.match(notice.changes[0].diff, /-# Old title/);
  assert.match(notice.changes[0].diff, /\+# New title/);
});

test('Claude conversation adapter suppresses file change notice for failed Edit tool', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_claude_file_change_failed', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_edit_fail',
    name: 'Edit',
    input: { file_path: 'missing.txt', old_string: 'old', new_string: 'new' }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_edit_fail',
    content: 'File not found',
    is_error: true
  })}\n`);

  assert.equal(events.some((event) => event.noticeKind === 'codex_file_change'), false);
});

test('Claude adapter rejects missing workspace before spawning', () => {
  const adapter = new ClaudeAdapter({
    spawnSyncFn: fakeSpawnSync,
    spawnFn: () => {
      throw new Error('spawn should not be called');
    }
  });

  assert.throws(
    () => adapter.startRun({ prompt: 'x', workspacePath: '', onEvent: () => {} }),
    /workspacePath is required/
  );
});

test('Claude adapter passes metacharacter workspace as cwd without shell script', () => {
  let spawnCommand = null;
  let spawnArgs = null;
  let spawnOptions = null;
  const adapter = new ClaudeAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeSpawnSync,
    spawnFn: (cmd, args, options) => {
      spawnCommand = cmd;
      spawnArgs = args;
      spawnOptions = options;
      return fakeSpawn();
    }
  });

  adapter.startRun({ prompt: 'x', workspacePath: 'D:\\A&B(C)', permissionMode: 'auto', onEvent: () => {} });
  assert.equal(spawnCommand, 'claude');
  assert.equal(spawnArgs.join(' ').includes('cd /d'), false);
  assert.equal(spawnOptions.cwd, 'D:\\A&B(C)');
});

test('Claude adapter does not force an empty system prompt', () => {
  const adapter = new ClaudeAdapter({
    spawnSyncFn: fakeSpawnSync,
    spawnFn: (_cmd, args) => {
      assert.equal(args.join(' ').includes('--system-prompt'), false);
      return fakeSpawn();
    }
  });

  adapter.startRun({ prompt: 'x', workspacePath: 'D:\\AiProject\\vibe-coding', permissionMode: 'auto', onEvent: () => {} });
});

test('Claude default run closes stdin after result', async () => {
  let ended = false;
  let initRequestId = null;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    writable: true,
    write(data) {
      const parsed = JSON.parse(data);
      if (parsed.type === 'control_request') initRequestId = parsed.request_id;
    },
    end() { ended = true; }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeAdapter({ spawnSyncFn: fakeSpawnSync, spawnFn: () => child });

  adapter.startRun({ prompt: 'x', workspacePath: 'D:\\AiProject\\vibe-coding', permissionMode: 'default', onEvent: () => {} });
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: initRequestId } })}\n`);
  assert.equal(ended, false);
  child.stdout.emit('data', `${JSON.stringify({ type: 'result', subtype: 'success', result: 'ok', session_id: 's1' })}\n`);

  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(ended, true);
});

test('Claude text filtering keeps normal apostrophes', () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, writable: true, write() {}, end() {} };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const events = [];
  const adapter = new ClaudeAdapter({ spawnSyncFn: fakeSpawnSync, spawnFn: () => child });

  adapter.startRun({ prompt: 'x', workspacePath: 'D:\\AiProject\\vibe-coding', permissionMode: 'auto', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: { role: 'assistant', content: [{ type: 'text', text: "it's not a protocol type message" }] }
  })}\n`);

  assert.equal(events.some((event) => event.text === "it's not a protocol type message"), true);
});

test('HTTP new run ignores sessionId and starts a fresh Claude CLI', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath() });
  app.adapterRegistry.get('claude').spawnSyncFn = fakeSpawnSync;
  let firstArgs = null;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {}, end() { this.destroyed = true; } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  app.adapterRegistry.get('claude').spawnFn = (_cmd, args) => {
    firstArgs = args;
    return child;
  };
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, paired.body.token);
    const created = await request(port, 'POST', '/api/runs', {
      tool: 'claude',
      workspaceId: (await request(port, 'GET', '/api/workspaces', null, paired.body.token)).body.workspaces[0].id,
      prompt: 'fresh run',
      sessionId: 'must-not-resume-this-session'
    }, paired.body.token);

    assert.equal(created.status, 201);
    assert.equal(created.body.cliSessionId, null);
    const launchScript = firstArgs.join(' ');
    assert.equal(launchScript.includes('--resume'), false);
    assert.equal(launchScript.includes('--continue'), false);
    assert.equal(launchScript.includes('must-not-resume-this-session'), false);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('follow-up resumes only the captured Claude session', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath() });
  app.adapterRegistry.get('claude').spawnSyncFn = fakeSpawnSync;
  const spawnArgs = [];
  app.adapterRegistry.get('claude').spawnFn = (_cmd, args) => {
    spawnArgs.push(args);
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.stdin = {
      destroyed: false,
      write(data) {
        if (data.includes('"initialize"')) {
          const req = JSON.parse(data.trim());
          setImmediate(() => {
            child.stdout.emit('data', Buffer.from(`${JSON.stringify({
              type: 'control_response',
              response: { request_id: req.request_id, subtype: 'success', response: {} }
            })}\n`));
          });
          return;
        }
        if (!data.includes('"type":"user"')) return;
        setImmediate(() => {
          child.stdout.emit('data', Buffer.from(`${JSON.stringify({
            type: 'result',
            subtype: 'success',
            is_error: false,
            result: 'ok',
            session_id: 'captured-session-1'
          })}\n`));
        });
      },
      end() { this.destroyed = true; }
    };
    child.kill = () => child.emit('exit', null, 'SIGTERM');
    return child;
  };
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, paired.body.token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, paired.body.token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId, prompt: 'first' }, paired.body.token);
    await new Promise((resolve) => setTimeout(resolve, 100));
    const followed = await request(port, 'POST', `/api/runs/${created.body.id}/input`, { prompt: 'second' }, paired.body.token);

    assert.equal(followed.status, 200);
    const firstLaunch = spawnArgs[0].join(' ');
    const secondLaunch = spawnArgs[1].join(' ');
    assert.equal(firstLaunch.includes('--resume'), false);
    assert.equal(firstLaunch.includes('--continue'), false);
    assert.equal(secondLaunch.includes('--resume'), true);
    assert.equal(secondLaunch.includes('captured-session-1'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('Claude adapter turns AskUserQuestion into a user-facing question', async () => {
  const events = [];
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) {
      stdinLines.push(data.trim());
      if (data.includes('"initialize"')) {
        const req = JSON.parse(data.trim());
        setImmediate(() => {
          child.stdout.emit('data', Buffer.from(`${JSON.stringify({
            type: 'control_response',
            response: { request_id: req.request_id, subtype: 'success', response: {} }
          })}\n`));
        });
        return;
      }
      if (!data.includes('"type":"user"')) return;
      setImmediate(() => {
        child.stdout.emit('data', Buffer.from(`${JSON.stringify({
          type: 'control_request',
          request_id: 'ask_user_question_1',
          request: {
            subtype: 'can_use_tool',
            tool_name: 'AskUserQuestion',
            input: {
              question: '你希望脚本做什么？',
              suggestions: ['系统自动化工具', '异步并发脚本']
            }
          }
        })}\n`));
        child.stdout.emit('data', Buffer.from(`${JSON.stringify({
          type: 'result',
          subtype: 'success',
          is_error: false,
          result: '"高级脚本"范围很广——你希望它做什么？\n\n- 系统自动化工具\n- 异步并发脚本',
          session_id: 'claude-session-ask'
        })}\n`));
      });
    },
    end() { this.destroyed = true; }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeAdapter({ spawnSyncFn: fakeSpawnSync, spawnFn: () => child });

  adapter.startRun({ prompt: '写一个python高级脚本', workspacePath: '.', onEvent: (event) => events.push(event) });
  await new Promise((resolve) => setTimeout(resolve, 50));

  assert.equal(events.some((event) => event.type === eventTypes.APPROVAL_REQUIRED), false);
  assert.equal(events.some((event) => event.type === eventTypes.ASSISTANT_QUESTION && event.text === '你希望脚本做什么？'), true);
  assert.deepEqual(events.find((event) => event.type === eventTypes.ASSISTANT_QUESTION).suggestions, ['系统自动化工具', '异步并发脚本']);
  assert.equal(events.some((event) => event.type === eventTypes.ASSISTANT_DELTA && event.text.includes('系统自动化工具')), true);
  assert.equal(events.some((event) => event.type === eventTypes.RUN_COMPLETED), true);
  assert.equal(stdinLines.some((line) => line.includes('ask_user_question_1') && line.includes('"behavior":"allow"')), true);
});

test('Claude conversation adapter preserves full AskUserQuestion context and suggestions', async () => {
  const events = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) {
      if (data.includes('"initialize"')) {
        const req = JSON.parse(data.trim());
        setImmediate(() => {
          child.stdout.emit('data', Buffer.from(`${JSON.stringify({
            type: 'control_response',
            response: { request_id: req.request_id, subtype: 'success', response: {} }
          })}\n`));
        });
        return;
      }
      if (!data.includes('"type":"user"')) return;
      setImmediate(() => {
        child.stdout.emit('data', Buffer.from(`${JSON.stringify({
          type: 'assistant',
          message: {
            role: 'assistant',
            content: [{
              type: 'thinking',
              thinking: 'The request is vague; ask for clarification before coding.'
            }]
          },
          session_id: 'conversation-session-ask'
        })}\n`));
        child.stdout.emit('data', Buffer.from(`${JSON.stringify({
          type: 'control_request',
          request_id: 'ask_user_question_2',
          request: {
            subtype: 'can_use_tool',
            tool_name: 'AskUserQuestion',
            tool_use_id: 'toolu_question_2',
            input: {
              prompt: '请帮我明确需求：',
              question: '你有什么类型的推荐吗？',
              suggestions: [
                '数据处理/分析 — 批量文件处理、数据清洗、爬虫',
                '自动化工具 — 系统监控、定时任务、日志分析',
                '开发工具 — 代码生成器、项目脚手架、依赖分析'
              ]
            }
          },
          session_id: 'conversation-session-ask'
        })}\n`));
      });
    },
    end() { this.destroyed = true; }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeConversationAdapter({ spawnSyncFn: fakeSpawnSync, spawnFn: () => child });
  const handle = await adapter.startConversation({
    conversationId: 'conv_ask',
    workspacePath: '.',
    permissionMode: 'auto',
    onEvent: (event) => events.push(event)
  });

  await handle.sendUserMessage('写一个python高级脚本');
  await new Promise((resolve) => setTimeout(resolve, 20));

  const question = events.find((event) => event.type === 'assistant.question');
  assert.ok(question);
  assert.equal(events.some((event) => event.type === 'assistant.thinking' && event.text.includes('request is vague')), true);
  assert.equal(question.questionId, 'toolu_question_2');
  assert.match(question.text, /请帮我明确需求/);
  assert.match(question.text, /你有什么类型的推荐吗/);
  assert.match(question.text, /开发工具/);
  assert.deepEqual(question.suggestions, [
    '数据处理/分析 — 批量文件处理、数据清洗、爬虫',
    '自动化工具 — 系统监控、定时任务、日志分析',
    '开发工具 — 代码生成器、项目脚手架、依赖分析'
  ]);
});

test('conversation HTTP API creates, sends, and replays events', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const conversationAdapters = new Map([['claude', {
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true },
    async startConversation({ onEvent }) {
      return {
        async sendUserMessage(text) { onEvent({ type: 'assistant.message', text: `synthetic conversation response: ${text}` }); },
        async answerQuestion(_questionId, text) { onEvent({ type: 'assistant.message', text: `synthetic question response: ${text}` }); },
        async respondApproval() {},
        async cancel() {},
        async dispose() {}
      };
    }
  }]]);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-http-'));
  const conversationDbPath = path.join(dir, 'conversations.sqlite');
  const app = createApp({ port: 0, conversationAdapters, conversationDbPath });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  let token;
  let conversationId;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'conversation-test',
      deviceId: 'fixed-device-1'
    });
    token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'claude' }, token);
    conversationId = created.body.conversation.id;
    assert.equal(created.status, 201);
    assert.equal(created.body.conversation.status, 'idle');
    assert.equal(created.body.conversation.cliSessionId, null);
    const listed = await request(port, 'GET', '/api/conversations', null, token);
    assert.equal(listed.body.conversations.some((conversation) => conversation.id === conversationId), true);
    const sent = await request(port, 'POST', `/api/conversations/${conversationId}/messages`, { text: 'hello' }, token);
    assert.equal(sent.status, 200);
    const events = await request(port, 'GET', `/api/conversations/${conversationId}/events?afterSeq=0`, null, token);
    assert.equal(events.body.events.some((event) => event.type === 'user.message' && event.text === 'hello'), true);
    assert.equal(events.body.events.some((event) => event.type === 'assistant.message' && /hello/.test(event.text)), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.conversationSqliteStore.close();
  }

  const restarted = createApp({ port: 0, conversationAdapters, conversationDbPath });
  await new Promise((resolve) => restarted.server.listen(0, '127.0.0.1', resolve));
  const restartedPort = restarted.server.address().port;
  try {
    const pairing = await request(restartedPort, 'POST', '/api/pairing-code', {});
    const paired = await request(restartedPort, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'conversation-test-restarted',
      deviceId: 'fixed-device-1'
    });
    const restartedToken = paired.body.token;
    await request(restartedPort, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, restartedToken);
    const workspaceId = (await request(restartedPort, 'GET', '/api/workspaces', null, restartedToken)).body.workspaces[0].id;
    const listed = await request(restartedPort, 'GET', '/api/conversations', null, restartedToken);
    assert.equal(listed.body.conversations.some((conversation) => conversation.id === conversationId), true);
    const events = await request(restartedPort, 'GET', `/api/conversations/${conversationId}/events?afterSeq=0`, null, restartedToken);
    assert.equal(events.body.events.some((event) => event.type === 'user.message' && event.text === 'hello'), true);
    assert.equal(events.body.events.some((event) => event.type === 'assistant.message' && /hello/.test(event.text)), true);
  } finally {
    await new Promise((resolve) => restarted.server.close(resolve));
    restarted.conversationSqliteStore.close();
  }
});

test('conversation events API supports tail and beforeSeq pages', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath('conversation-event-pages-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'phone' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId,
      adapter: 'claude',
      permissionMode: 'default'
    }, token);
    assert.equal(created.status, 201);
    const conversationId = created.body.conversation.id;
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'one' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'two' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'three' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'four' });

    const tail = await request(port, 'GET', `/api/conversations/${conversationId}/events?tail=2`, null, token);
    assert.equal(tail.status, 200);
    assert.deepEqual(tail.body.events.map((event) => event.seq), [4, 5]);
    assert.deepEqual(tail.body.page, {
      mode: 'tail',
      oldestSeq: 4,
      newestSeq: 5,
      hasMoreBefore: true
    });

    const before = await request(port, 'GET', `/api/conversations/${conversationId}/events?beforeSeq=3&limit=2`, null, token);
    assert.equal(before.status, 200);
    assert.deepEqual(before.body.events.map((event) => event.seq), [1, 2]);
    assert.deepEqual(before.body.page, {
      mode: 'before',
      oldestSeq: 1,
      newestSeq: 2,
      hasMoreBefore: false
    });
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.conversationSqliteStore.close();
  }
});

test('conversation events API rejects mixed pagination modes', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath('conversation-event-page-invalid-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'phone' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId,
      adapter: 'claude',
      permissionMode: 'default'
    }, token);
    for (const query of [
      'afterSeq=0&tail=2',
      'afterSeq=0&beforeSeq=3',
      'tail=2&beforeSeq=3'
    ]) {
      const response = await request(port, 'GET', `/api/conversations/${created.body.conversation.id}/events?${query}`, null, token);

      assert.equal(response.status, 400);
      assert.equal(response.body.error.code, 'invalid_event_page_query');
    }
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.conversationSqliteStore.close();
  }
});

test('conversation events API validates sequence cursors and clamps page limits', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath('conversation-event-page-validation-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'phone' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId,
      adapter: 'claude',
      permissionMode: 'default'
    }, token);
    const conversationId = created.body.conversation.id;
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'one' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'two' });

    for (const query of [
      'afterSeq=bad',
      'afterSeq=',
      'afterSeq=-1',
      'afterSeq=1e2',
      'afterSeq=0x10',
      'afterSeq=1.0',
      'afterSeq=9007199254740992',
      'beforeSeq=bad',
      'beforeSeq=0',
      'beforeSeq=1e2',
      'beforeSeq=0x10',
      'beforeSeq=1.0',
      'beforeSeq=9007199254740992',
      'tail=1e2',
      'tail=0x10',
      'tail=1.0',
      'tail=9007199254740992',
      'beforeSeq=3&limit=1e2',
      'beforeSeq=3&limit=0x10',
      'beforeSeq=3&limit=1.0',
      'beforeSeq=3&limit=9007199254740992'
    ]) {
      const response = await request(port, 'GET', `/api/conversations/${conversationId}/events?${query}`, null, token);

      assert.equal(response.status, 400);
      assert.equal(response.body.error.code, 'invalid_event_page_query');
    }

    const tail = await request(port, 'GET', `/api/conversations/${conversationId}/events?tail=0`, null, token);
    assert.equal(tail.status, 200);
    assert.deepEqual(tail.body.events.map((event) => event.seq), [3]);

    const before = await request(port, 'GET', `/api/conversations/${conversationId}/events?beforeSeq=3`, null, token);
    assert.equal(before.status, 200);
    assert.deepEqual(before.body.events.map((event) => event.seq), [1, 2]);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.conversationSqliteStore.close();
  }
});

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

function assertNotificationProtocolError(fn, code) {
  assert.throws(fn, (error) => {
    assert.equal(error.code, code);
    return true;
  });
}

test('notification protocol rejects invalid subscribe frames', () => {
  assertNotificationProtocolError(
    () => parseClientFrame(JSON.stringify({
      type: 'subscribe',
      id: 'req_1',
      topic: 'conversation.events',
      scope: {},
      afterSeq: -1
    })),
    notificationErrorCodes.INVALID_MESSAGE
  );

  assertNotificationProtocolError(
    () => parseClientFrame(JSON.stringify({
      type: 'subscribe',
      id: 'req_1',
      topic: 'conversation.events',
      scope: { conversationId: 'conv_1', workspaceId: 'ws_1' },
      afterSeq: 0
    })),
    notificationErrorCodes.INVALID_MESSAGE
  );
});

test('notification protocol rejects non-integer subscribe cursors without coercion', () => {
  assert.equal(parseClientFrame(JSON.stringify({
    type: 'subscribe',
    id: 'req_1',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' }
  })).afterSeq, 0);

  for (const afterSeq of ['7', '', null, 1.5, -1, [], {}]) {
    assertNotificationProtocolError(
      () => parseClientFrame(JSON.stringify({
        type: 'subscribe',
        id: 'req_1',
        topic: 'conversation.events',
        scope: { conversationId: 'conv_1' },
        afterSeq
      })),
      notificationErrorCodes.INVALID_MESSAGE
    );
  }
});

test('notification protocol rejects non-integer ack cursors without coercion', () => {
  for (const seq of ['7', '', null, 1.5, -1, [], {}]) {
    assertNotificationProtocolError(
      () => parseClientFrame(JSON.stringify({
        type: 'ack',
        topic: 'conversation.events',
        scope: { conversationId: 'conv_1' },
        seq
      })),
      notificationErrorCodes.INVALID_MESSAGE
    );
  }

  assertNotificationProtocolError(
    () => parseClientFrame(JSON.stringify({
      type: 'ack',
      topic: 'conversation.events',
      scope: { conversationId: 'conv_1' }
    })),
    notificationErrorCodes.INVALID_MESSAGE
  );
});

test('notification protocol errors expose codes separately from messages', () => {
  assert.throws(
    () => parseClientFrame(JSON.stringify({
      type: 'subscribe',
      id: 'req_1',
      topic: 'conversation.events',
      scope: {},
      afterSeq: 0
    })),
    (error) => {
      assert.equal(error.code, notificationErrorCodes.INVALID_MESSAGE);
      assert.equal(error.message, 'conversation.events requires scope.conversationId.');
      return true;
    }
  );
});

test('notification protocol parses ack frames', () => {
  assert.deepEqual(parseClientFrame(JSON.stringify({
    type: 'ack',
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    seq: 8
  })), {
    type: 'ack',
    id: null,
    topic: 'conversation.events',
    scope: { conversationId: 'conv_1' },
    seq: 8
  });
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

test('Claude conversation adapter asks user via input instead of permission approval', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) { stdinLines.push(data.trim()); }
  };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  const handle = await adapter.startConversation({ conversationId: 'conv_test', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: 'init_test' } })}\n`);
  await handle.sendUserMessage('写一个python高级脚本');
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'ask_user_question_1',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'AskUserQuestion',
      tool_use_id: 'toolu_1',
      input: { question: '你想让这个 Python 脚本做什么？', suggestions: ['爬虫', '数据分析'] }
    }
  })}\n`);

  const question = events.find((event) => event.type === 'assistant.question');
  assert.equal(question.text, '你想让这个 Python 脚本做什么？\n\n- 爬虫\n- 数据分析');
  assert.deepEqual(question.suggestions, ['爬虫', '数据分析']);
  assert.equal(events.some((event) => event.type === 'approval.requested'), false);
  await handle.answerQuestion(question.questionId, '数据分析');
  assert.equal(stdinLines.some((line) => line.includes('"type":"user"') && line.includes('数据分析')), true);
  assert.equal(stdinLines.some((line) => line.includes('ask_user_question_1') && line.includes('"behavior":"allow"')), true);
});

test('Claude conversation adapter extracts nested AskUserQuestion text', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_nested', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'ask_nested',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'AskUserQuestion',
      tool_use_id: 'toolu_nested',
      input: {
        tool_input: {
          question: '请帮我明确需求：\n\n1. 网络爬虫\n2. 数据分析\n3. 自动化工具',
          suggestions: ['网络爬虫', '数据分析']
        }
      }
    }
  })}\n`);
  const question = events.find((event) => event.type === 'assistant.question');
  assert.equal(question.text.includes('1. 网络爬虫'), true);
  assert.deepEqual(question.suggestions, ['网络爬虫', '数据分析']);
});

test('Claude conversation adapter separates thinking from final text', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_thinking', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [{ type: 'thinking', thinking: 'The request is vague; ask for clarification.' }]
    },
    session_id: 'session-thinking'
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [{ type: 'text', text: '"高级脚本"范围很广，能具体说说你想实现什么功能吗？' }]
    },
    session_id: 'session-thinking'
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'result',
    result: '"高级脚本"范围很广，能具体说说你想实现什么功能吗？\n\n- 数据处理/分析\n- 自动化工具\n- 网络/安全',
    session_id: 'session-thinking'
  })}\n`);

  const thinking = events.find((event) => event.type === 'assistant.thinking');
  const partial = events.find((event) => event.type === 'assistant.partial');
  const final = events.find((event) => event.type === 'assistant.message');
  assert.equal(thinking.text, 'The request is vague; ask for clarification.');
  assert.equal(partial.text.includes('范围很广'), true);
  assert.equal(final.text.includes('- 数据处理/分析'), true);
});

test('Claude conversation adapter forwards thinking chunks as typed blocks', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_multi_thinking', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [
        { type: 'thinking', thinking: 'First thought.' },
        { type: 'thinking', thinking: 'Second thought.' },
        { type: 'text', text: 'Visible answer.' }
      ]
    },
    session_id: 'session-multi-thinking'
  })}\n`);

  assert.deepEqual(
    events.filter((event) => event.type === 'assistant.thinking').map((event) => event.text),
    ['First thought.', 'Second thought.']
  );
  assert.equal(events.some((event) => event.type === 'assistant.partial' && event.text === 'Visible answer.'), true);
});

test('Claude conversation adapter maps AskUserQuestion tool_use to question event and tool_result answer', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) { stdinLines.push(data.trim()); }
  };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  const handle = await adapter.startConversation({ conversationId: 'conv_tool_question', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [
        { type: 'text', text: '请帮我明确需求：' },
        {
          type: 'tool_use',
          id: 'call_ask_python_script',
          name: 'AskUserQuestion',
          input: {
            questions: [{
              header: 'Script Type',
              question: '你想要什么类型的 Python 高级脚本？',
              options: [
                { label: '系统自动化', description: '文件管理、批量处理、系统监控、定时任务等' },
                { label: '网络爬虫/数据处理', description: '网页抓取、API 调用、数据清洗、数据分析可视化' },
                { label: 'CLI 工具', description: '带参数解析、彩色输出、进度条的命令行工具' },
                { label: 'AI/ML 相关', description: '调用 AI API、文本处理、机器学习管道' }
              ],
              multiSelect: false
            }]
          }
        }
      ]
    },
    session_id: 'session-tool-question'
  })}\n`);

  const question = events.find((event) => event.type === 'assistant.question');
  assert.equal(events.some((event) => event.type === 'approval.requested'), false);
  assert.equal(question.questionId, 'call_ask_python_script');
  assert.equal(question.text.includes('Script Type'), true);
  assert.equal(question.text.includes('你想要什么类型的 Python 高级脚本？'), true);
  assert.equal(question.text.includes('系统自动化 — 文件管理、批量处理、系统监控、定时任务等'), true);
  assert.deepEqual(question.suggestions, ['系统自动化', '网络爬虫/数据处理', 'CLI 工具', 'AI/ML 相关']);

  await handle.answerQuestion(question.questionId, 'CLI 工具');
  const toolResultLine = stdinLines.map((line) => JSON.parse(line)).find((payload) => {
    const content = payload.message?.content;
    return Array.isArray(content) && content.some((part) => part.type === 'tool_result');
  });
  const toolResult = toolResultLine.message.content[0];
  assert.equal(toolResult.tool_use_id, 'call_ask_python_script');
  assert.equal(toolResult.content, 'CLI 工具');
  assert.equal(toolResult.is_error, false);
});

test('Claude conversation adapter suppresses AskUserQuestion tool echoes', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_ask_echo', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'call_ask',
    name: 'AskUserQuestion',
    input: { question: 'Where should I create worktrees?', options: ['.worktrees/', 'Global directory'] }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'call_ask',
    name: 'AskUserQuestion',
    content: 'Answer questions?',
    is_error: true
  })}\n`);

  assert.equal(events.some((event) => event.type === 'assistant.question'), true);
  assert.equal(events.some((event) => event.type === 'tool.started'), false);
  assert.equal(events.some((event) => event.type === 'tool.output'), false);
  assert.equal(events.some((event) => event.type === 'tool.completed'), false);
});

test('Claude conversation adapter emits approval requests for tools', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) { stdinLines.push(data.trim()); }
  };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  const handle = await adapter.startConversation({ conversationId: 'conv_test', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'approval_1',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Bash',
      tool_use_id: 'toolu_2',
      input: { command: 'dir scripts' },
      permission_suggestions: [{ tool: 'Bash', rule: 'allow' }]
    }
  })}\n`);

  const approval = events.find((event) => event.type === 'approval.requested');
  assert.equal(approval.approvalId, 'approval_1');
  assert.equal(approval.summary, 'dir scripts');
  assert.deepEqual(approval.suggestions, [{ tool: 'Bash', rule: 'allow' }]);
  assert.deepEqual(approval.approvalOptions, {
    kind: 'command',
    supportsSessionScope: true,
    supportsCancel: false,
    denyBehavior: 'interrupt',
    command: 'dir scripts',
    proposedPermissions: { suggestions: [{ tool: 'Bash', rule: 'allow' }] }
  });
  await handle.respondApproval('approval_1', 'allow');
  assert.equal(stdinLines.some((line) => line.includes('approval_1') && line.includes('"behavior":"allow"')), true);
});

test('Claude conversation adapter denies Bash commands that target the daemon process', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) { stdinLines.push(data.trim()); }
  };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_daemon_guard', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'approval_kill_daemon',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Bash',
      tool_use_id: 'toolu_kill_daemon',
      input: { command: `taskkill /F /PID ${process.pid}` },
      permission_suggestions: ['allow']
    }
  })}\n`);
  await new Promise((resolve) => setImmediate(resolve));

  const responses = stdinLines
    .map((line) => JSON.parse(line))
    .filter((payload) => payload.type === 'control_response');
  const deny = responses.find((payload) =>
    payload.response?.request_id === 'approval_kill_daemon');
  assert.equal(deny.response.response.behavior, 'deny');
  assert.equal(deny.response.response.interrupt, false);
  assert.match(deny.response.response.message, /Blocked a shell command/);
  assert.equal(events.some((event) => event.type === 'approval.requested'), false);
  assert.equal(events.some((event) =>
    event.type === 'system.notice' &&
    event.noticeKind === 'daemon_self_protection'), true);
});

test('Claude conversation adapter responds to unsupported control requests with errors', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write(data) { stdinLines.push(data.trim()); } };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  await adapter.startConversation({ conversationId: 'conv_unknown_control', workspacePath: '.', onEvent: () => {} });

  for (const subtype of ['hook_callback', 'mcp_message', 'not_supported']) {
    child.stdout.emit('data', `${JSON.stringify({
      type: 'control_request',
      request_id: `req_${subtype}`,
      request: { subtype, callback_id: 'missing', server_name: 'missing' }
    })}\n`);
  }

  const responses = stdinLines
    .map((line) => JSON.parse(line))
    .filter((payload) => payload.type === 'control_response' && payload.response?.subtype === 'error');
  assert.deepEqual(responses.map((payload) => payload.response.request_id), [
    'req_hook_callback',
    'req_mcp_message',
    'req_not_supported'
  ]);
});

test('Claude conversation adapter sends dynamic control requests and returns responses', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write(data) { stdinLines.push(data.trim()); } };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const handle = await adapter.startConversation({ conversationId: 'conv_dynamic_control', workspacePath: '.', onEvent: () => {} });
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: 'init_dynamic' } })}\n`);

  const usagePromise = handle.getContextUsage();
  await new Promise((resolve) => setImmediate(resolve));
  const usageRequest = JSON.parse(stdinLines.at(-1));
  assert.equal(usageRequest.request.subtype, 'get_context_usage');
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_response',
    response: { request_id: usageRequest.request_id, subtype: 'success', response: { tokens: 12 } }
  })}\n`);
  assert.deepEqual(await usagePromise, { tokens: 12 });

  const permissionPromise = handle.setPermissionMode('auto');
  await new Promise((resolve) => setImmediate(resolve));
  const permissionRequest = JSON.parse(stdinLines.at(-1));
  assert.equal(permissionRequest.request.subtype, 'set_permission_mode');
  assert.equal(permissionRequest.request.mode, 'auto');
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_response',
    response: { request_id: permissionRequest.request_id, subtype: 'success', response: {} }
  })}\n`);
  await permissionPromise;

  await assert.rejects(async () => {
    const stopPromise = handle.stopTask('task_1');
    await new Promise((resolve) => setImmediate(resolve));
    const stopRequest = JSON.parse(stdinLines.at(-1));
    child.stdout.emit('data', `${JSON.stringify({
      type: 'control_response',
      response: { request_id: stopRequest.request_id, subtype: 'error', error: { message: 'no task' } }
    })}\n`);
    await stopPromise;
  }, /no task/);
});

test('Claude conversation adapter forwards updated approval input and deny interrupt flags', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const stdinLines = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write(data) { stdinLines.push(data.trim()); } };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const handle = await adapter.startConversation({ conversationId: 'conv_approval_payload', workspacePath: '.', onEvent: () => {} });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'approval_payload',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Bash',
      input: { command: 'dir' }
    }
  })}\n`);

  await handle.respondApproval('approval_payload', {
    decision: 'allow',
    updatedInput: { command: 'npm test' },
    updatedPermissions: [{ tool: 'Bash', rule: 'allow' }]
  });
  const allowResponse = JSON.parse(stdinLines.at(-1)).response.response;
  assert.deepEqual(allowResponse.updatedInput, { command: 'npm test' });
  assert.deepEqual(allowResponse.updatedPermissions, [{ tool: 'Bash', rule: 'allow' }]);

  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'approval_session',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Bash',
      input: { command: 'npm test' },
      permission_suggestions: [{ tool: 'Bash', rule: 'allow' }]
    }
  })}\n`);

  await handle.respondApproval('approval_session', {
    decision: 'allow',
    scope: 'session'
  });
  const sessionResponse = JSON.parse(stdinLines.at(-1)).response.response;
  assert.equal(sessionResponse.behavior, 'allow');
  assert.deepEqual(sessionResponse.updatedPermissions, [{ tool: 'Bash', rule: 'allow' }]);

  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'approval_session_no_suggestions',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Bash',
      input: { command: 'npm run lint' }
    }
  })}\n`);

  await handle.respondApproval('approval_session_no_suggestions', {
    decision: 'allow',
    scope: 'session'
  });
  const noSuggestionResponse = JSON.parse(stdinLines.at(-1)).response.response;
  assert.equal(noSuggestionResponse.behavior, 'allow');
  assert.equal(Object.prototype.hasOwnProperty.call(noSuggestionResponse, 'updatedPermissions'), false);

  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'approval_deny',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Bash',
      input: { command: 'del file' }
    }
  })}\n`);
  await handle.respondApproval('approval_deny', { decision: 'deny', interrupt: false });
  const denyResponse = JSON.parse(stdinLines.at(-1)).response.response;
  assert.equal(denyResponse.behavior, 'deny');
  assert.equal(denyResponse.interrupt, false);
});

test('Claude conversation adapter throws when stdin writes fail', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(_data, callback) {
      if (typeof callback === 'function') callback(new Error('stdin closed'));
      return false;
    }
  };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });

  await assert.rejects(
    () => adapter.startConversation({ conversationId: 'conv_write_fail', workspacePath: '.', onEvent: () => {} }),
    /stdin closed/
  );
});

test('Claude conversation adapter emits blocking cancellation for cancelled approvals', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_cancel_approval', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'approval_cancel_1',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Bash',
      tool_use_id: 'toolu_cancel',
      input: { command: 'git push --force' }
    }
  })}\n`);

  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_cancel_request',
    request_id: 'approval_cancel_1'
  })}\n`);

  const cancelled = events.find((event) => event.type === 'blocking.request_cancelled');
  assert.equal(cancelled.approvalId, 'approval_cancel_1');
  assert.equal(cancelled.blockingType, 'approval_request');
  assert.equal(cancelled.toolUseId, 'toolu_cancel');
  assert.equal(cancelled.toolName, 'Bash');
});

test('Claude conversation adapter emits blocking cancellation for cancelled questions', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_cancel_question', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_request',
    request_id: 'question_cancel_1',
    request: {
      subtype: 'can_use_tool',
      tool_name: 'AskUserQuestion',
      tool_use_id: 'toolu_question_cancel',
      input: { question: 'Pick a direction' }
    }
  })}\n`);

  child.stdout.emit('data', `${JSON.stringify({
    type: 'control_cancel_request',
    request_id: 'question_cancel_1'
  })}\n`);

  const cancelled = events.find((event) => event.type === 'blocking.request_cancelled');
  assert.equal(cancelled.questionId, 'toolu_question_cancel');
  assert.equal(cancelled.requestId, 'question_cancel_1');
  assert.equal(cancelled.blockingType, 'input_request');
  assert.equal(cancelled.toolName, 'AskUserQuestion');
});

test('Claude conversation adapter surfaces ExitPlanMode denial as question', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_exit_plan', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_exit_plan',
    name: 'ExitPlanMode',
    input: { allowedPrompts: [{ tool: 'Bash', prompt: 'npm test' }] }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_exit_plan',
    content: 'Exit plan mode?',
    is_error: true
  })}\n`);

  const question = events.find((event) => event.type === 'assistant.question');
  assert.equal(question.questionId, 'toolu_exit_plan');
  assert.equal(question.toolName, 'ExitPlanMode');
  assert.deepEqual(question.suggestions, ['批准计划并继续', '调整计划']);
});

test('Claude conversation adapter surfaces result permission denials', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_permission_denial', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'result',
    result: 'done',
    permission_denials: [{
      tool_name: 'Write',
      tool_use_id: 'toolu_write',
      tool_input: { file_path: 'D:\\\\tmp\\\\a.txt' }
    }]
  })}\n`);

  const notice = events.find((event) => event.type === 'system.notice');
  assert.equal(notice.noticeKind, 'permission_unavailable');
  assert.equal(notice.toolUseId, 'toolu_write');
  assert.equal(notice.toolName, 'Write');
  assert.equal(/自动权限模式/.test(notice.text), false);
  assert.equal(/默认/.test(notice.text), true);
});

test('Claude conversation adapter maps TaskCreate and TaskUpdate to task progress', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_claude_tasks', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_task_create',
    name: 'TaskCreate',
    input: {
      subject: 'Fix Converters project external path dependency',
      description: 'Replace hardcoded project reference',
      activeForm: 'Fixing Converters project dependency'
    }
  })}\n`);
  const startedProgress = events.filter((event) => event.type === 'task.progress.updated');
  assert.equal(startedProgress.length, 1);
  assert.equal(startedProgress[0].items[0].title, 'Fix Converters project external path dependency');
  assert.equal(startedProgress[0].items[0].status, 'pending');

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_task_create',
    tool_use_result: {
      success: true,
      task: {
        id: '1'
      }
    }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_task_update',
    name: 'TaskUpdate',
    input: { taskId: '1', status: 'in_progress' }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_task_update',
    content: 'Updated task #1 status',
    tool_use_result: {
      success: true,
      taskId: '1',
      updatedFields: ['status'],
      statusChange: { from: 'pending', to: 'in_progress' }
    }
  })}\n`);

  const progressEvents = events.filter((event) => event.type === 'task.progress.updated');
  assert.equal(progressEvents.length, 2);
  assert.equal(progressEvents[0].source, 'claude');
  assert.equal(progressEvents[0].taskId, 'claude_tasks');
  assert.equal(progressEvents[0].items[0].id, 'toolu_task_create');
  assert.equal(progressEvents[0].items[0].title, 'Fix Converters project external path dependency');
  assert.equal(progressEvents[0].items[0].status, 'pending');
  assert.equal(progressEvents[1].items[0].id, '1');
  assert.equal(progressEvents[1].items[0].title, 'Fix Converters project external path dependency');
  assert.equal(progressEvents[1].items[0].status, 'in_progress');
  assert.equal(progressEvents[1].completedCount, 0);
  assert.equal(progressEvents[1].totalCount, 1);
  assert.equal(events.some((event) => event.type === 'tool.started' && event.toolName === 'TaskUpdate'), false);
});

test('Claude conversation adapter restores task titles from initial progress', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({
    conversationId: 'conv_claude_seeded_tasks',
    workspacePath: '.',
    initialTaskProgress: {
      items: [
        { id: '8', title: 'Task 13: Final Integration & Polish', status: 'in_progress' }
      ]
    },
    onEvent: (event) => events.push(event)
  });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_task_update_8',
    name: 'TaskUpdate',
    input: { taskId: '8', status: 'completed' }
  })}\n`);

  const progressEvents = events.filter((event) => event.type === 'task.progress.updated');
  assert.equal(progressEvents.length, 1);
  assert.equal(progressEvents[0].items[0].id, '8');
  assert.equal(progressEvents[0].items[0].title, 'Task 13: Final Integration & Polish');
  assert.equal(progressEvents[0].items[0].status, 'completed');
});

test('Claude conversation adapter ignores empty lifecycle frames', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_lifecycle', workspacePath: '.', onEvent: (event) => events.push(event) });

  for (const raw of [
    { type: 'system', subtype: 'hook_started', session_id: 'session_lifecycle' },
    { type: 'system', subtype: 'status', session_id: 'session_lifecycle' },
    { type: 'message_delta', session_id: 'session_lifecycle' },
    { type: 'message_stop', session_id: 'session_lifecycle' }
  ]) {
    child.stdout.emit('data', `${JSON.stringify(raw)}\n`);
  }

  assert.equal(events.some((event) => event.type === 'protocol.warning'), false);
});

test('Claude conversation adapter surfaces API retry authentication failures', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_api_retry', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'system',
    subtype: 'api_retry',
    attempt: 1,
    max_retries: 10,
    error_status: 401,
    error: 'authentication_failed',
    session_id: 'session_api_retry'
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'system',
    subtype: 'api_retry',
    attempt: 2,
    max_retries: 10,
    error_status: 401,
    error: 'authentication_failed',
    session_id: 'session_api_retry'
  })}\n`);

  const warnings = events.filter((event) => event.type === 'protocol.warning');
  const warning = warnings[0];
  assert.equal(warning.visible, true);
  assert.match(warning.text, /Claude API 401 authentication_failed/);
  assert.equal(warning.sessionId, 'session_api_retry');
  assert.equal(warnings[1].visible, false);
});

test('Claude conversation adapter marks non-interactive approval failures', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_permission_error', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_permission',
    name: 'Bash',
    input: { command: 'git pull' }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_permission',
    content: 'This command requires approval',
    is_error: true
  })}\n`);

  const notice = events.find((event) => event.type === 'system.notice');
  const output = events.find((event) => event.type === 'tool.output');
  const completed = events.find((event) => event.type === 'tool.completed');
  assert.equal(notice.noticeKind, 'permission_unavailable');
  assert.equal(notice.text.includes('当前 CLI 没有发出可响应的移动端审批请求'), true);
  assert.equal(output.permissionError, true);
  assert.equal(completed.permissionError, true);
});

test('Claude conversation adapter marks auto classifier denials as permission failures', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_auto_permission_error', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_use',
    id: 'toolu_permission_auto',
    name: 'Bash',
    input: { command: 'git commit --amend' }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'tool_result',
    tool_use_id: 'toolu_permission_auto',
    content: 'Permission for this action was denied by the Claude Code auto mode classifier. Reason: Git destructive: `git commit --amend` rewrites remote history.',
    is_error: true
  })}\n`);

  const notice = events.find((event) => event.type === 'system.notice');
  const output = events.find((event) => event.type === 'tool.output');
  const completed = events.find((event) => event.type === 'tool.completed');
  assert.equal(notice.noticeKind, 'permission_unavailable');
  assert.equal(output.permissionError, true);
  assert.equal(completed.permissionError, true);
});

test('Claude conversation adapter maps wrapped tool result to output and completion', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_tool', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'stream_event',
    event: { type: 'tool_use', id: 'toolu_a', name: 'Bash', input: { command: 'npm test' } }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'stream_event',
    event: { type: 'tool_result', tool_use_id: 'toolu_a', content: '1 failing test', exit_code: 1, is_error: true }
  })}\n`);

  const started = events.find((event) => event.type === 'tool.started');
  const output = events.find((event) => event.type === 'tool.output');
  const completed = events.find((event) => event.type === 'tool.completed');
  assert.equal(started.toolUseId, 'toolu_a');
  assert.equal(started.toolName, 'Bash');
  assert.equal(started.input.command, 'npm test');
  assert.equal(output.toolUseId, 'toolu_a');
  assert.equal(output.text, '1 failing test');
  assert.equal(output.exitCode, 1);
  assert.equal(output.isError, true);
  assert.equal(completed.toolUseId, 'toolu_a');
  assert.equal(completed.exitCode, 1);
  assert.equal(completed.isError, true);
});

test('Claude conversation adapter correlates repeated and interleaved tool results', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_multi_tool', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_use', id: 'toolu_a', name: 'Bash', input: { command: 'npm' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_use', id: 'toolu_a', name: 'Bash', input: { command: 'npm test' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_use_delta', tool_use_id: 'toolu_a', content: 'running tests' })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_use', id: 'toolu_b', name: 'Read', input: { file_path: 'README.md' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_result', tool_use_id: 'toolu_b', content: 'readme body', exit_code: 0, is_error: false })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_result', tool_use_id: 'toolu_a', content: 'tests passed', exit_code: 0, is_error: false })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_result', tool_use_id: 'toolu_orphan', content: 'resumed output', exit_code: 0, is_error: false })}\n`);

  const starts = events.filter((event) => event.type === 'tool.started');
  const deltas = events.filter((event) => event.type === 'tool.delta');
  const outputs = events.filter((event) => event.type === 'tool.output');
  assert.equal(starts.filter((event) => event.toolUseId === 'toolu_a').at(-1).input.command, 'npm test');
  assert.equal(deltas.find((event) => event.toolUseId === 'toolu_a').text, 'running tests');
  assert.equal(outputs.find((event) => event.toolUseId === 'toolu_b').text, 'readme body');
  assert.equal(outputs.find((event) => event.toolUseId === 'toolu_a').text, 'tests passed');
  assert.equal(outputs.find((event) => event.toolUseId === 'toolu_orphan').text, 'resumed output');
});

test('Claude conversation adapter maps content block tool use and result', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_content_block_tool', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'content_block_start',
    index: 1,
    content_block: { type: 'tool_use', id: 'toolu_cb', name: 'Bash', input: {} }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'content_block_delta',
    index: 1,
    delta: { type: 'input_json_delta', partial_json: '{"command":"python python_basics.py"' }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'content_block_delta',
    index: 1,
    delta: { type: 'input_json_delta', partial_json: ',"description":"Run script"}' }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'content_block_stop', index: 1 })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'content_block_start',
    index: 0,
    content_block: { type: 'tool_result', tool_use_id: 'toolu_cb', content: 'script output', is_error: false }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n`);

  const started = events.find((event) => event.type === 'tool.started');
  const output = events.find((event) => event.type === 'tool.output');
  const completed = events.find((event) => event.type === 'tool.completed');
  assert.equal(started.toolUseId, 'toolu_cb');
  assert.equal(started.toolName, 'Bash');
  assert.equal(started.input.command, 'python python_basics.py');
  assert.equal(started.input.description, 'Run script');
  assert.equal(output.toolUseId, 'toolu_cb');
  assert.equal(output.text, 'script output');
  assert.equal(completed.toolUseId, 'toolu_cb');
});

test('Claude conversation adapter maps assistant content tool result without duplicates', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_assistant_tool_result', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: 'init_conv_assistant_tool_result', subtype: 'success', response: {} } })}\n`);

  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_use', id: 'toolu_assistant', name: 'Bash', input: { command: 'npm test' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [{ type: 'tool_result', tool_use_id: 'toolu_assistant', content: 'tests passed', is_error: false }]
    }
  })}\n`);

  const outputs = events.filter((event) => event.type === 'tool.output');
  const completed = events.filter((event) => event.type === 'tool.completed');
  assert.equal(outputs.length, 1);
  assert.equal(outputs[0].toolUseId, 'toolu_assistant');
  assert.equal(outputs[0].text, 'tests passed');
  assert.equal(completed.length, 1);
});

test('Claude conversation adapter emits one output for chunked content block result', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_chunked_tool_result', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: 'init_conv_chunked_tool_result', subtype: 'success', response: {} } })}\n`);

  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_use', id: 'toolu_chunked', name: 'Bash', input: { command: 'npm test' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'content_block_start',
    index: 0,
    content_block: { type: 'tool_result', tool_use_id: 'toolu_chunked', content: '', is_error: false }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'tests ' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'passed' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n`);

  const deltas = events.filter((event) => event.type === 'tool.delta');
  const outputs = events.filter((event) => event.type === 'tool.output');
  assert.equal(deltas.length, 0);
  assert.equal(outputs.length, 1);
  assert.equal(outputs[0].text, 'tests passed');
});

test('Claude conversation adapter maps assistant tool_use and user tool_result', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_user_tool_result', workspacePath: '.', onEvent: (event) => events.push(event) });
  child.stdout.emit('data', `${JSON.stringify({ type: 'control_response', response: { request_id: 'init_conv_user_tool_result', subtype: 'success', response: {} } })}\n`);

  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [{ type: 'tool_use', id: 'toolu_read_log', name: 'Read', input: { file_path: 'D:\\Test\\log.txt' } }]
    }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'user',
    message: {
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: 'toolu_read_log', content: 'line 1\nline 2\nline 3', is_error: false }]
    }
  })}\n`);

  const started = events.find((event) => event.type === 'tool.started');
  const output = events.find((event) => event.type === 'tool.output');
  const completed = events.find((event) => event.type === 'tool.completed');
  assert.equal(started.toolUseId, 'toolu_read_log');
  assert.equal(started.toolName, 'Read');
  assert.equal(started.input.file_path, 'D:\\Test\\log.txt');
  assert.equal(output.toolUseId, 'toolu_read_log');
  assert.equal(output.text, 'line 1\nline 2\nline 3');
  assert.equal(completed.toolUseId, 'toolu_read_log');
});

test('Claude conversation adapter surfaces permission tool_result as notice', async () => {
  const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {} };
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 0, stdout: '2.1.119', stderr: '' }),
    spawnFn: () => child
  });
  const events = [];
  await adapter.startConversation({ conversationId: 'conv_permission_result', workspacePath: '.', onEvent: (event) => events.push(event) });

  child.stdout.emit('data', `${JSON.stringify({
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [{ type: 'tool_use', id: 'toolu_write_denied', name: 'Write', input: { file_path: 'D:\\AiProject\\Agent\\python_basics.py', content: 'print(1)' } }]
    }
  })}\n`);
  child.stdout.emit('data', `${JSON.stringify({
    type: 'user',
    message: {
      role: 'user',
      content: [{
        type: 'tool_result',
        tool_use_id: 'toolu_write_denied',
        content: 'Claude requested permissions to write to D:\\AiProject\\Agent\\python_basics.py, but you haven\'t granted it yet.',
        is_error: true
      }]
    }
  })}\n`);

  const notice = events.find((event) => event.type === 'system.notice');
  const output = events.find((event) => event.type === 'tool.output');
  const completed = events.find((event) => event.type === 'tool.completed');
  assert.equal(notice.noticeKind, 'permission_unavailable');
  assert.equal(notice.toolUseId, 'toolu_write_denied');
  assert.equal(notice.text.includes('没有发出可响应的移动端审批请求'), true);
  assert.equal(output.isError, true);
  assert.equal(output.permissionError, true);
  assert.equal(completed.isError, true);
  assert.equal(completed.permissionError, true);
});

test('Codex conversation adapter starts first turn with global approval before exec and workspace cwd', async () => {
  let spawnCommand = null;
  let spawnArgs = null;
  let spawnOptions = null;
  let stdinEnded = false;
  const child = fakeCodexChild();
  child.stdin = { destroyed: false, end() { stdinEnded = true; this.destroyed = true; } };
  const adapter = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeCodexConversationSpawnSync,
    spawnFn: (cmd, args, options) => {
      spawnCommand = cmd;
      spawnArgs = args;
      spawnOptions = options;
      return child;
    }
  });

  const handle = await adapter.startConversation({ conversationId: 'conv_codex_args', workspacePath: 'D:\\AiProject\\vibe-coding', permissionMode: 'auto', onEvent: () => {} });
  await handle.sendUserMessage('hello');

  assert.equal(spawnCommand, 'codex');
  assert.deepEqual(spawnArgs.slice(0, 7), ['--ask-for-approval', 'never', '-c', 'tool_timeout_sec=600', 'exec', '--json', '-C']);
  assert.equal(spawnArgs.includes('--skip-git-repo-check'), true);
  assert.equal(spawnArgs.includes('--dangerously-bypass-approvals-and-sandbox'), false);
  assert.equal(spawnArgs[spawnArgs.length - 1], 'hello');
  assert.equal(spawnOptions.cwd, 'D:\\AiProject\\vibe-coding');
  assert.equal(stdinEnded, true);
  child.emit('exit', 0, null);
});

test('Codex attachment dispatch includes image paths and text wrapper blocks', () => {
  const { buildAdapterUserMessage } = require('../daemon/src/codex-conversation-adapter');

  const message = buildAdapterUserMessage({
    text: 'Inspect this.',
    attachments: [
      { kind: 'image', handling: 'native', scratchPath: 'D:\\scratch\\a.png', mimeType: 'image/png', name: 'a.png' },
      { kind: 'textDocument', handling: 'text_extract', text: 'alpha', mimeType: 'text/plain', name: 'a.txt' }
    ]
  });

  assert.deepEqual(message.imagePaths, ['D:\\scratch\\a.png']);
  assert.match(message.prompt, /^Inspect this\./);
  assert.match(message.prompt, /<attachment name="a.txt" mime="text\/plain">/);
  assert.match(message.prompt, /alpha/);
});

test('attachment text wrapper escapes XML-ish attributes', () => {
  const { buildAdapterUserMessage } = require('../daemon/src/codex-conversation-adapter');

  const message = buildAdapterUserMessage({
    text: '',
    attachments: [
      {
        kind: 'textDocument',
        handling: 'text_extract',
        text: 'body',
        mimeType: 'text/plain; note="<tag>&"',
        name: 'a"&<>.txt'
      }
    ]
  });

  assert.match(message.prompt, /name="a&quot;&amp;&lt;&gt;.txt"/);
  assert.match(message.prompt, /mime="text\/plain; note=&quot;&lt;tag&gt;&amp;&quot;"/);
});

test('Codex attachment dispatch adds image flags to exec and resume argv', () => {
  const { buildCodexExecArgs, buildCodexResumeArgs } = require('../daemon/src/codex-conversation-adapter');

  const execArgs = buildCodexExecArgs({
    prompt: 'Inspect image.',
    workspacePath: 'D:\\Repo',
    imagePaths: ['D:\\scratch\\a.png', 'D:\\scratch\\b.png']
  });
  const resumeArgs = buildCodexResumeArgs({
    prompt: 'Inspect again.',
    sessionId: 'thread_1',
    workspacePath: 'D:\\Repo',
    imagePaths: ['D:\\scratch\\a.png']
  });

  assert.deepEqual(execArgs.slice(execArgs.indexOf('--image'), execArgs.indexOf('--image') + 4), ['--image', 'D:\\scratch\\a.png', '--image', 'D:\\scratch\\b.png']);
  assert.equal(execArgs.indexOf('Inspect image.') < execArgs.indexOf('--image'), true);
  assert.deepEqual(resumeArgs.slice(resumeArgs.indexOf('--image'), resumeArgs.indexOf('--image') + 2), ['--image', 'D:\\scratch\\a.png']);
  assert.equal(resumeArgs.indexOf('thread_1') < resumeArgs.indexOf('--image'), true);
  assert.equal(resumeArgs.indexOf('Inspect again.') < resumeArgs.indexOf('--image'), true);
});

test('Codex command timeout config is explicit and configurable', () => {
  const { buildCodexExecArgs, buildCodexResumeArgs } = require('../daemon/src/codex-conversation-adapter');

  const execArgs = buildCodexExecArgs({
    prompt: 'Run tests.',
    workspacePath: 'D:\\Repo',
    toolTimeoutSec: 900
  });
  const resumeArgs = buildCodexResumeArgs({
    prompt: 'Continue tests.',
    sessionId: 'thread_1',
    workspacePath: 'D:\\Repo',
    toolTimeoutSec: 900
  });
  const defaultArgs = buildCodexExecArgs({
    prompt: 'Run without override.',
    workspacePath: 'D:\\Repo',
    toolTimeoutSec: null
  });

  assert.deepEqual(execArgs.slice(0, 5), ['--ask-for-approval', 'on-request', '-c', 'tool_timeout_sec=900', 'exec']);
  assert.deepEqual(resumeArgs.slice(0, 5), ['--ask-for-approval', 'on-request', '-c', 'tool_timeout_sec=900', 'exec']);
  assert.deepEqual(defaultArgs.slice(0, 3), ['--ask-for-approval', 'on-request', 'exec']);
});

test('Codex app-server approval requests map to mobile contract and JSON-RPC responses', () => {
  const {
    CODEX_APP_SERVER_APPROVAL_CAPABILITY,
    buildCodexAppServerApprovalResponse,
    mapCodexAppServerApprovalRequest
  } = require('../daemon/src/codex-app-server-approval');
  const {
    normalizeApprovalDecision,
    normalizeApprovalOptions
  } = require('../daemon/src/conversation-protocol');

  const commandRequest = mapCodexAppServerApprovalRequest({
    id: 61,
    method: 'item/commandExecution/requestApproval',
    params: {
      threadId: 'thread_1',
      turnId: 'turn_1',
      itemId: 'item_cmd',
      approvalId: 'approval_cmd',
      startedAtMs: 1710000000000,
      reason: 'Need to run tests',
      command: 'npm test',
      cwd: 'D:\\Repo',
      additionalPermissions: { network: { enabled: true } },
      availableDecisions: ['accept', 'acceptForSession', 'decline', 'cancel']
    }
  });

  assert.equal(commandRequest.event.type, conversationEventTypes.APPROVAL_REQUESTED);
  assert.equal(commandRequest.event.approvalId, 'approval_cmd');
  assert.equal(commandRequest.event.summary, 'npm test');
  assert.equal(Object.prototype.hasOwnProperty.call(commandRequest.event.approvalOptions, 'rawProviderRequest'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(commandRequest.event.approvalOptions, 'availableDecisions'), false);
  assert.deepEqual(
    normalizeApprovalOptions(commandRequest.event.approvalOptions, CODEX_APP_SERVER_APPROVAL_CAPABILITY),
    {
      kind: 'command',
      supportsSessionScope: true,
      supportsCancel: true,
      denyBehavior: 'continue',
      command: 'npm test',
      cwd: 'D:\\Repo',
      reason: 'Need to run tests',
      proposedPermissions: { network: { enabled: true } }
    }
  );
  assert.deepEqual(
    buildCodexAppServerApprovalResponse(
      commandRequest.context,
      normalizeApprovalDecision({ decision: 'allow', scope: 'session' })
    ),
    { id: 61, result: { decision: 'acceptForSession' } }
  );
  assert.deepEqual(
    buildCodexAppServerApprovalResponse(
      commandRequest.context,
      normalizeApprovalDecision({ decision: 'deny', interrupt: false })
    ),
    { id: 61, result: { decision: 'decline' } }
  );
  assert.deepEqual(
    buildCodexAppServerApprovalResponse(
      commandRequest.context,
      normalizeApprovalDecision({ decision: 'deny', interrupt: true })
    ),
    { id: 61, result: { decision: 'cancel' } }
  );

  const commandWithoutDecisionMetadata = mapCodexAppServerApprovalRequest({
    id: 62,
    method: 'item/commandExecution/requestApproval',
    params: {
      itemId: 'item_cmd_no_decisions',
      command: 'npm test'
    }
  });
  assert.equal(commandWithoutDecisionMetadata.event.approvalOptions.supportsSessionScope, false);
  assert.equal(commandWithoutDecisionMetadata.event.approvalOptions.supportsCancel, false);
  assert.equal(
    normalizeApprovalOptions(commandWithoutDecisionMetadata.event.approvalOptions, CODEX_APP_SERVER_APPROVAL_CAPABILITY)
      .supportsSessionScope,
    false
  );
  assert.deepEqual(
    buildCodexAppServerApprovalResponse(
      commandWithoutDecisionMetadata.context,
      normalizeApprovalDecision({ decision: 'cancel' })
    ),
    { id: 62, result: { decision: 'decline' } }
  );

  const permissionsRequest = mapCodexAppServerApprovalRequest({
    id: 'req_permissions',
    method: 'item/permissions/requestApproval',
    params: {
      threadId: 'thread_1',
      turnId: 'turn_1',
      itemId: 'perm_1',
      environmentId: 'local',
      startedAtMs: 1710000000001,
      cwd: 'D:\\Repo',
      reason: 'Need workspace write access',
      permissions: {
        fileSystem: { write: ['D:\\Repo'] },
        network: { enabled: true }
      }
    }
  });

  assert.equal(permissionsRequest.event.type, conversationEventTypes.APPROVAL_REQUESTED);
  assert.equal(permissionsRequest.event.approvalId, 'perm_1');
  assert.deepEqual(
    normalizeApprovalOptions(permissionsRequest.event.approvalOptions, CODEX_APP_SERVER_APPROVAL_CAPABILITY),
    {
      kind: 'permissions',
      supportsSessionScope: true,
      supportsCancel: false,
      denyBehavior: 'continue',
      cwd: 'D:\\Repo',
      reason: 'Need workspace write access',
      proposedPermissions: {
        fileSystem: { write: ['D:\\Repo'] },
        network: { enabled: true }
      }
    }
  );
  assert.deepEqual(
    buildCodexAppServerApprovalResponse(
      permissionsRequest.context,
      normalizeApprovalDecision({ decision: 'allow', scope: 'session' })
    ),
    {
      id: 'req_permissions',
      result: {
        permissions: {
          fileSystem: { write: ['D:\\Repo'] },
          network: { enabled: true }
        },
        scope: 'session'
      }
    }
  );
  assert.deepEqual(
    buildCodexAppServerApprovalResponse(
      permissionsRequest.context,
      normalizeApprovalDecision({ decision: 'deny', interrupt: false })
    ),
    { id: 'req_permissions', result: { permissions: {}, scope: 'turn' } }
  );
});

test('Codex app-server bridge covers current exec adapter launch and event contract', () => {
  const {
    buildCodexAppServerThreadResumeRequest,
    buildCodexAppServerThreadStartRequest,
    buildCodexAppServerTurnInterruptRequest,
    buildCodexAppServerTurnStartRequest,
    mapCodexAppServerNotification
  } = require('../daemon/src/codex-app-server-bridge');

  const threadStart = buildCodexAppServerThreadStartRequest({
    requestId: 1,
    workspacePath: 'D:\\Repo',
    permissionMode: 'auto',
    model: 'gpt-5.5',
    toolTimeoutSec: 900
  });
  assert.deepEqual(threadStart, {
    id: 1,
    method: 'thread/start',
    params: {
      cwd: 'D:\\Repo',
      approvalPolicy: 'never',
      approvalsReviewer: 'user',
      sandbox: 'read-only',
      config: { tool_timeout_sec: 900 },
      model: 'gpt-5.5'
    }
  });

  const threadResume = buildCodexAppServerThreadResumeRequest({
    requestId: 2,
    threadId: 'thread_1',
    workspacePath: 'D:\\Repo',
    permissionMode: 'default',
    model: 'gpt-5.5',
    toolTimeoutSec: 900
  });
  assert.deepEqual(threadResume, {
    id: 2,
    method: 'thread/resume',
    params: {
      threadId: 'thread_1',
      cwd: 'D:\\Repo',
      approvalPolicy: 'on-request',
      approvalsReviewer: 'user',
      sandbox: 'read-only',
      config: { tool_timeout_sec: 900 },
      model: 'gpt-5.5'
    }
  });

  const turnStart = buildCodexAppServerTurnStartRequest({
    requestId: 3,
    threadId: 'thread_1',
    clientUserMessageId: 'client_msg_1',
    workspacePath: 'D:\\Repo',
    permissionMode: 'default',
    model: 'gpt-5.5',
    message: {
      text: 'Inspect this.',
      attachments: [
        { kind: 'image', handling: 'native', scratchPath: 'D:\\scratch\\a.png', mimeType: 'image/png', name: 'a.png' },
        { kind: 'textDocument', handling: 'text_extract', text: 'alpha', mimeType: 'text/plain', name: 'a.txt' }
      ]
    }
  });
  assert.equal(turnStart.method, 'turn/start');
  assert.equal(turnStart.params.threadId, 'thread_1');
  assert.equal(turnStart.params.clientUserMessageId, 'client_msg_1');
  assert.equal(turnStart.params.cwd, 'D:\\Repo');
  assert.equal(turnStart.params.approvalPolicy, 'on-request');
  assert.equal(turnStart.params.approvalsReviewer, 'user');
  assert.equal(turnStart.params.model, 'gpt-5.5');
  assert.deepEqual(turnStart.params.sandboxPolicy, {
    type: 'workspaceWrite',
    writableRoots: ['D:\\Repo'],
    networkAccess: false,
    excludeTmpdirEnvVar: false,
    excludeSlashTmp: false
  });
  assert.equal(turnStart.params.input[0].type, 'text');
  assert.match(turnStart.params.input[0].text, /^Inspect this\./);
  assert.match(turnStart.params.input[0].text, /<attachment name="a.txt" mime="text\/plain">/);
  assert.deepEqual(turnStart.params.input[0].text_elements, []);
  assert.deepEqual(turnStart.params.input[1], { type: 'localImage', path: 'D:\\scratch\\a.png' });

  assert.deepEqual(
    buildCodexAppServerTurnInterruptRequest({ requestId: 4, threadId: 'thread_1', turnId: 'turn_1' }),
    {
      id: 4,
      method: 'turn/interrupt',
      params: { threadId: 'thread_1', turnId: 'turn_1' }
    }
  );

  const threadNotice = mapCodexAppServerNotification({
    method: 'thread/started',
    params: { thread: { id: 'thread_1' } }
  });
  assert.equal(threadNotice.type, conversationEventTypes.SYSTEM_NOTICE);
  assert.equal(threadNotice.sessionId, 'thread_1');
  assert.equal(threadNotice.visible, false);

  const turnStarted = mapCodexAppServerNotification({
    method: 'turn/started',
    params: { threadId: 'thread_1', turnId: 'turn_1' }
  });
  assert.equal(turnStarted.type, conversationEventTypes.SYSTEM_NOTICE);
  assert.equal(turnStarted.noticeKind, 'codex_turn_started');

  const assistant = mapCodexAppServerNotification({
    method: 'item/completed',
    params: {
      item: { id: 'msg_1', type: 'agentMessage', text: 'hello', phase: null, memoryCitation: null },
      threadId: 'thread_1',
      turnId: 'turn_1',
      completedAtMs: 1710000000000
    }
  });
  assert.equal(assistant.type, conversationEventTypes.ASSISTANT_MESSAGE);
  assert.equal(assistant.text, 'hello');

  const commandStarted = mapCodexAppServerNotification({
    method: 'item/started',
    params: {
      item: {
        id: 'cmd_1',
        type: 'commandExecution',
        command: 'dir',
        cwd: 'D:\\Repo',
        processId: null,
        source: 'exec',
        status: 'inProgress',
        commandActions: [],
        aggregatedOutput: null,
        exitCode: null,
        durationMs: null
      },
      threadId: 'thread_1',
      turnId: 'turn_1',
      startedAtMs: 1710000000000
    }
  });
  assert.equal(commandStarted.type, conversationEventTypes.TOOL_STARTED);
  assert.equal(commandStarted.toolUseId, 'cmd_1');

  const commandDelta = mapCodexAppServerNotification({
    method: 'item/commandExecution/outputDelta',
    params: {
      threadId: 'thread_1',
      turnId: 'turn_1',
      itemId: 'cmd_1',
      delta: 'partial output'
    }
  });
  assert.deepEqual({
    type: commandDelta.type,
    toolUseId: commandDelta.toolUseId,
    toolName: commandDelta.toolName,
    text: commandDelta.text
  }, {
    type: conversationEventTypes.TOOL_DELTA,
    toolUseId: 'cmd_1',
    toolName: 'command_execution',
    text: 'partial output'
  });

  const commandCompleted = mapCodexAppServerNotification({
    method: 'item/completed',
    params: {
      item: {
        id: 'cmd_1',
        type: 'commandExecution',
        command: 'dir',
        cwd: 'D:\\Repo',
        processId: null,
        source: 'exec',
        status: 'completed',
        commandActions: [],
        aggregatedOutput: 'done',
        exitCode: 0,
        durationMs: 12
      },
      threadId: 'thread_1',
      turnId: 'turn_1',
      completedAtMs: 1710000000012
    }
  });
  assert.equal(commandCompleted.type, conversationEventTypes.TOOL_COMPLETED);
  assert.equal(commandCompleted.text, 'done');
  assert.equal(commandCompleted.exitCode, 0);

  const declined = mapCodexAppServerNotification({
    method: 'item/completed',
    params: {
      item: {
        id: 'cmd_2',
        type: 'commandExecution',
        command: 'write',
        cwd: 'D:\\Repo',
        processId: null,
        source: 'exec',
        status: 'declined',
        commandActions: [],
        aggregatedOutput: 'rejected',
        exitCode: null,
        durationMs: 1
      },
      threadId: 'thread_1',
      turnId: 'turn_1',
      completedAtMs: 1710000000013
    }
  });
  assert.equal(declined.type, conversationEventTypes.SYSTEM_NOTICE);
  assert.equal(declined.noticeKind, 'codex_policy_blocked');

  const fileChange = mapCodexAppServerNotification({
    method: 'item/completed',
    params: {
      item: {
        id: 'file_1',
        type: 'fileChange',
        status: 'completed',
        changes: [{ path: 'D:\\Repo\\src\\a.js', kind: 'add', diff: '+hello' }]
      },
      threadId: 'thread_1',
      turnId: 'turn_1',
      completedAtMs: 1710000000014
    }
  }, { workspacePath: 'D:\\Repo' });
  assert.equal(fileChange.type, conversationEventTypes.SYSTEM_NOTICE);
  assert.equal(fileChange.noticeKind, 'codex_file_change');
  assert.equal(fileChange.changes[0].path, 'src/a.js');

  const mcpCompleted = mapCodexAppServerNotification({
    method: 'item/completed',
    params: {
      item: {
        id: 'mcp_1',
        type: 'mcpToolCall',
        server: 'codegraph',
        tool: 'codegraph_search',
        status: 'completed',
        arguments: { query: 'mapCodexEvent' },
        pluginId: null,
        result: { content: [{ type: 'text', text: 'found' }] },
        error: null,
        durationMs: 10
      },
      threadId: 'thread_1',
      turnId: 'turn_1',
      completedAtMs: 1710000000015
    }
  });
  assert.equal(mcpCompleted.type, conversationEventTypes.TOOL_COMPLETED);
  assert.equal(mcpCompleted.toolName, 'codegraph.codegraph_search');
  assert.equal(mcpCompleted.text, 'found');

  const plan = mapCodexAppServerNotification({
    method: 'turn/plan/updated',
    params: {
      threadId: 'thread_1',
      turnId: 'turn_1',
      explanation: null,
      plan: [
        { step: 'Inspect repo', status: 'completed' },
        { step: 'Run tests', status: 'inProgress' },
        { step: 'Summarize', status: 'pending' }
      ]
    }
  });
  assert.equal(plan.type, conversationEventTypes.TASK_PROGRESS_UPDATED);
  assert.equal(plan.taskId, 'turn_1');
  assert.deepEqual(plan.items.map((item) => item.status), ['completed', 'in_progress', 'pending']);

  const failed = mapCodexAppServerNotification({
    method: 'turn/completed',
    params: {
      threadId: 'thread_1',
      turn: {
        id: 'turn_1',
        items: [],
        itemsView: 'full',
        status: 'failed',
        error: { message: 'bad model', codexErrorInfo: null, additionalDetails: null },
        startedAt: 1,
        completedAt: 2,
        durationMs: 1000
      }
    }
  });
  assert.equal(failed.type, conversationEventTypes.RUN_ERROR);
  assert.equal(failed.message, 'bad model');

  const interrupted = mapCodexAppServerNotification({
    method: 'turn/completed',
    params: {
      threadId: 'thread_1',
      turn: {
        id: 'turn_cancelled',
        items: [],
        itemsView: 'full',
        status: 'interrupted',
        error: null,
        startedAt: 1,
        completedAt: 2,
        durationMs: 1000
      }
    }
  });
  assert.equal(interrupted.type, conversationEventTypes.CONVERSATION_CANCELLED);

  const completed = mapCodexAppServerNotification({
    method: 'turn/completed',
    params: {
      threadId: 'thread_1',
      turn: {
        id: 'turn_2',
        items: [],
        itemsView: 'full',
        status: 'completed',
        error: null,
        startedAt: 1,
        completedAt: 2,
        durationMs: 1000
      }
    }
  });
  assert.equal(completed.type, conversationEventTypes.CONVERSATION_COMPLETED);
});

test('Codex capability detection allows slow Windows npm shim startup', () => {
  const adapter = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_cmd, args, options = {}) => {
      if ((options.timeout || 0) < 10000) {
        return { status: null, stdout: '', stderr: '', error: Object.assign(new Error('timeout'), { code: 'ETIMEDOUT' }) };
      }
      return fakeCodexConversationSpawnSync(_cmd, args, options);
    }
  });

  const capability = adapter.detectCapabilities();
  assert.equal(capability.available, true);
  assert.equal(capability.version, 'codex-cli 0.130.0');
});

test('Codex image capability detection requires image flags for exec and resume', () => {
  const adapter = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
      if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec resume\n--json\n--model <MODEL>\n--image <PATH>', stderr: '' };
      if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec\n--json\n--model <MODEL>\n--image <PATH>', stderr: '' };
      return { status: 0, stdout: '', stderr: '' };
    }
  });

  const capability = adapter.detectCapabilities();

  assert.equal(capability.available, true);
  assert.equal(capability.canSelectModel, true);
  assert.equal(capability.capabilities.attachments.image, 'native');
  assert.equal(adapter.getCapabilities().attachments.image, 'native');
});

test('Codex image capability detection keeps image unsupported when exec or resume lacks image flag', () => {
  function adapterWithHelp({ execHelp, resumeHelp }) {
    return new CodexConversationAdapter({
      cliResolverOptions: { platform: 'linux' },
      spawnSyncFn: (_cmd, args) => {
        if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
        if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: resumeHelp, stderr: '' };
        if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: execHelp, stderr: '' };
        return { status: 0, stdout: '', stderr: '' };
      }
    });
  }
  const execSupportsImage = adapterWithHelp({
    execHelp: 'Usage: codex exec\n--json\n--model <MODEL>\n--image <PATH>',
    resumeHelp: 'Usage: codex exec resume\n--json\n--model <MODEL>'
  });
  const resumeSupportsImage = adapterWithHelp({
    execHelp: 'Usage: codex exec\n--json\n--model <MODEL>',
    resumeHelp: 'Usage: codex exec resume\n--json\n--model <MODEL>\n--image <PATH>'
  });

  const execOnlyCapability = execSupportsImage.detectCapabilities();
  const resumeOnlyCapability = resumeSupportsImage.detectCapabilities();

  assert.equal(execOnlyCapability.capabilities.attachments.image, 'unsupported');
  assert.equal(execSupportsImage.getCapabilities().attachments.image, 'unsupported');
  assert.equal(resumeOnlyCapability.capabilities.attachments.image, 'unsupported');
  assert.equal(resumeSupportsImage.getCapabilities().attachments.image, 'unsupported');
});

test('Codex model selection capability follows exec help model flag', () => {
  const withModel = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
      if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec resume\n--json\n--model <MODEL>', stderr: '' };
      if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec\n--json\n--model <MODEL>', stderr: '' };
      return { status: 0, stdout: '', stderr: '' };
    }
  });
  const withoutResumeModel = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
      if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec resume\n--json', stderr: '' };
      if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec\n--json\n--model <MODEL>', stderr: '' };
      return { status: 0, stdout: '', stderr: '' };
    }
  });
  const withoutModel = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
      if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec resume\n--json', stderr: '' };
      if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec\n--json', stderr: '' };
      return { status: 0, stdout: '', stderr: '' };
    }
  });

  withModel.detectCapabilities();
  withoutResumeModel.detectCapabilities();
  withoutModel.detectCapabilities();

  assert.equal(withModel.getModelCapability().canSelectModel, true);
  assert.equal(withoutResumeModel.getModelCapability().canSelectModel, false);
  assert.equal(withoutModel.getModelCapability().canSelectModel, false);
});

test('Codex conversation adapter adds model flag only when supported', async () => {
  const spawnCalls = [];
  const modelAwareSpawnSync = (_cmd, args) => {
    if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
    if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec resume\n--json\n--model <MODEL>', stderr: '' };
    if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec\n--json\n--model <MODEL>', stderr: '' };
    return { status: 0, stdout: '', stderr: '' };
  };
  const execOnlyModelSpawnSync = (_cmd, args) => {
    if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
    if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec resume\n--json', stderr: '' };
    if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec\n--json\n--model <MODEL>', stderr: '' };
    return { status: 0, stdout: '', stderr: '' };
  };
  const supported = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: modelAwareSpawnSync,
    spawnFn: (_cmd, args, options) => {
      const child = fakeCodexChild();
      spawnCalls.push({ adapter: 'supported', args, options, child });
      return child;
    }
  });
  const unsupported = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeCodexConversationSpawnSync,
    spawnFn: (_cmd, args, options) => {
      const child = fakeCodexChild();
      spawnCalls.push({ adapter: 'unsupported', args, options, child });
      return child;
    }
  });
  const execOnlyModel = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: execOnlyModelSpawnSync,
    spawnFn: (_cmd, args, options) => {
      const child = fakeCodexChild();
      spawnCalls.push({ adapter: 'execOnlyModel', args, options, child });
      return child;
    }
  });

  const execHandle = await supported.startConversation({ conversationId: 'conv_codex_model_exec', workspacePath: 'D:\\Repo', model: 'gpt-5.5', onEvent: () => {} });
  await execHandle.sendUserMessage('first');
  const resumeHandle = await supported.startConversation({ conversationId: 'conv_codex_model_resume', workspacePath: 'D:\\Repo', sessionId: 'thread_1', model: 'gpt-5.5', onEvent: () => {} });
  await resumeHandle.sendUserMessage('second');
  const unsupportedHandle = await unsupported.startConversation({ conversationId: 'conv_codex_model_unsupported', workspacePath: 'D:\\Repo', model: 'gpt-5.5', onEvent: () => {} });
  await unsupportedHandle.sendUserMessage('third');
  const execOnlyResumeHandle = await execOnlyModel.startConversation({ conversationId: 'conv_codex_model_exec_only_resume', workspacePath: 'D:\\Repo', sessionId: 'thread_2', model: 'gpt-5.5', onEvent: () => {} });
  await execOnlyResumeHandle.sendUserMessage('fourth');

  const supportedExecArgs = spawnCalls[0].args;
  const supportedResumeArgs = spawnCalls[1].args;
  const unsupportedArgs = spawnCalls[2].args;
  const execOnlyResumeArgs = spawnCalls[3].args;
  assert.deepEqual(supportedExecArgs.slice(supportedExecArgs.indexOf('--model'), supportedExecArgs.indexOf('--model') + 2), ['--model', 'gpt-5.5']);
  assert.deepEqual(supportedResumeArgs.slice(supportedResumeArgs.indexOf('--model'), supportedResumeArgs.indexOf('--model') + 2), ['--model', 'gpt-5.5']);
  assert.equal(unsupportedArgs.includes('--model'), false);
  assert.equal(execOnlyResumeArgs.includes('--model'), false);
});

test('Codex registry adapter exposes model selection capability from production path', async () => {
  const registry = new AdapterRegistry([
    createCodexAdapter({
      explicitEnabled: true,
      cliResolverOptions: { platform: 'linux' },
      spawnSyncFn: (_cmd, args) => {
        if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
        if (args[0] === 'exec' && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec\n--json\n--model <MODEL>', stderr: '' };
        if (args.includes('--help')) return { status: 0, stdout: 'Usage: codex\nexec', stderr: '' };
        return { status: 1, stdout: '', stderr: 'unexpected probe' };
      }
    })
  ]);

  const [codex] = await registry.listCapabilities();

  assert.equal(codex.adapter, 'codex');
  assert.equal(codex.available, true);
  assert.equal(codex.canSelectModel, true);
});

test('Codex conversation adapter resumes captured thread with authorized workspace cwd', async () => {
  const spawnCalls = [];
  const adapter = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeCodexConversationSpawnSync,
    spawnFn: (_cmd, args, options) => {
      const child = fakeCodexChild();
      spawnCalls.push({ args, options, child });
      return child;
    }
  });

  const handle = await adapter.startConversation({ conversationId: 'conv_codex_resume', workspacePath: 'D:\\Authorized\\Repo', permissionMode: 'default', sessionId: 'thread_1', onEvent: () => {} });
  await handle.sendUserMessage('second');

  assert.deepEqual(spawnCalls[0].args.slice(0, 7), ['--ask-for-approval', 'on-request', '-c', 'tool_timeout_sec=600', 'exec', 'resume', '--json']);
  assert.equal(spawnCalls[0].args.includes('-C'), false);
  assert.equal(spawnCalls[0].args.includes('--cd'), false);
  assert.equal(spawnCalls[0].options.cwd, 'D:\\Authorized\\Repo');
  assert.equal(spawnCalls[0].args.includes('--skip-git-repo-check'), true);
  assert.equal(spawnCalls[0].args[8], 'thread_1');
  assert.equal(spawnCalls[0].args[9], 'second');
  spawnCalls[0].child.emit('exit', 0, null);
});

test('Codex event mapper normalizes thread, assistant, tool, file changes, declined, unknown, and failed events', () => {
  const threadStarted = mapCodexEvent({ type: 'thread.started', thread_id: 'thread_a' });
  assert.equal(threadStarted.sessionId, 'thread_a');
  assert.equal(threadStarted.visible, false);
  const turnStarted = mapCodexEvent({ type: 'turn.started' });
  assert.equal(turnStarted.type, 'system.notice');
  assert.equal(turnStarted.noticeKind, 'codex_turn_started');
  assert.equal(turnStarted.visible, false);
  const assistant = mapCodexEvent({ type: 'item.completed', item: { id: 'item_1', type: 'agent_message', text: 'hello' } });
  assert.equal(assistant.type, 'assistant.message');
  assert.equal(assistant.turnFinal, false);
  assert.equal(mapCodexEvent({ type: 'item.started', item: { id: 'cmd_1', type: 'command_execution', command: 'dir', status: 'in_progress' } }).type, 'tool.started');
  const completedCommand = mapCodexEvent({ type: 'item.completed', item: { id: 'cmd_1', type: 'command_execution', command: 'dir', aggregated_output: 'done', exit_code: 0, status: 'completed' } });
  assert.equal(completedCommand.type, 'tool.completed');
  assert.equal(completedCommand.text, 'done');
  assert.equal(completedCommand.exitCode, 0);
  const fileChange = mapCodexEvent({
    type: 'item.completed',
    item: {
      id: 'item_96',
      type: 'file_change',
      changes: [
        { path: 'D:\\AIProject\\vibe-coding\\daemon\\src\\conversation-notes.js', kind: 'add' }
      ],
      status: 'completed'
    }
  }, { workspacePath: 'D:\\AIProject\\vibe-coding' });
  assert.equal(fileChange.type, 'system.notice');
  assert.equal(fileChange.noticeKind, 'codex_file_change');
  assert.equal(fileChange.visible, true);
  assert.equal(fileChange.changes[0].path, 'daemon/src/conversation-notes.js');
  assert.match(fileChange.text, /added daemon\/src\/conversation-notes\.js/);
  const declined = mapCodexEvent({ type: 'item.completed', item: { id: 'cmd_1', type: 'command_execution', command: 'write', aggregated_output: 'rejected: blocked by policy', status: 'declined' } });
  assert.equal(declined.type, 'system.notice');
  assert.equal(declined.noticeKind, 'codex_policy_blocked');
  assert.equal(mapCodexEvent({ type: 'turn.failed', error: { message: 'bad model' } }).type, 'run.error');
  const unknown = mapCodexEvent({ type: 'new.future.event', value: 1 });
  assert.equal(unknown.type, 'system.notice');
  assert.equal(unknown.noticeKind, 'codex_unknown_event');
  assert.equal(unknown.visible, false);
});

test('Codex file change mapper enriches completed changes with git diff previews', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { spawnSync } = require('node:child_process');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-file-change-diff-'));
  const gitAvailable = spawnSync('git', ['--version'], { encoding: 'utf8' });
  if (gitAvailable.status !== 0) return;
  const runGit = (args) => spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  if (runGit(['init']).status !== 0) return;
  fs.writeFileSync(path.join(root, 'example.txt'), 'old line\n', 'utf8');
  if (runGit(['add', 'example.txt']).status !== 0) return;
  if (runGit(['-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', 'init']).status !== 0) return;
  fs.writeFileSync(path.join(root, 'example.txt'), 'old line\nnew line\n', 'utf8');

  const event = mapCodexEvent({
    type: 'item.completed',
    item: {
      id: 'item_diff',
      type: 'file_change',
      changes: [{ path: path.join(root, 'example.txt'), kind: 'update' }],
      status: 'completed'
    }
  }, { workspacePath: root, includeFileChangeDiff: true });

  assert.equal(event.noticeKind, 'codex_file_change');
  assert.equal(event.changes[0].path, 'example.txt');
  assert.match(event.changes[0].diff, /@@/);
  assert.match(event.changes[0].diff, /\+new line/);
});

test('Codex mapper normalizes MCP tool calls into visible tool events', () => {
  const started = mapCodexEvent({
    type: 'item.started',
    item: {
      id: 'mcp_1',
      type: 'mcp_tool_call',
      server: 'codegraph',
      tool: 'codegraph_search',
      arguments: { query: 'fetchConversationEvents', limit: 20 },
      status: 'in_progress'
    }
  });
  assert.equal(started.type, 'tool.started');
  assert.equal(started.toolUseId, 'mcp_1');
  assert.equal(started.toolName, 'codegraph.codegraph_search');
  assert.equal(started.input.server, 'codegraph');
  assert.equal(started.input.tool, 'codegraph_search');
  assert.match(started.summary, /fetchConversationEvents/);

  const completed = mapCodexEvent({
    type: 'item.completed',
    item: {
      id: 'mcp_1',
      type: 'mcp_tool_call',
      server: 'codegraph',
      tool: 'codegraph_search',
      result: {
        content: [
          { type: 'text', text: '## Search Results\nfetchConversationEvents' }
        ]
      },
      status: 'completed'
    }
  });
  assert.equal(completed.type, 'tool.completed');
  assert.equal(completed.toolUseId, 'mcp_1');
  assert.equal(completed.toolName, 'codegraph.codegraph_search');
  assert.equal(completed.isError, false);
  assert.match(completed.text, /Search Results/);

  const failed = mapCodexEvent({
    type: 'item.completed',
    item: {
      id: 'mcp_2',
      type: 'mcp_tool_call',
      server: 'codegraph',
      tool: 'codegraph_search',
      error: { message: 'server unavailable' },
      status: 'failed'
    }
  });
  assert.equal(failed.type, 'tool.completed');
  assert.equal(failed.isError, true);
  assert.match(failed.text, /server unavailable/);
});

test('conversation replay remaps legacy Codex unknown MCP events', () => {
  const now = new Date('2026-05-23T00:00:00.000Z');
  const eventStore = new ConversationEventStore({ now: () => now });
  const device = { id: 'device_1' };
  const manager = new ConversationManager({
    workspaces: {
      getAuthorized() {
        return { id: 'workspace_1', path: process.cwd() };
      }
    },
    eventStore,
    auditLog: new AuditLog(),
    adapters: new Map([['codex', { capabilities: {} }]]),
    now: () => now
  });
  const conversation = manager.createConversation(
    { workspaceId: 'workspace_1', adapter: 'codex' },
    device
  );

  eventStore.append(conversation.id, 'system.notice', {
    text: 'Codex event: item.started',
    noticeKind: 'codex_unknown_event',
    visible: false,
    raw: {
      type: 'item.started',
      item: {
        id: 'mcp_legacy',
        type: 'mcp_tool_call',
        server: 'codegraph',
        tool: 'codegraph_search',
        arguments: { query: 'mapCodexEvent' },
        status: 'in_progress'
      }
    }
  });
  eventStore.append(conversation.id, 'system.notice', {
    text: 'Codex event: item.completed',
    noticeKind: 'codex_unknown_event',
    visible: false,
    raw: {
      type: 'item.completed',
      item: {
        id: 'mcp_legacy',
        type: 'mcp_tool_call',
        server: 'codegraph',
        tool: 'codegraph_search',
        result: {
          content: [{ type: 'text', text: '## Search Results\nmapCodexEvent' }]
        },
        status: 'completed'
      }
    }
  });

  const replayed = manager.listEvents(conversation.id, 1, device);
  const started = replayed.find((event) => event.toolUseId === 'mcp_legacy' && event.type === 'tool.started');
  const completed = replayed.find((event) => event.toolUseId === 'mcp_legacy' && event.type === 'tool.completed');
  assert.ok(started);
  assert.equal(started.toolName, 'codegraph.codegraph_search');
  assert.equal(started.seq, 2);
  assert.ok(completed);
  assert.match(completed.text, /Search Results/);
  assert.equal(completed.seq, 3);
});

test('Codex mapper normalizes observed todo_list items into task progress', () => {
  const event = mapCodexEvent({
    type: 'item.started',
    item: {
      id: 'item_1',
      type: 'todo_list',
      items: [
        { text: 'Inspect repo', completed: true },
        { text: 'Run tests', completed: false },
        { text: 'Summarize findings', completed: false }
      ]
    }
  });

  assert.equal(event.type, 'task.progress.updated');
  assert.equal(event.taskId, 'item_1');
  assert.equal(event.source, 'codex');
  assert.equal(event.completedCount, 1);
  assert.equal(event.totalCount, 3);
  assert.deepEqual(event.items.map((item) => item.title), ['Inspect repo', 'Run tests', 'Summarize findings']);
  assert.deepEqual(event.items.map((item) => item.status), ['completed', 'pending', 'pending']);
  assert.match(event.updatedAt, /^\d{4}-\d{2}-\d{2}T/);
});

test('Codex mapper normalizes compatibility todo_list todos statuses', () => {
  const event = mapCodexEvent({
    type: 'item.updated',
    item: {
      id: 'item_1',
      type: 'todo_list',
      todos: [
        { content: 'Inspect repo', status: 'completed' },
        { content: 'Run tests', status: 'in_progress' },
        { content: 'Summarize findings', status: 'pending' }
      ]
    }
  });

  assert.equal(event.type, 'task.progress.updated');
  assert.deepEqual(event.items.map((item) => item.title), ['Inspect repo', 'Run tests', 'Summarize findings']);
  assert.deepEqual(event.items.map((item) => item.status), ['completed', 'in_progress', 'pending']);
  assert.equal(event.completedCount, 1);
  assert.equal(event.totalCount, 3);
});

test('Codex mapper treats completed todo_list event as terminal progress', () => {
  const event = mapCodexEvent({
    type: 'item.completed',
    item: {
      id: 'item_1',
      type: 'todo_list',
      items: [
        { text: 'Inspect repo', completed: false },
        { text: 'Run tests', completed: false },
        { text: 'Summarize findings', completed: false }
      ]
    }
  });

  assert.equal(event.type, 'task.progress.updated');
  assert.deepEqual(event.items.map((item) => item.status), ['completed', 'completed', 'completed']);
  assert.equal(event.completedCount, 3);
  assert.equal(event.totalCount, 3);
});

test('Codex mapper drops malformed todo_list payloads', () => {
  assert.equal(mapCodexEvent({ type: 'item.started', item: { id: 'item_1', type: 'todo_list' } }), null);
  assert.equal(mapCodexEvent({ type: 'item.updated', item: { id: 'item_1', type: 'todo_list', items: [] } }), null);
  assert.equal(mapCodexEvent({ type: 'item.completed', item: { id: 'item_1', type: 'todo_list', items: [{ completed: true }] } }), null);
});

test('Codex model discovery prefers project config over user config and catalog entries', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-model-discovery-'));
  const homeDir = path.join(root, 'home');
  const workspacePath = path.join(root, 'workspace');
  fs.mkdirSync(path.join(homeDir, '.codex'), { recursive: true });
  fs.mkdirSync(path.join(workspacePath, '.codex'), { recursive: true });
  const catalogPath = path.join(workspacePath, '.codex', 'models.json');
  fs.writeFileSync(path.join(homeDir, '.codex', 'config.toml'), 'model = "gpt-user"\nmodel_catalog_json = "ignored.json"\n');
  fs.writeFileSync(catalogPath, JSON.stringify({ models: [{ id: 'gpt-project' }, { id: 'gpt-catalog', label: 'Catalog model' }] }));
  fs.writeFileSync(path.join(workspacePath, '.codex', 'config.toml'), `model = "gpt-project"\nmodel_catalog_json = "${catalogPath.replace(/\\/g, '\\\\')}"\n`);

  const discovered = discoverConfiguredModels({ adapter: 'codex', homeDir, workspacePath, env: {} });

  assert.equal(discovered.selectedModel, 'gpt-project');
  assert.equal(discovered.canSelectModel, false);
  assert.deepEqual(discovered.models.map((model) => model.id), ['gpt-project', 'gpt-catalog']);
  assert.deepEqual(discovered.models.map((model) => model.source), ['codex_config', 'codex_catalog']);
  assert.equal(discovered.models[0].selected, true);
});

test('Codex model discovery preserves catalog capability metadata', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-model-capability-catalog-'));
  const homeDir = path.join(root, 'home');
  const workspacePath = path.join(root, 'workspace');
  fs.mkdirSync(path.join(workspacePath, '.codex'), { recursive: true });
  const catalogPath = path.join(workspacePath, '.codex', 'models.json');
  fs.writeFileSync(catalogPath, JSON.stringify({
    models: [
      {
        id: 'gpt-image',
        label: 'GPT image',
        input_modalities: ['text', 'image'],
        attachments: {
          image: 'native',
          textDocument: 'unsupported'
        }
      }
    ]
  }));
  fs.writeFileSync(path.join(workspacePath, '.codex', 'config.toml'), `model_catalog_json = "${catalogPath.replace(/\\/g, '\\\\')}"\n`);

  const discovered = discoverConfiguredModels({ adapter: 'codex', homeDir, workspacePath, env: {} });

  assert.deepEqual(discovered.models, [
    {
      id: 'gpt-image',
      label: 'GPT image',
      source: 'codex_catalog',
      selected: true,
      inputModalities: ['text', 'image'],
      attachments: {
        image: 'native',
        textDocument: 'unsupported'
      }
    }
  ]);
});

test('model discovery ignores unsupported TOML syntax', () => {
  const parsed = parseTomlScalarConfig([
    'model = "gpt-supported"',
    'inline = { model = "gpt-inline" }',
    'number = 42',
    'multi = """gpt-multiline"""',
    '[shell_environment_policy.set]',
    'ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-env"'
  ].join('\n'));

  assert.equal(parsed.model, 'gpt-supported');
  assert.equal(parsed.inline, undefined);
  assert.equal(parsed.number, undefined);
  assert.equal(parsed.multi, undefined);
  assert.deepEqual(parsed.shell_environment_policy.set, { ANTHROPIC_DEFAULT_SONNET_MODEL: 'claude-sonnet-env' });
});

test('model discovery TOML parser rejects prototype pollution sections', () => {
  try {
    const parsed = parseTomlScalarConfig([
      '[__proto__]',
      'polluted = "yes"',
      '[shell_environment_policy.set]',
      'ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus"'
    ].join('\n'));

    assert.equal({}.polluted, undefined);
    assert.equal(parsed.polluted, undefined);
    assert.deepEqual(parsed.shell_environment_policy.set, { ANTHROPIC_DEFAULT_OPUS_MODEL: 'claude-opus' });
  } finally {
    delete Object.prototype.polluted;
  }
});

test('model discovery disable switch returns empty discovery case-insensitively', () => {
  const discovered = discoverConfiguredModels({
    adapter: 'claude',
    env: {
      VIBE_DISABLE_MODEL_DISCOVERY: 'TRUE',
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'claude-opus'
    }
  });

  assert.deepEqual(discovered, { models: [], selectedModel: null, canSelectModel: false });
});

test('Codex model discovery ignores oversize catalog files', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-model-oversize-'));
  const homeDir = path.join(root, 'home');
  const workspacePath = path.join(root, 'workspace');
  fs.mkdirSync(path.join(workspacePath, '.codex'), { recursive: true });
  const catalogPath = path.join(workspacePath, '.codex', 'models.json');
  fs.writeFileSync(catalogPath, Buffer.alloc(MODEL_CATALOG_MAX_BYTES + 1, 'x'));
  fs.writeFileSync(path.join(workspacePath, '.codex', 'config.toml'), `model = "gpt-project"\nmodel_catalog_json = "${catalogPath.replace(/\\/g, '\\\\')}"\n`);

  const discovered = discoverConfiguredModels({ adapter: 'codex', homeDir, workspacePath, env: {} });

  assert.equal(discovered.selectedModel, 'gpt-project');
  assert.deepEqual(discovered.models.map((model) => model.id), ['gpt-project']);
});

test('Claude model discovery de-duplicates environment defaults by priority', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-env-model-discovery-'));
  const discovered = discoverConfiguredModels({
    adapter: 'claude',
    homeDir: path.join(root, 'home'),
    workspacePath: path.join(root, 'workspace'),
    claudeSettingsPath: path.join(os.tmpdir(), 'missing-claude-settings.json'),
    env: {
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'claude-duplicate',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'claude-duplicate',
      ANTHROPIC_DEFAULT_HAIKU_MODEL: 'claude-haiku'
    }
  });

  assert.equal(discovered.selectedModel, 'claude-duplicate');
  assert.deepEqual(discovered.models.map((model) => model.id), ['claude-duplicate', 'claude-haiku']);
  assert.deepEqual(discovered.models.map((model) => model.source), ['claude_env', 'claude_env']);
  assert.equal(discovered.models[0].selected, true);
});

test('Claude model discovery falls back to user CLI default when settings has no model list', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-settings-model-'));
  const homeDir = path.join(root, 'home');
  const workspacePath = path.join(root, 'workspace');
  fs.mkdirSync(path.join(homeDir, '.claude'), { recursive: true });
  fs.mkdirSync(workspacePath, { recursive: true });
  fs.writeFileSync(
    path.join(homeDir, '.claude', 'settings.json'),
    JSON.stringify({ model: 'claude-opus-4-6' })
  );

  const discovered = discoverConfiguredModels({ adapter: 'claude', homeDir, workspacePath, env: {} });

  assert.equal(discovered.selectedModel, 'claude-opus-4-6');
  assert.deepEqual(discovered.models.map((model) => model.id), ['claude-opus-4-6']);
  assert.deepEqual(discovered.models.map((model) => model.source), ['cli_default']);
  assert.equal(discovered.models[0].selected, true);
});

test('Claude model discovery orders explicit config before system environment', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-config-models-'));
  const homeDir = path.join(root, 'home');
  const workspacePath = path.join(root, 'workspace');
  fs.mkdirSync(path.join(homeDir, '.claude'), { recursive: true });
  fs.mkdirSync(path.join(workspacePath, '.claude'), { recursive: true });
  fs.mkdirSync(workspacePath, { recursive: true });
  fs.writeFileSync(
    path.join(homeDir, '.claude', 'settings.json'),
    JSON.stringify({
      model: 'user-sonnet',
      env: {
        ANTHROPIC_DEFAULT_OPUS_MODEL: 'user-opus',
        ANTHROPIC_DEFAULT_SONNET_MODEL: 'user-sonnet',
        ANTHROPIC_DEFAULT_HAIKU_MODEL: 'user-haiku'
      }
    })
  );
  fs.writeFileSync(
    path.join(workspacePath, '.claude', 'settings.json'),
    JSON.stringify({
      model: 'project-sonnet',
      env: {
        ANTHROPIC_DEFAULT_OPUS_MODEL: 'project-opus',
        ANTHROPIC_DEFAULT_SONNET_MODEL: 'project-sonnet',
        ANTHROPIC_DEFAULT_HAIKU_MODEL: 'project-haiku'
      }
    })
  );
  fs.writeFileSync(
    path.join(homeDir, '.claude.json'),
    JSON.stringify({
      projects: {
        [workspacePath.replace(/\\/g, '/')]: {
          lastModelUsage: {
            'history-only-model': { inputTokens: 1 }
          }
        }
      }
    })
  );

  const discovered = discoverConfiguredModels({
    adapter: 'claude',
    homeDir,
    workspacePath,
    env: {
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'system-opus',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'system-sonnet',
      ANTHROPIC_DEFAULT_HAIKU_MODEL: 'system-haiku'
    }
  });

  assert.equal(discovered.selectedModel, 'user-sonnet');
  assert.deepEqual(discovered.models.map((model) => model.id), [
    'user-opus',
    'user-sonnet',
    'user-haiku',
    'project-opus',
    'project-sonnet',
    'project-haiku',
    'system-opus',
    'system-sonnet',
    'system-haiku'
  ]);
  assert.deepEqual(discovered.models.map((model) => model.source), [
    'claude_config',
    'claude_config',
    'claude_config',
    'claude_config',
    'claude_config',
    'claude_config',
    'claude_env',
    'claude_env',
    'claude_env'
  ]);
  assert.deepEqual(discovered.models.map((model) => model.selected), [
    false,
    true,
    false,
    false,
    false,
    false,
    false,
    false,
    false
  ]);
});

test('Claude model discovery uses project settings before system environment when user list is absent', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-project-config-models-'));
  const homeDir = path.join(root, 'home');
  const workspacePath = path.join(root, 'workspace');
  fs.mkdirSync(path.join(homeDir, '.claude'), { recursive: true });
  fs.mkdirSync(path.join(workspacePath, '.claude'), { recursive: true });
  fs.writeFileSync(
    path.join(homeDir, '.claude', 'settings.json'),
    JSON.stringify({})
  );
  fs.writeFileSync(
    path.join(workspacePath, '.claude', 'settings.json'),
    JSON.stringify({
      model: 'project-sonnet',
      env: {
        ANTHROPIC_DEFAULT_OPUS_MODEL: 'project-opus',
        ANTHROPIC_DEFAULT_SONNET_MODEL: 'project-sonnet'
      }
    })
  );

  const discovered = discoverConfiguredModels({
    adapter: 'claude',
    homeDir,
    workspacePath,
    env: {
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'system-opus',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'system-sonnet'
    }
  });

  assert.equal(discovered.selectedModel, 'project-sonnet');
  assert.deepEqual(discovered.models.map((model) => model.id), [
    'project-opus',
    'project-sonnet',
    'system-opus',
    'system-sonnet'
  ]);
  assert.deepEqual(discovered.models.map((model) => model.source), [
    'claude_config',
    'claude_config',
    'claude_env',
    'claude_env'
  ]);
});

test('Codex mapper truncates large aggregated output with marker', () => {
  const event = mapCodexEvent({ type: 'item.completed', item: { id: 'cmd_big', type: 'command_execution', command: 'dump', aggregated_output: 'abcdef', status: 'completed' } }, { maxAggregatedOutputBytes: 3 });
  assert.equal(event.type, 'tool.completed');
  assert.equal(event.text, 'abc');
  assert.equal(event.truncated, true);
});

test('Codex conversation cancel kills process tree and reports cancellation only', async () => {
  const child = fakeCodexChild();
  const killed = [];
  const events = [];
  const adapter = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeCodexConversationSpawnSync,
    spawnFn: () => child,
    killProcessTreeFn: async (target) => {
      killed.push(target.pid);
    }
  });

  const handle = await adapter.startConversation({ conversationId: 'conv_codex_cancel', workspacePath: 'D:\\Repo', onEvent: (event) => events.push(event) });
  await handle.sendUserMessage('long task');
  await handle.cancel();
  child.emit('exit', 1, null);

  assert.deepEqual(killed, [12345]);
  assert.equal(events.some((event) => event.type === 'conversation.cancelled'), true);
  assert.equal(events.some((event) => event.type === 'run.error'), false);
});

test('Codex conversation treats stderr after JSONL as warning instead of startup failure', async () => {
  const child = fakeCodexChild();
  const events = [];
  const adapter = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeCodexConversationSpawnSync,
    spawnFn: () => child
  });

  const handle = await adapter.startConversation({ conversationId: 'conv_codex_stderr', workspacePath: 'D:\\Repo', onEvent: (event) => events.push(event) });
  await handle.sendUserMessage('warn');
  child.stdout.emit('data', `${JSON.stringify({ type: 'thread.started', thread_id: 'thread_warn' })}\n`);
  child.stderr.emit('data', 'stderr warning\n');
  child.emit('exit', 2, null);

  assert.equal(events.some((event) => event.type === 'protocol.warning' && event.text.includes('stderr warning')), true);
  const error = events.find((event) => event.type === 'run.error');
  assert.equal(error.exitCode, 2);
  assert.equal(error.message, undefined);
});

test('Codex conversation ignores invalid stdout noise after turn completion', async () => {
  const child = fakeCodexChild();
  const events = [];
  const adapter = new CodexConversationAdapter({
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: fakeCodexConversationSpawnSync,
    spawnFn: () => child
  });

  const handle = await adapter.startConversation({ conversationId: 'conv_codex_trailing_noise', workspacePath: 'D:\\Repo', onEvent: (event) => events.push(event) });
  await handle.sendUserMessage('short');
  child.stdout.emit('data', `${JSON.stringify({ type: 'thread.started', thread_id: 'thread_noise' })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'turn.completed', usage: {} })}\n`);
  child.stdout.emit('data', 'SUCCESS: The process with PID 123 has been terminated.\n');
  child.stdout.emit('data', 'Reading additional input from stdin...\n');
  child.emit('exit', 0, null);

  assert.equal(events.some((event) => event.type === 'conversation.completed'), true);
  assert.equal(events.some((event) => event.text === 'Codex emitted invalid JSONL'), false);
});

test('Codex conversation persists thread id and preserves it after turn failure', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath(), conversationAdapters: new Map([['codex', fakeCodexConversationAdapter()]]), codexEnabled: true });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'codex' }, token);
    const conversationId = created.body.conversation.id;
    await request(port, 'POST', `/api/conversations/${conversationId}/messages`, { text: 'fail after thread' }, token);
    await new Promise((resolve) => setTimeout(resolve, 20));
    const listed = await request(port, 'GET', '/api/conversations', null, token);
    const conversation = listed.body.conversations.find((item) => item.id === conversationId);
    assert.equal(conversation.cliSessionId, 'thread_after_fail');
    assert.equal(conversation.status, 'failed');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('Codex conversation HTTP API sends message and stores CLI thread id', async () => {
  const spawned = [];
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath() });
  const codex = app.conversations.adapters.get('codex');
  codex.spawnSyncFn = fakeCodexConversationSpawnSync;
  codex.capability = null;
  codex.spawnFn = (_cmd, args, options) => {
    const child = fakeCodexChild();
    spawned.push({ args, options, child });
    setImmediate(() => {
      child.stdout.emit('data', `${JSON.stringify({ type: 'thread.started', thread_id: 'thread_http_1' })}\n`);
      child.stdout.emit('data', `${JSON.stringify({ type: 'item.completed', item: { id: 'item_1', type: 'agent_message', text: 'hello from codex' } })}\n`);
      child.stdout.emit('data', `${JSON.stringify({ type: 'turn.completed', usage: { input_tokens: 1, output_tokens: 1 } })}\n`);
      child.emit('exit', 0, null);
    });
    return child;
  };
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId, adapter: 'codex', permissionMode: 'auto' }, token);
    const conversationId = created.body.conversation.id;
    const sent = await request(port, 'POST', `/api/conversations/${conversationId}/messages`, { text: 'hello' }, token);
    assert.equal(sent.status, 200);
    await new Promise((resolve) => setTimeout(resolve, 20));
    const listed = await request(port, 'GET', '/api/conversations', null, token);
    const conversation = listed.body.conversations.find((item) => item.id === conversationId);
    assert.equal(conversation.cliSessionId, 'thread_http_1');
    assert.equal(conversation.status, 'idle');
    const approvalIndex = spawned[0].args.indexOf('--ask-for-approval');
    assert.notEqual(approvalIndex, -1);
    assert.deepEqual(spawned[0].args.slice(approvalIndex, approvalIndex + 7), ['--ask-for-approval', 'never', '-c', 'tool_timeout_sec=600', 'exec', '--json', '-C']);
    const events = await request(port, 'GET', `/api/conversations/${conversationId}/events?afterSeq=0`, null, token);
    assert.equal(events.body.events.some((event) => event.type === 'assistant.message' && event.text === 'hello from codex'), true);
    assert.equal(events.body.events.some((event) => event.type === 'conversation.completed'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('HTTP conversation API exposes model metadata and passes selected model into adapter startup', async () => {
  const { conversationEventTypes } = require('../daemon/src/conversation-protocol');
  const startCalls = [];
  const conversationAdapters = new Map([['codex', {
    capabilities: { resume: true, partialOutput: true },
    async getModelCapability() {
      return {
        models: [
          { id: 'gpt-5', label: 'GPT-5', source: MODEL_SOURCES.CODEX_CONFIG, selected: true },
          { id: 'gpt-5.5', label: 'GPT-5.5', source: MODEL_SOURCES.CODEX_CONFIG }
        ],
        selectedModel: 'gpt-5',
        canSelectModel: true
      };
    },
    async startConversation(input) {
      startCalls.push(input);
      return {
        async sendUserMessage() {
          input.onEvent({ type: 'conversation.completed' });
        },
        async cancel() {},
        async dispose() {}
      };
    }
  }]]);
  const app = createApp({
    port: 0,
    conversationAdapters,
    conversationDbPath: tempConversationDbPath('conversation-model-http-'),
    codexAppServerProbe: false
  });
  app.adapterRegistry.adapters.set('codex', {
    name: 'codex',
    displayName: 'Codex',
    async detectCapabilities() {
      return { adapter: 'codex', available: true, status: 'available' };
    },
    getModelCapability() {
      return {
        models: [
          {
            id: 'gpt-5',
            label: 'GPT-5',
            source: MODEL_SOURCES.CODEX_CONFIG,
            selected: true
          },
          {
            id: 'gpt-5.5',
            label: 'GPT-5.5',
            source: MODEL_SOURCES.CODEX_CONFIG
          }
        ],
        selectedModel: 'gpt-5',
        canSelectModel: true
      };
    },
    getCapabilities() {
      return { resume: true };
    }
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'conversation-model-test'
    });
    const token = paired.body.token;
    const adapters = await request(port, 'GET', '/api/adapters', null, token);
    const codex = adapters.body.adapters.find((item) => item.adapter === 'codex');
    assert.deepEqual(codex.models.map((model) => model.id), ['gpt-5', 'gpt-5.5']);
    assert.equal(codex.selectedModel, 'gpt-5');
    assert.equal(codex.canSelectModel, true);

    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId,
      adapter: 'codex',
      model: ' gpt-5 '
    }, token);
    assert.equal(created.status, 201);
    assert.equal(created.body.conversation.model, 'gpt-5');

    const conversationId = created.body.conversation.id;
    const patched = await request(port, 'PATCH', `/api/conversations/${conversationId}/model`, { model: 'gpt-5.5' }, token);
    assert.equal(patched.status, 200);
    assert.equal(patched.body.conversation.model, 'gpt-5.5');

    const updatedList = await request(port, 'GET', '/api/conversations', null, token);
    const updatedConversation = updatedList.body.conversations.find((item) => item.id === conversationId);
    assert.equal(updatedConversation.model, 'gpt-5.5');

    const updateEvents = await request(port, 'GET', `/api/conversations/${conversationId}/events?afterSeq=0`, null, token);
    const modelChanged = updateEvents.body.events.find((event) => event.type === conversationEventTypes.MODEL_CHANGED);
    assert.ok(modelChanged);
    assert.equal(modelChanged.previousModel, 'gpt-5');
    assert.equal(modelChanged.model, 'gpt-5.5');

    await request(port, 'POST', `/api/conversations/${conversationId}/messages`, { text: 'hello' }, token);
    assert.equal(startCalls.length, 1);
    assert.equal(startCalls[0].model, 'gpt-5.5');

    const listed = await request(port, 'GET', '/api/conversations', null, token);
    const conversation = listed.body.conversations.find((item) => item.id === conversationId);
    assert.equal(conversation.model, 'gpt-5.5');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('HTTP API enforces pairing, workspace ACL, run creation, replay, and V1 terminal boundary', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath() });
  app.adapterRegistry.get('claude').spawnSyncFn = fakeSpawnSync;
  app.adapterRegistry.get('claude').spawnFn = fakeSpawn;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    assert.equal(paired.status, 200);
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const unauthorized = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', prompt: 'x' }, token);
    assert.equal(unauthorized.status, 404);
    const rejected = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId, prompt: 'x', command: 'dir' }, token);
    assert.equal(rejected.status, 400);
    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId, prompt: 'hello' }, token);
    assert.equal(created.status, 201);
    await new Promise((resolve) => setTimeout(resolve, 20));
    const events = await request(port, 'GET', `/api/runs/${created.body.id}/events?afterSeq=0`, null, token);
    assert.equal(events.status, 200);
    assert.equal(events.body.events[0].type, eventTypes.RUN_STARTED);
    assert.equal(events.body.events.some((event) => event.type === eventTypes.ASSISTANT_DELTA), true);
    const replay = await request(port, 'GET', `/api/runs/${created.body.id}/events?afterSeq=1`, null, token);
    assert.equal(replay.body.events.every((event) => event.seq > 1), true);
    const cancelled = await request(port, 'POST', `/api/runs/${created.body.id}/cancel`, {}, token);
    assert.equal(cancelled.status, 200);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('V1.1 adapter diagnostics include codex disabled and opencode needs configuration', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath(), codexAppServerProbe: false });
  app.adapterRegistry.get('claude').spawnSyncFn = fakeSpawnSync;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const adapters = await request(port, 'GET', '/api/adapters', null, paired.body.token);
    assert.equal(adapters.status, 200);
    assert.equal(adapters.body.adapters.some((adapter) => adapter.adapter === 'codex' && adapter.status === 'disabled'), true);
    assert.equal(adapters.body.adapters.some((adapter) => adapter.adapter === 'opencode'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('slash command catalog returns adapter commands and unknown adapters as empty lists', async () => {
  const app = createApp({
    port: 0,
    devAdapters: true,
    appDbPath: tempConversationDbPath('app-db-slash-commands-')
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'slash-command-test'
    });
    const token = paired.body.token;

    const codex = await request(port, 'GET', '/api/adapters/codex/slash-commands', null, token);
    assert.equal(codex.status, 200);
    assert.equal(codex.body.adapter, 'codex');
    assert.equal(Array.isArray(codex.body.commands), true);
    assert.equal(codex.body.commands.some((item) => item.command === '/model'), true);
    assert.equal(codex.body.commands.every((item) => typeof item.command === 'string' && item.command.startsWith('/')), true);
    assert.equal(codex.body.commands.every((item) => typeof item.description === 'string'), true);
    assert.equal(codex.body.commands.some((item) => Object.prototype.hasOwnProperty.call(item, 'source')), false);

    const claude = await request(port, 'GET', '/api/adapters/claude/slash-commands', null, token);
    assert.equal(claude.status, 200);
    assert.equal(claude.body.adapter, 'claude');
    assert.equal(claude.body.commands.some((item) => item.command === '/compact'), true);

    const opencode = await request(port, 'GET', '/api/adapters/opencode/slash-commands', null, token);
    assert.equal(opencode.status, 200);
    assert.equal(opencode.body.adapter, 'opencode');
    assert.equal(Array.isArray(opencode.body.commands), true);

    const unknown = await request(port, 'GET', '/api/adapters/not-real/slash-commands', null, token);
    assert.equal(unknown.status, 200);
    assert.deepEqual(unknown.body, { adapter: 'not-real', commands: [] });
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('slash command catalog prefers Claude SDK initialize commands', async () => {
  const { SlashCommandCatalog } = require('../daemon/src/slash-command-catalog');
  const catalog = new SlashCommandCatalog({
    discoverers: {
      claude: {
        async discover({ workspacePath }) {
          assert.equal(workspacePath, process.cwd());
          return [
            { name: 'compact', description: 'SDK compact' },
            { command: '/review', description: 'SDK review' },
            { name: 'vim', description: 'SDK vim mode', interactive: true }
          ];
        }
      }
    }
  });

  const result = await catalog.list('claude', { workspacePath: process.cwd(), force: true });

  assert.equal(result.adapter, 'claude');
  assert.deepEqual(result.commands, [
    { command: '/compact', description: 'SDK compact' },
    { command: '/review', description: 'SDK review' },
    { command: '/vim', description: 'SDK vim mode' }
  ]);
});

test('Claude slash command discoverer reads SDK initialize response commands', async () => {
  const { ClaudeSlashCommandDiscoverer } = require('../daemon/src/slash-command-catalog');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    write(data) {
      const request = JSON.parse(data.trim());
      setImmediate(() => {
        child.stdout.emit('data', Buffer.from(`${JSON.stringify({
          type: 'control_response',
          response: {
            request_id: request.request_id,
            subtype: 'success',
            response: {
              commands: [
                { name: 'compact', description: 'compact from sdk' },
                { name: 'vim', description: 'vim from sdk', interactive: true }
              ]
            }
          }
        })}\n`));
      });
    },
    end() { this.destroyed = true; }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const spawnCalls = [];
  const discoverer = new ClaudeSlashCommandDiscoverer({
    command: 'claude',
    spawnSyncFn: fakeSpawnSync,
    spawnFn: (command, args, options) => {
      spawnCalls.push({ command, args, options });
      return child;
    },
    timeoutMs: 500
  });

  const commands = await discoverer.discover({ workspacePath: process.cwd() });

  assert.equal(spawnCalls[0].options.cwd, process.cwd());
  assert.equal(spawnCalls[0].args.includes('--input-format'), true);
  assert.deepEqual(commands, [
    { command: '/compact', description: 'compact from sdk' },
    { command: '/vim', description: 'vim from sdk' }
  ]);
});

test('V1.1 run filters, shortcuts, and token revocation work', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath() });
  app.adapterRegistry.get('claude').spawnSyncFn = fakeSpawnSync;
  app.adapterRegistry.get('claude').spawnFn = fakeSpawn;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const shortcuts = await request(port, 'GET', '/api/shortcuts', null, token);
    assert.equal(shortcuts.body.shortcuts.some((shortcut) => shortcut.id === 'test'), true);
    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId, shortcutId: 'test' }, token);
    assert.equal(created.status, 201);
    const filtered = await request(port, 'GET', `/api/runs?tool=claude&workspaceId=${workspaceId}&status=running`, null, token);
    assert.equal(filtered.body.runs.length, 1);
    const revoked = await request(port, 'POST', `/api/devices/${paired.body.deviceId}/revoke`, {}, token);
    assert.equal(revoked.body.revoked, true);
    const denied = await request(port, 'GET', '/api/workspaces', null, token);
    assert.equal(denied.status, 401);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('Codex adapter can run when explicitly enabled and still rejects arbitrary args', async () => {
  const app = createApp({ port: 0, codexEnabled: true, conversationDbPath: tempConversationDbPath() });
  app.adapterRegistry.get('codex').spawnSyncFn = fakeCodexSpawnSync;
  app.adapterRegistry.get('codex').spawnFn = fakeSpawn;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const rejected = await request(port, 'POST', '/api/runs', { tool: 'codex', workspaceId, prompt: 'x', args: ['--danger'] }, token);
    assert.equal(rejected.status, 400);
    const created = await request(port, 'POST', '/api/runs', { tool: 'codex', workspaceId, prompt: 'hello' }, token);
    assert.equal(created.status, 201);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('Windows npm shim resolution launches Codex through node script', () => {
  const resolved = resolveCliInvocation('codex', {
    platform: 'win32',
    nodePath: 'D:\\nodejs\\node.exe',
    which: () => 'C:\\Users\\wenmm\\npm-global\\codex.cmd',
    readTextFile: () => [
      '@ECHO off',
      'IF EXIST "%dp0%\\node.exe" (',
      '  SET "_prog=%dp0%\\node.exe"',
      ') ELSE (',
      '  SET "_prog=node"',
      ')',
      'endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & "%_prog%"  "%dp0%\\node_modules\\@openai\\codex\\bin\\codex.js" %*'
    ].join('\n')
  });

  assert.deepEqual(resolved, {
    command: 'D:\\nodejs\\node.exe',
    argsPrefix: ['C:\\Users\\wenmm\\npm-global\\node_modules\\@openai\\codex\\bin\\codex.js']
  });
});

test('Windows npm shim resolution launches Claude through packaged exe', () => {
  const resolved = resolveCliInvocation('claude', {
    platform: 'win32',
    which: () => 'C:\\Users\\wenmm\\npm-global\\claude.cmd',
    readTextFile: () => [
      '@ECHO off',
      'GOTO start',
      ':find_dp0',
      'SET dp0=%~dp0',
      'EXIT /b',
      ':start',
      'SETLOCAL',
      'CALL :find_dp0',
      '"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe"   %*'
    ].join('\n')
  });

  assert.deepEqual(resolved, {
    command: 'C:\\Users\\wenmm\\npm-global\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe',
    argsPrefix: []
  });
});

test('Claude capability detection uses resolved Windows npm shim exe', () => {
  const exePath = 'C:\\Users\\wenmm\\npm-global\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe';
  const adapter = new ClaudeAdapter({
    command: 'claude',
    cliResolverOptions: claudeShimResolverOptions(),
    spawnSyncFn: (cmd, args) => {
      if (cmd === 'where.exe') return { status: 0, stdout: 'C:\\Users\\wenmm\\npm-global\\claude.cmd\n', stderr: '' };
      if (cmd !== exePath) return { status: 1, stdout: '', stderr: 'wrong command' };
      if (args.includes('--version')) return { status: 0, stdout: '2.1.132 (Claude Code)', stderr: '' };
      if (args.includes('--help')) return { status: 0, stdout: '-p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-mode [default|auto]', stderr: '' };
      return { status: 0, stdout: '', stderr: '' };
    }
  });

  const capability = adapter.detectCapabilities();
  assert.equal(capability.available, true);
  assert.equal(capability.version, '2.1.132 (Claude Code)');
});

test('Claude capability detection accepts installed shim when version exec is blocked', () => {
  const adapter = new ClaudeAdapter({
    command: 'claude',
    cliResolverOptions: {
      platform: 'win32',
      nodePath: 'D:\\nodejs\\node.exe',
      which: () => 'C:\\Users\\wenmm\\npm-global\\claude.cmd',
      readTextFile: claudeCliJsShimText
    },
    readTextFile: () => JSON.stringify({ version: '2.1.112' }),
    spawnSyncFn: (cmd) => {
      if (cmd === 'where.exe') return { status: 1, stdout: '', stderr: 'not used' };
      return {
        error: Object.assign(new Error(`spawnSync ${cmd} EPERM`), { code: 'EPERM' }),
        status: null,
        stdout: '',
        stderr: ''
      };
    }
  });

  const capability = adapter.detectCapabilities();
  assert.equal(capability.available, true);
  assert.equal(capability.path, 'C:\\Users\\wenmm\\npm-global\\node_modules\\@anthropic-ai\\claude-code\\cli.js');
  assert.equal(capability.version, '2.1.112 (Claude Code)');
  assert.equal(capability.detectionMethod, 'which+package');
  assert.equal(capability.capabilities.streamJson, true);
});

test('Claude conversation adapter starts with resolved Windows npm shim exe', async () => {
  const exePath = 'C:\\Users\\wenmm\\npm-global\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe';
  let spawnCommand = null;
  let spawnArgs = null;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write() {}, end() { this.destroyed = true; } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  const adapter = new ClaudeConversationAdapter({
    command: 'claude',
    cliResolverOptions: claudeShimResolverOptions(),
    spawnSyncFn: (cmd, args) => {
      if (cmd === 'where.exe') return { status: 0, stdout: 'C:\\Users\\wenmm\\npm-global\\claude.cmd\n', stderr: '' };
      if (cmd !== exePath) return { status: 1, stdout: '', stderr: 'wrong command' };
      if (args.includes('--version')) return { status: 0, stdout: '2.1.132 (Claude Code)', stderr: '' };
      return { status: 0, stdout: '', stderr: '' };
    },
    spawnFn: (cmd, args) => {
      spawnCommand = cmd;
      spawnArgs = args;
      return child;
    }
  });

  await adapter.startConversation({ conversationId: 'conv_claude_shim', workspacePath: 'D:\\AiProject\\vibe-coding', onEvent: () => {} });
  assert.equal(spawnCommand, exePath);
  assert.equal(spawnArgs.includes('--output-format'), true);
  assert.equal(spawnArgs.includes('stream-json'), true);
});

function claudeShimResolverOptions() {
  return {
    platform: 'win32',
    env: { PATH: '' },
    existsSync: () => false,
    readTextFile: () => [
      '@ECHO off',
      'GOTO start',
      ':find_dp0',
      'SET dp0=%~dp0',
      'EXIT /b',
      ':start',
      'SETLOCAL',
      'CALL :find_dp0',
      '"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe"   %*'
    ].join('\n')
  };
}

function claudeCliJsShimText() {
  return [
    '@ECHO off',
    'IF EXIST "%dp0%\\node.exe" (',
    '  SET "_prog=%dp0%\\node.exe"',
    ') ELSE (',
    '  SET "_prog=node"',
    ')',
    'endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & "%_prog%"  "%dp0%\\node_modules\\@anthropic-ai\\claude-code\\cli.js" %*'
  ].join('\n');
}

function fakeSpawnSync(_cmd, args) {
  if (args.includes('--version')) return { status: 0, stdout: 'claude-test', stderr: '' };
  return { status: 0, stdout: '-p --bare --output-format stream-json --verbose --include-partial-messages --resume', stderr: '' };
}

function fakeCodexSpawnSync(_cmd, args) {
  if (args.includes('--version')) return { status: 0, stdout: 'codex-test', stderr: '' };
  return { status: 0, stdout: 'Usage: codex exec --json', stderr: '' };
}

function createFakeAppServerChild({ pid = 1234, kill } = {}) {
  const { PassThrough } = require('node:stream');
  const child = new EventEmitter();
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.pid = pid;
  child.kill = kill || (() => true);
  const closeStdio = () => {
    child.stdin.destroy();
    child.stdout.destroy();
    child.stderr.destroy();
  };
  child.once('exit', closeStdio);
  child.once('error', closeStdio);
  return child;
}

function fakeCodexConversationSpawnSync(_cmd, args) {
  if (args.includes('--version')) return { status: 0, stdout: 'codex-cli 0.130.0', stderr: '' };
  if (args.includes('resume') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec resume [OPTIONS] [SESSION_ID] [PROMPT]\n--json\n--skip-git-repo-check', stderr: '' };
  if (args.includes('exec') && args.includes('--help')) return { status: 0, stdout: 'Usage: codex exec [OPTIONS] [PROMPT]\n--json\n-C, --cd <DIR>\n--sandbox <SANDBOX_MODE>\n--skip-git-repo-check', stderr: '' };
  return { status: 0, stdout: '', stderr: '' };
}

function fakeCodexChild() {
  const child = new EventEmitter();
  child.pid = 12345;
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  return child;
}

function fakeCodexConversationAdapter() {
  return {
    capabilities: { resume: true, partialOutput: true, waitingApproval: false, mobileApprovalCallbacks: false },
    async startConversation({ onEvent }) {
      return {
        async sendUserMessage() {
          onEvent({ type: 'system.notice', sessionId: 'thread_after_fail', text: 'thread started', noticeKind: 'codex_thread_started' });
          onEvent({ type: 'run.error', message: 'failed after thread', sessionId: 'thread_after_fail' });
        },
        async cancel() {}
      };
    }
  };
}

function fakeSpawn() {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  setImmediate(() => child.stdout.emit('data', Buffer.from('{"type":"assistant","text":"hello"}\n')));
  return child;
}

async function request(port, method, path, body, token) {
  const payload = body ? JSON.stringify(body) : '';
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: '127.0.0.1',
      port,
      path,
      method,
      headers: {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload),
        ...(token ? { authorization: `Bearer ${token}` } : {})
      }
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) }));
    });
    req.on('error', reject);
    req.end(payload);
  });
}

async function createCodexAppServerRouteTestApp({
  service,
  auditLog = new AuditLog(),
  workspacePath = process.cwd(),
  workspaceName = 'Codex App Server Test',
  label = 'codex-app-server-route-test',
  deviceId = `device_${nodeCrypto.randomBytes(4).toString('hex')}`
} = {}) {
  const app = createApp({
    port: 0,
    codexAppServerService: service,
    auditLog,
    codexAppServerProbe: false,
    codexAppServerModelLister: false,
    appDbPath: tempConversationDbPath('app-server-route-test-')
  });
  const pair = app.auth.createPairingCode();
  const paired = app.auth.pair(pair.code, label, deviceId);
  const device = app.auth.authenticate(`Bearer ${paired.token}`);
  const workspace = app.workspaces.add({ workspacePath, name: workspaceName }, device);
  app.auth.allowWorkspace(device.id, workspace.id);
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  const call = (method, pathValue, body) => request(port, method, pathValue, body, paired.token);
  return {
    app,
    auditLog,
    device,
    token: paired.token,
    workspace,
    port,
    get: (pathValue) => call('GET', pathValue),
    post: (pathValue, body = {}) => call('POST', pathValue, body),
    patch: (pathValue, body = {}) => call('PATCH', pathValue, body),
    delete: (pathValue, body = {}) => call('DELETE', pathValue, body),
    close: async () => {
      await new Promise((resolve) => app.server.close(resolve));
      app.notificationHub.close();
      app.appSqliteStore.close();
    }
  };
}

function wsUrl(port, path = '/api/notifications/ws') {
  return `ws://127.0.0.1:${port}${path}`;
}

function createNotificationHubTestConnection() {
  return {
    id: 'ws_test',
    ws: { readyState: WebSocket.OPEN, send() {} },
    device: { id: 'device_test', allowedWorkspaceIds: new Set(['default']) },
    subscriptions: new Map(),
    generationCounter: 0,
    sentFrames: []
  };
}

function openNotificationSocket(port, token) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl(port), {
      headers: token ? { authorization: `Bearer ${token}` } : {}
    });
    socket.__pendingMessages = [];
    socket.on('message', (data) => {
      socket.__pendingMessages.push(data);
    });
    socket.once('open', () => resolve(socket));
    socket.once('error', reject);
  });
}

function readWsJson(socket) {
  if (socket.__pendingMessages && socket.__pendingMessages.length > 0) {
    return Promise.resolve(JSON.parse(String(socket.__pendingMessages.shift())));
  }
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('timed out waiting for WebSocket message')), 1000);
    const onMessage = () => {
      clearTimeout(timeout);
      resolve(JSON.parse(String(socket.__pendingMessages.shift())));
    };
    socket.once('message', onMessage);
    socket.once('error', (error) => {
      clearTimeout(timeout);
      socket.off('message', onMessage);
      reject(error);
    });
  });
}

function expectNoWsMessage(socket, timeoutMs = 100) {
  if (socket.__pendingMessages && socket.__pendingMessages.length > 0) {
    return Promise.reject(new Error(`unexpected WebSocket message: ${String(socket.__pendingMessages.shift())}`));
  }
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(resolve, timeoutMs);
    socket.once('message', (data) => {
      clearTimeout(timeout);
      reject(new Error(`unexpected WebSocket message: ${String(data)}`));
    });
  });
}

function waitForWsClose(socket) {
  return new Promise((resolve) => socket.once('close', resolve));
}

async function requestRaw(port, method, path, body, token, extraHeaders = {}) {
  const payload = Buffer.isBuffer(body) ? body : (body ? Buffer.from(JSON.stringify(body), 'utf8') : Buffer.alloc(0));
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: '127.0.0.1',
      port,
      path,
      method,
      headers: {
        'content-type': 'application/json',
        'content-length': payload.length,
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...extraHeaders,
      }
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    });
    req.on('error', reject);
    req.end(payload);
  });
}

function multipartBody({ boundary, payload, files }) {
  const chunks = [];
  chunks.push(Buffer.from(`--${boundary}\r\ncontent-disposition: form-data; name="payload"\r\n\r\n${JSON.stringify(payload)}\r\n`, 'utf8'));
  files.forEach((file) => {
    chunks.push(Buffer.from(`--${boundary}\r\ncontent-disposition: form-data; name="files[]"; filename="${file.name}"\r\ncontent-type: ${file.mimeType}\r\n\r\n`, 'utf8'));
    chunks.push(file.bytes);
    chunks.push(Buffer.from('\r\n', 'utf8'));
  });
  chunks.push(Buffer.from(`--${boundary}--\r\n`, 'utf8'));
  return Buffer.concat(chunks);
}

function multipartBodyFileFirst({ boundary, payload, file }) {
  return Buffer.concat([
    Buffer.from(`--${boundary}\r\ncontent-disposition: form-data; name="files[]"; filename="${file.name}"\r\ncontent-type: ${file.mimeType}\r\n\r\n`, 'utf8'),
    file.bytes,
    Buffer.from(`\r\n--${boundary}\r\ncontent-disposition: form-data; name="payload"\r\n\r\n${JSON.stringify(payload)}\r\n--${boundary}--\r\n`, 'utf8')
  ]);
}

function minimalPngBytes({ width = 1, height = 1, extraBytes = Buffer.alloc(0) } = {}) {
  const signature = Buffer.from('89504e470d0a1a0a', 'hex');
  const ihdr = Buffer.alloc(25);
  ihdr.writeUInt32BE(13, 0);
  ihdr.write('IHDR', 4, 4, 'ascii');
  ihdr.writeUInt32BE(width, 8);
  ihdr.writeUInt32BE(height, 12);
  ihdr[16] = 8;
  ihdr[17] = 2;
  ihdr[18] = 0;
  ihdr[19] = 0;
  ihdr[20] = 0;
  const iend = Buffer.from('0000000049454e4400000000', 'hex');
  return Buffer.concat([signature, ihdr, iend, extraBytes]);
}

function minimalJpegBytes({ width = 1, height = 1 } = {}) {
  return Buffer.from([
    0xff, 0xd8,
    0xff, 0xc0,
    0x00, 0x11,
    0x08,
    (height >> 8) & 0xff, height & 0xff,
    (width >> 8) & 0xff, width & 0xff,
    0x03,
    0x01, 0x11, 0x00,
    0x02, 0x11, 0x00,
    0x03, 0x11, 0x00,
    0xff, 0xd9
  ]);
}

function minimalWebpBytes({ width = 1, height = 1 } = {}) {
  const bytes = Buffer.alloc(30);
  bytes.write('RIFF', 0, 4, 'ascii');
  bytes.writeUInt32LE(22, 4);
  bytes.write('WEBP', 8, 4, 'ascii');
  bytes.write('VP8X', 12, 4, 'ascii');
  bytes.writeUInt32LE(10, 16);
  writeUInt24LE(bytes, width - 1, 24);
  writeUInt24LE(bytes, height - 1, 27);
  return bytes;
}

function writeUInt24LE(buffer, value, offset) {
  buffer[offset] = value & 0xff;
  buffer[offset + 1] = (value >> 8) & 0xff;
  buffer[offset + 2] = (value >> 16) & 0xff;
}

function malformedMultipartBody({ boundary, payload }) {
  return Buffer.from(`--${boundary}\r\ncontent-disposition: form-data; name="payload"\r\n\r\n${JSON.stringify(payload)}\r\n`, 'utf8');
}

function attachmentTestCapabilityVersion() {
  const { capabilityVersionForNormalizedInput } = require('../daemon/src/attachment-hashes');
  return capabilityVersionForNormalizedInput({
    adapterId: 'codex',
    attachments: {
      image: 'unsupported',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    },
    cliPath: 'codex',
    cliVersion: null,
    models: [],
    selectedModelId: null
  });
}

function attachmentTextOnlyModelCapabilityVersion() {
  const { capabilityVersionForNormalizedInput } = require('../daemon/src/attachment-hashes');
  return capabilityVersionForNormalizedInput({
    adapterId: 'codex',
    attachments: {
      image: 'native',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    },
    cliPath: 'codex',
    cliVersion: null,
    models: [{
      id: 'text-only',
      inputModalities: ['text']
    }],
    selectedModelId: 'text-only'
  });
}

function attachmentPdfCapabilityVersion() {
  const { capabilityVersionForNormalizedInput } = require('../daemon/src/attachment-hashes');
  return capabilityVersionForNormalizedInput({
    adapterId: 'codex',
    attachments: {
      image: 'unsupported',
      pdf: 'staged_path',
      textDocument: 'text_extract'
    },
    cliPath: 'codex',
    cliVersion: null,
    models: [],
    selectedModelId: null
  });
}

function attachmentImageCapabilityVersion(adapterId = 'codex') {
  const { capabilityVersionForNormalizedInput } = require('../daemon/src/attachment-hashes');
  return capabilityVersionForNormalizedInput({
    adapterId,
    attachments: {
      image: 'native',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    },
    cliPath: adapterId,
    cliVersion: null,
    models: [],
    selectedModelId: null
  });
}

function attachmentConversationAdapter({ delaySend = false, failAfterSend = false, sendError = null, capabilities = null, modelCapability = null, onSendEvent = null, onSendEvents = null } = {}) {
  const sent = [];
  let releaseSend;
  return {
    sent,
    capabilities: capabilities || {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'unsupported',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    },
    getCapabilities() {
      return this.capabilities;
    },
    getModelCapability() {
      return modelCapability || { models: [], selectedModel: null, canSelectModel: false };
    },
    releaseSend() {
      if (releaseSend) releaseSend();
    },
    async startConversation({ onEvent } = {}) {
      return {
        async sendUserMessage(message) {
          sent.push(message);
          if (sendError) throw (typeof sendError === 'function' ? sendError(message) : sendError);
          if (failAfterSend) throw new Error('adapter failed after commit');
          if (delaySend) await new Promise((resolve) => { releaseSend = resolve; });
          const events = onSendEvents || (onSendEvent ? [onSendEvent] : []);
          for (const event of events) onEvent(event);
        },
        async cancel() {},
        async dispose() {}
      };
    }
  };
}

function codexNativeImageAttachmentAdapter(options = {}) {
  return attachmentConversationAdapter({
    ...options,
    capabilities: options.capabilities || {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
}

async function createAttachmentConversationApp(options = {}) {
  const adapterId = options.adapterId || 'codex';
  const adapter = options.adapter || attachmentConversationAdapter();
  const app = createApp({
    port: 0,
    mode: 'dev',
    devAdapters: true,
    appDbPath: options.appDbPath || tempConversationDbPath(options.dbPrefix || 'app-db-attachments-'),
    conversationAdapters: new Map([[adapterId, adapter]])
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  const pairing = await request(port, 'POST', '/api/pairing-code', {});
  const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: options.label || 'test' });
  const workspace = await request(port, 'POST', '/api/workspaces', { workspacePath: process.cwd(), name: 'Attachments' }, paired.body.token);
  const created = await request(port, 'POST', '/api/conversations', { workspaceId: workspace.body.id, adapter: adapterId }, paired.body.token);
  return { app, adapter, adapterId, port, token: paired.body.token, deviceId: paired.body.deviceId, conversationId: created.body.conversation.id };
}

async function closeAttachmentConversationApp(app) {
  await new Promise((resolve) => app.server.close(resolve));
  app.appSqliteStore.close();
}

function parseRawJson(response) {
  return JSON.parse(response.body.toString('utf8'));
}

function attachmentScratchEntries(app) {
  const fs = require('node:fs');
  const scratchRoot = app.conversations.attachmentScratchStore.root;
  return fs.existsSync(scratchRoot) ? fs.readdirSync(scratchRoot) : [];
}

async function waitForAttachmentScratchCleanup(app) {
  for (let i = 0; i < 20; i += 1) {
    if (attachmentScratchEntries(app).length === 0) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

async function sendCodexNativeImageTurnScratch({ app, port, token, conversationId, clientMessageId, text, boundary }) {
  const imageBytes = minimalPngBytes({ width: 1, height: 1 });
  const body = multipartBody({
    boundary,
    payload: {
      text,
      clientMessageId,
      capabilityVersion: attachmentImageCapabilityVersion(),
      attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
    },
    files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
  });
  const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
    'content-type': `multipart/form-data; boundary=${boundary}`
  });
  const internal = app.conversations.conversations.get(conversationId);
  assert.equal(response.status, 200);
  assert.equal(internal.turnAttachmentScratches.length, 1);
  assert.equal(attachmentScratchEntries(app).length, 1);
  return { response, internal };
}

function sentMessageTexts(adapter) {
  return adapter.sent.map((message) => (typeof message === 'string' ? message : message.text));
}

test('JSON conversation send still accepts text payloads', async () => {
  const { app, adapter, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-json-' });
  try {
    const response = await request(port, 'POST', `/api/conversations/${conversationId}/messages`, { text: 'hello json' }, token);
    assert.equal(response.status, 200);
    assert.equal(response.body.conversation.status, 'running');
    assert.deepEqual(adapter.sent, ['hello json']);
    const userMessage = app.conversationEventStore.list(conversationId, 0).find((event) => event.type === 'user.message');
    assert.equal(userMessage.text, 'hello json');
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage, 'attachments'), false);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('JSON conversation send rejects attachment metadata before committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-json-metadata-' });
  try {
    const response = await request(port, 'POST', `/api/conversations/${conversationId}/messages`, {
      text: 'hello json',
      attachments: [{ name: 'a.txt', kind: 'textDocument', mimeType: 'text/plain', sizeBytes: 5 }]
    }, token);

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('JSON conversation send rejects any attachments key presence before committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-json-reserved-metadata-' });
  try {
    const cases = [
      { label: 'object', attachments: { name: 'a.txt', kind: 'textDocument', mimeType: 'text/plain', sizeBytes: 5 } },
      { label: 'null', attachments: null },
      { label: 'string', attachments: 'metadata' },
      { label: 'empty array', attachments: [] }
    ];

    for (const item of cases) {
      const response = await request(port, 'POST', `/api/conversations/${conversationId}/messages`, {
        text: `hello json ${item.label}`,
        attachments: item.attachments
      }, token);

      assert.equal(response.status, 400, item.label);
      assert.equal(response.body.error.code, 'BAD_REQUEST');
      assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    }
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects missing capabilityVersion before committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-capability-' });
  try {
    const boundary = '----attachments-test-boundary';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_1',
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 409);
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'capability_stale');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.equal(app.conversations.getConversation(conversationId, app.auth.authenticate(`Bearer ${token}`)).status, 'idle');
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects stale capabilityVersion before committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-stale-capability-' });
  try {
    const boundary = '----attachments-stale-capability';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_stale',
        capabilityVersion: 'stale',
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 409);
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'capability_stale');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.equal(app.conversations.getConversation(conversationId, app.auth.authenticate(`Bearer ${token}`)).status, 'idle');
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects missing clientMessageId before committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-client-id-' });
  try {
    const boundary = '----attachments-missing-client';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 400);
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.equal(app.conversations.getConversation(conversationId, app.auth.authenticate(`Bearer ${token}`)).status, 'idle');
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects files before payload with JSON error response', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-file-first-' });
  try {
    const boundary = '----attachments-file-first';
    const body = multipartBodyFileFirst({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_file_first',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      file: { name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 400);
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart parser errors return JSON response without committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-parser-error-' });
  try {
    const boundary = '----attachments-parser-error';
    const body = malformedMultipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_parser_error',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      }
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 400);
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects payload fields larger than 64KB before committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-payload-too-large-' });
  try {
    const boundary = '----attachments-payload-too-large';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'x'.repeat((64 * 1024) + 1),
        clientMessageId: 'client_payload_too_large',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 400);
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects declared attachment metadata without matching file bytes', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-missing-file-part-' });
  try {
    const boundary = '----attachments-missing-file-part';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_missing_file_part',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: []
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 400);
    assert.equal(parseRawJson(response).error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.equal(app.conversations.getConversation(conversationId, app.auth.authenticate(`Bearer ${token}`)).status, 'idle');
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects a payload attachments key that is not an array', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-non-array-metadata-' });
  try {
    const boundary = '----attachments-non-array-metadata';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_non_array_metadata',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: { field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }
      },
      files: []
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 400);
    assert.equal(parseRawJson(response).error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects file bytes without declared attachment metadata', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-extra-file-part-' });
  try {
    const boundary = '----attachments-extra-file-part';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_extra_file_part',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: []
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 400);
    assert.equal(parseRawJson(response).error.code, 'BAD_REQUEST');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart reader destroys abortable request streams after validation failure', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { PassThrough } = require('node:stream');
  const { readMultipartConversationMessage } = require('../daemon/src/multipart-message-reader');
  const scratchDir = fs.mkdtempSync(path.join(os.tmpdir(), 'multipart-reader-abort-'));
  try {
    const boundary = '----attachments-reader-abort';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_reader_abort',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 3 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from([0x61, 0x00, 0x62]) }]
    });
    const req = new PassThrough();
    req.headers = {
      'content-type': `multipart/form-data; boundary=${boundary}`,
      'content-length': String(body.length)
    };
    req.destroyOnValidationFailure = true;
    let destroyed = false;
    let destroyError = null;
    const destroy = req.destroy.bind(req);
    req.destroy = (error) => {
      destroyed = true;
      destroyError = error || null;
      return destroy(error);
    };
    req.on('error', () => {});

    const reading = readMultipartConversationMessage(req, { dir: scratchDir });
    req.end(body);

    await assert.rejects(
      () => reading,
      (error) => error.status === 415 && error.code === 'UNSUPPORTED_MEDIA_TYPE'
    );
    assert.equal(destroyed, true);
    assert.equal(destroyError?.code, 'UNSUPPORTED_MEDIA_TYPE');
  } finally {
    fs.rmSync(scratchDir, { recursive: true, force: true });
  }
});

test('multipart validation failures return JSON errors and clean scratch before commit', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-text-invalid-' });
  try {
    const boundary = '----attachments-text-invalid';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect text',
        clientMessageId: 'client_text_invalid',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 3 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from([0x61, 0x00, 0x62]) }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 415);
    assert.equal(parseRawJson(response).error.code, 'UNSUPPORTED_MEDIA_TYPE');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart image validation failures return JSON errors and clean scratch before commit', async () => {
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-image-invalid-' });
  try {
    const boundary = '----attachments-image-invalid';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_image_invalid',
        capabilityVersion: attachmentImageCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: 12 }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: Buffer.from('not an image', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 415);
    assert.equal(parseRawJson(response).error.code, 'UNSUPPORTED_MEDIA_TYPE');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart oversized PNG dimensions reject before committing user.message', async () => {
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-image-dimensions-' });
  try {
    const imageBytes = minimalPngBytes({ width: 20000, height: 1 });
    const boundary = '----attachments-image-dimensions';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_image_dimensions',
        capabilityVersion: attachmentImageCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'wide.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'wide.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 413);
    assert.equal(parseRawJson(response).error.code, 'ATTACHMENT_LIMIT_EXCEEDED');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart oversized image bytes reject before committing user.message', async () => {
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-image-too-large-' });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1, extraBytes: Buffer.alloc((10 * 1024 * 1024) + 1) });
    const boundary = '----attachments-image-too-large';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_image_too_large',
        capabilityVersion: attachmentImageCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'large.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'large.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 413);
    assert.equal(parseRawJson(response).error.code, 'ATTACHMENT_LIMIT_EXCEEDED');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart Claude native image over 5MB rejects before committing user.message', async () => {
  const adapterId = 'claude';
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-claude-image-too-large-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1, extraBytes: Buffer.alloc(6 * 1024 * 1024) });
    const boundary = '----attachments-claude-image-too-large';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_claude_image_too_large',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'large.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'large.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const internal = app.conversations.conversations.get(conversationId);
    assert.equal(response.status, 413);
    assert.equal(parseRawJson(response).error.code, 'ATTACHMENT_LIMIT_EXCEEDED');
    assert.equal(events.some((event) => event.type === 'user.message'), false);
    assert.equal(events.some((event) => event.type === 'run.error'), false);
    assert.equal(events.some((event) => Object.prototype.hasOwnProperty.call(event, 'payloadHash')), false);
    assert.equal(events.some((event) => event.type === 'conversation.status_changed'), false);
    assert.equal(internal.status, 'idle');
    assert.equal(internal.userMessageCount, 0);
    assert.equal(internal.messageIdempotency.has('client_claude_image_too_large'), false);
    assert.equal(internal.messageInFlightIds.has('client_claude_image_too_large'), false);
    assert.deepEqual(adapter.sent, []);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart pre-commit failure does not consume clientMessageId', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-client-retry-' });
  try {
    const failingBoundary = '----attachments-client-retry-fail';
    const failing = multipartBody({
      boundary: failingBoundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_retry',
        capabilityVersion: 'stale',
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, failing, token, {
      'content-type': `multipart/form-data; boundary=${failingBoundary}`
    });
    assert.equal(failed.status, 409);

    const retryBoundary = '----attachments-client-retry-ok';
    const retry = multipartBody({
      boundary: retryBoundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_retry',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const succeeded = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, retry, token, {
      'content-type': `multipart/form-data; boundary=${retryBoundary}`
    });

    assert.equal(succeeded.status, 200);
    assert.equal(app.conversationEventStore.list(conversationId, 0).filter((event) => event.type === 'user.message').length, 1);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart touch persistence failure rolls back pre-commit state and cleans scratch', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-touch-rollback-' });
  const internal = app.conversations.conversations.get(conversationId);
  try {
    internal.status = 'idle';
    internal.blockingItem = { type: 'preexisting', value: 1 };
    internal.idleExpiresAt = '2030-01-01T00:00:00.000Z';
    internal.userMessageCount = 7;
    internal.updatedAt = '2026-05-18T00:00:00.000Z';
    app.conversationSqliteStore.saveConversation(internal);
    const snapshot = {
      status: internal.status,
      blockingItem: internal.blockingItem,
      idleExpiresAt: internal.idleExpiresAt,
      userMessageCount: internal.userMessageCount,
      updatedAt: internal.updatedAt
    };
    const originalSaveConversation = app.conversationSqliteStore.saveConversation.bind(app.conversationSqliteStore);
    let failNextRunningSave = true;
    app.conversationSqliteStore.saveConversation = (conversation) => {
      if (failNextRunningSave && conversation.id === conversationId && conversation.status === 'running') {
        failNextRunningSave = false;
        throw new Error('simulated conversation save failure');
      }
      return originalSaveConversation(conversation);
    };

    const boundary = '----attachments-touch-rollback';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'rollback touch',
        clientMessageId: 'client_touch_rollback',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 500);
    assert.equal(parseRawJson(response).error.message, 'simulated conversation save failure');
    assert.deepEqual({
      status: internal.status,
      blockingItem: internal.blockingItem,
      idleExpiresAt: internal.idleExpiresAt,
      userMessageCount: internal.userMessageCount,
      updatedAt: internal.updatedAt
    }, snapshot);
    assert.equal(internal.messageInFlightIds.has('client_touch_rollback'), false);
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart user.message append failure rolls back persisted state and clears in-flight id', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-event-rollback-' });
  const internal = app.conversations.conversations.get(conversationId);
  try {
    internal.status = 'idle';
    internal.blockingItem = { type: 'preexisting', value: 2 };
    internal.idleExpiresAt = '2030-02-01T00:00:00.000Z';
    internal.userMessageCount = 0;
    internal.updatedAt = '2026-05-18T01:00:00.000Z';
    app.conversationSqliteStore.saveConversation(internal);
    const snapshot = {
      status: internal.status,
      blockingItem: internal.blockingItem,
      idleExpiresAt: internal.idleExpiresAt,
      userMessageCount: internal.userMessageCount,
      updatedAt: internal.updatedAt
    };
    const originalAppendEvent = app.conversationSqliteStore.appendEvent.bind(app.conversationSqliteStore);
    app.conversationSqliteStore.appendEvent = (event) => {
      if (event.conversationId === conversationId && event.type === 'user.message') {
        throw new Error('simulated user.message append failure');
      }
      return originalAppendEvent(event);
    };

    const boundary = '----attachments-event-rollback';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'rollback event',
        clientMessageId: 'client_event_rollback',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });
    const persisted = app.conversationSqliteStore.loadConversations().find((conversation) => conversation.id === conversationId);

    assert.equal(response.status, 500);
    assert.equal(parseRawJson(response).error.message, 'simulated user.message append failure');
    assert.deepEqual({
      status: internal.status,
      blockingItem: internal.blockingItem,
      idleExpiresAt: internal.idleExpiresAt,
      userMessageCount: internal.userMessageCount,
      updatedAt: internal.updatedAt
    }, snapshot);
    assert.deepEqual({
      status: persisted.status,
      blockingItem: persisted.blockingItem,
      idleExpiresAt: persisted.idleExpiresAt,
      userMessageCount: persisted.userMessageCount,
      updatedAt: persisted.updatedAt
    }, snapshot);
    assert.equal(internal.messageInFlightIds.has('client_event_rollback'), false);
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart send validates handling against effective selected model capabilities', async () => {
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    },
    modelCapability: {
      canSelectModel: true,
      selectedModel: 'text-only',
      models: [{ id: 'text-only', inputModalities: ['text'] }]
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-model-capability-' });
  try {
    const boundary = '----attachments-model-capability';
    const pngHeader = minimalPngBytes({ width: 1, height: 1 });
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_model_capability',
        capabilityVersion: attachmentTextOnlyModelCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: pngHeader.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: pngHeader }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });
    const parsed = JSON.parse(response.body.toString('utf8'));

    assert.equal(response.status, 415);
    assert.equal(parsed.error.code, 'UNSUPPORTED_MEDIA_TYPE');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart send allows image when selected model lacks modality metadata and adapter supports images', async () => {
  const adapter = codexNativeImageAttachmentAdapter({
    modelCapability: {
      canSelectModel: true,
      selectedModel: 'gpt-5.5',
      models: [{ id: 'gpt-5.5', label: 'GPT-5.5', source: MODEL_SOURCES.CODEX_CONFIG }]
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-inherited-model-capability-' });
  try {
    const internal = app.conversations.conversations.get(conversationId);
    const capabilityVersion = await app.conversations.currentCapabilityVersion(internal);
    const boundary = '----attachments-inherited-model-capability';
    const pngHeader = minimalPngBytes({ width: 1, height: 1 });
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_inherited_model_capability',
        capabilityVersion,
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: pngHeader.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: pngHeader }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    assert.equal(adapter.sent.length, 1);
    assert.equal(adapter.sent[0].attachments[0].kind, 'image');
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart duplicate in-flight clientMessageId rejects with stable conflict code', async () => {
  const { manager, device, eventStore } = createConversationManagerForTest({
    adapters: new Map([['codex', attachmentConversationAdapter()]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);
  const internal = manager.conversations.get(conversation.id);
  internal.messageInFlightIds.add('client_inflight');

  await assert.rejects(
    () => manager.commitAndDispatchMessage(internal, {
      text: 'inspect',
      clientMessageId: 'client_inflight',
      capabilityVersion: attachmentTestCapabilityVersion(),
      attachments: []
    }, device, {
      files: [{ name: 'a.txt', kind: 'textDocument', mimeType: 'text/plain', sizeBytes: 5, contentSha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824', contentSha256Prefix: '2cf24dba5fb0a30e26e83b2ac5b9e29e' }]
    }),
    (error) => error.status === 409 && error.code === 'message_already_in_flight'
  );
  assert.equal(eventStore.list(conversation.id, 0).some((event) => event.type === 'user.message'), false);
});

test('multipart locked conversations reject before creating scratch directories', async () => {
  const { conversationStatuses } = require('../daemon/src/conversation-protocol');
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([['codex', attachmentConversationAdapter()]])
  });
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);
  const internal = manager.conversations.get(conversation.id);
  let scratchCreateCount = 0;
  manager.attachmentScratchStore = {
    async createMessageScratch() {
      scratchCreateCount += 1;
      throw new Error('scratch should not be created while message start is locked');
    }
  };

  const cases = [
    { label: 'waiting input', apply: () => { internal.status = conversationStatuses.WAITING_INPUT; } },
    { label: 'waiting approval', apply: () => { internal.status = conversationStatuses.WAITING_APPROVAL; } },
    { label: 'model lock', apply: () => { internal.modelUpdateLock = true; } },
    { label: 'send lock', apply: () => { internal.sendLock = true; } }
  ];

  for (const item of cases) {
    internal.status = conversationStatuses.IDLE;
    internal.modelUpdateLock = false;
    internal.sendLock = false;
    item.apply();
    await assert.rejects(
      () => manager.sendMultipartMessage(conversation.id, {}, device),
      (error) => error.status === 409 && error.code === 'CONVERSATION_CONFLICT',
      item.label
    );
    assert.equal(scratchCreateCount, 0, item.label);
  }
});

test('multipart upload concurrency gate responds with retry-after', async () => {
  const { app, port, token, deviceId, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-rate-limit-' });
  try {
    app.conversations.multipartDeviceLocks.set(deviceId, true);
    const boundary = '----attachments-rate-limit';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_rate',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 429);
    assert.equal(response.headers['retry-after'], '5');
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'upload_rate_limited');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
  } finally {
    app.conversations.multipartDeviceLocks.delete(deviceId);
    await closeAttachmentConversationApp(app);
  }
});

test('multipart daemon-wide upload concurrency gate rejects the fifth active upload', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-daemon-rate-limit-' });
  try {
    app.conversations.multipartActiveCount = 4;
    const boundary = '----attachments-daemon-rate-limit';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_daemon_rate',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 429);
    assert.equal(response.headers['retry-after'], '5');
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'upload_rate_limited');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
  } finally {
    app.conversations.multipartActiveCount = 0;
    await closeAttachmentConversationApp(app);
  }
});

test('multipart upload allows different devices until the daemon-wide limit', async () => {
  const { app, adapter, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-rate-limit-allowed-' });
  try {
    app.conversations.multipartActiveCount = 3;
    const boundary = '----attachments-rate-limit-allowed';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect',
        clientMessageId: 'client_rate_allowed',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    assert.deepEqual(sentMessageTexts(adapter), ['inspect']);
    assert.equal(app.conversationEventStore.list(conversationId, 0).filter((event) => event.type === 'user.message').length, 1);
  } finally {
    app.conversations.multipartActiveCount = 0;
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send commits attachment metadata without raw scratch bytes', async () => {
  const { app, adapter, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-success-' });
  try {
    const boundary = '----attachments-success';
    const body = multipartBody({
      boundary,
      payload: {
        text: '',
        clientMessageId: 'client_success',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    assert.deepEqual(sentMessageTexts(adapter), ['']);
    const userMessage = app.conversationEventStore.list(conversationId, 0).find((event) => event.type === 'user.message');
    assert.equal(userMessage.text, '');
    assert.equal(userMessage.clientMessageId, 'client_success');
    assert.equal(typeof userMessage.payloadHash, 'string');
    assert.equal(userMessage.payloadHash.length, 64);
    assert.equal(userMessage.attachments.length, 1);
    assert.match(userMessage.attachments[0].id, /^att_0_[0-9a-f]{8}$/);
    assert.deepEqual({
      name: userMessage.attachments[0].name,
      kind: userMessage.attachments[0].kind,
      mimeType: userMessage.attachments[0].mimeType,
      sizeBytes: userMessage.attachments[0].sizeBytes,
      handling: userMessage.attachments[0].handling
    }, {
      name: 'a.txt',
      kind: 'textDocument',
      mimeType: 'text/plain',
      sizeBytes: 5,
      handling: 'text_extract'
    });
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'contentSha256'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'text'), false);
    const fs = require('node:fs');
    const scratchRoot = app.conversations.attachmentScratchStore.root;
    const scratchEntries = fs.existsSync(scratchRoot) ? fs.readdirSync(scratchRoot) : [];
    assert.deepEqual(scratchEntries, []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation image attachments commit metadata without preview storage', async () => {
  const adapter = codexNativeImageAttachmentAdapter();
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    dbPrefix: 'app-db-attachments-image-metadata-'
  });
  try {
    const boundary = '----attachments-image-metadata';
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_image_metadata',
        capabilityVersion: attachmentImageCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'preview.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'preview.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    const internal = app.conversations.conversations.get(conversationId);
    const userMessage = app.conversationEventStore.list(conversationId, 0).find((event) => event.type === 'user.message');
    const attachment = userMessage.attachments[0];
    assert.equal(attachment.name, 'preview.png');
    assert.equal(attachment.kind, 'image');
    assert.equal(attachment.mimeType, 'image/png');
    assert.equal(attachment.handling, 'native');
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'previewPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'previewUrl'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'previewHeaders'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'contentSha256'), false);

    app.conversations.recordAdapterEvent(internal, { type: 'conversation.completed' });
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);

    const previewRoute = `/api/conversations/${conversationId}/attachments/${attachment.id}/preview`;
    const preview = await requestRaw(port, 'GET', previewRoute, null, token);
    assert.equal(preview.status, 404);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send dispatches attachment-aware messages and cleans send_time scratch', async () => {
  const { app, adapter, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-dispatch-shape-' });
  try {
    const boundary = '----attachments-dispatch-shape';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect dispatch',
        clientMessageId: 'client_dispatch_shape',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    assert.equal(adapter.sent.length, 1);
    assert.equal(adapter.sent[0].text, 'inspect dispatch');
    assert.equal(adapter.sent[0].attachments.length, 1);
    assert.equal(adapter.sent[0].attachments[0].name, 'a.txt');
    assert.equal(adapter.sent[0].attachments[0].text, 'hello');
    assert.equal(typeof adapter.sent[0].attachments[0].scratchPath, 'string');
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart Codex native image scratch stays until terminal turn event', async () => {
  const adapter = codexNativeImageAttachmentAdapter();
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-turn-scratch-' });
  try {
    const { response, internal } = await sendCodexNativeImageTurnScratch({
      app,
      port,
      token,
      conversationId,
      clientMessageId: 'client_turn_scratch',
      text: 'inspect image',
      boundary: '----attachments-turn-scratch'
    });

    assert.equal(response.status, 200);
    assert.equal(adapter.sent[0].attachments[0].kind, 'image');
    assert.equal(adapter.sent[0].attachments[0].scratchLifetime, 'turn');
    assert.equal(attachmentScratchEntries(app).length, 1);

    app.conversations.recordAdapterEvent(internal, { type: 'conversation.completed' });
    await waitForAttachmentScratchCleanup(app);

    assert.deepEqual(attachmentScratchEntries(app), []);
    assert.deepEqual(internal.turnAttachmentScratches, []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart Codex native image scratch cleans on terminal assistant.message', async () => {
  const adapter = codexNativeImageAttachmentAdapter();
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-assistant-terminal-scratch-' });
  try {
    const { internal } = await sendCodexNativeImageTurnScratch({
      app,
      port,
      token,
      conversationId,
      clientMessageId: 'client_assistant_terminal_scratch',
      text: 'inspect terminal image',
      boundary: '----attachments-assistant-terminal-scratch'
    });

    app.conversations.recordAdapterEvent(internal, { type: 'assistant.message', text: 'done' });
    await waitForAttachmentScratchCleanup(app);

    assert.deepEqual(attachmentScratchEntries(app), []);
    assert.deepEqual(internal.turnAttachmentScratches, []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart Codex native image scratch cleans on adapter run.error', async () => {
  const adapter = codexNativeImageAttachmentAdapter();
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-run-error-scratch-' });
  try {
    const { internal } = await sendCodexNativeImageTurnScratch({
      app,
      port,
      token,
      conversationId,
      clientMessageId: 'client_run_error_scratch',
      text: 'inspect failing image',
      boundary: '----attachments-run-error-scratch'
    });

    app.conversations.recordAdapterEvent(internal, { type: 'run.error', message: 'adapter failed' });
    await waitForAttachmentScratchCleanup(app);

    assert.deepEqual(attachmentScratchEntries(app), []);
    assert.deepEqual(internal.turnAttachmentScratches, []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('manager cancellation cleans Codex native image turn scratch without adapter cancellation event', async () => {
  const adapter = codexNativeImageAttachmentAdapter();
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-cancel-turn-scratch-' });
  try {
    const { internal } = await sendCodexNativeImageTurnScratch({
      app,
      port,
      token,
      conversationId,
      clientMessageId: 'client_cancel_turn_scratch',
      text: 'inspect cancelled image',
      boundary: '----attachments-cancel-turn-scratch'
    });
    const device = app.auth.authenticate(`Bearer ${token}`);

    await app.conversations.cancelConversation(conversationId, device);

    assert.deepEqual(attachmentScratchEntries(app), []);
    assert.deepEqual(internal.turnAttachmentScratches, []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('attachment cleanup failure audit redacts path-bearing error messages', async () => {
  const { manager, auditLog } = createConversationManagerForTest();

  await manager.cleanupAttachmentScratch({ id: 'conv_cleanup' }, {
    dir: 'D:\\scratch\\fake',
    async cleanup() {
      throw new Error('unlink D:\\secret\\scratch\\msg_1 failed with raw bytes 89504e47');
    }
  });

  const record = auditLog.list().find((item) => item.type === 'conversation.attachment_cleanup_failed');
  assert.equal(record.conversationId, 'conv_cleanup');
  assert.equal(record.error, 'cleanup_failed');
  const auditRecordJson = JSON.stringify(record);
  assert.equal(auditRecordJson.includes('D:'), false);
  assert.equal(auditRecordJson.includes('secret'), false);
  assert.equal(auditRecordJson.includes('msg_1'), false);
  assert.equal(auditRecordJson.includes('89504e47'), false);

  await manager.cleanupAttachmentScratch({ id: 'conv_cleanup_code' }, {
    dir: 'D:\\scratch\\fake',
    async cleanup() {
      const error = new Error('unlink failed');
      error.code = 'EACCES D:\\secret\\scratch\\msg_2';
      throw error;
    }
  });

  const codeRecord = auditLog.list().find((item) => item.conversationId === 'conv_cleanup_code');
  assert.equal(codeRecord.error, 'cleanup_failed');
  const codeRecordJson = JSON.stringify(codeRecord);
  assert.equal(codeRecordJson.includes('D:'), false);
  assert.equal(codeRecordJson.includes('secret'), false);
  assert.equal(codeRecordJson.includes('msg_2'), false);
});

test('multipart committed clientMessageId retries idempotently and conflicts on different payloads', async () => {
  const { app, adapter, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-committed-idempotency-' });
  try {
    const payload = {
      text: 'inspect once',
      clientMessageId: 'client_committed_idempotency',
      capabilityVersion: attachmentTestCapabilityVersion(),
      attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
    };
    const firstBoundary = '----attachments-committed-idempotency-first';
    const first = multipartBody({
      boundary: firstBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const firstResponse = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, first, token, {
      'content-type': `multipart/form-data; boundary=${firstBoundary}`
    });

    const retryBoundary = '----attachments-committed-idempotency-retry';
    const retry = multipartBody({
      boundary: retryBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const retryResponse = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, retry, token, {
      'content-type': `multipart/form-data; boundary=${retryBoundary}`
    });

    const conflictBoundary = '----attachments-committed-idempotency-conflict';
    const conflict = multipartBody({
      boundary: conflictBoundary,
      payload: {
        ...payload,
        text: 'inspect different'
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const conflictResponse = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, conflict, token, {
      'content-type': `multipart/form-data; boundary=${conflictBoundary}`
    });

    assert.equal(firstResponse.status, 200);
    assert.equal(retryResponse.status, 200);
    assert.equal(conflictResponse.status, 409);
    assert.equal(parseRawJson(conflictResponse).error.code, 'message_idempotency_conflict');
    assert.deepEqual(sentMessageTexts(adapter), ['inspect once']);
    assert.equal(app.conversationEventStore.list(conversationId, 0).filter((event) => event.type === 'user.message').length, 1);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart running conversation permits same payload retry but rejects new attachment message', async () => {
  const { app, adapter, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-running-guard-' });
  try {
    const payload = {
      text: 'inspect running once',
      clientMessageId: 'client_running_first',
      capabilityVersion: attachmentTestCapabilityVersion(),
      attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
    };
    const firstBoundary = '----attachments-running-first';
    const first = multipartBody({
      boundary: firstBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const firstResponse = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, first, token, {
      'content-type': `multipart/form-data; boundary=${firstBoundary}`
    });

    const retryBoundary = '----attachments-running-retry';
    const retry = multipartBody({
      boundary: retryBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const retryResponse = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, retry, token, {
      'content-type': `multipart/form-data; boundary=${retryBoundary}`
    });

    const secondBoundary = '----attachments-running-second';
    const second = multipartBody({
      boundary: secondBoundary,
      payload: {
        text: 'inspect running twice',
        clientMessageId: 'client_running_second',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'b.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
      },
      files: [{ name: 'b.txt', mimeType: 'text/plain', bytes: Buffer.from('world', 'utf8') }]
    });
    const secondResponse = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, second, token, {
      'content-type': `multipart/form-data; boundary=${secondBoundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    assert.equal(firstResponse.status, 200);
    assert.equal(parseRawJson(firstResponse).conversation.status, 'running');
    assert.equal(retryResponse.status, 200);
    assert.equal(secondResponse.status, 409);
    assert.equal(parseRawJson(secondResponse).error.code, 'conversation_running');
    assert.deepEqual(sentMessageTexts(adapter), ['inspect running once']);
    assert.equal(events.filter((event) => event.type === 'user.message').length, 1);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart idempotency rebuilds from persisted user.message events after restart', async () => {
  const appDbPath = tempConversationDbPath('app-db-attachments-restart-idempotency-');
  const firstAdapter = attachmentConversationAdapter();
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter: firstAdapter, appDbPath });
  try {
    const payload = {
      text: 'persisted idempotency',
      clientMessageId: 'client_restart_idempotency',
      capabilityVersion: attachmentTestCapabilityVersion(),
      attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
    };
    const firstBoundary = '----attachments-restart-idempotency-first';
    const first = multipartBody({
      boundary: firstBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const firstResponse = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, first, token, {
      'content-type': `multipart/form-data; boundary=${firstBoundary}`
    });
    assert.equal(firstResponse.status, 200);
  } finally {
    await closeAttachmentConversationApp(app);
  }

  const restartedAdapter = attachmentConversationAdapter();
  const restarted = createApp({
    port: 0,
    mode: 'dev',
    devAdapters: true,
    appDbPath,
    conversationAdapters: new Map([['codex', restartedAdapter]])
  });
  await restarted.attachmentScratchCleanup;
  await new Promise((resolve) => restarted.server.listen(0, '127.0.0.1', resolve));
  const restartedPort = restarted.server.address().port;
  try {
    const payload = {
      text: 'persisted idempotency',
      clientMessageId: 'client_restart_idempotency',
      capabilityVersion: attachmentTestCapabilityVersion(),
      attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
    };
    const retryBoundary = '----attachments-restart-idempotency-retry';
    const retry = multipartBody({
      boundary: retryBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const retryResponse = await requestRaw(restartedPort, 'POST', `/api/conversations/${conversationId}/messages`, retry, token, {
      'content-type': `multipart/form-data; boundary=${retryBoundary}`
    });

    const conflictBoundary = '----attachments-restart-idempotency-conflict';
    const conflict = multipartBody({
      boundary: conflictBoundary,
      payload: {
        ...payload,
        text: 'persisted idempotency changed'
      },
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const conflictResponse = await requestRaw(restartedPort, 'POST', `/api/conversations/${conversationId}/messages`, conflict, token, {
      'content-type': `multipart/form-data; boundary=${conflictBoundary}`
    });

    assert.equal(retryResponse.status, 200);
    assert.equal(conflictResponse.status, 409);
    assert.equal(parseRawJson(conflictResponse).error.code, 'message_idempotency_conflict');
    assert.deepEqual(restartedAdapter.sent, []);
    assert.equal(restarted.conversationEventStore.list(conversationId, 0).filter((event) => event.type === 'user.message').length, 1);
    assert.deepEqual(attachmentScratchEntries(restarted), []);
  } finally {
    await closeAttachmentConversationApp(restarted);
  }
});

test('multipart post-commit adapter failure records run error and consumes clientMessageId', async () => {
  const adapter = attachmentConversationAdapter({ failAfterSend: true });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-post-commit-failure-' });
  try {
    const payload = {
      text: 'inspect failure',
      clientMessageId: 'client_post_commit_failure',
      capabilityVersion: attachmentTestCapabilityVersion(),
      attachments: [{ field: 'files[0]', name: 'a.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: 5 }]
    };
    const firstBoundary = '----attachments-post-commit-failure-first';
    const first = multipartBody({
      boundary: firstBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, first, token, {
      'content-type': `multipart/form-data; boundary=${firstBoundary}`
    });

    const retryBoundary = '----attachments-post-commit-failure-retry';
    const retry = multipartBody({
      boundary: retryBoundary,
      payload,
      files: [{ name: 'a.txt', mimeType: 'text/plain', bytes: Buffer.from('hello', 'utf8') }]
    });
    const retried = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, retry, token, {
      'content-type': `multipart/form-data; boundary=${retryBoundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const publicConversation = app.conversations.getConversation(conversationId, app.auth.authenticate(`Bearer ${token}`));
    assert.equal(failed.status, 500);
    assert.equal(parseRawJson(failed).error.message, 'adapter failed after commit');
    assert.equal(events.filter((event) => event.type === 'user.message').length, 1);
    assert.equal(events.some((event) => event.type === 'run.error' && event.message === 'adapter failed after commit'), true);
    assert.equal(publicConversation.status, 'failed');
    assert.equal(retried.status, 200);
    assert.equal(parseRawJson(retried).conversation.status, 'failed');
    assert.deepEqual(sentMessageTexts(adapter), ['inspect failure']);
    assert.equal(app.conversationEventStore.list(conversationId, 0).filter((event) => event.type === 'user.message').length, 1);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment dispatch failure redacts path-bearing errors in HTTP and run.error', async () => {
  const adapterId = 'claude';
  let leakedPath = null;
  const adapter = attachmentConversationAdapter({
    sendError: (message) => {
      leakedPath = message.attachments[0].scratchPath;
      return new Error(`ENOENT: open ${leakedPath} failed with raw bytes 89504e47`);
    },
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-dispatch-redaction-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const boundary = '----attachments-dispatch-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect failure',
        clientMessageId: 'client_dispatch_redaction',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const errorBody = parseRawJson(failed).error;
    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const userMessage = events.find((event) => event.type === 'user.message');
    const responseJson = JSON.stringify(errorBody);
    const runErrorJson = JSON.stringify(runError);
    const committedAttachmentJson = JSON.stringify(userMessage.attachments[0]);
    assert.equal(failed.status, 502);
    assert.equal(errorBody.code, 'attachment_dispatch_failed');
    assert.equal(errorBody.message, 'Attachment dispatch failed');
    assert.equal(responseJson.includes(leakedPath), false);
    assert.equal(responseJson.includes('D:\\secret'), false);
    assert.equal(responseJson.includes('file_0.bin'), false);
    assert.equal(responseJson.includes('89504e47'), false);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(runErrorJson.includes(leakedPath), false);
    assert.equal(runErrorJson.includes('D:\\secret'), false);
    assert.equal(runErrorJson.includes('file_0.bin'), false);
    assert.equal(runErrorJson.includes('89504e47'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'bytes'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'contentSha256'), false);
    assert.equal(committedAttachmentJson.includes(leakedPath), false);
    assert.equal(committedAttachmentJson.includes('89504e47'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment dispatch failure redacts nested details paths in HTTP and run.error', async () => {
  const adapterId = 'claude';
  let leakedPath = null;
  const adapter = attachmentConversationAdapter({
    sendError: (message) => {
      leakedPath = message.attachments[0].scratchPath;
      const error = new Error('adapter write failed');
      error.status = 500;
      error.details = { path: leakedPath };
      return error;
    },
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-nested-details-redaction-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const boundary = '----attachments-nested-details-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect nested details failure',
        clientMessageId: 'client_nested_details_redaction',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const errorBody = parseRawJson(failed).error;
    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const userMessage = events.find((event) => event.type === 'user.message');
    const responseJson = JSON.stringify(errorBody);
    const runErrorJson = JSON.stringify(runError);
    const committedAttachmentJson = JSON.stringify(userMessage.attachments[0]);
    assert.equal(failed.status, 502);
    assert.equal(errorBody.code, 'attachment_dispatch_failed');
    assert.equal(errorBody.message, 'Attachment dispatch failed');
    assert.equal(responseJson.includes(leakedPath), false);
    assert.equal(responseJson.includes('D:\\secret'), false);
    assert.equal(responseJson.includes('file_0.bin'), false);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(runErrorJson.includes(leakedPath), false);
    assert.equal(runErrorJson.includes('D:\\secret'), false);
    assert.equal(runErrorJson.includes('file_0.bin'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'bytes'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'contentSha256'), false);
    assert.equal(committedAttachmentJson.includes(leakedPath), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment dispatch failure redacts raw payload errors without path-like strings', async () => {
  const adapterId = 'claude';
  const rawHex = '89504e470d0a1a0a0000000d4948445200000001000000010806000000';
  const base64Image = Buffer.concat([
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 })
  ]).toString('base64');
  const base64Marker = base64Image.slice(0, 24);
  const adapter = attachmentConversationAdapter({
    sendError: () => {
      const error = new Error(`provider rejected image: ${base64Image}`);
      error.rawBytes = `${rawHex}abcdef1234567890`;
      return error;
    },
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-raw-dispatch-redaction-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const boundary = '----attachments-raw-dispatch-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect raw dispatch failure',
        clientMessageId: 'client_raw_dispatch_redaction',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const errorBody = parseRawJson(failed).error;
    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const userMessage = events.find((event) => event.type === 'user.message');
    const responseJson = JSON.stringify(errorBody);
    const eventsJson = JSON.stringify(events);
    const committedAttachmentJson = JSON.stringify(userMessage.attachments[0]);
    assert.equal(failed.status, 502);
    assert.equal(errorBody.code, 'attachment_dispatch_failed');
    assert.equal(errorBody.message, 'Attachment dispatch failed');
    assert.equal(responseJson.includes(base64Marker), false);
    assert.equal(responseJson.includes(rawHex), false);
    assert.equal(responseJson.includes('rawBytes'), false);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(eventsJson.includes(base64Marker), false);
    assert.equal(eventsJson.includes(rawHex), false);
    assert.equal(eventsJson.includes('rawBytes'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'bytes'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'contentSha256'), false);
    assert.equal(committedAttachmentJson.includes(base64Marker), false);
    assert.equal(committedAttachmentJson.includes(rawHex), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart text attachment dispatch failure redacts echoed wrapper and contents', async () => {
  const privateText = 'private document contents';
  const wrapper = '<attachment name="secret.txt" mime="text/plain">\nprivate document contents\n</attachment>';
  const cases = [
    {
      suffix: 'message',
      clientMessageId: 'client_text_dispatch_message_redaction',
      sendError: () => new Error(wrapper)
    },
    {
      suffix: 'details',
      clientMessageId: 'client_text_dispatch_details_redaction',
      sendError: () => {
        const error = new Error('adapter write failed');
        error.status = 500;
        error.details = { echoed: privateText };
        return error;
      }
    }
  ];

  for (const item of cases) {
    const adapterId = 'codex';
    const adapter = attachmentConversationAdapter({ sendError: item.sendError });
    const { app, port, token, conversationId } = await createAttachmentConversationApp({
      adapter,
      adapterId,
      dbPrefix: `app-db-attachments-text-dispatch-${item.suffix}-`
    });
    try {
      const textBytes = Buffer.from(privateText, 'utf8');
      const boundary = `----attachments-text-dispatch-${item.suffix}`;
      const body = multipartBody({
        boundary,
        payload: {
          text: 'summarize text',
          clientMessageId: item.clientMessageId,
          capabilityVersion: attachmentTestCapabilityVersion(adapterId),
          attachments: [{ field: 'files[0]', name: 'secret.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
        },
        files: [{ name: 'secret.txt', mimeType: 'text/plain', bytes: textBytes }]
      });
      const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
        'content-type': `multipart/form-data; boundary=${boundary}`
      });

      const errorBody = parseRawJson(failed).error;
      const events = app.conversationEventStore.list(conversationId, 0);
      const runError = events.find((event) => event.type === 'run.error');
      const responseJson = JSON.stringify(errorBody);
      const runErrorJson = JSON.stringify(runError);
      const eventsJson = JSON.stringify(events);
      assert.equal(failed.status, 502);
      assert.equal(errorBody.code, 'attachment_dispatch_failed');
      assert.equal(errorBody.message, 'Attachment dispatch failed');
      assert.equal(runError.message, 'Attachment dispatch failed');
      assert.equal(runError.code, 'attachment_dispatch_failed');
      assert.equal(runError.status, 502);
      assert.equal(responseJson.includes('<attachment'), false);
      assert.equal(responseJson.includes('secret.txt'), false);
      assert.equal(responseJson.includes(privateText), false);
      assert.equal(runErrorJson.includes('secret.txt'), false);
      assert.equal(eventsJson.includes('<attachment'), false);
      assert.equal(eventsJson.includes(privateText), false);
      assert.deepEqual(attachmentScratchEntries(app), []);
    } finally {
      await closeAttachmentConversationApp(app);
    }
  }
});

test('multipart text attachment dispatch failure redacts short exact text echoes', async () => {
  const adapterId = 'codex';
  const privateText = 'token=xyz';
  const adapter = attachmentConversationAdapter({
    sendError: () => {
      const error = new Error(privateText);
      error.status = 500;
      error.details = { echoed: privateText };
      return error;
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-short-text-dispatch-redaction-'
  });
  try {
    const textBytes = Buffer.from(privateText, 'utf8');
    const boundary = '----attachments-short-text-dispatch-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'summarize short text',
        clientMessageId: 'client_short_text_dispatch_redaction',
        capabilityVersion: attachmentTestCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'secret.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
      },
      files: [{ name: 'secret.txt', mimeType: 'text/plain', bytes: textBytes }]
    });
    const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const errorBody = parseRawJson(failed).error;
    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const responseJson = JSON.stringify(errorBody);
    const eventsJson = JSON.stringify(events);
    assert.equal(failed.status, 502);
    assert.equal(errorBody.code, 'attachment_dispatch_failed');
    assert.equal(errorBody.message, 'Attachment dispatch failed');
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(responseJson.includes(privateText), false);
    assert.equal(eventsJson.includes(privateText), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart text attachment dispatch failure redacts partial private text echoes', async () => {
  const adapterId = 'codex';
  const privateText = 'private document contents with customer credentials';
  const partialText = 'private document';
  const partialWrapper = '<attachment name="secret.txt" mime="text/plain">\nprivate...';
  const adapter = attachmentConversationAdapter({
    sendError: () => {
      const error = new Error(`provider rejected ${partialText}`);
      error.status = 500;
      error.details = { preview: partialWrapper };
      return error;
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-partial-text-dispatch-redaction-'
  });
  try {
    const textBytes = Buffer.from(privateText, 'utf8');
    const boundary = '----attachments-partial-text-dispatch-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'summarize text partial failure',
        clientMessageId: 'client_partial_text_dispatch_redaction',
        capabilityVersion: attachmentTestCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'secret.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
      },
      files: [{ name: 'secret.txt', mimeType: 'text/plain', bytes: textBytes }]
    });
    const failed = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const errorBody = parseRawJson(failed).error;
    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const responseJson = JSON.stringify(errorBody);
    const runErrorJson = JSON.stringify(runError);
    const eventsJson = JSON.stringify(events);
    assert.equal(failed.status, 502);
    assert.equal(errorBody.code, 'attachment_dispatch_failed');
    assert.equal(errorBody.message, 'Attachment dispatch failed');
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    for (const leaked of ['<attachment', 'secret.txt', partialText, privateText]) {
      assert.equal(responseJson.includes(leaked), false);
      assert.equal(runErrorJson.includes(leaked), false);
    }
    for (const leaked of ['<attachment', partialText, privateText]) {
      assert.equal(eventsJson.includes(leaked), false);
    }
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment adapter events redact path-bearing run errors and warnings', async () => {
  const adapterId = 'claude';
  const leakedPath = 'D:\\secret\\scratch\\file_0.bin';
  const leakText = `ENOENT: open ${leakedPath} failed with raw bytes 89504e47`;
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      { type: 'protocol.warning', text: leakText, message: leakText, visible: true },
      { type: 'run.error', message: leakText, code: 'ENOENT', detail: { path: leakedPath, raw: '89504e47' } }
    ],
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-event-redaction-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const boundary = '----attachments-event-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect post-send event failure',
        clientMessageId: 'client_event_redaction',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const protocolWarning = events.find((event) => event.type === 'protocol.warning');
    const userMessage = events.find((event) => event.type === 'user.message');
    const responseJson = JSON.stringify(parseRawJson(response));
    const eventsJson = JSON.stringify(events);
    const committedAttachmentJson = JSON.stringify(userMessage.attachments[0]);
    assert.equal(response.status, 200);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(protocolWarning.text, 'Attachment dispatch failed');
    assert.equal(protocolWarning.message, 'Attachment dispatch failed');
    assert.equal(responseJson.includes(leakedPath), false);
    assert.equal(responseJson.includes('file_0.bin'), false);
    assert.equal(responseJson.includes('89504e47'), false);
    assert.equal(eventsJson.includes(leakedPath), false);
    assert.equal(eventsJson.includes('D:\\secret'), false);
    assert.equal(eventsJson.includes('file_0.bin'), false);
    assert.equal(eventsJson.includes('89504e47'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'bytes'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'contentSha256'), false);
    assert.equal(committedAttachmentJson.includes(leakedPath), false);
    assert.equal(committedAttachmentJson.includes('89504e47'), false);
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart text attachment adapter events redact echoed wrapper and contents', async () => {
  const adapterId = 'codex';
  const privateText = 'private document contents';
  const wrapper = '<attachment name="secret.txt" mime="text/plain">\nprivate document contents\n</attachment>';
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      { type: 'protocol.warning', text: wrapper, message: wrapper, visible: true },
      { type: 'run.error', message: 'provider rejected text', details: { echoed: privateText } }
    ]
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-text-event-redaction-'
  });
  try {
    const textBytes = Buffer.from(privateText, 'utf8');
    const boundary = '----attachments-text-event-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'summarize text event failure',
        clientMessageId: 'client_text_event_redaction',
        capabilityVersion: attachmentTestCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'secret.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
      },
      files: [{ name: 'secret.txt', mimeType: 'text/plain', bytes: textBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const protocolWarning = events.find((event) => event.type === 'protocol.warning');
    const responseJson = JSON.stringify(parseRawJson(response));
    const runErrorJson = JSON.stringify(runError);
    const protocolWarningJson = JSON.stringify(protocolWarning);
    const eventsJson = JSON.stringify(events);
    assert.equal(response.status, 200);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(protocolWarning.text, 'Attachment dispatch failed');
    assert.equal(protocolWarning.message, 'Attachment dispatch failed');
    assert.equal(responseJson.includes('<attachment'), false);
    assert.equal(responseJson.includes('secret.txt'), false);
    assert.equal(responseJson.includes(privateText), false);
    assert.equal(runErrorJson.includes('secret.txt'), false);
    assert.equal(protocolWarningJson.includes('secret.txt'), false);
    assert.equal(eventsJson.includes('<attachment'), false);
    assert.equal(eventsJson.includes(privateText), false);
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart text attachment adapter events redact short exact text echoes', async () => {
  const adapterId = 'codex';
  const privateText = 'token=xyz';
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      { type: 'protocol.warning', text: privateText, message: privateText, visible: true },
      { type: 'system.notice', text: privateText, details: { echoed: privateText }, visible: true },
      { type: 'run.error', message: 'provider rejected text', details: { echoed: privateText } }
    ]
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-short-text-event-redaction-'
  });
  try {
    const textBytes = Buffer.from(privateText, 'utf8');
    const boundary = '----attachments-short-text-event-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'summarize short text event failure',
        clientMessageId: 'client_short_text_event_redaction',
        capabilityVersion: attachmentTestCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'secret.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
      },
      files: [{ name: 'secret.txt', mimeType: 'text/plain', bytes: textBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const protocolWarnings = events.filter((event) => event.type === 'protocol.warning');
    const eventsJson = JSON.stringify(events);
    assert.equal(response.status, 200);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(protocolWarnings.length, 2);
    for (const warning of protocolWarnings) {
      assert.equal(warning.text, 'Attachment dispatch failed');
      assert.equal(warning.message, 'Attachment dispatch failed');
    }
    assert.equal(eventsJson.includes(privateText), false);
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart text attachment adapter events redact partial private text echoes', async () => {
  const adapterId = 'codex';
  const privateText = 'private document contents with customer credentials';
  const partialText = 'private document';
  const partialWrapper = '<attachment name="secret.txt" mime="text/plain">\nprivate...';
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      { type: 'protocol.warning', text: partialWrapper, message: partialWrapper, visible: true },
      { type: 'run.error', message: `provider rejected ${partialText}`, details: { echoed: partialText } }
    ]
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-partial-text-event-redaction-'
  });
  try {
    const textBytes = Buffer.from(privateText, 'utf8');
    const boundary = '----attachments-partial-text-event-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'summarize text partial event failure',
        clientMessageId: 'client_partial_text_event_redaction',
        capabilityVersion: attachmentTestCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'secret.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
      },
      files: [{ name: 'secret.txt', mimeType: 'text/plain', bytes: textBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const protocolWarning = events.find((event) => event.type === 'protocol.warning');
    const responseJson = JSON.stringify(parseRawJson(response));
    const runErrorJson = JSON.stringify(runError);
    const protocolWarningJson = JSON.stringify(protocolWarning);
    const eventsJson = JSON.stringify(events);
    assert.equal(response.status, 200);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(protocolWarning.text, 'Attachment dispatch failed');
    assert.equal(protocolWarning.message, 'Attachment dispatch failed');
    for (const leaked of ['<attachment', 'secret.txt', partialText, privateText]) {
      assert.equal(responseJson.includes(leaked), false);
      assert.equal(runErrorJson.includes(leaked), false);
      assert.equal(protocolWarningJson.includes(leaked), false);
    }
    for (const leaked of ['<attachment', partialText, privateText]) {
      assert.equal(eventsJson.includes(leaked), false);
    }
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment adapter events redact raw payloads without path-like strings', async () => {
  const adapterId = 'claude';
  const rawHex = '89504e470d0a1a0a0000000d4948445200000001000000010806000000';
  const base64Image = Buffer.concat([
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 })
  ]).toString('base64');
  const base64Marker = base64Image.slice(0, 24);
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      { type: 'protocol.warning', text: 'provider warning', payload: { image: base64Image }, visible: true },
      { type: 'run.error', message: 'provider rejected image', detail: { rawBytes: `${rawHex}abcdef1234567890` } }
    ],
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-raw-event-redaction-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const boundary = '----attachments-raw-event-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect raw event failure',
        clientMessageId: 'client_raw_event_redaction',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const protocolWarning = events.find((event) => event.type === 'protocol.warning');
    const userMessage = events.find((event) => event.type === 'user.message');
    const eventsJson = JSON.stringify(events);
    const committedAttachmentJson = JSON.stringify(userMessage.attachments[0]);
    assert.equal(response.status, 200);
    assert.equal(runError.message, 'Attachment dispatch failed');
    assert.equal(runError.code, 'attachment_dispatch_failed');
    assert.equal(runError.status, 502);
    assert.equal(protocolWarning.text, 'Attachment dispatch failed');
    assert.equal(protocolWarning.message, 'Attachment dispatch failed');
    assert.equal(eventsJson.includes(rawHex), false);
    assert.equal(eventsJson.includes(base64Marker), false);
    assert.equal(eventsJson.includes('rawBytes'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'bytes'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'contentSha256'), false);
    assert.equal(committedAttachmentJson.includes(rawHex), false);
    assert.equal(committedAttachmentJson.includes(base64Marker), false);
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment adapter events preserve ordinary Windows repo scratch paths', async () => {
  const adapterId = 'claude';
  const repoPath = 'D:\\Repo\\scratch\\file_0.bin';
  const warningMessage = `provider warning while reading ${repoPath}`;
  const runErrorMessage = `provider failed while reading ${repoPath}`;
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      { type: 'protocol.warning', text: warningMessage, message: warningMessage, visible: true },
      { type: 'run.error', message: runErrorMessage, code: 'ADAPTER_FAILURE' }
    ],
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-repo-path-event-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const boundary = '----attachments-repo-path-event';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect repo path event',
        clientMessageId: 'client_repo_path_event',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const protocolWarning = events.find((event) => event.type === 'protocol.warning');
    assert.equal(response.status, 200);
    assert.equal(protocolWarning.text, warningMessage);
    assert.equal(protocolWarning.message, warningMessage);
    assert.equal(runError.message, runErrorMessage);
    assert.equal(runError.code, 'ADAPTER_FAILURE');
    assert.equal(protocolWarning.text.includes(repoPath), true);
    assert.equal(runError.message.includes(repoPath), true);
    assert.equal(events.some((event) => event.code === 'attachment_dispatch_failed'), false);
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment dispatch errors preserve ordinary Windows repo scratch paths', async () => {
  const adapterId = 'claude';
  const repoPath = 'D:\\Repo\\scratch\\file_0.bin';
  const errorMessage = `adapter failed while loading ${repoPath}`;
  const adapter = attachmentConversationAdapter({
    sendError: () => {
      const error = new Error(errorMessage);
      error.status = 500;
      error.code = 'ADAPTER_FAILURE';
      return error;
    },
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        pdf: 'unsupported',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-repo-path-dispatch-'
  });
  try {
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const boundary = '----attachments-repo-path-dispatch';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect repo path dispatch',
        clientMessageId: 'client_repo_path_dispatch',
        capabilityVersion: attachmentImageCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'a.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'a.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const errorBody = parseRawJson(response).error;
    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    assert.equal(response.status, 500);
    assert.equal(errorBody.code, 'ADAPTER_FAILURE');
    assert.equal(errorBody.message, errorMessage);
    assert.notEqual(errorBody.code, 'attachment_dispatch_failed');
    assert.equal(runError.message, errorMessage);
    assert.equal(errorBody.message.includes(repoPath), true);
    assert.equal(runError.message.includes(repoPath), true);
    assert.equal(events.some((event) => event.code === 'attachment_dispatch_failed'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart attachment system notices redact attachment diagnostics', async () => {
  const adapterId = 'codex';
  const privateText = 'private document contents with customer credentials';
  const partialText = 'private document';
  const partialWrapper = '<attachment name="secret.txt" mime="text/plain">\nprivate...';
  const rawHex = '89504e470d0a1a0a0000000d4948445200000001000000010806000000';
  let scratchPath;
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      {
        type: 'system.notice',
        text: 'attachment dispatch diagnostic',
        details: {
          scratchPath: null,
          rawBytes: `${rawHex}abcdef1234567890`,
          preview: partialWrapper,
          echoed: partialText
        },
        visible: true
      }
    ]
  });
  const originalStartConversation = adapter.startConversation.bind(adapter);
  adapter.startConversation = async (...args) => {
    const handle = await originalStartConversation(...args);
    handle.sendUserMessage = async (message) => {
      scratchPath = message.attachments[0].scratchPath;
      adapter.sent.length = 0;
      adapter.sent.push(message);
      args[0].onEvent({
        type: 'system.notice',
        text: `attachment diagnostic ${scratchPath}`,
        details: {
          scratchPath,
          rawBytes: `${rawHex}abcdef1234567890`,
          preview: partialWrapper,
          echoed: partialText
        },
        visible: true
      });
    };
    return handle;
  };
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    adapterId,
    dbPrefix: 'app-db-attachments-system-notice-redaction-'
  });
  try {
    const textBytes = Buffer.from(privateText, 'utf8');
    const boundary = '----attachments-system-notice-redaction';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'summarize text notice diagnostics',
        clientMessageId: 'client_system_notice_redaction',
        capabilityVersion: attachmentTestCapabilityVersion(adapterId),
        attachments: [{ field: 'files[0]', name: 'secret.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
      },
      files: [{ name: 'secret.txt', mimeType: 'text/plain', bytes: textBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    const events = app.conversationEventStore.list(conversationId, 0);
    const notice = events.find((event) => event.type === 'system.notice');
    const warning = events.find((event) => event.type === 'protocol.warning');
    const eventsJson = JSON.stringify(events);
    assert.equal(response.status, 200);
    assert.equal(notice, undefined);
    assert.equal(warning.text, 'Attachment dispatch failed');
    assert.equal(warning.message, 'Attachment dispatch failed');
    for (const leaked of [scratchPath, rawHex, '<attachment', partialText, privateText]) {
      assert.equal(eventsJson.includes(leaked), false);
    }
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('conversation adapter events preserve raw-looking payloads without attachment context', async () => {
  const rawHex = '89504e470d0a1a0a0000000d4948445200000001000000010806000000';
  const base64Image = Buffer.concat([
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 })
  ]).toString('base64');
  const base64Marker = base64Image.slice(0, 24);
  const adapter = attachmentConversationAdapter({
    onSendEvents: [
      { type: 'protocol.warning', text: 'provider warning', payload: { image: base64Image }, visible: true },
      { type: 'run.error', message: 'provider rejected image', detail: { rawBytes: `${rawHex}abcdef1234567890` } }
    ]
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    dbPrefix: 'app-db-no-attachment-raw-event-'
  });
  try {
    const response = await request(port, 'POST', `/api/conversations/${conversationId}/messages`, {
      text: 'ordinary provider event'
    }, token);

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const protocolWarning = events.find((event) => event.type === 'protocol.warning');
    const eventsJson = JSON.stringify(events);
    assert.equal(response.status, 200);
    assert.equal(runError.message, 'provider rejected image');
    assert.equal(runError.detail.rawBytes, `${rawHex}abcdef1234567890`);
    assert.equal(protocolWarning.text, 'provider warning');
    assert.equal(protocolWarning.payload.image, base64Image);
    assert.equal(eventsJson.includes(rawHex), true);
    assert.equal(eventsJson.includes(base64Marker), true);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('conversation dispatch errors preserve raw-looking payloads without attachment context', async () => {
  const base64Image = Buffer.concat([
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 }),
    minimalPngBytes({ width: 1, height: 1 })
  ]).toString('base64');
  const base64Marker = base64Image.slice(0, 24);
  const adapter = attachmentConversationAdapter({
    sendError: () => new Error(`provider rejected image: ${base64Image}`)
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    dbPrefix: 'app-db-no-attachment-raw-dispatch-'
  });
  try {
    const response = await request(port, 'POST', `/api/conversations/${conversationId}/messages`, {
      text: 'ordinary provider failure'
    }, token);

    const events = app.conversationEventStore.list(conversationId, 0);
    const runError = events.find((event) => event.type === 'run.error');
    const responseJson = JSON.stringify(response.body);
    const eventsJson = JSON.stringify(events);
    assert.equal(response.status, 500);
    assert.equal(response.body.error.code, 'ERROR');
    assert.equal(response.body.error.message.includes(base64Marker), true);
    assert.equal(runError.message.includes(base64Marker), true);
    assert.equal(responseJson.includes(base64Marker), true);
    assert.equal(eventsJson.includes(base64Marker), true);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send commits multiple attachment metadata entries in order', async () => {
  const { payloadHashForNormalizedInput } = require('../daemon/src/attachment-hashes');
  const crypto = require('node:crypto');
  const fs = require('node:fs');
  const firstBytes = Buffer.from('first attachment', 'utf8');
  const secondBytes = Buffer.from('second attachment', 'utf8');
  const { app, adapter, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-multi-success-' });
  try {
    const boundary = '----attachments-multi-success';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect both',
        clientMessageId: 'client_multi_success',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [
          { field: 'files[0]', name: 'first.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: firstBytes.length },
          { field: 'files[1]', name: 'second.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: secondBytes.length }
        ]
      },
      files: [
        { name: 'first.txt', mimeType: 'text/plain', bytes: firstBytes },
        { name: 'second.txt', mimeType: 'text/plain', bytes: secondBytes }
      ]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    assert.deepEqual(sentMessageTexts(adapter), ['inspect both']);
    const userMessage = app.conversationEventStore.list(conversationId, 0).find((event) => event.type === 'user.message');
    assert.deepEqual(userMessage.attachments.map((attachment) => ({
      name: attachment.name,
      kind: attachment.kind,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      handling: attachment.handling
    })), [
      { name: 'first.txt', kind: 'textDocument', mimeType: 'text/plain', sizeBytes: firstBytes.length, handling: 'text_extract' },
      { name: 'second.txt', kind: 'textDocument', mimeType: 'text/plain', sizeBytes: secondBytes.length, handling: 'text_extract' }
    ]);
    const expectedHash = payloadHashForNormalizedInput({
      text: 'inspect both',
      attachments: [
        {
          contentSha256Prefix: crypto.createHash('sha256').update(firstBytes).digest('hex').slice(0, 32),
          index: 0,
          kind: 'textDocument',
          mimeType: 'text/plain',
          name: 'first.txt',
          sizeBytes: firstBytes.length
        },
        {
          contentSha256Prefix: crypto.createHash('sha256').update(secondBytes).digest('hex').slice(0, 32),
          index: 1,
          kind: 'textDocument',
          mimeType: 'text/plain',
          name: 'second.txt',
          sizeBytes: secondBytes.length
        }
      ]
    });
    assert.equal(userMessage.payloadHash, expectedHash);
    const scratchRoot = app.conversations.attachmentScratchStore.root;
    const scratchEntries = fs.existsSync(scratchRoot) ? fs.readdirSync(scratchRoot) : [];
    assert.deepEqual(scratchEntries, []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send accepts PDF bytes when selected capabilities stage PDFs', async () => {
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'unsupported',
        pdf: 'staged_path',
        textDocument: 'text_extract'
      }
    }
  });
  const pdfBytes = Buffer.from('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n', 'utf8');
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-pdf-success-' });
  try {
    const boundary = '----attachments-pdf-success';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect pdf',
        clientMessageId: 'client_pdf_success',
        capabilityVersion: attachmentPdfCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'report.pdf', mimeType: 'application/pdf', kind: 'pdf', sizeBytes: pdfBytes.length }]
      },
      files: [{ name: 'report.pdf', mimeType: 'application/pdf', bytes: pdfBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    const userMessage = app.conversationEventStore.list(conversationId, 0).find((event) => event.type === 'user.message');
    assert.deepEqual({
      name: userMessage.attachments[0].name,
      kind: userMessage.attachments[0].kind,
      mimeType: userMessage.attachments[0].mimeType,
      sizeBytes: userMessage.attachments[0].sizeBytes,
      handling: userMessage.attachments[0].handling
    }, {
      name: 'report.pdf',
      kind: 'pdf',
      mimeType: 'application/pdf',
      sizeBytes: pdfBytes.length,
      handling: 'staged_path'
    });
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'contentSha256'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(userMessage.attachments[0], 'text'), false);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart conversation send rejects PDF kind with non-PDF bytes before committing user.message', async () => {
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'unsupported',
        pdf: 'staged_path',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-pdf-invalid-' });
  try {
    const boundary = '----attachments-pdf-invalid';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect pdf',
        clientMessageId: 'client_pdf_invalid',
        capabilityVersion: attachmentPdfCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'report.pdf', mimeType: 'application/pdf', kind: 'pdf', sizeBytes: 9 }]
      },
      files: [{ name: 'report.pdf', mimeType: 'application/pdf', bytes: Buffer.from('not a pdf', 'utf8') }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 415);
    assert.equal(JSON.parse(response.body.toString('utf8')).error.code, 'UNSUPPORTED_MEDIA_TYPE');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart oversized PDF bytes reject before committing user.message', async () => {
  const adapter = attachmentConversationAdapter({
    capabilities: {
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'unsupported',
        pdf: 'staged_path',
        textDocument: 'text_extract'
      }
    }
  });
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ adapter, dbPrefix: 'app-db-attachments-pdf-too-large-' });
  try {
    const pdfBytes = Buffer.concat([
      Buffer.from('%PDF-1.7\n', 'utf8'),
      Buffer.alloc((20 * 1024 * 1024) + 1)
    ]);
    const boundary = '----attachments-pdf-too-large';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect pdf',
        clientMessageId: 'client_pdf_too_large',
        capabilityVersion: attachmentPdfCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'large.pdf', mimeType: 'application/pdf', kind: 'pdf', sizeBytes: pdfBytes.length }]
      },
      files: [{ name: 'large.pdf', mimeType: 'application/pdf', bytes: pdfBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 413);
    assert.equal(parseRawJson(response).error.code, 'ATTACHMENT_LIMIT_EXCEEDED');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('multipart text_extract context budget rejects before committing user.message', async () => {
  const { app, port, token, conversationId } = await createAttachmentConversationApp({ dbPrefix: 'app-db-attachments-context-budget-' });
  try {
    const textBytes = Buffer.from('a'.repeat(20 * 1024), 'utf8');
    const boundary = '----attachments-context-budget';
    const body = multipartBody({
      boundary,
      payload: {
        text: 'summarize text',
        clientMessageId: 'client_context_budget',
        capabilityVersion: attachmentTestCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'large.txt', mimeType: 'text/plain', kind: 'textDocument', sizeBytes: textBytes.length }]
      },
      files: [{ name: 'large.txt', mimeType: 'text/plain', bytes: textBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 413);
    assert.equal(parseRawJson(response).error.code, 'ATTACHMENT_CONTEXT_BUDGET_EXCEEDED');
    assert.equal(app.conversationEventStore.list(conversationId, 0).some((event) => event.type === 'user.message'), false);
    assert.deepEqual(attachmentScratchEntries(app), []);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});

test('V1.2 queue serializes workspace runs and synthetic adapter completes without provider CLI', async () => {
  const app = createApp({ port: 0, devAdapters: true, conversationDbPath: tempConversationDbPath() });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const first = await request(port, 'POST', '/api/runs', { tool: 'synthetic-slow', workspaceId, prompt: 'first' }, token);
    const second = await request(port, 'POST', '/api/runs', { tool: 'synthetic-jsonl', workspaceId, prompt: 'second' }, token);
    assert.equal(first.body.status, 'running');
    assert.equal(second.body.status, 'queued');
    const queue = await request(port, 'GET', '/api/queue', null, token);
    assert.equal(queue.body.queue.length, 1);
    await new Promise((resolve) => setTimeout(resolve, 1100));
    const events = await request(port, 'GET', `/api/runs/${second.body.id}/events?afterSeq=0`, null, token);
    assert.equal(events.body.events.some((event) => event.type === 'run.dequeued'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('V1.2 command templates invoke adapter runs and reject raw command fields', async () => {
  const app = createApp({ port: 0, devAdapters: true, conversationDbPath: tempConversationDbPath() });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    await request(port, 'POST', '/api/workspaces', {
      workspacePath: process.cwd(),
      name: 'Default'
    }, token);
    const workspaceId = (await request(port, 'GET', '/api/workspaces', null, token)).body.workspaces[0].id;
    const templates = await request(port, 'GET', '/api/command-templates', null, token);
    assert.equal(templates.body.templates.some((template) => template.id === 'test'), true);
    const rejected = await request(port, 'POST', '/api/command-templates', { id: 'bad', label: 'bad', prompt: 'bad', command: 'rm -rf' }, token);
    assert.equal(rejected.status, 400);
    const invoked = await request(port, 'POST', '/api/command-templates/test/invoke', { workspaceId, tool: 'synthetic-jsonl' }, token);
    assert.equal(invoked.status, 201);
    assert.equal(invoked.body.run.tool, 'synthetic-jsonl');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('workspace API renames and logically deletes workspaces', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const appDbPath = tempConversationDbPath('app-db-workspace-api-');
  const app = createApp({ port: 0, appDbPath, devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-api-project-'));
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/workspaces', { workspacePath, name: 'Before' }, token);
    const renamed = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'After' }, token);
    const deleted = await request(port, 'DELETE', `/api/workspaces/${created.body.id}`, {}, token);
    const listed = await request(port, 'GET', '/api/workspaces', null, token);
    const recreated = await request(port, 'POST', '/api/workspaces', { workspacePath, name: 'Fresh' }, token);

    assert.equal(renamed.status, 200);
    assert.equal(renamed.body.name, 'After');
    assert.equal(renamed.body.path, path.resolve(workspacePath));
    assert.equal(deleted.status, 200);
    assert.deepEqual(listed.body.workspaces.map((workspace) => workspace.id), []);
    assert.notEqual(recreated.body.id, created.body.id);
    assert.equal(recreated.body.name, 'Fresh');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('workspace API rejects deleted workspace rename and path mutation', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-workspace-api-guard-'), devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/workspaces', { workspacePath: fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-api-guard-')), name: 'Before' }, token);
    const pathUpdate = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'After', workspacePath: 'D:/other' }, token);
    await request(port, 'DELETE', `/api/workspaces/${created.body.id}`, {}, token);
    const renameDeleted = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'Hidden' }, token);

    assert.equal(pathUpdate.status, 400);
    assert.equal(renameDeleted.status, 404);
    assert.equal(renameDeleted.body.error.code, 'WORKSPACE_NOT_FOUND');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('filesystem children permits authorized workspace paths', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-fs-authorized-'));
  fs.mkdirSync(path.join(workspacePath, 'src'));
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-workspace-fs-'), devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/workspaces', { workspacePath, name: 'Browse Me' }, token);
    const listed = await request(port, 'GET', `/api/fs/children?path=${encodeURIComponent(created.body.path)}`, null, token);

    assert.equal(created.status, 201);
    assert.equal(listed.status, 200);
    assert.equal(listed.body.path, path.resolve(workspacePath));
    assert.equal(listed.body.directories.some((entry) => entry.name === 'src'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('filesystem children permits paired workspace picker browsing before creation', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const rootPath = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-picker-root-'));
  fs.mkdirSync(path.join(rootPath, 'candidate'));
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-workspace-picker-fs-'), devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const listed = await request(port, 'GET', `/api/fs/children?path=${encodeURIComponent(rootPath)}`, null, paired.body.token);

    assert.equal(listed.status, 200);
    assert.equal(listed.body.path, path.resolve(rootPath));
    assert.equal(listed.body.directories.some((entry) => entry.name === 'candidate'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('filesystem children still requires a paired device token', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const rootPath = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-picker-auth-'));
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-workspace-picker-auth-'), devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  try {
    const listed = await request(app.server.address().port, 'GET', `/api/fs/children?path=${encodeURIComponent(rootPath)}`);

    assert.equal(listed.status, 401);
    assert.equal(listed.body.error.code, 'AUTH_REQUIRED');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('workspace delete requires confirmation for active conversations and is idempotent after they end', async () => {
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-workspace-active-'), devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test', deviceId: 'device_1' });
    const token = paired.body.token;
    const device = app.auth.authenticate(`Bearer ${token}`);
    const workspace = app.workspaces.add({ workspacePath: process.cwd(), name: 'Active' }, device);
    const fakeHandle = { cancelled: 0, async cancel() { this.cancelled += 1; } };
    const conversation = {
      id: 'conv_active',
      workspaceId: workspace.id,
      workspacePath: workspace.path,
      adapter: 'codex',
      permissionMode: 'default',
      deviceId: device.id,
      status: 'running',
      cliSessionId: 'session_1',
      sessionBinding: 'confirmed',
      userMessageCount: 1,
      blockingItem: null,
      idleExpiresAt: null,
      createdAt: '2026-05-11T00:00:00.000Z',
      updatedAt: '2026-05-11T00:00:00.000Z',
      capabilities: {},
      handle: fakeHandle
    };
    app.conversations.conversations.set(conversation.id, conversation);

    const rejected = await request(port, 'DELETE', `/api/workspaces/${workspace.id}`, {}, token);
    conversation.status = 'idle';
    const confirmed = await request(port, 'DELETE', `/api/workspaces/${workspace.id}`, { closeActive: true }, token);

    assert.equal(rejected.status, 409);
    assert.equal(rejected.body.error.code, 'WORKSPACE_HAS_ACTIVE_CLI');
    assert.equal(confirmed.status, 200);
    assert.equal(fakeHandle.cancelled, 0);
    assert.deepEqual(confirmed.body.workspaces, []);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('V1.2 git service parses status and diff output', () => {
  const { GitService } = require('../daemon/src/git-service');
  const service = new GitService({
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('status')) return { status: 0, stdout: ' M README.md\n?? new.txt\n', stderr: '' };
      return { status: 0, stdout: '2\t1\tREADME.md\n-\t-\timage.png\n', stderr: '' };
    }
  });
  const workspace = { id: 'default', path: process.cwd() };
  assert.equal(service.status(workspace).files.length, 2);
  const diff = service.diff(workspace).summaries;
  assert.equal(diff[0].additions, 2);
  assert.equal(diff[1].binary, true);
});
test('V1.3 health and version expose release readiness without secrets', async () => {
  const app = createApp({ port: 0, mode: 'dev', devAdapters: true, conversationDbPath: tempConversationDbPath() });
  for (const adapter of app.adapterRegistry.adapters.values()) {
    adapter.detectCapabilities = () => {
      throw new Error('health must not inspect adapter capabilities');
    };
  }
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const health = await request(port, 'GET', '/api/health');
    assert.equal(health.status, 200);
    assert.equal(health.body.daemonVersion, '1.3.0');
    assert.equal(health.body.security.ptyEnabled, false);
    assert.equal(Object.prototype.hasOwnProperty.call(health.body, 'adapters'), false);
    assert.equal(JSON.stringify(health.body).includes('Bearer'), false);
    const version = await request(port, 'GET', '/api/version');
    assert.equal(version.body.schemaVersion, 5);
    assert.equal(version.body.mode, 'dev');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('adapter capability loading shares concurrent probes', async () => {
  let firstCalls = 0;
  let secondCalls = 0;
  let releaseProbe;
  const probeReleased = new Promise((resolve) => {
    releaseProbe = resolve;
  });
  const registry = new AdapterRegistry([
    {
      name: 'first',
      async detectCapabilities() {
        firstCalls++;
        await probeReleased;
        return { adapter: 'first', available: true, status: 'available' };
      },
    },
    {
      name: 'second',
      async detectCapabilities() {
        secondCalls++;
        await probeReleased;
        return { adapter: 'second', available: true, status: 'available' };
      },
    },
  ]);

  const firstLoad = registry.listCapabilities();
  const secondLoad = registry.listCapabilities();
  assert.equal(firstLoad, secondLoad);
  assert.equal(firstCalls, 1);
  assert.equal(secondCalls, 1);

  releaseProbe();
  const [firstResult, secondResult] = await Promise.all([firstLoad, secondLoad]);
  assert.deepEqual(firstResult, secondResult);
  assert.equal(firstResult.length, 2);

  await registry.listCapabilities();
  assert.equal(firstCalls, 2);
  assert.equal(secondCalls, 2);
});

test('attachment capability fixture hashes to the documented capabilityVersion', () => {
  const {
    canonicalizeForHash,
    sha256Hex,
    sha256PrefixHex
  } = require('../daemon/src/canonical-json');
  const { capabilityVersionForNormalizedInput } = require('../daemon/src/attachment-hashes');
  const fixture = {
    adapterId: 'codex',
    attachments: {
      image: 'native',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    },
    cliPath: 'codex',
    cliVersion: '0.21.0',
    models: [
      {
        id: 'gpt-5.3-codex',
        inputModalities: ['image', 'text']
      }
    ],
    selectedModelId: 'gpt-5.3-codex'
  };
  const canonical = canonicalizeForHash(fixture);
  assert.equal(
    canonical,
    '{"adapterId":"codex","attachments":{"image":"native","pdf":"unsupported","textDocument":"text_extract"},"cliPath":"codex","cliVersion":"0.21.0","models":[{"id":"gpt-5.3-codex","inputModalities":["image","text"]}],"selectedModelId":"gpt-5.3-codex"}'
  );
  const fullHash = sha256Hex(canonical);
  assert.equal(
    fullHash,
    '4bcf6aa44f7e2e074229f9cd64880e8dc42fa727917b9ef732209a3f0f776973'
  );
  assert.equal(sha256PrefixHex(canonical, 12), '4bcf6aa44f7e2e074229f9cd');
  assert.equal(
    capabilityVersionForNormalizedInput(fixture),
    '4bcf6aa44f7e2e074229f9cd'
  );
});

test('attachment payload fixture hashes to the documented payloadHash', () => {
  const { canonicalizeForHash, sha256Hex } = require('../daemon/src/canonical-json');
  const { payloadHashForNormalizedInput } = require('../daemon/src/attachment-hashes');
  const fixture = {
    attachments: [
      {
        contentSha256Prefix: '0123456789abcdeffedcba9876543210',
        index: 0,
        kind: 'image',
        mimeType: 'image/png',
        name: 'screenshot.png',
        sizeBytes: 120034
      }
    ],
    text: 'Please inspect this screenshot.'
  };
  const canonical = canonicalizeForHash(fixture);
  assert.equal(
    canonical,
    '{"attachments":[{"contentSha256Prefix":"0123456789abcdeffedcba9876543210","index":0,"kind":"image","mimeType":"image/png","name":"screenshot.png","sizeBytes":120034}],"text":"Please inspect this screenshot."}'
  );
  assert.equal(
    sha256Hex(canonical),
    '760cab258596d09e0ca1f9b9a8821a03ad4da63461e1ead383a790123f153f26'
  );
  assert.equal(
    payloadHashForNormalizedInput(fixture),
    '760cab258596d09e0ca1f9b9a8821a03ad4da63461e1ead383a790123f153f26'
  );
});

test('attachment hash inputs normalize strings to NFC before canonicalization', () => {
  const { canonicalizeForHash, sha256Hex } = require('../daemon/src/canonical-json');
  const composed = canonicalizeForHash({ text: 'café' });
  const decomposed = canonicalizeForHash({ text: 'cafe\u0301' });

  assert.equal(composed, decomposed);
  assert.equal(sha256Hex(composed), sha256Hex(decomposed));
});

test('attachment hash inputs normalize object keys to NFC before canonicalization', () => {
  const { canonicalizeForHash, sha256Hex } = require('../daemon/src/canonical-json');
  const composed = canonicalizeForHash({ café: 'value' });
  const decomposed = canonicalizeForHash({ 'cafe\u0301': 'value' });

  assert.equal(composed, decomposed);
  assert.equal(composed, '{"café":"value"}');
  assert.equal(sha256Hex(composed), sha256Hex(decomposed));
});

test('attachment hash inputs reject unsupported numbers and values', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');
  const unsupported = [
    1.5,
    Number.MAX_SAFE_INTEGER + 1,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    undefined,
    { value: undefined },
    [undefined],
    new Date('2026-05-19T00:00:00.000Z'),
    /hash/,
    Buffer.from('hash'),
    new Map([['key', 'value']])
  ];

  for (const value of unsupported) {
    assert.throws(() => canonicalizeForHash(value), TypeError);
  }
});

test('attachment hash inputs reject duplicate object keys after NFC normalization', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');

  assert.throws(
    () => canonicalizeForHash({ café: 'composed', 'cafe\u0301': 'decomposed' }),
    TypeError
  );
});

test('attachment hash inputs reject sparse arrays', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');

  assert.throws(() => canonicalizeForHash(Array(1)), TypeError);
  assert.throws(() => canonicalizeForHash([, 'x']), TypeError);
});

test('attachment hash inputs reject arrays with JavaScript-only own properties', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');
  const symbolKeyed = ['x'];
  symbolKeyed[Symbol('hidden')] = 'secret';
  const nonEnumerableIndex = ['x'];
  Object.defineProperty(nonEnumerableIndex, '0', { value: 'x', enumerable: false });
  const accessorIndex = ['x'];
  Object.defineProperty(accessorIndex, '0', {
    enumerable: true,
    get() {
      return 'computed';
    }
  });
  const extraStringKey = ['x'];
  extraStringKey.extra = 'y';
  const nonCanonicalIndexKey = ['x'];
  nonCanonicalIndexKey['01'] = 'y';

  assert.throws(() => canonicalizeForHash(symbolKeyed), TypeError);
  assert.throws(() => canonicalizeForHash(nonEnumerableIndex), TypeError);
  assert.throws(() => canonicalizeForHash(accessorIndex), TypeError);
  assert.throws(() => canonicalizeForHash(extraStringKey), TypeError);
  assert.throws(() => canonicalizeForHash(nonCanonicalIndexKey), TypeError);
});

test('attachment hash inputs reject sparse arrays even with prototype pollution', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');
  Array.prototype[0] = 'polluted';
  try {
    assert.throws(() => canonicalizeForHash(Array(1)), TypeError);
  } finally {
    delete Array.prototype[0];
  }
});

test('attachment hash arrays ignore inherited toJSON serialization hooks', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');
  Array.prototype.toJSON = function toJSON() {
    return { polluted: true };
  };
  try {
    assert.equal(canonicalizeForHash(['x']), '["x"]');
  } finally {
    delete Array.prototype.toJSON;
  }
});

test('attachment hash inputs reject non-JSON object property shapes', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');
  const symbolKeyed = { text: 'value' };
  symbolKeyed[Symbol('hidden')] = 'secret';
  const nonEnumerable = { text: 'value' };
  Object.defineProperty(nonEnumerable, 'hidden', { value: 'secret', enumerable: false });
  const accessor = {};
  Object.defineProperty(accessor, 'text', {
    enumerable: true,
    get() {
      return 'computed';
    }
  });

  assert.throws(() => canonicalizeForHash(symbolKeyed), TypeError);
  assert.throws(() => canonicalizeForHash(nonEnumerable), TypeError);
  assert.throws(() => canonicalizeForHash(accessor), TypeError);
});

test('attachment hash inputs accept null-prototype plain objects', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');
  const input = Object.create(null);
  input.text = 'value';

  assert.equal(canonicalizeForHash(input), '{"text":"value"}');
});

test('attachment hash inputs preserve own enumerable __proto__ data keys', () => {
  const { canonicalizeForHash } = require('../daemon/src/canonical-json');
  const input = {};
  Object.defineProperty(input, '__proto__', { value: 1, enumerable: true });

  assert.equal(canonicalizeForHash(input), '{"__proto__":1}');
});

test('adapter capability listing merges model capability metadata', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      displayName: 'Codex',
      async detectCapabilities() {
        return { adapter: 'codex', available: true, status: 'available', selectedModel: 'status-model' };
      },
      getModelCapability() {
        return {
          models: [{ id: 'gpt-5', label: 'GPT-5', source: MODEL_SOURCES.CODEX_CONFIG, selected: true }],
          selectedModel: 'gpt-5',
          canSelectModel: true
        };
      },
      getCapabilities() {
        return { resume: true };
      }
    },
    {
      name: 'claude',
      async detectCapabilities() {
        return { adapter: 'claude', available: true, status: 'available', capabilities: { resume: true } };
      }
    }
  ]);

  const listed = await registry.listCapabilities();
  const codex = listed.find((item) => item.adapter === 'codex');
  const claude = listed.find((item) => item.adapter === 'claude');

  assert.equal(codex.displayName, 'Codex');
  assert.deepEqual(codex.models.map((model) => model.id), ['gpt-5']);
  assert.equal(codex.selectedModel, 'gpt-5');
  assert.equal(codex.canSelectModel, true);
  assert.deepEqual(codex.capabilities, {
    resume: true,
    attachments: {
      image: 'unsupported',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    }
  });
  assert.deepEqual(claude.models, []);
  assert.equal(claude.selectedModel, null);
  assert.equal(claude.canSelectModel, false);
});

test('adapter capability listing exposes attachment capabilities and stable capabilityVersion', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      displayName: 'Codex',
      async detectCapabilities() {
        return {
          adapter: 'codex',
          available: true,
          status: 'available',
          cliVersion: '0.21.0',
          cliPath: 'codex'
        };
      },
      getModelCapability() {
        return {
          canSelectModel: true,
          selectedModel: 'gpt-5.3-codex',
          models: [
            {
              id: 'gpt-5.3-codex',
              label: 'gpt-5.3-codex',
              inputModalities: ['text', 'image']
            }
          ]
        };
      },
      getCapabilities() {
        return {
          resume: true,
          attachments: {
            image: 'native',
            textDocument: 'text_extract',
            pdf: 'unsupported'
          }
        };
      }
    }
  ]);

  const [codex] = await registry.listCapabilities();

  assert.equal(codex.capabilityVersion, '4bcf6aa44f7e2e074229f9cd');
  assert.deepEqual(codex.capabilities.attachments, {
    image: 'native',
    pdf: 'unsupported',
    textDocument: 'text_extract'
  });
  assert.deepEqual(codex.models[0].inputModalities, ['image', 'text']);
  assert.deepEqual(codex.models[0].attachments, {
    image: 'native',
    pdf: 'unsupported',
    textDocument: 'text_extract'
  });
});

test('adapter capability listing lets models without modality metadata inherit image support', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      async detectCapabilities() {
        return {
          adapter: 'codex',
          available: true,
          status: 'available',
          cliVersion: '0.21.0',
          cliPath: 'codex'
        };
      },
      getModelCapability() {
        return {
          canSelectModel: true,
          selectedModel: 'gpt-5.5',
          models: [
            {
              id: 'gpt-5.5',
              label: 'GPT-5.5',
              source: MODEL_SOURCES.CODEX_CONFIG
            },
            {
              id: 'text-only-model',
              inputModalities: ['text']
            }
          ]
        };
      },
      getCapabilities() {
        return {
          attachments: {
            image: 'native',
            textDocument: 'text_extract',
            pdf: 'unsupported'
          }
        };
      }
    }
  ]);

  const [codex] = await registry.listCapabilities();
  const imageModel = codex.models.find((model) => model.id === 'gpt-5.5');
  const textOnlyModel = codex.models.find((model) => model.id === 'text-only-model');

  assert.equal(imageModel.attachments.image, 'native');
  assert.equal(Object.prototype.hasOwnProperty.call(imageModel, 'inputModalities'), false);
  assert.equal(textOnlyModel.attachments.image, 'unsupported');
  assert.deepEqual(textOnlyModel.inputModalities, ['text']);
});

test('adapter capability listing trims selected model before exposing and hashing', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      async detectCapabilities() {
        return {
          adapter: 'codex',
          available: true,
          status: 'available',
          cliVersion: '0.21.0',
          cliPath: 'codex'
        };
      },
      getModelCapability() {
        return {
          canSelectModel: true,
          selectedModel: ' gpt-5.3-codex ',
          models: [
            {
              id: ' gpt-5.3-codex ',
              inputModalities: ['text', 'image']
            }
          ]
        };
      },
      getCapabilities() {
        return {
          attachments: {
            image: 'native',
            textDocument: 'text_extract',
            pdf: 'unsupported'
          }
        };
      }
    }
  ]);

  const [codex] = await registry.listCapabilities();

  assert.equal(codex.selectedModel, 'gpt-5.3-codex');
  assert.equal(codex.models[0].id, 'gpt-5.3-codex');
  assert.equal(codex.capabilityVersion, '4bcf6aa44f7e2e074229f9cd');
});

test('adapter capability listing changes capabilityVersion for effective model attachment overrides', async () => {
  function registryForModel(model) {
    return new AdapterRegistry([
      {
        name: 'codex',
        async detectCapabilities() {
          return {
            adapter: 'codex',
            available: true,
            status: 'available',
            cliVersion: '0.21.0',
            cliPath: 'codex'
          };
        },
        getModelCapability() {
          return {
            canSelectModel: true,
            selectedModel: 'gpt-5.3-codex',
            models: [model]
          };
        },
        getCapabilities() {
          return {
            attachments: {
              image: 'native',
              textDocument: 'text_extract',
              pdf: 'unsupported'
            }
          };
        }
      }
    ]);
  }

  const [defaultProjection] = await registryForModel({
    id: 'gpt-5.3-codex',
    inputModalities: ['text', 'image']
  }).listCapabilities();
  const [overrideProjection] = await registryForModel({
    id: 'gpt-5.3-codex',
    inputModalities: ['text', 'image'],
    attachments: {
      textDocument: 'unsupported'
    }
  }).listCapabilities();

  assert.equal(defaultProjection.capabilityVersion, '4bcf6aa44f7e2e074229f9cd');
  assert.notEqual(defaultProjection.capabilityVersion, overrideProjection.capabilityVersion);
});

test('adapter capability listing merges partial model attachment overrides over adapter defaults', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      async detectCapabilities() {
        return { adapter: 'codex', available: true, status: 'available', cliVersion: '0.21.0', cliPath: 'codex' };
      },
      getModelCapability() {
        return {
          canSelectModel: true,
          selectedModel: 'gpt-5.3-codex',
          models: [
            {
              id: 'gpt-5.3-codex',
              inputModalities: ['image', 'text'],
              attachments: {
                textDocument: 'unsupported'
              }
            }
          ]
        };
      },
      getCapabilities() {
        return {
          attachments: {
            image: 'native',
            textDocument: 'text_extract',
            pdf: 'unsupported'
          }
        };
      }
    }
  ]);

  const [codex] = await registry.listCapabilities();

  assert.deepEqual(codex.models[0].attachments, {
    image: 'native',
    pdf: 'unsupported',
    textDocument: 'unsupported'
  });
});

test('adapter capability listing lets dynamic status capabilities win static conflicts', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      async detectCapabilities() {
        return {
          adapter: 'codex',
          available: true,
          status: 'available',
          capabilities: {
            resume: false,
            attachments: {
              image: 'native'
            }
          }
        };
      },
      getCapabilities() {
        return {
          resume: true,
          attachments: {
            image: 'unsupported',
            textDocument: 'text_extract',
            pdf: 'unsupported'
          }
        };
      }
    }
  ]);

  const [codex] = await registry.listCapabilities();

  assert.equal(codex.capabilities.resume, false);
  assert.deepEqual(codex.capabilities.attachments, {
    image: 'native',
    pdf: 'unsupported',
    textDocument: 'text_extract'
  });
});

test('adapter capability listing preserves status model metadata without model hook', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      async detectCapabilities() {
        return {
          adapter: 'codex',
          available: true,
          status: 'available',
          selectedModel: ' status-model ',
          models: [
            {
              id: ' status-model ',
              inputModalities: ['image', 'text']
            }
          ],
          capabilities: {
            attachments: {
              image: 'native',
              textDocument: 'text_extract',
              pdf: 'unsupported'
            }
          }
        };
      }
    }
  ]);

  const [codex] = await registry.listCapabilities();

  assert.equal(codex.selectedModel, 'status-model');
  assert.deepEqual(codex.models.map((model) => model.id), ['status-model']);
  assert.deepEqual(codex.models[0].inputModalities, ['image', 'text']);
});

test('conversation adapters expose explicit attachment capability contracts', () => {
  const codex = new CodexConversationAdapter({ cliResolverOptions: { platform: 'linux' } });
  const claude = new ClaudeConversationAdapter({ cliResolverOptions: { platform: 'linux' } });

  assert.deepEqual(codex.getCapabilities().attachments, {
    image: 'unsupported',
    pdf: 'unsupported',
    textDocument: 'text_extract'
  });
  assert.deepEqual(claude.getCapabilities().attachments, {
    image: 'native',
    pdf: 'unsupported',
    textDocument: 'text_extract'
  });
});

test('production Claude adapter listing exposes native image attachment support and dynamic flags', async () => {
  const claude = new ClaudeAdapter({
    command: 'claude',
    cliResolverOptions: { platform: 'linux' },
    spawnSyncFn: (_command, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '2.1.112\n', stderr: '' };
      if (args.includes('--help')) {
        return {
          status: 0,
          stdout: '--print --output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --model --permission-mode [default,auto]\n',
          stderr: ''
        };
      }
      return { status: 0, stdout: '', stderr: '' };
    }
  });
  const registry = new AdapterRegistry([claude]);

  const [listed] = await registry.listCapabilities();

  assert.equal(listed.capabilities.supportsModelFlag, true);
  assert.equal(listed.capabilities.streamJson, true);
  assert.deepEqual(listed.capabilities.attachments, {
    image: 'native',
    pdf: 'unsupported',
    textDocument: 'text_extract'
  });
});

function fakeProductionCodexSpawnSync({ execHelp, resumeHelp, version = 'codex-cli 0.21.0\n' }) {
  return (_command, args) => {
    if (args.includes('--version')) return { status: 0, stdout: version, stderr: '' };
    if (args[0] === '--help') return { status: 0, stdout: 'Usage: codex exec\n', stderr: '' };
    if (args[0] === 'exec' && args[1] === 'resume' && args.includes('--help')) return { status: 0, stdout: resumeHelp, stderr: '' };
    if (args[0] === 'exec' && args.includes('--help')) return { status: 0, stdout: execHelp, stderr: '' };
    return { status: 0, stdout: '', stderr: '' };
  };
}

function expectedProductionCodexCapabilityVersion(image) {
  const { capabilityVersionForNormalizedInput } = require('../daemon/src/attachment-hashes');
  return capabilityVersionForNormalizedInput({
    adapterId: 'codex',
    attachments: {
      image,
      pdf: 'unsupported',
      textDocument: 'text_extract'
    },
    cliPath: 'codex',
    cliVersion: 'codex-cli 0.21.0',
    models: [],
    selectedModelId: null
  });
}

async function withDisabledModelDiscovery(fn) {
  const original = process.env.VIBE_DISABLE_MODEL_DISCOVERY;
  process.env.VIBE_DISABLE_MODEL_DISCOVERY = 'true';
  try {
    return await fn();
  } finally {
    if (original === undefined) delete process.env.VIBE_DISABLE_MODEL_DISCOVERY;
    else process.env.VIBE_DISABLE_MODEL_DISCOVERY = original;
  }
}

test('production Codex adapter listing exposes attachment support and preserves detection metadata', async () => {
  await withDisabledModelDiscovery(async () => {
    const spawnSyncFn = fakeProductionCodexSpawnSync({
      execHelp: 'Usage: codex exec\n--json\n--model <model>\n-i <path>\n',
      resumeHelp: 'Usage: codex exec resume\n--json\n-i, --image <path>\n'
    });
    const codex = createCodexAdapter({
      command: 'codex',
      explicitEnabled: true,
      cliResolverOptions: { platform: 'linux' },
      spawnSyncFn
    });
    const conversation = new CodexConversationAdapter({
      command: 'codex',
      cliResolverOptions: { platform: 'linux' },
      spawnSyncFn
    });
    const registry = new AdapterRegistry([codex]);

    const [listed] = await registry.listCapabilities();
    conversation.detectCapabilities();

    assert.equal(listed.available, true);
    assert.equal(listed.status, 'available');
    assert.equal(listed.version, 'codex-cli 0.21.0');
    assert.equal(listed.canSelectModel, true);
    assert.deepEqual(listed.capabilities.attachments, {
      image: 'native',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    });
    assert.deepEqual(listed.capabilities.attachments, conversation.getCapabilities().attachments);
    assert.equal(listed.capabilityVersion, expectedProductionCodexCapabilityVersion('native'));
  });
});

test('production Codex adapter listing keeps image unsupported when resume help lacks image flag', async () => {
  await withDisabledModelDiscovery(async () => {
    const spawnSyncFn = fakeProductionCodexSpawnSync({
      execHelp: 'Usage: codex exec\n--json\n--model <model>\n--image <path>\n',
      resumeHelp: 'Usage: codex exec resume\n--json\n'
    });
    const codex = createCodexAdapter({
      command: 'codex',
      explicitEnabled: true,
      cliResolverOptions: { platform: 'linux' },
      spawnSyncFn
    });
    const conversation = new CodexConversationAdapter({
      command: 'codex',
      cliResolverOptions: { platform: 'linux' },
      spawnSyncFn
    });
    const registry = new AdapterRegistry([codex]);

    const [listed] = await registry.listCapabilities();
    conversation.detectCapabilities();

    assert.deepEqual(listed.capabilities.attachments, {
      image: 'unsupported',
      pdf: 'unsupported',
      textDocument: 'text_extract'
    });
    assert.deepEqual(listed.capabilities.attachments, conversation.getCapabilities().attachments);
    assert.equal(listed.capabilityVersion, expectedProductionCodexCapabilityVersion('unsupported'));
  });
});

test('adapter capability listing preserves dynamic status capabilities with static adapter defaults', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      async detectCapabilities() {
        return {
          adapter: 'codex',
          available: true,
          status: 'available',
          cliVersion: '0.21.0',
          cliPath: 'codex',
          capabilities: {
            execJson: true,
            resumeJson: true,
            resumeWorkspaceOverride: true
          }
        };
      },
      getCapabilities() {
        return {
          resume: true,
          attachments: {
            image: 'unsupported',
            textDocument: 'text_extract',
            pdf: 'unsupported'
          }
        };
      }
    }
  ]);

  const [codex] = await registry.listCapabilities();

  assert.equal(codex.capabilities.execJson, true);
  assert.equal(codex.capabilities.resumeJson, true);
  assert.equal(codex.capabilities.resumeWorkspaceOverride, true);
  assert.equal(codex.capabilities.resume, true);
  assert.deepEqual(codex.capabilities.attachments, {
    image: 'unsupported',
    pdf: 'unsupported',
    textDocument: 'text_extract'
  });
});

test('adapter capability listing sorts multiple models by id before hashing', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'codex',
      async detectCapabilities() {
        return { adapter: 'codex', available: true, status: 'available', cliVersion: '0.21.0', cliPath: 'codex' };
      },
      getModelCapability() {
        return {
          canSelectModel: true,
          selectedModel: 'a-model',
          models: [
            { id: 'z-model', inputModalities: ['text'] },
            { id: 'a-model', inputModalities: ['image', 'text'] }
          ]
        };
      },
      getCapabilities() {
        return { attachments: { image: 'native', textDocument: 'text_extract', pdf: 'unsupported' } };
      }
    }
  ]);

  const first = await registry.listCapabilities();
  const second = await registry.listCapabilities();

  assert.equal(first[0].models[0].id, 'a-model');
  assert.equal(first[0].models[1].id, 'z-model');
  assert.equal(first[0].capabilityVersion, second[0].capabilityVersion);
});

test('adapter capability listing falls back when model capability hooks fail', async () => {
  const registry = new AdapterRegistry([
    {
      name: 'throws',
      async detectCapabilities() {
        return { adapter: 'throws', available: true, status: 'available' };
      },
      getModelCapability() {
        throw new Error('model discovery failed');
      }
    },
    {
      name: 'rejects',
      async detectCapabilities() {
        return { adapter: 'rejects', available: true, status: 'available' };
      },
      async getModelCapability() {
        throw new Error('async model discovery failed');
      }
    }
  ]);

  const listed = await registry.listCapabilities();

  for (const item of listed) {
    assert.deepEqual(item.models, []);
    assert.equal(item.selectedModel, null);
    assert.equal(item.canSelectModel, false);
  }
});

test('V1.3 diagnostic export is authenticated, redacted, and audited', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const app = createApp({ port: 0, mode: 'dev', devAdapters: true, conversationDbPath: tempConversationDbPath(), codexAppServerProbe: false });
  app.diagnosticBundle.outputDir = fs.mkdtempSync(path.join(os.tmpdir(), 'diagnostic-export-'));
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const unauthenticated = await request(port, 'POST', '/api/diagnostics/export', {});
    assert.equal(unauthenticated.status, 401);
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const exported = await request(port, 'POST', '/api/diagnostics/export', {}, paired.body.token);
    assert.equal(exported.status, 200);
    assert.equal(exported.body.redacted, true);
    assert.equal(exported.body.items.includes('redaction_report'), true);
    assert.equal(app.auditLog.list().some((record) => record.type === 'diagnostic.export'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('android update endpoints serve manifest, 304, HEAD, full APK, and range APK', async () => {
  const fixture = createAndroidUpdateFixture();
  const app = createApp({
    port: 0,
    devAdapters: false,
    appDbPath: tempConversationDbPath('app-db-update-api-'),
    androidUpdateArtifactDir: fixture.root
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const unauthenticated = await request(port, 'GET', '/api/app-updates/android/latest');
    assert.equal(unauthenticated.status, 401);

    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'test',
      deviceId: 'device-update'
    });
    const token = paired.body.token;

    const latest = await requestRaw(port, 'GET', '/api/app-updates/android/latest', null, token);
    assert.equal(latest.status, 200);
    assert.equal(latest.headers.etag, fixture.manifest.etag);
    assert.equal(JSON.parse(latest.body.toString('utf8')).schemaVersion, 1);

    const cached = await requestRaw(port, 'GET', '/api/app-updates/android/latest', null, token, {
      'if-none-match': fixture.manifest.etag
    });
    assert.equal(cached.status, 304);
    assert.equal(cached.body.length, 0);

    const cachedFromList = await requestRaw(port, 'GET', '/api/app-updates/android/latest', null, token, {
      'if-none-match': `"old", ${fixture.manifest.etag}`
    });
    assert.equal(cachedFromList.status, 304);
    assert.equal(cachedFromList.body.length, 0);

    const cachedFromWildcard = await requestRaw(port, 'GET', '/api/app-updates/android/latest', null, token, {
      'if-none-match': '*'
    });
    assert.equal(cachedFromWildcard.status, 304);
    assert.equal(cachedFromWildcard.body.length, 0);

    const head = await requestRaw(port, 'HEAD', `/api/app-updates/android/apk/${fixture.manifest.versionCode}`, null, token);
    assert.equal(head.status, 200);
    assert.equal(Number(head.headers['content-length']), fixture.apkBytes.length);
    assert.equal(head.headers['accept-ranges'], 'bytes');
    assert.equal(head.headers['content-type'], 'application/vnd.android.package-archive');
    assert.equal(head.body.length, 0);

    const full = await requestRaw(port, 'GET', `/api/app-updates/android/apk/${fixture.manifest.versionCode}`, null, token);
    assert.equal(full.status, 200);
    assert.equal(full.headers.etag, fixture.manifest.etag);
    assert.deepEqual(full.body, fixture.apkBytes);

    const range = await requestRaw(port, 'GET', `/api/app-updates/android/apk/${fixture.manifest.versionCode}`, null, token, {
      range: 'bytes=2-',
      'if-range': fixture.manifest.etag
    });
    assert.equal(range.status, 206);
    assert.equal(range.headers['content-range'], `bytes 2-${fixture.apkBytes.length - 1}/${fixture.apkBytes.length}`);
    assert.deepEqual(range.body, fixture.apkBytes.subarray(2));

    const staleIfRange = await requestRaw(port, 'GET', `/api/app-updates/android/apk/${fixture.manifest.versionCode}`, null, token, {
      range: 'bytes=2-',
      'if-range': '"stale"'
    });
    assert.equal(staleIfRange.status, 200);
    assert.deepEqual(staleIfRange.body, fixture.apkBytes);

    const invalidRange = await requestRaw(port, 'GET', `/api/app-updates/android/apk/${fixture.manifest.versionCode}`, null, token, {
      range: `bytes=${fixture.apkBytes.length}-`
    });
    assert.equal(invalidRange.status, 416);
    assert.equal(invalidRange.headers['content-range'], `bytes */${fixture.apkBytes.length}`);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('android update endpoints pass authenticated device into APK service', async () => {
  const { createServer } = require('../daemon/src/server');
  const device = { id: 'device-app-update' };
  let seenDevice = null;
  const server = createServer({
    auth: {
      authenticate() {
        return device;
      }
    },
    appUpdates: {
      sendLatest(req, res) {
        res.writeHead(500);
        res.end();
      },
      sendApk(req, res, versionCode, authenticatedDevice) {
        seenDevice = authenticatedDevice;
        res.writeHead(204, { 'x-version-code': versionCode });
        res.end();
      }
    },
    asrModelAsset: {},
    diagnostics: {},
    diagnosticBundle: {},
    adapterRegistry: {},
    runQueue: {},
    shortcuts: {},
    commandTemplates: {},
    gitService: {},
    workspaceInspector: {},
    workspaces: {},
    runs: {},
    conversations: {},
    eventStore: {},
    config: {},
    version: {}
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await requestRaw(server.address().port, 'GET', '/api/app-updates/android/apk/2', null, 'token');
    assert.equal(response.status, 204);
    assert.equal(response.headers['x-version-code'], '2');
    assert.equal(seenDevice, device);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('android update service reloads newly published artifacts without daemon restart', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-reload-'));
  const app = createApp({
    port: 0,
    devAdapters: false,
    appDbPath: tempConversationDbPath('app-db-update-reload-'),
    androidUpdateArtifactDir: root
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'test',
      deviceId: 'device-update-reload'
    });
    const token = paired.body.token;

    const unavailable = await requestRaw(port, 'GET', '/api/app-updates/android/latest', null, token);
    assert.equal(unavailable.status, 200);
    assert.equal(unavailable.headers.etag, undefined);
    assert.equal(unavailable.headers['cache-control'], 'no-store');
    assert.equal(JSON.parse(unavailable.body.toString('utf8')).available, false);

    const unavailableCached = await requestRaw(port, 'GET', '/api/app-updates/android/latest', null, token, {
      'if-none-match': '"android-update-none"'
    });
    assert.equal(unavailableCached.status, 200);
    assert.equal(JSON.parse(unavailableCached.body.toString('utf8')).available, false);

    const fixture = createAndroidUpdateFixture({ root, versionCode: 7, apkBytes: Buffer.from('fresh-apk') });
    const latest = await request(port, 'GET', '/api/app-updates/android/latest', null, token);
    assert.equal(latest.status, 200);
    assert.equal(latest.body.available, true);
    assert.equal(latest.body.versionCode, fixture.manifest.versionCode);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('android update service rejects digest mismatches and invalid APK URLs before publishing', () => {
  const fixture = createAndroidUpdateFixture({ apkBytes: Buffer.from('release-a') });
  try {
    fs.writeFileSync(path.join(fixture.root, fixture.manifest.fileName), Buffer.from('release-b'));
    const corrupted = createApp({
      port: 0,
      devAdapters: false,
      appDbPath: tempConversationDbPath('app-db-update-corrupt-'),
      androidUpdateArtifactDir: fixture.root
    });
    assert.equal(corrupted.appUpdates.available, false);
    corrupted.appSqliteStore.close();

    const validBytes = Buffer.from('release-a');
    fs.writeFileSync(path.join(fixture.root, fixture.manifest.fileName), validBytes);
    fs.writeFileSync(path.join(fixture.root, 'latest.json'), JSON.stringify({
      ...fixture.manifest,
      sha256: nodeCrypto.createHash('sha256').update(validBytes).digest('hex'),
      sizeBytes: validBytes.length,
      apkUrl: 'https://updates.example.test/app.apk'
    }), 'utf8');
    const externalUrl = createApp({
      port: 0,
      devAdapters: false,
      appDbPath: tempConversationDbPath('app-db-update-external-url-'),
      androidUpdateArtifactDir: fixture.root
    });
    assert.equal(externalUrl.appUpdates.available, false);
    externalUrl.appSqliteStore.close();
  } finally {
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('android update service rejects symlinked APK targets outside artifact directory', () => {
  const fixture = createAndroidUpdateFixture({ apkBytes: Buffer.from('safe-apk') });
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-outside-'));
  try {
    const target = path.join(outside, 'outside.apk');
    fs.writeFileSync(target, Buffer.from('safe-apk'));
    const link = path.join(fixture.root, 'linked.apk');
    try {
      fs.symlinkSync(target, link, 'file');
    } catch {
      return;
    }
    fs.writeFileSync(path.join(fixture.root, 'latest.json'), JSON.stringify({
      ...fixture.manifest,
      fileName: 'linked.apk'
    }), 'utf8');
    const app = createApp({
      port: 0,
      devAdapters: false,
      appDbPath: tempConversationDbPath('app-db-update-symlink-'),
      androidUpdateArtifactDir: fixture.root
    });
    assert.equal(app.appUpdates.available, false);
    app.appSqliteStore.close();
  } finally {
    fs.rmSync(fixture.root, { recursive: true, force: true });
    fs.rmSync(outside, { recursive: true, force: true });
  }
});

test('android update service registers stream error handlers for APK responses', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'daemon/src/app-update-service.js'), 'utf8');
  assert.match(source, /createReadStream/);
  assert.match(source, /\.on\('error'/);
});

test('android update service streams only from fd-bound validated APK identity', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'daemon/src/app-update-service.js'), 'utf8');
  const streamStart = source.indexOf('streamApk(res, fd');
  const streamBody = source.slice(streamStart, source.indexOf('\n  openVerifiedApk', streamStart));
  const loadStart = source.indexOf('  async load()');
  const loadBody = source.slice(loadStart, source.indexOf('\n  _markUnavailable', loadStart));
  const openStart = source.indexOf('  openVerifiedApk()');
  const openBody = source.slice(openStart, source.indexOf('\n  async _verifyDigest', openStart));

  assert.match(source, /async sendLatest\(req, res\)/);
  assert.match(source, /async sendApk\(req, res, requestedVersionCode, device\)/);
  assert.match(source, /await this\.load\(\)/);
  assert.match(source, /openVerifiedApk\(\)/);
  assert.match(source, /streamApk\(res, openedApk\.fd/);
  assert.match(source, /this\.apkIdentity = null/);
  assert.match(loadBody, /const identity = apkIdentityFor\(stats, realApkPath, manifest\.sha256\)/);
  assert.match(loadBody, /await this\._verifyDigest\(realApkPath, stats, manifest\.sha256\)/);
  assert.match(loadBody, /this\.apkIdentity = identity/);
  assert.match(source, /fs\.openSync\(this\.apkPath, 'r'\)/);
  assert.match(source, /fs\.fstatSync\(fd\)/);
  assert.match(openBody, /const identity = this\.apkIdentity/);
  assert.match(openBody, /apkIdentityMatches\(identity, stats, realApkPath, this\.manifest\.sha256\)/);
  assert.equal(openBody.includes('_verifyDigest'), false);
  assert.equal(openBody.includes('sha256ForFd'), false);
  assert.equal(openBody.includes('fs.readSync'), false);
  assert.equal(source.includes('_digestCache'), false);
  assert.notEqual(streamStart, -1);
  assert.match(streamBody, /createReadStream\([^)]*fd/);
  assert.match(streamBody, /autoClose: true/);
});

test('android update service hashes changed APK identities asynchronously', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'daemon/src/app-update-service.js'), 'utf8');
  const digestStart = source.indexOf('  async _verifyDigest');
  const digestBody = source.slice(digestStart, source.indexOf('\n}', digestStart));
  const helperStart = source.indexOf('function sha256ForFile');
  const helperBody = source.slice(helperStart, source.indexOf('\nfunction unavailableManifest', helperStart));

  assert.notEqual(digestStart, -1);
  assert.match(digestBody, /await sha256ForFile\(apkPath\)/);
  assert.equal(digestBody.includes('fs.readFileSync'), false);
  assert.notEqual(helperStart, -1);
  assert.match(helperBody, /fs\.createReadStream\(apkPath\)/);
  assert.match(helperBody, /\.on\('data'/);
  assert.match(helperBody, /\.on\('end'/);
  assert.match(helperBody, /\.on\('error'/);
});

test('android update service marks unavailable when digest stream fails', async () => {
  const { AppUpdateService } = require('../daemon/src/app-update-service');
  const fixture = createAndroidUpdateFixture();
  const service = new AppUpdateService({ artifactDir: fixture.root });
  service._verifyDigest = async () => {
    throw new Error('read failed');
  };

  try {
    await service.load();

    assert.equal(service.available, false);
    assert.equal(service.manifest.available, false);
  } finally {
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('android update APK endpoint rejects retained non-latest versions and path escape', async () => {
  const fixture = createAndroidUpdateFixture({ versionCode: 5 });
  fs.writeFileSync(path.join(fixture.root, 'lan_ai_cli_control-1.3.0+3.apk'), Buffer.from('old'));
  const app = createApp({
    port: 0,
    devAdapters: false,
    appDbPath: tempConversationDbPath('app-db-update-retained-'),
    androidUpdateArtifactDir: fixture.root
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'test',
      deviceId: 'device-retained'
    });
    const token = paired.body.token;

    const old = await requestRaw(port, 'GET', '/api/app-updates/android/apk/3', null, token);
    assert.equal(old.status, 404);

    const escapeRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-escape-'));
    fs.writeFileSync(path.join(escapeRoot, 'evil.apk'), Buffer.from('evil'));
    fs.writeFileSync(path.join(fixture.root, 'latest.json'), JSON.stringify({
      ...fixture.manifest,
      sizeBytes: 4,
      sha256: nodeCrypto.createHash('sha256').update(Buffer.from('evil')).digest('hex'),
      fileName: path.relative(fixture.root, path.join(escapeRoot, 'evil.apk'))
    }), 'utf8');
    const invalidApp = createApp({
      port: 0,
      devAdapters: false,
      appDbPath: tempConversationDbPath('app-db-update-invalid-'),
      androidUpdateArtifactDir: fixture.root
    });
    assert.equal(invalidApp.appUpdates.available, false);
    invalidApp.appSqliteStore.close();
    fs.rmSync(escapeRoot, { recursive: true, force: true });
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('prepare android update writes latest manifest and sha sidecar', async () => {
  const childProcess = require('node:child_process');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'android-update-helper-'));
  const apk = path.join(root, 'app-release.apk');
  const out = path.join(root, 'artifacts');
  fs.writeFileSync(apk, Buffer.from('release-apk'));

  const result = childProcess.spawnSync(process.execPath, [
    path.join(process.cwd(), 'scripts', 'prepare-android-update.js'),
    '--apk', apk,
    '--out', out,
    '--version-name', '1.4.0',
    '--version-code', '2',
    '--package', 'com.example.lan_ai_cli_control',
    '--release-notes', 'test release'
  ], { encoding: 'utf8' });

  try {
    assert.equal(result.status, 0, result.stderr);
    const manifest = JSON.parse(fs.readFileSync(path.join(out, 'latest.json'), 'utf8'));
    assert.equal(manifest.schemaVersion, 1);
    assert.equal(manifest.versionCode, 2);
    assert.equal(manifest.apkUrl, '/api/app-updates/android/apk/2');
    assert.match(manifest.fileName, /-[a-f0-9]{12}\.apk$/);
    assert.equal(fs.existsSync(path.join(out, manifest.fileName)), true);
    assert.equal(fs.existsSync(path.join(out, `${manifest.fileName}.sha256`)), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('prepare android update publishes artifacts by atomic final rename', () => {
  const helper = fs.readFileSync(
    path.join(__dirname, '..', 'scripts/prepare-android-update.js'),
    'utf8'
  );
  const copyIndex = helper.indexOf('fs.copyFileSync(apkPath');
  const apkRenameIndex = helper.indexOf('fs.renameSync(apkTemp, apkFinal)');
  const shaRenameIndex = helper.indexOf('fs.renameSync(shaTemp, shaFinal)');
  const manifestRenameIndex = helper.indexOf('fs.renameSync(manifestTemp, manifestFinal)');

  assert.equal(copyIndex, -1, 'APK copy must not write directly to the final published path');
  assert.notEqual(apkRenameIndex, -1);
  assert.notEqual(shaRenameIndex, -1);
  assert.notEqual(manifestRenameIndex, -1);
  assert.ok(apkRenameIndex < shaRenameIndex, 'APK must be published before sidecar');
  assert.ok(shaRenameIndex < manifestRenameIndex, 'latest.json must be published last');
});

test('android release build requires private signing and portable NDK lookup', () => {
  const buildGradle = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/android/app/build.gradle.kts'),
    'utf8'
  );

  assert.equal(buildGradle.includes('ndkPath'), false);
  assert.equal(buildGradle.includes('signingConfigs.getByName("debug")'), false);
  assert.match(buildGradle, /throw GradleException\([^)]*key\.properties/);
  assert.match(buildGradle, /signingConfigs\.getByName\("releasePrivate"\)/);
  assert.match(buildGradle, /enableV1Signing\s*=\s*true/);
  assert.equal(buildGradle.includes('TODO: Specify your own unique Application ID'), false);
});

test('android app permits LAN daemon cleartext traffic for native downloads', () => {
  const manifest = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/android/app/src/main/AndroidManifest.xml'),
    'utf8'
  );

  assert.match(manifest, /android:usesCleartextTraffic="true"/);
});

test('android installer native bridge abandons failed sessions after creation', () => {
  const activity = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt'),
    'utf8'
  );
  const createSessionIndex = activity.indexOf('installer.createSession(params)');
  const tryIndex = activity.indexOf('try {', createSessionIndex);
  const openSessionIndex = activity.indexOf('installer.openSession(sessionId)', createSessionIndex);
  const abandonIndex = activity.indexOf('installer.abandonSession(sessionId)', createSessionIndex);
  const commitIndex = activity.indexOf('activeSession.commit(pendingIntent.intentSender)', createSessionIndex);

  assert.notEqual(createSessionIndex, -1);
  assert.notEqual(tryIndex, -1);
  assert.notEqual(openSessionIndex, -1);
  assert.notEqual(abandonIndex, -1);
  assert.notEqual(commitIndex, -1);
  assert.ok(tryIndex < openSessionIndex, 'openSession must be inside the abandon-protected try block');
  assert.ok(openSessionIndex < abandonIndex, 'failed open/write/commit paths must abandon the session');
  assert.equal(
    activity.includes('sendInstallEvent("committed"'),
    false,
    'Dart records committed after persisting the PackageInstaller session id'
  );
});

test('android installer status receiver is private and session-scoped', () => {
  const activity = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt'),
    'utf8'
  );
  const manifest = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/android/app/src/main/AndroidManifest.xml'),
    'utf8'
  );
  const receiverIndex = activity.indexOf('private fun registerInstallReceiver');
  const receiverBody = activity.slice(receiverIndex, activity.indexOf('\n    private fun confirmationIntent', receiverIndex));

  assert.notEqual(receiverIndex, -1);
  assert.match(activity, /private val installStatusPermission/);
  assert.match(activity, /private val pendingInstallSessionIds/);
  assert.match(receiverBody, /installStatusPermission/);
  assert.equal(receiverBody.includes('registerReceiver(installReceiver, filter)'), false);
  assert.match(activity, /if \(!pendingInstallSessionIds\.contains\(sessionId\)\) return/);
  assert.match(activity, /pendingInstallSessionIds\.remove\(sessionId\)/);
  assert.match(manifest, /android:name="\$\{applicationId\}\.permission\.APP_UPDATE_INSTALL_STATUS"/);
  assert.match(manifest, /android:protectionLevel="signature"/);
}
);

test('android installer pending action is emitted only after confirmation UI opens', () => {
  const activity = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt'),
    'utf8'
  );
  const pendingIndex = activity.indexOf('if (status == PackageInstaller.STATUS_PENDING_USER_ACTION)');
  const pendingBody = activity.slice(pendingIndex, activity.indexOf('\n            val mapped = when', pendingIndex));
  const nullIndex = pendingBody.indexOf('if (confirmation == null)');
  const startIndex = pendingBody.indexOf('context.startActivity(confirmation)');
  const eventIndex = pendingBody.indexOf('sendInstallEvent("pendingUserAction"');

  assert.notEqual(pendingIndex, -1);
  assert.notEqual(nullIndex, -1);
  assert.notEqual(startIndex, -1);
  assert.notEqual(eventIndex, -1);
  assert.ok(startIndex < eventIndex, 'pending event must be emitted only after confirmation UI starts');
  assert.match(pendingBody, /catch \(error: Exception\)/);
  assert.match(pendingBody, /sendInstallEvent\(\s*"failed"/);
  assert.match(pendingBody, /pendingInstallSessionIds\.remove\(sessionId\)/);
});

test('android installer recovery reports recoverable sessions as pending', () => {
  const activity = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt'),
    'utf8'
  );
  const recoverIndex = activity.indexOf('private fun recoverSession');
  const recoverBody = activity.slice(recoverIndex, activity.indexOf('\n    private fun availableBytes', recoverIndex));
  const recoverableIndex = activity.indexOf('private fun isRecoverableInstallerSession');
  const recoverableBody = activity.slice(recoverableIndex, activity.indexOf('\n    private fun isSessionCommitted', recoverableIndex));
  const committedIndex = activity.indexOf('private fun isSessionCommitted');
  const committedBody = activity.slice(committedIndex, activity.indexOf('\n    private fun isSessionSealed', committedIndex));
  const sealedIndex = activity.indexOf('private fun isSessionSealed');
  const sealedBody = activity.slice(sealedIndex, activity.indexOf('\n    private fun availableBytes', sealedIndex));

  assert.notEqual(recoverIndex, -1);
  assert.match(recoverBody, /getSessionInfo\(sessionId\) \?: return null/);
  assert.match(recoverBody, /if \(!isRecoverableInstallerSession\(info\)\) return null/);
  assert.match(recoverBody, /return mapOf\(/);
  assert.match(recoverBody, /pendingInstallSessionIds\.add\(sessionId\)/);
  assert.match(recoverBody, /"status" to "pendingUserAction"/);
  assert.match(recoverBody, /"sessionId" to sessionId/);
  assert.match(recoverBody, /"appPackageName" to info\.appPackageName/);
  assert.equal(recoverBody.includes('info.isActive ||'), false);
  assert.notEqual(recoverableIndex, -1);
  assert.match(recoverableBody, /info\.isActive/);
  assert.match(recoverableBody, /Build\.VERSION\.SDK_INT < Build\.VERSION_CODES\.O/);
  assert.match(recoverableBody, /isSessionCommitted\(info\)/);
  assert.match(recoverableBody, /isSessionSealed\(info\)/);
  assert.match(recoverableBody, /return false/);
  assert.notEqual(committedIndex, -1);
  assert.match(committedBody, /Build\.VERSION\.SDK_INT >= Build\.VERSION_CODES\.Q/);
  assert.match(committedBody, /info\.isCommitted/);
  assert.notEqual(sealedIndex, -1);
  assert.match(sealedBody, /Build\.VERSION\.SDK_INT >= Build\.VERSION_CODES\.O/);
  assert.match(sealedBody, /info\.isSealed/);
});

test('android update downloader writes metadata from checked non-null manifest fields', () => {
  const downloader = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/services/app_update_download_manager.dart'),
    'utf8'
  );
  const writeIndex = downloader.indexOf('Future<void> _writeMetadata(');
  const writeBody = downloader.slice(writeIndex, downloader.indexOf('\n  bool _metadataMatches', writeIndex));

  assert.notEqual(writeIndex, -1);
  assert.equal(writeBody.includes('manifest.etag!'), false);
  assert.equal(writeBody.includes('manifest.versionCode!'), false);
  assert.match(writeBody, /final etag = manifest\.etag;/);
  assert.match(writeBody, /if \([^)]*etag == null/s);
});

test('android update install recovery is wired through ViewModel and app lifecycle', () => {
  const viewModel = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart'),
    'utf8'
  );
  const mainTabs = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/ui/main/main_page.dart'),
    'utf8'
  );
  const workflow = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/workflows/app_update_workflow.dart'),
    'utf8'
  );

  const installMatch = viewModel.match(/Future<void>\s+install\([^)]*\)\s+async/);
  assert.notEqual(installMatch, null);
  const installIndex = installMatch.index;
  const installBody = viewModel.slice(
    installIndex,
    viewModel.indexOf('\n  Future<void> recoverInstallSession', installIndex)
  );
  assert.match(installBody, /state\.status == AppUpdateStatus\.installing/);
  assert.match(installBody, /state\.status == AppUpdateStatus\.awaitingUserConfirmation/);
  assert.match(installBody, /return;/);
  assert.match(viewModel, /workflow\.startInstall\(/);
  assert.match(viewModel, /Future<void> recoverInstallSession\(\) async/);
  assert.match(viewModel, /Future<void>\s+handleAppLifecycleStateChanged\(\s*AppLifecycleState lifecycleState,\s*\)\s+async/);
  assert.match(viewModel, /recoverInstallSession\(\)/);
  assert.match(viewModel, /workflow\.recoverInstall\(/);
  assert.match(viewModel, /workflow\.clearAllInstallSessions\(\)/);
  assert.equal(viewModel.includes('workflow.readInstallSession'), false);
  assert.equal(viewModel.includes('workflow.recoverInstallSession'), false);
  assert.match(workflow, /Future<AppUpdateRecoveryResult> recoverInstall\(/);
  assert.match(workflow, /Future<void> clearAllInstallSessions\(\)/);
  const recoverWorkflowBody = workflow.slice(
    workflow.indexOf('Future<AppUpdateRecoveryResult> recoverInstall('),
    workflow.indexOf('\n  Future<bool> _downloadedFileExists', workflow.indexOf('Future<AppUpdateRecoveryResult> recoverInstall('))
  );
  assert.equal(recoverWorkflowBody.includes('clearAllInstallSessions'), false);
  assert.equal(recoverWorkflowBody.includes('_downloader.clearInstallSession'), false);
  assert.match(workflow, /await _downloader\.readInstallSession\(manifest\)/);
  assert.match(workflow, /await _installer\.recoverInstallSession\(session\.sessionId\)/);
  assert.match(workflow, /sessionId: session\.sessionId/);
  assert.match(mainTabs, /with WidgetsBindingObserver/);
  assert.match(mainTabs, /Platform\.isAndroid/);
  assert.match(mainTabs, /viewModel\.handleAppLifecycleStateChanged\(AppLifecycleState\.resumed\)/);
});

test('android update ViewModel depends on workflow boundary instead of services', () => {
  const viewModel = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart'),
    'utf8'
  );
  const appDependencies = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/app/app_dependencies.dart'),
    'utf8'
  );

  const importLines = viewModel.split('\n').filter((line) => line.trim().startsWith('import '));
  assert.equal(importLines.some((line) => line.includes('/services/') || line.includes('src/services/')), false);
  assert.match(viewModel, /workflows\/app_update_workflow\.dart/);
  assert.equal(viewModel.includes('AppUpdateDownloader'), false);
  assert.equal(viewModel.includes('PackageInstallerService'), false);
  assert.match(appDependencies, /AppUpdateWorkflow\(/);
});

test('android update downloader contains ready APK cache races before fetching', () => {
  const downloader = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/services/app_update_download_manager.dart'),
    'utf8'
  );
  const helperIndex = downloader.indexOf('Future<File?> _reuseReadyApk(');
  const helperBody = downloader.slice(helperIndex, downloader.indexOf('\n  Future<AppUpdateDownloadResult?> _downloadFromDaemon', helperIndex));
  const downloadIndex = downloader.indexOf('Future<AppUpdateDownloadResult> download(');
  const downloadBody = downloader.slice(downloadIndex, downloader.indexOf('\n  Future<void> reconcile', downloadIndex));

  assert.notEqual(helperIndex, -1);
  assert.match(helperBody, /on FileSystemException/);
  assert.match(helperBody, /return null/);
  assert.match(downloadBody, /final readyApk = await _reuseReadyApk/);
});

test('android update downloader serializes version-scoped mutations and hashes off the caller isolate', () => {
  const downloader = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/services/app_update_download_manager.dart'),
    'utf8'
  );
  const downloadKeyIndex = downloader.indexOf('String _downloadKey(');
  const downloadKeyBody = downloader.slice(
    downloadKeyIndex,
    downloader.indexOf('\n  String _joinPath', downloadKeyIndex)
  );

  assert.match(downloader, /final Map<String, _ActiveAppUpdateDownload> _downloadsByKey/);
  assert.match(downloader, /_downloadKey\(manifest, daemonBaseUri\)/);
  assert.notEqual(downloadKeyIndex, -1);
  assert.match(downloadKeyBody, /manifest\.versionCode/);
  assert.match(downloadKeyBody, /manifest\.versionName/);
  assert.match(downloadKeyBody, /manifest\.sha256/);
  assert.match(downloadKeyBody, /manifest\.sizeBytes/);
  assert.match(downloadKeyBody, /manifest\.etag/);
  assert.match(downloadKeyBody, /manifest\.apkUrl/);
  assert.match(downloader, /_awaitActiveDownloadsForVersion\(versionCode/);
  assert.match(downloader, /whenComplete\(\(\)\s*=>\s*_downloadsByKey\.remove\(downloadKey\)\)/s);
  assert.match(downloader, /Isolate\.run/);
});

test('android update downloader cancels response stream when file write fails', () => {
  const downloader = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/services/app_update_download_manager.dart'),
    'utf8'
  );
  const writeStreamIndex = downloader.indexOf('Future<int> _writeStream(');
  const writeStreamBody = downloader.slice(writeStreamIndex, downloader.indexOf('\n  Future<int> _resumeLength', writeStreamIndex));

  assert.notEqual(writeStreamIndex, -1);
  assert.match(writeStreamBody, /final iterator = StreamIterator<List<int>>\(stream\)/);
  assert.match(writeStreamBody, /await iterator\.cancel\(\)/);
  assert.equal(writeStreamBody.includes('await for (final chunk in stream)'), false);
});

test('android update downloader treats filesystem write failures as retryable interruptions', () => {
  const downloader = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/services/app_update_download_manager.dart'),
    'utf8'
  );
  const catchIndex = downloader.indexOf('} on FileSystemException catch');
  const catchBody = downloader.slice(catchIndex, downloader.indexOf('\n    } on FormatException', catchIndex));

  assert.notEqual(catchIndex, -1);
  assert.match(catchBody, /AppUpdateDownloadState\.paused/);
  assert.match(catchBody, /interrupted/);
});

test('android update downloader tolerates cache delete races', () => {
  const downloader = fs.readFileSync(
    path.join(__dirname, '..', 'mobile/lib/src/services/app_update_download_manager.dart'),
    'utf8'
  );
  const deleteIndex = downloader.indexOf('Future<void> _deleteIfExists');
  const deleteBody = downloader.slice(deleteIndex, downloader.indexOf('\n  String? _validateDownloadableManifest', deleteIndex));
  const reconcileIndex = downloader.indexOf('Future<void> reconcile(');
  const discardIndex = downloader.indexOf('Future<void> discard', reconcileIndex);
  const reconcileBody = downloader.slice(reconcileIndex, discardIndex);

  assert.notEqual(deleteIndex, -1);
  assert.match(deleteBody, /try \{/);
  assert.match(deleteBody, /on FileSystemException/);
  assert.notEqual(reconcileIndex, -1);
  assert.notEqual(discardIndex, -1);
  assert.equal(reconcileBody.includes('await paths.apk.exists()'), false);
  assert.match(reconcileBody, /_safeExists\(paths\.apk\)/);
  assert.match(reconcileBody, /on FileSystemException/);
});

test('ASR model API returns metadata and supports full and ranged downloads', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const crypto = require('node:crypto');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asr-model-api-'));
  const filePath = path.join(dir, 'fixture-model.zip');
  const bytes = Buffer.from('0123456789abcdef');
  fs.writeFileSync(filePath, bytes);
  const app = createApp({
    port: 0,
    appDbPath: tempConversationDbPath('app-db-asr-model-'),
    asrModelAsset: new AsrModelAsset({ filePath, version: 'fixture-model' }),
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const unauthenticated = await request(port, 'GET', '/api/asr-model');
    assert.equal(unauthenticated.status, 401);
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;

    const metadata = await request(port, 'GET', '/api/asr-model', null, token);
    assert.equal(metadata.status, 200);
    assert.equal(metadata.body.version, 'fixture-model');
    assert.equal(metadata.body.fileName, 'fixture-model.zip');
    assert.equal(metadata.body.sizeBytes, bytes.length);
    assert.equal(metadata.body.sha256, crypto.createHash('sha256').update(bytes).digest('hex'));
    assert.equal(metadata.body.downloadPath, '/api/asr-model/download');

    const full = await requestRaw(port, 'GET', '/api/asr-model/download', null, token);
    assert.equal(full.status, 200);
    assert.equal(full.headers['accept-ranges'], 'bytes');
    assert.equal(full.body.toString('utf8'), bytes.toString('utf8'));

    const partial = await requestRaw(port, 'GET', '/api/asr-model/download', null, token, { range: 'bytes=4-9' });
    assert.equal(partial.status, 206);
    assert.equal(partial.headers['content-range'], `bytes 4-9/${bytes.length}`);
    assert.equal(partial.body.toString('utf8'), '456789');

    const invalid = await requestRaw(port, 'GET', '/api/asr-model/download', null, token, { range: `bytes=${bytes.length}-` });
    assert.equal(invalid.status, 416);
    assert.equal(invalid.headers['content-range'], `bytes */${bytes.length}`);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('ASR model API reports missing asset as structured traceable error', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const missingPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'asr-model-missing-')), 'missing.zip');
  const app = createApp({
    port: 0,
    appDbPath: tempConversationDbPath('app-db-asr-model-missing-'),
    asrModelAsset: new AsrModelAsset({ filePath: missingPath, version: 'missing' }),
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const response = await request(port, 'GET', '/api/asr-model', null, paired.body.token);
    assert.equal(response.status, 503);
    assert.equal(response.body.error.code, 'ASR_MODEL_UNAVAILABLE');
    assert.match(response.body.error.traceId, /^trc_/);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('exceptions are persisted with trace ids and exported in diagnostics', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const appDbPath = tempConversationDbPath('app-db-exceptions-');
  const app = createApp({ port: 0, mode: 'dev', devAdapters: true, appDbPath, codexAppServerProbe: false });
  app.diagnosticBundle.outputDir = fs.mkdtempSync(path.join(os.tmpdir(), 'diagnostic-exceptions-'));
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const recorded = await request(port, 'POST', '/api/exceptions', {
      source: 'mobile',
      message: 'SocketException: Write failed',
      path: '/api/notifications/ws',
      conversationId: 'conv_1',
      metadata: { operation: 'watchConversationEvents' }
    }, token);
    assert.equal(recorded.status, 201);
    assert.match(recorded.body.traceId, /^trc_/);
    assert.equal(app.appSqliteStore.listExceptions()[0].traceId, recorded.body.traceId);
    const exported = await request(port, 'POST', '/api/diagnostics/export', {}, token);
    const bundle = JSON.parse(fs.readFileSync(exported.body.path, 'utf8'));
    assert.equal(bundle.recent_errors[0].traceId, recorded.body.traceId);

    const failed = await request(port, 'GET', '/api/not-found-for-trace', null, token);
    assert.equal(failed.status, 404);
    assert.match(failed.body.error.traceId, /^trc_/);
    assert.equal(app.appSqliteStore.listExceptions().some((item) => item.traceId === failed.body.error.traceId), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('V1.3 smoke endpoint is dev-only and release mode hides it', async () => {
  const dev = createApp({ port: 0, mode: 'dev', devAdapters: true, conversationDbPath: tempConversationDbPath() });
  await new Promise((resolve) => dev.server.listen(0, '127.0.0.1', resolve));
  try {
    const smoke = await request(dev.server.address().port, 'POST', '/api/e2e/smoke', {});
    assert.equal(smoke.status, 200);
    assert.equal(smoke.body.ok, true);
  } finally {
    await new Promise((resolve) => dev.server.close(resolve));
  }

  const release = createApp({ port: 0, mode: 'release', devAdapters: false, conversationDbPath: tempConversationDbPath() });
  await new Promise((resolve) => release.server.listen(0, '127.0.0.1', resolve));
  try {
    const smoke = await request(release.server.address().port, 'POST', '/api/e2e/smoke', {});
    assert.equal(smoke.status, 403);
    assert.equal(smoke.body.error.code, 'DEV_API_DISABLED');
  } finally {
    await new Promise((resolve) => release.server.close(resolve));
  }
});

test('attachment filename validation rejects unsafe display names', () => {
  const { sanitizeAttachmentName } = require('../daemon/src/attachment-validation');

  assert.equal(sanitizeAttachmentName(' screenshot.png '), 'screenshot.png');
  assert.throws(() => sanitizeAttachmentName('../secret.png'), /unsupported media type/);
  assert.throws(() => sanitizeAttachmentName('safe.txt:evil'), /unsupported media type/);
  assert.throws(() => sanitizeAttachmentName('bad<name>.txt'), /unsupported media type/);
  assert.throws(() => sanitizeAttachmentName('con.txt'), /unsupported media type/);
  assert.throws(() => sanitizeAttachmentName('CONIN$.txt'), /unsupported media type/);
  assert.throws(() => sanitizeAttachmentName('CONOUT$.txt'), /unsupported media type/);
  assert.throws(() => sanitizeAttachmentName('report.'), /unsupported media type/);
  assert.throws(() => sanitizeAttachmentName('photo\u202Egpj.exe'), /unsupported media type/);
});

test('attachment validation rejects zero-byte text files', async () => {
  const { validateTextAttachmentBytes } = require('../daemon/src/attachment-validation');

  await assert.rejects(
    () => validateTextAttachmentBytes(Buffer.alloc(0), { name: 'empty.txt', mimeType: 'text/plain' }),
    /unsupported media type/
  );
});

test('attachment validation accepts UTF-8 BOM and strips it without normalizing line endings', async () => {
  const { validateTextAttachmentBytes } = require('../daemon/src/attachment-validation');
  const bytes = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('a\r\nb', 'utf8')]);

  const result = await validateTextAttachmentBytes(bytes, { name: 'notes.txt', mimeType: 'text/plain' });

  assert.equal(result.text, 'a\r\nb');
  assert.equal(result.mimeType, 'text/plain');
});

test('attachment validation rejects UTF-16 text and binary-looking text', async () => {
  const { validateTextAttachmentBytes } = require('../daemon/src/attachment-validation');

  await assert.rejects(
    () => validateTextAttachmentBytes(Buffer.from([0xff, 0xfe, 0x61, 0x00]), { name: 'notes.txt', mimeType: 'text/plain' }),
    /unsupported media type/
  );
  await assert.rejects(
    () => validateTextAttachmentBytes(Buffer.from([0x61, 0x00, 0x62]), { name: 'notes.txt', mimeType: 'text/plain' }),
    /unsupported media type/
  );
});

test('attachment validation rejects non-text MIME hints for text bytes', async () => {
  const { validateTextAttachmentBytes } = require('../daemon/src/attachment-validation');

  await assert.rejects(
    () => validateTextAttachmentBytes(Buffer.from('hello', 'utf8'), { name: 'notes.txt', mimeType: 'image/png' }),
    /unsupported media type/
  );
  const result = await validateTextAttachmentBytes(Buffer.from('hello', 'utf8'), {
    name: 'notes.txt',
    mimeType: 'Text/Markdown; charset=utf-8'
  });

  assert.equal(result.mimeType, 'text/markdown');
});

test('attachment validation rejects known non-text signatures in text bytes', async () => {
  const { validateTextAttachmentBytes } = require('../daemon/src/attachment-validation');

  await assert.rejects(
    () => validateTextAttachmentBytes(Buffer.from('%PDF-1.7\nhello', 'utf8'), { name: 'notes.txt', mimeType: 'text/plain' }),
    /unsupported media type/
  );
  await assert.rejects(
    () => validateTextAttachmentBytes(Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex'), { name: 'notes.txt', mimeType: 'text/plain' }),
    /unsupported media type/
  );
  await assert.rejects(
    () => validateTextAttachmentBytes(Buffer.from('504b0304616263', 'hex'), { name: 'notes.txt', mimeType: 'text/plain' }),
    /unsupported media type/
  );
});

test('attachment validation sniffs PNG, JPEG, WebP, and rejects non-WebP RIFF', () => {
  const { sniffAttachmentBytes } = require('../daemon/src/attachment-validation');

  assert.equal(sniffAttachmentBytes(Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex')).mimeType, 'image/png');
  assert.equal(sniffAttachmentBytes(Buffer.from('ffd8ffe000104a464946', 'hex')).mimeType, 'image/jpeg');
  assert.equal(sniffAttachmentBytes(Buffer.from('524946460000000057454250', 'hex')).mimeType, 'image/webp');
  assert.equal(sniffAttachmentBytes(Buffer.from('524946460000000057415645', 'hex')).knownType, 'riff-other');
});

test('attachment image header validation accepts supported images and rejects non-images', () => {
  const { validateImageAttachmentHeader } = require('../daemon/src/attachment-validation');

  assert.deepEqual(validateImageAttachmentHeader(minimalPngBytes({ width: 640, height: 480 }), { name: 'image.png' }), {
    mimeType: 'image/png',
    knownType: 'png',
    width: 640,
    height: 480
  });
  assert.deepEqual(validateImageAttachmentHeader(minimalJpegBytes({ width: 320, height: 240 }), { name: 'image.jpg' }), {
    mimeType: 'image/jpeg',
    knownType: 'jpeg',
    width: 320,
    height: 240
  });
  assert.deepEqual(validateImageAttachmentHeader(minimalWebpBytes({ width: 16, height: 9 }), { name: 'image.webp' }), {
    mimeType: 'image/webp',
    knownType: 'webp',
    width: 16,
    height: 9
  });
  assert.throws(
    () => validateImageAttachmentHeader(Buffer.from('%PDF-1.7\nhello', 'utf8'), { name: 'report.pdf' }),
    /unsupported media type/
  );
  assert.throws(
    () => validateImageAttachmentHeader(Buffer.from('hello', 'utf8'), { name: 'notes.txt' }),
    /unsupported media type/
  );
  assert.throws(
    () => validateImageAttachmentHeader(minimalPngBytes({ width: 20000, height: 1 }), { name: 'wide.png' }),
    (error) => error.status === 413 && error.code === 'ATTACHMENT_LIMIT_EXCEEDED'
  );
  assert.throws(
    () => validateImageAttachmentHeader(Buffer.from('89504e470d0a1a0a', 'hex'), { name: 'truncated.png' }),
    (error) => error.status === 415 && error.code === 'UNSUPPORTED_MEDIA_TYPE'
  );
});

test('attachment PDF header validation accepts PDFs and rejects non-PDF bytes', () => {
  const { validatePdfAttachmentHeader } = require('../daemon/src/attachment-validation');

  assert.equal(validatePdfAttachmentHeader(Buffer.from('%PDF-1.7\nhello', 'utf8'), { name: 'report.pdf' }).mimeType, 'application/pdf');
  assert.throws(
    () => validatePdfAttachmentHeader(Buffer.from('not a pdf', 'utf8'), { name: 'report.pdf' }),
    (error) => error.status === 415 && error.code === 'UNSUPPORTED_MEDIA_TYPE'
  );
});

test('context budget estimate counts code points and wrapper ascii conservatively', () => {
  const { estimateAttachmentTextTokens } = require('../daemon/src/attachment-validation');

  assert.equal(estimateAttachmentTextTokens({ asciiChars: 30, wrapperChars: 12, nonAsciiChars: 2 }), 16);
  assert.equal(estimateAttachmentTextTokens({ text: 'abc你好😀', wrapperChars: 0 }), 4);
});

test('attachment context budget reports successful and exceeded estimates', () => {
  const { assertWithinContextBudget } = require('../daemon/src/attachment-validation');

  assert.deepEqual(assertWithinContextBudget(100, 4096), {
    estimatedTokens: 100,
    contextWindow: 4096,
    reserve: 2048,
    available: 2048
  });
  assert.throws(() => assertWithinContextBudget(2049, 4096), (error) => {
    assert.equal(error.status, 413);
    assert.equal(error.code, 'ATTACHMENT_CONTEXT_BUDGET_EXCEEDED');
    assert.equal(error.message, 'attachment context budget exceeded');
    assert.deepEqual(error.details, {
      estimatedTokens: 2049,
      contextWindow: 4096,
      reserve: 2048,
      available: 2048
    });
    return true;
  });
});

test('attachment HTTP errors expose stable status code details and message', () => {
  const { attachmentHttpError } = require('../daemon/src/attachment-validation');
  const details = { field: 'name' };

  const error = attachmentHttpError(415, 'UNSUPPORTED_MEDIA_TYPE', 'unsupported media type', details);

  assert.equal(error.status, 415);
  assert.equal(error.code, 'UNSUPPORTED_MEDIA_TYPE');
  assert.equal(error.message, 'unsupported media type');
  assert.equal(error.details, details);
});

test('attachment scratch store writes scoped metadata and cleanup stays under root', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-'));
  const store = new AttachmentScratchStore({ root, now: () => new Date('2026-05-19T00:00:00.000Z') });

  const scratch = await store.createMessageScratch({
    conversationId: 'conv_1',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn'
  });
  await scratch.writeFile('file_0.png', Buffer.from('abc'));
  await scratch.writeMetadata({ active: true, pid: process.pid });

  assert.equal(fs.existsSync(path.join(scratch.dir, 'metadata.json')), true);
  assert.equal(fs.existsSync(path.join(scratch.dir, 'file_0.png')), true);

  await scratch.cleanup();

  assert.equal(fs.existsSync(scratch.dir), false);
});

test('attachment scratch writeFile rejects reserved and non-flat file names', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-file-name-'));
  const store = new AttachmentScratchStore({ root, now: () => new Date('2026-05-19T00:00:00.000Z') });
  const scratch = await store.createMessageScratch({
    conversationId: 'conv_1',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn'
  });

  try {
    await assert.rejects(() => scratch.writeFile('metadata.json', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('.attachment-scratch', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('metadata.json:ads', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('CON.txt', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('bad\u0001name.txt', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('photo\u202Egpj.txt', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('trailing.', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('trailing ', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('nested/file.txt', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile(path.join(root, 'absolute.txt'), Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('../escape.txt', Buffer.from('abc')), /scratch file name is invalid/);
    await assert.rejects(() => scratch.writeFile('', Buffer.from('abc')), /scratch file name is invalid/);

    assert.equal(fs.existsSync(path.join(scratch.dir, 'metadata.json')), true);
    assert.equal(fs.existsSync(path.join(scratch.dir, 'nested')), false);
    assert.equal(fs.existsSync(path.join(root, 'absolute.txt')), false);
  } finally {
    await scratch.cleanup();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('attachment scratch metadata keeps base lifecycle fields authoritative', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-metadata-'));
  const store = new AttachmentScratchStore({ root, now: () => new Date('2026-05-19T00:00:00.000Z') });

  const scratch = await store.createMessageScratch({
    conversationId: 'conv_1',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn'
  });
  try {
    await scratch.writeMetadata({
      active: true,
      conversationId: 'conv_evil',
      createdAt: '1999-01-01T00:00:00.000Z'
    });

    const metadata = JSON.parse(fs.readFileSync(path.join(scratch.dir, 'metadata.json'), 'utf8'));
    assert.equal(metadata.active, true);
    assert.equal(metadata.conversationId, 'conv_1');
    assert.equal(metadata.clientMessageId, 'client_1');
    assert.equal(metadata.scratchLifetime, 'turn');
    assert.equal(metadata.createdAt, '2026-05-19T00:00:00.000Z');
  } finally {
    await scratch.cleanup();
  }
});

test('attachment scratch ignores public field mutation for writes and cleanup', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-mutation-'));
  const fakeRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-fake-root-'));
  const fakeDir = path.join(fakeRoot, 'fake-message');
  fs.mkdirSync(fakeDir);
  const store = new AttachmentScratchStore({ root, now: () => new Date('2026-05-19T00:00:00.000Z') });

  const scratch = await store.createMessageScratch({
    conversationId: 'conv_1',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn'
  });
  const originalDir = scratch.dir;
  attemptPublicMutation(() => { scratch.dir = fakeDir; });
  attemptPublicMutation(() => { scratch.root = fakeRoot; });
  attemptPublicMutation(() => { scratch._root = fakeRoot; });
  attemptPublicMutation(() => {
    scratch.baseMetadata = {
      conversationId: 'conv_evil',
      clientMessageId: 'client_evil',
      scratchLifetime: 'forever',
      createdAt: '1999-01-01T00:00:00.000Z'
    };
  });
  attemptPublicMutation(() => {
    scratch.baseMetadata.conversationId = 'conv_evil_nested';
  });
  scratch._root = fakeRoot;
  scratch.baseMetadata = {
    conversationId: 'conv_evil',
    clientMessageId: 'client_evil',
    scratchLifetime: 'forever',
    createdAt: '1999-01-01T00:00:00.000Z'
  };

  const written = await scratch.writeFile('file_0.txt', Buffer.from('abc'));
  await scratch.writeMetadata({ active: true });

  assert.equal(written, path.join(originalDir, 'file_0.txt'));
  assert.equal(fs.existsSync(path.join(originalDir, 'file_0.txt')), true);
  assert.equal(fs.existsSync(path.join(fakeDir, 'file_0.txt')), false);
  const metadata = JSON.parse(fs.readFileSync(path.join(originalDir, 'metadata.json'), 'utf8'));
  assert.equal(metadata.active, true);
  assert.equal(metadata.conversationId, 'conv_1');
  assert.equal(metadata.clientMessageId, 'client_1');
  assert.equal(metadata.scratchLifetime, 'turn');
  assert.equal(metadata.createdAt, '2026-05-19T00:00:00.000Z');

  await scratch.cleanup();
  assert.equal(fs.existsSync(originalDir), false);
  assert.equal(fs.existsSync(fakeDir), true);
  fs.rmSync(fakeRoot, { recursive: true, force: true });
  assert.equal(fs.existsSync(root), true);
  fs.rmSync(root, { recursive: true, force: true });
});

test('attachment scratch cleanup rejects constructor root equality and escaped dirs', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { MessageScratch } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-constructor-'));
  const baseMetadata = {
    conversationId: 'conv_1',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn',
    createdAt: '2026-05-19T00:00:00.000Z'
  };

  assert.throws(
    () => new MessageScratch({ root, dir: root, baseMetadata }),
    /scratch constructor is private/
  );

  const escapedDir = path.dirname(root);
  assert.throws(
    () => new MessageScratch({ root, dir: escapedDir, baseMetadata }),
    /scratch constructor is private/
  );

  assert.equal(fs.existsSync(root), true);
  fs.rmSync(root, { recursive: true, force: true });
});

test('attachment scratch constructor rejects arbitrary child directories', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { MessageScratch } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-child-'));
  const unrelatedDir = path.join(root, 'unrelated-existing-dir');
  fs.mkdirSync(unrelatedDir);
  const baseMetadata = {
    conversationId: 'conv_1',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn',
    createdAt: '2026-05-19T00:00:00.000Z'
  };

  assert.throws(
    () => new MessageScratch({ root, dir: unrelatedDir, baseMetadata }),
    /scratch constructor is private/
  );
  assert.equal(fs.existsSync(unrelatedDir), true);
  assert.equal(fs.existsSync(path.join(unrelatedDir, 'file_0.txt')), false);
  fs.rmSync(root, { recursive: true, force: true });
});

test('attachment scratch constructor rejects forged message directory names', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { MessageScratch } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-forged-'));
  const forgedDir = path.join(root, 'msg_123_00000000-0000-4000-8000-000000000000');
  fs.mkdirSync(forgedDir);
  const baseMetadata = {
    conversationId: 'conv_1',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn',
    createdAt: '2026-05-19T00:00:00.000Z'
  };

  assert.throws(
    () => new MessageScratch({ root, dir: forgedDir, baseMetadata }),
    /scratch constructor is private/
  );
  assert.equal(fs.existsSync(forgedDir), true);
  assert.equal(fs.existsSync(path.join(forgedDir, 'file_0.txt')), false);
  fs.rmSync(root, { recursive: true, force: true });
});

test('attachment scratch cleanupExpired deletes expired inactive scratches only', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-expired-'));
  let now = new Date('2026-05-19T00:00:00.000Z');
  const store = new AttachmentScratchStore({ root, ttlMs: 1000, now: () => now });

  const expired = await store.createMessageScratch({
    conversationId: 'conv_expired',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn'
  });
  const active = await store.createMessageScratch({
    conversationId: 'conv_active',
    clientMessageId: 'client_2',
    scratchLifetime: 'turn'
  });

  now = new Date('2026-05-19T00:00:02.000Z');
  await store.cleanupExpired({ activeConversationIds: new Set(['conv_active']) });

  assert.equal(fs.existsSync(expired.dir), false);
  assert.equal(fs.existsSync(active.dir), true);
  await active.cleanup();
  fs.rmSync(root, { recursive: true, force: true });
});

test('attachment scratch cleanupExpired ignores unrelated child directories', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-unrelated-'));
  const unrelatedDir = path.join(root, 'unrelated-existing-dir');
  fs.mkdirSync(unrelatedDir);
  const store = new AttachmentScratchStore({
    root,
    ttlMs: 1000,
    now: () => new Date('2026-05-19T00:00:02.000Z')
  });

  await store.cleanupExpired();

  assert.equal(fs.existsSync(unrelatedDir), true);
  fs.rmSync(root, { recursive: true, force: true });
});

test('attachment scratch cleanupExpired ignores scratch-shaped dirs without marker', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-unmarked-'));
  const unmarkedDir = path.join(root, 'msg_123_00000000-0000-4000-8000-000000000000');
  fs.mkdirSync(unmarkedDir);
  const store = new AttachmentScratchStore({
    root,
    ttlMs: 1000,
    now: () => new Date('2026-05-19T00:00:02.000Z')
  });

  await store.cleanupExpired();

  assert.equal(fs.existsSync(unmarkedDir), true);
  fs.rmSync(root, { recursive: true, force: true });
});

test('attachment scratch cleanupExpired deletes marked scratch with missing or malformed metadata', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attachment-scratch-bad-metadata-'));
  const store = new AttachmentScratchStore({
    root,
    ttlMs: 1000,
    now: () => new Date('2026-05-19T00:00:02.000Z')
  });

  const missing = await store.createMessageScratch({
    conversationId: 'conv_missing',
    clientMessageId: 'client_1',
    scratchLifetime: 'turn'
  });
  fs.rmSync(path.join(missing.dir, 'metadata.json'), { force: true });
  const malformed = await store.createMessageScratch({
    conversationId: 'conv_malformed',
    clientMessageId: 'client_2',
    scratchLifetime: 'turn'
  });
  fs.writeFileSync(path.join(malformed.dir, 'metadata.json'), '{not-json', 'utf8');

  await store.cleanupExpired();

  assert.equal(fs.existsSync(missing.dir), false);
  assert.equal(fs.existsSync(malformed.dir), false);
  fs.rmSync(root, { recursive: true, force: true });
});

test('createApp starts attachment scratch cleanup without deleting conservative paths', async () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const { AttachmentScratchStore } = require('../daemon/src/attachment-scratch-store');
  const appDbPath = tempConversationDbPath('app-db-attachment-scratch-startup-');
  const scratchRoot = path.join(path.dirname(appDbPath), 'attachment-scratch');
  const oldStore = new AttachmentScratchStore({
    root: scratchRoot,
    now: () => new Date('2020-01-01T00:00:00.000Z')
  });
  const expired = await oldStore.createMessageScratch({
    conversationId: 'conv_expired',
    clientMessageId: 'client_expired',
    scratchLifetime: 'turn'
  });
  const currentStore = new AttachmentScratchStore({ root: scratchRoot });
  const current = await currentStore.createMessageScratch({
    conversationId: 'conv_current',
    clientMessageId: 'client_current',
    scratchLifetime: 'turn'
  });
  const unmarked = path.join(scratchRoot, 'msg_123_00000000-0000-4000-8000-000000000000');
  const unrelated = path.join(scratchRoot, 'unrelated');
  fs.mkdirSync(unmarked, { recursive: true });
  fs.mkdirSync(unrelated, { recursive: true });

  const app = createApp({ port: 0, devAdapters: false, appDbPath });
  try {
    await app.attachmentScratchCleanup;

    assert.equal(fs.existsSync(expired.dir), false);
    assert.equal(fs.existsSync(current.dir), true);
    assert.equal(fs.existsSync(unmarked), true);
    assert.equal(fs.existsSync(unrelated), true);
  } finally {
    app.appSqliteStore.close();
    fs.rmSync(path.dirname(appDbPath), { recursive: true, force: true });
  }
});

function attemptPublicMutation(mutator) {
  try {
    mutator();
  } catch {
    // Getter-only properties throw in this strict test file; non-strict callers may see ignored writes.
  }
}
(async () => {
  let passed = 0;
  for (const item of tests) {
    try {
      await item.fn();
      passed += 1;
      console.log(`ok - ${item.name}`);
    } catch (error) {
      console.error(`not ok - ${item.name}`);
      console.error(error);
      process.exitCode = 1;
      break;
    }
  }
  if (process.exitCode) return;
  console.log(`${passed} tests passed`);
})();









