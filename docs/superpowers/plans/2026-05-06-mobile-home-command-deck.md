# Mobile Home Command Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mobile home dashboard with a compact current-workspace command deck that surfaces urgent cross-workspace interruptions without showing connection state or scan controls.

**Architecture:** Add a small home view-model layer that derives ranked home signals from `AppSnapshot`, then rebuild `HomePage` from focused widgets that render the command bar, Now panel, interrupt lane, execution stream, workspace signals, and compact actions. Keep data additions lightweight by deriving workspace run summaries from existing snapshot data first, with helper boundaries ready for future broader daemon data.

**Tech Stack:** Flutter/Dart, existing `AppSnapshot` protocol models, Flutter widget tests, ARB/gen-l10n localization.

---

## File Structure

- Create: `mobile/lib/src/ui/pages/home_command_deck_model.dart`
  - Pure Dart helpers for signal ranking, overflow, interrupt filtering, stream de-duplication, workspace signal counts, and workspace run summary aggregation.
- Modify: `mobile/lib/src/ui/pages/home_page.dart`
  - Replace the old dashboard composition with Command Deck widgets. Keep widgets private to this file unless they grow too large during implementation.
- Modify: `mobile/lib/l10n/app_en.arb`
  - Add new static labels and remove no keys yet to avoid generated-code churn outside this slice.
- Modify: `mobile/lib/l10n/app_zh.arb`
  - Add Simplified Chinese equivalents for new static labels.
- Generated after `flutter gen-l10n`:
  - Modify: `mobile/lib/l10n/app_localizations.dart`
  - Modify: `mobile/lib/l10n/app_localizations_en.dart`
  - Modify: `mobile/lib/l10n/app_localizations_zh.dart`
- Modify: `mobile/test/widget_test.dart`
  - Add widget coverage for hidden connection UI, interrupt lane visibility, compact empty state, Now Panel priority, de-duplication, and Simplified Chinese labels.
- Create: `mobile/test/home_command_deck_model_test.dart`
  - Unit tests for pure helper logic.

## Commands

- Format targeted files: `cd mobile && dart format lib\src\ui\pages\home_page.dart lib\src\ui\pages\home_command_deck_model.dart test\home_command_deck_model_test.dart test\widget_test.dart`
- Generate localization: `cd mobile && flutter gen-l10n`
- Analyze: `cd mobile && flutter analyze --no-pub`
- Unit test: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`
- Widget test: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"`

If Flutter commands are blocked by the Windows sandbox/cache issue, record the exact failure and still run `git diff --check`.

---

### Task 1: Home View Model Helpers

**Files:**
- Create: `mobile/lib/src/ui/pages/home_command_deck_model.dart`
- Create: `mobile/test/home_command_deck_model_test.dart`

- [ ] **Step 1: Write tests for priority, overflow, interrupts, and de-duplication**

