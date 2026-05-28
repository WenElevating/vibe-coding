# Mobile Repository-Owned State Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the connected Flutter runtime so Workspace, Home, Settings, and Workbench read shared Repository-owned state through their own ViewModels, while `MainTabs` owns only shell/navigation state.

**Architecture:** Keep `domain/` repository contracts pure Dart. Add listenable runtime repository contracts and concrete caches in `data/repositories/`; these implementations extend `ChangeNotifier`, implement the existing pure domain contracts where useful, and become the connected-session business state authority. Feature ViewModels subscribe to those repositories and remove listeners in `dispose`; `AppSnapshot` remains bootstrap/compatibility data only and is removed from `MainTabsViewModel.data`, `HomePage`, `SettingsPage`, and `CodingWorkbenchPage` runtime paths.

**Tech Stack:** Flutter/Dart, existing `ChangeNotifier`/`ListenableBuilder`, existing daemon repository implementations, existing `tool/check_architecture_imports.dart`, no new runtime dependencies.

---

## File Structure

- Create `mobile/lib/src/data/repositories/workspace_repository.dart`: listenable runtime workspace repository contract used by feature ViewModels.
- Modify `mobile/lib/src/data/repositories/daemon_workspace_repository.dart`: hold workspace catalog cache, selected workspace, loading/error state, and notifications.
- Modify `mobile/lib/src/app/app_dependencies.dart`: type connected data dependencies as listenable repositories and wire feature ViewModel factories.
- Create `mobile/lib/src/data/repositories/cached_adapter_repository.dart`: shared adapter/template/extension cache that wraps the existing daemon adapter repository.
- Create `mobile/lib/src/data/repositories/cached_conversation_repository.dart`: shared conversation list cache around the existing daemon conversation repository.
- Create `mobile/lib/src/data/repositories/cached_run_repository.dart`: shared run and queue cache around the existing daemon run repository.
- Create `mobile/lib/src/data/repositories/coding_preferences_repository.dart`: repository replacement for `CodingPreferencesStore`.
- Delete or privatize `mobile/lib/src/services/coding_preferences_store.dart` after `CodingPreferencesRepository` owns runtime preference state.
- Create `mobile/lib/src/ui/view_models/main_tabs_shell_view_model.dart`: shell-only tab, overlay, bottom-nav, and back behavior state.
- Delete `mobile/lib/src/ui/view_models/main_tabs_view_model.dart` after all callers use `MainTabsShellViewModel`.
- Create `mobile/lib/src/ui/pages/home_view_model.dart`: Home projection from shared repositories.
- Modify `mobile/lib/src/ui/pages/home_page.dart`: accept `HomeViewModel`, not `AppSnapshot`.
- Create `mobile/lib/src/ui/features/settings/view_models/settings_view_model.dart`: Settings projection from repositories/preferences/app update.
- Modify `mobile/lib/src/ui/pages/settings_page.dart` and `mobile/lib/src/ui/features/settings/settings_page.dart`: accept `SettingsViewModel`, not `AppSnapshot`.
- Modify `mobile/lib/src/ui/pages/coding/coding_page.dart`: pass repositories/ViewModel-facing inputs instead of `AppSnapshot`.
- Modify `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`: remove `data`, `didUpdateWidget -> updateFromSnapshot`, and runtime `AppSnapshot` reconciliation.
- Modify `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`: subscribe to workspace/adapter/conversation/run repositories, store route ids instead of workspace lists/entities, and expose `createWorkspaceAndOpen` / `openWorkspaceSessions`.
- Modify `mobile/lib/src/ui/main_tabs_page.dart`: construct and own feature ViewModels, no longer pass `viewModel.data` into tabs.
- Modify `mobile/lib/src/shell/app_snapshot.dart`: keep bootstrap helpers only; do not use it as connected runtime state.
- Modify tests under `mobile/test/`: repository tests, ViewModel tests, and the tab-switch regression.

Use mainland China mirrors for every Flutter/Dart validation command:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
```

If a Flutter/Dart command times out once, stop retrying automatically and record the exact command plus the last visible output.

---

## Task 1: Make WorkspaceRepository The Runtime Catalog Authority

**Files:**
- Create: `mobile/lib/src/data/repositories/workspace_repository.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_workspace_repository.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/workspace_repository_test.dart`

- [ ] **Step 1: Write repository contract tests**

Create `mobile/test/workspace_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_workspace_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';

void main() {
  test('load caches workspaces and notifies listeners', () async {
    final client = _FakeWorkspaceDaemonClient(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      ],
    );
    final repository = DaemonWorkspaceRepository(client: client);
    var notifications = 0;
    repository.addListener(() => notifications++);

    await repository.load();

    expect(repository.loading, isFalse);
    expect(repository.error, isNull);
    expect(repository.workspaces.map((w) => w.id), const <String>['w1']);
    expect(repository.selectedWorkspace?.id, 'w1');
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('create refreshes catalog, selects created workspace, and notifies',
      () async {
    final client = _FakeWorkspaceDaemonClient(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
      ],
      createdWorkspace:
          const WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
      refreshedWorkspaces: const <WorkspaceSummary>[
        WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
        WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
      ],
    );
    final repository = DaemonWorkspaceRepository(client: client);
    await repository.load();
    var notifications = 0;
    repository.addListener(() => notifications++);

    final created = await repository.create(path: r'D:\new', name: 'New');

    expect(created.id, 'new');
    expect(repository.workspaces.map((w) => w.id),
        const <String>['old', 'new']);
    expect(repository.selectedWorkspace?.id, 'new');
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('select returns false for unknown workspace without notifying', () async {
    final repository = DaemonWorkspaceRepository(
      client: _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      ),
    );
    await repository.load();
    var notifications = 0;
    repository.addListener(() => notifications++);

    final accepted = repository.select('missing');

    expect(accepted, isFalse);
    expect(repository.selectedWorkspace?.id, 'w1');
    expect(notifications, 0);
  });

  test('create failure preserves previous catalog and selected workspace',
      () async {
    final client = _FakeWorkspaceDaemonClient(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      ],
    )..createError = StateError('create failed');
    final repository = DaemonWorkspaceRepository(client: client);
    await repository.load();

    await expectLater(
      repository.create(path: r'D:\bad'),
      throwsA(isA<StateError>()),
    );

    expect(repository.loading, isFalse);
    expect(repository.error, isA<StateError>());
    expect(repository.workspaces.map((w) => w.id), const <String>['w1']);
    expect(repository.selectedWorkspace?.id, 'w1');
  });
}

class _FakeWorkspaceDaemonClient implements DaemonClient {
  _FakeWorkspaceDaemonClient({
    required List<WorkspaceSummary> workspaces,
    WorkspaceSummary? createdWorkspace,
    List<WorkspaceSummary>? refreshedWorkspaces,
  })  : _workspaces = workspaces,
        _createdWorkspace = createdWorkspace,
        _refreshedWorkspaces = refreshedWorkspaces;

