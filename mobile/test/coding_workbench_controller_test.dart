import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/l10n/app_localizations_zh.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/sessions/session_item.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/attachment_preview_cache.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/draft_attachment.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/coding_workbench_controller.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/view_models/workbench_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/workbench_messages.dart';
import 'package:lan_ai_cli_control/src/workflows/workspace/create_workspace_workflow.dart';

void main() {
  test('workbench route state stores ids and resolves workspace via repository',
      () async {
    const other = WorkspaceSummary(
      id: 'workspace_2',
      name: 'Other Workspace',
      path: r'D:\other',
    );
    final viewModel = _workbenchViewModel(
      workspaces: const <WorkspaceSummary>[_workspace, other],
    );

    expect(viewModel.routeWorkspace, isNull);

    await viewModel.openWorkspaceSessions(other.id);
    expect(viewModel.selectedWorkspace, other);
    expect(viewModel.routeWorkspace, other);
    expect(
      viewModel.routeState,
      isA<WorkspaceSessionsRouteState>()
          .having((state) => state.workspaceId, 'workspaceId', other.id),
    );

    viewModel.showConversationRoute(_workspace.id, 'conv_1');
    expect(viewModel.routeWorkspace, _workspace);
    expect(
      viewModel.routeState,
      isA<ConversationRouteState>()
          .having((state) => state.workspaceId, 'workspaceId', _workspace.id)
          .having((state) => state.conversationId, 'conversationId', 'conv_1'),
    );

    viewModel.showWorkspaceList();
    expect(viewModel.routeWorkspace, isNull);
  });

  test('active conversation owns adapter selection across cache refreshes', () {
    final adapterRepository = _FakeCliAdapterRepository(
      adapters: const <AdapterStatus>[_codexAdapter, _claudeAdapter],
    );
    final viewModel = _workbenchViewModel(
      adapterRepository: adapterRepository,
    );
    final conversation = _conversation(
      id: 'conv_codex',
      workspaceId: _workspace.id,
      status: 'idle',
      adapter: 'codex',
    );

    expect(viewModel.selectedAdapter, 'claude');

    viewModel.openSession(SessionItem(
      run: WorkbenchViewModel.runSummaryFromConversation(conversation),
      conversation: conversation,
    ));
    expect(viewModel.selectedAdapter, 'codex');

    adapterRepository.replaceAdapters(const <AdapterStatus>[_claudeAdapter]);

    expect(viewModel.selectedAdapter, 'codex');
    viewModel.setSelectedAdapter('claude');
    expect(viewModel.selectedAdapter, 'codex');
  });

  test('new conversation send uses cached repository state for session items',
      () async {
    final repository = _FakeConversationRepository();
    final viewModel = _workbenchViewModel(conversationRepository: repository);

    final result = await viewModel.createAndSend(
      workspace: _workspace,
      prompt: 'hello',
      adapter: 'codex',
      permissionMode: 'default',
    );

    expect(viewModel.sessionItems, hasLength(1));
    expect(viewModel.sessionItems.single.id, 'conv_1');
    expect(viewModel.sessionItems.single.conversation?.status, 'sending');

    final updated = await result.updatedConversation;

    expect(repository.calls, <String>[
      'create:workspace_1:codex:default:null',
      'send:conv_1:hello',
    ]);
    expect(updated.status, 'running');
    expect(viewModel.sessionItems, hasLength(1));
    expect(viewModel.sessionItems.single.conversation?.status, 'running');
  });

  test('workbench view model forwards conversation stream operations',
      () async {
    final repository = _FakeConversationRepository();
    final viewModel = _workbenchViewModel(conversationRepository: repository);

    final events = await viewModel.fetchConversationEvents(
      conversationId: 'conv_existing',
      afterSeq: 7,
    );

    expect(repository.calls, <String>['events:conv_existing:7']);
    expect(events.single.seq, 8);

    repository.calls.clear();
    final emitted = <ConversationEvent>[];
    final subscription = viewModel
        .watchConversationEvents(conversationId: 'conv_existing', afterSeq: 7)
        .listen(emitted.add);

    repository.emitConversationEvent(ConversationEvent(
      seq: 9,
      conversationId: 'conv_existing',
      type: 'assistant.message',
      createdAt: DateTime.parse('2026-05-23T05:18:14.000Z'),
      text: 'streamed',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(repository.calls, <String>['watchEvents:conv_existing:7']);
    expect(emitted.single.seq, 9);
    await subscription.cancel();
  });

  test('workbench view model applies tail page and tracks historical cursor',
      () async {
    final repository = _FakeConversationRepository(
      eventPage: ConversationEventPage(
        events: <ConversationEvent>[
          _event(
              seq: 7,
              conversationId: 'conv_existing',
              type: 'user.message',
              text: 'tail prompt'),
          _event(
              seq: 8,
              conversationId: 'conv_existing',
              type: 'assistant.message',
              text: 'tail answer'),
        ],
        oldestSeq: 7,
        newestSeq: 8,
        hasMoreBefore: true,
      ),
    );
    final viewModel = _workbenchViewModel(conversationRepository: repository);
    final conversation = _conversation(
      id: 'conv_existing',
      workspaceId: _workspace.id,
      status: 'idle',
    );
    viewModel.openSession(SessionItem(
      run: WorkbenchViewModel.runSummaryFromConversation(conversation),
      conversation: conversation,
    ));

    final changed = await viewModel.loadInitialConversationEventPage(
      conversationId: 'conv_existing',
      limit: 80,
      streamOutput: false,
    );

    expect(changed, isTrue);
    expect(repository.calls, <String>['page:conv_existing:null:80']);
    expect(viewModel.oldestLoadedConversationSeq, 7);
    expect(viewModel.hasMoreHistoricalConversationEvents, isTrue);
    expect(viewModel.loadingOlderConversationEvents, isFalse);
    expect(viewModel.lastSeq, 8);
    expect(viewModel.messages.map((message) => message.body),
        containsAll(<String>['tail prompt', 'tail answer']));
  });

  test('workbench view model dedupes stream overlap with older page', () async {
    final repository = _FakeConversationRepository(
      eventPages: <ConversationEventPage>[
        ConversationEventPage(
          events: <ConversationEvent>[
            _event(
                seq: 2,
                conversationId: 'conv_existing',
                type: 'assistant.message',
                text: 'streamed answer'),
          ],
          oldestSeq: 2,
          newestSeq: 2,
          hasMoreBefore: true,
        ),
        ConversationEventPage(
          events: <ConversationEvent>[
            _event(
                seq: 1,
                conversationId: 'conv_existing',
                type: 'user.message',
                text: 'older prompt'),
            _event(
                seq: 2,
                conversationId: 'conv_existing',
                type: 'assistant.message',
                text: 'streamed answer'),
          ],
          oldestSeq: 1,
          newestSeq: 2,
          hasMoreBefore: false,
        ),
      ],
    );
    final viewModel = _workbenchViewModel(conversationRepository: repository);
    final conversation = _conversation(
      id: 'conv_existing',
      workspaceId: _workspace.id,
      status: 'running',
    );
    viewModel.openSession(SessionItem(
      run: WorkbenchViewModel.runSummaryFromConversation(conversation),
      conversation: conversation,
    ));

    await viewModel.loadInitialConversationEventPage(
      conversationId: 'conv_existing',
      limit: 80,
      streamOutput: true,
    );
    viewModel.applyConversationEvents(<ConversationEvent>[
      _event(
          seq: 3,
          conversationId: 'conv_existing',
          type: 'assistant.message',
          text: 'live answer'),
    ], streamOutput: true);
    final changed = await viewModel.loadOlderConversationEventPage(
      conversationId: 'conv_existing',
      limit: 80,
      streamOutput: true,
    );

    expect(changed, isTrue);
    expect(repository.calls, <String>[
      'page:conv_existing:null:80',
      'page:conv_existing:2:80',
    ]);
    expect(viewModel.hasMoreHistoricalConversationEvents, isFalse);
    expect(
        viewModel.conversationEvents.map((event) => event.seq), <int>[1, 2, 3]);
    expect(
        viewModel.messages
            .where((message) => message.body == 'streamed answer'),
        hasLength(1));
  });

  test('workbench view model cancels conversation and run through repositories',
      () async {
    final conversationRepository = _FakeConversationRepository();
    final runRepository = _FakeRunRepository();
    final viewModel = _workbenchViewModel(
      conversationRepository: conversationRepository,
      runRepository: runRepository,
    );

    final conversationResult =
        await viewModel.cancelActiveRun(conversationId: 'conv_1');
    final runResult = await viewModel.cancelActiveRun(runId: 'run_1');

    expect(
      conversationRepository.calls,
      <String>['cancelConversation:conv_1'],
    );
    expect(conversationResult.conversation?.status, 'cancelled');
    expect(conversationResult.run?.status, 'cancelled');
    expect(runRepository.calls, <String>['cancelRun:run_1']);
    expect(runResult.conversation, isNull);
    expect(runResult.run?.status, 'cancelled');
  });

  test('workbench view model records event trace metadata', () async {
    final repository = _FakeDiagnosticsRepository();
    final viewModel = _workbenchViewModel(diagnosticsRepository: repository);

    await viewModel.recordEventTrace(WorkbenchEventTraceEntry(
      conversationId: 'conv_1',
      runId: 'run_1',
      path: '/api/notifications/ws',
      afterSeq: 7,
      returnedCount: 3,
      durationMs: 42,
      cancelled: false,
      changed: true,
      terminalDrainPending: false,
    ));

    expect(viewModel.eventTraceEntries, hasLength(1));
    expect(repository.calls, <String>[
      'watchConversationEvents: success|null|/api/notifications/ws|GET|conv_1|run_1|info|watchConversationEvents|7|3|42|false|true|false|null',
    ]);
  });

  test('workbench view model creates workspace through workflow', () async {
    const created = WorkspaceSummary(
      id: 'workspace_new',
      name: 'New Workspace',
      path: r'D:\new',
    );
    final repository = _FakeWorkspaceRepository(
      workspaces: const <WorkspaceSummary>[_workspace],
      createdWorkspace: created,
    );
    final viewModel = _workbenchViewModel(
      workspaceRepository: repository,
      workspaceCreationTimeout: const Duration(seconds: 1),
    );

    final outcome = await viewModel.createWorkspace(
      path: created.path,
      name: created.name,
    );

    expect(repository.calls, <String>[
      r'create:D:\new:New Workspace',
      'list',
    ]);
    expect(outcome, isA<CreateWorkspaceSuccess>());
    expect((outcome as CreateWorkspaceSuccess).workspace, created);
  });

  test('conversation event projection preserves optimistic user messages', () {
    final viewModel = _workbenchViewModel();
    viewModel.updateActiveConversation(_conversation(
      id: 'conv_1',
      workspaceId: _workspace.id,
      status: 'sending',
    ));
    viewModel.addUserMessage('inspect image');

    final changed = viewModel.applyConversationEvents(
      <ConversationEvent>[_event(seq: 1, type: 'conversation.started')],
      streamOutput: false,
    );

    expect(changed, isTrue);
    expect(viewModel.messages.single.role, 'user');
    expect(viewModel.messages.single.body, 'inspect image');
  });

  test('committed attachment event binds cache identity', () async {
    const imageCapableAdapter = AdapterStatus(
      adapter: 'codex',
      available: true,
      status: 'available',
      capabilityVersion: 'cap_v1',
      attachmentCapabilities:
          AttachmentCapabilities(image: AttachmentHandling.native),
    );
    final repository = _FakeConversationRepository();
    final cache = _FakeAttachmentPreviewCache();
    final viewModel = _workbenchViewModel(
      adapters: const <AdapterStatus>[imageCapableAdapter],
      conversationRepository: repository,
      attachmentPreviewCache: cache,
    );
    viewModel.updateActiveConversation(_conversation(
      id: 'conv_1',
      workspaceId: _workspace.id,
      status: 'sending',
    ));
    viewModel.addDraftAttachmentForTest(const DraftAttachment(
      localPath: r'C:\tmp\screenshot.png',
      name: 'screenshot.png',
      mimeType: 'image/png',
      kind: AttachmentKind.image,
      sizeBytes: 42,
    ));
    viewModel.addUserMessage('inspect image', includeDraftAttachments: true);
    await viewModel.sendExistingConversationPrompt(
      conversationId: 'conv_1',
      prompt: 'inspect image',
    );
    final clientMessageId = repository.sentRequests.single.clientMessageId;

    await viewModel.applyConversationEventsAsync(
      <ConversationEvent>[
        ConversationEvent(
          seq: 1,
          conversationId: 'conv_1',
          type: 'user.message',
          createdAt: DateTime.parse('2026-05-12T00:00:01.000Z'),
          text: 'inspect image',
          raw: <String, Object?>{'clientMessageId': clientMessageId},
          attachments: const <CommittedAttachment>[
            CommittedAttachment(
              id: 'att_0',
              name: 'screenshot.png',
              kind: AttachmentKind.image,
              mimeType: 'image/png',
              sizeBytes: 42,
              handling: AttachmentHandling.native,
            ),
          ],
        ),
      ],
      streamOutput: false,
    );

    expect(cache.bound, <String>[
      'conv_1|$clientMessageId|att_0|hash_0',
    ]);
    expect(
      viewModel.messages.single.attachments.single.localPath,
      r'C:\cache\screenshot.png',
    );
  });

  test('workbench helper functions preserve running and pending semantics', () {
    final l10n = AppLocalizationsZh();
    final events = <ConversationEvent>[
      _event(
        seq: 1,
        type: 'tool.started',
        toolUseId: 'cmd_1',
        toolName: 'command_execution',
        input: const <String, Object?>{
          'command': 'flutter test test\\voice_input_controller_test.dart',
        },
      ),
    ];

    expect(canSendInConversationStatus('idle'), isTrue);
    expect(canSendInConversationStatus('waiting_input'), isTrue);
    expect(canSendInConversationStatus('waiting_approval'), isFalse);
    expect(isActiveConversationStatus('waiting_input'), isTrue);
    expect(isActiveConversationStatus('cancelled'), isFalse);
    expect(
      conversationPendingStatusText(l10n, 'running', events),
      contains('flutter test test\\voice_input_controller_test.dart'),
    );
    expect(
      conversationPendingStatusText(l10n, 'running', <ConversationEvent>[
        _event(
          seq: 2,
          type: 'tool.started',
          toolUseId: 'web_1',
          toolName: 'WebSearch',
        ),
      ]),
      '正在搜索网页...',
    );
    expect(
      isSendAcknowledgementTimeout(
        TimeoutException('Future not completed'),
        activeConversationId: 'conv_1',
        activeRunId: null,
      ),
      isTrue,
    );
  });
}

const _workspace = WorkspaceSummary(
  id: 'workspace_1',
  name: 'Workspace',
  path: r'D:\workspace',
);

WorkbenchViewModel _workbenchViewModel({
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[_workspace],
  _FakeWorkspaceRepository? workspaceRepository,
  _FakeCliAdapterRepository? adapterRepository,
  _FakeConversationRepository? conversationRepository,
  _FakeRunRepository? runRepository,
  DiagnosticsRepository? diagnosticsRepository,
  AttachmentPreviewCache attachmentPreviewCache =
      const NoopAttachmentPreviewCache(),
  Duration workspaceCreationTimeout = const Duration(seconds: 20),
}) {
  return WorkbenchViewModel(
    workspaceRepository:
        workspaceRepository ?? _FakeWorkspaceRepository(workspaces: workspaces),
    adapterRepository:
        adapterRepository ?? _FakeCliAdapterRepository(adapters: adapters),
    conversationRepository: CachedConversationRepository(
      delegate: conversationRepository ?? _FakeConversationRepository(),
    ),
    runRepository: CachedRunRepository(
      delegate: runRepository ?? _FakeRunRepository(),
    ),
    diagnosticsRepository: diagnosticsRepository,
    attachmentPreviewCache: attachmentPreviewCache,
    workspaceCreationTimeout: workspaceCreationTimeout,
  );
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({
    required List<WorkspaceSummary> workspaces,
    WorkspaceSummary? createdWorkspace,
  })  : _workspaces = List<WorkspaceSummary>.of(workspaces),
        _createdWorkspace = createdWorkspace;

  List<WorkspaceSummary> _workspaces;
  final WorkspaceSummary? _createdWorkspace;
  WorkspaceSummary? _selectedWorkspace;
  final List<String> calls = <String>[];

  @override
  List<WorkspaceSummary> get workspaces => List.unmodifiable(_workspaces);

  @override
  WorkspaceSummary? get selectedWorkspace =>
      _selectedWorkspace ?? (_workspaces.isEmpty ? null : _workspaces.first);

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
    calls.add('create:$path:$name');
    final workspace = _createdWorkspace ??
        WorkspaceSummary(
          id: 'workspace_created',
          name: name ?? path,
          path: path,
        );
    _workspaces = <WorkspaceSummary>[..._workspaces, workspace];
    _selectedWorkspace = workspace;
    notifyListeners();
    return workspace;
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
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    calls.add('list');
    return List<WorkspaceSummary>.of(_workspaces);
  }

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) =>
      create(path: path, name: name);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCliAdapterRepository extends CliAdapterRepository {
  _FakeCliAdapterRepository({
    List<AdapterStatus> adapters = const <AdapterStatus>[],
  })  : _adapters = List<AdapterStatus>.of(adapters),
        super(delegate: _NoOpAdapterRepository());

  List<AdapterStatus> _adapters;

  @override
  List<AdapterStatus> get adapters => List.unmodifiable(_adapters);

  void replaceAdapters(List<AdapterStatus> adapters) {
    _adapters = List<AdapterStatus>.of(adapters);
    notifyListeners();
  }
}

class _NoOpAdapterRepository implements AdapterRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository({
    ConversationEventPage? eventPage,
    List<ConversationEventPage>? eventPages,
  }) : eventPages = eventPages ??
            <ConversationEventPage>[
              if (eventPage != null) eventPage,
            ];

  final List<ConversationEventPage> eventPages;
  final List<String> calls = <String>[];
  final List<ConversationMessageSendRequest> sentRequests =
      <ConversationMessageSendRequest>[];
  final StreamController<ConversationEvent> _events =
      StreamController<ConversationEvent>.broadcast();
  int _eventPageIndex = 0;

  void emitConversationEvent(ConversationEvent event) => _events.add(event);

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    calls.add('create:$workspaceId:$adapter:$permissionMode:$model');
    return _conversation(
      id: 'conv_1',
      workspaceId: workspaceId,
      status: 'idle',
      adapter: adapter,
      model: model,
    );
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async {
    calls.add('send:$conversationId:${request.text}');
    sentRequests.add(request);
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'running',
      userMessageCount: 1,
    );
  }

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async {
    calls.add('events:$conversationId:$afterSeq');
    return <ConversationEvent>[
      ConversationEvent(
        seq: afterSeq + 1,
        conversationId: conversationId,
        type: 'assistant.message',
        createdAt: DateTime.parse('2026-05-12T00:00:02.000Z'),
        text: 'hello',
      ),
    ];
  }

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    calls.add('page:$conversationId:$beforeSeq:$limit');
    if (_eventPageIndex < eventPages.length) {
      return eventPages[_eventPageIndex++];
    }
    return const ConversationEventPage(
      events: <ConversationEvent>[],
      oldestSeq: null,
      newestSeq: null,
      hasMoreBefore: false,
    );
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    calls.add('watchEvents:$conversationId:$afterSeq');
    return _events.stream;
  }

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async {
    calls.add('cancelConversation:$conversationId');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'cancelled',
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      _conversation(id: conversationId, workspaceId: _workspace.id);

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async =>
      _conversation(
        id: conversationId,
        workspaceId: _workspace.id,
        status: 'running',
      );

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      _conversation(
        id: conversationId,
        workspaceId: _workspace.id,
        model: model,
      );

  @override
  Future<ConversationSummary> updateConversationPermissionMode(
    String conversationId,
    String permissionMode,
  ) async =>
      _conversation(
        id: conversationId,
        workspaceId: _workspace.id,
      );
}

