# Mobile Bootstrap Lazy Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make daemon connection load only the home-critical bootstrap data, then defer workspace-heavy data to the pages that need it.

**Architecture:** Add `AppSnapshot.loadBootstrap` beside the existing full `AppSnapshot.load`, keeping `AppSnapshot` as the shell data object with safe empty defaults for deferred fields. Switch `DaemonConnectionController` to bootstrap loading with a 10-second timeout, and update Home workspace signals so deferred Git/diagnostic/recent-file values do not pretend to be verified zeros.

**Tech Stack:** Flutter/Dart, existing `DaemonClient`, existing `AppSnapshot`, Flutter tests, no new dependencies.

---

## File Structure

- Modify: `mobile/lib/src/shell/app_snapshot.dart`
  - Add `AppSnapshot.loadBootstrap` and private empty-default helpers.
  - Keep existing `AppSnapshot.load` for full snapshot compatibility.
- Modify: `mobile/lib/src/state/daemon_connection_controller.dart`
  - Use `AppSnapshot.loadBootstrap` as the default snapshot loader.
  - Restore default connection timeout to 10 seconds.
- Modify: `mobile/lib/src/ui/pages/home_command_deck_model.dart`
  - Allow workspace signal counts to be nullable when data is deferred.
- Modify: `mobile/lib/src/ui/pages/home_page.dart`
  - Render deferred workspace signals as `—`, not `0`.
- Modify: `mobile/test/daemon_connection_controller_test.dart`
  - Add coverage that default connection uses bootstrap behavior and keeps the existing custom-loader tests intact.
- Create: `mobile/test/app_snapshot_bootstrap_test.dart`
  - Unit-style test with a fake `DaemonClient` proving bootstrap does not call heavy methods.
- Modify: `mobile/test/home_command_deck_model_test.dart`
  - Adjust signal tests for nullable/deferred workspace signal counts.
- Modify: `mobile/test/widget_test.dart`
  - Assert Home renders deferred signal labels honestly from bootstrap defaults.

## Commands

- Focused snapshot test: `cd mobile && flutter test --no-pub test\app_snapshot_bootstrap_test.dart -r expanded`
- Focused connection test: `cd mobile && flutter test --no-pub test\daemon_connection_controller_test.dart -r expanded`
- Focused home model test: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`
- Focused home widget test: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"`
- Analyze: `cd mobile && flutter analyze --no-pub`
- Build verification when dependencies are available: `cd mobile && flutter build windows --debug --no-pub`

If Flutter commands are blocked by the sandbox approval service, record the exact failure and still run `git diff --check` and `npm test`.

---

### Task 1: Bootstrap Snapshot Loader

**Files:**
- Modify: `mobile/lib/src/shell/app_snapshot.dart`
- Create: `mobile/test/app_snapshot_bootstrap_test.dart`

- [ ] **Step 1: Write the failing bootstrap test**

