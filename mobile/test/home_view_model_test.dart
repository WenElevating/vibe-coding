import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/main/home/home.dart';

const _conversationCapabilities = ConversationCapabilities(
  longLivedProcess: false,
  waitingInput: false,
  waitingApproval: false,
  resume: false,
  partialOutput: false,
);

void main() {
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

  test('home deck includes bootstrap workspace signal metrics', () async {
    final viewModel = HomeViewModel(
      workspaceRepository: _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      ),
      conversationRepository: _FakeCachedConversationRepository(),
      runRepository: _FakeCachedRunRepository(),
      signalMetrics: const HomeWorkspaceSignalMetrics(
        changedFiles: 3,
        diagnostics: 2,
        recentFiles: 5,
      ),
    );

    expect(viewModel.deck?.signals.changedFiles, 3);
    expect(viewModel.deck?.signals.diagnostics, 2);
    expect(viewModel.deck?.signals.recentFiles, 5);
  });

  test('home renders repository bootstrap data without refresh', () async {
    final conversationRepository = _FakeCachedConversationRepository()
      ..replaceFromBootstrap(
        workspaceId: 'w1',
        conversations: const <ConversationSummary>[
          ConversationSummary(
            id: 'c1',
            workspaceId: 'w1',
            adapter: 'codex',
            status: 'idle',
            capabilities: _conversationCapabilities,
            createdAt: '2026-05-29T00:00:00.000Z',
            updatedAt: '2026-05-29T00:00:00.000Z',
          ),
        ],
      );
    final runRepository = _FakeCachedRunRepository()
      ..replaceFromBootstrap(
        workspaceId: 'w1',
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'completed',
          ),
        ],
        queue: const <QueueItem>[
          QueueItem(
            runId: 'r1',
            workspaceId: 'w1',
            position: 1,
            status: 'queued',
            reason: 'waiting',
          ),
        ],
      );
    final viewModel = HomeViewModel(
      workspaceRepository: _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      ),
      conversationRepository: conversationRepository,
      runRepository: runRepository,
    );

    final deck = viewModel.deck;
    expect(deck, isNotNull);
    expect(deck!.now.id, 'queue:r1');
    expect(deck.signals.queue, 1);
    expect(
      deck.allSignals.map((signal) => signal.id),
      containsAll(const <String>['queue:r1', 'run:r1']),
    );
    expect(deck.workspaceRunSummaries.single.latestRunId, 'r1');
    expect(conversationRepository.refreshCalls, 0);
    expect(runRepository.refreshCalls, 0);
  });

  test('home deck updates when bootstrap workspace signal metrics change',
      () async {
    final viewModel = HomeViewModel(
      workspaceRepository: _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      ),
      conversationRepository: _FakeCachedConversationRepository(),
      runRepository: _FakeCachedRunRepository(),
    );
    var notifications = 0;
    viewModel.addListener(() => notifications += 1);

    viewModel.updateSignalMetrics(
      const HomeWorkspaceSignalMetrics(
        changedFiles: 4,
        diagnostics: 1,
        recentFiles: 7,
      ),
    );

    expect(notifications, 1);
    expect(viewModel.deck?.signals.changedFiles, 4);
    expect(viewModel.deck?.signals.diagnostics, 1);
    expect(viewModel.deck?.signals.recentFiles, 7);
  });

  test('home refresh delegates to all repositories', () async {
    final workspaceRepository =
        _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]);
    final conversationRepository = _FakeCachedConversationRepository();
    final runRepository = _FakeCachedRunRepository();
    final viewModel = HomeViewModel(
      workspaceRepository: workspaceRepository,
      conversationRepository: conversationRepository,
      runRepository: runRepository,
    );

    await viewModel.refresh();

    expect(workspaceRepository.refreshCalls, 1);
    expect(conversationRepository.refreshCalls, 1);
    expect(runRepository.refreshCalls, 1);
  });

  test('home removes repository listeners on dispose', () async {
    final workspaceRepository =
        _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]);
    final conversationRepository = _FakeCachedConversationRepository();
    final runRepository = _FakeCachedRunRepository();
    final viewModel = HomeViewModel(
      workspaceRepository: workspaceRepository,
      conversationRepository: conversationRepository,
      runRepository: runRepository,
    );

    viewModel.dispose();
    workspaceRepository.notifyForTest();
    conversationRepository.notifyForTest();
    runRepository.notifyForTest();

    expect(workspaceRepository.listenerCount, 0);
    expect(conversationRepository.listenerCount, 0);
    expect(runRepository.listenerCount, 0);
  });
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({required List<WorkspaceSummary> workspaces})
      : _workspaces = List<WorkspaceSummary>.unmodifiable(workspaces),
        _selectedWorkspaceId = workspaces.isEmpty ? null : workspaces.first.id;

  final List<WorkspaceSummary> _workspaces;
  String? _selectedWorkspaceId;
  int refreshCalls = 0;
  int listenerCount = 0;

  @override
  List<WorkspaceSummary> get workspaces => _workspaces;

  @override
  WorkspaceSummary? get selectedWorkspace {
    final selectedId = _selectedWorkspaceId;
    if (selectedId == null) return null;
    for (final workspace in _workspaces) {
      if (workspace.id == selectedId) return workspace;
    }
    return null;
  }

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
  }

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) =>
      throw UnimplementedError();

  @override
  bool select(String workspaceId) {
    if (!_workspaces.any((workspace) => workspace.id == workspaceId)) {
      return false;
    }
    _selectedWorkspaceId = workspaceId;
    notifyListeners();
    return true;
  }

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    throw UnimplementedError();
  }

  void notifyForTest() => notifyListeners();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCachedConversationRepository extends CachedConversationRepository {
  _FakeCachedConversationRepository()
      : super(delegate: _UnusedConversationRepository());

  int refreshCalls = 0;
  int listenerCount = 0;

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
  }

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }

  void notifyForTest() => notifyListeners();
}

class _FakeCachedRunRepository extends CachedRunRepository {
  _FakeCachedRunRepository() : super(delegate: _UnusedRunRepository());

  int refreshCalls = 0;
  int listenerCount = 0;

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
  }

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }

  void notifyForTest() => notifyListeners();
}

class _UnusedConversationRepository implements ConversationRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedRunRepository implements RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
