# Codex Task Progress Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render Codex CLI structured `todo_list` JSONL events as a compact task progress card in the mobile workbench.

**Architecture:** The daemon owns CLI-specific parsing and maps Codex `todo_list` raw events into a normalized `task.progress.updated` conversation event. Mobile protocol models and reducer logic consume only normalized fields, then the workbench message renderer displays a dedicated task progress card. Ordinary tool calls remain command cards, and free-form text is never parsed as TODO state.

**Tech Stack:** Node.js daemon tests via `npm test`; Flutter/Dart mobile models, reducer, widget tests; existing workbench glass-card styling and protocol model classes.

---

## File Structure

- Modify `daemon/src/conversation-protocol.js`: add `TASK_PROGRESS_UPDATED` to `conversationEventTypes`.
- Modify `daemon/src/codex-conversation-adapter.js`: add Codex `todo_list` mapper helpers near `mapCodexEvent()`.
- Modify `scripts/run-tests.js`: add Codex mapper regression tests for observed and compatibility shapes.
- Modify `mobile/lib/src/data/models/conversation_models.dart`: add parsed task progress fields to `ConversationEvent` plus a `TaskProgressItem` model.
- Modify `mobile/lib/src/ui/features/workbench/conversation_reducer.dart`: project `task.progress.updated` into upserted `ConversationMessage` rows.
- Modify `mobile/lib/src/models/protocol.dart`: no direct edit expected because it already exports `conversation_models.dart`.
- Modify `mobile/lib/src/ui/features/workbench/workbench_messages.dart`: carry task progress data from `ConversationMessage` to `WorkbenchMessage`.
- Modify `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`: render `task_progress` messages as the new card and add a preview builder.
- Modify `mobile/test/conversation_reducer_test.dart`: reducer coverage for create/update semantics.
- Modify `mobile/test/widget_test.dart`: widget coverage for card rendering.

### Task 1: Daemon Protocol And Codex Mapper

**Files:**
- Modify: `daemon/src/conversation-protocol.js`
- Modify: `daemon/src/codex-conversation-adapter.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing mapper tests**

Add these tests near the existing `Codex event mapper normalizes...` tests in `scripts/run-tests.js`:

```js
test('Codex mapper normalizes observed todo_list items into task progress', () => {
  const event = mapCodexEvent({
    type: 'item.started',
    item: {
      id: 'item_1',
      type: 'todo_list',
      items: [
        { text: 'Inspect repo', completed: true },
        { text: 'Run tests', completed: false },
        { text: 'Summarize findings', completed: false }
      ]
    }
  });

  assert.equal(event.type, 'task.progress.updated');
  assert.equal(event.taskId, 'item_1');
  assert.equal(event.source, 'codex');
  assert.equal(event.completedCount, 1);
  assert.equal(event.totalCount, 3);
  assert.deepEqual(event.items.map((item) => item.status), ['completed', 'pending', 'pending']);
  assert.deepEqual(event.items.map((item) => item.title), ['Inspect repo', 'Run tests', 'Summarize findings']);
});

test('Codex mapper normalizes compatibility todo statuses into task progress', () => {
  const event = mapCodexEvent({
    type: 'item.updated',
    item: {
      id: 'item_2',
      type: 'todo_list',
      todos: [
        { content: 'Implement auth', status: 'completed' },
        { content: 'Run tests', status: 'in_progress' },
        { content: 'Summarize', status: 'pending' }
      ]
    }
  });

  assert.equal(event.type, 'task.progress.updated');
  assert.equal(event.taskId, 'item_2');
  assert.equal(event.completedCount, 1);
  assert.equal(event.totalCount, 3);
  assert.deepEqual(event.items.map((item) => item.status), ['completed', 'in_progress', 'pending']);
});

test('Codex mapper treats terminal todo_list with all false children as completed', () => {
  const event = mapCodexEvent({
    type: 'item.completed',
    item: {
      id: 'item_3',
      type: 'todo_list',
      items: [
        { text: 'Inspect repo', completed: false },
        { text: 'Run tests', completed: false }
      ]
    }
  });

  assert.equal(event.type, 'task.progress.updated');
  assert.equal(event.completedCount, 2);
  assert.equal(event.totalCount, 2);
  assert.deepEqual(event.items.map((item) => item.status), ['completed', 'completed']);
});

