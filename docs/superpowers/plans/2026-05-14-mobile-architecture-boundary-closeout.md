# Mobile Architecture Boundary Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the mobile app architecture structure and remove ordinary UI direct `DaemonClient` access from diagnostics, run detail, and route overlay surfaces.

**Architecture:** Keep `src/app/` as the app-layer composition root, `src/ui/` as MVVM presentation, `src/domain/` as repository contracts, `src/data/` as daemon repository implementations, and `src/services/` as infrastructure. `MainTabsPage` remains the temporary connected shell boundary, but ordinary feature UI receives repositories, ViewModels, or app-built feature dependencies.

**Tech Stack:** Flutter, Dart `ChangeNotifier`, repository interfaces, existing hand-written dependency builders in `app_dependencies.dart`, `flutter_test`, and `mobile/tool/check_architecture_imports.dart`.

---

## Scope And Source Design

Implement the approved spec:

```text
docs/superpowers/specs/2026-05-14-mobile-architecture-structure-and-daemon-boundary-design.md
```

Do not implement the later `MainTabsPage` exit from the daemon-client allowlist in this plan. This plan only records the exit path and preserves `MainTabsPage` as the temporary connected shell boundary.

Do not split `CodingWorkbenchPage`, `WorkbenchViewModel`, or `src/models/protocol.dart`.

## File Map

### Structure closeout

- Rename: `mobile/lib/src/ui/features/sessions/session_list_view_model.dart` -> `mobile/lib/src/ui/features/sessions/session_item_projection.dart`
- Modify: `mobile/lib/src/ui/features/sessions/view_models/session_list_view_model.dart`
- Modify: `mobile/lib/src/ui/features/sessions/sessions.dart`
- Delete local empty directories if present:
  - `mobile/lib/src/features/`
  - `mobile/lib/src/state/`
  - `mobile/lib/src/theme/`
  - `mobile/lib/src/widgets/`

### Diagnostics boundary

- Modify: `mobile/lib/src/domain/repositories/diagnostics_repository.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_diagnostics_repository.dart`
- Create: `mobile/lib/src/ui/features/diagnostics/view_models/diagnostics_view_model.dart`
- Modify: `mobile/lib/src/ui/features/diagnostics/diagnostics.dart`
- Modify: `mobile/lib/src/ui/features/diagnostics/diagnostics_page.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/diagnostics_view_model_test.dart`
- Modify test fakes that implement `DiagnosticsRepository`, currently including `mobile/test/coding_workbench_controller_test.dart`

### Run detail boundary

- Modify: `mobile/lib/src/ui/features/run_detail/view_models/run_detail_view_model.dart`
- Modify: `mobile/lib/src/ui/features/run_detail/run_detail_page.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/run_detail_view_model_test.dart`

### Overlay and checker boundary

- Modify: `mobile/lib/src/ui/main_route_overlay.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/tool/check_architecture_imports.dart`

---

### Task 1: Structure Closeout

**Files:**
- Rename: `mobile/lib/src/ui/features/sessions/session_list_view_model.dart` -> `mobile/lib/src/ui/features/sessions/session_item_projection.dart`
- Modify: `mobile/lib/src/ui/features/sessions/view_models/session_list_view_model.dart`
- Modify: `mobile/lib/src/ui/features/sessions/sessions.dart`
- Delete local directories if they exist and are empty:
  - `mobile/lib/src/features/`
  - `mobile/lib/src/state/`
  - `mobile/lib/src/theme/`
  - `mobile/lib/src/widgets/`

- [ ] **Step 1: Confirm the old session helper has no external package consumers**

Run:

```powershell
rg "session_list_view_model" mobile/lib mobile/test -n
```

Expected current output before the rename:

```text
mobile/lib\src\ui\features\sessions\sessions.dart:3:export 'session_list_view_model.dart';
mobile/lib\src\ui\features\sessions\view_models\session_list_view_model.dart:5:import '../session_list_view_model.dart';
```

- [ ] **Step 2: Rename the helper file**

Run:

```powershell
Move-Item -LiteralPath mobile\lib\src\ui\features\sessions\session_list_view_model.dart -Destination mobile\lib\src\ui\features\sessions\session_item_projection.dart
```

Expected: the file moves and `git status --short` shows a rename or delete/add pair.

- [ ] **Step 3: Update the ViewModel import**

In `mobile/lib/src/ui/features/sessions/view_models/session_list_view_model.dart`, replace:

```dart
import '../session_list_view_model.dart';
```

with:

```dart
import '../session_item_projection.dart';
```

- [ ] **Step 4: Update the sessions barrel**

In `mobile/lib/src/ui/features/sessions/sessions.dart`, replace the whole file with:

