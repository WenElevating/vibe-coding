# Conversation Model Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add server-confirmed model switching for existing conversations, keeping adapter switching locked and applying the new model on the next CLI start or resume.

**Architecture:** Add a daemon `PATCH /api/conversations/:id/model` endpoint that validates conversation state, adapter model capability, persistence, idle handle disposal, and diagnostic eventing before returning the updated public conversation. Extend the Flutter layered path from `ConversationSummary` through `ConversationRepository` and `DaemonClient`, then split ViewModel state into local new-conversation draft model and confirmed existing-conversation model so the composer chip never updates optimistically.

**Tech Stack:** Node.js CommonJS daemon, current in-memory and SQLite-backed conversation store, `scripts/run-tests.js`, Flutter/Dart layered mobile app, `http` package, ViewModel-based workbench UI, Flutter widget and unit tests.

---

## File Structure

- Modify: `daemon/src/conversation-protocol.js` - add `conversation.model_changed` event type and `normalizeConversationModelUpdate()`.
- Modify: `daemon/src/conversation-manager.js` - add `updateModel()`, lock handling, model capability validation, idle handle disposal, persistence compensation, event append best-effort handling, and `sendMessage()` guard.
- Modify: `daemon/src/server.js` - route `PATCH /api/conversations/:id/model` to `ConversationManager.updateModel()`.
- Modify: `scripts/run-tests.js` - daemon tests for protocol normalization, API happy path, validation, failure compensation, and concurrency.
- Modify: `mobile/lib/src/data/models/conversation_models.dart` - add nullable `ConversationSummary.model`.
- Modify: `mobile/lib/src/data/services/conversation_service.dart` - add `updateConversationModel()`.
- Modify: `mobile/lib/src/domain/repositories/conversation_repository.dart` - add `updateConversationModel()`.
- Modify: `mobile/lib/src/data/repositories/daemon_conversation_repository.dart` - forward model updates to `DaemonClient`.
- Modify: `mobile/lib/src/services/daemon_client.dart` - add `updateConversationModel()` and a private `_patch()` helper with the same auth-refresh behavior as `_post()`.
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart` - split draft/confirmed model state and implement server-confirmed existing-conversation updates.
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` - wire async model selection, pending/error picker state, active-state locking, and default-model display.
- Modify: `mobile/lib/src/ui/features/workbench/coding_composer.dart` - no API change expected beyond current `modelLocked`; use pending/error state from page only.
- Modify: `mobile/lib/l10n/app_en.arb` and `mobile/lib/l10n/app_zh.arb` - add model update status/error strings.
- Modify: `mobile/test/protocol_compatibility_test.dart` - coverage for `ConversationSummary.model`.
- Modify: `mobile/test/adapter_model_test.dart` - ViewModel draft/confirmed/update/error tests.
- Modify: `mobile/test/widget_test.dart` - picker pending/error/default display tests.
- Modify test fakes in `mobile/test/main_route_overlay_test.dart` and `mobile/test/widget_test.dart` only when compiler errors show they must implement the new repository method.

## Verification Rules

- Daemon:
  - `npm test`
  - `npm run lint`
- Flutter/Dart from `mobile/`, with mainland China mirrors:
  - PowerShell:
    - `$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; dart run tool/check_architecture_imports.dart`
    - `$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/adapter_model_test.dart test/widget_test.dart test/protocol_compatibility_test.dart -r expanded`
  - POSIX shells:
    - `PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn dart run tool/check_architecture_imports.dart`
    - `PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn flutter test test/adapter_model_test.dart test/widget_test.dart test/protocol_compatibility_test.dart -r expanded`
- If the first Flutter/Dart test/analyze/check command times out, stop running Flutter/Dart commands automatically and report the exact command for manual execution.

---

### Task 1: Daemon Protocol And Route

