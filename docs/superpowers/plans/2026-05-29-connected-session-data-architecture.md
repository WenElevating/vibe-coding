# Connected Session Data Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move connected-session runtime data behind per-resource repositories and use cases so connected UI paths stop reading `DaemonInitialData` or runtime `AppSnapshot` as business state.

**Architecture:** `AppDependencies` remains the composition root: it constructs repositories, use cases, session scope, and UI ViewModels. `ConnectedSessionScope` owns repositories and use cases only; it does not contain feature factories or ViewModels. Resource state lives in focused repositories, while `OpenWorkspaceUseCase` owns the ordered workspace-bootstrap update flow.

**Tech Stack:** Flutter/Dart, existing `ChangeNotifier` repositories and ViewModels, existing daemon `DaemonClient`, existing architecture import checker, no new runtime dependency package.

---

## File Structure

- Create `mobile/lib/src/data/repositories/cli_adapter_repository.dart`: adapter probe source of truth.
- Create `mobile/lib/src/data/repositories/command_catalog_repository.dart`: shortcuts, command templates, and extensions source of truth.
- Create `mobile/lib/src/data/repositories/bootstrap_hydration.dart`: narrow bootstrap hydration interfaces used by workspace workflows.
- Modify `mobile/lib/src/data/repositories/cached_conversation_repository.dart`: add bootstrap replacement plus `loadedWorkspaceId`.
- Modify `mobile/lib/src/data/repositories/cached_run_repository.dart`: add bootstrap replacement plus `loadedWorkspaceId`; queue stays coupled here for this migration slice.
- Modify `mobile/lib/src/data/repositories/workspace_repository.dart`: allow bootstrap workspace catalog hydration with no selected workspace.
- Modify `mobile/lib/src/data/repositories/daemon_workspace_repository.dart`: retain workspace list when bootstrap has `workspace: null`.
- Create `mobile/lib/src/app/connected_session_scope.dart`: repositories plus use cases only.
- Modify `mobile/lib/src/app/app_dependencies.dart`: build `ConnectedSessionScope`, hydrate repositories from connection bootstrap, and create feature ViewModels from scope repositories.
- Modify `mobile/lib/src/ui/features/connection/views/mobile_connection_gate.dart`: pass connection bootstrap data into `AppDependencies.createMainTabsDependencies`.
- Modify `mobile/lib/src/ui/main_tabs_page.dart`: remove resource hydration from UI, remove startup Home refresh, use adapter probe repository for Coding gate, and route workspace opening through the use case.
- Modify `mobile/lib/src/ui/main_route_overlay.dart`: build adapters overlay from repositories instead of bootstrap snapshot data.
- Modify `mobile/lib/src/ui/features/adapters/view_models/adapters_view_model.dart`: consume adapter and catalog repositories.
- Modify `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`: use `CliAdapterRepository` for adapter availability.
- Modify `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`: expose workspace-opening state and call `OpenWorkspaceUseCase` for workspace selection.
- Create `mobile/lib/src/workflows/connection/open_workspace_use_case.dart`: load workspace bootstrap and replace workspace-scoped repository data in order.
- Modify tests under `mobile/test/`: add repository bootstrap, adapter split, scope hydration, overlay, Coding gate, Home second-request prevention, and workspace-open coverage.

Run Flutter/Dart commands with the mirror environment:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
```

When a Flutter/Dart command times out on the first attempt, stop automatic retries and report the exact command.

---

## Task 1: Add Bootstrap State To Workspace-Scoped Repositories

**Files:**
- Create: `mobile/lib/src/data/repositories/bootstrap_hydration.dart`
- Modify: `mobile/lib/src/data/repositories/cached_conversation_repository.dart`
- Modify: `mobile/lib/src/data/repositories/cached_run_repository.dart`
- Modify: `mobile/lib/src/data/repositories/workspace_repository.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_workspace_repository.dart`
- Test: `mobile/test/connected_repository_bootstrap_test.dart`

- [ ] **Step 1: Write failing repository bootstrap tests**

Create `mobile/test/connected_repository_bootstrap_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  test('conversation bootstrap records loaded workspace id', () {
    final repository = CachedConversationRepository(
      delegate: _UnusedConversationRepository(),
    );

    repository.replaceFromBootstrap(
      workspaceId: 'w1',
      conversations: const <ConversationSummary>[_conversation],
    );

    expect(repository.loadedWorkspaceId, 'w1');
    expect(repository.conversations.single.id, 'c1');
    expect(repository.loading, isFalse);
    expect(repository.error, isNull);
  });

  test('run bootstrap records loaded workspace id and queue', () {
    final repository = CachedRunRepository(delegate: _UnusedRunRepository());

    repository.replaceFromBootstrap(
      workspaceId: 'w1',
      runs: const <RunSummary>[_run],
      queue: const <QueueItem>[_queueItem],
    );

    expect(repository.loadedWorkspaceId, 'w1');
    expect(repository.runs.single.id, 'r1');
    expect(repository.queue.single.runId, 'r1');
    expect(repository.loading, isFalse);
    expect(repository.error, isNull);
  });
}

const _conversationCapabilities = ConversationCapabilities(
  longLivedProcess: false,
  waitingInput: false,
  waitingApproval: false,
  resume: false,
  partialOutput: false,
);

const _conversation = ConversationSummary(
  id: 'c1',
  workspaceId: 'w1',
  adapter: 'codex',
  status: 'idle',
  capabilities: _conversationCapabilities,
  createdAt: '2026-05-29T00:00:00.000Z',
  updatedAt: '2026-05-29T00:00:00.000Z',
);

const _run = RunSummary(
  id: 'r1',
  tool: 'codex',
  workspaceId: 'w1',
  status: 'completed',
);

const _queueItem = QueueItem(
  runId: 'r1',
  workspaceId: 'w1',
  position: 1,
  status: 'queued',
  reason: 'waiting',
);

class _UnusedConversationRepository implements ConversationRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedRunRepository implements RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Run the failing test**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\connected_repository_bootstrap_test.dart -r expanded
```

Expected: FAIL with missing `replaceFromBootstrap` and `loadedWorkspaceId` members.

- [ ] **Step 3: Add narrow bootstrap hydration interfaces**

Create `mobile/lib/src/data/repositories/bootstrap_hydration.dart`:

```dart
import '../../models/protocol.dart';

abstract interface class ConversationBootstrapTarget {
  String? get loadedWorkspaceId;

  void replaceFromBootstrap({
    required String workspaceId,
    required List<ConversationSummary> conversations,
  });
}

abstract interface class RunBootstrapTarget {
  String? get loadedWorkspaceId;