```dart
export 'coding_session_list_page.dart';
export 'session_item.dart';
export 'session_item_projection.dart';
export 'view_models/session_list_view_model.dart';
```

- [ ] **Step 5: Remove retired empty roots from the working tree**

Run this PowerShell script from the repo root:

```powershell
$roots = @(
  'mobile\lib\src\features',
  'mobile\lib\src\state',
  'mobile\lib\src\theme',
  'mobile\lib\src\widgets'
)
foreach ($root in $roots) {
  if (Test-Path -LiteralPath $root) {
    $files = Get-ChildItem -LiteralPath $root -Recurse -File -Force
    if ($files.Count -ne 0) {
      throw "Refusing to delete non-empty retired root: $root"
    }
    Remove-Item -LiteralPath $root -Recurse
  }
}
```

Expected: the directories are gone if they were empty. If the script throws, inspect the listed files and stop this task rather than deleting non-empty roots.

- [ ] **Step 6: Verify old paths and old helper name are gone**

Run:

```powershell
rg "src/features|src/widgets|src/theme|src/state" mobile/lib mobile/test -n
rg "export 'session_list_view_model.dart'|import '../session_list_view_model.dart'" mobile/lib mobile/test -n
git ls-files mobile/lib/src/features mobile/lib/src/state mobile/lib/src/theme mobile/lib/src/widgets
```

Expected:

```text
no rg matches for retired roots
no rg matches for the old top-level session_list_view_model.dart import/export
git ls-files prints nothing for retired roots
```

- [ ] **Step 7: Format and analyze**

Run:

```powershell
Set-Location mobile
dart format lib\src\ui\features\sessions\session_item_projection.dart lib\src\ui\features\sessions\sessions.dart lib\src\ui\features\sessions\view_models\session_list_view_model.dart
dart analyze
```

Expected:

```text
No issues found!
```

- [ ] **Step 8: Run focused regression tests**

Run:

```powershell
Set-Location mobile
flutter test test\coding_workbench_controller_test.dart -r expanded --name "session|conversation route|workbench view model"
flutter test test\widget_test.dart -r expanded --name "session|workspace|coding workbench"
```

Expected: selected tests pass. If a name pattern selects zero tests, rerun the relevant file without `--name` and record that broader command in the commit message.

- [ ] **Step 9: Commit structure closeout**

Run:

```powershell
git add mobile/lib/src/ui/features/sessions/session_item_projection.dart mobile/lib/src/ui/features/sessions/view_models/session_list_view_model.dart mobile/lib/src/ui/features/sessions/sessions.dart
git add -A mobile/lib/src/ui/features/sessions
git commit -m "Clarify mobile feature structure" -m "Constraint: keep ui/features as the only active feature UI root." -m "Tested: cd mobile && dart analyze" -m "Tested: cd mobile && flutter test selected session/workbench widget coverage"
```

Expected: one commit containing only the rename/import cleanup and empty-root removal.

---

### Task 2: Diagnostics Repository ViewModel

**Files:**
- Modify: `mobile/lib/src/domain/repositories/diagnostics_repository.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_diagnostics_repository.dart`
- Create: `mobile/lib/src/ui/features/diagnostics/view_models/diagnostics_view_model.dart`
- Modify: `mobile/lib/src/ui/features/diagnostics/diagnostics.dart`
- Modify: `mobile/lib/src/ui/features/diagnostics/diagnostics_page.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/diagnostics_view_model_test.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`

- [ ] **Step 1: Write diagnostics ViewModel tests**

Create `mobile/test/diagnostics_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/diagnostics/view_models/diagnostics_view_model.dart';

void main() {
  test('exports diagnostics bundle and exposes result', () async {
    final repository = _FakeDiagnosticsRepository(
      bundle: DiagnosticBundleSummary(
        bundleId: 'bundle-1',
        createdAt: DateTime.utc(2026, 5, 14, 10),
        path: r'D:\tmp\diagnostics.zip',
        redacted: true,
        items: const <String>['system', 'runs'],
      ),
    );
    final viewModel = DiagnosticsViewModel(repository: repository);

    await viewModel.createBundle();

    expect(repository.exportCount, 1);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.error, isNull);
    expect(viewModel.bundle?.bundleId, 'bundle-1');
    expect(viewModel.bundle?.redacted, isTrue);
  });

  test('reports diagnostics export failure', () async {
    final repository = _FakeDiagnosticsRepository(error: StateError('disk full'));
    final viewModel = DiagnosticsViewModel(repository: repository);

    await viewModel.createBundle();

    expect(repository.exportCount, 1);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.bundle, isNull);
    expect(viewModel.error, contains('disk full'));
  });
}

class _FakeDiagnosticsRepository implements DiagnosticsRepository {
  _FakeDiagnosticsRepository({this.bundle, this.error});

  final DiagnosticBundleSummary? bundle;
  final Object? error;
  int exportCount = 0;

  @override
  Future<DiagnosticBundleSummary> exportDiagnostics() async {
    exportCount++;
    final error = this.error;
    if (error != null) throw error;
    return bundle!;
  }

  @override
  Future<String> recordException({
    required String message,
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async =>
      'trace-test';
}
```

