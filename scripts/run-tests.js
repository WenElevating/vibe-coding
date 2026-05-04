'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');
const { EventEmitter } = require('node:events');
const { AuthManager, verifyToken } = require('../daemon/src/auth');
const { validateRunCreate, assertNoV1TerminalRequest, eventTypes } = require('../daemon/src/protocol');
const { EventStore } = require('../daemon/src/event-store');
const { WorkspaceRegistry } = require('../daemon/src/workspace');
const { AuditLog, redact } = require('../daemon/src/audit');
const { ClaudeAdapter, mapClaudeEvent, buildClaudeArgs, resolvePermissionMode, parsePermissionModes } = require('../daemon/src/claude-adapter');
const { ClaudeConversationAdapter } = require('../daemon/src/claude-conversation-adapter');
const { createApp } = require('../daemon/src/main');

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
    conversationEventTypes,
    normalizeConversationCreate,
    normalizeMessagePayload,
    normalizeQuestionResponse,
    normalizeApprovalDecision
  } = require('../daemon/src/conversation-protocol');

  assert.equal(conversationStatuses.IDLE, 'idle');
  assert.equal(conversationStatuses.WAITING_INPUT, 'waiting_input');
  assert.equal(conversationStatuses.WAITING_APPROVAL, 'waiting_approval');
  assert.equal(conversationStatuses.INTERRUPTED, 'interrupted');
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
  const adapter = new ClaudeAdapter({ command: 'claude', spawnSyncFn: () => ({ status: 1, stdout: '', stderr: 'not found' }) });
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
  const adapter = new ClaudeAdapter({ spawnSyncFn: () => ({ status: 1, stdout: '', stderr: 'missing' }), spawnFn: () => new EventEmitter() });
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
  await new Promise((resolve) => setTimeout(resolve, 1700));

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

test('Claude adapter starts CLI after explicitly changing to workspace', async () => {
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

  assert.equal(spawnCommand, process.platform === 'win32' ? 'cmd.exe' : 'sh');
  const launchScript = spawnArgs.join(' ');
  assert.equal(launchScript.includes(workspacePath), true);
  assert.equal(launchScript.includes(process.platform === 'win32' ? 'cd /d' : 'cd '), true);
  assert.equal(launchScript.includes('claude'), true);
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

test('Claude adapter shell launch escapes Windows workspace metacharacters', () => {
  const adapter = new ClaudeAdapter({
    spawnSyncFn: fakeSpawnSync,
    spawnFn: (_cmd, args) => {
      const script = args.join(' ');
      assert.equal(script.includes('A^&B^(C^)'), true);
      return fakeSpawn();
    }
  });

  adapter.startRun({ prompt: 'x', workspacePath: 'D:\\A&B(C)', permissionMode: 'auto', onEvent: () => {} });
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
    const created = await request(port, 'POST', '/api/runs', {
      tool: 'claude',
      workspaceId: 'default',
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
    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', prompt: 'first' }, paired.body.token);
    await new Promise((resolve) => setTimeout(resolve, 1700));
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
  await new Promise((resolve) => setTimeout(resolve, 1700));

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
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'conversation-test' });
    token = paired.body.token;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId: 'default', adapter: 'claude' }, token);
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
    const paired = await request(restartedPort, 'POST', '/api/pair', { code: pairing.body.code, label: 'conversation-test-restarted' });
    const restartedToken = paired.body.token;
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
    const rejected = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', prompt: 'x', command: 'dir' }, token);
    assert.equal(rejected.status, 400);
    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', prompt: 'hello' }, token);
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
    const shortcuts = await request(port, 'GET', '/api/shortcuts', null, token);
    assert.equal(shortcuts.body.shortcuts.some((shortcut) => shortcut.id === 'test'), true);
    const created = await request(port, 'POST', '/api/runs', { tool: 'claude', workspaceId: 'default', shortcutId: 'test' }, token);
    assert.equal(created.status, 201);
    const filtered = await request(port, 'GET', '/api/runs?tool=claude&workspaceId=default&status=running', null, token);
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
    const rejected = await request(port, 'POST', '/api/runs', { tool: 'codex', workspaceId: 'default', prompt: 'x', args: ['--danger'] }, token);
    assert.equal(rejected.status, 400);
    const created = await request(port, 'POST', '/api/runs', { tool: 'codex', workspaceId: 'default', prompt: 'hello' }, token);
    assert.equal(created.status, 201);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});
function fakeSpawnSync(_cmd, args) {
  if (args.includes('--version')) return { status: 0, stdout: 'claude-test', stderr: '' };
  return { status: 0, stdout: '-p --bare --output-format stream-json --verbose --include-partial-messages --resume', stderr: '' };
}

function fakeCodexSpawnSync(_cmd, args) {
  if (args.includes('--version')) return { status: 0, stdout: 'codex-test', stderr: '' };
  return { status: 0, stdout: 'Usage: codex exec --json', stderr: '' };
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

test('V1.2 queue serializes workspace runs and synthetic adapter completes without provider CLI', async () => {
  const app = createApp({ port: 0, devAdapters: true, conversationDbPath: tempConversationDbPath() });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const first = await request(port, 'POST', '/api/runs', { tool: 'synthetic-slow', workspaceId: 'default', prompt: 'first' }, token);
    const second = await request(port, 'POST', '/api/runs', { tool: 'synthetic-jsonl', workspaceId: 'default', prompt: 'second' }, token);
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
    const templates = await request(port, 'GET', '/api/command-templates', null, token);
    assert.equal(templates.body.templates.some((template) => template.id === 'test'), true);
    const rejected = await request(port, 'POST', '/api/command-templates', { id: 'bad', label: 'bad', prompt: 'bad', command: 'rm -rf' }, token);
    assert.equal(rejected.status, 400);
    const invoked = await request(port, 'POST', '/api/command-templates/test/invoke', { workspaceId: 'default', tool: 'synthetic-jsonl' }, token);
    assert.equal(invoked.status, 201);
    assert.equal(invoked.body.run.tool, 'synthetic-jsonl');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
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
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const health = await request(port, 'GET', '/api/health');
    assert.equal(health.status, 200);
    assert.equal(health.body.daemonVersion, '1.3.0');
    assert.equal(health.body.security.ptyEnabled, false);
    assert.equal(JSON.stringify(health.body).includes('Bearer'), false);
    const version = await request(port, 'GET', '/api/version');
    assert.equal(version.body.schemaVersion, 5);
    assert.equal(version.body.mode, 'dev');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
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