Create `mobile/test/home_command_deck_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/pages/home_command_deck_model.dart';

void main() {
  const current = WorkspaceSummary(
      id: 'workspace_1', name: 'vibe-coding', path: r'D:\AiProject\vibe-coding');
  const other = WorkspaceSummary(
      id: 'workspace_2', name: 'daemon', path: r'D:\AiProject\daemon');

  test('approval outranks failure and exposes overflow count', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_failed',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'failed'),
      ],
      conversations: <ConversationSummary>[
        conversation(
            id: 'conv_approval',
            workspaceId: 'workspace_1',
            status: 'waiting_approval',
            blockingItem: const ConversationBlockingItem(
                type: 'approval_request',
                approvalId: 'ap1',
                questionId: null,
                summary: 'Modify file')),
      ],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(data.now.kind, HomeSignalKind.approval);
    expect(data.now.id, 'conversation:conv_approval');
    expect(data.nowOverflowCount, 1);
    expect(data.executionStream.map((item) => item.id), contains('run:run_failed'));
  });

  test('interrupt lane shows other workspace running only when current is idle', () {
    final idleData = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current, other],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_other',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'running'),
      ],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(idleData.now.kind, HomeSignalKind.idle);
    expect(idleData.interrupts.map((item) => item.id), contains('workspace-run:workspace_2'));

    final activeData = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current, other],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_current',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'running'),
        RunSummary(
            id: 'run_other',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'running'),
      ],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(activeData.now.id, 'run:run_current');
    expect(activeData.interrupts, isEmpty);
  });

  test('execution stream excludes exact now item', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_current',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'running'),
        RunSummary(
            id: 'run_recent',
            tool: 'claude',
            workspaceId: 'workspace_1',
            status: 'completed'),
      ],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(data.now.id, 'run:run_current');
    expect(data.executionStream.map((item) => item.id), isNot(contains('run:run_current')));
    expect(data.executionStream.map((item) => item.id), contains('run:run_recent'));
  });

  test('workspace signals preserve current workspace counts', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[
        QueueItem(
            runId: 'run_queued',
            workspaceId: 'workspace_1',
            position: 1,
            status: 'queued',
            reason: 'busy'),
      ],
      changedFiles: 5,
      diagnostics: 2,
      recentFiles: 4,
    );

    expect(data.signals.changedFiles, 5);
    expect(data.signals.diagnostics, 2);
    expect(data.signals.queue, 1);
    expect(data.signals.recentFiles, 4);
  });
}

ConversationSummary conversation({
  required String id,
  required String workspaceId,
  required String status,
  ConversationBlockingItem? blockingItem,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: 'codex',
      status: status,
      capabilities: ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-06T10:00:00.000Z',
      updatedAt: '2026-05-06T10:01:00.000Z',
      blockingItem: blockingItem,
    );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`

Expected: FAIL because `home_command_deck_model.dart`, `buildHomeCommandDeckData`, `HomeSignalKind`, and related types do not exist.

- [ ] **Step 3: Implement the pure helper model**

Create `mobile/lib/src/ui/pages/home_command_deck_model.dart`:

```dart
import '../../models/protocol.dart';

enum HomeSignalKind { approval, failure, running, queue, idle }

class HomeSignalItem {
  const HomeSignalItem({
    required this.id,
    required this.kind,
    required this.workspaceId,
    required this.workspaceName,
    required this.title,
    required this.detail,
    this.tool,
  });

  final String id;
  final HomeSignalKind kind;
  final String workspaceId;
  final String workspaceName;
  final String title;
  final String detail;
  final String? tool;

  bool get isIdle => kind == HomeSignalKind.idle;
}

class HomeWorkspaceSignalsData {
  const HomeWorkspaceSignalsData({
    required this.changedFiles,
    required this.diagnostics,
    required this.queue,
    required this.recentFiles,
  });

  final int changedFiles;
  final int diagnostics;
  final int queue;
  final int recentFiles;
}

class WorkspaceRunSummary {
  const WorkspaceRunSummary({
    required this.workspaceId,
    required this.runningCount,
    required this.failedCount,
    required this.latestRunId,
    required this.latestStatus,
    required this.latestTool,
  });

  final String workspaceId;
  final int runningCount;
  final int failedCount;
  final String latestRunId;
  final String latestStatus;
  final String latestTool;
}

class HomeCommandDeckData {
  const HomeCommandDeckData({
    required this.now,
    required this.nowOverflowCount,
    required this.interrupts,
    required this.executionStream,
    required this.signals,
    required this.workspaceRunSummaries,
  });

  final HomeSignalItem now;
  final int nowOverflowCount;
  final List<HomeSignalItem> interrupts;
  final List<HomeSignalItem> executionStream;
  final HomeWorkspaceSignalsData signals;
  final List<WorkspaceRunSummary> workspaceRunSummaries;
}

HomeCommandDeckData buildHomeCommandDeckData({
  required WorkspaceSummary currentWorkspace,
  required List<WorkspaceSummary> workspaces,
  required List<RunSummary> runs,
  required List<ConversationSummary> conversations,
  required List<QueueItem> queue,
  required int changedFiles,
  required int diagnostics,
  required int recentFiles,
}) {
  final workspaceNames = <String, String>{
    for (final workspace in workspaces) workspace.id: workspace.name,
  };
  final currentWorkspaceId = currentWorkspace.id;
  final allSignals = <HomeSignalItem>[
    ...conversations.map((conversation) => _conversationSignal(
          conversation,
          _workspaceName(workspaceNames, conversation.workspaceId),
        )),
    ...runs.map((run) => _runSignal(run, _workspaceName(workspaceNames, run.workspaceId))),
    ...queue.map((item) => _queueSignal(item, _workspaceName(workspaceNames, item.workspaceId))),
  ].whereType<HomeSignalItem>().toList()
    ..sort(_compareSignals);

  final currentSignals = allSignals
      .where((item) => item.workspaceId == currentWorkspaceId)
      .toList();
  final now = currentSignals.isNotEmpty
      ? currentSignals.first
      : HomeSignalItem(
          id: 'idle:$currentWorkspaceId',
          kind: HomeSignalKind.idle,
          workspaceId: currentWorkspaceId,
          workspaceName: currentWorkspace.name,
          title: currentWorkspace.name,
          detail: 'idle',
        );
  final overflow = currentSignals
      .skip(1)
      .where((item) => _priority(item.kind) <= _priority(now.kind) + 1)
      .length;
  final hasStrongSignal = allSignals.any((item) =>
      item.kind == HomeSignalKind.approval ||
      item.kind == HomeSignalKind.failure ||
      item.kind == HomeSignalKind.queue);
  final interrupts = allSignals
      .where((item) => item.workspaceId != currentWorkspaceId)
      .where((item) => item.kind != HomeSignalKind.running || (!hasStrongSignal && now.isIdle))
      .where((item) => item.kind != HomeSignalKind.idle)
      .take(3)
      .toList();
  final executionStream = allSignals
      .where((item) => item.workspaceId == currentWorkspaceId)
      .where((item) => item.id != now.id)
      .take(3)
      .toList();
  final currentQueue = queue
      .where((item) => item.workspaceId == currentWorkspaceId)
      .length;

  return HomeCommandDeckData(
    now: now,
    nowOverflowCount: overflow,
    interrupts: interrupts,
    executionStream: executionStream,
    signals: HomeWorkspaceSignalsData(
      changedFiles: changedFiles,
      diagnostics: diagnostics,
      queue: currentQueue,
      recentFiles: recentFiles,
    ),
    workspaceRunSummaries: buildWorkspaceRunSummaries(runs),
  );
}

List<WorkspaceRunSummary> buildWorkspaceRunSummaries(List<RunSummary> runs) {
  final byWorkspace = <String, List<RunSummary>>{};
  for (final run in runs) {
    byWorkspace.putIfAbsent(run.workspaceId, () => <RunSummary>[]).add(run);
  }
  return byWorkspace.entries.map((entry) {
    final latest = entry.value.first;
    return WorkspaceRunSummary(
      workspaceId: entry.key,
      runningCount: entry.value.where((run) => _isRunning(run.status)).length,
      failedCount: entry.value.where((run) => _isFailed(run.status)).length,
      latestRunId: latest.id,
      latestStatus: latest.status,
      latestTool: latest.tool,
    );
  }).toList();
}

HomeSignalItem? _conversationSignal(
    ConversationSummary conversation, String workspaceName) {
  final lower = conversation.status.toLowerCase();
  final hasBlockingItem = conversation.blockingItem != null;
  if (hasBlockingItem || lower.contains('approval')) {
    return HomeSignalItem(
      id: 'conversation:${conversation.id}',
      kind: HomeSignalKind.approval,
      workspaceId: conversation.workspaceId,
      workspaceName: workspaceName,
      title: conversation.blockingItem?.summary ?? conversation.status,
      detail: conversation.adapter,
      tool: conversation.adapter,
    );
  }
  if (_isFailed(conversation.status)) {
    return HomeSignalItem(
      id: 'conversation:${conversation.id}',
      kind: HomeSignalKind.failure,
      workspaceId: conversation.workspaceId,
      workspaceName: workspaceName,
      title: conversation.status,
      detail: conversation.adapter,
      tool: conversation.adapter,
    );
  }
  if (_isRunning(conversation.status)) {
    return HomeSignalItem(
      id: 'conversation:${conversation.id}',
      kind: HomeSignalKind.running,
      workspaceId: conversation.workspaceId,
      workspaceName: workspaceName,
      title: conversation.status,
      detail: conversation.adapter,
      tool: conversation.adapter,
    );
  }
  return null;
}

HomeSignalItem? _runSignal(RunSummary run, String workspaceName) {
  if (_isFailed(run.status)) {
    return HomeSignalItem(
      id: 'run:${run.id}',
      kind: HomeSignalKind.failure,
      workspaceId: run.workspaceId,
      workspaceName: workspaceName,
      title: run.status,
      detail: run.id,
      tool: run.tool,
    );
  }
  if (_isRunning(run.status) || run.status == 'completed') {
    return HomeSignalItem(
      id: 'run:${run.id}',
      kind: _isRunning(run.status) ? HomeSignalKind.running : HomeSignalKind.idle,
      workspaceId: run.workspaceId,
      workspaceName: workspaceName,
      title: run.status,
      detail: run.id,
      tool: run.tool,
    );
  }
  return null;
}

HomeSignalItem? _queueSignal(QueueItem item, String workspaceName) {
  final lower = item.status.toLowerCase();
  if (lower == 'running') return null;
  return HomeSignalItem(
    id: 'queue:${item.runId}',
    kind: HomeSignalKind.queue,
    workspaceId: item.workspaceId,
    workspaceName: workspaceName,
    title: item.status,
    detail: item.reason,
  );
}

String _workspaceName(Map<String, String> names, String workspaceId) =>
    names[workspaceId] ?? workspaceId;

int _compareSignals(HomeSignalItem left, HomeSignalItem right) {
  final priority = _priority(left.kind).compareTo(_priority(right.kind));
  if (priority != 0) return priority;
  return left.id.compareTo(right.id);
}

int _priority(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => 0,
      HomeSignalKind.failure => 1,
      HomeSignalKind.running => 2,
      HomeSignalKind.queue => 3,
      HomeSignalKind.idle => 4,
    };

bool _isRunning(String status) {
  final lower = status.toLowerCase();
  return lower == 'running' || lower == 'starting' || lower.contains('active');
}

bool _isFailed(String status) {
  final lower = status.toLowerCase();
  return lower == 'failed' || lower.contains('error') || lower.contains('cancel');
}
```