- [ ] **Step 2: Run diagnostics tests to verify they fail**

Run:

```powershell
Set-Location mobile
flutter test test\diagnostics_view_model_test.dart -r expanded
```

Expected: FAIL because `DiagnosticsViewModel` and `DiagnosticsRepository.exportDiagnostics()` do not exist yet.

- [ ] **Step 3: Add export method to diagnostics repository contract**

Replace `mobile/lib/src/domain/repositories/diagnostics_repository.dart` with:

```dart
import '../../models/protocol.dart';

abstract class DiagnosticsRepository {
  Future<DiagnosticBundleSummary> exportDiagnostics();

  Future<String> recordException({
    required String message,
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  });
}
```

- [ ] **Step 4: Implement export in daemon diagnostics repository**

In `mobile/lib/src/data/repositories/daemon_diagnostics_repository.dart`, add the protocol import and method:

```dart
import '../../models/protocol.dart';
```

Inside `DaemonDiagnosticsRepository` add:

```dart
@override
Future<DiagnosticBundleSummary> exportDiagnostics() =>
    _client.exportDiagnostics();
```

Keep `recordException` unchanged.

- [ ] **Step 5: Update diagnostics repository fakes**

In `mobile/test/coding_workbench_controller_test.dart`, find `_FakeDiagnosticsRepository implements DiagnosticsRepository` and add:

```dart
@override
Future<DiagnosticBundleSummary> exportDiagnostics() async =>
    DiagnosticBundleSummary(
      bundleId: 'bundle-test',
      createdAt: DateTime.utc(2026, 5, 14),
      path: r'D:\tmp\bundle-test.zip',
      redacted: true,
      items: const <String>['system'],
    );
```

If another fake implements `DiagnosticsRepository`, add the same method there too.

- [ ] **Step 6: Add DiagnosticsViewModel**