**Files:**
- Modify: `daemon/src/conversation-protocol.js`
- Modify: `daemon/src/server.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing protocol tests**

In `scripts/run-tests.js`, extend the conversation protocol import near the top:

```js
const {
  conversationStatuses,
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
```

Add these assertions inside the existing `conversation protocol validates statuses and blocking payloads` test, directly after the current model create assertions:

```js
assert.deepEqual(normalizeConversationModelUpdate({ model: ' gpt-5.5 ' }), { model: 'gpt-5.5' });
assert.deepEqual(normalizeConversationModelUpdate({ model: '   ' }), { model: null });
assert.deepEqual(normalizeConversationModelUpdate({ model: null }), { model: null });
assert.throws(() => normalizeConversationModelUpdate(null), /payload must be an object/);
assert.throws(() => normalizeConversationModelUpdate({ model: 42 }), /model must be a string or null/);
```

- [ ] **Step 2: Run the daemon test and confirm it fails**

Run:

```sh
npm test
```

Expected: FAIL with `normalizeConversationModelUpdate is not a function`.

- [ ] **Step 3: Implement protocol helper and event type**

In `daemon/src/conversation-protocol.js`, add `MODEL_CHANGED` to `conversationEventTypes`:

```js
MODEL_CHANGED: 'conversation.model_changed',
```

Add the helper after `normalizeConversationCreate()`:

```js
function normalizeConversationModelUpdate(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw badRequest('payload must be an object');
  }
  if (payload.model == null) return { model: null };
  if (typeof payload.model !== 'string') {
    throw badRequest('model must be a string or null');
  }
  const model = payload.model.trim();
  return { model: model || null };
}
```

Export it from `module.exports`:

```js
normalizeConversationModelUpdate,
```

- [ ] **Step 4: Add the HTTP route**

In `daemon/src/server.js`, insert this route between `POST /api/conversations` and conversation events:

```js
const conversationModel = url.pathname.match(/^\/api\/conversations\/([^/]+)\/model$/);
if (method === 'PATCH' && conversationModel) {
  return json(res, 200, {
    conversation: await conversations.updateModel(
      conversationModel[1],
      await readJson(req),
      device
    )
  });
}
```

- [ ] **Step 5: Run the daemon test and confirm the protocol assertions pass**

Run:

```sh
npm test
```

Expected: protocol helper assertions pass. Later daemon update tests are not present in this task.

- [ ] **Step 6: Commit protocol and route**

```sh
git add daemon/src/conversation-protocol.js daemon/src/server.js scripts/run-tests.js
git commit -m "Add conversation model update route"
```

---

### Task 2: Daemon Happy Path And Validation

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Write failing happy-path API tests**

In `scripts/run-tests.js`, near the existing `HTTP conversation API exposes model metadata and passes selected model into adapter startup` test, add:

```js
test('PATCH conversation model updates public model and records diagnostic event', async () => {
  const app = createTestApp({ synthetic: true });
  const port = await listen(app.server);
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code');
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'test'
    });
    const headers = { authorization: `Bearer ${paired.body.token}` };
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId: 'default',
      adapter: 'codex',
      model: 'gpt-5'
    }, headers);

    const updated = await request(port, 'PATCH', `/api/conversations/${created.body.conversation.id}/model`, {
      model: 'gpt-5.5'
    }, headers);

    assert.equal(updated.status, 200);
    assert.equal(updated.body.conversation.model, 'gpt-5.5');
    const listed = await request(port, 'GET', '/api/conversations', null, headers);
    assert.equal(listed.body.conversations.find((item) => item.id === created.body.conversation.id).model, 'gpt-5.5');
    const events = await request(port, 'GET', `/api/conversations/${created.body.conversation.id}/events?afterSeq=0`, null, headers);
    const modelEvent = events.body.events.find((event) => event.type === conversationEventTypes.MODEL_CHANGED);
    assert.equal(modelEvent.previousModel, 'gpt-5');
    assert.equal(modelEvent.model, 'gpt-5.5');
  } finally {
    await closeServer(app.server);
  }
});
```

- [ ] **Step 2: Write failing validation tests**

Add:

```js
test('PATCH conversation model validates adapter capability and model list', async () => {
  const { manager, device } = createConversationManagerForTest({
    adapters: new Map([
      ['codex', {
        capabilities: {},
        async detectCapabilities() {
          return { available: true };
        },
        getModelCapability() {
          return {
            canSelectModel: true,
            selectedModel: 'gpt-5',
            models: [{ id: 'gpt-5', label: 'GPT-5', source: 'codex_config', selected: true }]
          };
        },
        async startConversation() {
          throw new Error('not needed');
        }
      }],
      ['claude', {
        capabilities: {},
        async detectCapabilities() {
          return { available: true };
        },
        getModelCapability() {
          return { canSelectModel: false, selectedModel: null, models: [] };
        },
        async startConversation() {
          throw new Error('not needed');
        }
      }]
    ])
  });
  const codex = manager.createConversation({ workspaceId: 'default', adapter: 'codex' }, device);
  const claude = manager.createConversation({ workspaceId: 'default', adapter: 'claude' }, device);

  await assert.rejects(
    () => manager.updateModel(codex.id, { model: 'unknown-model' }, device),
    (error) => error.status === 422 && /not available/.test(error.message)
  );
  await assert.rejects(
    () => manager.updateModel(claude.id, { model: 'claude-opus' }, device),
    (error) => error.status === 422 && /does not support model selection/.test(error.message)
  );
  const defaulted = await manager.updateModel(claude.id, { model: null }, device);
  assert.equal(defaulted.model, null);
});
```

- [ ] **Step 3: Run tests and confirm they fail**

Run:

```sh
npm test
```

Expected: FAIL because `ConversationManager.updateModel` is missing.

- [ ] **Step 4: Import protocol helper**

In `daemon/src/conversation-manager.js`, extend the destructuring import:

```js
normalizeConversationModelUpdate
```

- [ ] **Step 5: Add update helper errors**

Near `conflict()` and `notFound()`, add:

```js
function unprocessable(message) {
  const error = new Error(message);
  error.status = 422;
  error.code = 'CONVERSATION_MODEL_UNSUPPORTED';
  return error;
}
```

- [ ] **Step 6: Add capability helpers**

Above `publicConversation()`, add:

```js
function activeStateBlocksModelUpdate(conversation) {
  return [
    conversationStatuses.RUNNING,
    conversationStatuses.WAITING_INPUT,
    conversationStatuses.WAITING_APPROVAL
  ].includes(conversation.status) || Boolean(conversation.sendLock);
}