Create `mobile/test/app_snapshot_bootstrap_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';

class RecordingDaemonClient extends DaemonClient {
  RecordingDaemonClient()
      : super(baseUri: Uri.parse('http://127.0.0.1:4317'), tokenStore: MemoryTokenStore());

  final calls = <String>[];

  @override
  Future<DaemonHealth> health() async {
    calls.add('health');
    return DaemonHealth.fromJson(const <String, Object?>{
      'status': 'ok',
      'daemonVersion': 'test',
      'mode': 'test',
      'lanMode': false,
      'bindAddress': '127.0.0.1',
      'port': 4317,
      'security': {'tokenRequired': false}
    });
  }

  @override
  Future<String> createPairingCode() async {
    calls.add('createPairingCode');
    return '123456';
  }

  @override
  Future<void> pair({required String code, String label = 'Android device'}) async {
    calls.add('pair');
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    calls.add('listWorkspaces');
    return const <WorkspaceSummary>[
      WorkspaceSummary(
          id: 'workspace_1', name: 'vibe-coding', path: r'D:\AiProject\vibe-coding'),
    ];
  }

  @override
  Future<List<RunSummary>> listRuns({String? workspaceId, String? status}) async {
    calls.add('listRuns:$workspaceId');
    return const <RunSummary>[
      RunSummary(
          id: 'run_1', tool: 'codex', workspaceId: 'workspace_1', status: 'running'),
    ];
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    calls.add('listConversations');
    return const <ConversationSummary>[];
  }

  @override
  Future<List<QueueItem>> listQueue() async {
    calls.add('listQueue');
    return const <QueueItem>[];
  }

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) async {
    calls.add('projectOverview');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    calls.add('listAdapters');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async {
    calls.add('listCommandTemplates');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) async {
    calls.add('gitStatus');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) async {
    calls.add('gitDiff');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<List<GitCommitSummary>> gitCommits(String workspaceId, {int limit = 20}) async {
    calls.add('gitCommits');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<FileTreeResponse> fileTree(String workspaceId, {String path = '', int maxDepth = 8}) async {
    calls.add('fileTree');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) async {
    calls.add('codeDiagnostics');
    throw StateError('heavy method must not be called');
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    calls.add('listExtensions');
    throw StateError('heavy method must not be called');
  }
}

void main() {
  test('bootstrap snapshot loads only home-critical data', () async {
    final client = RecordingDaemonClient();

    final snapshot = await AppSnapshot.loadBootstrap(client);

    expect(snapshot.workspace.id, 'workspace_1');
    expect(snapshot.runs.single.id, 'run_1');
    expect(snapshot.gitStatus, isNull);
    expect(snapshot.diagnostics.available, isFalse);
    expect(snapshot.fileTree.entries, isEmpty);
    expect(client.calls, containsAllInOrder(<String>[
      'health',
      'createPairingCode',
      'pair',
      'listWorkspaces',
      'listRuns:workspace_1',
      'listConversations',
      'listQueue',
    ]));
    expect(client.calls, isNot(contains('projectOverview')));
    expect(client.calls, isNot(contains('gitStatus')));
    expect(client.calls, isNot(contains('fileTree')));
    expect(client.calls, isNot(contains('codeDiagnostics')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test --no-pub test\app_snapshot_bootstrap_test.dart -r expanded`

Expected: FAIL because `AppSnapshot.loadBootstrap` does not exist yet.

- [ ] **Step 3: Implement `AppSnapshot.loadBootstrap`**

Modify `mobile/lib/src/shell/app_snapshot.dart`:

```dart
  static Future<AppSnapshot> loadBootstrap(DaemonClient client,
      {DaemonHealth? health}) async {
    final resolvedHealth = health ?? await client.health();
    final pairingCode = await client.createPairingCode();
    await client.pair(code: pairingCode, label: 'Windows preview');
    final workspaces = await client.listWorkspaces();
    final workspace = workspaces.first;
    final results = await Future.wait<Object?>([
      _loadStep('runs', () => client.listRuns(workspaceId: workspace.id)),
      _loadStep('conversations', client.listConversations),
      _loadStep('queue', client.listQueue),
    ]);
    return AppSnapshot(
      health: resolvedHealth,
      workspaces: workspaces,
      workspace: workspace,
      overview: _emptyOverview(workspace),
      adapters: const <AdapterStatus>[],
      runs: results[0] as List<RunSummary>,
      conversations: results[1] as List<ConversationSummary>,
      queue: results[2] as List<QueueItem>,
      templates: const <CommandTemplate>[],
      gitStatus: null,
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: _emptyFileTree(workspace),
      diagnostics: _deferredDiagnostics(workspace),
      extensions: const <ExtensionSummary>[],
    );
  }
```

Add helpers below the class:

```dart
ProjectOverview _emptyOverview(WorkspaceSummary workspace) => ProjectOverview(
      workspaceId: workspace.id,
      name: workspace.name,
      path: workspace.path,
      fileCount: 0,
      codeLineCount: 0,
      symbolCount: 0,
      analysisScore: 0,
      recentFiles: const <RecentFileSummary>[],
    );

FileTreeResponse _emptyFileTree(WorkspaceSummary workspace) => FileTreeResponse(
      workspaceId: workspace.id,
      root: '',
      entries: const <FileTreeEntry>[],
    );

CodeDiagnosticsSummary _deferredDiagnostics(WorkspaceSummary workspace) =>
    CodeDiagnosticsSummary(
      workspaceId: workspace.id,
      available: false,
      diagnostics: const <CodeDiagnostic>[],
    );
```

- [ ] **Step 4: Run bootstrap test to verify it passes**

Run: `cd mobile && flutter test --no-pub test\app_snapshot_bootstrap_test.dart -r expanded`

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add mobile/lib/src/shell/app_snapshot.dart mobile/test/app_snapshot_bootstrap_test.dart
git commit -m "Add lightweight mobile bootstrap snapshot

Connection now has a snapshot loading path that fetches only home-critical data and avoids workspace-heavy scans.

Constraint: Bootstrap must keep Home Command Deck immediately usable
Rejected: Make AppSnapshot fields broadly nullable | too much migration risk for existing pages
Confidence: high
Scope-risk: moderate
Tested: flutter test --no-pub test\app_snapshot_bootstrap_test.dart -r expanded
Not-tested: page lazy loaders follow in later tasks"
```

---

### Task 2: Switch Connection To Bootstrap

**Files:**
- Modify: `mobile/lib/src/state/daemon_connection_controller.dart`
- Modify: `mobile/test/daemon_connection_controller_test.dart`

- [ ] **Step 1: Update existing connection expectations**

In `mobile/test/daemon_connection_controller_test.dart`, add a test after `successful connection saves config and exposes snapshot`:

```dart
  test('default connection timeout is ten seconds for bootstrap loading', () {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );

    expect(controller.connectionTimeout, const Duration(seconds: 10));
  });
```

This requires adding a public getter to the controller in the implementation step.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test --no-pub test\daemon_connection_controller_test.dart -r expanded`

Expected: FAIL because `connectionTimeout` getter does not exist or default is still 30 seconds.

- [ ] **Step 3: Switch controller default loader and timeout**

Modify `mobile/lib/src/state/daemon_connection_controller.dart`:

```dart
  DaemonConnectionController({
    required this.store,
    required this.tokenStore,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration connectionTimeout = const Duration(seconds: 10),
  })  : _snapshotLoader =
            snapshotLoader ?? ((client) => AppSnapshot.loadBootstrap(client)),
        _healthProbe = healthProbe ?? ((client) async => client.health()),
        _connectionTimeout = connectionTimeout;
```

Add getter near existing getters:

```dart
  Duration get connectionTimeout => _connectionTimeout;
```

- [ ] **Step 4: Run connection controller tests**

Run: `cd mobile && flutter test --no-pub test\daemon_connection_controller_test.dart -r expanded`

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add mobile/lib/src/state/daemon_connection_controller.dart mobile/test/daemon_connection_controller_test.dart
git commit -m "Use bootstrap snapshot for daemon connection

The connection controller now enters the app through the lightweight bootstrap snapshot and restores the finite ten-second connection timeout.

Constraint: Heavy workspace data must not block the connection button
Rejected: Keep the thirty-second timeout as the main fix | it masks scaling problems
Confidence: high
Scope-risk: narrow
Tested: flutter test --no-pub test\daemon_connection_controller_test.dart -r expanded
Not-tested: full app navigation follows in later tasks"
```

---

### Task 3: Honest Deferred Home Signals

**Files:**
- Modify: `mobile/lib/src/ui/pages/home_command_deck_model.dart`
- Modify: `mobile/lib/src/ui/pages/home_page.dart`
- Modify: `mobile/test/home_command_deck_model_test.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Update home model tests for deferred counts**