test('Codex mapper ignores malformed todo_list payloads', () => {
  assert.equal(mapCodexEvent({ type: 'item.started', item: { id: 'bad', type: 'todo_list', items: [] } }), null);
  assert.equal(mapCodexEvent({ type: 'item.started', item: { id: 'bad', type: 'todo_list', items: [{ completed: false }] } }), null);
});
```

- [ ] **Step 2: Run daemon tests to confirm failure**

Run: `npm test`

Expected: FAIL because `task.progress.updated` is not defined and `mapCodexEvent()` currently falls through to hidden `codex_unknown_event` for `todo_list`.

- [ ] **Step 3: Add protocol event constant**

In `daemon/src/conversation-protocol.js`, add:

```js
TASK_PROGRESS_UPDATED: 'task.progress.updated',
```

Place it near the other event constants, after `SYSTEM_NOTICE` or before tool events.

- [ ] **Step 4: Implement Codex todo_list mapping**

In `daemon/src/codex-conversation-adapter.js`, add this branch immediately after `const item = ...` and before command-execution branches:

```js
  if ((raw.type === 'item.started' || raw.type === 'item.updated' || raw.type === 'item.completed') && item?.type === 'todo_list') {
    return mapCodexTodoListEvent(raw, item);
  }
```

Add helpers near `mapCodexEvent()`:

```js
function mapCodexTodoListEvent(raw, item) {
  const taskId = String(item.id || 'codex_todo_list');
  const sourceItems = Array.isArray(item.items)
    ? item.items.map((entry, index) => normalizeCodexTodoItem(entry, index, taskId, raw.type, 'items'))
    : Array.isArray(item.todos)
      ? item.todos.map((entry, index) => normalizeCodexTodoItem(entry, index, taskId, raw.type, 'todos'))
      : [];
  const items = sourceItems.filter(Boolean);
  if (!items.length) return null;
  const completedCount = items.filter((entry) => entry.status === 'completed').length;
  return {
    type: conversationEventTypes.TASK_PROGRESS_UPDATED,
    taskId,
    source: 'codex',
    updatedAt: new Date().toISOString(),
    items,
    completedCount,
    totalCount: items.length,
    raw
  };
}

function normalizeCodexTodoItem(entry, index, taskId, rawType, shape) {
  if (!entry || typeof entry !== 'object') return null;
  const title = shape === 'items'
    ? String(entry.text || '').trim()
    : String(entry.content || '').trim();
  if (!title) return null;
  return {
    id: `${taskId}_${index}`,
    title,
    status: normalizeCodexTodoStatus(entry, rawType)
  };
}

function normalizeCodexTodoStatus(entry, rawType) {
  if (rawType === 'item.completed') return 'completed';
  if (entry.completed === true) return 'completed';
  const status = String(entry.status || '').toLowerCase();
  if (status === 'completed') return 'completed';
  if (status === 'in_progress') return 'in_progress';
  return 'pending';
}
```

If this introduces lint pressure around nested ternaries, split `sourceItems` into simple `if` branches.

- [ ] **Step 5: Run daemon tests to confirm pass**

Run: `npm test`

Expected: PASS with all daemon tests passing.

- [ ] **Step 6: Commit daemon mapper**

```bash
git add daemon/src/conversation-protocol.js daemon/src/codex-conversation-adapter.js scripts/run-tests.js
git commit -m "Normalize Codex todo_list progress events"
```

Use Lore trailers in the commit body documenting the observed Codex `items[].text/completed` shape.

### Task 2: Mobile Protocol Model And Reducer

**Files:**
- Modify: `mobile/lib/src/data/models/conversation_models.dart`
- Modify: `mobile/lib/src/ui/features/workbench/conversation_reducer.dart`
- Test: `mobile/test/conversation_reducer_test.dart`

- [ ] **Step 1: Add failing reducer tests**

Add tests to `mobile/test/conversation_reducer_test.dart` near existing projection tests:

```dart
test('ConversationViewState projects task progress updates', () {
  final state = const ConversationViewState().apply(<ConversationEvent>[
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'createdAt': '2026-05-17T08:00:00.000Z',
      'type': 'task.progress.updated',
      'taskId': 'item_1',
      'source': 'codex',
      'completedCount': 1,
      'totalCount': 3,
      'items': <Object?>[
        <String, Object?>{'id': 'item_1_0', 'title': 'Inspect repo', 'status': 'completed'},
        <String, Object?>{'id': 'item_1_1', 'title': 'Run tests', 'status': 'in_progress'},
        <String, Object?>{'id': 'item_1_2', 'title': 'Summarize', 'status': 'pending'},
      ],
    }),
  ]);

  expect(state.lastSeq, 1);
  expect(state.messages, hasLength(1));
  final message = state.messages.single;
  expect(message.role, 'task_progress');
  expect(message.text, 'Task Progress');
  expect(message.taskId, 'item_1');
  expect(message.completedCount, 1);
  expect(message.totalCount, 3);
  expect(message.taskItems.map((item) => item.status), <String>['completed', 'in_progress', 'pending']);
});

