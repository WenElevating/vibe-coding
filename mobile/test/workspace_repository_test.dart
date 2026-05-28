import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_workspace_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/auth_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/workflows/workspace/create_workspace_workflow.dart';

void main() {
  test('load caches workspaces and notifies listeners', () async {
    final client = _FakeWorkspaceDaemonClient(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      ],
    );
    final repository = DaemonWorkspaceRepository(client: client);
    final snapshots = <_RepositorySnapshot>[];
    repository.addListener(() {
      snapshots.add(_RepositorySnapshot.from(repository));
    });

    await repository.load();

    expect(repository.loading, isFalse);
    expect(repository.error, isNull);
    expect(
      repository.workspaces.map((workspace) => workspace.id),
      const <String>['w1'],
    );
    expect(repository.selectedWorkspace?.id, 'w1');
    expect(snapshots, hasLength(2));
    expect(snapshots.first.loading, isTrue);
    expect(snapshots.first.error, isNull);
    expect(snapshots.first.workspaceIds, isEmpty);
    expect(snapshots.last.loading, isFalse);
    expect(snapshots.last.error, isNull);
    expect(snapshots.last.workspaceIds, const <String>['w1']);
    expect(snapshots.last.selectedWorkspaceId, 'w1');
  });

  test('listWorkspaces refreshes cache and notifies listeners', () async {
    final client = _FakeWorkspaceDaemonClient(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      ],
    );
    final repository = DaemonWorkspaceRepository(client: client);
    final snapshots = <_RepositorySnapshot>[];
    repository.addListener(() {
      snapshots.add(_RepositorySnapshot.from(repository));
    });

    final listed = await repository.listWorkspaces();

    expect(listed.map((workspace) => workspace.id), const <String>['w1']);
    expect(
      repository.workspaces.map((workspace) => workspace.id),
      const <String>['w1'],
    );
    expect(repository.selectedWorkspace?.id, 'w1');
    expect(snapshots, hasLength(2));
    expect(snapshots.first.loading, isTrue);
    expect(snapshots.first.workspaceIds, isEmpty);
    expect(snapshots.last.loading, isFalse);
    expect(snapshots.last.workspaceIds, const <String>['w1']);
    expect(snapshots.last.selectedWorkspaceId, 'w1');
  });

  test(
    'create refreshes catalog, selects created workspace, and notifies',
    () async {
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
        ],
        createdWorkspace: const WorkspaceSummary(
          id: 'new',
          name: 'New',
          path: r'D:\new',
        ),
        refreshedWorkspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
          WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
        ],
      );
      final repository = DaemonWorkspaceRepository(client: client);
      await repository.load();
      final snapshots = <_RepositorySnapshot>[];
      repository.addListener(() {
        snapshots.add(_RepositorySnapshot.from(repository));
      });

      final created = await repository.create(path: r'D:\new', name: 'New');

      expect(created.id, 'new');
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['old', 'new'],
      );
      expect(repository.selectedWorkspace?.id, 'new');
      expect(snapshots, hasLength(2));
      expect(snapshots.first.loading, isTrue);
      expect(snapshots.first.error, isNull);
      expect(snapshots.first.workspaceIds, const <String>['old']);
      expect(snapshots.first.selectedWorkspaceId, 'old');
      expect(snapshots.last.loading, isFalse);
      expect(snapshots.last.error, isNull);
      expect(snapshots.last.workspaceIds, const <String>['old', 'new']);
      expect(snapshots.last.selectedWorkspaceId, 'new');
    },
  );

  test(
    'createWorkspace refreshes catalog and selects created workspace',
    () async {
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
        ],
        createdWorkspace: const WorkspaceSummary(
          id: 'new',
          name: 'New',
          path: r'D:\new',
        ),
        refreshedWorkspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
          WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
        ],
      );
      final repository = DaemonWorkspaceRepository(client: client);
      await repository.load();
      final snapshots = <_RepositorySnapshot>[];
      repository.addListener(() {
        snapshots.add(_RepositorySnapshot.from(repository));
      });

      final created =
          await repository.createWorkspace(path: r'D:\new', name: 'New');

      expect(created.id, 'new');
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['old', 'new'],
      );
      expect(repository.selectedWorkspace?.id, 'new');
      expect(snapshots, hasLength(2));
      expect(snapshots.first.loading, isTrue);
      expect(snapshots.last.loading, isFalse);
      expect(snapshots.last.workspaceIds, const <String>['old', 'new']);
      expect(snapshots.last.selectedWorkspaceId, 'new');
    },
  );

  test(
    'select returns false for unknown workspace without notifying',
    () async {
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
    },
  );

  test(
    'select returns true for fallback first workspace without notifying',
    () async {
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

      final accepted = repository.select('w1');

      expect(accepted, isTrue);
      expect(repository.selectedWorkspace?.id, 'w1');
      expect(notifications, 0);
    },
  );

  test(
    'applyBootstrapCatalog seeds and pins selected workspace before refresh',
    () async {
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
          WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        ],
      );
      final repository = DaemonWorkspaceRepository(client: client);

      repository.applyBootstrapCatalog(
        selectedWorkspace:
            const WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
          WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        ],
      );

      expect(repository.selectedWorkspace?.id, 'w2');
      await repository.refresh();
      expect(repository.selectedWorkspace?.id, 'w2');
    },
  );

  test(
    'explicitly selecting fallback first workspace survives refreshed reorder',
    () async {
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
          WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        ],
      );
      final repository = DaemonWorkspaceRepository(client: client);
      await repository.load();
      var notifications = 0;
      repository.addListener(() => notifications++);

      final accepted = repository.select('w1');

      client.workspaces = const <WorkspaceSummary>[
        WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
      ];
      await repository.refresh();

      expect(accepted, isTrue);
      expect(repository.selectedWorkspace?.id, 'w1');
      expect(notifications, 2);
    },
  );

  test(
    'create failure preserves previous catalog and selected workspace',
    () async {
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      )..createError = StateError('create failed');
      final repository = DaemonWorkspaceRepository(client: client);
      await repository.load();
      final snapshots = <_RepositorySnapshot>[];
      repository.addListener(() {
        snapshots.add(_RepositorySnapshot.from(repository));
      });

      await expectLater(
        repository.create(path: r'D:\bad'),
        throwsA(isA<StateError>()),
      );

      expect(repository.loading, isFalse);
      expect(repository.error, isA<StateError>());
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['w1'],
      );
      expect(repository.selectedWorkspace?.id, 'w1');
      expect(snapshots, hasLength(2));
      expect(snapshots.first.loading, isTrue);
      expect(snapshots.first.error, isNull);
      expect(snapshots.last.loading, isFalse);
      expect(snapshots.last.error, isA<StateError>());
      expect(snapshots.last.workspaceIds, const <String>['w1']);
      expect(snapshots.last.selectedWorkspaceId, 'w1');
    },
  );

  test(
    'stale overlapping refresh does not overwrite newer create result',
    () async {
      final refreshCompleter = Completer<List<WorkspaceSummary>>();
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
        ],
        createdWorkspace: const WorkspaceSummary(
          id: 'new',
          name: 'New',
          path: r'D:\new',
        ),
        refreshedWorkspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
          WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
        ],
      )..queuedListWorkspaces.add(refreshCompleter.future);
      final repository = DaemonWorkspaceRepository(client: client);

      final staleRefresh = repository.refresh();
      await pumpEventQueue();

      final created = await repository.create(path: r'D:\new', name: 'New');
      refreshCompleter.complete(const <WorkspaceSummary>[
        WorkspaceSummary(id: 'stale', name: 'Stale', path: r'D:\stale'),
      ]);
      await staleRefresh;

      expect(created.id, 'new');
      expect(repository.loading, isFalse);
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['old', 'new'],
      );
      expect(repository.selectedWorkspace?.id, 'new');
    },
  );

  test(
    'stale listWorkspaces returns fetched list without overwriting newer cache',
    () async {
      final staleListCompleter = Completer<List<WorkspaceSummary>>();
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
        ],
        createdWorkspace: const WorkspaceSummary(
          id: 'new',
          name: 'New',
          path: r'D:\new',
        ),
        refreshedWorkspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
          WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
        ],
      )..queuedListWorkspaces.add(staleListCompleter.future);
      final repository = DaemonWorkspaceRepository(client: client);

      final staleList = repository.listWorkspaces();
      await pumpEventQueue();

      await repository.create(path: r'D:\new', name: 'New');
      staleListCompleter.complete(const <WorkspaceSummary>[
        WorkspaceSummary(id: 'stale', name: 'Stale', path: r'D:\stale'),
      ]);
      final listed = await staleList;

      expect(listed.map((workspace) => workspace.id), const <String>['stale']);
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['old', 'new'],
      );
      expect(repository.selectedWorkspace?.id, 'new');
      expect(repository.loading, isFalse);
    },
  );

  test(
    'CreateWorkspaceWorkflow updates repository catalog and selection',
    () async {
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
        ],
        createdWorkspace: const WorkspaceSummary(
          id: 'new',
          name: 'New',
          path: r'D:\new',
        ),
        refreshedWorkspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'old', name: 'Old', path: r'D:\old'),
          WorkspaceSummary(id: 'new', name: 'New', path: r'D:\new'),
        ],
      );
      final repository = DaemonWorkspaceRepository(client: client);
      final workflow = CreateWorkspaceWorkflow(
        client: repository,
        timeout: const Duration(seconds: 1),
      );

      final outcome = await workflow.create(path: r'D:\new', name: 'New');

      expect(outcome, isA<CreateWorkspaceSuccess>());
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['old', 'new'],
      );
      expect(repository.selectedWorkspace?.id, 'new');
    },
  );

  test('ConnectedDataDependencies disposes workspace repository once',
      () async {
    final workspaceRepository = _DisposableWorkspaceRepository();
    final dependencies = ConnectedDataDependencies(
      authRepository: _UnusedRepository(),
      adapterRepository: _UnusedRepository(),
      appUpdateRepository: _UnusedRepository(),
      conversationRepository: _UnusedRepository(),
      diagnosticsRepository: _UnusedRepository(),
      runRepository: _UnusedRepository(),
      workspaceRepository: workspaceRepository,
    );

    await dependencies.dispose();
    await dependencies.dispose();

    expect(workspaceRepository.disposeCalls, 1);
  });

  test(
    'pending refresh completion after dispose does not notify or mutate',
    () async {
      final refreshCompleter = Completer<List<WorkspaceSummary>>();
      final client = _FakeWorkspaceDaemonClient(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'initial', name: 'Initial', path: r'D:\initial'),
        ],
      )..queuedListWorkspaces.add(refreshCompleter.future);
      final repository = DaemonWorkspaceRepository(client: client);
      var notifications = 0;
      repository.addListener(() => notifications++);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();

      expect(notifications, 1);
      repository.dispose();
      refreshCompleter.complete(const <WorkspaceSummary>[
        WorkspaceSummary(id: 'late', name: 'Late', path: r'D:\late'),
      ]);

      await pendingRefresh;

      expect(notifications, 1);
      expect(repository.workspaces, isEmpty);
      expect(repository.selectedWorkspace, isNull);
    },
  );
}

