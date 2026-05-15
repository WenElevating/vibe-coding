'use strict';

process.env.AUTH_TOKEN_SECRET = process.env.AUTH_TOKEN_SECRET || 'test-only-auth-token-secret';
process.env.DEVICE_ID_PEPPER = process.env.DEVICE_ID_PEPPER || 'test-only-device-id-pepper';

const assert = require('node:assert/strict');
const http = require('node:http');
const { EventEmitter } = require('node:events');
const { AuthManager, hashDeviceId, verifyToken } = require('../daemon/src/auth');
const { validateRunCreate, assertNoV1TerminalRequest, eventTypes } = require('../daemon/src/protocol');
const { EventStore } = require('../daemon/src/event-store');
const { WorkspaceRegistry } = require('../daemon/src/workspace');
const { AuditLog, redact } = require('../daemon/src/audit');
const { ClaudeAdapter, mapClaudeEvent, buildClaudeArgs, resolvePermissionMode, parsePermissionModes } = require('../daemon/src/claude-adapter');
const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
const { CodexConversationAdapter, mapCodexEvent } = require('../daemon/src/codex-conversation-adapter');
const { resolveCliInvocation } = require('../daemon/src/cli-resolver');
const { AdapterRegistry } = require('../daemon/src/adapter-registry');
const { createApp } = require('../daemon/src/main');
const { AsrModelAsset } = require('../daemon/src/asr-model-asset');

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

function tempConversationDbPath(prefix = 'conversation-app-') {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), prefix)), 'conversations.sqlite');
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

  const defaultConversationCreate = normalizeConversationCreate({
    workspaceId: 'default',
    adapter: 'claude',
    permissionMode: 'default'
  });
  assert.deepEqual(defaultConversationCreate, {
    workspaceId: 'default',
    adapter: 'claude',
    permissionMode: 'default',
    requestedTools: [],
    requestedToolPolicy: { tools: [], allowedTools: [], disallowedTools: [] },
    resumePolicy: { type: 'fresh' },
    systemPromptPolicy: { type: 'none' }
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
    systemPromptPolicy: { type: 'append', text: 'Keep responses concise.' }
  });
  assert.deepEqual(extendedConversationCreate, {
    workspaceId: 'default',
    adapter: 'claude',
    permissionMode: 'auto',
    requestedTools: ['Read', 'Glob'],
    requestedToolPolicy: { tools: ['Read', 'Glob', 'Grep'], allowedTools: ['Read'], disallowedTools: ['Bash'] },
    resumePolicy: { type: 'resume', sessionId: 'claude-session-1', name: 'bugfix' },
    systemPromptPolicy: { type: 'append', text: 'Keep responses concise.' }
  });
  assert.equal(normalizeMessagePayload({ text: ' hello ' }).text, 'hello');
  assert.equal(normalizeQuestionResponse({ questionId: 'q1', text: ' answer ' }).text, 'answer');
  assert.equal(normalizeApprovalDecision({ decision: 'allow' }).decision, 'allow');
  assert.throws(() => normalizeConversationCreate({ workspaceId: '', adapter: 'claude' }), /workspaceId is required/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: 'default', adapter: 'unknown' }), /unsupported adapter/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: 'default', resumePolicy: { type: 'sideways' } }), /resumePolicy.type is invalid/);
  assert.throws(() => normalizeConversationCreate({ workspaceId: 'default', systemPromptPolicy: { type: 'replace' } }), /systemPromptPolicy.type is invalid/);
  assert.throws(() => normalizeMessagePayload({ text: '' }), /text is required/);
  assert.throws(() => normalizeQuestionResponse({ questionId: 'q1', text: '' }), /text is required/);
  assert.throws(() => normalizeApprovalDecision({ decision: 'maybe' }), /decision must be allow or deny/);
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
    createdAt: '2026-05-08T00:00:00.000Z', updatedAt: '2026-05-08T00:00:01.000Z', capabilities: { resume: true }, handle: null
  });

  const loaded = sqlite.loadConversations()[0];
  assert.equal(loaded.sessionBinding, 'confirmed');
  assert.equal(loaded.userMessageCount, 3);
  assert.equal(loaded.cliSessionId, 'claude-session-1');
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
    capabilities: { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true },
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

  adapter.onEvent({ type: 'approval.requested', approvalId: 'ap1', toolName: 'Bash', toolUseId: 'toolu_1', input: { command: 'dir' }, summary: 'List files' });
  const waitingApproval = manager.getConversation(conversation.id, device);
  assert.equal(waitingApproval.status, 'waiting_approval');
  assert.equal(waitingApproval.blockingItem.toolUseId, 'toolu_1');
  await assert.rejects(() => manager.respondApproval(conversation.id, 'bad', { decision: 'allow' }, device), /approvalId does not match/);
  await manager.respondApproval(conversation.id, 'ap1', { decision: 'allow' }, device);
  assert.equal(manager.getConversation(conversation.id, device).status, 'running');
  assert.deepEqual(fakeHandle.approvals, [{ approvalId: 'ap1', decision: 'allow' }]);
  const resolvedApproval = manager.listEvents(conversation.id, 0, device)
    .find((event) => event.type === 'approval.resolved');
  assert.equal(resolvedApproval.toolUseId, 'toolu_1');

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
        return { status: 0, stdout: '-p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-mode [default|acceptEdits|plan|dontAsk|bypassPermissions]', stderr: '' };
      }
      return { status: 0, stdout: '', stderr: '' };
    }
  });
  const capability = adapter.detectCapabilities();
  assert.deepEqual(capability.capabilities.permissionModes.sort(), ['acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan'].sort());
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