- [ ] **Step 4: Run unit test to verify it passes**

Run: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`

Expected: PASS for all four tests.

- [ ] **Step 5: Commit Task 1**

```bash
git add mobile/lib/src/ui/pages/home_command_deck_model.dart mobile/test/home_command_deck_model_test.dart
git commit -m "Derive mobile home command deck signals

Home signal ranking is kept outside widget layout so the command deck can handle priority, overflow, workspace scoping, and stream de-duplication predictably.

Constraint: Home must stay current-workspace first while surfacing cross-workspace interruptions
Confidence: high
Scope-risk: narrow
Tested: flutter test --no-pub test\home_command_deck_model_test.dart -r expanded
Not-tested: widget rendering follows in the next task"
```

---

### Task 2: Localization Keys

**Files:**
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Modify generated files after `flutter gen-l10n`:
  - `mobile/lib/l10n/app_localizations.dart`
  - `mobile/lib/l10n/app_localizations_en.dart`
  - `mobile/lib/l10n/app_localizations_zh.dart`

- [ ] **Step 1: Add ARB keys**

Add these English keys near the existing `home*` entries in `mobile/lib/l10n/app_en.arb`:

```json
  "homeNowTitle": "Now",
  "homeInterruptsTitle": "Needs attention",
  "homeExecutionStreamTitle": "Execution stream",
  "homeWorkspaceSignalsTitle": "Workspace signals",
  "homeIdleNow": "No blockers in this workspace",
  "homeNoRecentActivity": "No recent activity in this workspace",
  "homeGitChangedLabel": "Git changes",
  "homeDiagnosticsLabel": "Diagnostics",
  "homeQueueLabel": "Queue",
  "homeRecentFilesLabel": "Recent files",
  "homeMoreSignalsLabel": "+{count} more",
  "@homeMoreSignalsLabel": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  }