async function modelCapabilityFor(adapter) {
  if (typeof adapter.detectCapabilities === 'function') {
    await adapter.detectCapabilities();
  }
  if (typeof adapter.getModelCapability !== 'function') {
    return { canSelectModel: false, selectedModel: null, models: [] };
  }
  const capability = await adapter.getModelCapability();
  return {
    canSelectModel: capability?.canSelectModel === true,
    selectedModel: typeof capability?.selectedModel === 'string' ? capability.selectedModel : null,
    models: Array.isArray(capability?.models) ? capability.models : []
  };
}

function assertRequestedModelAllowed(requestedModel, capability) {
  if (requestedModel == null) return;
  if (capability.canSelectModel !== true) {
    throw unprocessable('adapter does not support model selection');
  }
  if (capability.models.length === 0) {
    throw unprocessable('adapter model capability has no selectable models');
  }
  if (!capability.models.some((model) => model && model.id === requestedModel)) {
    throw unprocessable(`model is not available for this adapter: ${requestedModel}`);
  }
}
```

- [ ] **Step 7: Implement `updateModel()` happy path**

Inside `ConversationManager`, after `getConversation()`, add:

```js
async updateModel(conversationId, payload, device) {
  const conversation = this.requireConversation(conversationId, device);
  const input = normalizeConversationModelUpdate(payload);
  if (activeStateBlocksModelUpdate(conversation)) {
    throw conflict('conversation is active; wait for the current turn before changing model');
  }
  if (conversation.modelUpdateLock) throw conflict('model update already in flight');

  conversation.modelUpdateLock = true;
  try {
    if (activeStateBlocksModelUpdate(conversation)) {
      throw conflict('conversation is active; wait for the current turn before changing model');
    }
    const adapter = this.getAdapter(conversation.adapter);
    const capability = await modelCapabilityFor(adapter);
    assertRequestedModelAllowed(input.model, capability);
    if ((conversation.model || null) === input.model) return publicConversation(conversation);

    const previousModel = conversation.model || null;
    conversation.model = input.model;
    this.touch(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.MODEL_CHANGED, {
      previousModel,
      model: input.model
    });
    return publicConversation(conversation);
  } finally {
    conversation.modelUpdateLock = false;
  }
}
```

This task intentionally writes the simple version. Task 3 adds handle disposal and failure compensation.

- [ ] **Step 8: Add send guard**

In `sendMessage()`, after waiting-state checks and before `sendLock`, add:

```js
if (conversation.modelUpdateLock) throw conflict('model update already in flight');
```

- [ ] **Step 9: Run daemon tests**

Run:

```sh
npm test
```

Expected: new happy-path and validation tests pass. Compensation tests are added in Task 3.

- [ ] **Step 10: Commit daemon happy path**

```sh
git add daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Implement conversation model update happy path"
```

---

### Task 3: Daemon Failure Compensation And Concurrency

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add tests for handle disposal and persistence failure**

Add daemon tests:

```js
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
```

- [ ] **Step 2: Add tests for event append failure and locks**

Add:

```js
test('PATCH conversation model event append failure keeps persisted model', async () => {
  const { manager, device } = createConversationManagerForTest();
  const conversation = manager.createConversation({ workspaceId: 'default', adapter: 'codex', model: 'gpt-5' }, device);
  const originalAppend = manager.eventStore.append.bind(manager.eventStore);
  manager.eventStore.append = (conversationId, type, payload) => {
    if (type === conversationEventTypes.MODEL_CHANGED) throw new Error('event failed');
    return originalAppend(conversationId, type, payload);
  };

  const updated = await manager.updateModel(conversation.id, { model: 'gpt-5.5' }, device);

  assert.equal(updated.model, 'gpt-5.5');
  assert.equal(manager.requireConversation(conversation.id, device).model, 'gpt-5.5');
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
```

- [ ] **Step 3: Run tests and confirm failures**

Run:

```sh
npm test
```

Expected: FAIL in the new disposal, persistence, event failure, or lock tests.

- [ ] **Step 4: Add handle disposal helper**

In `daemon/src/conversation-manager.js`, add:

```js
async function disposeIdleHandle(conversation) {
  if (!conversation.handle) return;
  const handle = conversation.handle;
  try {
    if (typeof handle.dispose === 'function') await handle.dispose();
  } finally {
    conversation.handle = null;
  }
}
```

- [ ] **Step 5: Replace the middle of `updateModel()` with compensation logic**

Replace the body after unchanged-model check with:

```js
const previousModel = conversation.model || null;
try {
  try {
    await disposeIdleHandle(conversation);
  } catch (error) {
    this.auditLog.record('conversation.model_handle_dispose_error', {
      conversationId: conversation.id,
      error: error.message
    });
    throw error;
  }

  conversation.model = input.model;
  this.touch(conversation);
} catch (error) {
  conversation.model = previousModel;
  throw error;
}

try {
  this.eventStore.append(conversation.id, conversationEventTypes.MODEL_CHANGED, {
    previousModel,
    model: input.model
  });
} catch (error) {
  this.auditLog.record('conversation.model_change_event_error', {
    conversationId: conversation.id,
    error: error.message
  });
}

return publicConversation(conversation);
```

- [ ] **Step 6: Confirm disposal failure preserves session id**

The helper above must not mutate `conversation.cliSessionId`. Inspect the function after editing and confirm the only handle assignment is:

```js
conversation.handle = null;
```

- [ ] **Step 7: Run daemon tests**

Run:

```sh
npm test
```

Expected: all daemon tests pass.

- [ ] **Step 8: Commit daemon compensation**

```sh
git add daemon/src/conversation-manager.js scripts/run-tests.js
git commit -m "Harden conversation model update consistency"
```

---

### Task 4: Mobile Protocol And Repository Plumbing

**Files:**
- Modify: `mobile/lib/src/data/models/conversation_models.dart`
- Modify: `mobile/lib/src/data/services/conversation_service.dart`
- Modify: `mobile/lib/src/domain/repositories/conversation_repository.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_conversation_repository.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Test: `mobile/test/protocol_compatibility_test.dart`
- Test: `mobile/test/adapter_model_test.dart`
- Test fakes: `mobile/test/main_route_overlay_test.dart`, `mobile/test/widget_test.dart`

- [ ] **Step 1: Add failing model parse test**

In `mobile/test/protocol_compatibility_test.dart`, add `'model': 'gpt-5.5'` to the first conversation payload and assert:

```dart
expect(summary.model, 'gpt-5.5');
```

Add this to the legacy defaults test:

```dart
expect(summary.model, isNull);
```

- [ ] **Step 2: Add failing repository fake method test**

In `mobile/test/adapter_model_test.dart`, add a test to `_FakeConversationRepository` usage:

```dart
test('repository updateConversationModel records selected model', () async {
  final repository = _FakeConversationRepository();

  final updated = await repository.updateConversationModel('conv_1', 'gpt-5-mini');

  expect(updated.model, 'gpt-5-mini');
  expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);
});
```

- [ ] **Step 3: Run focused Flutter test and confirm failure**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/protocol_compatibility_test.dart test/adapter_model_test.dart -r expanded
```

Expected: FAIL because `ConversationSummary.model` and repository method are missing.

- [ ] **Step 4: Add `ConversationSummary.model`**

In `mobile/lib/src/data/models/conversation_models.dart`, add constructor parameter:

```dart
this.model,
```

Add field:

```dart
final String? model;
```

Add parser argument:

```dart
model: _optionalText(json['model']),
```

Add helper near the bottom of the file:

```dart
String? _optionalText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
```

- [ ] **Step 5: Extend conversation service and repository contracts**

Add this method to both `ConversationService` and `ConversationRepository`:

```dart
Future<ConversationSummary> updateConversationModel(
  String conversationId,
  String? model,
);
```

- [ ] **Step 6: Implement repository forwarding**

In `DaemonConversationRepository`, add:

```dart
@override
Future<ConversationSummary> updateConversationModel(
  String conversationId,
  String? model,
) =>
    _client.updateConversationModel(conversationId, model);
```

- [ ] **Step 7: Implement `DaemonClient.updateConversationModel()`**

In `DaemonClient`, add near the conversation methods:

```dart
@override
Future<ConversationSummary> updateConversationModel(
  String conversationId,
  String? model,
) async {
  final trimmedModel = model?.trim();
  final response = await _patch(
    '/api/conversations/$conversationId/model',
    <String, Object?>{
      'model': trimmedModel == null || trimmedModel.isEmpty ? null : trimmedModel,
    },
  );
  return ConversationSummary.fromJson(
      response['conversation'] as Map<String, Object?>);
}
```

Add `_patch()` next to `_post()`:

```dart
Future<Map<String, Object?>> _patch(String path, Map<String, Object?> body,
    {bool authorize = true}) async {
  final response = await _request(() => _httpClient.patch(
        baseUri.resolve(path),
        headers: _headers(authorize: authorize),
        body: jsonEncode(body),
      ));
  if (authorize && _isAuthRequired(response)) {
    await _refreshAfterAuthRequired();
    final retry = await _request(() => _httpClient.patch(
          baseUri.resolve(path),
          headers: _headers(authorize: authorize),
          body: jsonEncode(body),
        ));
    return _decode(retry);
  }
  return _decode(response);
}
```

- [ ] **Step 8: Update test fakes**

For each class implementing `ConversationRepository`, add:

```dart
@override
Future<ConversationSummary> updateConversationModel(
  String conversationId,
  String? model,
) async =>
    _conversation(model: model);
```

Where the fake uses a call log, record:

```dart
calls.add('update-model:$conversationId:$model');
```

- [ ] **Step 9: Run focused Flutter tests**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/protocol_compatibility_test.dart test/adapter_model_test.dart -r expanded
```

Expected: both files pass.

- [ ] **Step 10: Format and commit**

```sh
dart format lib/src/data/models/conversation_models.dart lib/src/data/services/conversation_service.dart lib/src/domain/repositories/conversation_repository.dart lib/src/data/repositories/daemon_conversation_repository.dart lib/src/services/daemon_client.dart test/protocol_compatibility_test.dart test/adapter_model_test.dart test/main_route_overlay_test.dart test/widget_test.dart
git add mobile/lib/src/data/models/conversation_models.dart mobile/lib/src/data/services/conversation_service.dart mobile/lib/src/domain/repositories/conversation_repository.dart mobile/lib/src/data/repositories/daemon_conversation_repository.dart mobile/lib/src/services/daemon_client.dart mobile/test/protocol_compatibility_test.dart mobile/test/adapter_model_test.dart mobile/test/main_route_overlay_test.dart mobile/test/widget_test.dart
git commit -m "Add mobile conversation model update transport"
```

---

### Task 5: ViewModel Server-Confirmed Model State

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Test: `mobile/test/adapter_model_test.dart`

- [ ] **Step 1: Write failing ViewModel tests for draft and confirmed state**

In `mobile/test/adapter_model_test.dart`, replace the active-conversation direct model mutation test with:

```dart
test('existing conversation model update waits for repository success', () async {
  final repository = _FakeConversationRepository();
  final viewModel = WorkbenchViewModel(
    initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
    conversationRepository: repository,
  );
  viewModel.updateActiveConversation(_conversation(adapter: 'codex', model: 'gpt-5-codex'));

  final future = viewModel.selectModel('gpt-5-mini');

  expect(viewModel.selectedModel, 'gpt-5-codex');
  expect(viewModel.modelUpdating, true);
  await future;

  expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);
  expect(viewModel.selectedModel, 'gpt-5-mini');
  expect(viewModel.modelUpdating, false);
  expect(viewModel.modelUpdateError, isNull);
});
```

Add:

```dart
test('existing conversation model update failure keeps confirmed model', () async {
  final repository = _FakeConversationRepository()
    ..updateError = const DaemonClientException(409, <String, Object?>{
      'error': {'code': 'CONVERSATION_CONFLICT', 'message': 'busy'}
    });
  final viewModel = WorkbenchViewModel(
    initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
    conversationRepository: repository,
  );
  viewModel.updateActiveConversation(_conversation(adapter: 'codex', model: 'gpt-5-codex'));

  final changed = await viewModel.selectModel('gpt-5-mini');

  expect(changed, false);
  expect(viewModel.selectedModel, 'gpt-5-codex');
  expect(viewModel.modelUpdating, false);
  expect(viewModel.modelUpdateError, isNotNull);
});
```

Add:

```dart
test('old daemon model endpoint disables existing conversation updates', () async {
  final repository = _FakeConversationRepository()
    ..updateError = const DaemonClientException(404, <String, Object?>{
      'error': {'code': 'ERROR', 'message': 'not found'}
    });
  final viewModel = WorkbenchViewModel(
    initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
    conversationRepository: repository,
  );
  viewModel.updateActiveConversation(_conversation(adapter: 'codex', model: 'gpt-5-codex'));

  await viewModel.selectModel('gpt-5-mini');

  expect(viewModel.conversationModelUpdatesUnsupported, true);
  expect(viewModel.selectedModel, 'gpt-5-codex');
});
```

- [ ] **Step 2: Run focused ViewModel tests and confirm failure**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/adapter_model_test.dart -r expanded
```

Expected: FAIL because split state and async selection are missing.

- [ ] **Step 3: Add ViewModel fields and getters**

In `WorkbenchViewModel`, replace `_selectedModel` with:

```dart
String? _draftModel;
String? _confirmedConversationModel;
bool _modelUpdating = false;
String? _modelUpdateError;
bool _conversationModelUpdatesUnsupported = false;
```

Initialize `_draftModel` in the constructor:

```dart
_draftModel = _initialSelectedModel(initialData.adapters);
```

Add getters:

```dart
String? get draftModel => _draftModel;
String? get confirmedConversationModel => _confirmedConversationModel;
String? get selectedModel =>
    _activeConversationId == null ? _draftModel : _confirmedConversationModel;
bool get modelUpdating => _modelUpdating;
String? get modelUpdateError => _modelUpdateError;
bool get conversationModelUpdatesUnsupported =>
    _conversationModelUpdatesUnsupported;
```

- [ ] **Step 4: Update local draft paths**

Replace `_selectedModel` references in new-conversation logic with `_draftModel`:

```dart
_draftModel = _preferredModelFor(selectedAdapterStatus);
```

```dart
final normalized = _normalizeModel(requested) ?? _draftModel;
```

In `_reconcileSelectedModel()`, compare and assign `_draftModel`.

- [ ] **Step 5: Set confirmed model when opening an existing conversation**

Update `_selectActiveConversationAdapter()`:

```dart
void _selectActiveConversationAdapter(ConversationSummary? conversation) {
  final adapter = conversation?.adapter.trim();
  if (adapter == null || adapter.isEmpty) return;
  _selectedAdapter = adapter;
  _confirmedConversationModel = conversation?.model;
  _modelUpdateError = null;
}
```

Clear confirmed state in `clearActiveConversation()` and `resetConversationDisplay()`:

```dart
_confirmedConversationModel = null;
_modelUpdateError = null;
```

- [ ] **Step 6: Replace model selection method**

Replace `setSelectedModel()` with:

```dart
Future<bool> selectModel(String? model) async {
  if (_sending || _modelUpdating) return false;
  final normalized = _normalizeModel(model);
  final status = selectedAdapterStatus;
  if (normalized != null &&
      (status?.canSelectModel != true ||
          !_modelStillAvailable(normalized, status))) {
    return false;
  }

  if (_activeConversationId == null) {
    final changed = _draftModel != normalized || _modelNotice != null;
    _draftModel = normalized;
    _modelNotice = null;
    if (changed) notifyListeners();
    return true;
  }

  return _updateExistingConversationModel(normalized);
}
```

Add:

```dart
Future<bool> _updateExistingConversationModel(String? model) async {
  final conversationId = _activeConversationId;
  if (conversationId == null || _conversationModelUpdatesUnsupported) {
    return false;
  }
  final repository = _requireConversationRepository();
  _modelUpdating = true;
  _modelUpdateError = null;
  notifyListeners();
  try {
    final conversation =
        await repository.updateConversationModel(conversationId, model);
    _activeConversation = conversation;
    _confirmedConversationModel = conversation.model;
    _modelUpdating = false;
    _modelUpdateError = null;
    notifyListeners();
    return true;
  } on DaemonClientException catch (error) {
    _handleModelUpdateException(error);
    notifyListeners();
    return false;
  } catch (error) {
    _modelUpdating = false;
    _modelUpdateError = error.toString();
    notifyListeners();
    return false;
  }
}
```

Add the error helper:

```dart
void _handleModelUpdateException(DaemonClientException error) {
  _modelUpdating = false;
  final code = _daemonErrorCode(error);
  if (error.statusCode == 404 && code != 'NOT_FOUND') {
    _conversationModelUpdatesUnsupported = true;
    _modelUpdateError = 'existing conversation model updates require a newer daemon';
    return;
  }
  if (error.statusCode == 405) {
    _conversationModelUpdatesUnsupported = true;
    _modelUpdateError = 'existing conversation model updates require a newer daemon';
    return;
  }
  _modelUpdateError = _daemonErrorMessage(error) ?? error.toString();
}
```

Add helpers near other private functions:

```dart
String? _daemonErrorCode(DaemonClientException error) {
  final bodyError = error.body['error'];
  if (bodyError is Map<String, Object?>) {
    final code = bodyError['code'];
    return code is String ? code : null;
  }
  return bodyError is String ? bodyError : null;
}

String? _daemonErrorMessage(DaemonClientException error) {
  final bodyError = error.body['error'];
  if (bodyError is Map<String, Object?>) {
    final message = bodyError['message'];
    return message is String && message.trim().isNotEmpty
        ? message.trim()
        : null;
  }
  final message = error.body['message'];
  return message is String && message.trim().isNotEmpty
      ? message.trim()
      : null;
}
```

- [ ] **Step 7: Update fake repository**

In `_FakeConversationRepository`, add:

```dart
DaemonClientException? updateError;
```

Update `_conversation()` helper signature:

```dart
ConversationSummary _conversation({String adapter = 'codex', String? model}) =>
    ConversationSummary(
      id: 'conv_1',
      workspaceId: _workspace.id,
      adapter: adapter,
      model: model,
      status: 'idle',
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-18T00:00:00.000Z',
      updatedAt: '2026-05-18T00:00:01.000Z',
    );
```

Implement fake update:

```dart
@override
Future<ConversationSummary> updateConversationModel(
  String conversationId,
  String? model,
) async {
  if (updateError != null) throw updateError!;
  calls.add('update-model:$conversationId:$model');
  return _conversation(model: model);
}
```

- [ ] **Step 8: Run focused ViewModel tests**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/adapter_model_test.dart -r expanded
```

Expected: all tests in `adapter_model_test.dart` pass.

- [ ] **Step 9: Format and commit**

```sh
dart format lib/src/ui/features/workbench/view_models/workbench_view_model.dart test/adapter_model_test.dart
git add mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart mobile/test/adapter_model_test.dart
git commit -m "Confirm existing conversation model updates in ViewModel"
```

---

### Task 6: Mobile Picker UI Pending And Error States

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add l10n strings**

Add to `app_en.arb`:

```json
"modelPickerUpdating": "Updating model...",
"modelPickerUnsupportedDaemon": "Update the desktop daemon to change models in existing conversations.",
"modelPickerBusy": "Wait for the current turn to finish before changing model.",
"modelPickerUpdateFailed": "Model update failed.",
"modelPickerCliDefaultDetail": "Uses the CLI configured default."
```

Add to `app_zh.arb`:

```json
"modelPickerUpdating": "正在更新模型...",
"modelPickerUnsupportedDaemon": "请更新桌面端 daemon 后再修改已有对话的模型。",
"modelPickerBusy": "当前轮次结束后才能切换模型。",
"modelPickerUpdateFailed": "模型更新失败。",
"modelPickerCliDefaultDetail": "使用 CLI 当前配置的默认模型。"
```

- [ ] **Step 2: Generate local localization files**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter gen-l10n
```

Expected: generated localization files under `mobile/lib/l10n/` refresh locally. They are ignored by Git in this repo; stage only `.arb` files.

- [ ] **Step 3: Write failing widget tests**

In `mobile/test/widget_test.dart`, add:

```dart
testWidgets('model picker disables rows and shows pending update',
    (WidgetTester tester) async {
  String? selected;
  await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: ModelPickerSheet(
              models: const <AdapterModelOption>[
                AdapterModelOption(
                    id: 'gpt-5-codex',
                    label: 'GPT-5 Codex',
                    source: 'codex_config',
                    selected: true),
                AdapterModelOption(
                    id: 'gpt-5-mini',
                    label: 'GPT-5 Mini',
                    source: 'codex_catalog',
                    selected: false),
              ],
              selected: 'gpt-5-codex',
              updating: true,
              pendingModel: 'gpt-5-mini',
              errorText: null,
              onSelected: (model) => selected = model))));

  expect(find.text('Updating model...'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('model-option-gpt-5-codex')));
  expect(selected, isNull);
});
```

Add:

```dart
testWidgets('model picker shows model update error',
    (WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: ModelPickerSheet(
              models: const <AdapterModelOption>[],
              selected: null,
              updating: false,
              pendingModel: null,
              errorText: 'Update the desktop daemon to change models in existing conversations.',
              onSelected: (_) {}))));

  expect(find.text('Update the desktop daemon to change models in existing conversations.'), findsOneWidget);
});
```

- [ ] **Step 4: Run widget tests and confirm failure**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/widget_test.dart -r expanded
```

