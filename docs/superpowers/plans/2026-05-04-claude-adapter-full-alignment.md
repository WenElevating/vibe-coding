# Claude Adapter Full Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the Claude CLI adapter, daemon conversation protocol, API summaries, and mobile rendering with `docs/claude-code-agent-guide.md`.

**Architecture:** Keep Claude-specific runtime behavior inside the daemon adapter, expose only normalized conversation events and summaries through `/api/conversations`, and make Flutter render typed blocking states instead of raw Claude frames. Preserve existing conversation-first structure while adding explicit capability, permission, notice, and session semantics.

**Tech Stack:** Node.js CommonJS daemon, `node:test`, Flutter/Dart models and widget/reducer tests, existing polling API.

---

## File Structure

- Modify: `daemon/src/claude-adapter.js` — Claude capability detection, launch argument builder, stream-json handshake, event mapping, protocol leak filtering.
- Modify: `daemon/test/claude-adapter.test.js` — focused adapter tests for permissions, launch args, `stream_event`, system notices, handshake, stdin lifecycle.
- Modify: `daemon/src/conversation-protocol.js` — request normalization for extended conversation creation fields and permission modes.
- Modify: `daemon/src/conversation-manager.js` — effective permission mode, blocking item metadata, notices, timeout/error state handling, session capture.
- Modify: `daemon/test/server.test.js` — conversation API and manager regression tests.
- Modify: `daemon/src/conversation-sqlite-store.js` — persist new summary fields if stored conversations need them.
- Modify: `mobile/lib/src/models/protocol.dart` — parse new conversation fields, blocking metadata, notices, multi-select details.
- Modify: `mobile/lib/src/state/conversation_reducer.dart` — keep question, approval, command, and notice messages distinct.
- Modify: `mobile/lib/main.dart` — render new blocking card details where the current UI builds conversation messages/cards.
- Modify: `mobile/test/protocol_compatibility_test.dart` — model parsing coverage.
- Modify: `mobile/test/conversation_reducer_test.dart` — reducer semantics coverage.
- Modify: `mobile/test/widget_test.dart` — UI behavior coverage.

Do not create new dependencies. Do not commit changes unless the user explicitly requests it.

## Task 1: Protocol Fields and API Normalization

**Files:**
- Modify: `daemon/src/conversation-protocol.js`
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/test/server.test.js`

- [ ] **Step 1: Write failing protocol normalization tests**

Add assertions to the existing `conversation protocol validates statuses and blocking payloads` test in `scripts/run-tests.js` or the relevant conversation protocol test block in `daemon/test/server.test.js` if using `node:test` directly. Cover extended creation input:

```js
const created = normalizeConversationCreate({
  workspaceId: 'default',
  adapter: 'claude',
  permissionMode: 'auto',
  requestedTools: ['Read', 'Glob', 'Grep'],
  requestedToolPolicy: {
    tools: ['Read', 'Glob', 'Grep'],
    allowedTools: ['Read'],
    disallowedTools: ['Bash']
  },
  resumePolicy: { type: 'resume', sessionId: 'claude-session-1' },
  systemPromptPolicy: { type: 'append', text: 'Keep responses concise.' }
});
assert.equal(created.permissionMode, 'auto');
assert.deepEqual(created.requestedTools, ['Read', 'Glob', 'Grep']);
assert.equal(created.requestedToolPolicy.tools[0], 'Read');
assert.equal(created.resumePolicy.sessionId, 'claude-session-1');
assert.equal(created.systemPromptPolicy.type, 'append');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `normalizeConversationCreate` currently drops extended fields and only accepts `default` / `auto`.

- [ ] **Step 3: Implement normalization**

Update `normalizeConversationCreate` so it returns these fields with safe defaults:

```js
return {
  workspaceId,
  adapter,
  permissionMode: normalizePermissionMode(payload.permissionMode),
  requestedTools: normalizeStringList(payload.requestedTools),
  requestedToolPolicy: normalizeToolPolicy(payload.requestedToolPolicy),
  resumePolicy: normalizeResumePolicy(payload.resumePolicy),
  systemPromptPolicy: normalizeSystemPromptPolicy(payload.systemPromptPolicy)
};
```

Add helper functions in `daemon/src/conversation-protocol.js`:

```js
function normalizeStringList(value) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => stringValue(item).trim()).filter(Boolean);
}

function normalizeToolPolicy(value) {
  if (!value || typeof value !== 'object') return { tools: [], allowedTools: [], disallowedTools: [] };
  return {
    tools: normalizeStringList(value.tools),
    allowedTools: normalizeStringList(value.allowedTools),
    disallowedTools: normalizeStringList(value.disallowedTools)
  };
}

function normalizeResumePolicy(value) {
  if (!value || typeof value !== 'object') return { type: 'fresh' };
  const type = stringValue(value.type).trim() || 'fresh';
  if (!['fresh', 'continue', 'resume', 'fork'].includes(type)) throw badRequest('resumePolicy.type is invalid');
  return { type, sessionId: stringValue(value.sessionId).trim(), name: stringValue(value.name).trim() };
}

function normalizeSystemPromptPolicy(value) {
  if (!value || typeof value !== 'object') return { type: 'none' };
  const type = stringValue(value.type).trim() || 'none';
  if (!['none', 'append'].includes(type)) throw badRequest('systemPromptPolicy.type is invalid');
  return { type, text: stringValue(value.text) };
}
```

- [ ] **Step 4: Store requested intent on conversations**

In `ConversationManager.createConversation`, copy the normalized fields onto the conversation object:

```js
requestedPermissionMode: input.permissionMode,
effectivePermissionMode: input.permissionMode,
requestedTools: input.requestedTools,
requestedToolPolicy: input.requestedToolPolicy,
resumePolicy: input.resumePolicy,
systemPromptPolicy: input.systemPromptPolicy,
permissionSupport: {},
notices: [],
protocolVersion: 2,
```

Expose the same values from `publicConversation`.

- [ ] **Step 5: Run daemon tests**

Run: `npm test`

Expected: PASS for existing tests plus the new normalization assertions.

## Task 2: Claude Capability Detection and Launch Args

**Files:**
- Modify: `daemon/src/claude-adapter.js`
- Modify: `daemon/test/claude-adapter.test.js`

- [ ] **Step 1: Write failing capability tests**

Add tests to `daemon/test/claude-adapter.test.js` for permission mode support and fallback:

```js
test('Claude capability detection records permission modes from help text', () => {
  const adapter = new ClaudeAdapter({
    spawnSyncFn: (_cmd, args) => {
      if (args.includes('--version')) return { status: 0, stdout: '2.1.119', stderr: '' };
      if (args.includes('--help')) return { status: 0, stdout: '--permission-mode <mode> [default|acceptEdits|plan|dontAsk|bypassPermissions]', stderr: '' };
      return { status: 0, stdout: '', stderr: '' };
    }
  });
  const capability = adapter.detectCapabilities();
  assert.deepEqual(capability.capabilities.permissionModes.sort(), ['acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan'].sort());
});

test('Claude auto permission mode falls back to default when unsupported', () => {
  const capability = { capabilities: { permissionModes: ['default', 'plan'] } };
  assert.equal(resolvePermissionMode('auto', capability).effectivePermissionMode, 'default');
});
```

Export `resolvePermissionMode` from `daemon/src/claude-adapter.js` for testing.

- [ ] **Step 2: Write failing launch arg tests**

Add tests for stream-json and permission prompt tool mutual exclusion:

```js
test('Claude launch args never add permission-prompt-tool with stream-json input', () => {
  const args = buildClaudeArgs({ permissionMode: 'default', prompt: 'hello' }, {
    capabilities: { permissionModes: ['default'], inputFormat: true }
  }).args;
  assert.equal(args.includes('--input-format'), true);
  assert.equal(args.includes('--permission-prompt-tool'), false);
});
```

Export `buildClaudeArgs` for testing.

- [ ] **Step 3: Run focused adapter tests**

Run: `node --test daemon/test/claude-adapter.test.js`

Expected: FAIL because `permissionModes`, `resolvePermissionMode`, and `buildClaudeArgs` do not exist yet.

- [ ] **Step 4: Implement capability and arg helpers**

In `daemon/src/claude-adapter.js`, add:

```js
function parsePermissionModes(helpText) {
  const supported = new Set(['default']);
  const match = String(helpText || '').match(/--permission-mode[^\n]*(?:\[([^\]]+)\]|:\s*([^\n]+))/i);
  const source = `${match?.[1] || ''} ${match?.[2] || ''}`;
  for (const mode of ['auto', 'acceptEdits', 'bypassPermissions', 'plan', 'dontAsk', 'delegate', 'default']) {
    if (source.includes(mode)) supported.add(mode);
  }
  return Array.from(supported);
}

function resolvePermissionMode(requestedPermissionMode, capability) {
  const requested = requestedPermissionMode || 'default';
  const modes = new Set(capability?.capabilities?.permissionModes || ['default']);
  const effectivePermissionMode = modes.has(requested) ? requested : 'default';
  return { requestedPermissionMode: requested, effectivePermissionMode };
}
```

Add `buildClaudeArgs(input, capability)` that always includes `--print`, `--output-format stream-json`, `--input-format stream-json`, `--verbose`, `--include-partial-messages`, and never adds `--permission-prompt-tool` when `--input-format stream-json` is present.

- [ ] **Step 5: Run focused adapter tests**

Run: `node --test daemon/test/claude-adapter.test.js`

Expected: PASS.

## Task 3: Claude Handshake, Stdin Lifecycle, and Event Mapping

**Files:**
- Modify: `daemon/src/claude-adapter.js`
- Modify: `daemon/test/claude-adapter.test.js`

- [ ] **Step 1: Write failing initialize handshake test**

Add a test proving prompt waits for initialize response:

```js
test('startRun completes initialize handshake before user prompt', async () => {
  const writes = [];
  const child = makeFakeClaudeChild(writes);
  const adapter = new ClaudeAdapter({ spawnSyncFn: claudeOkSpawnSync, spawnFn: () => child });
  adapter.startRun({ prompt: 'hello', workspacePath: '.', permissionMode: 'default', onEvent: () => {} });
  await tick();
  assert.equal(writes.some((line) => line.includes('"hello"')), false);
  const init = JSON.parse(writes.find((line) => line.includes('"initialize"')));
  child.stdout.emit('data', Buffer.from(JSON.stringify({
    type: 'control_response',
    response: { request_id: init.request_id, subtype: 'success', response: {} }
  }) + '\n'));
  await tick();
  assert.equal(writes.some((line) => line.includes('"hello"')), true);
});
```

Define local test helpers `tick`, `makeFakeClaudeChild`, and `claudeOkSpawnSync` in the test file if not already present.

- [ ] **Step 2: Write failing event mapping tests**

Add coverage for `stream_event`, retry notice, status notice, and internal session frames:

```js
assert.equal(mapClaudeEvent({ type: 'stream_event', event: { type: 'assistant', text: 'hi' } }).type, eventTypes.ASSISTANT_DELTA);
assert.equal(mapClaudeEvent({ type: 'system', subtype: 'api_retry', attempt: 1, max_retries: 3, retry_delay_ms: 500 }).type, eventTypes.RAW_OUTPUT);
assert.equal(mapClaudeEvent({ type: 'system', subtype: 'session_start', session_id: 's1' }).sessionId, 's1');
```

- [ ] **Step 3: Run focused adapter tests**

Run: `node --test daemon/test/claude-adapter.test.js`

Expected: FAIL on new handshake or mapping assertions.

- [ ] **Step 4: Implement handshake and mapping**

Update `startRun` so it always sends initialize before prompt:

```js
writeJsonLine(child, {
  type: 'control_request',
  request_id: initRequestId,
  request: { subtype: 'initialize', hooks: null }
});
```

Keep the existing timeout fallback if present; otherwise add a short fallback that sends the prompt after the current test timeout window and emits a protocol warning.

Update `mapClaudeEvent` to unwrap:

```js
if (raw.type === 'stream_event' && raw.event && typeof raw.event === 'object') {
  return mapClaudeEvent(raw.event);
}
```

Add system frame handling that captures `session_id`, returns non-user-facing internal frames with empty text, and formats retry/status notices as normalized raw output text.

- [ ] **Step 5: Run adapter tests**

Run: `node --test daemon/test/claude-adapter.test.js`

Expected: PASS.