In `mobile/test/home_command_deck_model_test.dart`, add:

```dart
  test('workspace signals can represent deferred values', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: null,
      diagnostics: null,
      recentFiles: null,
    );

    expect(data.signals.changedFiles, isNull);
    expect(data.signals.diagnostics, isNull);
    expect(data.signals.recentFiles, isNull);
    expect(data.signals.queue, 0);
  });
```

Update the helper signature uses in existing tests so `changedFiles`, `diagnostics`, and `recentFiles` accept nullable integers.

- [ ] **Step 2: Run home model test to verify it fails**

Run: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`

Expected: FAIL because `buildHomeCommandDeckData` currently requires non-null integers.

- [ ] **Step 3: Make deferred counts nullable**

Modify `mobile/lib/src/ui/pages/home_command_deck_model.dart`:

```dart
class HomeWorkspaceSignalsData {
  const HomeWorkspaceSignalsData({
    required this.changedFiles,
    required this.diagnostics,
    required this.queue,
    required this.recentFiles,
  });

  final int? changedFiles;
  final int? diagnostics;
  final int queue;
  final int? recentFiles;
}
```

Change `buildHomeCommandDeckData` signature:

```dart
  required int? changedFiles,
  required int? diagnostics,
  required int? recentFiles,
```

- [ ] **Step 4: Render deferred values as em-neutral placeholder**

Modify `mobile/lib/src/ui/pages/home_page.dart`:

```dart
      changedFiles: data.gitStatus?.files.length,
      diagnostics: data.diagnostics.available
          ? data.diagnostics.diagnostics.length
          : null,
      recentFiles: data.overview.recentFiles.isEmpty &&
              data.diagnostics.available == false &&
              data.gitStatus == null
          ? null
          : data.overview.recentFiles.length,
```

Add helper:

```dart
String _signalValue(int? value) => value == null ? '—' : '$value';
```

Use it in `_HomeWorkspaceSignals`:

```dart
_SignalChip(label: l10n.homeGitChangedLabel, value: _signalValue(data.changedFiles)),
_SignalChip(label: l10n.homeDiagnosticsLabel, value: _signalValue(data.diagnostics)),
_SignalChip(label: l10n.homeQueueLabel, value: '${data.queue}'),
_SignalChip(label: l10n.homeRecentFilesLabel, value: _signalValue(data.recentFiles)),
```

- [ ] **Step 5: Add widget test for deferred Home signals**

In `mobile/test/widget_test.dart`, add near home command deck tests:

```dart
testWidgets('home command deck renders deferred workspace signals honestly',
    (WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'en-US'});

  await tester.pumpWidget(const _LocalizedHomePageApp());
  await tester.pumpAndSettle();

  expect(find.text('Git changes'), findsOneWidget);
  expect(find.text('Diagnostics'), findsOneWidget);
  expect(find.text('Recent files'), findsOneWidget);
  expect(find.text('—'), findsWidgets);
});
```

Update `_testSnapshot()` defaults so diagnostics can represent deferred bootstrap state:

```dart
  CodeDiagnosticsSummary diagnostics = const CodeDiagnosticsSummary(
      workspaceId: 'workspace_1',
      available: false,
      diagnostics: <CodeDiagnostic>[]),
```

- [ ] **Step 6: Run focused home tests**

Run: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`

Expected: PASS.

Run: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"`

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add mobile/lib/src/ui/pages/home_command_deck_model.dart mobile/lib/src/ui/pages/home_page.dart mobile/test/home_command_deck_model_test.dart mobile/test/widget_test.dart
git commit -m "Show deferred workspace signals honestly on home

Home no longer displays zero Git, diagnostics, or recent-file counts when bootstrap has not loaded those page-specific resources.

