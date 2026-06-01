import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_initial_data.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/view_models/workbench_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/workbench_route_state.dart';
import 'package:lan_ai_cli_control/src/workflows/connection/open_workspace_use_case.dart';

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
        () async {
      final viewModel = _workbenchViewModel(
        _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      );

      await viewModel.openWorkspaceSessions('missing');

      expect(viewModel.routeState, isA<WorkspaceListRouteState>());
    });

    test(
        'openWorkspaceSessions routes to sessions when repository select returns true',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      await viewModel.openWorkspaceSessions('w1');

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
      final adapterRepository = _FakeCliAdapterRepository();
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

    test('routeWorkspace resolves workspace id from repository', () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      await viewModel.openWorkspaceSessions('w1');

      expect(viewModel.routeWorkspace, isNotNull);
      expect(viewModel.routeWorkspace?.id, 'w1');
    });

    test(
        'route transitions keep workspace and conversation route ids consistent',
        () {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final viewModel = _workbenchViewModel(workspaceRepository);

      viewModel.showSessions('w1');
      expect(viewModel.routeWorkspace?.id, 'w1');
      expect(viewModel.activeConversationId, isNull);

      viewModel.showConversationRoute('w1', 'c1');
      expect(viewModel.routeWorkspace?.id, 'w1');
      expect(viewModel.routeState, isA<ConversationRouteState>());
      expect(
        (viewModel.routeState as ConversationRouteState).conversationId,
        'c1',
      );
      expect(viewModel.activeConversationId, isNull);

      viewModel.showWorkspaceList();
      expect(viewModel.routeWorkspace, isNull);
      expect(viewModel.activeConversationId, isNull);
    });

    test(
        'older event page prepends events without duplicating existing messages',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final conversationRepository = _FakeCachedConversationRepository(
        eventPages: <ConversationEventPage>[
          ConversationEventPage(
            events: <ConversationEvent>[
              _event(
                seq: 2,
                type: 'user.message',
                text: 'newer question',
              ),
              _event(
                seq: 3,
                type: 'assistant.message',
                text: 'newer answer',
              ),
            ],
            oldestSeq: 2,
            newestSeq: 3,
            hasMoreBefore: true,
          ),
          ConversationEventPage(
            events: <ConversationEvent>[
              _event(
                seq: 1,
                type: 'assistant.message',
                text: 'older answer',
              ),
              _event(
                seq: 2,
                type: 'user.message',
                text: 'newer question duplicate',
              ),
            ],
            oldestSeq: 1,
            newestSeq: 2,
            hasMoreBefore: false,
          ),
        ],
      );
      final viewModel = _workbenchViewModel(
        workspaceRepository,
        conversationRepository: conversationRepository,
      );

      await viewModel.loadInitialConversationEventPage(
        conversationId: 'c1',
        limit: 2,
        streamOutput: false,
      );
      final loaded = await viewModel.loadOlderConversationEventPage(
        conversationId: 'c1',
        limit: 2,
        streamOutput: false,
      );

      expect(loaded, isTrue);
      expect(viewModel.conversationEvents.map((event) => event.seq),
          const <int>[1, 2, 3]);
      expect(viewModel.messages.map((message) => message.body).toSet().length,
          viewModel.messages.length);
    });

    test('selectModel preserves selected model when repository rejects update',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final conversationRepository = _FakeCachedConversationRepository()
        ..updateModelError = const ConversationRepositoryException(
          message: 'model update unsupported',
          statusCode: 404,
        );
      final viewModel = _workbenchViewModel(
        workspaceRepository,
        adapterRepository: _FakeCliAdapterRepository(
          adapters: const <AdapterStatus>[_codexModels],
        ),
        conversationRepository: conversationRepository,
      );
      viewModel.updateActiveConversation(
        _conversation(id: 'c1', workspaceId: 'w1', model: 'gpt-5-codex'),
      );

      final changed = await viewModel.selectModel('gpt-5-mini');

      expect(changed, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.conversationModelUpdatesUnsupported, isTrue);
      expect(viewModel.activeConversationId, 'c1');
    });

    test('conversation question answer delegates without route mutation',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final conversationRepository = _FakeCachedConversationRepository();
      final viewModel = _workbenchViewModel(
        workspaceRepository,
        conversationRepository: conversationRepository,
      );
      viewModel.showConversationRoute('w1', 'c1');

      await viewModel.answerConversationQuestion(
        conversationId: 'c1',
        questionId: 'q1',
        text: 'yes',
      );

      expect(
        (viewModel.routeState as ConversationRouteState).conversationId,
        'c1',
      );
      expect(conversationRepository.answeredQuestionIds, const <String>['q1']);
    });

    test('conversation approval delegates without route mutation', () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        ],
      );
      final conversationRepository = _FakeCachedConversationRepository();
      final viewModel = _workbenchViewModel(
        workspaceRepository,
        conversationRepository: conversationRepository,
      );
      viewModel.showConversationRoute('w1', 'c1');

      await viewModel.respondConversationApproval(
        conversationId: 'c1',
        approvalId: 'ap1',
        decision: 'allow',
      );

      expect(
        (viewModel.routeState as ConversationRouteState).conversationId,
        'c1',
      );
      expect(
          conversationRepository.respondedApprovalIds, const <String>['ap1']);
    });

    test(
        'openWorkspaceSessions exposes loading until workspace bootstrap completes',
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
        openWorkspace: _FakeWorkspaceOpeningUseCase(completer.future),
      );

      final future = viewModel.openWorkspaceSessions('w2');

      expect(viewModel.openingWorkspaceId, 'w2');
      expect(viewModel.openingWorkspace, isTrue);

      completer.complete(_initialDataForWorkspace('w2'));
      await future;

      expect(viewModel.openingWorkspaceId, isNull);
      expect(viewModel.openingWorkspace, isFalse);
      expect(viewModel.routeState, isA<WorkspaceSessionsRouteState>());
    });

    test(
        'openWorkspaceSessions returns to list when bootstrap has no workspace',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
          WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        ],
      );
      final viewModel = _workbenchViewModel(
        workspaceRepository,
        openWorkspace: _FakeWorkspaceOpeningUseCase(
          Future<DaemonInitialData>.value(_initialDataWithoutWorkspace()),
        ),
      );

      await viewModel.openWorkspaceSessions('w2');

      expect(viewModel.openingWorkspace, isFalse);
      expect(viewModel.routeState, isA<WorkspaceListRouteState>());
    });

    test(
        'openWorkspaceSessions returns to list when bootstrap selects a different workspace',
        () async {
      final workspaceRepository = _FakeWorkspaceRepository(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
          WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
        ],
      );
      final viewModel = _workbenchViewModel(
        workspaceRepository,
        openWorkspace: _FakeWorkspaceOpeningUseCase(
          Future<DaemonInitialData>.value(_initialDataForWorkspace('w1')),
        ),
      );

      await viewModel.openWorkspaceSessions('w2');

      expect(viewModel.openingWorkspace, isFalse);
      expect(viewModel.routeState, isA<WorkspaceListRouteState>());
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

WorkbenchViewModel _workbenchViewModel(
  _FakeWorkspaceRepository workspaceRepository, {
  _FakeCliAdapterRepository? adapterRepository,
  _FakeCachedConversationRepository? conversationRepository,
  _FakeCachedRunRepository? runRepository,
  WorkspaceOpeningUseCase? openWorkspace,
}) {
  return WorkbenchViewModel(
    workspaceRepository: workspaceRepository,
    adapterRepository: adapterRepository ?? _FakeCliAdapterRepository(),
    conversationRepository:
        conversationRepository ?? _FakeCachedConversationRepository(),
    runRepository: runRepository ?? _FakeCachedRunRepository(),
    workspaceOpeningUseCase: openWorkspace,
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
// Fake CLI adapter repository
// ---------------------------------------------------------------------------

class _FakeCliAdapterRepository extends CliAdapterRepository {
  _FakeCliAdapterRepository({List<AdapterStatus> adapters = const []})
      : _adapters = adapters,
        super(delegate: _NoOpAdapterRepository());

  final List<AdapterStatus> _adapters;

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
  List<AdapterStatus> get adapters => List.unmodifiable(_adapters);
}

class _NoOpAdapterRepository implements AdapterRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCachedConversationRepository extends CachedConversationRepository {
  _FakeCachedConversationRepository({
    List<ConversationEventPage> eventPages = const <ConversationEventPage>[],
  })  : _eventPages = List<ConversationEventPage>.of(eventPages),
        super(delegate: _NoOpConversationRepository());

  final List<ConversationEventPage> _eventPages;
  final List<String> answeredQuestionIds = <String>[];
  final List<String> respondedApprovalIds = <String>[];
  ConversationRepositoryException? updateModelError;
  int _eventPageIndex = 0;

  @override
  List<ConversationSummary> get conversations => const <ConversationSummary>[];

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async {
    final error = updateModelError;
    if (error != null) throw error;
    return _conversation(id: conversationId, workspaceId: 'w1', model: model);
  }

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    if (_eventPageIndex < _eventPages.length) {
      return _eventPages[_eventPageIndex++];
    }
    return const ConversationEventPage(
      events: <ConversationEvent>[],
      oldestSeq: null,
      newestSeq: null,
      hasMoreBefore: false,
    );
  }

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async {
    answeredQuestionIds.add(questionId);
    return _conversation(id: conversationId, workspaceId: 'w1');
  }

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async {
    respondedApprovalIds.add(approvalId);
    return _conversation(id: conversationId, workspaceId: 'w1');
  }
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

class _FakeWorkspaceOpeningUseCase implements WorkspaceOpeningUseCase {
  _FakeWorkspaceOpeningUseCase(this.result);

  final Future<DaemonInitialData> result;

  @override
  Future<DaemonInitialData> open({
    required List<WorkspaceSummary> workspaces,
    required WorkspaceSummary workspace,
  }) =>
      result;
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

DaemonInitialData _initialDataForWorkspace(String workspaceId) {
  final workspace = WorkspaceSummary(
    id: workspaceId,
    name: workspaceId,
    path: r'D:\workspace',
  );
  return DaemonInitialData(
    health: _health,
    workspaces: <WorkspaceSummary>[workspace],
    workspace: workspace,
    adapters: const <AdapterStatus>[],
    conversations: const <ConversationSummary>[],
    runs: const <RunSummary>[],
    queue: const <QueueItem>[],
  );
}

DaemonInitialData _initialDataWithoutWorkspace() {
  return const DaemonInitialData(
    health: _health,
    workspaces: <WorkspaceSummary>[],
    workspace: null,
    adapters: <AdapterStatus>[],
    conversations: <ConversationSummary>[],
    runs: <RunSummary>[],
    queue: <QueueItem>[],
  );
}

ConversationSummary _conversation({
  required String id,
  required String workspaceId,
  String adapter = 'codex',
  String status = 'idle',
  String? model,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: adapter,
      status: status,
      model: model,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-06-01T00:00:00.000Z',
      updatedAt: '2026-06-01T00:00:01.000Z',
    );

ConversationEvent _event({
  required int seq,
  required String type,
  String conversationId = 'c1',
  String? text,
}) =>
    ConversationEvent(
      type: type,
      seq: seq,
      conversationId: conversationId,
      createdAt: DateTime.parse('2026-06-01T00:00:0$seq.000Z'),
      text: text,
    );

const _codexModels = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  canSelectModel: true,
  selectedModel: 'gpt-5-codex',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-codex',
      label: 'GPT-5 Codex',
      source: 'codex_config',
      selected: true,
    ),
    AdapterModelOption(
      id: 'gpt-5-mini',
      label: 'GPT-5 Mini',
      source: 'codex_catalog',
      selected: false,
    ),
  ],
);