test('ConversationViewState upserts task progress by task id', () {
  final state = const ConversationViewState().apply(<ConversationEvent>[
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'createdAt': '2026-05-17T08:00:00.000Z',
      'type': 'task.progress.updated',
      'taskId': 'item_1',
      'source': 'codex',
      'completedCount': 0,
      'totalCount': 1,
      'items': <Object?>[
        <String, Object?>{'id': 'item_1_0', 'title': 'Inspect repo', 'status': 'pending'},
      ],
    }),
    ConversationEvent.fromJson(const <String, Object?>{
      'seq': 2,
      'conversationId': 'conv_1',
      'createdAt': '2026-05-17T08:00:01.000Z',
      'type': 'task.progress.updated',
      'taskId': 'item_1',
      'source': 'codex',
      'completedCount': 1,
      'totalCount': 1,
      'items': <Object?>[
        <String, Object?>{'id': 'item_1_0', 'title': 'Inspect repo', 'status': 'completed'},
      ],
    }),
  ]);

  expect(state.messages, hasLength(1));
  expect(state.messages.single.completedCount, 1);
  expect(state.messages.single.taskItems.single.status, 'completed');
});
```

- [ ] **Step 2: Run reducer tests to confirm failure**

Run with mirrors from repo root:

```bat
cd mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\conversation_reducer_test.dart
```

Expected: FAIL because task progress fields do not exist.

- [ ] **Step 3: Add task progress model fields**

In `mobile/lib/src/data/models/conversation_models.dart`, add below `ConversationEvent` or before it:

```dart
class TaskProgressItem {
  const TaskProgressItem({
    required this.id,
    required this.title,
    required this.status,
  });

  final String id;
  final String title;
  final String status;

  factory TaskProgressItem.fromJson(Map<String, Object?> json) =>
      TaskProgressItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
      );
}
```

Extend `ConversationEvent` constructor and fields:

```dart
this.taskId,
this.source,
this.updatedAt,
this.taskItems = const <TaskProgressItem>[],
this.completedCount = 0,
this.totalCount = 0,
```

Add final fields:

```dart
final String? taskId;
final String? source;
final DateTime? updatedAt;
final List<TaskProgressItem> taskItems;
final int completedCount;
final int totalCount;
```

In `fromJson`, parse:

```dart
taskId: json['taskId'] as String?,
source: json['source'] as String?,
updatedAt: json['updatedAt'] is String
    ? DateTime.tryParse(json['updatedAt']! as String)
    : null,
taskItems: ((json['items'] as List<Object?>?) ?? const <Object?>[])
    .whereType<Map<String, Object?>>()
    .map(TaskProgressItem.fromJson)
    .where((item) => item.title.trim().isNotEmpty)
    .toList(),
completedCount: json['completedCount'] as int? ?? 0,
totalCount: json['totalCount'] as int? ?? 0,
```

- [ ] **Step 4: Extend ConversationMessage**

In `mobile/lib/src/ui/features/workbench/conversation_reducer.dart`, extend `ConversationMessage` constructor with:

```dart
this.taskId,
this.source,
this.taskItems = const <TaskProgressItem>[],
this.completedCount = 0,
this.totalCount = 0,
```

Add fields:

```dart
final String? taskId;
final String? source;
final List<TaskProgressItem> taskItems;
final int completedCount;
final int totalCount;
```

- [ ] **Step 5: Add reducer projection**

In `ConversationViewState.apply()`, add a switch case:

```dart
case 'task.progress.updated':
  final taskId = event.taskId;
  if (taskId == null || taskId.isEmpty || event.taskItems.isEmpty) break;
  _upsertTaskProgressMessage(
    nextMessages,
    ConversationMessage(
      role: 'task_progress',
      text: 'Task Progress',
      eventSeq: event.seq,
      taskId: taskId,
      source: event.source,
      taskItems: event.taskItems,
      completedCount: event.completedCount,
      totalCount: event.totalCount,
    ),
  );
  break;