  List<WorkspaceSummary> _workspaces;
  final WorkspaceSummary? _createdWorkspace;
  final List<WorkspaceSummary>? _refreshedWorkspaces;
  Object? createError;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => _workspaces;

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async {
    final error = createError;
    if (error != null) throw error;
    final created = _createdWorkspace ??
        WorkspaceSummary(id: 'created', name: name ?? path, path: path);
    _workspaces = _refreshedWorkspaces ?? <WorkspaceSummary>[..._workspaces, created];
    return created;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Run the failing repository tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/workspace_repository_test.dart -r expanded
```

Expected: compile failures because `DaemonWorkspaceRepository` does not yet expose `load`, `refresh`, `create`, `select`, `workspaces`, `selectedWorkspace`, `loading`, or `error`.

- [ ] **Step 3: Add the listenable runtime repository contract**

Create `mobile/lib/src/data/repositories/workspace_repository.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../domain/repositories/workspace_repository.dart' as domain;
import '../../models/protocol.dart';

abstract class WorkspaceRepository extends ChangeNotifier
    implements domain.WorkspaceRepository {
  List<WorkspaceSummary> get workspaces;
  WorkspaceSummary? get selectedWorkspace;
  bool get loading;
  Object? get error;

  Future<void> load();
  Future<void> refresh();
  Future<WorkspaceSummary> create({required String path, String? name});
  bool select(String workspaceId);
}
```

- [ ] **Step 4: Implement workspace cache in DaemonWorkspaceRepository**

Modify `mobile/lib/src/data/repositories/daemon_workspace_repository.dart` so the class extends the new data contract:

```dart
import 'workspace_repository.dart';
```

Use this state shape and methods:

```dart
class DaemonWorkspaceRepository extends WorkspaceRepository {
  DaemonWorkspaceRepository({required DaemonClient client}) : _client = client;

  final DaemonClient _client;

  List<WorkspaceSummary> _workspaces = const <WorkspaceSummary>[];
  String? _selectedWorkspaceId;
  bool _loading = false;
  Object? _error;

  @override
  List<WorkspaceSummary> get workspaces => List.unmodifiable(_workspaces);

  @override
  WorkspaceSummary? get selectedWorkspace {
    final selectedId = _selectedWorkspaceId;
    if (selectedId == null) return _workspaces.isEmpty ? null : _workspaces.first;
    for (final workspace in _workspaces) {
      if (workspace.id == selectedId) return workspace;
    }
    return _workspaces.isEmpty ? null : _workspaces.first;
  }

  @override
  bool get loading => _loading;

  @override
  Object? get error => _error;

  @override
  Future<void> load() => refresh();

  @override
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final loaded = await listWorkspaces();
      _workspaces = List<WorkspaceSummary>.unmodifiable(loaded);
      _selectedWorkspaceId = _resolveSelectedId(_selectedWorkspaceId, loaded);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final created = await createWorkspace(path: path, name: name);
      final refreshed = await listWorkspaces();
      _workspaces = List<WorkspaceSummary>.unmodifiable(refreshed);
      _selectedWorkspaceId = refreshed.any((w) => w.id == created.id)
          ? created.id
          : _resolveSelectedId(_selectedWorkspaceId, refreshed);
      return selectedWorkspace ?? created;
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  bool select(String workspaceId) {
    if (!_workspaces.any((workspace) => workspace.id == workspaceId)) {
      return false;
    }
    if (_selectedWorkspaceId == workspaceId) return true;
    _selectedWorkspaceId = workspaceId;
    notifyListeners();
    return true;
  }
}

String? _resolveSelectedId(String? current, List<WorkspaceSummary> workspaces) {
  if (current != null && workspaces.any((workspace) => workspace.id == current)) {
    return current;
  }
  return workspaces.isEmpty ? null : workspaces.first.id;
}
```

Keep all existing daemon delegation methods (`projectOverview`, `fileTree`, `gitStatus`, etc.) in the same class.

- [ ] **Step 5: Update connected dependency typing**

In `mobile/lib/src/app/app_dependencies.dart`, replace the domain workspace repository import with the data runtime contract:

```dart
import '../data/repositories/workspace_repository.dart';
```

The existing `ConnectedDataDependencies.workspaceRepository` field should remain named `workspaceRepository`, but its type should be the data runtime `WorkspaceRepository` so ViewModels can subscribe to it.

- [ ] **Step 6: Run tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/workspace_repository_test.dart -r expanded
```

Expected: all `WorkspaceRepository` tests pass.

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/data/repositories/workspace_repository.dart mobile/lib/src/data/repositories/daemon_workspace_repository.dart mobile/lib/src/app/app_dependencies.dart mobile/test/workspace_repository_test.dart
git commit -m "Make workspace repository own runtime catalog state" -m "Constraint: domain workspace contracts stay pure Dart; the listenable runtime repository lives in data/repositories." -m "Tested: cd mobile && flutter test test/workspace_repository_test.dart -r expanded"
```

---

## Task 2: Add Shared Runtime Caches For Adapter, Conversation, And Run Data

**Files:**
- Create: `mobile/lib/src/data/repositories/cached_adapter_repository.dart`
- Create: `mobile/lib/src/data/repositories/cached_conversation_repository.dart`
- Create: `mobile/lib/src/data/repositories/cached_run_repository.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/cached_connected_repositories_test.dart`

- [ ] **Step 1: Write cache behavior tests**

Create `mobile/test/cached_connected_repositories_test.dart` with tests for:

```dart
test('adapter cache loads once and exposes adapters', () async {
  final delegate = _FakeAdapterRepository();
  final repository = CachedAdapterRepository(delegate: delegate);

  await repository.load();
  final adapters = await repository.listAdapters();

  expect(delegate.listAdaptersCalls, 1);
  expect(adapters.map((adapter) => adapter.adapter), const <String>['codex']);
  expect(repository.adapters.map((adapter) => adapter.adapter),
      const <String>['codex']);
});

test('conversation cache refreshes and upserts mutated conversations', () async {
  final delegate = _FakeConversationRepository(
    conversations: const <ConversationSummary>[
      ConversationSummary(
        id: 'c1',
        workspaceId: 'w1',
        title: 'Old',
        status: 'running',
        adapter: 'codex',
        createdAt: '2026-05-28T00:00:00.000Z',
        updatedAt: '2026-05-28T00:00:00.000Z',
      ),
    ],
  );
  final repository = CachedConversationRepository(delegate: delegate);

  await repository.refresh();
  await repository.updateConversationModel('c1', 'gpt-5');

  expect(repository.conversations.single.id, 'c1');
  expect(repository.conversations.single.model, 'gpt-5');
});

test('run cache refreshes runs and queue together', () async {
  final delegate = _FakeRunRepository(
    runs: const <RunSummary>[
      RunSummary(
        id: 'r1',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'running',
        createdAt: '2026-05-28T00:00:00.000Z',
        updatedAt: '2026-05-28T00:00:00.000Z',
      ),
    ],
    queue: const <QueueItem>[
      QueueItem(id: 'q1', workspaceId: 'w1', tool: 'codex', status: 'queued'),
    ],
  );
  final repository = CachedRunRepository(delegate: delegate);

  await repository.refresh();

  expect(repository.runs.map((run) => run.id), const <String>['r1']);
  expect(repository.queue.map((item) => item.id), const <String>['q1']);
});

test('cache refresh failure preserves previous data', () async {
  final delegate = _FakeRunRepository(
    runs: const <RunSummary>[
      RunSummary(
        id: 'r1',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'running',
        createdAt: '2026-05-28T00:00:00.000Z',
        updatedAt: '2026-05-28T00:00:00.000Z',
      ),
    ],
    queue: const <QueueItem>[],
  );
  final repository = CachedRunRepository(delegate: delegate);
  await repository.refresh();
  delegate.refreshError = StateError('refresh failed');

  await expectLater(repository.refresh(), throwsA(isA<StateError>()));

  expect(repository.runs.map((run) => run.id), const <String>['r1']);
  expect(repository.error, isA<StateError>());
});
```

Use fake delegate repositories that implement the existing pure domain contracts. Each fake must expose call counts so the tests prove the cache is the shared authority after refresh.

- [ ] **Step 2: Run the failing cache tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/cached_connected_repositories_test.dart -r expanded
```

Expected: compile failures because the cached repositories do not exist.

- [ ] **Step 3: Implement CachedAdapterRepository**

Create `mobile/lib/src/data/repositories/cached_adapter_repository.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';

class CachedAdapterRepository extends ChangeNotifier implements AdapterRepository {
  CachedAdapterRepository({required AdapterRepository delegate})
      : _delegate = delegate;

  final AdapterRepository _delegate;
  List<AdapterStatus> _adapters = const <AdapterStatus>[];
  List<ShortcutCommand> _shortcuts = const <ShortcutCommand>[];
  List<CommandTemplate> _templates = const <CommandTemplate>[];
  List<ExtensionSummary> _extensions = const <ExtensionSummary>[];
  bool _loading = false;
  Object? _error;

  List<AdapterStatus> get adapters => List.unmodifiable(_adapters);
  List<ShortcutCommand> get shortcuts => List.unmodifiable(_shortcuts);
  List<CommandTemplate> get templates => List.unmodifiable(_templates);
  List<ExtensionSummary> get extensions => List.unmodifiable(_extensions);
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _delegate.listAdapters(),
        _delegate.listShortcuts(),
        _delegate.listCommandTemplates(),
        _delegate.listExtensions(),
      ]);
      _adapters = List<AdapterStatus>.unmodifiable(results[0] as List<AdapterStatus>);
      _shortcuts =
          List<ShortcutCommand>.unmodifiable(results[1] as List<ShortcutCommand>);
      _templates =
          List<CommandTemplate>.unmodifiable(results[2] as List<CommandTemplate>);
      _extensions =
          List<ExtensionSummary>.unmodifiable(results[3] as List<ExtensionSummary>);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    if (_adapters.isEmpty && !_loading) await load();
    return adapters;
  }

  @override
  Future<List<ShortcutCommand>> listShortcuts() async {
    if (_shortcuts.isEmpty && !_loading) await load();
    return shortcuts;
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async {
    if (_templates.isEmpty && !_loading) await load();
    return templates;
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    if (_extensions.isEmpty && !_loading) await load();
    return extensions;
  }
}
```

- [ ] **Step 4: Implement CachedConversationRepository**

Create `mobile/lib/src/data/repositories/cached_conversation_repository.dart` by wrapping every existing `ConversationRepository` method and updating `_conversations` after `listConversations`, `createConversation`, `sendConversationMessage`, `updateConversationModel`, `answerConversationQuestion`, `respondConversationApproval`, and `cancelConversation`.

Use this helper for mutations:

```dart
void _upsertConversation(ConversationSummary conversation) {
  final next = <ConversationSummary>[
    for (final existing in _conversations)
      if (existing.id != conversation.id) existing,
    conversation,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  _conversations = List<ConversationSummary>.unmodifiable(next);
  notifyListeners();
}
```

`watchConversationEvents` and `fetchConversationEvents` should delegate directly and must not mutate the conversation list unless a later task explicitly adds event-derived summary updates.

- [ ] **Step 5: Implement CachedRunRepository**

Create `mobile/lib/src/data/repositories/cached_run_repository.dart` by wrapping `RunRepository`. It must expose:

```dart
List<RunSummary> get runs;
List<QueueItem> get queue;
bool get loading;
Object? get error;
Future<void> refresh();
```

`refresh()` calls `listRuns()` and `listQueue()` through the delegate, updates both caches only on success, and preserves previous values on failure.

- [ ] **Step 6: Wire cached repositories in AppDependencies**

In `DataDependencies.forDaemonClient`, build the raw daemon repositories first and wrap them:

```dart
final adapterRepository = CachedAdapterRepository(
  delegate: DaemonAdapterRepository(client: client),
);
final conversationRepository = CachedConversationRepository(
  delegate: DaemonConversationRepository(
    client: client,
    notificationService: notificationClient,
  ),
);
final runRepository = CachedRunRepository(
  delegate: DaemonRunRepository(client: client),
);
```

Pass the cached instances into `ConnectedDataDependencies`.

- [ ] **Step 7: Run tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/cached_connected_repositories_test.dart -r expanded
```

Expected: all cache tests pass.

- [ ] **Step 8: Commit**

```powershell
git add mobile/lib/src/data/repositories/cached_adapter_repository.dart mobile/lib/src/data/repositories/cached_conversation_repository.dart mobile/lib/src/data/repositories/cached_run_repository.dart mobile/lib/src/app/app_dependencies.dart mobile/test/cached_connected_repositories_test.dart
git commit -m "Add connected runtime repository caches" -m "Constraint: caches wrap existing pure repository contracts and preserve previous data on refresh failure." -m "Tested: cd mobile && flutter test test/cached_connected_repositories_test.dart -r expanded"
```

---

## Task 3: Replace CodingPreferencesStore With CodingPreferencesRepository

**Files:**
- Create: `mobile/lib/src/data/repositories/coding_preferences_repository.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Test: `mobile/test/coding_preferences_repository_test.dart`

- [ ] **Step 1: Write preference repository tests**

Create `mobile/test/coding_preferences_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/coding_preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('load normalizes persisted permission mode and notifies', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{CodingPreferencesRepository.permissionModeStorageKey: 'default'},
    );
    final repository = CodingPreferencesRepository();
    var notifications = 0;
    repository.addListener(() => notifications++);

    await repository.load();

    expect(repository.permissionMode, 'default');
    expect(notifications, greaterThanOrEqualTo(1));
  });

  test('setPermissionMode persists normalized value and notifies', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = CodingPreferencesRepository();

    await repository.setPermissionMode('invalid');

    final prefs = await SharedPreferences.getInstance();
    expect(repository.permissionMode, 'auto');
    expect(
      prefs.getString(CodingPreferencesRepository.permissionModeStorageKey),
      'auto',
    );
  });
}
```

- [ ] **Step 2: Run failing tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/coding_preferences_repository_test.dart -r expanded
```

Expected: compile failure because `CodingPreferencesRepository` does not exist.

- [ ] **Step 3: Implement CodingPreferencesRepository**

Create `mobile/lib/src/data/repositories/coding_preferences_repository.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CodingPreferencesRepository extends ChangeNotifier {
  static const permissionModeStorageKey = 'coding.permissionMode';

  String _permissionMode = 'auto';
  bool _loading = false;
  Object? _error;

  String get permissionMode => _permissionMode;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _permissionMode =
          normalizePermissionMode(prefs.getString(permissionModeStorageKey));
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setPermissionMode(String value) async {
    final normalized = normalizePermissionMode(value);
    _permissionMode = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(permissionModeStorageKey, normalized);
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  static String normalizePermissionMode(String? value) =>
      value == 'default' ? 'default' : 'auto';
}
```

- [ ] **Step 4: Wire repository in app dependencies**

Add `CodingPreferencesRepository` to `DataDependencies` because the preference survives daemon reconnects:

```dart
final CodingPreferencesRepository codingPreferencesRepository;
```

Construct it once in `DataDependencies.createDefault()` and pass it through `MainTabsDependencies`.

- [ ] **Step 5: Remove CodingPreferencesStore usage from MainTabsPage**

In `mobile/lib/src/ui/main_tabs_page.dart`, delete:

```dart
late final CodingPreferencesStore _codingPreferencesStore;
_codingPreferencesStore = CodingPreferencesStore();
```

Replace `_loadCodingPreferences` and `_savePermissionMode` with calls to the repository. The shell should no longer own the persisted preference; it only delegates user commands to `SettingsViewModel` in Task 5.

- [ ] **Step 6: Run tests and store scan**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/coding_preferences_repository_test.dart -r expanded
rg "CodingPreferencesStore" mobile/lib mobile/test -n
```

Expected: tests pass. The `rg` command may only show deleted compatibility tests until Task 8; no production runtime code should instantiate `CodingPreferencesStore`.

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/data/repositories/coding_preferences_repository.dart mobile/lib/src/app/app_dependencies.dart mobile/lib/src/ui/main_tabs_page.dart mobile/test/coding_preferences_repository_test.dart
git commit -m "Replace coding preferences store with repository" -m "Constraint: preference runtime state is repository-owned and shell delegates preference commands." -m "Tested: cd mobile && flutter test test/coding_preferences_repository_test.dart -r expanded"
```

---

## Task 4: Introduce HomeViewModel And SettingsViewModel

**Files:**
- Create: `mobile/lib/src/ui/pages/home_view_model.dart`
- Modify: `mobile/lib/src/ui/pages/home_page.dart`
- Create: `mobile/lib/src/ui/features/settings/view_models/settings_view_model.dart`
- Modify: `mobile/lib/src/ui/pages/settings_page.dart`
- Modify: `mobile/lib/src/ui/features/settings/settings_page.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/home_view_model_test.dart`
- Test: `mobile/test/settings_view_model_test.dart`

- [ ] **Step 1: Write HomeViewModel tests**

Create `mobile/test/home_view_model_test.dart` with a fake workspace repository, cached conversation repository, and cached run repository. Test:

```dart
test('home deck updates when workspace repository notifies', () async {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
    ],
  );
  final conversationRepository = _FakeCachedConversationRepository();
  final runRepository = _FakeCachedRunRepository();
  final viewModel = HomeViewModel(
    workspaceRepository: workspaceRepository,
    conversationRepository: conversationRepository,
    runRepository: runRepository,
  );

  workspaceRepository.select('w2');

  expect(viewModel.currentWorkspace?.id, 'w2');
  expect(viewModel.deck?.now.workspaceId, 'w2');
});

test('home empty state does not require AppSnapshot', () async {
  final viewModel = HomeViewModel(
    workspaceRepository:
        _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
    conversationRepository: _FakeCachedConversationRepository(),
    runRepository: _FakeCachedRunRepository(),
  );

  expect(viewModel.currentWorkspace, isNull);
  expect(viewModel.deck, isNull);
});
```

The first test should create two workspaces, select the second through the repository, and expect `viewModel.currentWorkspace?.id` and `viewModel.deck.now.workspaceId` to change after notification.

- [ ] **Step 2: Write SettingsViewModel tests**

Create `mobile/test/settings_view_model_test.dart` with fake workspace and coding preference repositories. Test:

```dart
test('settings reflects selected workspace from repository', () async {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
    ],
  );
  final viewModel = _settingsViewModel(workspaceRepository);

