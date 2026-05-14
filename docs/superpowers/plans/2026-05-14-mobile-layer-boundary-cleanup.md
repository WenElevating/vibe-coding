# Mobile Layer Boundary Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten the Flutter mobile layer boundaries from `docs/superpowers/specs/2026-05-14-mobile-layer-boundary-cleanup-design.md` without changing visible workbench behavior.

**Architecture:** Move pure connection config models into `src/domain`, route feature behavior through repositories or narrow feature dependencies, and turn the architecture checker into an explicit guardrail. Keep `DaemonClient` construction in app/shell composition for now, but remove it from the targeted ViewModel/workbench/workspace-picker surfaces.

**Tech Stack:** Flutter/Dart mobile app, existing `ChangeNotifier` ViewModels, existing repository interfaces, existing `tool/check_architecture_imports.dart`, no new runtime dependencies.

---

## File Structure

- Create `mobile/lib/src/domain/models/daemon_connection_config.dart`: pure daemon connection config model, normalization helpers, proxy mode enum, and validation exception.
- Delete `mobile/lib/src/services/daemon_connection_config.dart`: old infrastructure path for pure config model after every import is moved.
- Modify `mobile/tool/check_architecture_imports.dart`: hard-fail domain imports from `src/services/`; report UI direct `DaemonClient` imports as migration debt.
- Modify `mobile/lib/src/ui/view_models/main_tabs_view_model.dart`: depend on `AdapterRepository` instead of `DaemonClient`.
- Modify `mobile/lib/src/ui/main_tabs_page.dart`: keep shell-level client ownership, create connected repositories and workbench dependencies, and pass repository-backed dependencies down.
- Modify `mobile/lib/src/ui/pages/coding/coding_page.dart`: remove `DaemonClient` and `AppDependencies` parameters; receive `WorkbenchDependencies`.
- Modify `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`: remove `DaemonClient` parameter and concrete Sherpa service import.
- Modify `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`: add `SpeechInputServiceBuilder`.
- Modify `mobile/lib/src/services/speech_input_contract.dart`: add the builder typedef.
- Modify `mobile/lib/src/app/app_dependencies.dart`: wire `AdapterRepository`, `WorkbenchDependencies`, and `SpeechInputServiceBuilder` from the composition root.
- Modify `mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart`: remove the unused direct-client `WorkspacePickerSheet` and direct `DirectoryBrowserSheet` constructor.
- Modify tests under `mobile/test/`: update connection config imports, add focused `MainTabsViewModel` tests, and keep widget tests aligned with the changed constructors.
- Modify `mobile/lib/src/testing/debug_helpers.dart`: update test/debug `WorkbenchDependencies` construction after adding the speech builder.

Before every task commit, run `git status --short` and `git diff --cached --name-only`. The commit must include only the files named by that task; leave unrelated user or generated changes unstaged.

---

## Task 1: Move Connection Config Model To Domain

**Files:**
- Create: `mobile/lib/src/domain/models/daemon_connection_config.dart`
- Delete: `mobile/lib/src/services/daemon_connection_config.dart`
- Modify: `mobile/lib/src/domain/models/connected_app_session.dart`
- Modify: `mobile/lib/src/domain/use_cases/connect_to_daemon_use_case.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_connection_config_repository.dart`
- Modify: `mobile/lib/src/services/daemon_connection_config_store.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart`
- Modify: connection/settings UI imports that currently reference `src/services/daemon_connection_config.dart`
- Test: `mobile/test/daemon_connection_config_test.dart`
- Test: `mobile/test/daemon_connection_config_store_test.dart`
- Test: `mobile/test/daemon_connection_workflow_test.dart`
- Test: `mobile/test/daemon_connection_controller_test.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Move the pure config code into domain**

Create `mobile/lib/src/domain/models/daemon_connection_config.dart` with the same pure model and helper behavior currently in `mobile/lib/src/services/daemon_connection_config.dart`:

```dart
enum DaemonProxyMode {
  direct,
  system,
  manual;

  String get storageValue => switch (this) {
        DaemonProxyMode.direct => 'direct',
        DaemonProxyMode.system => 'system',
        DaemonProxyMode.manual => 'manual',
      };

  String get label => switch (this) {
        DaemonProxyMode.direct => 'Direct',
        DaemonProxyMode.system => 'System proxy',
        DaemonProxyMode.manual => 'Manual proxy',
      };

