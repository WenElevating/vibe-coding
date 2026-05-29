import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/view_models/workbench_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/workbench_route_state.dart';

void main() {
  group('WorkbenchViewModel repository-owned state', () {
    test('workbench exposes workspace list directly from repository', () {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
          WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      expect(
        viewModel.workspaces.map((w) => w.id),
        const <String>['w1', 'w2'],
      );
    });

    test('workspace list updates when repository notifies', () {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      workspaceRepository.updateWorkspaces(const <WorkspaceSummary>[
        WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
      ]);

      expect(
        viewModel.workspaces.map((w) => w.id),
        const <String>['w1', 'w2'],
      );
    });

    test(
        'openWorkspaceSessions falls back to workspace list when repository select returns false',
        () {
      final viewModel = _workbenchViewModel(
        _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      );

      viewModel.openWorkspaceSessions('missing');

      expect(viewModel.routeState, isA<WorkspaceListRouteState>());
    });

    test(
        'openWorkspaceSessions routes to sessions when repository select returns true',
        () {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      viewModel.openWorkspaceSessions('w1');

      final route = viewModel.routeState as WorkspaceSessionsRouteState;
      expect(route.workspaceId, 'w1');
    });

    test(
        'createWorkspaceAndOpen routes to created workspace without AppSnapshot',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[],
        createdWorkspace: const WorkspaceSummary(
          id: 'new',
          name: 'New',
          path: r'D:\new',
        ),
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      await viewModel.createWorkspaceAndOpen(path: r'D:\new', name: 'New');

      final route = viewModel.routeState as WorkspaceSessionsRouteState;
      expect(route.workspaceId, 'new');
    });

    test('createWorkspaceAndOpen returns to list on creation failure',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[],
      )..createError = StateError('create failed');
      final viewModel = _workbenchViewModel(workspaceRepository);

      await viewModel.createWorkspaceAndOpen(path: r'D:\bad');

      expect(viewModel.routeState, isA<WorkspaceListRouteState>());
    });

    test('dispose removes workspace and adapter repository listeners', () {
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

    test('selected workspace comes from repository', () {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
          WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      // Default selected workspace is first.
      expect(viewModel.selectedWorkspace?.id, 'w1');

      workspaceRepository.select('w2');
      expect(viewModel.selectedWorkspace?.id, 'w2');
    });

    test('routeWorkspace resolves workspace id from repository', () {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      viewModel.openWorkspaceSessions('w1');

      expect(viewModel.routeWorkspace, isNotNull);
      expect(viewModel.routeWorkspace?.id, 'w1');
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

WorkbenchViewModel _workbenchViewModel(
  _FakeWorkspaceRepository workspaceRepository, {
  _FakeCachedAdapterRepository? adapterRepository,
}) {
  return WorkbenchViewModel(
    workspaceRepository: workspaceRepository,
    adapterRepository: adapterRepository ?? _FakeCachedAdapterRepository(),
    conversationRepository: _FakeCachedConversationRepository(),
    runRepository: _FakeCachedRunRepository(),
  );
}

// ---------------------------------------------------------------------------
// Fake workspace repository
// ---------------------------------------------------------------------------

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({
    required List<WorkspaceSummary> workspaces,
    WorkspaceSummary? createdWorkspace,
  })  : _workspaces = List<WorkspaceSummary>.of(workspaces),
        _createdWorkspace = createdWorkspace;

  List<WorkspaceSummary> _workspaces;
  final WorkspaceSummary? _createdWorkspace;
  WorkspaceSummary? _selectedWorkspace;
  Object? createError;

  int get listenerCount => _listenerCount;
  int _listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    _listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listenerCount--;
    super.removeListener(listener);
  }

  void notifyForTest() => notifyListeners();

  void updateWorkspaces(List<WorkspaceSummary> updated) {
    _workspaces = List<WorkspaceSummary>.of(updated);
    notifyListeners();
  }

  // -- WorkspaceRepository (data contract) --

  @override
  List<WorkspaceSummary> get workspaces => List.unmodifiable(_workspaces);

  @override
  WorkspaceSummary? get selectedWorkspace {
    if (_selectedWorkspace != null) {
      for (final w in _workspaces) {
        if (w.id == _selectedWorkspace!.id) return w;
      }
    }
    return _workspaces.isEmpty ? null : _workspaces.first;
  }

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({
    required String path,
    String? name,
  }) async {
    final error = createError;
    if (error != null) throw error;
    final created = _createdWorkspace ??
        WorkspaceSummary(id: 'created', name: name ?? path, path: path);
    _workspaces.add(created);
    _selectedWorkspace = created;
    notifyListeners();
    return created;
  }

  @override
  bool select(String workspaceId) {
    if (!_workspaces.any((w) => w.id == workspaceId)) return false;
    _selectedWorkspace = _workspaces.firstWhere((w) => w.id == workspaceId);
    notifyListeners();
    return true;
  }

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    _workspaces = List<WorkspaceSummary>.of(workspaces);
    _selectedWorkspace = selectedWorkspace;
  }

  // -- domain WorkspaceRepository (pure Dart contract) --

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      List<WorkspaceSummary>.of(_workspaces);

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) =>
      create(path: path, name: name);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Fake cached adapter repository
// ---------------------------------------------------------------------------

class _FakeCachedAdapterRepository extends CachedAdapterRepository {
  _FakeCachedAdapterRepository() : super(delegate: _NoOpAdapterRepository());

  int get listenerCount => _listenerCount;
  int _listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    _listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listenerCount--;
    super.removeListener(listener);
  }

  @override
  List<AdapterStatus> get adapters => const <AdapterStatus>[];
}

class _NoOpAdapterRepository implements AdapterRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCachedConversationRepository extends CachedConversationRepository {
  _FakeCachedConversationRepository()
      : super(delegate: _NoOpConversationRepository());

  @override
  List<ConversationSummary> get conversations => const <ConversationSummary>[];
}

class _NoOpConversationRepository implements ConversationRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCachedRunRepository extends CachedRunRepository {
  _FakeCachedRunRepository() : super(delegate: _NoOpRunRepository());

  @override
  List<RunSummary> get runs => const <RunSummary>[];
}

class _NoOpRunRepository implements RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