Expected: FAIL because `ModelPickerSheet` lacks pending/error fields.

- [ ] **Step 5: Extend `ModelPickerSheet` constructor**

Add fields:

```dart
this.updating = false,
this.pendingModel,
this.errorText,
```

Add properties:

```dart
final bool updating;
final String? pendingModel;
final String? errorText;
```

- [ ] **Step 6: Render pending and error UI**

Inside `ModelPickerSheet.build()`, after the title row and before the list, add:

```dart
if (updating) ...[
  const SizedBox(height: 8),
  Row(children: [
    const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    const SizedBox(width: 8),
    Text(l10n.modelPickerUpdating,
        style: const TextStyle(color: theme.muted, fontSize: 12)),
  ]),
],
if (errorText != null && errorText!.trim().isNotEmpty) ...[
  const SizedBox(height: 8),
  Text(errorText!,
      style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 12)),
],
```

- [ ] **Step 7: Disable rows during update**

Change row creation calls to pass disabled tap callbacks:

```dart
onTap: updating ? null : () => onSelected(null),
```

and:

```dart
onTap: updating ? null : () => onSelected(model.id),
```

Change `_ModelChoiceRow.onTap` type:

```dart
final VoidCallback? onTap;
```

Keep the `InkWell` assignment:

```dart
onTap: onTap,
```

