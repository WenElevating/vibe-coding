# Codex CLI Conversation Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real Codex CLI support to the daemon conversation workflow while leaving `/api/runs` as residual logic.

**Architecture:** Create a dedicated `CodexConversationAdapter` that starts one `codex exec --json` process per user message and preserves continuity by storing `thread.started.thread_id` as `cliSessionId`. The adapter will normalize Codex JSONL into the existing conversation event protocol, enforce bounded output, keep process cwd fixed to the authorized workspace, and cancel process trees.

**Tech Stack:** Node.js CommonJS daemon, `child_process.spawn`, existing `ConversationManager`, existing `conversation-protocol`, existing `cli-resolver`, `scripts/run-tests.js`, Flutter mobile reducer only if needed.

---

## File Structure

- Create `daemon/src/codex-conversation-adapter.js`: Codex CLI detection, argv builders, JSONL parsing, event mapping, bounded output, process-tree cancellation, and conversation handle.
- Modify `daemon/src/main.js`: import `CodexConversationAdapter`, pass `codexCommand` into conversation adapter creation, and replace the `codex` placeholder.
- Modify `scripts/run-tests.js`: add daemon unit and integration tests for Codex conversation behavior.
- Modify mobile files only if tests show the current reducer cannot render normalized Codex events. The planned daemon event types already match existing protocol names.

## Task 1: Add Failing Codex Conversation Adapter Tests

**Files:**
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Import the adapter under test**

Add near the existing adapter imports:

```js
const {
  CodexConversationAdapter,
  buildCodexExecArgs,
  buildCodexResumeArgs,
  mapCodexEvent,
  truncateText
} = require('../daemon/src/codex-conversation-adapter');
```

- [ ] **Step 2: Add argv and cwd tests**

Add tests near the Claude conversation adapter tests:

```js
test('Codex conversation adapter starts first turn with global approval before exec and workspace cwd', async () => {
  let spawnCommand = null;
  let spawnArgs = null;
  let spawnOptions = null;
  const child = fakeCodexChild();
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
  assert.equal(spawnArgs.includes('--dangerously-bypass-approvals-and-sandbox'), false);
  assert.equal(spawnArgs[spawnArgs.length - 1], 'hello');
  assert.equal(spawnOptions.cwd, 'D:\\AiProject\\vibe-coding');
  child.emit('exit', 0, null);
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
  assert.equal(spawnCalls[0].args[5], 'thread_1');
  assert.equal(spawnCalls[0].args[6], 'second');
  spawnCalls[0].child.emit('exit', 0, null);
});
```

- [ ] **Step 3: Add JSONL mapping and bound tests**

```js
test('Codex event mapper normalizes thread, assistant, tool, declined, unknown, and failed events', () => {
  assert.deepEqual(mapCodexEvent({ type: 'thread.started', thread_id: 'thread_a' }).sessionId, 'thread_a');
  assert.equal(mapCodexEvent({ type: 'item.completed', item: { id: 'item_1', type: 'agent_message', text: 'hello' } }).type, 'assistant.message');
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
```

- [ ] **Step 4: Add ConversationManager session preservation test**

```js
test('Codex conversation persists thread id and preserves it after turn failure', async () => {
  const app = createApp({ port: 0, conversationDbPath: tempConversationDbPath(), conversationAdapters: new Map([['codex', fakeCodexConversationAdapter()]]), codexEnabled: true });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/conversations', { workspaceId: 'default', adapter: 'codex' }, token);
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
```

- [ ] **Step 5: Run focused tests to verify they fail**

Run: `npm test`

Expected: fail with `Cannot find module '../daemon/src/codex-conversation-adapter'`.

## Task 2: Implement Codex Conversation Adapter

**Files:**
- Create: `daemon/src/codex-conversation-adapter.js`

- [ ] **Step 1: Create adapter skeleton**

Implement CommonJS exports for:

```js
module.exports = {
  CodexConversationAdapter,
  CodexConversationHandle,
  buildCodexExecArgs,
  buildCodexResumeArgs,
  mapCodexEvent,
  truncateText
};
```

- [ ] **Step 2: Implement capability detection**

Detection should call resolved `codex --version`, `codex exec --help`, and `codex exec resume --help`. It must not run `codex exec` as a live smoke test.

- [ ] **Step 3: Implement argv builders**

`buildCodexExecArgs({ prompt, workspacePath, permissionMode })` must return:

```js
['--ask-for-approval', approval, 'exec', '--json', '-C', workspacePath, '--sandbox', 'workspace-write', prompt]
```

`buildCodexResumeArgs({ prompt, sessionId, permissionMode, workspacePath, resumeSupportsCd })` must return:

```js
['--ask-for-approval', approval, 'exec', 'resume', '--json', sessionId, prompt]
```

and only include `--cd workspacePath` when capability detection proves resume supports it.

- [ ] **Step 4: Implement per-message process launch**

`startConversation()` returns a handle. `sendUserMessage(text)` spawns a child with cwd set to `workspacePath`, hooks stdout/stderr/exit, and returns after launch. It must reject if a previous turn is still active.

- [ ] **Step 5: Implement JSONL parser and event mapping**

Parse across chunk boundaries, enforce `maxJsonLineBytes`, strip ANSI control sequences, map known Codex JSON events to existing `conversationEventTypes`, and surface unknown JSON as `system.notice`.

- [ ] **Step 6: Implement cancellation**

`cancel()` marks the handle as cancelling, invokes an injected `killProcessTreeFn(pid, child)`, and emits `conversation.cancelled`. Default Windows behavior should use `taskkill /PID <pid> /T /F`; fallback to `child.kill('SIGTERM')`.

- [ ] **Step 7: Run focused tests**

Run: `npm test`

Expected: new Codex adapter tests pass or expose integration gaps.

## Task 3: Wire Codex Into Conversation Adapters

**Files:**
- Modify: `daemon/src/main.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Import adapter**

Add:

```js
const { CodexConversationAdapter } = require('./codex-conversation-adapter');
```

- [ ] **Step 2: Pass codex command to conversation adapters**

Change:

```js
adapters: conversationAdapters || createConversationAdapters({ claudeCommand }),
```

to:

```js
adapters: conversationAdapters || createConversationAdapters({ claudeCommand, codexCommand }),
```

- [ ] **Step 3: Replace placeholder**

Change `createConversationAdapters()` so `codex` is:

```js
['codex', new CodexConversationAdapter({ command: codexCommand })]
```

- [ ] **Step 4: Add API integration test**

Add a test that creates a Codex conversation through `/api/conversations`, sends a message, receives `thread.started`, `assistant.message`, and `conversation.completed`, and verifies `cliSessionId`.

- [ ] **Step 5: Run tests**

Run: `npm test`

Expected: pass.

## Task 4: Verify Mobile Rendering Assumptions

**Files:**
- Modify only if required: `mobile/test/conversation_reducer_test.dart`
- Modify only if required: `mobile/lib/src/state/conversation_reducer.dart`

- [ ] **Step 1: Search current reducer event support**

Run: `rg -n "assistant.message|tool.started|tool.output|system.notice|conversation.completed|run.error" mobile/lib mobile/test`

Expected: existing reducer handles the daemon event types or tests reveal the missing case.

- [ ] **Step 2: Add reducer test only for missing behavior**

If declined Codex policy notice is not rendered, add a test event:

```dart
ConversationEvent(
  seq: 1,
  type: 'system.notice',
  payload: {'text': 'Codex CLI blocked this command under the current local policy.', 'noticeKind': 'codex_policy_blocked'},
)
```

Expected: visible system notice item, not an approval request.

- [ ] **Step 3: Run Flutter focused tests if mobile changed**

Run: `cd mobile && flutter test test/conversation_reducer_test.dart`

Expected: pass.

## Task 5: Final Verification and Commit

**Files:**
- All changed files.

- [ ] **Step 1: Run daemon verification**

Run:

```powershell
npm test
npm run lint
```

Expected: both pass.

- [ ] **Step 2: Run mobile verification if mobile changed**

Run:

```powershell
cd mobile && flutter test
cd mobile && flutter analyze
```

Expected: pass, or document environment-specific failures separately.

- [ ] **Step 3: Review git status**

Run: `git status --short`

Expected: implementation files staged separately from existing Flutter Windows generated-file noise.

- [ ] **Step 4: Commit**

Commit message:

```text
Add Codex CLI conversation adapter

Constraint: Treat /api/runs as residual and bind Codex conversation turns to authorized workspace cwd.
Rejected: Generic JSONL mapping, live diagnostics smoke tests, and mobile approval callbacks for Codex CLI policy decisions.
Tested: npm test; npm run lint
Not-tested: Flutter full suite if no mobile files changed.
```