  workspaceRepository.select('w2');

  expect(viewModel.selectedWorkspace?.id, 'w2');
});

test('settings updates permission mode through CodingPreferencesRepository',
    () async {
  final preferences = _FakeCodingPreferencesRepository();
  final viewModel = _settingsViewModel(
    _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
    preferences: preferences,
  );

  await viewModel.setPermissionMode('default');

  expect(preferences.permissionMode, 'default');
  expect(viewModel.permissionMode, 'default');
});

test('settings removes repository listeners on dispose', () async {
  final workspaceRepository =
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]);
  final viewModel = _settingsViewModel(workspaceRepository);

  viewModel.dispose();
  workspaceRepository.notifyForTest();

  expect(workspaceRepository.listenerCount, 0);
});
```

- [ ] **Step 3: Run failing ViewModel tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/home_view_model_test.dart test/settings_view_model_test.dart -r expanded
```

Expected: compile failures because the ViewModels do not exist.

- [ ] **Step 4: Implement HomeViewModel**

Create `mobile/lib/src/ui/pages/home_view_model.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../data/repositories/cached_conversation_repository.dart';
import '../../data/repositories/cached_run_repository.dart';
import '../../data/repositories/workspace_repository.dart';
import '../../models/protocol.dart';
import 'home_command_deck_model.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required WorkspaceRepository workspaceRepository,
    required CachedConversationRepository conversationRepository,
    required CachedRunRepository runRepository,
  })  : _workspaceRepository = workspaceRepository,
        _conversationRepository = conversationRepository,
        _runRepository = runRepository {
    _workspaceRepository.addListener(_onRepositoryChanged);
    _conversationRepository.addListener(_onRepositoryChanged);
    _runRepository.addListener(_onRepositoryChanged);
  }

  final WorkspaceRepository _workspaceRepository;
  final CachedConversationRepository _conversationRepository;
  final CachedRunRepository _runRepository;

  List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
  WorkspaceSummary? get currentWorkspace => _workspaceRepository.selectedWorkspace;

  HomeCommandDeckData? get deck {
    final workspace = currentWorkspace;
    if (workspace == null) return null;
    return buildHomeCommandDeckData(
      currentWorkspace: workspace,
      workspaces: _workspaceRepository.workspaces,
      runs: _runRepository.runs,
      conversations: _conversationRepository.conversations,
      queue: _runRepository.queue,
      changedFiles: null,
      diagnostics: null,
      recentFiles: null,
    );
  }

  Future<void> refresh() async {
    await Future.wait<void>([
      _workspaceRepository.refresh(),
      _conversationRepository.refresh(),
      _runRepository.refresh(),
    ]);
  }

  void _onRepositoryChanged() => notifyListeners();

  @override
  void dispose() {
    _workspaceRepository.removeListener(_onRepositoryChanged);
    _conversationRepository.removeListener(_onRepositoryChanged);
    _runRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
```