  static DaemonProxyMode fromStorageValue(String? value) => switch (value) {
        'system' => DaemonProxyMode.system,
        'manual' => DaemonProxyMode.manual,
        _ => DaemonProxyMode.direct,
      };
}

class DaemonConnectionConfig {
  const DaemonConnectionConfig({
    required this.addressInput,
    required this.proxyMode,
    required this.manualProxyInput,
  });

  static const fallback = DaemonConnectionConfig(
    addressInput: '127.0.0.1:4317',
    proxyMode: DaemonProxyMode.direct,
    manualProxyInput: '',
  );

  final String addressInput;
  final DaemonProxyMode proxyMode;
  final String manualProxyInput;

  DaemonConnectionConfig copyWith({
    String? addressInput,
    DaemonProxyMode? proxyMode,
    String? manualProxyInput,
  }) =>
      DaemonConnectionConfig(
        addressInput: addressInput ?? this.addressInput,
        proxyMode: proxyMode ?? this.proxyMode,
        manualProxyInput: manualProxyInput ?? this.manualProxyInput,
      );
}

class NormalizedDaemonAddress {
  const NormalizedDaemonAddress({
    required this.input,
    required this.uri,
  });

  final String input;
  final Uri uri;
}

class DaemonConnectionConfigException implements Exception {
  const DaemonConnectionConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

NormalizedDaemonAddress normalizeDaemonAddress(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const DaemonConnectionConfigException('Enter a daemon address.');
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final parsed = Uri.tryParse(withScheme);
  if (parsed == null || parsed.host.trim().isEmpty) {
    throw const DaemonConnectionConfigException(
        'Enter a valid daemon address.');
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    throw const DaemonConnectionConfigException(
        'Daemon address must use http or https.');
  }

  final uri = parsed.hasPort
      ? parsed
      : parsed.replace(port: parsed.scheme == 'https' ? 443 : 4317);
  return NormalizedDaemonAddress(input: trimmed, uri: uri);
}

Uri normalizeManualProxy(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const DaemonConnectionConfigException('Enter a proxy address.');
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final parsed = Uri.tryParse(withScheme);
  if (parsed == null || parsed.host.trim().isEmpty || !parsed.hasPort) {
    throw const DaemonConnectionConfigException(
        'Enter a valid proxy host and port.');
  }
  if (parsed.scheme != 'http') {
    throw const DaemonConnectionConfigException('Manual proxy must use http.');
  }
  return parsed;
}

bool isLocalOrPrivateDaemonHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized == '::1') return true;
  final parts = normalized.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    octets.add(value);
  }
  if (octets.first == 127) return true;
  if (octets.first == 10) return true;
  if (octets.first == 192 && octets[1] == 168) return true;
  if (octets.first == 172 && octets[1] >= 16 && octets[1] <= 31) {
    return true;
  }
  return false;
}
```

- [ ] **Step 2: Update domain imports first**

Change `mobile/lib/src/domain/models/connected_app_session.dart`:

```dart
import 'daemon_connection_config.dart';
import 'daemon_initial_data.dart';
```

Change `mobile/lib/src/domain/use_cases/connect_to_daemon_use_case.dart`:

```dart
import '../models/connected_app_session.dart';
import '../models/daemon_connection_config.dart';
```

- [ ] **Step 3: Update data, service, and workflow imports**

Use direct import replacements, not a compatibility barrel:

```text
mobile/lib/src/data/repositories/daemon_connection_config_repository.dart
  from: ../../services/daemon_connection_config.dart
  to:   ../../domain/models/daemon_connection_config.dart

mobile/lib/src/services/daemon_connection_config_store.dart
  from: daemon_connection_config.dart
  to:   ../domain/models/daemon_connection_config.dart

mobile/lib/src/services/daemon_client.dart
  from: daemon_connection_config.dart
  to:   ../domain/models/daemon_connection_config.dart

mobile/lib/src/workflows/connection/daemon_connection_workflow.dart
  from: ../../services/daemon_connection_config.dart
  to:   ../../domain/models/daemon_connection_config.dart
