# Conversation CLI Selection Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reopen a conversation with its persisted CLI adapter selected, and prevent CLI switching while a conversation is active.

**Architecture:** Keep `conversations.adapter` as the single source of truth. Hydrate the workbench selector from the active conversation when it is opened, and guard adapter changes so they only apply before the first conversation send. Existing daemon persistence already survives restart, so the work is isolated to Flutter state synchronization and tests.

**Tech Stack:** Flutter `ChangeNotifier`, existing `WorkbenchViewModel`, existing conversation repository models, current Flutter test suite.

---

### Task 1: Lock adapter selection to inactive conversations

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Test: `mobile/test/workbench_view_model_test.dart` or the closest existing workbench view model test file

- [ ] **Step 1: Write the failing test**

```dart
test('reopening a conversation hydrates selectedAdapter from the conversation adapter and blocks mid-conversation changes', () {
  final vm = WorkbenchViewModel(initialData: snapshotWithAdaptersAndWorkspaces);
  vm.showConversation(sessionItemFor(adapter: 'codex', conversationId: 'c-1'));

  expect(vm.selectedAdapter, 'codex');

  vm.selectAdapter('claude');

  expect(vm.selectedAdapter, 'codex');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile; flutter test test/workbench_view_model_test.dart -r compact`
Expected: FAIL because the current view model does not hydrate `_selectedAdapter` from the opened conversation and still allows changes.

- [ ] **Step 3: Write minimal implementation**

```dart
void selectAdapter(String adapter) {
  if (_activeConversationId != null) return;
  if (_selectedAdapter == adapter) return;
  _selectedAdapter = adapter;
  notifyListeners();
}

void updateActiveConversation(ConversationSummary conversation, {String? runId, bool notify = true}) {
  _activeConversation = conversation;
  _activeConversationId = conversation.id;
  _selectedAdapter = conversation.adapter;
  // existing update logic continues here
}

void clearActiveConversation() {
  _activeConversationId = null;
  _activeConversation = null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile; flutter test test/workbench_view_model_test.dart -r compact`
Expected: PASS.

### Task 2: Cover restart-safe adapter hydration and send path

**Files:**
- Modify: `mobile/test/workbench_view_model_test.dart` or the closest existing workbench/session test file
- Modify: `daemon/test/app-sqlite-store.test.js` only if there is already persistence coverage in that file

- [ ] **Step 1: Write the failing test**

```dart
test('opening an existing conversation keeps its stored adapter after snapshot refresh', () {
  final vm = WorkbenchViewModel(initialData: initialSnapshot);
  vm.showConversation(sessionItemFor(adapter: 'claude', conversationId: 'c-2'));

  vm.refreshSnapshot(snapshotWithPreferredAdapter('codex'));

  expect(vm.selectedAdapter, 'claude');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile; flutter test test/workbench_view_model_test.dart -r compact`
Expected: FAIL because adapter refresh can still overwrite the selection if the implementation is incomplete.

- [ ] **Step 3: Write minimal implementation**

```dart
void updateAdapters(List<AdapterStatus> adapters) {
  final activeConversation = _activeConversation;
  if (activeConversation != null) {
    _selectedAdapter = activeConversation.adapter;
    return;
  }

  final stillAvailable = _selectedAdapter != null &&
      adapters.any((a) => a.adapter == _selectedAdapter && a.available && _isSelectableAdapter(a));
  if (!stillAvailable) {
    _selectedAdapter = _computePreferredAdapter(adapters);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile; flutter test test/workbench_view_model_test.dart -r compact`
Expected: PASS.

### Task 3: Verify daemon persistence remains intact

**Files:**
- Test: `daemon/test/app-sqlite-store.test.js`

- [ ] **Step 1: Write or extend a persistence test**

```js
test('conversation adapter survives store reload', () => {
  const store = createStore();
  store.saveConversation({ id: 'c-1', adapter: 'codex', ...rest });

  const reloaded = createStoreFromSameDb();
  const conversations = reloaded.loadConversations();

  assert.equal(conversations[0].adapter, 'codex');
});
```

- [ ] **Step 2: Run test to verify it fails if coverage is missing**

Run: `npm test -- --runInBand daemon/test/app-sqlite-store.test.js`
Expected: FAIL or no-coverage if the test is not yet present.

- [ ] **Step 3: Run the targeted daemon test after adding coverage**

Run: `npm test -- --runInBand daemon/test/app-sqlite-store.test.js`
Expected: PASS.

### Task 4: Full targeted verification

**Files:**
- No code changes; verify the touched surfaces together.

- [ ] **Step 1: Run Flutter analysis and the focused tests**

Run:
`cd mobile; dart run tool/check_architecture_imports.dart`
`cd mobile; flutter test test/workbench_view_model_test.dart -r compact`
`npm test -- --runInBand daemon/test/app-sqlite-store.test.js`

- [ ] **Step 2: Confirm behavior**

Expected:
- Opening a historical conversation restores its adapter in the selector.
- The adapter selector cannot change while a conversation is active.
- Adapter persistence remains durable across restart.
