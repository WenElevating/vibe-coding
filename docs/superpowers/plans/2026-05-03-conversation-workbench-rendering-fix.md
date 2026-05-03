# Conversation Workbench Rendering Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mobile coding workbench render conversation events natively so final assistant replies are complete and pending state stops correctly.

**Architecture:** Keep the backend conversation protocol intact. Replace the workbench's core `ConversationEvent -> AgentEvent` bridge with a conversation-native reducer and message model, while reusing existing visual cards where possible. Conversation status becomes the source of truth for running, idle, input, and approval states.

**Tech Stack:** Flutter/Dart mobile UI and tests; Node daemon tests only for regression coverage already present.

---

## File Structure

- Modify `mobile/lib/src/state/conversation_reducer.dart`: make reducer preserve complete final assistant messages, statuses, questions, approvals, and resolved approval display state.
- Modify `mobile/test/conversation_reducer_test.dart`: add tests for full final message rendering, stream-off behavior, normal assistant question text, and status transitions.
- Modify `mobile/lib/main.dart`: switch `_CodingWorkbenchPage` to store `ConversationSummary`, `ConversationEvent`, and `ConversationViewState`; stop using `_agentEventFromConversation()` for core chat rendering.
- Modify `mobile/test/widget_test.dart`: add a focused regression test for the screenshot scenario if helper functions can cover it without broad UI setup.

---

## Task 1: Strengthen Conversation Reducer

**Files:**
- Modify: `mobile/lib/src/state/conversation_reducer.dart`
- Test: `mobile/test/conversation_reducer_test.dart`

- [ ] **Step 1: Add failing reducer tests**

Add tests for:

```dart
test('ConversationViewState keeps complete final assistant message', () {
  const full = '你的请求比较笼统——"高级 Python 脚本"可以涵盖很多东西。请帮我明确需求：\n\n1. 网络爬虫\n2. 数据分析\n3. 自动化工具';
  final state = const ConversationViewState().apply(<ConversationEvent>[
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'assistant.partial',
      'createdAt': '2026-05-03T00:00:00.000Z',
      'text': '你的请求比较笼统——'
    }),
    ConversationEvent.fromJson(<String, Object?>{
      'seq': 2,
      'conversationId': 'conv_1',
      'type': 'assistant.message',
      'createdAt': '2026-05-03T00:00:01.000Z',
      'text': full,
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 3,
      'conversationId': 'conv_1',
      'type': 'conversation.status_changed',
      'createdAt': '2026-05-03T00:00:02.000Z',
      'status': 'idle'
    }),
  ], streamOutput: false);

  expect(state.status, 'idle');
  expect(state.messages, hasLength(1));
  expect(state.messages.single.role, 'assistant');
  expect(state.messages.single.text, full);
  expect(state.messages.single.text, contains('1. 网络爬虫'));
});

test('ConversationViewState treats normal assistant question as assistant text', () {
  final state = const ConversationViewState().apply(<ConversationEvent>[
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'assistant.message',
      'createdAt': '2026-05-03T00:00:00.000Z',
      'text': '你想让这个 Python 脚本做什么？请补充。'
    }),
  ]);

  expect(state.status, 'idle');
  expect(state.messages.single.role, 'assistant');
});
```

- [ ] **Step 2: Run reducer tests**

Run: `flutter test test/conversation_reducer_test.dart`
Expected: failures where API lacks `streamOutput` and status handling is incomplete.

- [ ] **Step 3: Update reducer implementation**

Change `ConversationViewState.apply` to accept `bool streamOutput = false`. Ensure:

```dart
ConversationViewState apply(Iterable<ConversationEvent> events,
    {bool streamOutput = false}) { ... }
```

Behavior:
- Hide `assistant.partial` when `streamOutput == false`.
- Show one `assistant_stream` temporary message when `streamOutput == true`.
- On `assistant.message`, remove temporary stream messages and append one complete `assistant` message using `event.text` exactly.
- On `conversation.status_changed`, update `status` from `event.raw['status']`.
- On `assistant.message`, set status to `idle`.
- On `assistant.question`, set status to `waiting_input` and add a `question` message.
- On `approval.requested`, set status to `waiting_approval` and upsert by `approvalId`.
- On `approval.resolved`, remove matching approval and set status to `running`.

- [ ] **Step 4: Run reducer tests again**

Run: `flutter test test/conversation_reducer_test.dart`
Expected: all reducer tests pass.

---

## Task 2: Make Workbench Conversation-Native

**Files:**
- Modify: `mobile/lib/main.dart`

- [ ] **Step 1: Replace workbench state fields**

Add fields:

```dart
ConversationSummary? _activeConversation;
ConversationViewState _conversationState = const ConversationViewState();
final List<ConversationEvent> _conversationEvents = <ConversationEvent>[];
```

Keep `_activeRunId` only as a legacy display id alias until session list is also migrated.

- [ ] **Step 2: Update running and terminal getters**

Use conversation status:

```dart
bool get _isTerminal => _activeConversation == null ||
    const {'idle', 'failed', 'cancelled', 'expired'}.contains(_activeConversation!.status);

bool get _isRunningCli => _activeConversation?.status == 'running';
```

- [ ] **Step 3: Update send flow**

Rules:
- New session creates conversation then sends message.
- Existing `waiting_input` answers the pending question.
- Existing `idle` sends a normal message to the same conversation.
- Existing `running` does not send a second message.

- [ ] **Step 4: Update polling flow**

Fetch `ConversationEvent` directly:

```dart
final next = await widget.client.fetchConversationEvents(
  _activeConversation!.id,
  afterSeq: _lastSeq,
);
```

Apply reducer:

```dart
_conversationState = _conversationState.apply(next,
    streamOutput: widget.streamOutput);
```

Refresh `_activeConversation.status` from status events when present.

- [ ] **Step 5: Render from conversation messages**

Convert `ConversationMessage` to `_WorkbenchMessage` in a small helper:

```dart
_WorkbenchMessage _workbenchMessageFromConversation(ConversationMessage message)
```

Mapping:
- `user` -> `_WorkbenchMessage.user(message.text)`
- `assistant` -> `_WorkbenchMessage('assistant', 'CLI 助手', message.text, runId: _activeConversation?.id)`
- `assistant_stream` -> stream message
- `question` -> question card with suggestions
- `approval` -> approval card with approval id

- [ ] **Step 6: Remove core `_agentEventFromConversation` usage**

No core send/poll/render path may call `_agentEventFromConversation()`.

---

## Task 3: Regression Tests and Verification

**Files:**
- Modify: `mobile/test/conversation_reducer_test.dart`
- Modify: `mobile/test/widget_test.dart` only if existing helper coverage is insufficient.

- [ ] **Step 1: Run focused tests**

Run: `flutter test test/conversation_reducer_test.dart test/protocol_compatibility_test.dart`
Expected: all pass.

- [ ] **Step 2: Run all Flutter tests**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`
Expected: no issues found.

- [ ] **Step 4: Run daemon tests**

Run from repo root: `npm test`
Expected: all pass.

---

## Self-Review

- Spec coverage: complete final text, no normal-question waiting state, true question card, approval flow, and pending sentinel state are covered.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: plan uses existing `ConversationSummary`, `ConversationEvent`, `ConversationViewState`, and `ConversationMessage` names.