```

- [ ] **Step 4: Update UI and test imports**

Replace package imports in tests:

```dart
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
```

Replace relative UI imports:

```text
mobile/lib/src/ui/mobile_connection_page.dart
  import '../domain/models/daemon_connection_config.dart';

mobile/lib/src/ui/main_tabs_page.dart
  import '../domain/models/daemon_connection_config.dart';

mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart
  import '../../../../domain/models/daemon_connection_config.dart';

mobile/lib/src/ui/features/settings/settings_page.dart
  import '../../../domain/models/daemon_connection_config.dart';

mobile/lib/src/ui/pages/settings_page.dart
  import '../../domain/models/daemon_connection_config.dart';
```

- [ ] **Step 5: Delete the old services file and scan for aliases**

Delete `mobile/lib/src/services/daemon_connection_config.dart`.

Run:

```powershell
rg "services/daemon_connection_config|src/services/daemon_connection_config|daemon_connection_config.dart" mobile/lib mobile/test -n
```

Expected: every remaining `daemon_connection_config.dart` import points to `src/domain/models/daemon_connection_config.dart`, or is a relative import to that domain file. There must be no file at `mobile/lib/src/services/daemon_connection_config.dart`.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
cd mobile && flutter test test/daemon_connection_config_test.dart test/daemon_connection_config_store_test.dart test/daemon_connection_workflow_test.dart test/daemon_connection_controller_test.dart -r expanded
```

Expected: all listed tests pass. Failures should be import-path or constructor issues only; fix those before continuing.

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/domain/models/daemon_connection_config.dart mobile/lib/src/domain/models/connected_app_session.dart mobile/lib/src/domain/use_cases/connect_to_daemon_use_case.dart mobile/lib/src/data/repositories/daemon_connection_config_repository.dart mobile/lib/src/services/daemon_connection_config_store.dart mobile/lib/src/services/daemon_client.dart mobile/lib/src/workflows/connection/daemon_connection_workflow.dart mobile/lib/src/ui mobile/test
git add -u mobile/lib/src/services/daemon_connection_config.dart
git commit -m "Move daemon connection config to domain" -m "Constraint: keep connection config pure and update imports directly without a compatibility barrel." -m "Tested: cd mobile && flutter test test/daemon_connection_config_test.dart test/daemon_connection_config_store_test.dart test/daemon_connection_workflow_test.dart test/daemon_connection_controller_test.dart -r expanded"
```

---

## Task 2: Strengthen Architecture Checker

**Files:**
- Modify: `mobile/tool/check_architecture_imports.dart`
- Test: run checker directly

- [ ] **Step 1: Add UI direct client debt collection**

In `main`, add a new collection next to `migrationDebt`:

```dart
  final violations = <String>[];
  final migrationDebt = <String>[];
  final uiDaemonClientDebt = <String>[];
```

After `_checkServicesRule(...)`, call a new UI rule:

```dart
      _checkUiDaemonClientRule(
        relativeFile: relativeFile,
        uri: uri,
        normalizedTarget: normalizedTarget,
        lineNumber: lineNumber,
        uiDaemonClientDebt: uiDaemonClientDebt,
      );
```

After the `Allowed migration debt` output block, print the UI report:

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

- [ ] **Step 2: Make domain-to-services a hard failure**

Replace the `daemon_client.dart`-specific domain rule with a general services rule:

```dart
String? _domainRule(String uri, String normalizedTarget) {
  if (uri.startsWith('package:flutter/')) {
    return 'domain must not import Flutter';
  }
  if (uri.startsWith('package:http/')) return 'domain must not import HTTP';
  if (uri.startsWith('package:shared_preferences/')) {
    return 'domain must not import SharedPreferences';
  }
  if (_targetsRoot(normalizedTarget, 'src/ui/')) {
    return 'domain must not import UI';
  }
  if (_targetsRoot(normalizedTarget, 'src/services/')) {
    return 'domain must not import services';
  }
  return null;
}
```

- [ ] **Step 3: Add the UI direct-client warning rule**

Add this function below `_checkServicesRule`:

```dart
void _checkUiDaemonClientRule({
  required String relativeFile,
  required String uri,
  required String normalizedTarget,
  required int lineNumber,
  required List<String> uiDaemonClientDebt,
}) {
  if (!relativeFile.startsWith('lib/src/ui/')) return;
  if (!_targetsRoot(normalizedTarget, 'src/services/daemon_client.dart')) {
    return;
  }
  uiDaemonClientDebt.add(
    '$relativeFile:$lineNumber UI imports concrete DaemonClient ($uri)',
  );
}
```

- [ ] **Step 4: Run checker before target UI cleanup**

Run:

```powershell
cd mobile && dart run tool/check_architecture_imports.dart
```

Expected:

```text
Architecture import check
Migration-only import/export counts:
  src/features/ 0
  src/widgets/ 0
  src/theme/ 0
  src/state/ 0