```

Add these Simplified Chinese keys near the existing `home*` entries in `mobile/lib/l10n/app_zh.arb`:

```json
  "homeNowTitle": "当前焦点",
  "homeInterruptsTitle": "需要关注",
  "homeExecutionStreamTitle": "执行流",
  "homeWorkspaceSignalsTitle": "工作区信号",
  "homeIdleNow": "当前工作区无阻塞",
  "homeNoRecentActivity": "当前工作区暂无活动",
  "homeGitChangedLabel": "Git 变更",
  "homeDiagnosticsLabel": "诊断",
  "homeQueueLabel": "队列",
  "homeRecentFilesLabel": "最近文件",
  "homeMoreSignalsLabel": "+{count} 项",
  "@homeMoreSignalsLabel": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  }
```

- [ ] **Step 2: Generate localizations**

Run: `cd mobile && flutter gen-l10n`

Expected: generated Dart files contain getters for all new `home*` labels and `homeMoreSignalsLabel(int count)`.

- [ ] **Step 3: Commit Task 2**

```bash
git add mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb mobile/lib/l10n/app_localizations.dart mobile/lib/l10n/app_localizations_en.dart mobile/lib/l10n/app_localizations_zh.dart
git commit -m "Localize mobile home command deck labels

The redesigned home surface needs static labels for focus, interrupts, execution stream, workspace signals, and compact overflow text.

Constraint: Runtime workspace, adapter, tool, and run identifiers remain untranslated
Confidence: high
Scope-risk: narrow
Tested: flutter gen-l10n
Not-tested: widget rendering follows in the next task"
```

---

### Task 3: Command Deck Home UI

**Files:**
- Modify: `mobile/lib/src/ui/pages/home_page.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add widget tests for the command deck surface**

In `mobile/test/widget_test.dart`, add tests near the existing home page tests. Reuse the test app helpers already present in that file where possible.

Add a test named `home command deck hides connection controls`:

```dart
testWidgets('home command deck hides connection controls', (tester) async {
  await tester.pumpWidget(const _LocalizedHomePageApp());
  await tester.pumpAndSettle();

  expect(find.text('Connected'), findsNothing);
  expect(find.text('已连接'), findsNothing);
  expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
});
```

Add a test named `home command deck renders compact Chinese idle state`:

```dart
testWidgets('home command deck renders compact Chinese idle state', (tester) async {
  await tester.pumpWidget(const _LocalizedHomePageApp(locale: Locale('zh')));
  await tester.pumpAndSettle();

  expect(find.text('当前焦点'), findsOneWidget);
  expect(find.text('当前工作区无阻塞'), findsOneWidget);
  expect(find.text('工作区信号'), findsOneWidget);
});
```

If `_LocalizedHomePageApp` currently does not accept a locale, extend it with an optional `Locale? locale` argument and pass it to `MaterialApp(locale: widget.locale)`.

Add a test named `home command deck shows overflow and deduplicates now item` using a snapshot with one approval conversation and one failed run in the same workspace:

```dart
testWidgets('home command deck shows overflow and deduplicates now item', (tester) async {
  final snapshot = buildHomeSnapshot(
    runs: const <RunSummary>[
      RunSummary(
          id: 'run_failed',
          tool: 'codex',
          workspaceId: 'workspace_1',
          status: 'failed'),
    ],
    conversations: <ConversationSummary>[
      conversationSummary(
        id: 'conv_approval',
        workspaceId: 'workspace_1',
        status: 'waiting_approval',
        blockingItem: const ConversationBlockingItem(
            type: 'approval_request',
            approvalId: 'ap1',
            questionId: null,
            summary: 'Modify file'),
      ),
    ],
  );

  await tester.pumpWidget(_HomePagePreview(snapshot: snapshot));
  await tester.pumpAndSettle();

  expect(find.text('+1 more'), findsOneWidget);
  expect(find.textContaining('Modify file'), findsOneWidget);
  expect(find.textContaining('run_failed'), findsOneWidget);
});
```