- [ ] **Step 5: Implement SettingsViewModel**

Create `mobile/lib/src/ui/features/settings/view_models/settings_view_model.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../../../data/repositories/coding_preferences_repository.dart';
import '../../../../data/repositories/workspace_repository.dart';
import '../../../../domain/models/daemon_connection_config.dart';
import '../../../../models/protocol.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required WorkspaceRepository workspaceRepository,
    required CodingPreferencesRepository codingPreferencesRepository,
    required DaemonConnectionConfig connectionConfig,
    required DaemonHealth health,
  })  : _workspaceRepository = workspaceRepository,
        _codingPreferencesRepository = codingPreferencesRepository,
        _connectionConfig = connectionConfig,
        _health = health {
    _workspaceRepository.addListener(_onRepositoryChanged);
    _codingPreferencesRepository.addListener(_onRepositoryChanged);
  }

  final WorkspaceRepository _workspaceRepository;
  final CodingPreferencesRepository _codingPreferencesRepository;
  DaemonConnectionConfig _connectionConfig;
  DaemonHealth _health;

  WorkspaceSummary? get selectedWorkspace => _workspaceRepository.selectedWorkspace;
  List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
  String get permissionMode => _codingPreferencesRepository.permissionMode;
  DaemonConnectionConfig get connectionConfig => _connectionConfig;
  DaemonHealth get health => _health;

  void updateShellInputs({
    required DaemonConnectionConfig connectionConfig,
    required DaemonHealth health,
  }) {
    _connectionConfig = connectionConfig;
    _health = health;
    notifyListeners();
  }

  Future<void> setPermissionMode(String value) =>
      _codingPreferencesRepository.setPermissionMode(value);

  void _onRepositoryChanged() => notifyListeners();

  @override
  void dispose() {
    _workspaceRepository.removeListener(_onRepositoryChanged);
    _codingPreferencesRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
```

