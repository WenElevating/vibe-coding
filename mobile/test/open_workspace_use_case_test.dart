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

  test('open workspace applies catalog when selected workspace is absent',
      () async {
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
          const DaemonInitialData(
        health: _health,
        workspaces: <WorkspaceSummary>[_workspace2],
        workspace: null,
        adapters: <AdapterStatus>[],
        conversations: <ConversationSummary>[],
        runs: <RunSummary>[],
        queue: <QueueItem>[],
      ),
      workspaceRepository: workspaceRepository,
      conversationRepository: conversationRepository,
      runRepository: runRepository,
    );

    await useCase.open(
      workspaces: const <WorkspaceSummary>[_workspace1, _workspace2],
      workspace: _workspace2,
    );

    expect(workspaceRepository.workspaces.map((workspace) => workspace.id),
        const <String>['w2']);
    expect(workspaceRepository.selectedWorkspace, isNull);
    expect(conversationRepository.loadedWorkspaceId, isNull);
    expect(runRepository.loadedWorkspaceId, isNull);
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