Add a test named `home command deck shows other workspace running only while current is idle`:

```dart
testWidgets('home command deck shows other workspace running only while current is idle', (tester) async {
  final snapshot = buildHomeSnapshot(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'workspace_1', name: 'vibe-coding', path: r'D:\AiProject\vibe-coding'),
      WorkspaceSummary(id: 'workspace_2', name: 'daemon', path: r'D:\AiProject\daemon'),
    ],
    runs: const <RunSummary>[
      RunSummary(
          id: 'run_other',
          tool: 'claude',
          workspaceId: 'workspace_2',
          status: 'running'),
    ],
  );

  await tester.pumpWidget(_HomePagePreview(snapshot: snapshot));
  await tester.pumpAndSettle();

  expect(find.text('Needs attention'), findsOneWidget);
  expect(find.textContaining('daemon'), findsWidgets);
});
```

If helper constructors do not exist, create private test helpers inside `widget_test.dart` with the same fields used by the existing `_LocalizedHomePageApp` snapshot setup.

- [ ] **Step 2: Run widget tests to verify they fail**

Run: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"`

Expected: FAIL because the old home page still shows connection status/scan controls and lacks new labels/components.

- [ ] **Step 3: Replace `HomePage` composition**

Modify `mobile/lib/src/ui/pages/home_page.dart`:

- Import the new helper:

```dart
import 'home_command_deck_model.dart';
```

- In `build`, derive command deck data:

```dart
final deck = buildHomeCommandDeckData(
  currentWorkspace: data.workspace,
  workspaces: data.workspaces,
  runs: data.runs,
  conversations: data.conversations,
  queue: data.queue,
  changedFiles: data.gitStatus?.files.length ?? 0,
  diagnostics: data.diagnostics.diagnostics.length,
  recentFiles: data.overview.recentFiles.length,
);
```

- Replace the old `TopBar`, `MetricCard`, `GlassCard` recent run block, large `QuickAction` row, and static `ApprovalPreview` with this structure:

```dart
return PageScroll(
  children: [
    _HomeCommandBar(workspace: data.workspace, onTap: () => selectTab(2)),
    const SizedBox(height: 14),
    _HomeNowPanel(data: deck, l10n: l10n, onTap: () => open(RoutePage.approval)),
    if (deck.interrupts.isNotEmpty) ...[
      const SizedBox(height: 14),
      _HomeInterruptLane(items: deck.interrupts, l10n: l10n),
    ],
    const SizedBox(height: 18),
    _HomeExecutionStream(items: deck.executionStream, l10n: l10n, onTap: () => open(RoutePage.detail)),
    const SizedBox(height: 18),
    _HomeWorkspaceSignals(data: deck.signals, l10n: l10n),
    const SizedBox(height: 18),
    _HomeActionRow(selectTab: selectTab, l10n: l10n),
  ],
);
```

- Add private widgets to the bottom of `home_page.dart`:

```dart
class _HomeCommandBar extends StatelessWidget {
  const _HomeCommandBar({required this.workspace, required this.onTap});

  final WorkspaceSummary workspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workspaceDisplayName(workspace),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5)),
                    const SizedBox(height: 5),
                    Text(_pathTail(workspace.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: theme.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: theme.muted),
            ],
          ),
        ),
      );
}

String _pathTail(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return '${parts[parts.length - 2]}/${parts.last}';
}
```