class _FakeRunRepository implements RunRepository {
  final List<String> calls = <String>[];

  @override
  Future<RunSummary> cancelRun(String runId) async {
    calls.add('cancelRun:$runId');
    return RunSummary(
      id: runId,
      tool: 'codex',
      workspaceId: _workspace.id,
      status: 'cancelled',
    );
  }

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) async =>
      const <RunSummary>[];

  @override
  Future<List<QueueItem>> listQueue() async => const <QueueItem>[];

  @override
  Future<void> respondApproval(String approvalId, String decision) async {
    calls.add('approval:$approvalId:$decision');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDiagnosticsRepository implements DiagnosticsRepository {
  final List<String> calls = <String>[];

  @override
  Future<DiagnosticBundleSummary> exportDiagnostics() async =>
      DiagnosticBundleSummary(
        bundleId: 'diag_1',
        createdAt: DateTime.utc(2026, 5, 14),
        path: r'C:\temp\diag_1.zip',
        redacted: true,
        items: const <String>['system', 'logs'],
      );

  @override
  Future<String> recordException({
    required String message,
    String severity = 'error',
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    calls.add([
      message,
      stack,
      path,
      method,
      conversationId,
      runId,
      severity,
      metadata['operation'],
      metadata['afterSeq'],
      metadata['returnedCount'],
      metadata['durationMs'],
      metadata['cancelled'],
      metadata['changed'],
      metadata['terminalDrainPending'],
      metadata['error'],
    ].join('|'));
    return 'trace_1';
  }
}

class _FakeAttachmentPreviewCache implements AttachmentPreviewCache {
  final List<String> bound = <String>[];
  final Map<String, CachedAttachmentPreview> _resolved =
      <String, CachedAttachmentPreview>{};

  @override
  Future<AttachmentPreviewIdentity> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required int attachmentIndex,
    required DraftAttachment draft,
  }) async {
    return AttachmentPreviewIdentity(
      contentHash: 'hash_$attachmentIndex',
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
      attachmentIndex: attachmentIndex,
    );
  }

  @override
  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
    List<AttachmentPreviewIdentity>? pendingIdentities,
  }) async {
    final identity = pendingIdentities?.single;
    final attachment = attachments.single;
    bound.add(
      '$conversationId|$clientMessageId|${attachment.id}|'
      '${identity?.contentHash}',
    );
    _resolved['$conversationId|${attachment.id}'] = CachedAttachmentPreview(
      attachmentId: attachment.id,
      contentHash: identity?.contentHash ?? 'missing',
      cachePath: r'C:\cache\screenshot.png',
      width: 320,
      height: 200,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      createdAt: DateTime.utc(2026, 5, 22),
      lastAccessedAt: DateTime.utc(2026, 5, 22),
    );
  }

  @override
  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  }) async =>
      _resolved['$conversationId|${attachment.id}'];

  @override
  Future<void> markClientMessageOrphaned({
    required String conversationId,
    required String clientMessageId,
  }) async {}
}

ConversationSummary _conversation({
  required String id,
  required String workspaceId,
  String status = 'idle',
  String adapter = 'codex',
  String? model,
  int userMessageCount = 0,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: adapter,
      model: model,
      status: status,
      userMessageCount: userMessageCount,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-12T00:00:00.000Z',
      updatedAt: '2026-05-12T00:00:01.000Z',
    );

const _claudeAdapter = AdapterStatus(
  adapter: 'claude',
  available: true,
  status: 'available',
);

const _codexAdapter = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
);

ConversationEvent _event({
  required int seq,
  required String type,
  String conversationId = 'conv_1',
  String? text,
  String? questionId,
  String? approvalId,
  String? toolUseId,
  String? toolName,
  String? summary,
  Map<String, Object?> input = const <String, Object?>{},
  Map<String, Object?> raw = const <String, Object?>{},
}) =>
    ConversationEvent(
      seq: seq,
      conversationId: conversationId,
      type: type,
      createdAt: DateTime.parse('2026-05-12T00:00:0$seq.000Z'),
      text: text,
      questionId: questionId,
      approvalId: approvalId,
      toolUseId: toolUseId,
      toolName: toolName,
      summary: summary,
      input: input,
      raw: raw,
    );
