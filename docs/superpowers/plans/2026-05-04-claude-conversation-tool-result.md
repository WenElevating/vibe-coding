# Claude Conversation Tool Result Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Claude long-lived conversation command output by correlating `tool_use`, `tool_use_delta`, and `tool_result` events with `toolUseId`.

**Architecture:** Normalize all Claude stream frames through one unwrap step before event-specific mapping. `ClaudeConversationAdapter` owns in-memory tool correlation and emits `tool.started`, `tool.delta`, `tool.output`, and `tool.completed`; the conversation event stream persists those normalized fields; Flutter updates command cards strictly by `toolUseId`.

**Tech Stack:** Node.js CommonJS daemon, `scripts/run-tests.js`, Flutter/Dart protocol models and reducer tests.

---

## File Structure

- Modify: `daemon/src/claude-conversation-adapter.js` — unwrap `stream_event` globally, track pending tools, map `tool_use_delta` / `tool_result`, emit normalized tool events.
- Modify: `scripts/run-tests.js` — add daemon regression tests for stream-wrapped tools, repeated `tool_use`, orphan `tool_result`, and interleaved multi-tool results.
- Modify: `mobile/lib/src/models/protocol.dart` — parse `toolUseId`, `exitCode`, `isError`, and `durationMs` from conversation events.
- Modify: `mobile/lib/src/state/conversation_reducer.dart` — correlate command messages by `toolUseId`, append `tool.delta` / `tool.output`, complete only matching commands, ignore output without `toolUseId`.
- Modify: `mobile/test/protocol_compatibility_test.dart` — cover new event fields.
- Modify: `mobile/test/conversation_reducer_test.dart` — cover tool delta/output/completion, approval/command separation, missing `toolUseId`, and interleaved commands.

No new dependencies. No database schema changes. Do not modify one-shot `/api/runs` behavior for this plan.

## Task 1: Daemon Tool Event Correlation

**Files:**
- Modify: `daemon/src/claude-conversation-adapter.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing daemon test for wrapped tool use and result**

Add a test near the existing Claude conversation adapter tests in `scripts/run-tests.js`:

```js
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
```

- [ ] **Step 2: Write failing daemon test for repeated tool_use, orphan result, and interleaving**

Add a second test:

```js
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
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_use', id: 'toolu_b', name: 'Read', input: { file_path: 'README.md' } })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_result', tool_use_id: 'toolu_b', content: 'readme body', exit_code: 0, is_error: false })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_result', tool_use_id: 'toolu_a', content: 'tests passed', exit_code: 0, is_error: false })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ type: 'tool_result', tool_use_id: 'toolu_orphan', content: 'resumed output', exit_code: 0, is_error: false })}\n`);

  const starts = events.filter((event) => event.type === 'tool.started');
  const outputs = events.filter((event) => event.type === 'tool.output');
  assert.equal(starts.find((event) => event.toolUseId === 'toolu_a').input.command, 'npm test');
  assert.equal(outputs.find((event) => event.toolUseId === 'toolu_b').text, 'readme body');
  assert.equal(outputs.find((event) => event.toolUseId === 'toolu_a').text, 'tests passed');
  assert.equal(outputs.find((event) => event.toolUseId === 'toolu_orphan').text, 'resumed output');
});
```

- [ ] **Step 3: Run daemon tests to verify failure**

Run: `npm test`

Expected: FAIL because `ClaudeConversationAdapter` currently does not emit normalized `tool.started`, `tool.output`, or `tool.completed` from normal `tool_use` / `tool_result` frames.

- [ ] **Step 4: Add global unwrap step and pendingTools state**

In `daemon/src/claude-conversation-adapter.js`, change state creation:

```js
const state = {
  child,
  onEvent,
  pendingQuestions: new Map(),
  pendingApprovals: new Map(),
  pendingTools: new Map(),
  now: () => new Date()
};
```

At the start of `handleRawClaudeEvent`, add:

```js
const event = unwrapClaudeEvent(raw);
const rawType = typeof event.type === 'string' ? event.type : 'raw';
```

Define:

```js
function unwrapClaudeEvent(raw) {
  if (raw && raw.type === 'stream_event' && raw.event && typeof raw.event === 'object') {
    return {
      ...raw.event,
      session_id: raw.event.session_id || raw.session_id,
      sessionId: raw.event.sessionId || raw.sessionId
    };
  }
  return raw;
}
```

Use `event` instead of `raw` for downstream mapping, while keeping `raw` attached only when useful for diagnostics.

- [ ] **Step 5: Implement tool mapping helpers**

Add helpers in `daemon/src/claude-conversation-adapter.js`:

```js
function handleToolUse(raw, state) {
  const toolUseId = raw.id || raw.tool_use_id;
  if (!toolUseId) return;
  const previous = state.pendingTools.get(toolUseId) || {};
  const input = raw.input && typeof raw.input === 'object' ? raw.input : previous.input || {};
  const tool = {
    toolUseId,
    name: raw.name || raw.tool_name || previous.name || 'tool',
    input,
    startedAt: previous.startedAt || state.now().toISOString()
  };
  state.pendingTools.set(toolUseId, tool);
  state.onEvent({
    type: conversationEventTypes.TOOL_STARTED,
    toolUseId,
    toolName: tool.name,
    input: tool.input,
    summary: summarizeToolInput(tool.name, tool.input),
    raw
  });
}