- [ ] **Step 8: Wire page async selection**

In `_showModelPicker()`, pass state:

```dart
updating: _workbenchViewModel.modelUpdating,
pendingModel: null,
errorText: _modelUpdateErrorLabel(l10n),
```

Replace `onSelected` with:

```dart
onSelected: (model) =>
    unawaited(_selectModelFromPicker(context, model)),
```

Add page method:

```dart
Future<void> _selectModelFromPicker(
  BuildContext sheetContext,
  String? model,
) async {
  final changed = await _workbenchViewModel.selectModel(model);
  if (!mounted) return;
  if (changed && sheetContext.mounted) {
    Navigator.of(sheetContext).pop();
  }
}
```

Add label helper:

```dart
String? _modelUpdateErrorLabel(AppLocalizations l10n) {
  if (_workbenchViewModel.conversationModelUpdatesUnsupported) {
    return l10n.modelPickerUnsupportedDaemon;
  }
  final error = _workbenchViewModel.modelUpdateError;
  if (error == null || error.trim().isEmpty) return null;
  if (error.contains('current turn') || error.contains('active')) {
    return l10n.modelPickerBusy;
  }
  return error;
}
```

- [ ] **Step 9: Update model lock conditions**

Change `_isModelSelectionLocked`:

```dart
bool get _isModelSelectionLocked {
  if (_sending || _workbenchViewModel.modelUpdating) return true;
  if (_activeConversationId != null &&
      _workbenchViewModel.conversationModelUpdatesUnsupported) return true;
  if (_activeConversationId == null) return false;
  return isActiveConversationStatus(
      _workbenchViewModel.effectiveConversationStatus);
}
```