Create `mobile/lib/src/ui/features/diagnostics/view_models/diagnostics_view_model.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../../../domain/repositories/diagnostics_repository.dart';
import '../../../../models/protocol.dart';

class DiagnosticsViewModel extends ChangeNotifier {
  DiagnosticsViewModel({required DiagnosticsRepository repository})
      : _repository = repository;

  final DiagnosticsRepository _repository;

  DiagnosticBundleSummary? _bundle;
  bool _isLoading = false;
  String? _error;

  DiagnosticBundleSummary? get bundle => _bundle;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> createBundle() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _bundle = await _repository.exportDiagnostics();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

- [ ] **Step 7: Export the diagnostics ViewModel**

Replace `mobile/lib/src/ui/features/diagnostics/diagnostics.dart` with:

```dart
export 'diagnostics_page.dart';
export 'view_models/diagnostics_view_model.dart';
```

- [ ] **Step 8: Refactor DiagnosticsPage to receive a ViewModel**

Replace `mobile/lib/src/ui/features/diagnostics/diagnostics_page.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';
import 'view_models/diagnostics_view_model.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({
    super.key,
    required this.onBack,
    required this.viewModel,
  });

  final VoidCallback onBack;
  final DiagnosticsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => PageScroll(children: [
        TopBar(title: l10n.diagnosticsTitle, leading: true, action: '?'),
        const SizedBox(height: 10),
        Text(l10n.diagnosticsDescription,
            style: const TextStyle(color: theme.muted, fontSize: 12)),
        const SizedBox(height: 14),
        GlassCard(
            child: Column(children: [
          _DiagRow(l10n.diagnosticsSystemInfo, '1.2 KB'),
          const Hairline(),
          _DiagRow(l10n.diagnosticsAdapterStatus, '2.4 KB'),
          const Hairline(),
          _DiagRow(l10n.diagnosticsRunLogsRecent, '512 KB'),
          const Hairline(),
          _DiagRow(l10n.diagnosticsEventRecordsRecent, '3.1 MB'),
          const Hairline(),
          _DiagRow(l10n.diagnosticsConfigInfo, '1.8 KB')
        ])),
        const SizedBox(height: 18),
        Row(children: [
          Text(l10n.diagnosticsEstimatedSize,
              style: const TextStyle(color: theme.muted, fontSize: 12)),
          const Spacer(),
          const Text('5.1 MB', style: TextStyle(fontWeight: FontWeight.w800))
        ]),
        if (viewModel.error != null) ...[
          const SizedBox(height: 12),
          Text(viewModel.error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: theme.red, fontSize: 12)),
        ],
        if (viewModel.bundle != null) ...[
          const SizedBox(height: 12),
          Text(viewModel.bundle!.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: theme.muted, fontSize: 12)),
        ],
        const SizedBox(height: 18),
        PrimaryButton(
          l10n.diagnosticsGenerateAction,
          onTap: () {
            viewModel.createBundle();
          },
        ),
      ]),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow(this.title, this.size);
  final String title, size;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: theme.green, size: 17),
        const SizedBox(width: 9),
        Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(size, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
```

- [ ] **Step 9: Add app-layer diagnostics ViewModel builder**

In `mobile/lib/src/app/app_dependencies.dart`, add:

```dart
import '../ui/features/diagnostics/diagnostics.dart';
```

Update `FeatureDependencies` constructor fields to include:

```dart
required this.createDiagnosticsViewModel,
```

In `FeatureDependencies.createDefault`, add:

```dart
createDiagnosticsViewModel: (connectedData) => DiagnosticsViewModel(
  repository: connectedData.diagnosticsRepository,
),
```

Add the field:

```dart
final DiagnosticsViewModel Function(ConnectedDataDependencies connectedData)
    createDiagnosticsViewModel;
```

- [ ] **Step 10: Run diagnostics tests and analyzer**

Run:

```powershell
Set-Location mobile
dart format lib\src\domain\repositories\diagnostics_repository.dart lib\src\data\repositories\daemon_diagnostics_repository.dart lib\src\ui\features\diagnostics\diagnostics.dart lib\src\ui\features\diagnostics\diagnostics_page.dart lib\src\ui\features\diagnostics\view_models\diagnostics_view_model.dart lib\src\app\app_dependencies.dart test\diagnostics_view_model_test.dart test\coding_workbench_controller_test.dart
flutter test test\diagnostics_view_model_test.dart -r expanded
dart analyze
```

Expected:

```text
diagnostics_view_model_test.dart passes
No issues found!
```

- [ ] **Step 11: Commit diagnostics boundary**

Run:

```powershell
git add mobile/lib/src/domain/repositories/diagnostics_repository.dart mobile/lib/src/data/repositories/daemon_diagnostics_repository.dart mobile/lib/src/ui/features/diagnostics mobile/lib/src/app/app_dependencies.dart mobile/test/diagnostics_view_model_test.dart mobile/test/coding_workbench_controller_test.dart
git commit -m "Route diagnostics through repository view model" -m "Constraint: keep DiagnosticsPage free of DaemonClient." -m "Tested: cd mobile && flutter test test\\diagnostics_view_model_test.dart -r expanded" -m "Tested: cd mobile && dart analyze"
```

Expected: one commit containing diagnostics repository contract, ViewModel, page wiring, and tests.

---

### Task 3: Run Detail Repository ViewModel

**Files:**
- Modify: `mobile/lib/src/ui/features/run_detail/view_models/run_detail_view_model.dart`
- Modify: `mobile/lib/src/ui/features/run_detail/run_detail_page.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/run_detail_view_model_test.dart`

- [ ] **Step 1: Write run detail ViewModel tests**

Create `mobile/test/run_detail_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/run_detail/view_models/run_detail_view_model.dart';

void main() {
  test('loads run events through repository and advances sequence', () async {
    final repository = _FakeRunRepository(events: [
      AgentEvent(
        type: 'assistant.message',
        seq: 1,
        runId: 'run-1',
        createdAt: DateTime.utc(2026, 5, 14, 10),
        text: 'done',
      ),
    ]);
    const run = RunSummary(
      id: 'run-1',
      tool: 'claude',
      workspaceId: 'workspace-1',
      status: 'running',
    );
    final viewModel = RunDetailViewModel(
      run: run,
      runRepository: repository,
    );

    await viewModel.loadEvents();

    expect(repository.lastRunId, 'run-1');
    expect(repository.lastAfterSeq, 0);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.error, isNull);
    expect(viewModel.events, hasLength(1));
    expect(viewModel.state.lastSeq, 1);
  });

  test('loads only events after the current sequence on refresh', () async {
    final repository = _FakeRunRepository(events: [
      AgentEvent(
        type: 'assistant.message',
        seq: 2,
        runId: 'run-1',
        createdAt: DateTime.utc(2026, 5, 14, 10, 1),
        text: 'again',
      ),
    ]);
    const run = RunSummary(
      id: 'run-1',
      tool: 'claude',
      workspaceId: 'workspace-1',
      status: 'running',
    );
    final viewModel = RunDetailViewModel(
      run: run,
      runRepository: repository,
    )..applyEvents([
        AgentEvent(
          type: 'assistant.message',
          seq: 1,
          runId: 'run-1',
          createdAt: DateTime.utc(2026, 5, 14, 10),
          text: 'first',
        ),
      ]);

    await viewModel.loadEvents();

    expect(repository.lastAfterSeq, 1);
    expect(viewModel.events.map((event) => event.seq), <int>[1, 2]);
  });

  test('reports run event load failure', () async {
    final repository = _FakeRunRepository(error: StateError('offline'));
    const run = RunSummary(
      id: 'run-1',
      tool: 'claude',
      workspaceId: 'workspace-1',
      status: 'running',
    );
    final viewModel = RunDetailViewModel(
      run: run,
      runRepository: repository,
    );

    await viewModel.loadEvents();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.events, isEmpty);
    expect(viewModel.error, contains('offline'));
  });
}