```

Add helper near other upsert helpers:

```dart
void _upsertTaskProgressMessage(
    List<ConversationMessage> messages, ConversationMessage taskProgress) {
  final index = messages.indexWhere((message) =>
      message.role == 'task_progress' && message.taskId == taskProgress.taskId);
  if (index >= 0) {
    messages[index] = taskProgress;
  } else {
    messages.add(taskProgress);
  }
}
```

- [ ] **Step 6: Run reducer tests to confirm pass**

Run with mirrors:

```bat
cd mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\conversation_reducer_test.dart
```

Expected: PASS.

If this command times out on the first attempt, stop and report the timeout plus the manual command instead of retrying.

- [ ] **Step 7: Commit mobile reducer model**

```bash
git add mobile/lib/src/data/models/conversation_models.dart mobile/lib/src/ui/features/workbench/conversation_reducer.dart mobile/test/conversation_reducer_test.dart
git commit -m "Project task progress events into workbench state"
```

Use Lore trailers and include the reducer upsert semantics.

### Task 3: Workbench Task Progress Card UI

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/workbench_messages.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add failing widget test**

Add near command card widget tests in `mobile/test/widget_test.dart`:

```dart
testWidgets('task progress card shows progress and item statuses',
    (WidgetTester tester) async {
  await tester.pumpWidget(buildTaskProgressCardPreview());
  await tester.pumpAndSettle();

  expect(find.text('????'), findsOneWidget);
  expect(find.text('1 / 3 ??'), findsOneWidget);
  expect(find.text('Inspect repo'), findsOneWidget);
  expect(find.text('Run tests'), findsOneWidget);
  expect(find.text('Summarize findings'), findsOneWidget);
  expect(find.text('????'), findsOneWidget);
  expect(find.text('????'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test to confirm failure**

Run with mirrors:

```bat
cd mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\widget_test.dart
```

Expected: FAIL because `buildTaskProgressCardPreview()` does not exist.

- [ ] **Step 3: Carry task progress through WorkbenchMessage**

In `mobile/lib/src/ui/features/workbench/workbench_messages.dart`, extend `WorkbenchMessage` with:

```dart
this.taskId,
this.taskItems = const <TaskProgressItem>[],
this.completedCount = 0,
this.totalCount = 0,
```

Add fields:

```dart
final String? taskId;
final List<TaskProgressItem> taskItems;
final int completedCount;
final int totalCount;
```

Update `copyWith()` to preserve these fields.

Update `workbenchMessageFromConversation()` to handle `ConversationMessage.role == 'task_progress'`:

```dart
if (message.role == 'task_progress') {
  return WorkbenchMessage(
    'task_progress',
    'Task Progress',
    '',
    taskId: message.taskId,
    taskItems: message.taskItems,
    completedCount: message.completedCount,
    totalCount: message.totalCount,
  );
}
```

- [ ] **Step 4: Route message role to a dedicated card**

In `WorkbenchMessageCard.build()` in `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`, add before generic card handling:

```dart
if (message.role == 'task_progress') {
  return _TaskProgressCard(message: message);
}
```

- [ ] **Step 5: Implement _TaskProgressCard**

Add a private widget in `workbench_event_cards.dart`:

```dart
class _TaskProgressCard extends StatelessWidget {
  const _TaskProgressCard({required this.message});

  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final total = message.totalCount == 0 ? message.taskItems.length : message.totalCount;
    final completed = message.completedCount;
    final progress = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
              child: Text('????',
                  style: TextStyle(
                      color: theme.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withValues(alpha: .035),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
              ),
              child: Text('$completed / $total ??',
                  style: const TextStyle(color: theme.muted, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: .04),
              valueColor: const AlwaysStoppedAnimation<Color>(theme.green),
            ),
          ),
          const SizedBox(height: 14),
          for (final item in message.taskItems) _TaskProgressRow(item: item),
          const SizedBox(height: 8),
          const _TaskProgressLegend(),
        ],
      ),
    );
  }
}
```

Add row and legend widgets:

```dart
class _TaskProgressRow extends StatelessWidget {
  const _TaskProgressRow({required this.item});

  final TaskProgressItem item;

  @override
  Widget build(BuildContext context) {
    final completed = item.status == 'completed';
    final active = item.status == 'in_progress';
    final color = completed ? theme.green : active ? theme.blue : theme.muted;
    final subtitle = completed ? '??' : active ? '????' : '????';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed ? theme.green.withValues(alpha: .12) : Colors.transparent,
            border: Border.all(color: color.withValues(alpha: completed ? .35 : .65)),
          ),
          child: completed
              ? const Icon(Icons.check_rounded, color: theme.green, size: 14)
              : active
                  ? Container(width: 6, height: 6, decoration: const BoxDecoration(color: theme.blue, shape: BoxShape.circle))
                  : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title,
                style: TextStyle(
                    color: completed ? theme.muted : theme.text,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600)),
            const SizedBox(height: 3),
            Text(subtitle,
                style: TextStyle(color: active ? theme.blue : theme.faint, fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }
}

class _TaskProgressLegend extends StatelessWidget {
  const _TaskProgressLegend();

  @override
  Widget build(BuildContext context) => Row(children: const [
        _TaskLegendDot(color: theme.green, label: '??'),
        SizedBox(width: 14),
        _TaskLegendDot(color: theme.blue, label: '???'),
        SizedBox(width: 14),
        _TaskLegendDot(color: theme.muted, label: '???'),
      ]);
}

class _TaskLegendDot extends StatelessWidget {
  const _TaskLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color.withValues(alpha: .75), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: theme.faint, fontSize: 11)),
      ]);
}
```

Use existing `theme.blue` only if it exists. If not, use `const Color(0xFF5B8DFF)`.

- [ ] **Step 6: Add preview builder**

Near other preview builders in `workbench_event_cards.dart`, add:

```dart
@visibleForTesting
Widget buildTaskProgressCardPreview() => MaterialApp(
    locale: theme.zhHansCnLocale,
    supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: theme.appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: theme.appFontFallback,
        useMaterial3: true),
    home: Scaffold(
        backgroundColor: theme.bg,
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: WorkbenchMessageCard(
              const WorkbenchMessage(
                'task_progress',
                'Task Progress',
                '',
                taskItems: <TaskProgressItem>[
                  TaskProgressItem(id: 'item_1_0', title: 'Inspect repo', status: 'completed'),
                  TaskProgressItem(id: 'item_1_1', title: 'Run tests', status: 'in_progress'),
                  TaskProgressItem(id: 'item_1_2', title: 'Summarize findings', status: 'pending'),
                ],
                completedCount: 1,
                totalCount: 3,
              ),
            ))));
```

- [ ] **Step 7: Run widget test to confirm pass**

Run with mirrors:

```bat
cd mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\widget_test.dart
```

Expected: PASS.

If this command times out on the first attempt, stop and report the timeout plus the manual command instead of retrying.

- [ ] **Step 8: Commit UI card**

```bash
git add mobile/lib/src/ui/features/workbench/workbench_messages.dart mobile/lib/src/ui/features/workbench/workbench_event_cards.dart mobile/test/widget_test.dart
git commit -m "Render structured task progress cards"
```

Use Lore trailers documenting that the card is driven by normalized task progress data only.

### Task 4: Final Verification

**Files:**
- No planned source edits unless verification exposes a bug in this feature.

- [ ] **Step 1: Run daemon verification**

Run: `npm test`

Expected: PASS.

- [ ] **Step 2: Run architecture import check**

Run with mirrors:

```bat
cd mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& dart run tool\check_architecture_imports.dart
```

Expected: PASS with no forbidden imports.

If this command times out on the first attempt, stop and report the timeout plus the manual command instead of retrying.

- [ ] **Step 3: Run focused Flutter tests**

Run with mirrors:

```bat
cd mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\conversation_reducer_test.dart test\widget_test.dart
```

Expected: PASS.

If this command times out on the first attempt, stop and report the timeout plus the manual command instead of retrying.

- [ ] **Step 4: Run static analysis if tests pass**

Run with mirrors:

```bat
cd mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter analyze
```

Expected: PASS.

If this command times out on the first attempt, stop and report the timeout plus the manual command instead of retrying.

- [ ] **Step 5: Commit verification fixes only if needed**

If verification required fixes, commit them with a narrow Lore-style message. If no fixes were needed, do not create an empty commit.

## Self-Review

- Spec coverage: Codex observed `todo_list.items[]`, compatibility `todos[]`, terminal `item.completed`, malformed payloads, normalized protocol, reducer upsert, UI card, and no text parsing are all mapped to tasks.
- Placeholder scan: No unresolved markers or "similar to" implementation gaps remain; `TODO` appears only as the domain term being implemented.
- Type consistency: `TaskProgressItem`, `taskItems`, `completedCount`, `totalCount`, `taskId`, and `task.progress.updated` use the same names across daemon, model, reducer, and UI tasks.