- [ ] **Step 6: Convert pages to ViewModels**

Change `HomePage` constructor from:

```dart
required this.data
final AppSnapshot data;
```

to:

```dart
required this.viewModel
final HomeViewModel viewModel;
```

Wrap the body in:

```dart
return ListenableBuilder(
  listenable: viewModel,
  builder: (context, child) {
    final deck = viewModel.deck;
    if (deck == null) {
      return PageScroll(children: <Widget>[
        _AgentConsolePanel.empty(
          daemon: health,
          l10n: AppLocalizations.of(context),
          onWorkspaceTap: () => selectTab(1),
          onPrimaryTap: () => selectTab(1),
          onTemplatesTap: () => selectTab(1),
        ),
      ]);
    }
    return _HomePageBody(
      deck: deck,
      selectedWorkspace: viewModel.currentWorkspace!,
      open: open,
      selectTab: selectTab,
    );
  },
);
```

If `_AgentConsolePanel.empty` or `_HomePageBody` do not exist yet, extract them from the current `HomePage.build` body in the same task; the extracted widgets must receive already-projected values and must not receive `AppSnapshot`.

Change the settings wrapper and feature settings page so they accept:

```dart
final SettingsViewModel viewModel;
```

Replace `data.workspace`, `data.health`, and `permissionMode` reads with `viewModel.selectedWorkspace`, `viewModel.health`, and `viewModel.permissionMode`.

- [ ] **Step 7: Wire factories in AppDependencies**

Add `createHomeViewModel` and `createSettingsViewModel` factories to `FeatureDependencies`. They must receive `ConnectedDataDependencies` and the app-wide `CodingPreferencesRepository`.

- [ ] **Step 8: Run tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/home_view_model_test.dart test/settings_view_model_test.dart -r expanded
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```powershell
git add mobile/lib/src/ui/pages/home_view_model.dart mobile/lib/src/ui/pages/home_page.dart mobile/lib/src/ui/features/settings/view_models/settings_view_model.dart mobile/lib/src/ui/pages/settings_page.dart mobile/lib/src/ui/features/settings/settings_page.dart mobile/lib/src/app/app_dependencies.dart mobile/test/home_view_model_test.dart mobile/test/settings_view_model_test.dart
git commit -m "Add Home and Settings repository-backed ViewModels" -m "Constraint: Home and Settings no longer read AppSnapshot as runtime business state." -m "Tested: cd mobile && flutter test test/home_view_model_test.dart test/settings_view_model_test.dart -r expanded"
```

---

## Task 5: Convert WorkbenchViewModel To Repository-Owned Workspace State

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/ui/pages/coding/coding_page.dart`
- Test: `mobile/test/coding_workbench_controller_test.dart`
- Test: `mobile/test/workbench_view_model_repository_state_test.dart`

- [ ] **Step 1: Write workbench repository-state tests**

Create `mobile/test/workbench_view_model_repository_state_test.dart` with tests:

```dart
test('workbench exposes workspace list directly from repository', () async {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
    ],
  );
  final viewModel = _workbenchViewModel(workspaceRepository);

  expect(viewModel.workspaces.map((workspace) => workspace.id),
      const <String>['w1']);
});

test('openWorkspaceSessions falls back when repository select returns false',
    () async {
  final viewModel = _workbenchViewModel(
    _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
  );

  viewModel.openWorkspaceSessions('missing');

  expect(viewModel.routeState, isA<WorkspaceListRouteState>());
  expect(viewModel.error, contains('Workspace'));
});

test('createWorkspaceAndOpen routes to created workspace without AppSnapshot',
    () async {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[],
    createdWorkspace:
        const WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
  );
  final viewModel = _workbenchViewModel(workspaceRepository);

  await viewModel.createWorkspaceAndOpen(path: r'D:\new', name: 'New');

  final route = viewModel.routeState as WorkspaceSessionsRouteState;
  expect(route.workspaceId, 'new');
});