  void replaceFromBootstrap({
    required String workspaceId,
    required List<RunSummary> runs,
    required List<QueueItem> queue,
  });
}
```

- [ ] **Step 4: Allow workspace catalog bootstrap without selected workspace**

In `mobile/lib/src/data/repositories/workspace_repository.dart`, change the method signature:

```dart
void applyBootstrapCatalog({
  required WorkspaceSummary? selectedWorkspace,
  required List<WorkspaceSummary> workspaces,
});
```

In `mobile/lib/src/data/repositories/daemon_workspace_repository.dart`, update the implementation so `workspaces` is always applied:

```dart
@override
void applyBootstrapCatalog({
  required WorkspaceSummary? selectedWorkspace,
  required List<WorkspaceSummary> workspaces,
}) {
  if (_disposed) return;
  final nextWorkspaces = <WorkspaceSummary>[
    ...workspaces,
    if (selectedWorkspace != null &&
        !workspaces.any((workspace) => workspace.id == selectedWorkspace.id))
      selectedWorkspace,
  ];
  final nextSelectedWorkspaceId = selectedWorkspace?.id;
  final changed = !_sameWorkspaceCatalog(_workspaces, nextWorkspaces) ||
      _selectedWorkspaceId != nextSelectedWorkspaceId;
  _workspaces = List<WorkspaceSummary>.unmodifiable(nextWorkspaces);
  _selectedWorkspaceId = nextSelectedWorkspaceId;
  if (changed) {
    _notifyListeners();
  }
}
```

- [ ] **Step 5: Add conversation bootstrap replacement**

In `mobile/lib/src/data/repositories/cached_conversation_repository.dart`, add fields near `_loaded`:

```dart
String? _loadedWorkspaceId;
```

Add the getter near `error`:

```dart
String? get loadedWorkspaceId => _loadedWorkspaceId;
```

Update the class declaration:

```dart
class CachedConversationRepository extends ChangeNotifier
    implements ConversationRepository, ConversationBootstrapTarget {
```

Add this method before `listConversations`:

```dart
void replaceFromBootstrap({
  required String workspaceId,
  required List<ConversationSummary> conversations,
}) {
  if (_disposed) return;
  _refreshGeneration++;
  _refreshFuture = null;
  _loading = false;
  _error = null;
  _loadedWorkspaceId = workspaceId;
  final sorted = conversations.toList(growable: false)
    ..sort(_compareByUpdatedAtDescending);
  _conversations = List<ConversationSummary>.unmodifiable(sorted);
  _loaded = true;
  _locallyMutatedConversationIds.clear();
  _notifyIfActive();
}
```

- [ ] **Step 6: Add run bootstrap replacement**

In `mobile/lib/src/data/repositories/cached_run_repository.dart`, add fields near `_loaded`:

```dart
String? _loadedWorkspaceId;
```

Add the getter near `error`:

```dart
String? get loadedWorkspaceId => _loadedWorkspaceId;
```

Update the class declaration:

```dart
class CachedRunRepository extends ChangeNotifier
    implements RunRepository, RunBootstrapTarget {
```

Add this method before `listRuns`:

```dart
void replaceFromBootstrap({
  required String workspaceId,
  required List<RunSummary> runs,
  required List<QueueItem> queue,
}) {
  if (_disposed) return;
  _refreshGeneration++;
  _refreshFuture = null;
  _loading = false;
  _error = null;
  _loadedWorkspaceId = workspaceId;
  _runs = List<RunSummary>.unmodifiable(runs);
  _queue = List<QueueItem>.unmodifiable(queue);
  _loaded = true;
  _locallyMutatedRunIds.clear();
  _notifyIfActive();
}
```

- [ ] **Step 7: Run repository bootstrap tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\connected_repository_bootstrap_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add mobile/lib/src/data/repositories/bootstrap_hydration.dart mobile/lib/src/data/repositories/cached_conversation_repository.dart mobile/lib/src/data/repositories/cached_run_repository.dart mobile/lib/src/data/repositories/workspace_repository.dart mobile/lib/src/data/repositories/daemon_workspace_repository.dart mobile/test/connected_repository_bootstrap_test.dart
git commit -m "Hydrate workspace repositories from bootstrap"
```

---

## Task 2: Split Adapter Probe State From Command Catalog State

**Files:**
- Create: `mobile/lib/src/data/repositories/cli_adapter_repository.dart`
- Create: `mobile/lib/src/data/repositories/command_catalog_repository.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Test: `mobile/test/adapter_resource_state_test.dart`
- Test: `mobile/test/workbench_view_model_repository_state_test.dart`

- [ ] **Step 1: Write failing adapter split tests**

Create `mobile/test/adapter_resource_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  test('adapter probe failure does not set catalog error', () async {
    final delegate = _FakeAdapterRepository()
      ..adapterError = StateError('adapter failed');
    final adapters = CliAdapterRepository(delegate: delegate);
    final catalog = CommandCatalogRepository(delegate: delegate);

    await expectLater(adapters.probe(), throwsA(isA<StateError>()));

    expect(adapters.error, isA<StateError>());
    expect(catalog.error, isNull);
  });

  test('catalog failure does not block loaded adapters', () async {
    final delegate = _FakeAdapterRepository()
      ..extensionError = StateError('extension failed');
    final adapters = CliAdapterRepository(delegate: delegate);
    final catalog = CommandCatalogRepository(delegate: delegate);

    await adapters.probe();
    await expectLater(catalog.load(), throwsA(isA<StateError>()));

    expect(
      adapters.adapters.map((adapter) => adapter.adapter),
      const <String>['codex'],
    );
    expect(adapters.error, isNull);
    expect(catalog.error, isA<StateError>());
  });

  test('bootstrap adapters are available without probing', () {
    final adapters = CliAdapterRepository(delegate: _FakeAdapterRepository());

    adapters.replaceFromBootstrap(const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ]);

    expect(adapters.adapters.single.adapter, 'codex');
    expect(adapters.loading, isFalse);
    expect(adapters.error, isNull);
  });
}

class _FakeAdapterRepository implements AdapterRepository {
  Object? adapterError;
  Object? shortcutError;
  Object? templateError;
  Object? extensionError;

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    final error = adapterError;
    if (error != null) throw error;
    return const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ];
  }

  @override
  Future<List<ShortcutCommand>> listShortcuts() async {
    final error = shortcutError;
    if (error != null) throw error;
    return const <ShortcutCommand>[
      ShortcutCommand(
        id: 'fix',
        label: 'Fix',
        prompt: 'Fix failing tests',
        tool: 'codex',
      ),
    ];
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async {
    final error = templateError;
    if (error != null) throw error;
    return const <CommandTemplate>[
      CommandTemplate(
        id: 'review',
        label: 'Review',
        prompt: 'Review changes',
        requiresApproval: false,
      ),
    ];
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    final error = extensionError;
    if (error != null) throw error;
    return const <ExtensionSummary>[
      ExtensionSummary(
        id: 'github',
        name: 'GitHub',
        version: '1.0.0',
        installed: true,
        status: 'installed',
        description: 'Issue sync',
      ),
    ];
  }
}
```

- [ ] **Step 2: Run the failing adapter split tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\adapter_resource_state_test.dart -r expanded
```