function handleToolDelta(raw, state) {
  const toolUseId = raw.tool_use_id || raw.id;
  if (!toolUseId) return;
  const text = extractToolText(raw);
  if (!text) return;
  state.onEvent({ type: 'tool.delta', toolUseId, text, raw });
}

function handleToolResult(raw, state) {
  const toolUseId = raw.tool_use_id || raw.id;
  if (!toolUseId) return;
  const pending = state.pendingTools.get(toolUseId) || null;
  const text = extractToolText(raw);
  const exitCode = Number.isInteger(raw.exit_code) ? raw.exit_code : null;
  const isError = raw.is_error === true;
  state.onEvent({
    type: conversationEventTypes.TOOL_OUTPUT,
    toolUseId,
    toolName: pending?.name || raw.name || raw.tool_name || null,
    input: pending?.input || {},
    text,
    exitCode,
    isError,
    raw
  });
  state.onEvent({
    type: conversationEventTypes.TOOL_COMPLETED,
    toolUseId,
    toolName: pending?.name || raw.name || raw.tool_name || null,
    input: pending?.input || {},
    exitCode,
    isError,
    durationMs: pending ? Math.max(0, state.now().getTime() - Date.parse(pending.startedAt)) : null,
    raw
  });
  state.pendingTools.delete(toolUseId);
}