UI direct DaemonClient imports:
  ...
No forbidden imports found.
```

The UI list may still include `main_tabs_page.dart`, `main_route_overlay.dart`, connection ViewModels, diagnostics/run-detail pages, and any target files not yet cleaned. It must not cause a non-zero exit in this task.

- [ ] **Step 5: Commit**

```powershell
git add mobile/tool/check_architecture_imports.dart
git commit -m "Report remaining UI daemon client imports" -m "Constraint: domain-to-services imports are hard failures; UI direct DaemonClient imports are migration reporting for this pass." -m "Tested: cd mobile && dart run tool/check_architecture_imports.dart"
```

---

## Task 3: Convert MainTabsViewModel To AdapterRepository

**Files:**
- Modify: `mobile/lib/src/ui/view_models/main_tabs_view_model.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Create: `mobile/test/main_tabs_view_model_test.dart`
- Test: `mobile/test/main_tabs_view_model_test.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add ViewModel tests with a fake repository**

Create `mobile/test/main_tabs_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/view_models/main_tabs_view_model.dart';

void main() {
  test('loads coding adapters through repository once', () async {
    final repository = _FakeAdapterRepository();
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: repository,
    );

    await viewModel.ensureCodingAdaptersLoaded();
    await viewModel.ensureCodingAdaptersLoaded();

    expect(repository.listAdaptersCalls, 1);
    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
    expect(viewModel.data.adapters.map((adapter) => adapter.adapter),
        const <String>['codex']);
  });

  test('reports adapter load failures and retries', () async {
    final repository = _FakeAdapterRepository()..failNext = true;
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: repository,
    );

    await viewModel.ensureCodingAdaptersLoaded();

    expect(viewModel.adapterLoadState, CodingAdapterLoadState.failed);
    expect(viewModel.adapterLoadError, isA<StateError>());

    await viewModel.ensureCodingAdaptersLoaded();

    expect(repository.listAdaptersCalls, 2);
    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
  });
}

class _FakeAdapterRepository implements AdapterRepository {
  int listAdaptersCalls = 0;
  bool failNext = false;

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    listAdaptersCalls++;
    if (failNext) {
      failNext = false;
      throw StateError('adapter load failed');
    }
    return const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ];
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  @override
  Future<List<ExtensionSummary>> listExtensions() async =>
      const <ExtensionSummary>[];

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];
}

AppSnapshot _snapshot() => AppSnapshot(
      health: const DaemonHealth(
        status: 'ok',
        daemonVersion: '1.0.0',
        mode: 'lan',
        lanMode: true,
        bindAddress: '127.0.0.1',
        port: 4317,
        security: <String, Object?>{},
      ),
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(
          id: 'workspace_1',
          name: 'Workspace',
          path: r'D:\workspace',
        ),
      ],
      workspace: const WorkspaceSummary(
        id: 'workspace_1',
        name: 'Workspace',
        path: r'D:\workspace',
      ),
      overview: const ProjectOverview(
        workspaceId: 'workspace_1',
        name: 'Workspace',
        path: r'D:\workspace',
        fileCount: 0,
        codeLineCount: 0,
        symbolCount: 0,
        analysisScore: 0,
        recentFiles: <RecentFileSummary>[],
      ),
      adapters: const <AdapterStatus>[],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: null,
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
        workspaceId: 'workspace_1',
        root: '',
        entries: <FileTreeEntry>[],
      ),
      diagnostics: const CodeDiagnosticsSummary(
        workspaceId: 'workspace_1',
        available: false,
        diagnostics: <CodeDiagnostic>[],
      ),
      extensions: const <ExtensionSummary>[],
    );
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
cd mobile && flutter test test/main_tabs_view_model_test.dart -r expanded
```

Expected: compile failure because `MainTabsViewModel` does not yet accept `adapterRepository`.

- [ ] **Step 3: Update MainTabsViewModel**

In `mobile/lib/src/ui/view_models/main_tabs_view_model.dart`, replace the concrete client dependency with `AdapterRepository`:

```dart
import '../../domain/repositories/adapter_repository.dart';
```

Constructor and field:

```dart
  MainTabsViewModel({
    required AppSnapshot initialData,
    required AdapterRepository adapterRepository,
  })  : _data = initialData,
        _adapterRepository = adapterRepository;

  AdapterRepository _adapterRepository;