## Task 4: Conversation State, Notices, and Persistence

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/conversation-sqlite-store.js`
- Modify: `daemon/test/server.test.js`

- [ ] **Step 1: Write failing conversation manager tests**

Add assertions to the existing conversation manager blocking-state test:

```js
adapter.onEvent({ type: 'assistant.question', questionId: 'q2', text: 'Pick', suggestions: ['A'], multiSelect: true });
const waitingInput = manager.getConversation(conversation.id, device);
assert.equal(waitingInput.blockingItem.type, 'input_request');
assert.equal(waitingInput.blockingItem.multiSelect, true);
assert.ok(waitingInput.blockingItem.createdAt);
assert.ok(waitingInput.blockingItem.expiresAt);
```

Add a notice test:

```js
adapter.onEvent({ type: 'system.notice', text: 'Claude retry 1/3', noticeKind: 'retry' });
const events = manager.listEvents(conversation.id, 0, device);
assert.equal(events.at(-1).type, 'system.notice');
assert.equal(manager.getConversation(conversation.id, device).status, 'running');
```

- [ ] **Step 2: Run daemon tests**

Run: `npm test`

Expected: FAIL because blocking items do not yet include timeout metadata and notices are not normalized.

- [ ] **Step 3: Implement blocking metadata**

In `setBlockingItem`, enrich the item:

```js
const createdAt = this.now().toISOString();
const expiresAt = addMs(this.now(), this.blockingTtlMs || this.idleTtlMs).toISOString();
conversation.blockingItem = { ...blockingItem, createdAt, expiresAt };
```

When mapping `assistant.question`, preserve optional fields:

```js
multiSelect: event.multiSelect === true,
input: event.input || {}
```

- [ ] **Step 4: Implement non-blocking notices**

Handle `system.notice` events in `recordAdapterEvent` by appending them to the event store without changing `conversation.status` or `blockingItem`.

```js
if (event.type === 'system.notice') {
  const { type, ...payload } = event;
  this.eventStore.append(conversation.id, type, payload);
  return;
}
```

- [ ] **Step 5: Persist new fields**

If `conversation-sqlite-store.js` serializes the whole public conversation capability object only, no schema change is needed for `blockingItem` because live blocking items are intentionally cleared on restore. Persist `requestedPermissionMode`, `effectivePermissionMode`, and `permissionSupport` either inside existing JSON fields or as added JSON payload fields in the conversation record.

- [ ] **Step 6: Run daemon tests**

Run: `npm test`

Expected: PASS.

## Task 5: Mobile Protocol Model Parsing

**Files:**
- Modify: `mobile/lib/src/models/protocol.dart`
- Modify: `mobile/test/protocol_compatibility_test.dart`

- [ ] **Step 1: Write failing model parsing tests**

Extend `Conversation models parse daemon conversation payloads`:

```dart
expect(summary.protocolVersion, 2);
expect(summary.requestedPermissionMode, 'auto');
expect(summary.effectivePermissionMode, 'default');
expect(summary.blockingItem?.multiSelect, true);
expect(summary.blockingItem?.expiresAt, '2026-05-04T00:01:00.000Z');
```

Use a test JSON payload containing:

```dart
'protocolVersion': 2,
'requestedPermissionMode': 'auto',
'effectivePermissionMode': 'default',
'permissionSupport': {'permissionModes': ['default', 'plan']},
'blockingItem': {
  'type': 'input_request',
  'questionId': 'q1',
  'text': 'Pick options',
  'suggestions': ['A', 'B'],
  'multiSelect': true,
  'createdAt': '2026-05-04T00:00:00.000Z',
  'expiresAt': '2026-05-04T00:01:00.000Z',
  'input': {'multiSelect': true}
}
```

- [ ] **Step 2: Run focused Flutter model test**

Run: `cd mobile && flutter test test/protocol_compatibility_test.dart`

Expected: FAIL because the new Dart fields do not exist.

- [ ] **Step 3: Implement Dart fields**

Add fields to `ConversationBlockingItem`:

```dart
final bool multiSelect;
final String? createdAt;
final String? expiresAt;
```

Add fields to `ConversationSummary`:

```dart
final int protocolVersion;
final String requestedPermissionMode;
final String effectivePermissionMode;
final Map<String, Object?> permissionSupport;
```

Parse with defaults so older daemon payloads still work:

```dart
protocolVersion: json['protocolVersion'] as int? ?? 1,
requestedPermissionMode: json['requestedPermissionMode'] as String? ?? '',
effectivePermissionMode: json['effectivePermissionMode'] as String? ?? '',
permissionSupport: (json['permissionSupport'] as Map<String, Object?>?) ?? const <String, Object?>{},
```

- [ ] **Step 4: Run focused Flutter model test**

Run: `cd mobile && flutter test test/protocol_compatibility_test.dart`

Expected: PASS.

## Task 6: Mobile Reducer and UI Rendering

**Files:**
- Modify: `mobile/lib/src/state/conversation_reducer.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/test/conversation_reducer_test.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write failing reducer tests for notices and multi-select questions**

