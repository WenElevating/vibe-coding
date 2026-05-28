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
    expect(
      repository.workspaces.map((workspace) => workspace.id),
      const <String>['w1'],
    );
    expect(repository.selectedWorkspace?.id, 'w1');
    expect(notifications, greaterThanOrEqualTo(2));
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
      var notifications = 0;
      repository.addListener(() => notifications++);

      final created = await repository.create(path: r'D:\new', name: 'New');

      expect(created.id, 'new');
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['old', 'new'],
      );
      expect(repository.selectedWorkspace?.id, 'new');
      expect(notifications, greaterThanOrEqualTo(2));
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
    'create failure preserves previous catalog and selected workspace',
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
      expect(
        repository.workspaces.map((workspace) => workspace.id),
        const <String>['w1'],
      );
      expect(repository.selectedWorkspace?.id, 'w1');
    },
  );
}

class _FakeWorkspaceDaemonClient implements DaemonClient {
  _FakeWorkspaceDaemonClient({
    required List<WorkspaceSummary> workspaces,
    WorkspaceSummary? createdWorkspace,
    List<WorkspaceSummary>? refreshedWorkspaces,
  }) : _workspaces = workspaces,
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
    final created =
        _createdWorkspace ??
        WorkspaceSummary(id: 'created', name: name ?? path, path: path);
    _workspaces =
        _refreshedWorkspaces ?? <WorkspaceSummary>[..._workspaces, created];
    return created;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