class _FakeRunRepository implements RunRepository {
  _FakeRunRepository({this.events = const <AgentEvent>[], this.error});

  final List<AgentEvent> events;
  final Object? error;
  String? lastRunId;
  int? lastAfterSeq;

  @override
  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq = 0}) async {
    lastRunId = runId;
    lastAfterSeq = afterSeq;
    final error = this.error;
    if (error != null) throw error;
    return events;
  }

  @override
  Future<RunSummary> cancelRun(String runId) async =>
      throw UnimplementedError();

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) async =>
      throw UnimplementedError();

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<QueueItem>> listQueue() async => throw UnimplementedError();

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> respondApproval(String approvalId, String decision) async {}

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) async =>
      throw UnimplementedError();
}
```

- [ ] **Step 2: Run run-detail tests to verify they fail**

Run:

```powershell
Set-Location mobile
flutter test test\run_detail_view_model_test.dart -r expanded
```

Expected: FAIL because `RunDetailViewModel` does not yet accept `run` and `runRepository`, and `loadEvents()` does not exist.

- [ ] **Step 3: Extend RunDetailViewModel**

Replace `mobile/lib/src/ui/features/run_detail/view_models/run_detail_view_model.dart` with:

```dart
import 'package:flutter/foundation.dart';

import '../../../../domain/repositories/run_repository.dart';
import '../../../../models/protocol.dart';
import '../run_detail_state.dart';

class RunDetailViewModel extends ChangeNotifier {
  RunDetailViewModel({
    required RunSummary run,
    required RunRepository runRepository,
  })  : _run = run,
        _runRepository = runRepository,
        _state = const RunDetailState();

  final RunSummary _run;
  final RunRepository _runRepository;

  RunDetailState _state;
  bool _isLoading = false;
  String? _error;

  RunSummary get run => _run;
  RunDetailState get state => _state;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<AgentEvent> get events => _state.events;
  RunConnectionState get connectionState => _state.connectionState;

  Future<void> loadEvents() async {
    if (_isLoading) return;
    setLoading(loading: true);
    setError(null);
    try {
      final events = await _runRepository.fetchEvents(
        _run.id,
        afterSeq: _state.lastSeq,
      );
      applyEvents(events);
    } catch (error) {
      setError(error.toString());
    } finally {
      setLoading(loading: false);
    }
  }

  void applyEvents(Iterable<AgentEvent> incoming) {
    _state = _state.mergeEvents(incoming);
    notifyListeners();
  }

