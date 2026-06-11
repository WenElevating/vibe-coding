'use strict';

process.env.AUTH_TOKEN_SECRET = process.env.AUTH_TOKEN_SECRET || 'test-only-auth-token-secret';
process.env.DEVICE_ID_PEPPER = process.env.DEVICE_ID_PEPPER || 'test-only-device-id-pepper';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { createApp } = require('../src/main');
const { AppSqliteStore } = require('../src/app-sqlite-store');
const { eventTypes } = require('../src/protocol');

function fakeSpawnSync(_cmd, args) {
  if (args.includes('--version')) return { status: 0, stdout: 'claude-test', stderr: '' };
  return { status: 0, stdout: '--output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-prompt-tool', stderr: '' };
}

function createFakeClaudeRecorder() {
  const spawnedArgs = [];
  const stdinWrites = [];
  return {
    spawnedArgs,
    stdinWrites,
    spawnFn: (_cmd, args) => fakeSpawn(_cmd, args, { spawnedArgs, stdinWrites })
  };
}

function fakeSpawn(_cmd, args, recorder) {
  const { spawnedArgs, stdinWrites } = recorder;
  spawnedArgs.push(args);
  const child = new EventEmitter();
  const permissionMode = args[args.indexOf('--permission-mode') + 1];
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { destroyed: false, write: (data) => {
    stdinWrites.push(data);
    if (data.includes('\"subtype\":\"initialize\"')) {
      const request = JSON.parse(data);
      setImmediate(() => child.stdout.emit('data', Buffer.from(JSON.stringify({ type: 'control_response', response: { subtype: 'success', request_id: request.request_id, response: {} } }) + '\n')));
    }
  } };
  child.kill = () => child.emit('exit', null, 'SIGTERM');
  setImmediate(() => {
    if (permissionMode === 'default') {
      child.stdout.emit('data', Buffer.from('{"type":"control_request","request_id":"approval_1","request":{"subtype":"can_use_tool","tool_name":"Read","input":{"file_path":"README.md"},"tool_use_id":"toolu_1"}}\n'));
      return;
    }
    child.stdout.emit('data', Buffer.from('{"type":"assistant","text":"hello","session_id":"claude-session-1"}\n'));
    child.emit('exit', 0);
  });
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

function tempAppDbPath(prefix) {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), prefix)), 'app.sqlite');
}

test('app sqlite migration adds workspace soft-delete columns before partial index', () => {
  const dbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'lan-ai-old-workspaces-')), 'app.sqlite');
  let oldStore = new AppSqliteStore({ dbPath });
  oldStore.db.exec('DROP INDEX IF EXISTS idx_workspaces_owner_path_active');
  oldStore.db.exec('DROP TABLE workspace_device_authorizations');
  oldStore.db.exec('DROP TABLE workspaces');
  oldStore.db.exec(`
    CREATE TABLE workspaces (
      id TEXT PRIMARY KEY,
      owner_device_id TEXT NOT NULL,
      name TEXT NOT NULL,
      path TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE workspace_device_authorizations (
      device_id TEXT NOT NULL,
      workspace_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (device_id, workspace_id),
      FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
    );
    INSERT INTO workspaces(id, owner_device_id, name, path, created_at, updated_at)
      VALUES ('workspace-old', 'device-old', 'Old', 'D:/old', '2026-05-01T00:00:00.000Z', '2026-05-01T00:00:00.000Z');
    INSERT INTO workspace_device_authorizations(device_id, workspace_id, created_at)
      VALUES ('device-old', 'workspace-old', '2026-05-01T00:00:00.000Z');
  `);
  oldStore.close();

  const migrated = new AppSqliteStore({ dbPath });
  try {
    const columns = migrated.db.prepare('PRAGMA table_info(workspaces)').all().map((row) => row.name);
    assert.equal(columns.includes('is_deleted'), true);
    assert.equal(columns.includes('deleted_at'), true);
    assert.deepEqual(migrated.listWorkspacesForDevice('device-old').map((workspace) => workspace.id), ['workspace-old']);
    const indexes = migrated.db.prepare('PRAGMA index_list(workspaces)').all().map((row) => row.name);
    assert.equal(indexes.includes('idx_workspaces_owner_path_active'), true);
  } finally {
    migrated.close();
  }
});