```

Reset method:

```dart
  void resetForNewClient({
    required AdapterRepository adapterRepository,
    required AppSnapshot data,
  }) {
    _adapterRepository = adapterRepository;
    _data = data;
    _adapterLoadState = CodingAdapterLoadState.idle;
    _adapterLoadFuture = null;
    _adapterLoadError = null;
    notifyListeners();
    unawaited(ensureCodingAdaptersLoaded());
  }
```

Load method:

```dart
  Future<void> _loadCodingAdapters() async {
    try {
      final adapters = await _adapterRepository.listAdapters();
      if (_disposed) return;
      _data = _snapshotWithAdapters(_data, adapters);
      _adapterLoadState = CodingAdapterLoadState.loaded;
      _adapterLoadError = null;
      _adapterLoadFuture = null;
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      _adapterLoadState = CodingAdapterLoadState.failed;
      _adapterLoadError = error;
      _adapterLoadFuture = null;
      notifyListeners();
    }
  }
```

- [ ] **Step 4: Update MainTabsPage repository creation**

In `mobile/lib/src/ui/main_tabs_page.dart`, import the connected dependency type through the existing app dependency file and store it:

```dart
class _MainTabsPageState extends State<MainTabsPage> {
  late MainTabsViewModel _viewModel;
  late ConnectedDataDependencies _connectedData;
  final _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();
```

Initialize it before the ViewModel:

```dart
  @override
  void initState() {
    super.initState();
    _connectedData = widget.dependencies.data.forDaemonClient(widget.client);
    _viewModel = MainTabsViewModel(
      initialData: widget.data,
      adapterRepository: _connectedData.adapterRepository,
    );
    unawaited(_viewModel.ensureCodingAdaptersLoaded());
  }
```

Reset it on client change:

```dart
    if (oldWidget.client != widget.client) {
      _connectedData = widget.dependencies.data.forDaemonClient(widget.client);
      _viewModel.resetForNewClient(
        adapterRepository: _connectedData.adapterRepository,
        data: widget.data,
      );
      return;
    }
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
cd mobile && flutter test test/main_tabs_view_model_test.dart -r expanded
cd mobile && flutter test test/widget_test.dart -r expanded --name "connected app preloads adapters|coding waits for pending adapter preload|coding adapter preload failure can retry"
```

Expected: all tests pass.

- [ ] **Step 6: Run a direct import scan**

Run:

```powershell
rg "services/daemon_client|DaemonClient" mobile/lib/src/ui/view_models/main_tabs_view_model.dart -n
```

Expected: no output.

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/ui/view_models/main_tabs_view_model.dart mobile/lib/src/ui/main_tabs_page.dart mobile/test/main_tabs_view_model_test.dart mobile/test/widget_test.dart
git commit -m "Load coding adapters through repository" -m "Constraint: keep MainTabsViewModel presentation-only and fake AdapterRepository in focused tests." -m "Tested: cd mobile && flutter test test/main_tabs_view_model_test.dart -r expanded" -m "Tested: cd mobile && flutter test test/widget_test.dart -r expanded --name \"connected app preloads adapters|coding waits for pending adapter preload|coding adapter preload failure can retry\""
```

---

## Task 4: Remove Workbench And CodingPage DaemonClient Parameters

**Files:**
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/pages/coding/coding_page.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Move workbench dependency ownership into MainTabsPage**

In `mobile/lib/src/ui/main_tabs_page.dart`, add a field:

```dart
  late WorkbenchDependencies _workbenchDependencies;
```

Initialize and dispose it:

```dart
    _connectedData = widget.dependencies.data.forDaemonClient(widget.client);
    _workbenchDependencies =
        widget.dependencies.features.createWorkbenchDependencies(widget.client);
```

```dart
  @override
  void dispose() {
    _workbenchDependencies.asrModelManager.dispose();
    _viewModel.dispose();
    super.dispose();
  }
```

On client change, dispose and recreate:

```dart
    if (oldWidget.client != widget.client) {
      _workbenchDependencies.asrModelManager.dispose();
      _connectedData = widget.dependencies.data.forDaemonClient(widget.client);
      _workbenchDependencies =
          widget.dependencies.features.createWorkbenchDependencies(widget.client);
      _viewModel.resetForNewClient(
        adapterRepository: _connectedData.adapterRepository,
        data: widget.data,
      );
      return;
    }
```

- [ ] **Step 2: Pass WorkbenchDependencies into CodingPage**

Update `_buildCodingTab()`:

```dart
      return CodingPage(
        data: _viewModel.data,
        workbenchDependencies: _workbenchDependencies,
        workbenchKey: _codingWorkbenchKey,
        onBack: () => _viewModel.selectTab(0),
        onSessionListChanged: _viewModel.reportSessionListOpen,
        openSessionListRequest: _viewModel.openSessionListRequest,
        streamOutput: _viewModel.streamOutput,
        expandThinking: _viewModel.expandThinking,
        permissionMode: _viewModel.permissionMode,
      );
```

- [ ] **Step 3: Convert CodingPage into a stateless dependency pass-through**

Replace `mobile/lib/src/ui/pages/coding/coding_page.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../../shell/app_snapshot.dart';
import '../../features/workbench/workbench.dart';

class CodingPage extends StatelessWidget {
  const CodingPage({
    super.key,
    required this.data,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.workbenchDependencies,
    required this.workbenchKey,
    required this.streamOutput,
    required this.expandThinking,
    required this.permissionMode,
  });

  final AppSnapshot data;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final WorkbenchDependencies workbenchDependencies;
  final GlobalKey<CodingWorkbenchPageState> workbenchKey;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  Widget build(BuildContext context) {
    return CodingWorkbenchPage(
      key: workbenchKey,
      data: data,
      onBack: onBack,
      onSessionListChanged: onSessionListChanged,
      openSessionListRequest: openSessionListRequest,
      streamOutput: streamOutput,
      expandThinking: expandThinking,
      permissionMode: permissionMode,
      dependencies: workbenchDependencies,
    );
  }
}
```

- [ ] **Step 4: Remove CodingWorkbenchPage client parameter**

In `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`, delete:

```dart
import '../../../services/daemon_client.dart';
```

Delete from the constructor and fields:

```dart
required this.client,
final DaemonClient client;
```

- [ ] **Step 5: Run focused tests and import scans**

Run:

```powershell
cd mobile && flutter test test/widget_test.dart -r expanded --name "opening coding tab|coding composer|coding workbench|conversation|returning to coding tab|system back"
rg "services/daemon_client|DaemonClient" mobile/lib/src/ui/pages/coding mobile/lib/src/ui/features/workbench/coding_workbench_page.dart -n
```

Expected: tests pass and the `rg` command prints no matches.

- [ ] **Step 6: Commit**

```powershell
git add mobile/lib/src/ui/main_tabs_page.dart mobile/lib/src/ui/pages/coding/coding_page.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/test/widget_test.dart
git commit -m "Remove workbench daemon client parameters" -m "Constraint: keep DaemonClient at shell composition and pass feature dependencies into CodingPage." -m "Tested: cd mobile && flutter test test/widget_test.dart -r expanded --name \"opening coding tab|coding composer|coding workbench|conversation|returning to coding tab|system back\""
```

---

## Task 5: Add SpeechInputServiceBuilder To WorkbenchDependencies

**Files:**
- Modify: `mobile/lib/src/services/speech_input_contract.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/testing/debug_helpers.dart`
- Test: voice and workbench widget tests

- [ ] **Step 1: Add the typedef to the speech contract**

In `mobile/lib/src/services/speech_input_contract.dart`, add below `SpeechInputService`:

```dart
typedef SpeechInputServiceBuilder = SpeechInputService Function(
  String modelDirectory,
);
```

- [ ] **Step 2: Add builder to WorkbenchDependencies**

Update `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`:

```dart
import '../../../services/speech_input_contract.dart';
```

Constructor and field:

```dart
  const WorkbenchDependencies({
    required this.asrModelManager,
    required this.conversationRepository,
    required this.diagnosticsRepository,
    required this.runRepository,
    required this.workspaceRepository,
    required this.speechInputServiceBuilder,
  });

  final SpeechInputServiceBuilder speechInputServiceBuilder;
```

- [ ] **Step 3: Wire production builder in AppDependencies**

In `mobile/lib/src/app/app_dependencies.dart`, add:

```dart
import '../services/speech_input_service.dart';
```

When constructing `WorkbenchDependencies`, add:

```dart
            speechInputServiceBuilder: (modelDirectory) =>
                SherpaSpeechInputService(modelDirectory: modelDirectory),
```

- [ ] **Step 4: Use the builder in CodingWorkbenchPage**

In `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`, replace:

```dart
import '../../../services/speech_input_service.dart';
```

with:

```dart
import '../../../services/speech_input_contract.dart';
```

Replace concrete construction in `_startVoiceInput()`:

```dart
      final nextService =
          widget.dependencies.speechInputServiceBuilder(modelDirectory);
      _ownedSpeechInputService = nextService;
      _voiceInput.updateService(nextService);
```

- [ ] **Step 5: Update debug/test dependency construction**

Every test/debug `WorkbenchDependencies(` construction must pass a builder. For debug helpers, use:

```dart
speechInputServiceBuilder: (_) => const DisabledSpeechInputService(),
```

If `const DisabledSpeechInputService()` cannot satisfy a non-const closure context in a given file, use:

```dart
speechInputServiceBuilder: (modelDirectory) =>
    const DisabledSpeechInputService(),
```

- [ ] **Step 6: Run focused tests and import scan**

Run:

```powershell
cd mobile && flutter test test/voice_input_controller_test.dart test/voice_input_view_model_test.dart test/speech_input_service_test.dart -r expanded
cd mobile && flutter test test/widget_test.dart -r expanded --name "coding composer|coding workbench|conversation"
rg "SherpaSpeechInputService|speech_input_service.dart" mobile/lib/src/ui/features/workbench/coding_workbench_page.dart -n
```

Expected: tests pass and the `rg` command prints no matches.

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/services/speech_input_contract.dart mobile/lib/src/app/app_dependencies.dart mobile/lib/src/ui/features/workbench/workbench_dependencies.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/src/testing/debug_helpers.dart mobile/test
git commit -m "Inject workbench speech input builder" -m "Constraint: keep concrete Sherpa speech service construction outside the workbench page." -m "Tested: cd mobile && flutter test test/voice_input_controller_test.dart test/voice_input_view_model_test.dart test/speech_input_service_test.dart -r expanded" -m "Tested: cd mobile && flutter test test/widget_test.dart -r expanded --name \"coding composer|coding workbench|conversation\""
```

---

## Task 6: Remove Legacy Workspace Picker DaemonClient Path

**Files:**
- Modify: `mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Prove direct-client picker is unused**

Run:

```powershell
rg "WorkspacePickerSheet|DirectoryBrowserSheet\\(" mobile/lib mobile/test -n
```

Expected before deletion: matches only in `workspace_picker_sheet.dart` for the class definition and `DirectoryBrowserSheet({required DaemonClient client})` constructor. If a production caller appears, convert that caller to `AddWorkspaceSheet` or `DirectoryBrowserSheet.forWorkspaceRepository(...)` before deleting the direct-client path.

- [ ] **Step 2: Delete WorkspacePickerSheet and its state**

In `mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart`, delete the unused `WorkspacePickerSheet` class and `_WorkspacePickerSheetState` class. The active creation path should remain:

```dart
class AddWorkspaceSheet extends StatefulWidget {
  const AddWorkspaceSheet({super.key, required this.workspaceRepository});

  final WorkspaceRepository workspaceRepository;
```

- [ ] **Step 3: Delete the direct DirectoryBrowserSheet constructor**

Remove:

```dart
  DirectoryBrowserSheet({super.key, required DaemonClient client})
      : _listFileSystemRoots = client.listFileSystemRoots,
        _listDirectory = client.listDirectory;
```

Keep only:

```dart
  DirectoryBrowserSheet.forWorkspaceRepository({
    super.key,
    required WorkspaceRepository repository,
  })  : _listFileSystemRoots = repository.listFileSystemRoots,
        _listDirectory = repository.listDirectory;
```

Then remove:

```dart
import '../../../services/daemon_client.dart';
```

- [ ] **Step 4: Run tests and import scan**

Run:

```powershell
cd mobile && flutter test test/widget_test.dart -r expanded --name "workspace|coding workbench|opening coding tab"
rg "WorkspacePickerSheet|DirectoryBrowserSheet\\(|services/daemon_client|DaemonClient" mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart -n
```

Expected: tests pass. The `rg` command may print `DirectoryBrowserSheet.forWorkspaceRepository`, but must not print `WorkspacePickerSheet`, `services/daemon_client`, or `DaemonClient`.

- [ ] **Step 5: Commit**

```powershell
git add mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart mobile/test/widget_test.dart
git commit -m "Remove direct workspace picker daemon client path" -m "Constraint: keep workspace browsing and creation repository-backed." -m "Tested: cd mobile && flutter test test/widget_test.dart -r expanded --name \"workspace|coding workbench|opening coding tab\""
```

---

## Task 7: Final Architecture Verification

**Files:**
- Modify only if failures reveal missed imports: files touched in Tasks 1-6
- No implementation files should be changed for unrelated cleanup

- [ ] **Step 1: Run final architecture checker**

Run:

```powershell
cd mobile && dart run tool/check_architecture_imports.dart
```

Expected:

```text
Architecture import check
Migration-only import/export counts:
  src/features/ 0
  src/widgets/ 0
  src/theme/ 0
  src/state/ 0
UI direct DaemonClient imports:
  lib/src/ui/main_tabs_page.dart:...
  lib/src/ui/main_route_overlay.dart:...
  lib/src/ui/features/connection/view_models/daemon_connection_controller.dart:...
  lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart:...
  lib/src/ui/features/diagnostics/diagnostics_page.dart:...
  lib/src/ui/features/run_detail/run_detail_page.dart:...
No forbidden imports found.
```

The report must not include:

```text
lib/src/ui/view_models/main_tabs_view_model.dart
lib/src/ui/pages/coding/coding_page.dart
lib/src/ui/features/workbench/coding_workbench_page.dart
lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart
```

- [ ] **Step 2: Run Dart analysis**

Run:

```powershell
cd mobile && dart analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run targeted regression tests**

Run:

```powershell
cd mobile && flutter test test/daemon_connection_config_test.dart test/daemon_connection_config_store_test.dart test/daemon_connection_workflow_test.dart test/daemon_connection_controller_test.dart -r expanded
cd mobile && flutter test test/main_tabs_view_model_test.dart -r expanded
cd mobile && flutter test test/coding_workbench_controller_test.dart -r expanded
cd mobile && flutter test test/voice_input_controller_test.dart test/voice_input_view_model_test.dart test/speech_input_service_test.dart -r expanded
cd mobile && flutter test test/widget_test.dart -r expanded --name "adapter picker|opening coding tab|coding composer|coding workbench|conversation|workspace|system back|returning to coding tab"
```

Expected: all targeted tests pass. If this environment hangs on a broad Flutter command, rerun the smallest failing target with `-r expanded` and record the exact command and last visible output before changing code.

- [ ] **Step 4: Scan for forbidden aliases and target imports**

Run:

```powershell
rg "services/daemon_connection_config|src/services/daemon_connection_config" mobile/lib mobile/test -n
rg "services/daemon_client|DaemonClient" mobile/lib/src/ui/view_models/main_tabs_view_model.dart mobile/lib/src/ui/pages/coding mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart -n
rg "SherpaSpeechInputService|speech_input_service.dart" mobile/lib/src/ui/features/workbench/coding_workbench_page.dart -n
```

Expected: all three commands print no matches.

- [ ] **Step 5: Commit final verification fixes if any**

If steps 1-4 required small missed-import fixes, commit them:

```powershell
git add mobile
git commit -m "Complete mobile layer boundary cleanup verification" -m "Constraint: only final missed imports and verification fixes." -m "Tested: cd mobile && dart run tool/check_architecture_imports.dart" -m "Tested: cd mobile && dart analyze" -m "Tested: targeted Flutter tests listed in the implementation plan"
```

If no files changed during Task 7, do not create an empty commit. Report the verification evidence in the final handoff.