Expected: FAIL because the two new repositories do not exist.

- [ ] **Step 3: Implement `CliAdapterRepository`**

Create `mobile/lib/src/data/repositories/cli_adapter_repository.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';

class CliAdapterRepository extends ChangeNotifier {
  CliAdapterRepository({required AdapterRepository delegate})
      : _delegate = delegate;

  final AdapterRepository _delegate;
  List<AdapterStatus> _adapters = const <AdapterStatus>[];
  bool _loading = false;
  Object? _error;
  Future<void>? _probeFuture;
  int _generation = 0;
  bool _disposed = false;

  List<AdapterStatus> get adapters => List.unmodifiable(_adapters);
  bool get loading => _loading;
  Object? get error => _error;

  Future<List<AdapterStatus>> listAdapters() async {
    await probe();
    return adapters;
  }

  Future<void> probe() {
    final current = _probeFuture;
    if (current != null) return current;
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _notifyIfActive();
    final future = _delegate.listAdapters().then((value) {
      if (_disposed || generation != _generation) return;
      _adapters = List<AdapterStatus>.unmodifiable(value);
    }).catchError((Object error) {
      if (!_disposed && generation == _generation) _error = error;
      throw error;
    }).whenComplete(() {
      if (_disposed || generation != _generation) return;
      _loading = false;
      _probeFuture = null;
      _notifyIfActive();
    });
    _probeFuture = future;
    return future;
  }

  void replaceFromBootstrap(List<AdapterStatus> adapters) {
    if (_disposed) return;
    _generation++;
    _probeFuture = null;
    _loading = false;
    _error = null;
    _adapters = List<AdapterStatus>.unmodifiable(adapters);
    _notifyIfActive();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
```

- [ ] **Step 4: Implement `CommandCatalogRepository`**

Create `mobile/lib/src/data/repositories/command_catalog_repository.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';

class CommandCatalogRepository extends ChangeNotifier {
  CommandCatalogRepository({required AdapterRepository delegate})
      : _delegate = delegate;

  final AdapterRepository _delegate;
  List<ShortcutCommand> _shortcuts = const <ShortcutCommand>[];
  List<CommandTemplate> _templates = const <CommandTemplate>[];
  List<ExtensionSummary> _extensions = const <ExtensionSummary>[];
  bool _loading = false;
  Object? _error;
  Future<void>? _loadFuture;
  int _generation = 0;
  bool _disposed = false;

  List<ShortcutCommand> get shortcuts => List.unmodifiable(_shortcuts);
  List<CommandTemplate> get templates => List.unmodifiable(_templates);
  List<ExtensionSummary> get extensions => List.unmodifiable(_extensions);
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() {
    final current = _loadFuture;
    if (current != null) return current;
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _notifyIfActive();
    late List<ShortcutCommand> shortcuts;
    late List<CommandTemplate> templates;
    late List<ExtensionSummary> extensions;
    final future = Future.wait<void>([
      _delegate.listShortcuts().then((value) => shortcuts = value),
      _delegate.listCommandTemplates().then((value) => templates = value),
      _delegate.listExtensions().then((value) => extensions = value),
    ]).then((_) {
      if (_disposed || generation != _generation) return;
      _shortcuts = List<ShortcutCommand>.unmodifiable(shortcuts);
      _templates = List<CommandTemplate>.unmodifiable(templates);
      _extensions = List<ExtensionSummary>.unmodifiable(extensions);
    }).catchError((Object error) {
      if (!_disposed && generation == _generation) _error = error;
      throw error;
    }).whenComplete(() {
      if (_disposed || generation != _generation) return;
      _loading = false;
      _loadFuture = null;
      _notifyIfActive();
    });
    _loadFuture = future;
    return future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
```

- [ ] **Step 5: Wire split repositories into composition**

In `mobile/lib/src/app/app_dependencies.dart`, import the new repositories and construct them from the same daemon delegate:

```dart
final rawAdapterRepository = DaemonAdapterRepository(client: client);
final cliAdapterRepository = CliAdapterRepository(
  delegate: rawAdapterRepository,
);
final commandCatalogRepository = CommandCatalogRepository(
  delegate: rawAdapterRepository,
);
```

Add both fields to the connected repository holder used by the composition root:

```dart
final CliAdapterRepository cliAdapterRepository;
final CommandCatalogRepository commandCatalogRepository;
```

Update `FeatureDependencies.createWorkbenchDependencies` to pass `cliAdapterRepository` instead of the old broad cached adapter repository.

- [ ] **Step 6: Update Workbench adapter type**

In `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`, replace the adapter field type:

```dart
final CliAdapterRepository adapterRepository;
```

In `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`, replace the constructor parameter and field type:

```dart
required CliAdapterRepository adapterRepository,
```

```dart
final CliAdapterRepository _adapterRepository;
```

The existing Workbench reads `adapters`, listens to repository changes, and calls `listAdapters`; `CliAdapterRepository` provides those exact members without catalog state.

- [ ] **Step 7: Run adapter and workbench tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\adapter_resource_state_test.dart test\workbench_view_model_repository_state_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add mobile/lib/src/data/repositories/cli_adapter_repository.dart mobile/lib/src/data/repositories/command_catalog_repository.dart mobile/lib/src/app/app_dependencies.dart mobile/lib/src/ui/features/workbench/workbench_dependencies.dart mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart mobile/test/adapter_resource_state_test.dart mobile/test/workbench_view_model_repository_state_test.dart
git commit -m "Split adapter probe from command catalog state"
```

---

## Task 3: Add ConnectedSessionScope In The Composition Root

**Files:**
- Create: `mobile/lib/src/app/connected_session_scope.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/test/app_dependencies_test.dart`
- Test: `mobile/test/connected_session_scope_test.dart`

- [ ] **Step 1: Write failing scope tests**

Create `mobile/test/connected_session_scope_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/app/connected_session_scope.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_initial_data.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';