function extractToolText(raw) {
  if (typeof raw.content === 'string') return raw.content;
  if (typeof raw.text === 'string') return raw.text;
  if (typeof raw.delta === 'string') return raw.delta;
  if (Array.isArray(raw.content)) return raw.content.map((part) => part?.text || part?.content || '').join('');
  return '';
}
```

Use these branches before generic assistant/result handling:

```js
if (rawType === 'tool_use') return handleToolUse(event, state);
if (rawType === 'tool_use_delta') return handleToolDelta(event, state);
if (rawType === 'tool_result') return handleToolResult(event, state);
```

- [ ] **Step 6: Run daemon tests**

Run: `npm test`

Expected: PASS.

## Task 2: Mobile Protocol Fields

**Files:**
- Modify: `mobile/lib/src/models/protocol.dart`
- Modify: `mobile/test/protocol_compatibility_test.dart`

- [ ] **Step 1: Write failing protocol parsing test**

Add to `ConversationEvent parses normalized assistant and approval events` or a new test in `mobile/test/protocol_compatibility_test.dart`:

```dart
test('ConversationEvent parses tool correlation fields', () {
  final output = ConversationEvent.fromJson(const <String, Object?>{
    'seq': 3,
    'conversationId': 'conv_1',
    'type': 'tool.output',
    'createdAt': '2026-05-04T00:00:02.000Z',
    'toolUseId': 'toolu_a',
    'toolName': 'Bash',
    'text': '1 failing test',
    'exitCode': 1,
    'isError': true,
    'durationMs': 250
  });

  expect(output.toolUseId, 'toolu_a');
  expect(output.toolName, 'Bash');
  expect(output.exitCode, 1);
  expect(output.isError, true);
  expect(output.durationMs, 250);
});
```

- [ ] **Step 2: Run focused Flutter model test to verify failure**

Run: `cd mobile && flutter test test/protocol_compatibility_test.dart`

Expected: FAIL because `ConversationEvent` does not expose `toolUseId`, `exitCode`, `isError`, or `durationMs` yet.

- [ ] **Step 3: Implement fields in ConversationEvent**

In `mobile/lib/src/models/protocol.dart`, add constructor params and fields:

```dart
this.toolUseId,
this.exitCode,
this.isError = false,
this.durationMs,
```

Add final fields:

```dart
final String? toolUseId;
final int? exitCode;
final bool isError;
final int? durationMs;
```

Parse them in `fromJson`:

```dart
toolUseId: json['toolUseId'] as String?,
exitCode: json['exitCode'] as int?,
isError: json['isError'] as bool? ?? false,
durationMs: json['durationMs'] as int?,
```

- [ ] **Step 4: Run focused Flutter model test**

Run: `cd mobile && flutter test test/protocol_compatibility_test.dart`

Expected: PASS.

## Task 3: Mobile Reducer Tool Correlation

**Files:**
- Modify: `mobile/lib/src/state/conversation_reducer.dart`
- Modify: `mobile/test/conversation_reducer_test.dart`

- [ ] **Step 1: Write failing reducer test for delta/output/completion by toolUseId**

Add to `mobile/test/conversation_reducer_test.dart`:

```dart
test('ConversationViewState correlates tool output by toolUseId', () {
  final state = const ConversationViewState().apply(<ConversationEvent>[
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'tool.started',
      'createdAt': '2026-05-04T00:00:00.000Z',
      'toolUseId': 'toolu_a',
      'toolName': 'Bash',
      'input': {'command': 'npm test'}
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 2,
      'conversationId': 'conv_1',
      'type': 'tool.delta',
      'createdAt': '2026-05-04T00:00:01.000Z',
      'toolUseId': 'toolu_a',
      'text': 'running tests'
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 3,
      'conversationId': 'conv_1',
      'type': 'tool.output',
      'createdAt': '2026-05-04T00:00:02.000Z',
      'toolUseId': 'toolu_a',
      'text': '1 failing test',
      'exitCode': 1,
      'isError': true
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 4,
      'conversationId': 'conv_1',
      'type': 'tool.completed',
      'createdAt': '2026-05-04T00:00:03.000Z',
      'toolUseId': 'toolu_a',
      'exitCode': 1,
      'isError': true
    })
  ]);

  expect(state.messages.single.role, 'command');
  expect(state.messages.single.text, 'npm test');
  expect(state.messages.single.output, contains('running tests'));
  expect(state.messages.single.output, contains('1 failing test'));
  expect(state.messages.single.completed, true);
});
```

- [ ] **Step 2: Write failing reducer test for interleaving and missing toolUseId**

Add:

```dart
test('ConversationViewState keeps interleaved tool outputs separate and ignores missing ids', () {
  final state = const ConversationViewState().apply(<ConversationEvent>[
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'tool.started',
      'createdAt': '2026-05-04T00:00:00.000Z',
      'toolUseId': 'toolu_a',
      'toolName': 'Bash',
      'input': {'command': 'npm test'}
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 2,
      'conversationId': 'conv_1',
      'type': 'tool.started',
      'createdAt': '2026-05-04T00:00:01.000Z',
      'toolUseId': 'toolu_b',
      'toolName': 'Read',
      'input': {'file_path': 'README.md'}
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 3,
      'conversationId': 'conv_1',
      'type': 'tool.output',
      'createdAt': '2026-05-04T00:00:02.000Z',
      'toolUseId': 'toolu_b',
      'text': 'readme body'
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 4,
      'conversationId': 'conv_1',
      'type': 'tool.output',
      'createdAt': '2026-05-04T00:00:03.000Z',
      'toolUseId': 'toolu_a',
      'text': 'tests passed'
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 5,
      'conversationId': 'conv_1',
      'type': 'tool.output',
      'createdAt': '2026-05-04T00:00:04.000Z',
      'text': 'must not attach'
    })
  ]);

  final npm = state.messages.firstWhere((message) => message.text == 'npm test');
  final read = state.messages.firstWhere((message) => message.text.contains('README.md'));
  expect(npm.output, contains('tests passed'));
  expect(npm.output, isNot(contains('readme body')));
  expect(npm.output, isNot(contains('must not attach')));
  expect(read.output, contains('readme body'));
});
```

- [ ] **Step 3: Run focused reducer test to verify failure**

Run: `cd mobile && flutter test test/conversation_reducer_test.dart`

Expected: FAIL because messages are currently keyed by `approvalId` / newest incomplete command, not `toolUseId`.

- [ ] **Step 4: Add toolUseId to ConversationMessage**

In `mobile/lib/src/state/conversation_reducer.dart`, add:

```dart
this.toolUseId,
this.exitCode,
this.isError = false,
```

and fields:

```dart
final String? toolUseId;
final int? exitCode;
final bool isError;
```

Update all `ConversationMessage(...)` copies in helper functions to preserve `toolUseId`, `exitCode`, and `isError`.

- [ ] **Step 5: Implement command upsert by toolUseId**

Update command helpers:

```dart
int _commandIndexForToolUseId(List<ConversationMessage> messages, String? toolUseId) {
  if (toolUseId == null || toolUseId.isEmpty) return -1;
  return messages.indexWhere((message) => message.role == 'command' && message.toolUseId == toolUseId);
}
```

In `apply`, add cases:

```dart
case 'tool.started':
  final toolUseId = event.toolUseId;
  if (toolUseId == null || toolUseId.isEmpty) break;
  _upsertCommandMessage(nextMessages, ConversationMessage(
    role: 'command',
    text: _toolCommandText(event),
    eventSeq: event.seq,
    toolUseId: toolUseId,
    approvalId: event.approvalId,
    startedAt: event.createdAt,
  ));
  break;