```dart
class _HomeNowPanel extends StatelessWidget {
  const _HomeNowPanel({required this.data, required this.l10n, required this.onTap});

  final HomeCommandDeckData data;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = data.now;
    return _InstrumentPanel(
      child: InkWell(
        onTap: item.isIdle ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelLabel(text: l10n.homeNowTitle),
              const SizedBox(height: 10),
              Row(
                children: [
                  _SignalDot(kind: item.kind),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.isIdle ? l10n.homeIdleNow : item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w850,
                                letterSpacing: -.2)),
                        const SizedBox(height: 4),
                        Text(item.isIdle ? item.workspaceName : '${item.workspaceName} · ${item.detail}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: theme.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (data.nowOverflowCount > 0)
                    Text(l10n.homeMoreSignalsLabel(data.nowOverflowCount),
                        style: const TextStyle(color: theme.purple, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

```dart
class _HomeInterruptLane extends StatelessWidget {
  const _HomeInterruptLane({required this.items, required this.l10n});

  final List<HomeSignalItem> items;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelLabel(text: l10n.homeInterruptsTitle),
          const SizedBox(height: 8),
          for (final item in items) ...[
            _SignalRow(item: item),
            if (item != items.last) const SizedBox(height: 8),
          ],
        ],
      );
}
```

```dart
class _HomeExecutionStream extends StatelessWidget {
  const _HomeExecutionStream({required this.items, required this.l10n, required this.onTap});

  final List<HomeSignalItem> items;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeExecutionStreamTitle, action: l10n.homeViewAllAction, onAction: onTap),
          const SizedBox(height: 10),
          if (items.isEmpty)
            _InstrumentPanel(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(l10n.homeNoRecentActivity,
                    style: const TextStyle(color: theme.muted, fontSize: 13)),
              ),
            )
          else
            for (final item in items) ...[
              InkWell(onTap: onTap, child: _SignalRow(item: item)),
              if (item != items.last) const SizedBox(height: 8),
            ],
        ],
      );
}
```

```dart
class _HomeWorkspaceSignals extends StatelessWidget {
  const _HomeWorkspaceSignals({required this.data, required this.l10n});

  final HomeWorkspaceSignalsData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeWorkspaceSignalsTitle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SignalChip(label: l10n.homeGitChangedLabel, value: '${data.changedFiles}'),
              _SignalChip(label: l10n.homeDiagnosticsLabel, value: '${data.diagnostics}'),
              _SignalChip(label: l10n.homeQueueLabel, value: '${data.queue}'),
              _SignalChip(label: l10n.homeRecentFilesLabel, value: '${data.recentFiles}'),
            ],
          ),
        ],
      );
}
```

```dart
class _HomeActionRow extends StatelessWidget {
  const _HomeActionRow({required this.selectTab, required this.l10n});

  final ValueChanged<int> selectTab;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _ActionPill(icon: Icons.add_rounded, label: l10n.homeNewTaskTitle, onTap: () => selectTab(1))),
          const SizedBox(width: 8),
          Expanded(child: _ActionPill(icon: Icons.terminal_rounded, label: l10n.homeCommandTemplatesTitle, onTap: () => selectTab(2))),
          const SizedBox(width: 8),
          Expanded(child: _ActionPill(icon: Icons.format_list_bulleted_rounded, label: l10n.homeViewQueueTitle, onTap: () => selectTab(3))),
        ],
      );
}
```

Add small primitives:

```dart
class _InstrumentPanel extends StatelessWidget {
  const _InstrumentPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075)),
        ),
        child: child,
      );
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          color: theme.muted,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1));
}

class _SignalDot extends StatelessWidget {
  const _SignalDot({required this.kind});
  final HomeSignalKind kind;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: _signalColor(kind), shape: BoxShape.circle),
      );
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.item});
  final HomeSignalItem item;

  @override
  Widget build(BuildContext context) => _InstrumentPanel(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              _SignalDot(kind: item.kind),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 3),
                    Text('${item.workspaceName} · ${item.detail}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: theme.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1218),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: theme.muted, fontSize: 12)),
          ],
        ),
      );
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF10151B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .075)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: theme.purple),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      );
}