void main() {
  test('main tabs dependencies expose hydrated connected session scope', () {
    final appDependencies = AppDependencies.createDefault();
    final dependencies = appDependencies.createMainTabsDependencies(
      _FakeDaemonClient(),
      initialData: _initialData(),
    );

    final scope = dependencies.sessionScope;
    expect(scope, isA<ConnectedSessionScope>());
    expect(scope.repositories.workspaceRepository.selectedWorkspace?.id, 'w1');
    expect(scope.repositories.conversationRepository.loadedWorkspaceId, 'w1');
    expect(scope.repositories.runRepository.loadedWorkspaceId, 'w1');
    expect(scope.repositories.cliAdapterRepository.adapters.single.adapter,
        'codex');
  });

  test('scope hydrates workspace list when no workspace is selected', () {
    final appDependencies = AppDependencies.createDefault();
    final dependencies = appDependencies.createMainTabsDependencies(
      _FakeDaemonClient(),
      initialData: _initialDataWithoutSelectedWorkspace(),
    );

    final workspaces = dependencies.sessionScope.repositories
        .workspaceRepository.workspaces;
    expect(workspaces.map((workspace) => workspace.id), const <String>['w1']);
    expect(
      dependencies.sessionScope.repositories
          .workspaceRepository.selectedWorkspace,
      isNull,
    );
  });
}

DaemonInitialData _initialData() {
  const workspace = WorkspaceSummary(
    id: 'w1',
    name: 'Workspace',
    path: r'D:\workspace',
  );
  return const DaemonInitialData(
    health: DaemonHealth(
      status: 'ok',
      daemonVersion: 'test',
      mode: 'test',
      lanMode: false,
      bindAddress: '127.0.0.1',
      port: 4317,
      security: <String, Object?>{},
    ),
    workspaces: <WorkspaceSummary>[workspace],
    workspace: workspace,
    adapters: <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ],
    runs: <RunSummary>[],
    conversations: <ConversationSummary>[],
    queue: <QueueItem>[],
  );
}

class _FakeDaemonClient implements DaemonClient {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DaemonInitialData _initialDataWithoutSelectedWorkspace() {
  const workspace = WorkspaceSummary(
    id: 'w1',
    name: 'Workspace',
    path: r'D:\workspace',
  );
  return const DaemonInitialData(
    health: DaemonHealth(
      status: 'ok',
      daemonVersion: 'test',
      mode: 'test',
      lanMode: false,
      bindAddress: '127.0.0.1',
      port: 4317,
      security: <String, Object?>{},
    ),
    workspaces: <WorkspaceSummary>[workspace],
    workspace: null,
    adapters: <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ],
    runs: <RunSummary>[],
    conversations: <ConversationSummary>[],
    queue: <QueueItem>[],
  );
}
```

- [ ] **Step 2: Run the failing scope test**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\connected_session_scope_test.dart -r expanded
```

Expected: FAIL because `ConnectedSessionScope` and the `initialData` parameter are missing.

- [ ] **Step 3: Create scope types**

Create `mobile/lib/src/app/connected_session_scope.dart`:

```dart
import '../data/repositories/cached_conversation_repository.dart';
import '../data/repositories/cached_run_repository.dart';
import '../data/repositories/cli_adapter_repository.dart';
import '../data/repositories/coding_preferences_repository.dart';
import '../data/repositories/command_catalog_repository.dart';
import '../data/repositories/workspace_repository.dart';
import '../domain/repositories/app_update_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/diagnostics_repository.dart';
import '../workflows/connection/open_workspace_use_case.dart';

class ConnectedSessionScope {
  const ConnectedSessionScope({
    required this.repositories,
    required this.useCases,
    Future<void> Function()? closeSession,
  }) : _closeSession = closeSession;

  final ConnectedSessionRepositories repositories;
  final ConnectedSessionUseCases useCases;
  final Future<void> Function()? _closeSession;

  void recordDiagnosticEvent(
    String event,
    Map<String, Object?> metadata, {
    String severity = 'info',
    String? path,
  }) {
    repositories.recordDiagnosticEvent(
      event,
      metadata,
      severity: severity,
      path: path,
    );
  }

  Future<void> dispose() async {
    await _closeSession?.call();
    repositories.workspaceRepository.dispose();
    repositories.cliAdapterRepository.dispose();
    repositories.commandCatalogRepository.dispose();
    repositories.conversationRepository.dispose();
    repositories.runRepository.dispose();
  }
}

class ConnectedSessionRepositories {
  ConnectedSessionRepositories({
    required this.authRepository,
    required this.workspaceRepository,
    required this.conversationRepository,
    required this.runRepository,
    required this.cliAdapterRepository,
    required this.commandCatalogRepository,
    required this.diagnosticsRepository,
    required this.appUpdateRepository,
    required this.codingPreferencesRepository,
    required this.recordDiagnosticEvent,
  });

  final AuthRepository authRepository;
  final WorkspaceRepository workspaceRepository;
  final CachedConversationRepository conversationRepository;
  final CachedRunRepository runRepository;
  final CliAdapterRepository cliAdapterRepository;
  final CommandCatalogRepository commandCatalogRepository;
  final DiagnosticsRepository diagnosticsRepository;
  final AppUpdateRepository appUpdateRepository;
  final CodingPreferencesRepository codingPreferencesRepository;
  final void Function(
    String event,
    Map<String, Object?> metadata, {
    String severity,
    String? path,
  }) recordDiagnosticEvent;
}

class ConnectedSessionUseCases {
  const ConnectedSessionUseCases({
    required this.openWorkspace,
  });

  final OpenWorkspaceUseCase openWorkspace;
}
```

- [ ] **Step 4: Make `AppDependencies` create and hydrate the scope**

Change `AppDependencies.createMainTabsDependencies` to accept bootstrap data:

```dart
MainTabsDependencies createMainTabsDependencies(
  DaemonClient client, {
  required DaemonInitialData initialData,
}) {
  final connectedRepositories = data.forDaemonClient(client);
  final scope = _createConnectedSessionScope(
    client: client,
    repositories: connectedRepositories,
    initialData: initialData,
  );
  return MainTabsDependencies(
    sessionScope: scope,
    codingPreferencesRepository: data.codingPreferencesRepository,
    normalizeCodingPermissionMode:
        CodingPreferencesRepository.normalizePermissionMode,
    workbenchDependencies: features.createWorkbenchDependencies(
      client,
      scope.repositories,
    ),
    featureDependencies: features,
    createAppUpdateViewModel: ({
      required installedVersionCode,
      required installedVersionName,
    }) =>
        features.createAppUpdateViewModel(
      client: client,
      repositories: scope.repositories,
      installedVersionCode: installedVersionCode,
      installedVersionName: installedVersionName,
    ),
  );
}
```

Add this private app-layer hydration helper:

```dart
ConnectedSessionScope _createConnectedSessionScope({
  required DaemonClient client,
  required ConnectedSessionRepositories repositories,
  required DaemonInitialData initialData,
  Future<void> Function()? closeSession,
}) {
  _hydrateConnectedSessionRepositories(
    repositories,
    initialData: initialData,
  );
  return ConnectedSessionScope(
    repositories: repositories,
    useCases: ConnectedSessionUseCases(
      openWorkspace: OpenWorkspaceUseCase(
        loadWorkspaceBootstrap: ({
          required workspaces,
          required workspace,
        }) async =>
            (await loadWorkspaceBootstrap(
          client,
          health: initialData.health,
          workspaces: workspaces,
          workspace: workspace,
        ))
                .toDaemonInitialData(),
        workspaceRepository: repositories.workspaceRepository,
        conversationRepository: repositories.conversationRepository,
        runRepository: repositories.runRepository,
      ),
    ),
    closeSession: closeSession,
  );
}

void _hydrateConnectedSessionRepositories(
  ConnectedSessionRepositories repositories, {
  required DaemonInitialData initialData,
}) {
  final workspace = initialData.workspace;
  repositories.workspaceRepository.applyBootstrapCatalog(
    selectedWorkspace: workspace,
    workspaces: initialData.workspaces,
  );
  repositories.cliAdapterRepository.replaceFromBootstrap(initialData.adapters);
  if (workspace == null) return;
  repositories.conversationRepository.replaceFromBootstrap(
    workspaceId: workspace.id,
    conversations: initialData.conversations,
  );
  repositories.runRepository.replaceFromBootstrap(
    workspaceId: workspace.id,
    runs: initialData.runs,
    queue: initialData.queue,
  );
}
```

Update `MainTabsDependencies` so it stores the scope:

```dart
final ConnectedSessionScope sessionScope;
```

Remove `loadWorkspaceBootstrap` from `MainTabsDependencies`; workspace opening will use `sessionScope.useCases.openWorkspace`.

- [ ] **Step 5: Run scope tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\connected_session_scope_test.dart test\app_dependencies_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add mobile/lib/src/app/connected_session_scope.dart mobile/lib/src/app/app_dependencies.dart mobile/test/connected_session_scope_test.dart mobile/test/app_dependencies_test.dart
git commit -m "Create connected session scope in composition root"
```

---

## Task 4: Move Bootstrap Wiring Out Of MainTabsPage

**Files:**
- Modify: `mobile/lib/src/ui/features/connection/views/mobile_connection_gate.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/test/widget_test.dart`
- Test: `mobile/test/home_view_model_test.dart`

- [ ] **Step 1: Add Home second-request regression test**

In `mobile/test/home_view_model_test.dart`, append:

```dart
test('home renders repository bootstrap data without refresh', () {
  const workspace = WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one');
  const capabilities = ConversationCapabilities(
    longLivedProcess: false,
    waitingInput: false,
    waitingApproval: false,
    resume: false,
    partialOutput: false,
  );
  const conversation = ConversationSummary(
    id: 'c1',
    workspaceId: 'w1',
    adapter: 'codex',
    status: 'idle',
    capabilities: capabilities,
    createdAt: '2026-05-29T00:00:00.000Z',
    updatedAt: '2026-05-29T00:00:00.000Z',
  );
  const run = RunSummary(
    id: 'r1',
    tool: 'codex',
    workspaceId: 'w1',
    status: 'completed',
  );
  const queueItem = QueueItem(
    runId: 'r1',
    workspaceId: 'w1',
    position: 1,
    status: 'queued',
    reason: 'waiting',
  );
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[workspace],
  );
  final conversationRepository = _FakeCachedConversationRepository()
    ..replaceFromBootstrap(
      workspaceId: workspace.id,
      conversations: const <ConversationSummary>[conversation],
    );
  final runRepository = _FakeCachedRunRepository()
    ..replaceFromBootstrap(
      workspaceId: workspace.id,
      runs: const <RunSummary>[run],
      queue: const <QueueItem>[queueItem],
    );
  final viewModel = HomeViewModel(
    workspaceRepository: workspaceRepository,
    conversationRepository: conversationRepository,
    runRepository: runRepository,
  );

  expect(viewModel.deck, isNotNull);
  expect(conversationRepository.refreshCalls, 0);
  expect(runRepository.refreshCalls, 0);
});
```

Change the fake cached repository classes in that file so they return their superclass bootstrap data:

```dart
@override
List<ConversationSummary> get conversations => super.conversations;
```

```dart
@override
List<RunSummary> get runs => super.runs;

@override
List<QueueItem> get queue => super.queue;
```

- [ ] **Step 2: Update dependency creation call sites**

In `mobile/lib/src/ui/features/connection/views/mobile_connection_gate.dart`, pass bootstrap data:

```dart
_pageDependencies = widget.dependencies.createMainTabsDependencies(
  client,
  initialData: widget.viewModel.initialData!,
);
```

In `mobile/test/widget_test.dart`, update every `_dependencies.createMainTabsDependencies(widget.client)` call to pass:

```dart
final snapshot = widget.snapshot == null ? _testSnapshot() : widget.snapshot!;
_pageDependencies = _dependencies.createMainTabsDependencies(
  widget.client,
  initialData: snapshot.toDaemonInitialData(),
);
```

- [ ] **Step 3: Remove UI repository hydration and startup refresh**

In `mobile/lib/src/ui/main_tabs_page.dart`, remove `_seedWorkspaceRepository` and delete this call from `_createRepositoryBackedViewModels`:

```dart
unawaited(_refreshHomeViewModel(homeViewModel));
```

Delete `_refreshHomeViewModel` when no caller remains.

Change the connected repository access in `MainTabsPage` to read from scope:

```dart
ConnectedSessionRepositories get _repositories =>
    widget.pageDependencies.sessionScope.repositories;
```

Then replace `_connectedData.` reads with `_repositories.` reads in the file.

- [ ] **Step 4: Run Home and widget dependency tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\home_view_model_test.dart -r expanded --plain-name "home renders repository bootstrap data without refresh"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "connected startup"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add mobile/lib/src/ui/features/connection/views/mobile_connection_gate.dart mobile/lib/src/ui/main_tabs_page.dart mobile/test/home_view_model_test.dart mobile/test/widget_test.dart
git commit -m "Render connected tabs from hydrated repositories"
```

---

## Task 5: Source Adapters Overlay From Repositories

**Files:**
- Modify: `mobile/lib/src/ui/features/adapters/view_models/adapters_view_model.dart`
- Modify: `mobile/lib/src/ui/main_route_overlay.dart`
- Test: `mobile/test/adapters_view_model_test.dart`
- Test: `mobile/test/main_route_overlay_test.dart`

- [ ] **Step 1: Replace `AdaptersViewModel` tests**

In `mobile/test/adapters_view_model_test.dart`, replace snapshot-based tests with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/adapters/adapters.dart';