test('dispose removes workspace and adapter repository listeners', () async {
  final workspaceRepository =
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]);
  final adapterRepository = _FakeCachedAdapterRepository();
  final viewModel = _workbenchViewModel(
    workspaceRepository,
    adapterRepository: adapterRepository,
  );

  viewModel.dispose();

  expect(workspaceRepository.listenerCount, 0);
  expect(adapterRepository.listenerCount, 0);
});
```

Use fake listenable repositories with listener counters. The tests must not create an `AppSnapshot`.

- [ ] **Step 2: Run failing workbench tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/workbench_view_model_repository_state_test.dart -r expanded
```

Expected: compile failures because `WorkbenchViewModel` still requires `initialData` and stores route workspace lists/entities.

- [ ] **Step 3: Change route state to ids only**

In `workbench_view_model.dart`, replace route classes that carry workspace lists or `WorkspaceSummary` objects with:

```dart
sealed class WorkbenchRouteState {
  const WorkbenchRouteState();
}

final class WorkspaceListRouteState extends WorkbenchRouteState {
  const WorkspaceListRouteState({this.notice});
  final String? notice;
}

final class CreatingWorkspaceRouteState extends WorkbenchRouteState {
  const CreatingWorkspaceRouteState({required this.requestLabel});
  final String requestLabel;
}

final class WorkspaceSessionsRouteState extends WorkbenchRouteState {
  const WorkspaceSessionsRouteState({required this.workspaceId});
  final String workspaceId;
}

final class ConversationRouteState extends WorkbenchRouteState {
  const ConversationRouteState({
    required this.workspaceId,
    required this.conversationId,
  });

  final String workspaceId;
  final String conversationId;
}
```

- [ ] **Step 4: Rewrite WorkbenchViewModel constructor and repository listeners**

Replace `required AppSnapshot initialData` with required repositories:

```dart
WorkbenchViewModel({
  required WorkspaceRepository workspaceRepository,
  required CachedAdapterRepository adapterRepository,
  required CachedConversationRepository conversationRepository,
  required CachedRunRepository runRepository,
  required DiagnosticsRepository diagnosticsRepository,
  AttachmentPreviewCache attachmentPreviewCache =
      const NoopAttachmentPreviewCache(),
  Duration workspaceCreationTimeout = const Duration(seconds: 20),
})  : _workspaceRepository = workspaceRepository,
      _adapterRepository = adapterRepository,
      _conversationRepository = conversationRepository,
      _runRepository = runRepository,
      _diagnosticsRepository = diagnosticsRepository,
      _attachmentPreviewCache = attachmentPreviewCache,
      _workspaceCreationTimeout = workspaceCreationTimeout,
      _routeState = const WorkspaceListRouteState() {
  _workspaceRepository.addListener(_onRepositoryChanged);
  _adapterRepository.addListener(_onRepositoryChanged);
  _conversationRepository.addListener(_onRepositoryChanged);
  _runRepository.addListener(_onRepositoryChanged);
  _applyAdapters(_adapterRepository.adapters);
}
```

Add dispose cleanup:

```dart
@override
void dispose() {
  _workspaceRepository.removeListener(_onRepositoryChanged);
  _adapterRepository.removeListener(_onRepositoryChanged);
  _conversationRepository.removeListener(_onRepositoryChanged);
  _runRepository.removeListener(_onRepositoryChanged);
  _disposed = true;
  _modelUpdateGeneration++;
  super.dispose();
}
```

- [ ] **Step 5: Replace workspace getters and commands**

Use repository data directly:

```dart
List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
WorkspaceSummary? get selectedWorkspace => _workspaceRepository.selectedWorkspace;

WorkspaceSummary? get routeWorkspace => switch (_routeState) {
      WorkspaceSessionsRouteState(:final workspaceId) =>
        _workspaceById(workspaceId),
      ConversationRouteState(:final workspaceId) => _workspaceById(workspaceId),
      _ => null,
    };

WorkspaceSummary? _workspaceById(String id) {
  for (final workspace in _workspaceRepository.workspaces) {
    if (workspace.id == id) return workspace;
  }
  return null;
}
```

Add public commands:

```dart
Future<void> createWorkspaceAndOpen({
  required String path,
  String? name,
}) async {
  showCreatingWorkspace(requestLabel: name ?? path);
  try {
    final created = await _workspaceRepository.create(path: path, name: name);
    _routeState = WorkspaceSessionsRouteState(workspaceId: created.id);
    _error = null;
  } catch (error) {
    _routeState = WorkspaceListRouteState(notice: error.toString());
    _error = error.toString();
  }
  _notifyListeners();
}

void openWorkspaceSessions(String workspaceId) {
  final accepted = _workspaceRepository.select(workspaceId);
  if (!accepted) {
    _routeState = const WorkspaceListRouteState(
      notice: 'Workspace is no longer available.',
    );
    _notifyListeners();
    return;
  }
  _routeState = WorkspaceSessionsRouteState(workspaceId: workspaceId);
  _notifyListeners();
}
```

- [ ] **Step 6: Remove AppSnapshot update path**

Delete from `WorkbenchViewModel`:

```dart
void updateFromSnapshot(AppSnapshot snapshot)
void reconcile(AppSnapshot snapshot, {bool notify = true})
```

Replace `sessionItems(List<ConversationSummary> snapshotConversations, List<RunSummary> snapshotRuns)` with:

```dart
List<SessionItem> get sessionItems => mergeSessionItems(
      _optimisticSessions,
      _conversationRepository.conversations,
      _runRepository.runs,
    );
```

- [ ] **Step 7: Remove AppSnapshot from CodingWorkbenchPage**

In `coding_workbench_page.dart`, delete:

```dart
required this.data,
final AppSnapshot data;
```

Delete `didUpdateWidget` logic that calls:

```dart
_workbenchViewModel.updateFromSnapshot(widget.data);
```

Read current workspace from `viewModel.routeWorkspace ?? viewModel.selectedWorkspace`.

- [ ] **Step 8: Run tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/workbench_view_model_repository_state_test.dart -r expanded
flutter test test/coding_workbench_controller_test.dart -r expanded
```

Expected: all workbench tests pass.

- [ ] **Step 9: Commit**

```powershell
git add mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/src/ui/pages/coding/coding_page.dart mobile/test/workbench_view_model_repository_state_test.dart mobile/test/coding_workbench_controller_test.dart
git commit -m "Move workbench workspace state to repositories" -m "Constraint: workbench route state stores ids and does not reconcile runtime AppSnapshot data." -m "Tested: cd mobile && flutter test test/workbench_view_model_repository_state_test.dart -r expanded" -m "Tested: cd mobile && flutter test test/coding_workbench_controller_test.dart -r expanded"
```

---

## Task 6: Replace MainTabsViewModel With MainTabsShellViewModel

**Files:**
- Create: `mobile/lib/src/ui/view_models/main_tabs_shell_view_model.dart`
- Delete: `mobile/lib/src/ui/view_models/main_tabs_view_model.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Test: `mobile/test/main_tabs_shell_view_model_test.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write shell ViewModel tests**

Create `mobile/test/main_tabs_shell_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/shell/app_route.dart';
import 'package:lan_ai_cli_control/src/ui/view_models/main_tabs_shell_view_model.dart';