Add to `mobile/test/conversation_reducer_test.dart`:

```dart
test('ConversationViewState keeps system notices non-blocking', () {
  final state = const ConversationViewState().apply(<ConversationEvent>[
    ConversationEvent.fromJson(const <String, Object?>{
      'type': 'system.notice',
      'seq': 1,
      'conversationId': 'conv_1',
      'createdAt': '2026-05-04T00:00:00.000Z',
      'text': 'Claude retry 1/3',
      'summary': 'retry'
    })
  ]);
  expect(state.status, isNot('waiting_input'));
  expect(state.messages.single.role, 'notice');
});
```

- [ ] **Step 2: Run reducer tests**

Run: `cd mobile && flutter test test/conversation_reducer_test.dart`

Expected: FAIL until `system.notice` is handled.

- [ ] **Step 3: Implement reducer notice handling**

In `ConversationViewState.apply`, add a `system.notice` case:

```dart
case 'system.notice':
  nextMessages.add(ConversationMessage(
    role: 'notice',
    text: event.text ?? event.summary ?? '',
    createdAt: event.createdAt,
  ));
  break;
```

Preserve `assistant.question` behavior and pass through suggestions for multi-select payloads.

- [ ] **Step 4: Write failing widget test for distinct blocking cards**

Add to `mobile/test/widget_test.dart` a test that constructs a `ConversationSummary` with `blockingItem.type == 'input_request'`, `multiSelect == true`, and suggestions, then expects the UI to show question text and suggestion labels instead of an approval allow/deny-only card.

Use existing widget helper patterns in `widget_test.dart` rather than adding a new app harness.

- [ ] **Step 5: Implement UI text distinctions**

In `mobile/lib/main.dart`, locate the current conversation message/card builder and ensure:

```dart
if (blocking.type == 'input_request') {
  return QuestionCard(...);
}
if (blocking.type == 'approval_request') {
  return ApprovalCard(...);
}
```

If the existing code is inline instead of separate widgets, keep the change inline and minimal: question cards show `blocking.text` and `blocking.suggestions`; approval cards show `blocking.toolName`, `blocking.summary`, and allow/deny actions.

- [ ] **Step 6: Run mobile tests**

Run: `cd mobile && flutter test test/conversation_reducer_test.dart test/protocol_compatibility_test.dart test/widget_test.dart`

Expected: PASS.

## Task 7: Final Verification

**Files:**
- Read/verify all modified files.

- [ ] **Step 1: Run daemon tests**

Run: `npm test`

Expected: PASS.

- [ ] **Step 2: Run daemon lint**

Run: `npm run lint`

Expected: PASS.

- [ ] **Step 3: Run Flutter analysis**

Run: `cd mobile && flutter analyze`

Expected: PASS.

- [ ] **Step 4: Run Flutter tests**

Run: `cd mobile && flutter test`

Expected: PASS.

- [ ] **Step 5: Check diff scope**

Run: `git diff --stat`

Expected: changes are limited to daemon Claude/conversation code, mobile conversation models/rendering/tests, and this plan/spec documentation.

## Self-Review Notes

- Spec coverage: capability detection, permission fallback, launch args, stream-json permission protocol, initialize handshake, `stream_event`, system notices, blocking timeout metadata, mobile multi-select parsing, protocol feature detection, and verification are represented in tasks.
- Placeholder scan: this plan avoids open-ended `TBD` work and gives exact files, test commands, and implementation shapes.
- Type consistency: field names match the spec: `requestedPermissionMode`, `effectivePermissionMode`, `permissionSupport`, `protocolVersion`, `blockingItem`, `multiSelect`, `createdAt`, `expiresAt`.