test('HTTP API enforces pairing, workspace ACL, run creation, replay, and V1 terminal boundary', async () => {
  const fakeClaude = createFakeClaudeRecorder();
  const app = createApp({ port: 0, appDbPath: tempAppDbPath('lan-ai-server-api-') });
  const claude = app.adapterRegistry.get('claude');
  claude.spawnSyncFn = fakeSpawnSync;
  claude.spawnFn = fakeClaude.spawnFn;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test', deviceId: 'device-test-api' });
    assert.equal(paired.status, 200);

    const token = paired.body.token;
    app.workspaces.authorizeDeviceForWorkspace({ id: paired.body.deviceId, allowedWorkspaceIds: new Set() }, 'default');
    const rejected = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', prompt: 'x', command: 'dir' }, token);
    assert.equal(rejected.status, 400);

    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', prompt: 'hello', permissionMode: 'auto' }, token);
    assert.equal(created.status, 201);
    assert.equal(fakeClaude.spawnedArgs.at(-1).includes('--input-format'), true);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(fakeClaude.stdinWrites.some((item) => /\"type\":\"user\"/.test(item)), true);

    const events = await request(port, 'GET', `/api/runs/${created.body.id}/events?afterSeq=0`, null, token);
    assert.equal(events.status, 200);
    assert.equal(events.body.events[0].type, eventTypes.RUN_STARTED);
    assert.equal(events.body.events.some((event) => event.type === eventTypes.ASSISTANT_DELTA), true);

    const replay = await request(port, 'GET', `/api/runs/${created.body.id}/events?afterSeq=1`, null, token);
    assert.equal(replay.body.events.every((event) => event.seq > 1), true);

    const followUp = await request(port, 'POST', `/api/runs/${created.body.id}/input`, { prompt: 'continue with the same context' }, token);
    assert.equal(followUp.status, 200);
    await new Promise((resolve) => setTimeout(resolve, 20));
    const resumedArgs = fakeClaude.spawnedArgs.at(-1);
    assert.equal(resumedArgs.includes('--resume'), true);
    assert.equal(resumedArgs[resumedArgs.indexOf('--resume') + 1], 'claude-session-1');
    assert.match(fakeClaude.stdinWrites.at(-1), /continue with the same context/);

    const cancelled = await request(port, 'POST', `/api/runs/${created.body.id}/cancel`, {}, token);
    assert.equal(cancelled.status, 200);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('HTTP token refresh does not require a valid access token', async () => {
  const app = createApp({
    port: 0,
    appDbPath: tempAppDbPath('lan-ai-auth-'),
    accessTokenTtlMs: 10,
    refreshTokenTtlMs: 30 * 24 * 60 * 60 * 1000
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test', deviceId: 'device-123' });
    await new Promise((resolve) => setTimeout(resolve, 20));

    const denied = await request(port, 'GET', '/api/adapters', null, paired.body.token);
    assert.equal(denied.status, 401);
    assert.equal(denied.body.error.code, 'AUTH_REQUIRED');

    const refreshed = await request(port, 'POST', '/api/token/refresh', {
      deviceId: 'device-123',
      refreshToken: paired.body.refreshToken
    });

    assert.equal(refreshed.status, 200);
    assert.equal(refreshed.body.deviceId, 'device-123');
    assert.notEqual(refreshed.body.token, paired.body.token);
    assert.equal(typeof refreshed.body.accessTokenExpiresAt, 'string');
    assert.equal(typeof refreshed.body.refreshTokenExpiresAt, 'string');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});



test('Claude adapter filters SDK hook output frames', () => {
  const { mapClaudeEvent } = require('../src/claude-adapter');
  assert.equal(mapClaudeEvent({ continue: true, suppressOutput: true }).type, '__internal');
  assert.equal(mapClaudeEvent({ hookSpecificOutput: { hookEventName: 'SessionStart' } }).type, '__internal');
});

test('Claude default permission mode emits approval and writes control response', async () => {
  const fakeClaude = createFakeClaudeRecorder();
  const app = createApp({ port: 0, appDbPath: tempAppDbPath('lan-ai-approval-') });
  const claude = app.adapterRegistry.get('claude');
  claude.spawnSyncFn = fakeSpawnSync;
  claude.spawnFn = fakeClaude.spawnFn;
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test', deviceId: 'device-test-approval' });
    const token = paired.body.token;
    app.workspaces.authorizeDeviceForWorkspace({ id: paired.body.deviceId, allowedWorkspaceIds: new Set() }, 'default');
    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', prompt: 'read files', permissionMode: 'default' }, token);
    assert.equal(created.status, 201);
    await new Promise((resolve) => setTimeout(resolve, 20));

    const events = await request(port, 'GET', `/api/runs/${created.body.id}/events?afterSeq=0`, null, token);
    const approval = events.body.events.find((event) => event.type === eventTypes.APPROVAL_REQUIRED);
    assert.equal(approval.approvalId, 'approval_1');
    assert.equal(approval.toolName, 'Read');

    const response = await request(port, 'POST', '/api/approvals/approval_1/respond', { decision: 'allow' }, token);
    assert.equal(response.status, 200);
    assert.match(fakeClaude.stdinWrites.at(-1), /control_response/);
    assert.match(fakeClaude.stdinWrites.at(-1), /allow/);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});

test('workspace inspector APIs expose overview, tree, content, diagnostics, extensions, and reject path escape', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'mobile-real-client-api-'));
  fs.mkdirSync(path.join(tempRoot, 'lib', 'src'), { recursive: true });
  fs.writeFileSync(path.join(tempRoot, 'README.md'), '# Fixture\n', 'utf8');
  fs.writeFileSync(path.join(tempRoot, 'lib', 'src', 'auth_service.dart'), 'class AuthService {\n  // TODO: test diagnostic\n  void login() {}\n}\n', 'utf8');

  const app = createApp({ port: 0, appDbPath: tempAppDbPath('lan-ai-inspector-') });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;

  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test', deviceId: 'device-test-inspector' });
    const token = paired.body.token;
    app.workspaces.add({ id: 'fixture', name: 'Fixture', workspacePath: tempRoot }, { id: paired.body.deviceId, allowedWorkspaceIds: new Set() });

    const overview = await request(port, 'GET', '/api/workspaces/fixture/overview', null, token);
    assert.equal(overview.status, 200);
    assert.equal(overview.body.workspaceId, 'fixture');
    assert.equal(overview.body.fileCount >= 2, true);

    const tree = await request(port, 'GET', '/api/workspaces/fixture/files/tree', null, token);
    assert.equal(tree.status, 200);
    assert.equal(tree.body.entries.some((entry) => entry.name === 'lib'), true);

    const content = await request(port, 'GET', '/api/workspaces/fixture/files/content?path=lib/src/auth_service.dart', null, token);
    assert.equal(content.status, 200);
    assert.equal(content.body.content.includes('AuthService'), true);

    const rejected = await request(port, 'GET', '/api/workspaces/fixture/files/content?path=../package.json', null, token);
    assert.equal(rejected.status, 400);

    const diagnostics = await request(port, 'GET', '/api/workspaces/fixture/diagnostics/code', null, token);
    assert.equal(diagnostics.status, 200);
    assert.equal(diagnostics.body.diagnostics.some((item) => item.message.includes('TODO')), true);

    const extensions = await request(port, 'GET', '/api/extensions', null, token);
    assert.equal(extensions.status, 200);
    assert.equal(Array.isArray(extensions.body.extensions), true);
    assert.equal(extensions.body.extensions.every((item) => typeof item.status === 'string' && typeof item.description === 'string'), true);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