void main() {
  group('AdaptersViewModel', () {
    test('reads adapters and extensions from repositories', () async {
      final delegate = _FakeAdapterRepository();
      final adapters = CliAdapterRepository(delegate: delegate);
      final catalog = CommandCatalogRepository(delegate: delegate);
      final viewModel = AdaptersViewModel(
        adapterRepository: adapters,
        commandCatalogRepository: catalog,
      );

      adapters.replaceFromBootstrap(const <AdapterStatus>[_codexAdapter]);
      await catalog.load();

      expect(viewModel.adapters.single.adapter, 'codex');
      expect(viewModel.extensions.single.id, 'github');
    });

    test('notifies when adapter repository changes', () {
      final delegate = _FakeAdapterRepository();
      final adapters = CliAdapterRepository(delegate: delegate);
      final catalog = CommandCatalogRepository(delegate: delegate);
      final viewModel = AdaptersViewModel(
        adapterRepository: adapters,
        commandCatalogRepository: catalog,
      );
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      adapters.replaceFromBootstrap(const <AdapterStatus>[_codexAdapter]);

      expect(notifications, 1);
      expect(viewModel.adapters.single.adapter, 'codex');
    });
  });
}

const _codexAdapter = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
);

class _FakeAdapterRepository implements AdapterRepository {
  @override
  Future<List<AdapterStatus>> listAdapters() async =>
      const <AdapterStatus>[_codexAdapter];

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  @override
  Future<List<ExtensionSummary>> listExtensions() async =>
      const <ExtensionSummary>[
        ExtensionSummary(
          id: 'github',
          name: 'GitHub',
          version: '1.0.0',
          description: 'Issue sync',
          installed: true,
          status: 'installed',
        ),
      ];
}
```

- [ ] **Step 2: Add overlay regression**

In `mobile/test/main_route_overlay_test.dart`, add:

```dart
testWidgets('adapters overlay reads repository adapters when bootstrap is empty',
    (tester) async {
  final repositories = _connectedRepositories();
  repositories.cliAdapterRepository.replaceFromBootstrap(
    const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ],
  );

  await tester.pumpWidget(_OverlayHarness(
    route: RoutePage.adapters,
    data: _snapshotWithNoAdapters(runs: const <RunSummary>[]),
    repositories: repositories,
    featureDependencies: _featureDependencies(
      createRunDetailViewModel: _RunDetailFactory().create,
    ),
  ));
  await tester.pumpAndSettle();

  expect(find.text('codex'), findsOneWidget);
});
```

Add this helper beside `_snapshot`:

```dart
AppSnapshot _snapshotWithNoAdapters({required List<RunSummary> runs}) =>
    _snapshot(runs: runs).copyWith(adapters: const <AdapterStatus>[]);
```

- [ ] **Step 3: Update `AdaptersViewModel`**

Replace the snapshot constructor with repository injection:

```dart
class AdaptersViewModel extends ChangeNotifier {
  AdaptersViewModel({
    required CliAdapterRepository adapterRepository,
    required CommandCatalogRepository commandCatalogRepository,
  })  : _adapterRepository = adapterRepository,
        _commandCatalogRepository = commandCatalogRepository {
    _adapterRepository.addListener(_onRepositoryChanged);
    _commandCatalogRepository.addListener(_onRepositoryChanged);
  }

  final CliAdapterRepository _adapterRepository;
  final CommandCatalogRepository _commandCatalogRepository;

  List<AdapterStatus> get adapters => _adapterRepository.adapters;
  List<ExtensionSummary> get extensions => _commandCatalogRepository.extensions;
  bool get loading =>
      _adapterRepository.loading || _commandCatalogRepository.loading;
  Object? get error {
    final adapterError = _adapterRepository.error;
    if (adapterError != null) return adapterError;
    return _commandCatalogRepository.error;
  }

  void _onRepositoryChanged() => notifyListeners();

