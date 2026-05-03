'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { ClaudeAdapter, mapClaudeEvent } = require('../src/claude-adapter');
const { eventTypes } = require('../src/protocol');

test('Claude capability detection marks adapter unavailable on missing CLI', () => {
  const adapter = new ClaudeAdapter({
    command: 'claude',
    spawnSyncFn: () => ({ status: 1, stdout: '', stderr: 'not found' })
  });

  const capability = adapter.detectCapabilities();
  assert.equal(capability.available, false);
  assert.equal(capability.capabilities.streamJson, false);
});

test('Claude capability detection requires stream json flags', () => {
  const adapter = new ClaudeAdapter({
    command: 'claude',
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '1.2.3', stderr: '' };
      return { status: 0, stdout: '-p --bare --output-format stream-json --verbose --include-partial-messages --resume', stderr: '' };
    }
  });

  const capability = adapter.detectCapabilities();
  assert.equal(capability.available, true);
  assert.equal(capability.capabilities.bare, true);
  assert.equal(capability.capabilities.streamJson, true);
});

test('Claude events map to unified event types', () => {
  assert.equal(mapClaudeEvent({ type: 'assistant', text: 'hi' }).type, eventTypes.ASSISTANT_DELTA);
  assert.equal(mapClaudeEvent({ type: 'tool_start', name: 'bash' }).type, eventTypes.TOOL_STARTED);
  assert.equal(mapClaudeEvent({ type: 'tool_result', text: 'ok' }).type, eventTypes.TOOL_OUTPUT);
  assert.equal(mapClaudeEvent({ type: 'unknown', text: 'raw' }).type, eventTypes.RAW_OUTPUT);
});

test('startRun emits actionable unavailable error before spawning', () => {
  const adapter = new ClaudeAdapter({
    spawnSyncFn: () => ({ status: 1, stdout: '', stderr: 'missing' }),
    spawnFn: () => new EventEmitter()
  });

  assert.throws(() => adapter.startRun({ prompt: 'x', workspacePath: '.', onEvent: () => {} }), /unavailable/);
});


test('startRun writes stream-json prompt to stdin and closes input without initialize response', async () => {
  const writes = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    ended: false,
    write(data) { writes.push(data); },
    end() { this.ended = true; this.destroyed = true; writes.push('[stdin.end]'); }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');

  const adapter = new ClaudeAdapter({
    spawnSyncFn: (_cmd, args) => args.includes('--version')
      ? { status: 0, stdout: '2.1.119', stderr: '' }
      : { status: 0, stdout: '--output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-prompt-tool', stderr: '' },
    spawnFn: (_cmd, args) => {
      assert.equal(args.includes('--input-format'), true);
      assert.equal(args.includes('--print'), true);
      assert.deepEqual(args.slice(args.indexOf('--system-prompt'), args.indexOf('--system-prompt') + 2), ['--system-prompt', '']);
      assert.equal(args.includes('--permission-prompt-tool'), false);
      return child;
    }
  });

  adapter.startRun({ prompt: 'who are you?', workspacePath: '.', permissionMode: 'auto', onEvent: () => {} });
  await new Promise((resolve) => setTimeout(resolve, 1700));

  assert.equal(writes.some((line) => line.includes('"type":"control_request"')), true);
  assert.equal(writes.some((line) => line.includes('who are you?')), true);
  assert.equal(writes.some((line) => line.includes('"session_id":""')), true);
  assert.equal(child.stdin.ended, true);
});

test('startRun handles initialize response before writing prompt', async () => {
  const writes = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    ended: false,
    write(data) {
      writes.push(data);
      if (data.includes('"subtype":"initialize"')) {
        const request = JSON.parse(data);
        setImmediate(() => child.stdout.emit('data', Buffer.from(JSON.stringify({
          type: 'control_response',
          response: { subtype: 'success', request_id: request.request_id, response: {} }
        }) + '\n')));
      }
    },
    end() { this.ended = true; this.destroyed = true; writes.push('[stdin.end]'); }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');

  const adapter = new ClaudeAdapter({
    spawnSyncFn: (_cmd, args) => args.includes('--version')
      ? { status: 0, stdout: '2.1.119', stderr: '' }
      : { status: 0, stdout: '--output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-prompt-tool', stderr: '' },
    spawnFn: () => child
  });

  adapter.startRun({ prompt: 'hello after init', workspacePath: '.', permissionMode: 'default', onEvent: () => {} });
  await new Promise((resolve) => setTimeout(resolve, 30));

  const initializeIndex = writes.findIndex((line) => line.includes('"subtype":"initialize"'));
  const promptIndex = writes.findIndex((line) => line.includes('hello after init'));
  assert.equal(initializeIndex >= 0, true);
  assert.equal(promptIndex > initializeIndex, true);
  assert.equal(child.stdin.ended, false);
});