- [ ] **Step 10: Show default model chip label**

Update `_selectedModelLabel()` so null model returns localized default text when the selected adapter can select models:

```dart
if (selected == null || selected.isEmpty) {
  return AppLocalizations.of(context).modelPickerDefaultModel;
}
```

- [ ] **Step 11: Run widget tests**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/widget_test.dart -r expanded
```

Expected: widget tests pass.

- [ ] **Step 12: Format and commit**

```sh
dart format lib/src/ui/features/workbench/coding_workbench_page.dart test/widget_test.dart
git add mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb mobile/test/widget_test.dart
git commit -m "Show confirmed conversation model update state"
```

---

### Task 7: Final Verification And Cleanup

**Files:**
- Review all changed files from Tasks 1-6.

- [ ] **Step 1: Run daemon verification**

Run:

```sh
npm test
npm run lint
```

Expected: both commands exit 0.

- [ ] **Step 2: Run mobile architecture check**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; dart run tool/check_architecture_imports.dart
```

Expected: exit 0.

- [ ] **Step 3: Run focused mobile tests**

Run from `mobile/`:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'; flutter test test/adapter_model_test.dart test/widget_test.dart test/protocol_compatibility_test.dart -r expanded
```

Expected: exit 0. If this is the first Flutter/Dart timeout in the implementation run, stop automatic Flutter/Dart retries and report this exact command.

- [ ] **Step 4: Check generated and ignored files**

Run:

```sh
git status --short --ignored mobile/lib/l10n
git status --short --branch
```

Expected: staged or modified tracked files match the implementation. Ignored generated localization files can appear under `!!`; do not force-add them.

- [ ] **Step 5: Check whitespace and final diff**

Run:

```sh
git diff --check
git diff --stat
```

Expected: no whitespace errors. Diff stat should match the endpoint, mobile transport, ViewModel, UI, l10n, and tests.

- [ ] **Step 6: Final commit if verification changed files**

If Step 1-5 produced format or l10n tracked edits, stage the tracked files from this plan that Git reports as modified:

```sh
git add daemon/src/conversation-protocol.js daemon/src/conversation-manager.js daemon/src/server.js scripts/run-tests.js mobile/lib/src/data/models/conversation_models.dart mobile/lib/src/data/services/conversation_service.dart mobile/lib/src/domain/repositories/conversation_repository.dart mobile/lib/src/data/repositories/daemon_conversation_repository.dart mobile/lib/src/services/daemon_client.dart mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb mobile/test/protocol_compatibility_test.dart mobile/test/adapter_model_test.dart mobile/test/widget_test.dart mobile/test/main_route_overlay_test.dart
git commit -m "Finalize conversation model switching"
```

- [ ] **Step 7: Handoff summary**

Report:

```text
Implemented server-confirmed existing-conversation model switching.
Daemon verified with npm test and npm run lint.
Mobile verified with architecture check and focused Flutter tests.
Known gap: none when all verification commands exit 0. If a verification command timed out, replace this line with the exact command and timeout.
Latest commits: paste the output of `git log --oneline -7`.
```

---

## Self-Review Checklist

- Spec coverage:
  - `PATCH /api/conversations/:id/model`: Tasks 1-3.
  - Request normalization and validation: Tasks 1-2.
  - Active-state and lock behavior: Tasks 2-3.
  - Idle handle disposal and failure compensation: Task 3.
  - Diagnostic `conversation.model_changed` event: Tasks 1-3.
  - Mobile `ConversationSummary.model` and repository transport: Task 4.
  - Draft versus confirmed model state: Task 5.
  - Pending/error UI and old-daemon downgrade behavior: Tasks 5-6.
  - Verification commands and timeout handling: Task 7.
- Type consistency:
  - Daemon method name: `updateModel(conversationId, payload, device)`.
  - Mobile repository method: `updateConversationModel(String conversationId, String? model)`.
  - ViewModel method: `Future<bool> selectModel(String? model)`.
  - State getters: `draftModel`, `confirmedConversationModel`, `modelUpdating`, `modelUpdateError`, `conversationModelUpdatesUnsupported`.
- Risk notes:
  - The standalone `mobile/lib/src/services/conversation_client.dart` is not constructed anywhere in `mobile/lib` or `mobile/test`; keep it unchanged unless compiler usage appears during implementation.
  - Generated localization files are ignored in this repo; run `flutter gen-l10n` for local compilation but stage only tracked `.arb` files.