  @override
  void dispose() {
    _adapterRepository.removeListener(_onRepositoryChanged);
    _commandCatalogRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
```

- [ ] **Step 4: Update overlay construction**

In `mobile/lib/src/ui/main_route_overlay.dart`, create the adapters ViewModel from repositories:

```dart
var viewModel = _adaptersViewModel;
if (viewModel == null) {
  viewModel = AdaptersViewModel(
    adapterRepository: widget.repositories.cliAdapterRepository,
    commandCatalogRepository: widget.repositories.commandCatalogRepository,
  );
  _adaptersViewModel = viewModel;
}
```

Dispose `_adaptersViewModel` in `dispose`, and reset it in `didUpdateWidget` when the repository scope changes.

- [ ] **Step 5: Run adapter overlay tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\adapters_view_model_test.dart test\main_route_overlay_test.dart -r expanded --plain-name "adapters"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add mobile/lib/src/ui/features/adapters/view_models/adapters_view_model.dart mobile/lib/src/ui/main_route_overlay.dart mobile/test/adapters_view_model_test.dart mobile/test/main_route_overlay_test.dart
git commit -m "Source adapters overlay from repositories"
```

---

## Task 6: Gate Coding On Adapter Probe State Only

**Files:**
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add Coding gate regression**

In `mobile/test/widget_test.dart`, add:

```dart
testWidgets('coding gate ignores command catalog failure after adapters load',
    (tester) async {
  SharedPreferences.setMockInitialValues(
    <String, Object>{AppLanguage.storageKey: 'en-US'},
  );
  final client = _PendingAdapterClient()
    ..completeCatalogWithError = true;

  await tester.pumpWidget(_MainTabsHarness(client: client));
  await tester.pump();

  client.completeWithAdapters();
  await tester.tap(find.text('Coding'));
  await tester.pumpAndSettle();

  expect(find.text('Unable to load CLI adapters'), findsNothing);
  expect(find.byType(CodingPage), findsOneWidget);
});
```

Extend `_PendingAdapterClient` so `listExtensions` throws when `completeCatalogWithError` is true:

```dart
bool completeCatalogWithError = false;

@override
Future<List<ExtensionSummary>> listExtensions() async {
  if (completeCatalogWithError) {
    throw StateError('extensions failed');
  }
  return const <ExtensionSummary>[];
}
```

- [ ] **Step 2: Run the failing Coding gate test**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "coding gate ignores command catalog failure after adapters load"
```

Expected: FAIL because the gate still observes the broad cached adapter repository.

- [ ] **Step 3: Update preload and retry**

In `mobile/lib/src/ui/main_tabs_page.dart`, change `_loadCodingAdapters` to:

```dart
void _loadCodingAdapters() {
  unawaited(
    _repositories.cliAdapterRepository.probe().catchError(
      (Object error, StackTrace stackTrace) {
        if (mounted) {
          _repositories.recordDiagnosticEvent(
            'coding.adapters.load_failed',
            {'error': '$error'},
            path: 'coding',
          );
        }
      },
    ),
  );
}
```

Change `_buildCodingTab` to listen to adapter probe state:

```dart
// TODO(arch): Remove direct repository access when CodingGateViewModel
// owns coding gate state. Tracked by migration Slice 4.
return ListenableBuilder(
  listenable: _repositories.cliAdapterRepository,
  builder: (context, _) => _buildCodingTabContent(viewModel),
);
```

Change `_buildCodingTabContent`:

```dart
final adapterRepo = _repositories.cliAdapterRepository;
if (adapterRepo.loading || adapterRepo.error != null) {
  return _CodingAdapterGate(
    failed: adapterRepo.error != null,
    error: adapterRepo.error,
    onRetry: () => unawaited(adapterRepo.probe()),
  );
}
```

- [ ] **Step 4: Run Coding gate tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "coding waits for pending adapter preload"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "coding adapter preload failure can retry"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "coding gate ignores command catalog failure after adapters load"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add mobile/lib/src/ui/main_tabs_page.dart mobile/test/widget_test.dart
git commit -m "Gate coding on adapter probe state only"
```

---

## Task 7: Add OpenWorkspaceUseCase And Explicit Transition State

**Files:**
- Create: `mobile/lib/src/workflows/connection/open_workspace_use_case.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Test: `mobile/test/open_workspace_use_case_test.dart`
- Test: `mobile/test/workbench_view_model_repository_state_test.dart`

- [ ] **Step 1: Write use case test**

Create `mobile/test/open_workspace_use_case_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_initial_data.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/workflows/connection/open_workspace_use_case.dart';

void main() {
  test('open workspace hydrates workspace scoped repositories', () async {
    final workspaceRepository = _FakeWorkspaceRepository(
      workspaces: const <WorkspaceSummary>[_workspace1, _workspace2],
    );
    final conversationRepository = CachedConversationRepository(
      delegate: _UnusedConversationRepository(),
    );
    final runRepository = CachedRunRepository(
      delegate: _UnusedRunRepository(),
    );
    final useCase = OpenWorkspaceUseCase(
      loadWorkspaceBootstrap: ({
        required workspaces,
        required workspace,
      }) async =>
          _initialDataForWorkspace(workspace),
      workspaceRepository: workspaceRepository,
      conversationRepository: conversationRepository,
      runRepository: runRepository,
    );

    await useCase.open(
      workspaces: const <WorkspaceSummary>[_workspace1, _workspace2],
      workspace: _workspace2,
    );

    expect(workspaceRepository.selectedWorkspace?.id, 'w2');
    expect(conversationRepository.loadedWorkspaceId, 'w2');
    expect(runRepository.loadedWorkspaceId, 'w2');
  });
}

const _health = DaemonHealth(
  status: 'ok',
  daemonVersion: 'test',
  mode: 'test',
  lanMode: false,
  bindAddress: '127.0.0.1',
  port: 4317,
  security: <String, Object?>{},
);

const _workspace1 = WorkspaceSummary(
  id: 'w1',
  name: 'One',
  path: r'D:\one',
);

const _workspace2 = WorkspaceSummary(
  id: 'w2',
  name: 'Two',
  path: r'D:\two',
);

const _conversationCapabilities = ConversationCapabilities(
  longLivedProcess: false,
  waitingInput: false,
  waitingApproval: false,
  resume: false,
  partialOutput: false,
);

DaemonInitialData _initialDataForWorkspace(WorkspaceSummary workspace) {
  return DaemonInitialData(
    health: _health,
    workspaces: const <WorkspaceSummary>[_workspace1, _workspace2],
    workspace: workspace,
    adapters: const <AdapterStatus>[],
    conversations: <ConversationSummary>[
      ConversationSummary(
        id: 'c-${workspace.id}',
        workspaceId: workspace.id,
        adapter: 'codex',
        status: 'idle',
        capabilities: _conversationCapabilities,
        createdAt: '2026-05-29T00:00:00.000Z',
        updatedAt: '2026-05-29T00:00:00.000Z',
      ),
    ],
    runs: <RunSummary>[
      RunSummary(
        id: 'r-${workspace.id}',
        tool: 'codex',
        workspaceId: workspace.id,
        status: 'completed',
      ),
    ],
    queue: <QueueItem>[
      QueueItem(
        runId: 'r-${workspace.id}',
        workspaceId: workspace.id,
        position: 1,
        status: 'queued',
        reason: 'waiting',
      ),
    ],
  );
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({required List<WorkspaceSummary> workspaces})
      : _workspaces = List<WorkspaceSummary>.of(workspaces),
        _selectedWorkspace = workspaces.isEmpty ? null : workspaces.first;

  List<WorkspaceSummary> _workspaces;
  WorkspaceSummary? _selectedWorkspace;

  @override
  List<WorkspaceSummary> get workspaces => List.unmodifiable(_workspaces);

  @override
  WorkspaceSummary? get selectedWorkspace => _selectedWorkspace;

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) {
    throw UnimplementedError();
  }

  @override
  bool select(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) {
        _selectedWorkspace = workspace;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    _workspaces = List<WorkspaceSummary>.of(workspaces);
    _selectedWorkspace = selectedWorkspace;
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedConversationRepository implements ConversationRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedRunRepository implements RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Run the failing use case test**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\open_workspace_use_case_test.dart -r expanded
```

Expected: FAIL because `OpenWorkspaceUseCase` does not exist.

- [ ] **Step 3: Implement `OpenWorkspaceUseCase`**

Create `mobile/lib/src/workflows/connection/open_workspace_use_case.dart`:

```dart
import '../../data/repositories/bootstrap_hydration.dart';
import '../../data/repositories/workspace_repository.dart';
import '../../domain/models/daemon_initial_data.dart';
import '../../models/protocol.dart';

typedef LoadWorkspaceBootstrap = Future<DaemonInitialData> Function({
  required List<WorkspaceSummary> workspaces,
  required WorkspaceSummary workspace,
});

class OpenWorkspaceUseCase {
  OpenWorkspaceUseCase({
    required LoadWorkspaceBootstrap loadWorkspaceBootstrap,
    required WorkspaceRepository workspaceRepository,
    required ConversationBootstrapTarget conversationRepository,
    required RunBootstrapTarget runRepository,
  })  : _loadWorkspaceBootstrap = loadWorkspaceBootstrap,
        _workspaceRepository = workspaceRepository,
        _conversationRepository = conversationRepository,
        _runRepository = runRepository;

  final LoadWorkspaceBootstrap _loadWorkspaceBootstrap;
  final WorkspaceRepository _workspaceRepository;
  final ConversationBootstrapTarget _conversationRepository;
  final RunBootstrapTarget _runRepository;

  Future<DaemonInitialData> open({
    required List<WorkspaceSummary> workspaces,
    required WorkspaceSummary workspace,
  }) async {
    final initialData = await _loadWorkspaceBootstrap(
      workspaces: workspaces,
      workspace: workspace,
    );
    final selectedWorkspace = initialData.workspace;
    _workspaceRepository.applyBootstrapCatalog(
      selectedWorkspace: selectedWorkspace,
      workspaces: initialData.workspaces,
    );
    if (selectedWorkspace == null) return initialData;
    _conversationRepository.replaceFromBootstrap(
      workspaceId: selectedWorkspace.id,
      conversations: initialData.conversations,
    );
    _runRepository.replaceFromBootstrap(
      workspaceId: selectedWorkspace.id,
      runs: initialData.runs,
      queue: initialData.queue,
    );
    return initialData;
  }
}
```

- [ ] **Step 4: Add Workbench transition test**

In `mobile/test/workbench_view_model_repository_state_test.dart`, add:

```dart
test('openWorkspaceSessions exposes loading until workspace bootstrap completes',
    () async {
  final completer = Completer<DaemonInitialData>();
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
    ],
  );
  final viewModel = _workbenchViewModel(
    workspaceRepository,
    openWorkspace: _FakeOpenWorkspaceUseCase(completer.future),
  );

  final future = viewModel.openWorkspaceSessions('w2');

  expect(viewModel.openingWorkspaceId, 'w2');
  expect(viewModel.openingWorkspace, isTrue);

  completer.complete(_initialDataForWorkspace('w2'));
  await future;

  expect(viewModel.openingWorkspaceId, isNull);
  expect(viewModel.openingWorkspace, isFalse);
  expect(
    viewModel.routeState,
    isA<WorkspaceSessionsRouteState>(),
  );
});
```

- [ ] **Step 5: Wire workspace opening**

In `WorkbenchViewModel`, add fields and getters:

```dart
final OpenWorkspaceUseCase? _openWorkspaceUseCase;
String? _openingWorkspaceId;

String? get openingWorkspaceId => _openingWorkspaceId;
bool get openingWorkspace => _openingWorkspaceId != null;
```

Change `openWorkspaceSessions` to return `Future<void>` and use the use case:

```dart
Future<void> openWorkspaceSessions(String workspaceId) async {
  final workspace = _workspaceById(workspaceId);
  if (workspace == null) {
    _routeState = const WorkspaceListRouteState(
      notice: 'Workspace is no longer available.',
    );
    _notifyListeners();
    return;
  }
  final useCase = _openWorkspaceUseCase;
  if (useCase == null) {
    final accepted = _workspaceRepository.select(workspaceId);
    _routeState = accepted
        ? WorkspaceSessionsRouteState(workspaceId: workspaceId)
        : const WorkspaceListRouteState(
            notice: 'Workspace is no longer available.',
          );
    _notifyListeners();
    return;
  }
  _openingWorkspaceId = workspaceId;
  _notifyListeners();
  try {
    await useCase.open(
      workspaces: _workspaceRepository.workspaces,
      workspace: workspace,
    );
    _routeState = WorkspaceSessionsRouteState(workspaceId: workspaceId);
  } finally {
    _openingWorkspaceId = null;
    _notifyListeners();
  }
}
```

`MainTabsShellViewModel` remains unchanged; it only owns shell route, overlay, tab, and back behavior.

- [ ] **Step 6: Update `MainTabsPage` empty workspace flow**

In `_openWorkspace`, replace the direct `loadWorkspaceBootstrap` call with:

```dart
final initialData =
    await widget.pageDependencies.sessionScope.useCases.openWorkspace.open(
  workspaces: workspaces,
  workspace: workspace,
);
```

Keep `_loadingWorkspace` in the page because the empty shell has no `WorkbenchViewModel` yet.

- [ ] **Step 7: Run workspace tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\open_workspace_use_case_test.dart test\workbench_view_model_repository_state_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add mobile/lib/src/workflows/connection/open_workspace_use_case.dart mobile/lib/src/ui/main_tabs_page.dart mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart mobile/test/open_workspace_use_case_test.dart mobile/test/workbench_view_model_repository_state_test.dart
git commit -m "Coordinate workspace bootstrap through use case"
```

---

## Task 8: Architecture Verification And Cleanup

**Files:**
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/main_route_overlay.dart`
- Modify: `mobile/lib/src/ui/features/workbench/`
- Modify: `mobile/test/`

- [ ] **Step 1: Run architecture import check**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run focused tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\connected_repository_bootstrap_test.dart test\adapter_resource_state_test.dart test\connected_session_scope_test.dart test\open_workspace_use_case_test.dart -r expanded
flutter test --no-pub test\adapters_view_model_test.dart test\main_route_overlay_test.dart -r expanded --plain-name "adapters"
flutter test --no-pub test\home_view_model_test.dart -r expanded --plain-name "bootstrap"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "coding"
```

Expected: PASS.

- [ ] **Step 4: Scan forbidden runtime ownership paths**

Run:

```powershell
rg -n "MainTabsPage.*replaceFromBootstrap|MainTabsShellViewModel.*OpenWorkspaceUseCase|AdaptersViewModel\\(snapshot:|replaceBootstrapSnapshot|connectedInitialData\\.adapters|toAppSnapshot\\(\\)" mobile/lib/src mobile/test
```

Expected: no matches in connected runtime UI paths.

- [ ] **Step 5: Run diff check**

Run:

```powershell
git diff --check
```

Expected: PASS.

- [ ] **Step 6: Commit cleanup changes**

Create a cleanup commit only after import or test cleanup edits:

```powershell
git add mobile/lib/src mobile/test
git commit -m "Clean up connected session architecture migration"
```

Do not create an empty commit.

---

## Acceptance Criteria

- `ConnectedSessionScope` contains repositories and use cases only.
- Feature factories and ViewModel construction remain in `AppDependencies` or its app-layer dependency groups.
- `ConnectSessionUseCase` completes connection/bootstrap and returns bootstrap data; it does not hydrate repositories directly.
- Connection startup hydration happens in the composition root before connected ViewModels read repositories.
- Workspace switching hydration happens in `OpenWorkspaceUseCase`.
- `MainTabsPage` does not call repository bootstrap replacement methods.
- `MainTabsShellViewModel` does not call `OpenWorkspaceUseCase`.
- `ConversationRepository` and `RunRepository` expose `loadedWorkspaceId`; queue compatibility remains under `RunRepository` for this slice.
- Coding gate observes `CliAdapterRepository` only.
- Command catalog failures do not block Coding as adapter failures.
- Settings -> adapters reads adapter repository state when bootstrap adapters are empty.
- Home renders bootstrap conversations, runs, and queue without an immediate duplicate refresh.
- Architecture import checks, static analysis, and focused regression tests pass.