test('Claude permission mode parser extracts documented candidates', () => {
  assert.deepEqual(parsePermissionModes('--permission-mode [default|auto|acceptEdits|plan|dontAsk|bypassPermissions]').sort(), ['acceptEdits', 'auto', 'bypassPermissions', 'default', 'dontAsk', 'plan'].sort());
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
  assert.equal(spawnArgs.includes('--permission-prompt-tool'), false);
  assert.equal(spawnArgs.join(' ').includes('cd /d'), false);
  assert.equal(spawnOptions.cwd, workspacePath);
  assert.equal(spawnOptions.env.PWD, workspacePath);
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
      permission_suggestions: ['allow']
    }
  })}\n`);

  const approval = events.find((event) => event.type === 'approval.requested');
  assert.equal(approval.approvalId, 'approval_1');
  assert.equal(approval.summary, 'dir scripts');
  await handle.respondApproval('approval_1', 'allow');
  assert.equal(stdinLines.some((line) => line.includes('approval_1') && line.includes('"behavior":"allow"')), true);
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
  assert.deepEqual(spawnArgs.slice(0, 5), ['--ask-for-approval', 'never', 'exec', '--json', '-C']);
  assert.equal(spawnArgs.includes('--skip-git-repo-check'), true);
  assert.equal(spawnArgs.includes('--dangerously-bypass-approvals-and-sandbox'), false);
  assert.equal(spawnArgs[spawnArgs.length - 1], 'hello');
  assert.equal(spawnOptions.cwd, 'D:\\AiProject\\vibe-coding');
  assert.equal(stdinEnded, true);
  child.emit('exit', 0, null);
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

  assert.deepEqual(spawnCalls[0].args.slice(0, 5), ['--ask-for-approval', 'on-request', 'exec', 'resume', '--json']);
  assert.equal(spawnCalls[0].args.includes('-C'), false);
  assert.equal(spawnCalls[0].args.includes('--cd'), false);
  assert.equal(spawnCalls[0].options.cwd, 'D:\\Authorized\\Repo');
  assert.equal(spawnCalls[0].args.includes('--skip-git-repo-check'), true);
  assert.equal(spawnCalls[0].args[6], 'thread_1');
  assert.equal(spawnCalls[0].args[7], 'second');
  spawnCalls[0].child.emit('exit', 0, null);
});

test('Codex event mapper normalizes thread, assistant, tool, declined, unknown, and failed events', () => {
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
  const declined = mapCodexEvent({ type: 'item.completed', item: { id: 'cmd_1', type: 'command_execution', command: 'write', aggregated_output: 'rejected: blocked by policy', status: 'declined' } });
  assert.equal(declined.type, 'system.notice');
  assert.equal(declined.noticeKind, 'codex_policy_blocked');
  assert.equal(mapCodexEvent({ type: 'turn.failed', error: { message: 'bad model' } }).type, 'run.error');
  assert.equal(mapCodexEvent({ type: 'new.future.event', value: 1 }).type, 'system.notice');
});

test('Codex mapper truncates large aggregated output with marker', () => {
  const event = mapCodexEvent({ type: 'item.completed', item: { id: 'cmd_big', type: 'command_execution', command: 'dump', aggregated_output: 'abcdef', status: 'completed' } }, { maxAggregatedOutputBytes: 3 });
  assert.equal(event.type, 'tool.output');
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
    assert.deepEqual(spawned[0].args.slice(approvalIndex, approvalIndex + 5), ['--ask-for-approval', 'never', 'exec', '--json', '-C']);
    const events = await request(port, 'GET', `/api/conversations/${conversationId}/events?afterSeq=0`, null, token);
    assert.equal(events.body.events.some((event) => event.type === 'assistant.message' && event.text === 'hello from codex'), true);
    assert.equal(events.body.events.some((event) => event.type === 'conversation.completed'), true);
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
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath() });
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

async function requestRaw(port, method, path, body, token, extraHeaders = {}) {
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

test('V1.3 diagnostic export is authenticated, redacted, and audited', async () => {
  const app = createApp({ port: 0, mode: 'dev', devAdapters: true, conversationDbPath: tempConversationDbPath() });
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
  const appDbPath = tempConversationDbPath('app-db-exceptions-');
  const app = createApp({ port: 0, mode: 'dev', devAdapters: true, appDbPath });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const recorded = await request(port, 'POST', '/api/exceptions', {
      source: 'mobile',
      message: 'SocketException: Write failed',
      path: '/api/conversations/conv_1/events?afterSeq=44',
      conversationId: 'conv_1',
      metadata: { operation: 'pollConversationEvents' }
    }, token);
    assert.equal(recorded.status, 201);
    assert.match(recorded.body.traceId, /^trc_/);
    assert.equal(app.appSqliteStore.listExceptions()[0].traceId, recorded.body.traceId);
    const exported = await request(port, 'POST', '/api/diagnostics/export', {}, token);
    const fs = require('node:fs');
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