case 'tool.delta':
  _appendCommandOutput(nextMessages, event);
  break;
```

Update `_appendCommandOutput` so it returns early when `event.toolUseId` is missing, and otherwise finds by `toolUseId` only.

Update `_completeCommandMessages` so `tool.completed` completes only the matching `toolUseId`; `conversation.completed` can still complete all incomplete commands.

- [ ] **Step 6: Add command text helper**

Add:

```dart
String _toolCommandText(ConversationEvent event) {
  final command = event.input['command'];
  if (command is String && command.trim().isNotEmpty) return command.trim();
  final file = event.input['file_path'] ?? event.input['path'] ?? event.input['filename'];
  if (file is String && file.trim().isNotEmpty) {
    return '${event.toolName ?? 'Tool'} ${file.trim()}';
  }
  final summary = event.summary;
  if (summary != null && summary.trim().isNotEmpty) return summary.trim();
  return event.toolName ?? 'Tool';
}
```

- [ ] **Step 7: Run reducer tests**

Run: `cd mobile && flutter test test/conversation_reducer_test.dart`

Expected: PASS.

## Task 4: Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run daemon tests**

Run: `npm test`

Expected: PASS.

- [ ] **Step 2: Run JS lint**

Run: `npm run lint`

Expected: PASS.

- [ ] **Step 3: Run focused Flutter tests**

Run: `cd mobile && flutter test test/protocol_compatibility_test.dart test/conversation_reducer_test.dart`

Expected: PASS. If sandbox blocks Flutter, record the exact error and do not claim Flutter verification passed.

- [ ] **Step 4: Run Flutter analyze**

Run: `cd mobile && flutter analyze`

Expected: PASS. If sandbox blocks Flutter, record the exact error and do not claim analyzer verification passed.

- [ ] **Step 5: Inspect diff scope**

Run: `git diff --stat`

Expected: changes are limited to Claude conversation tool event handling, conversation event field parsing, reducer command correlation, tests, and this plan/spec documentation.

## Self-Review Notes

- Spec coverage: global `stream_event` unwrap, repeated `tool_use`, `tool_use_delta`, `tool_result`, orphan resume result, interleaved multi-tool output, strict mobile `toolUseId`, and approval/command separation are all represented.
- Placeholder scan: no open placeholder tasks remain; each code step includes concrete snippets and commands.
- Type consistency: `toolUseId`, `exitCode`, `isError`, and `durationMs` are used consistently across daemon events and Dart models.