test('startRun emits assistant text and completion for Claude result frames', async () => {
  const events = [];
  const writes = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    ended: false,
    write(data) {
      writes.push(data);
      if (data.includes('"result smoke"')) {
        setImmediate(() => child.stdout.emit('data', Buffer.from(JSON.stringify({
          type: 'result',
          subtype: 'success',
          is_error: false,
          result: 'I am Claude, an AI coding assistant.',
          session_id: 'claude-session-1'
        }) + '\n')));
        setImmediate(() => child.emit('exit', 0, null));
      }
    },
    end() { this.ended = true; this.destroyed = true; writes.push('[stdin.end]'); }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');

  const adapter = new ClaudeAdapter({
    spawnSyncFn: (_cmd, args) => args.includes('--version')
      ? { status: 0, stdout: '2.1.119', stderr: '' }
      : { status: 0, stdout: '--output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-prompt-tool', stderr: '' },
    spawnFn: () => child
  });

  adapter.startRun({ prompt: 'result smoke', workspacePath: '.', permissionMode: 'auto', onEvent: (event) => events.push(event) });
  await new Promise((resolve) => setTimeout(resolve, 1700));

  assert.equal(writes.some((line) => line.includes('result smoke')), true);
  assert.equal(events.some((event) => event.type === eventTypes.ASSISTANT_DELTA && event.text.includes('AI coding assistant')), true);
  assert.equal(events.filter((event) => event.type === eventTypes.RUN_COMPLETED).length, 1);
});

test('startRun suppresses late Claude noise after result completion', async () => {
  const events = [];
  const writes = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    destroyed: false,
    ended: false,
    write(data) {
      writes.push(data);
      if (data.includes('"late noise smoke"')) {
        setImmediate(() => {
          child.stdout.emit('data', Buffer.from(JSON.stringify({
            type: 'result',
            subtype: 'success',
            is_error: false,
            result: 'done',
            session_id: 'claude-session-late-noise'
          }) + '\n'));
          child.stdout.emit('data', Buffer.from(JSON.stringify({
            type: 'system',
            subtype: 'status',
            status: 'requesting',
            session_id: 'claude-session-late-noise'
          }) + '\n'));
          child.emit('exit', 0, null);
        });
      }
    },
    end() { this.ended = true; this.destroyed = true; writes.push('[stdin.end]'); }
  };
  child.kill = () => child.emit('exit', null, 'SIGTERM');

  const adapter = new ClaudeAdapter({
    spawnSyncFn: (_cmd, args) => args.includes('--version')
      ? { status: 0, stdout: '2.1.119', stderr: '' }
      : { status: 0, stdout: '--output-format stream-json --input-format stream-json --verbose --include-partial-messages --resume --permission-prompt-tool', stderr: '' },
    spawnFn: () => child
  });

  adapter.startRun({ prompt: 'late noise smoke', workspacePath: '.', permissionMode: 'auto', onEvent: (event) => events.push(event) });
  await new Promise((resolve) => setTimeout(resolve, 1700));

  assert.equal(events.filter((event) => event.type === eventTypes.RUN_COMPLETED).length, 1);
  assert.equal(events.some((event) => event.text === 'Claude requesting'), false);
  assert.equal(events.at(-1).type, eventTypes.RUN_COMPLETED);
});

test('Claude stream_event frames unwrap nested events', () => {
  const event = mapClaudeEvent({
    type: 'stream_event',
    event: { type: 'assistant', message: { role: 'assistant', content: 'nested hello' } },
    session_id: 'claude-session-2'
  });

  assert.equal(event.type, eventTypes.ASSISTANT_DELTA);
  assert.equal(event.text, 'nested hello');
  assert.equal(event.sessionId, 'claude-session-2');
});

test('Claude api_retry system frames remain visible as retry status', () => {
  const event = mapClaudeEvent({
    type: 'system',
    subtype: 'api_retry',
    attempt: 4,
    max_retries: 10,
    retry_delay_ms: 4310.2,
    error_status: 503,
    error: 'server_error',
    session_id: 'claude-session-3'
  });

  assert.equal(event.type, eventTypes.RAW_OUTPUT);
  assert.equal(event.sessionId, 'claude-session-3');
  assert.equal(event.text.includes('503'), true);
  assert.equal(event.text.includes('retry 4/10'), true);
});