Constraint: Bootstrap defaults must not imply verified clean or empty workspace state
Confidence: high
Scope-risk: narrow
Tested: focused home model and widget tests
Not-tested: page-specific lazy loaders follow separately if needed"
```

---

### Task 4: Final Verification

**Files:**
- Modify only files from Tasks 1-3 if verification exposes issues.

- [ ] **Step 1: Format targeted Dart files**

Run: `cd mobile && dart format lib\src\shell\app_snapshot.dart lib\src\state\daemon_connection_controller.dart lib\src\ui\pages\home_command_deck_model.dart lib\src\ui\pages\home_page.dart test\app_snapshot_bootstrap_test.dart test\daemon_connection_controller_test.dart test\home_command_deck_model_test.dart test\widget_test.dart`

Expected: formatter completes successfully.

- [ ] **Step 2: Run analyze**

Run: `cd mobile && flutter analyze --no-pub`

Expected: no new errors.

- [ ] **Step 3: Run focused Flutter tests**

Run: `cd mobile && flutter test --no-pub test\app_snapshot_bootstrap_test.dart -r expanded`

Run: `cd mobile && flutter test --no-pub test\daemon_connection_controller_test.dart -r expanded`

Run: `cd mobile && flutter test --no-pub test\home_command_deck_model_test.dart -r expanded`

Run: `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "home command deck"`

Expected: all pass.

- [ ] **Step 4: Run available broader tests**

Run: `npm test`

Expected: 66 daemon tests pass.

Run: `cd mobile && flutter build windows --debug --no-pub`

Expected: Windows debug build succeeds if dependencies are already resolved.

- [ ] **Step 5: Static checks**

Run: `git diff --check`

Expected: no whitespace errors.

Run: `rg -n "AppSnapshot.load\(client\)|Duration\(seconds: 30\)|projectOverview\(|fileTree\(|codeDiagnostics\(" mobile/lib/src/state mobile/lib/src/shell/app_snapshot.dart`

Expected: controller default uses `AppSnapshot.loadBootstrap`; connection timeout is not 30 seconds; heavy calls remain only in full `AppSnapshot.load`, not bootstrap.

- [ ] **Step 6: Commit final verification adjustments if needed**

If formatting or fixes changed files:

```bash
git add mobile/lib/src/shell/app_snapshot.dart mobile/lib/src/state/daemon_connection_controller.dart mobile/lib/src/ui/pages/home_command_deck_model.dart mobile/lib/src/ui/pages/home_page.dart mobile/test/app_snapshot_bootstrap_test.dart mobile/test/daemon_connection_controller_test.dart mobile/test/home_command_deck_model_test.dart mobile/test/widget_test.dart
git commit -m "Verify mobile bootstrap lazy loading

Focused verification confirms connection bootstrap avoids heavy workspace scans and home renders deferred workspace signals honestly.

Constraint: Local Flutter verification may depend on SDK/cache access
Confidence: medium
Scope-risk: narrow
Tested: dart format; flutter analyze --no-pub; focused Flutter tests; npm test; git diff --check
Not-tested: document any blocked command before committing"
```

Do not create an empty commit if no files changed.

---

## Self-Review Checklist

- Spec coverage:
  - Bootstrap loads only health, workspaces, runs, conversations, and queue in Task 1.
  - Connection uses bootstrap and returns to 10 seconds in Task 2.
  - Home deferred signals are honest in Task 3.
  - Heavy page-specific APIs remain outside connection flow.
  - Lazy page loaders are intentionally limited to follow-up if they grow beyond this slice.
- Placeholder scan: this plan contains no TBD/TODO/fill-in-later steps.
- Type consistency:
  - `AppSnapshot.loadBootstrap` is used by the controller.
  - `HomeWorkspaceSignalsData` nullable fields match `_signalValue` rendering.
  - `CodeDiagnosticsSummary.available == false` is the bootstrap deferred marker.