class _RepositorySnapshot {
  const _RepositorySnapshot({
    required this.loading,
    required this.error,
    required this.workspaceIds,
    required this.selectedWorkspaceId,
  });

  factory _RepositorySnapshot.from(DaemonWorkspaceRepository repository) =>
      _RepositorySnapshot(
        loading: repository.loading,
        error: repository.error,
        workspaceIds: repository.workspaces
            .map((workspace) => workspace.id)
            .toList(growable: false),
        selectedWorkspaceId: repository.selectedWorkspace?.id,
      );

  final bool loading;
  final Object? error;
  final List<String> workspaceIds;
  final String? selectedWorkspaceId;
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
  final queuedListWorkspaces = <Future<List<WorkspaceSummary>>>[];
  Object? createError;

  set workspaces(List<WorkspaceSummary> value) {
    _workspaces = value;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    if (queuedListWorkspaces.isNotEmpty) {
      return queuedListWorkspaces.removeAt(0);
    }
    return _workspaces;
  }

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async {
    final error = createError;
    if (error != null) throw error;
    final created = _createdWorkspace ??
        WorkspaceSummary(id: 'created', name: name ?? path, path: path);
    _workspaces =
        _refreshedWorkspaces ?? <WorkspaceSummary>[..._workspaces, created];
    return created;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DisposableWorkspaceRepository extends _UnusedRepository {
  var disposeCalls = 0;

  @override
  void dispose() {
    disposeCalls += 1;
    super.dispose();
  }
}

class _UnusedRepository extends WorkspaceRepository
    implements
        AdapterRepository,
        AppUpdateRepository,
        AuthRepository,
        ConversationRepository,
        DiagnosticsRepository,
        RunRepository {
  @override
  List<WorkspaceSummary> get workspaces => const <WorkspaceSummary>[];

  @override
  WorkspaceSummary? get selectedWorkspace => null;

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) =>
      throw UnimplementedError();

  @override
  bool select(String workspaceId) => false;

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {}

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() => throw UnimplementedError();

  @override
  Future<WorkspaceSummary> createWorkspace(
          {required String path, String? name}) =>
      throw UnimplementedError();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