Color _signalColor(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => theme.amber,
      HomeSignalKind.failure => theme.red,
      HomeSignalKind.running => theme.green,
      HomeSignalKind.queue => theme.purple,
      HomeSignalKind.idle => theme.muted,
    };
```

- [ ] **Step 4: Run widget tests to verify they pass**

Run: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"`

Expected: PASS for the new home command deck tests.

- [ ] **Step 5: Commit Task 3**

```bash
git add mobile/lib/src/ui/pages/home_page.dart mobile/test/widget_test.dart
git commit -m "Replace mobile home dashboard with command deck

The home page now prioritizes current workspace focus, compact interruption handling, execution activity, and workspace signals instead of large generic metric cards.

Constraint: Home must not show connection state, daemon address, or scan controls
Confidence: medium
Scope-risk: moderate
Tested: flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"
Not-tested: full Flutter suite pending final verification"
```

---

### Task 4: Full Verification And Polish

**Files:**
- Modify only files from Tasks 1-3 if verification exposes issues.

- [ ] **Step 1: Format targeted Dart files**

Run: `cd mobile && dart format lib\src\ui\pages\home_page.dart lib\src\ui\pages\home_command_deck_model.dart test\home_command_deck_model_test.dart test\widget_test.dart`

Expected: formatter completes and reports formatted files or no changes.

- [ ] **Step 2: Run Flutter analyze**

Run: `cd mobile && flutter analyze --no-pub`

Expected: no new errors. If existing unrelated warnings appear, record them and do not fix unrelated code.

- [ ] **Step 3: Run focused tests**

Run: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`

Expected: PASS.

Run: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"`

Expected: PASS.

- [ ] **Step 4: Run broader mobile widget tests if feasible**

Run: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded`

Expected: PASS, or only unrelated pre-existing failures. Do not claim full widget coverage if this command is blocked by sandbox/cache issues.

- [ ] **Step 5: Check diffs for ignored docs and whitespace**

Run: `git diff --check`

Expected: no whitespace errors.

Run: `git status --short --branch`

Expected: only intended files are modified.

- [ ] **Step 6: Commit final verification adjustments**

If formatting or verification changed files, commit them:

```bash
git add mobile/lib/src/ui/pages/home_page.dart mobile/lib/src/ui/pages/home_command_deck_model.dart mobile/test/home_command_deck_model_test.dart mobile/test/widget_test.dart mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb mobile/lib/l10n/app_localizations.dart mobile/lib/l10n/app_localizations_en.dart mobile/lib/l10n/app_localizations_zh.dart
git commit -m "Verify mobile home command deck integration

Final formatting and focused tests confirm the command deck view model, localized labels, and widget composition behave as specified.

Constraint: Verification may be limited by local Flutter sandbox/cache access
Confidence: medium
Scope-risk: narrow
Tested: dart format; flutter analyze --no-pub; focused Flutter tests; git diff --check
Not-tested: document any blocked command here before committing"
```

If no files changed after verification, do not create an empty commit.

---

## Self-Review Checklist

- Spec coverage:
  - Command Bar removes connection state, daemon address, and scan controls in Task 3.
  - Now Panel priority, overflow, and single-primary behavior are implemented in Task 1 and rendered in Task 3.
  - Interrupt Lane cross-workspace rules are implemented in Task 1 and rendered in Task 3.
  - Execution Stream de-duplication is implemented in Task 1 and tested in Tasks 1 and 3.
  - WorkspaceRunSummary lightweight aggregation is implemented in Task 1 without high-frequency polling.
  - Localization is handled in Task 2.
  - Tests are split into unit tests and widget tests.
- Placeholder scan: this plan contains no TBD/TODO/fill-in-later steps.
- Type consistency:
  - `HomeCommandDeckData`, `HomeSignalItem`, `HomeSignalKind`, `HomeWorkspaceSignalsData`, and `WorkspaceRunSummary` are defined in Task 1 and used consistently in later tasks.
  - Component name is `HomeWorkspaceSignals`, not `HomeSignalStrip`.
  - l10n keys use the `Label` suffix requested by the design review.