void main() {
  test('selectTab changes only shell state', () {
    final viewModel = MainTabsShellViewModel();

    viewModel.selectTab(1);

    expect(viewModel.activeTab, 1);
    expect(viewModel.activeRoute, RoutePage.tabs);
    expect(viewModel.openSessionListRequest, 1);
  });

  test('overlay is independent from business data', () {
    final viewModel = MainTabsShellViewModel();

    viewModel.openOverlay(RoutePage.approval);
    expect(viewModel.isOverlayActive, isTrue);

    viewModel.closeOverlay();
    expect(viewModel.isOverlayActive, isFalse);
  });
}
```

- [ ] **Step 2: Run failing shell tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/main_tabs_shell_view_model_test.dart -r expanded
```

Expected: compile failure because `MainTabsShellViewModel` does not exist.

- [ ] **Step 3: Implement shell-only ViewModel**

Create `mobile/lib/src/ui/view_models/main_tabs_shell_view_model.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../shell/app_route.dart';

class MainTabsShellViewModel extends ChangeNotifier {
  int _activeTab = 0;
  bool _codingSessionListOpen = true;
  int _openSessionListRequest = 0;
  RoutePage _activeRoute = RoutePage.tabs;

  int get activeTab => _activeTab;
  bool get codingSessionListOpen => _codingSessionListOpen;
  int get openSessionListRequest => _openSessionListRequest;
  RoutePage get activeRoute => _activeRoute;
  bool get isOverlayActive => _activeRoute != RoutePage.tabs;

  void openOverlay(RoutePage route) {
    _activeRoute = route;
    notifyListeners();
  }

  void closeOverlay() {
    _activeRoute = RoutePage.tabs;
    notifyListeners();
  }

  void selectTab(int index) {
    _activeTab = index;
    _activeRoute = RoutePage.tabs;
    if (index == 1) {
      _codingSessionListOpen = true;
      _openSessionListRequest++;
    }
    notifyListeners();
  }

  void reportSessionListOpen(bool open) {
    if (_codingSessionListOpen == open) return;
    _codingSessionListOpen = open;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Move adapter loading to repositories and feature ViewModels**

Delete `CodingAdapterLoadState`, `_adapterLoadState`, `_snapshotWithAdapters`, `ensureCodingAdaptersLoaded`, and `data` from the shell path. In `MainTabsPage.initState`, call:

```dart
unawaited(_connectedData.adapterRepository.load());
unawaited(_connectedData.workspaceRepository.load());
unawaited(_connectedData.conversationRepository.refresh());
unawaited(_connectedData.runRepository.refresh());
```

Adapter loading UI should observe `CachedAdapterRepository.loading/error` through WorkbenchViewModel or a small adapter gate widget that receives `CachedAdapterRepository`.

- [ ] **Step 5: Construct feature ViewModels in MainTabsPage**

Add fields:

```dart
late MainTabsShellViewModel _shellViewModel;
late HomeViewModel _homeViewModel;
late SettingsViewModel _settingsViewModel;
late WorkbenchViewModel _workbenchViewModel;
```

Dispose all four in `dispose`.

In `_buildShell`, pass ViewModels:

```dart
HomePage(
  open: _shellViewModel.openOverlay,
  selectTab: _shellViewModel.selectTab,
  viewModel: _homeViewModel,
),
CodingPage(
  workbenchViewModel: _workbenchViewModel,
  workbenchDependencies: _workbenchDependencies,
  workbenchKey: _codingWorkbenchKey,
  onBack: () => _shellViewModel.selectTab(0),
  onSessionListChanged: _shellViewModel.reportSessionListOpen,
  openSessionListRequest: _shellViewModel.openSessionListRequest,
),
SettingsPage(
  open: _shellViewModel.openOverlay,
  viewModel: _settingsViewModel,
  appUpdateViewModel: _appUpdateViewModel,
),
```

- [ ] **Step 6: Delete old MainTabsViewModel**

Remove `mobile/lib/src/ui/view_models/main_tabs_view_model.dart` after all imports and tests use `MainTabsShellViewModel`.

- [ ] **Step 7: Run shell tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/main_tabs_shell_view_model_test.dart -r expanded
flutter test test/widget_test.dart -r expanded --name "opening coding tab|returning to coding tab|system back"
```

Expected: all shell-focused tests pass.

- [ ] **Step 8: Commit**

```powershell
git add mobile/lib/src/ui/view_models/main_tabs_shell_view_model.dart mobile/lib/src/ui/view_models/main_tabs_view_model.dart mobile/lib/src/ui/main_tabs_page.dart mobile/lib/src/app/app_dependencies.dart mobile/test/main_tabs_shell_view_model_test.dart mobile/test/widget_test.dart
git add -u mobile/lib/src/ui/view_models/main_tabs_view_model.dart
git commit -m "Reduce main tabs to shell state" -m "Constraint: MainTabsShellViewModel owns navigation only and never stores AppSnapshot business data." -m "Tested: cd mobile && flutter test test/main_tabs_shell_view_model_test.dart -r expanded" -m "Tested: cd mobile && flutter test test/widget_test.dart -r expanded --name \"opening coding tab|returning to coding tab|system back\""
```

---

## Task 7: Remove Runtime AppSnapshot From Home, Settings, Workbench, And MainTabs

**Files:**
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/pages/home_page.dart`
- Modify: `mobile/lib/src/ui/pages/settings_page.dart`
- Modify: `mobile/lib/src/ui/pages/coding/coding_page.dart`
- Modify: `mobile/lib/src/ui/features/settings/settings_page.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/shell/app_snapshot.dart`
- Test: `mobile/test/widget_test.dart`
- Test: `mobile/test/app_snapshot_bootstrap_test.dart`

- [ ] **Step 1: Add tab-switch regression test**

In `mobile/test/widget_test.dart`, add a test that:

1. Starts connected with no selected runtime workspace or with an empty workspace list bootstrap.
2. Creates a workspace through the workbench/add-workspace path.
3. Verifies the new workspace is visible in the workbench session route.
4. Switches to Settings.
5. Switches back to Workbench.
6. Verifies the same new workspace is still visible without restarting.

The assertion should look for the created workspace name or path after the second tab switch.

- [ ] **Step 2: Run the failing regression**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/widget_test.dart -r expanded --name "created workspace remains visible after tab switch"
```

Expected before the final cutover: failure or compile errors caused by remaining `AppSnapshot` runtime paths.

- [ ] **Step 3: Remove `AppSnapshot data` constructor parameters**

Delete `data` fields from:

```text
mobile/lib/src/ui/pages/home_page.dart
mobile/lib/src/ui/pages/settings_page.dart
mobile/lib/src/ui/pages/coding/coding_page.dart
mobile/lib/src/ui/features/settings/settings_page.dart
mobile/lib/src/ui/features/workbench/coding_workbench_page.dart
```

Use the ViewModel inputs introduced in Tasks 4-6 instead.

- [ ] **Step 4: Restrict AppSnapshot to bootstrap**

In `mobile/lib/src/shell/app_snapshot.dart`, keep `load`, `loadBootstrap`, `toDaemonInitialData`, and `toAppSnapshot` only for connection bootstrap and tests. Add a file comment:

```dart
// AppSnapshot is a bootstrap/compatibility DTO. Connected runtime business
// state is owned by repositories and projected through feature ViewModels.
```

Do not import `AppSnapshot` from `home_page.dart`, `settings_page.dart`, `coding_page.dart`, `coding_workbench_page.dart`, or `main_tabs_view_model.dart`.

- [ ] **Step 5: Run runtime-state scans**

Run:

```powershell
rg "AppSnapshot|get data =>|updateData\\(|updateFromSnapshot\\(|viewModel\\.data|widget\\.data" mobile/lib/src/ui mobile/lib/src/app -n
```

Expected allowed matches only in:

```text
mobile/lib/src/ui/main_route_overlay.dart
mobile/lib/src/ui/features/adapters/
mobile/lib/src/ui/features/sessions/
```

Those are not part of this bug's Home/Settings/Workbench/MainTabs runtime state cutover. The command must not print:

```text
mobile/lib/src/ui/main_tabs_page.dart:<line>: viewModel.data
mobile/lib/src/ui/view_models/main_tabs_view_model.dart
mobile/lib/src/ui/pages/home_page.dart
mobile/lib/src/ui/pages/settings_page.dart
mobile/lib/src/ui/pages/coding/coding_page.dart
mobile/lib/src/ui/features/settings/settings_page.dart
mobile/lib/src/ui/features/workbench/coding_workbench_page.dart
mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart:<line>: updateFromSnapshot
```

- [ ] **Step 6: Run tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/widget_test.dart -r expanded --name "created workspace remains visible after tab switch"
flutter test test/app_snapshot_bootstrap_test.dart -r expanded
```

Expected: regression and bootstrap tests pass.

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/ui/main_tabs_page.dart mobile/lib/src/ui/pages/home_page.dart mobile/lib/src/ui/pages/settings_page.dart mobile/lib/src/ui/pages/coding/coding_page.dart mobile/lib/src/ui/features/settings/settings_page.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/src/shell/app_snapshot.dart mobile/test/widget_test.dart mobile/test/app_snapshot_bootstrap_test.dart
git commit -m "Remove runtime AppSnapshot from connected tabs" -m "Constraint: AppSnapshot remains bootstrap-only; Home, Settings, Workbench, and MainTabs use repositories plus feature ViewModels." -m "Tested: cd mobile && flutter test test/widget_test.dart -r expanded --name \"created workspace remains visible after tab switch\"" -m "Tested: cd mobile && flutter test test/app_snapshot_bootstrap_test.dart -r expanded"
```

---

## Task 8: Final Cleanup And Architecture Verification

**Files:**
- Modify only if checks reveal missed imports or stale tests:
  `mobile/lib/src/app/app_dependencies.dart`,
  `mobile/lib/src/ui/main_tabs_page.dart`,
  `mobile/lib/src/ui/pages/home_page.dart`,
  `mobile/lib/src/ui/pages/settings_page.dart`,
  `mobile/lib/src/ui/pages/coding/coding_page.dart`,
  `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`,
  `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`,
  `mobile/test/`

- [ ] **Step 1: Run architecture import checker**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool/check_architecture_imports.dart
```

Expected: no forbidden imports. Domain must not import Flutter; listenable repository contracts must be under `data/repositories/`.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run focused test suite**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test/workspace_repository_test.dart test/cached_connected_repositories_test.dart test/coding_preferences_repository_test.dart test/home_view_model_test.dart test/settings_view_model_test.dart test/workbench_view_model_repository_state_test.dart test/main_tabs_shell_view_model_test.dart -r expanded
flutter test test/coding_workbench_controller_test.dart -r expanded
flutter test test/widget_test.dart -r expanded --name "created workspace remains visible after tab switch|opening coding tab|returning to coding tab|system back|settings"
```

Expected: all focused tests pass.

- [ ] **Step 4: Run state-source scans**

Run:

```powershell
rg "MainTabsViewModel|MainTabsViewModel\\.data|viewModel\\.data|updateFromSnapshot\\(|CodingPreferencesStore\\(" mobile/lib mobile/test -n
rg "AppSnapshot" mobile/lib/src/ui/main_tabs_page.dart mobile/lib/src/ui/pages/home_page.dart mobile/lib/src/ui/pages/settings_page.dart mobile/lib/src/ui/pages/coding/coding_page.dart mobile/lib/src/ui/features/settings/settings_page.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart -n
```

Expected: no matches. Remaining `AppSnapshot` matches outside these target files must be bootstrap, overlay compatibility, or other explicitly un-migrated features.

- [ ] **Step 5: Run doc/spec consistency checks**

Run:

```powershell
node scripts/check-project-knowledge.js
git diff --check
```

Expected: both checks pass.

- [ ] **Step 6: Commit final verification fixes if any**

If Steps 1-5 require small missed-import or stale-test fixes, commit them:

```powershell
git add mobile docs
git commit -m "Complete repository-owned state migration cleanup" -m "Constraint: only final stale imports, stale tests, and verification cleanup." -m "Tested: cd mobile && dart run tool/check_architecture_imports.dart" -m "Tested: cd mobile && dart analyze" -m "Tested: focused Flutter tests from Task 8"
```

If no files changed during Task 8, do not create an empty commit. Report the verification evidence in the final handoff.

---

## Acceptance Criteria

- Creating a workspace in Workbench updates `WorkspaceRepository` and every subscribed ViewModel sees the same workspace without restart.
- Switching Workbench -> Settings -> Workbench no longer reapplies stale `AppSnapshot` data and no longer hides the newly created workspace.
- `MainTabsShellViewModel` has no `AppSnapshot`, no business data getters, no adapter cache, and no workspace/session/conversation lists.
- `HomePage`, `SettingsPage`, `CodingPage`, and `CodingWorkbenchPage` do not receive `AppSnapshot` as runtime data.
- `WorkbenchViewModel.updateFromSnapshot` and `MainTabsViewModel.data` are removed.
- `CodingPreferencesStore` is not a runtime state owner; `CodingPreferencesRepository` owns permission-mode state.
- Every ViewModel that subscribes to a repository removes the listener in `dispose`.
- `cd mobile && dart run tool/check_architecture_imports.dart` passes.
- Focused repository/ViewModel/widget regression tests pass.