  void setLoading({required bool loading}) {
    if (_isLoading == loading) return;
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? message) {
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Refactor RunDetailPage to use ViewModel**

Replace `mobile/lib/src/ui/features/run_detail/run_detail_page.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';
import 'view_models/run_detail_view_model.dart';

class RunDetailPage extends StatefulWidget {
  const RunDetailPage({
    super.key,
    required this.onBack,
    required this.viewModel,
  });

  final VoidCallback onBack;
  final RunDetailViewModel viewModel;

  @override
  State<RunDetailPage> createState() => _RunDetailPageState();
}

class _RunDetailPageState extends State<RunDetailPage> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final events = widget.viewModel.events;
        return PageScroll(children: [
          TopBar(title: l10n.runDetailTitle, leading: true, action: '?'),
          const SizedBox(height: 14),
          GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: Text(l10n.runDetailMockTask,
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  StatusBadge(l10n.runDetailRunningStatus, color: theme.green)
                ]),
                const SizedBox(height: 8),
                const Row(children: [
                  AgentIcon(color: theme.orange),
                  SizedBox(width: 6),
                  Text('Claude Code',
                      style: TextStyle(color: theme.muted, fontSize: 12))
                ]),
                const SizedBox(height: 8),
                Text(l10n.runDetailStartedDuration,
                    style: const TextStyle(color: theme.muted, fontSize: 12)),
              ])),
          const SizedBox(height: 14),
          Tabs(labels: [
            l10n.runDetailTabOverview,
            l10n.runDetailTabEvents,
            l10n.runDetailTabFileChanges,
            l10n.runDetailTabConfig
          ]),
          const SizedBox(height: 12),
          if (widget.viewModel.error != null)
            GlassCard(
                child: Text(widget.viewModel.error!,
                    style: const TextStyle(color: theme.red, fontSize: 12)))
          else if (events.isNotEmpty)
            for (final event in events)
              _Timeline(
                event.name ?? event.type,
                event.text ?? event.type,
                _formatEventTime(event.createdAt),
                Icons.terminal_rounded,
                theme.green,
              )
          else ...[
            _Timeline(l10n.runDetailUserPromptTitle,
                l10n.runDetailUserPromptBody, '10:32', Icons.person_rounded,
                theme.purple),
            _Timeline(l10n.runDetailThinkingTitle,
                l10n.runDetailThinkingBody, '10:32',
                Icons.auto_awesome_rounded, theme.purple),
            _Timeline(
                l10n.runDetailReadFileTitle,
                'tests/login_test.dart                 +128 -45',
                '10:33',
                Icons.file_open_rounded,
                theme.green),
            _Timeline(l10n.runDetailSearchCodeTitle,
                l10n.runDetailSearchBody, '10:34', Icons.search_rounded,
                theme.muted),
            _Timeline(
                l10n.runDetailEditFileTitle,
                'lib/services/auth_service.dart       +32 -8',
                '10:35',
                Icons.edit_document,
                theme.green),
            _Timeline(l10n.runDetailRunCommandTitle,
                l10n.runDetailCommandBody, '10:36', Icons.terminal_rounded,
                theme.green),
          ],
          const SizedBox(height: 8),
          GhostButton(l10n.commonBack, color: theme.purple, onTap: widget.onBack),
        ]);
      },
    );
  }

  String _formatEventTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.title, this.body, this.time, this.icon, this.color);
  final String title, body, time;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withValues(alpha: .18)),
            child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(body,
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
```

- [ ] **Step 5: Add app-layer run detail ViewModel builder**

In `mobile/lib/src/app/app_dependencies.dart`, add:

```dart
import '../models/protocol.dart';
import '../ui/features/run_detail/run_detail.dart';
```

Update `FeatureDependencies` constructor fields to include:

```dart
required this.createRunDetailViewModel,
```

In `FeatureDependencies.createDefault`, add:

```dart
createRunDetailViewModel: (connectedData, run) => RunDetailViewModel(
  run: run,
  runRepository: connectedData.runRepository,
),
```

Add the field:

```dart
final RunDetailViewModel Function(
  ConnectedDataDependencies connectedData,
  RunSummary run,
) createRunDetailViewModel;
```

- [ ] **Step 6: Run run-detail tests and analyzer**

Run:

```powershell
Set-Location mobile
dart format lib\src\ui\features\run_detail\view_models\run_detail_view_model.dart lib\src\ui\features\run_detail\run_detail_page.dart lib\src\app\app_dependencies.dart test\run_detail_view_model_test.dart
flutter test test\run_detail_view_model_test.dart -r expanded
dart analyze
```

Expected:

```text
run_detail_view_model_test.dart passes
No issues found!
```

- [ ] **Step 7: Commit run detail boundary**

Run:

```powershell
git add mobile/lib/src/ui/features/run_detail mobile/lib/src/app/app_dependencies.dart mobile/test/run_detail_view_model_test.dart
git commit -m "Route run detail through repository view model" -m "Constraint: keep RunDetailPage free of DaemonClient." -m "Tested: cd mobile && flutter test test\\run_detail_view_model_test.dart -r expanded" -m "Tested: cd mobile && dart analyze"
```

Expected: one commit containing run detail ViewModel/page wiring and tests.

---

### Task 4: Overlay and Checker Hardening

**Files:**
- Modify: `mobile/lib/src/ui/main_route_overlay.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/tool/check_architecture_imports.dart`

- [ ] **Step 1: Refactor MainRouteOverlay constructor and page wiring**

Replace `mobile/lib/src/ui/main_route_overlay.dart` with:

```dart
import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../models/protocol.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import 'features/adapters/adapters.dart';
import 'features/diagnostics/diagnostics.dart';
import 'features/notifications/notifications.dart';
import 'features/run_detail/run_detail.dart';
import 'features/workbench/workbench.dart';

class MainRouteOverlay extends StatelessWidget {
  const MainRouteOverlay({
    super.key,
    required this.route,
    required this.data,
    required this.connectedData,
    required this.featureDependencies,
    required this.onBack,
  });

  final RoutePage route;
  final AppSnapshot data;
  final ConnectedDataDependencies connectedData;
  final FeatureDependencies featureDependencies;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return switch (route) {
      RoutePage.detail => RunDetailPage(
          onBack: onBack,
          viewModel: featureDependencies.createRunDetailViewModel(
            connectedData,
            _selectedRun(data),
          ),
        ),
      RoutePage.approval => ApprovalPage(onBack: onBack),
      RoutePage.adapters => AdaptersPage(
          onBack: onBack,
          viewModel: AdaptersViewModel(snapshot: data),
        ),
      RoutePage.notifications => NotificationsPage(onBack: onBack),
      RoutePage.diagnostics => DiagnosticsPage(
          onBack: onBack,
          viewModel:
              featureDependencies.createDiagnosticsViewModel(connectedData),
        ),
      RoutePage.tabs => const SizedBox.shrink(),
    };
  }

  RunSummary _selectedRun(AppSnapshot data) {
    if (data.runningRuns.isNotEmpty) return data.runningRuns.first;
    if (data.runs.isNotEmpty) return data.runs.first;
    return RunSummary(
      id: 'no-run',
      tool: 'unknown',
      workspaceId: data.workspace.id,
      status: 'idle',
    );
  }
}
```

- [ ] **Step 2: Stop MainTabsPage from passing client to overlay**

In `mobile/lib/src/ui/main_tabs_page.dart`, replace the `MainRouteOverlay` call:

```dart
MainRouteOverlay(
  route: _viewModel.activeRoute,
  data: data,
  client: widget.client,
  onBack: _viewModel.closeOverlay,
),
```

with:

```dart
MainRouteOverlay(
  route: _viewModel.activeRoute,
  data: data,
  connectedData: _connectedData,
  featureDependencies: widget.dependencies.features,
  onBack: _viewModel.closeOverlay,
),
```

Keep the `DaemonClient` import in `main_tabs_page.dart`; it is still the allowed connected shell boundary.

- [ ] **Step 3: Harden UI daemon-client checker rule**

In `mobile/tool/check_architecture_imports.dart`, add this constant near the other constants:

```dart
const allowedUiDaemonClientBoundaryImports = <String>{
  'lib/src/ui/main_tabs_page.dart',
  'lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart',
  'lib/src/ui/features/connection/view_models/daemon_connection_controller.dart',
};
```

Replace:

```dart
final uiDaemonClientDebt = <String>[];
```

with:

```dart
final allowedUiDaemonClientImports = <String>[];
final forbiddenUiDaemonClientImports = <String>[];
```

Replace the `_checkUiDaemonClientRule` call arguments with:

```dart
allowedUiDaemonClientImports: allowedUiDaemonClientImports,
forbiddenUiDaemonClientImports: forbiddenUiDaemonClientImports,
```

Replace the output block:

```dart
stdout.writeln('UI direct DaemonClient imports:');
if (uiDaemonClientDebt.isEmpty) {
  stdout.writeln('  none');
} else {
  for (final debt in uiDaemonClientDebt) {
    stdout.writeln('  $debt');
  }
}
```

with:

```dart
stdout.writeln('Allowed UI DaemonClient boundary imports:');
if (allowedUiDaemonClientImports.isEmpty) {
  stdout.writeln('  none');
} else {
  for (final debt in allowedUiDaemonClientImports) {
    stdout.writeln('  $debt');
  }
}
stdout.writeln('Forbidden UI DaemonClient imports:');
if (forbiddenUiDaemonClientImports.isEmpty) {
  stdout.writeln('  none');
} else {
  for (final debt in forbiddenUiDaemonClientImports) {
    stdout.writeln('  $debt');
  }
}
violations.addAll(forbiddenUiDaemonClientImports);
```

Replace `_checkUiDaemonClientRule` with:

```dart
void _checkUiDaemonClientRule({
  required String relativeFile,
  required String uri,
  required String normalizedTarget,
  required int lineNumber,
  required List<String> allowedUiDaemonClientImports,
  required List<String> forbiddenUiDaemonClientImports,
}) {
  if (!relativeFile.startsWith('lib/src/ui/')) return;
  if (!_targetsRoot(normalizedTarget, 'src/services/daemon_client.dart')) {
    return;
  }
  final finding =
      '$relativeFile:$lineNumber UI imports concrete DaemonClient ($uri)';
  if (allowedUiDaemonClientBoundaryImports.contains(relativeFile)) {
    allowedUiDaemonClientImports.add(finding);
  } else {
    forbiddenUiDaemonClientImports.add(finding);
  }
}
```

- [ ] **Step 4: Verify ordinary UI direct DaemonClient imports fail cleanly**

Run:

```powershell
Set-Location mobile
dart run tool\check_architecture_imports.dart
```

Expected output includes:

```text
Allowed UI DaemonClient boundary imports:
  lib/src/ui/features/connection/view_models/daemon_connection_controller.dart:...
  lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart:...
  lib/src/ui/main_tabs_page.dart:...
Forbidden UI DaemonClient imports:
  none
No forbidden imports found.
```

If `diagnostics_page.dart`, `run_detail_page.dart`, or `main_route_overlay.dart` appears under forbidden imports, return to Tasks 2-4 and remove the direct import.

- [ ] **Step 5: Run final architecture and target scans**

Run:

```powershell
Set-Location mobile
dart run tool\check_architecture_imports.dart
dart analyze
Set-Location ..
rg "services/daemon_client|DaemonClient" mobile/lib/src/ui/main_route_overlay.dart mobile/lib/src/ui/features/diagnostics mobile/lib/src/ui/features/run_detail -n
rg "src/features|src/widgets|src/theme|src/state" mobile/lib mobile/test -n
git ls-files mobile/lib/src/features mobile/lib/src/state mobile/lib/src/theme mobile/lib/src/widgets
```

Expected:

```text
architecture checker passes
analyzer passes
no DaemonClient matches in overlay/diagnostics/run_detail
no retired-root import matches
git ls-files retired roots prints nothing
```

- [ ] **Step 6: Run final targeted tests**

Run:

```powershell
Set-Location mobile
flutter test test\diagnostics_view_model_test.dart test\run_detail_view_model_test.dart -r expanded
flutter test test\main_tabs_view_model_test.dart test\daemon_connection_controller_test.dart -r expanded
flutter test test\widget_test.dart -r expanded --name "diagnostics|run detail|adapter picker|opening coding tab|coding workbench|workspace"
```

Expected: all selected tests pass. If the widget-test name filter selects no diagnostics or run-detail tests, keep the command result and rely on the ViewModel tests plus architecture checker for those surfaces.

- [ ] **Step 7: Commit overlay and checker hardening**

Run:

```powershell
git add mobile/lib/src/ui/main_route_overlay.dart mobile/lib/src/ui/main_tabs_page.dart mobile/tool/check_architecture_imports.dart mobile/test/widget_test.dart
git commit -m "Harden mobile UI daemon client boundary" -m "Constraint: allow DaemonClient only at connection and main tabs shell boundaries." -m "Tested: cd mobile && dart run tool\\check_architecture_imports.dart" -m "Tested: cd mobile && dart analyze" -m "Tested: cd mobile && flutter test diagnostics, run-detail, main-tabs, connection, and selected widget coverage"
```

If `mobile/test/widget_test.dart` was not changed, omit it from `git add`.

Expected: one commit containing overlay wiring and checker hardening only.

---

## Final Verification

Run after all implementation commits:

```powershell
Set-Location mobile
dart run tool\check_architecture_imports.dart
dart analyze
flutter test test\diagnostics_view_model_test.dart test\run_detail_view_model_test.dart -r expanded
flutter test test\main_tabs_view_model_test.dart test\daemon_connection_controller_test.dart -r expanded
flutter test test\coding_workbench_controller_test.dart -r expanded --name "session|conversation route|workbench view model"
flutter test test\widget_test.dart -r expanded --name "diagnostics|run detail|adapter picker|opening coding tab|coding workbench|workspace"
Set-Location ..
rg "services/daemon_client|DaemonClient" mobile/lib/src/ui/main_route_overlay.dart mobile/lib/src/ui/features/diagnostics mobile/lib/src/ui/features/run_detail -n
rg "src/features|src/widgets|src/theme|src/state" mobile/lib mobile/test -n
git ls-files mobile/lib/src/features mobile/lib/src/state mobile/lib/src/theme mobile/lib/src/widgets
git status --short
```

Expected:

```text
architecture checker passes with only allowed UI DaemonClient boundary imports
analyzer passes
targeted Flutter tests pass
no direct DaemonClient in overlay/diagnostics/run_detail
no retired-root imports
no tracked files under retired roots
git status shows only intentional changes or is clean after commits
```

Fix verification fallout inside the slice that introduced it. Do not add a standalone final-fix commit unless there is an actual scoped fix to commit.
