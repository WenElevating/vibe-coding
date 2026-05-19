import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/view_models/workbench_view_model.dart';

void main() {
  group('AdapterStatus model parsing', () {
    test('uses safe defaults for old daemon payloads', () {
      final status = AdapterStatus.fromJson(<String, Object?>{
        'adapter': 'codex',
        'available': true,
        'status': 'available',
      });

      expect(status.models, isEmpty);
      expect(status.selectedModel, isNull);
      expect(status.canSelectModel, isFalse);
    });

    test('parses selected model rows from new daemon payloads', () {
      final status = AdapterStatus.fromJson(<String, Object?>{
        'adapter': 'codex',
        'available': true,
        'status': 'available',
        'models': <Object?>[
          <String, Object?>{
            'id': 'gpt-5-codex',
            'label': 'GPT-5 Codex',
            'source': 'codex_config',
            'selected': true,
          },
        ],
        'selectedModel': 'gpt-5-codex',
        'canSelectModel': true,
      });

      expect(status.canSelectModel, isTrue);
      expect(status.selectedModel, 'gpt-5-codex');
      expect(status.models, hasLength(1));
      expect(
        status.models.single,
        isA<AdapterModelOption>()
            .having((model) => model.id, 'id', 'gpt-5-codex')
            .having((model) => model.label, 'label', 'GPT-5 Codex')
            .having((model) => model.source, 'source', 'codex_config')
            .having((model) => model.selected, 'selected', isTrue),
      );
    });
  });

  group('WorkbenchViewModel model state', () {
    test('initial selected model comes from the selected adapter', () {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );

      expect(viewModel.selectedAdapter, 'codex');
      expect(viewModel.selectedAdapterStatus, _codexModels);
      expect(viewModel.availableModels, _codexModels.models);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.draftModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, isNull);
      expect(viewModel.modelNotice, isNull);
    });

    test('selectModel updates draft model state', () async {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isTrue);
      expect(viewModel.selectedModel, 'gpt-5-mini');
      expect(viewModel.draftModel, 'gpt-5-mini');
      expect(viewModel.modelNotice, isNull);
    });

    test('selectModel ignores unsupported model ids', () async {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );

      final selected = await viewModel.selectModel('not-configured');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
    });

    test('snapshot refresh selects a model when one becomes available', () {
      final viewModel = WorkbenchViewModel(initialData: _snapshot());

      viewModel.updateFromSnapshot(
        _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );

      expect(viewModel.selectedAdapter, 'codex');
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.modelNotice, isNull);
    });

    test('snapshot refresh falls back when the selected model disappears', () {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );

      viewModel.updateFromSnapshot(
        _snapshot(adapters: const <AdapterStatus>[_codexMiniOnly]),
      );

      expect(viewModel.selectedModel, 'gpt-5-mini');
      expect(
        viewModel.modelNotice,
        WorkbenchModelNotice.changedToAvailableOption,
      );

      viewModel.clearModelNotice();
      expect(viewModel.modelNotice, isNull);
    });

    test('existing conversation model update waits for repository success',
        () async {
      final repository = _FakeConversationRepository();
      final updateCompleter = Completer<ConversationSummary>();
      repository.updateCompleter = updateCompleter;
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final pendingSelection = viewModel.selectModel('gpt-5-mini');

      expect(viewModel.modelUpdating, isTrue);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
      expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);

      updateCompleter.complete(_conversation(model: 'gpt-5-mini'));
      final selected = await pendingSelection;

      expect(selected, isTrue);
      expect(viewModel.selectedModel, 'gpt-5-mini');
      expect(viewModel.confirmedConversationModel, 'gpt-5-mini');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, isNull);
    });

    test('existing conversation model update failure keeps confirmed model',
        () async {
      final repository = _FakeConversationRepository()
        ..updateError = const ConversationRepositoryException(
          statusCode: 500,
          code: 'SERVER_ERROR',
          message: 'update failed',
        );
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, 'update failed');
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
    });

    test('old daemon model endpoint disables existing conversation updates',
        () async {
      final repository = _FakeConversationRepository()
        ..updateError = const ConversationRepositoryException(statusCode: 405);
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.conversationModelUpdatesUnsupported, isTrue);
      expect(
        viewModel.modelUpdateError,
        'existing conversation model updates require a newer daemon',
      );

      final secondSelection = await viewModel.selectModel('gpt-5-mini');

      expect(secondSelection, isFalse);
      expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);
    });

    test('missing conversation response does not disable model updates',
        () async {
      final repository = _FakeConversationRepository()
        ..updateError = const ConversationRepositoryException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'conversation not found',
        );
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
      expect(viewModel.modelUpdateError, 'conversation not found');
    });

    test('status transitions preserve confirmed conversation model', () {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      viewModel.markConversationRunning(notify: false);

      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');

      viewModel.applyConversationEvents(
        <ConversationEvent>[
          _event(
            seq: 1,
            type: 'conversation.status_changed',
            raw: const <String, Object?>{'status': 'waiting_input'},
          ),
        ],
        streamOutput: false,
        notify: false,
      );

      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
    });

    test('stale model update success does not overwrite active conversation',
        () async {
      final repository = _FakeConversationRepository();
      final updateCompleter = Completer<ConversationSummary>();
      repository.updateCompleter = updateCompleter;
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_1', adapter: 'codex', model: 'gpt-5-codex'),
      );

      final pendingSelection = viewModel.selectModel('gpt-5-mini');
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_2', adapter: 'codex', model: 'gpt-5-codex'),
      );
      updateCompleter.complete(
        _conversation(id: 'conv_1', adapter: 'codex', model: 'gpt-5-mini'),
      );

      final selected = await pendingSelection;

      expect(selected, isFalse);
      expect(viewModel.activeConversationId, 'conv_2');
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, isNull);
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
    });

    test(
        'stale model update failure does not mark new conversation unsupported',
        () async {
      final repository = _FakeConversationRepository();
      final updateCompleter = Completer<ConversationSummary>();
      repository.updateCompleter = updateCompleter;
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_1', adapter: 'codex', model: 'gpt-5-codex'),
      );

      final pendingSelection = viewModel.selectModel('gpt-5-mini');
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_2', adapter: 'codex', model: 'gpt-5-codex'),
      );
      updateCompleter.completeError(
        const ConversationRepositoryException(statusCode: 405),
      );

      final selected = await pendingSelection;

      expect(selected, isFalse);
      expect(viewModel.activeConversationId, 'conv_2');
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, isNull);
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
    });

    test('sending operation state refuses adapter and model changes', () async {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(
          adapters: const <AdapterStatus>[_codexModels, _claudeAvailable],
        ),
      );

      viewModel.setSelectedAdapter('codex');
      viewModel.beginOperation();
      viewModel.setSelectedAdapter('claude');
      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedAdapter, 'codex');
      expect(viewModel.selectedModel, 'gpt-5-codex');
    });

    test('createAndSend forwards the ViewModel selected model', () async {
      final repository = _FakeConversationRepository();
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(
          adapters: const <AdapterStatus>[_codexModels],
          workspaces: const <WorkspaceSummary>[_workspace],
        ),
        conversationRepository: repository,
      );

      final result = await viewModel.createAndSend(
        workspace: _workspace,
        prompt: 'hello',
        adapter: 'codex',
        permissionMode: 'default',
      );
      await result.updatedConversation;

      expect(repository.calls, <String>[
        'create:workspace_1:codex:default:gpt-5-codex',
        'send:conv_1:hello',
      ]);
      expect(viewModel.modelNotice, isNull);
    });

    test('repository updateConversationModel records selected model', () async {
      final repository = _FakeConversationRepository();

      final updated =
          await repository.updateConversationModel('conv_1', 'gpt-5-mini');

      expect(updated.model, 'gpt-5-mini');
      expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);
    });

    test('createAndSend omits model when adapter cannot select models',
        () async {
      final repository = _FakeConversationRepository();
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(
          adapters: const <AdapterStatus>[_codexWithoutModelSelection],
          workspaces: const <WorkspaceSummary>[_workspace],
        ),
        conversationRepository: repository,
      );

      final result = await viewModel.createAndSend(
        workspace: _workspace,
        prompt: 'hello',
        adapter: 'codex',
        permissionMode: 'default',
        model: 'gpt-5-codex',
      );
      await result.updatedConversation;

      expect(repository.calls, <String>[
        'create:workspace_1:codex:default:null',
        'send:conv_1:hello',
      ]);
    });
  });
}

const _workspace = WorkspaceSummary(
  id: 'workspace_1',
  name: 'Workspace',
  path: r'D:\workspace',
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

const _codexMiniOnly = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  canSelectModel: true,
  selectedModel: 'gpt-5-mini',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-mini',
      label: 'GPT-5 Mini',
      source: 'codex_catalog',
      selected: true,
    ),
  ],
);

const _codexWithoutModelSelection = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  canSelectModel: false,
  selectedModel: 'gpt-5-codex',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-codex',
      label: 'GPT-5 Codex',
      source: 'codex_config',
      selected: true,
    ),
  ],
);

const _claudeAvailable = AdapterStatus(
  adapter: 'claude',
  available: true,
  status: 'available',
);

AppSnapshot _snapshot({
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[_workspace],
  List<ConversationSummary> conversations = const <ConversationSummary>[],
}) =>
    AppSnapshot(
      health: const DaemonHealth(
        status: 'ok',
        daemonVersion: 'test',
        mode: 'test',
        lanMode: true,
        bindAddress: '127.0.0.1',
        port: 0,
        security: <String, Object?>{},
      ),
      workspaces: workspaces,
      workspace: workspaces.first,
      overview: ProjectOverview(
        workspaceId: workspaces.first.id,
        name: workspaces.first.name,
        path: workspaces.first.path,
        fileCount: 0,
        codeLineCount: 0,
        symbolCount: 0,
        analysisScore: 0,
        recentFiles: const <RecentFileSummary>[],
      ),
      adapters: adapters,
      runs: const <RunSummary>[],
      conversations: conversations,
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: null,
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: FileTreeResponse(
        workspaceId: workspaces.first.id,
        root: workspaces.first.path,
        entries: const <FileTreeEntry>[],
      ),
      diagnostics: CodeDiagnosticsSummary(
        workspaceId: workspaces.first.id,
        available: false,
        diagnostics: const <CodeDiagnostic>[],
      ),
      extensions: const <ExtensionSummary>[],
    );

ConversationSummary _conversation({
  String id = 'conv_1',
  String adapter = 'codex',
  String? model,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: _workspace.id,
      adapter: adapter,
      model: model,
      status: 'idle',
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-18T00:00:00.000Z',
      updatedAt: '2026-05-18T00:00:01.000Z',
    );

ConversationEvent _event({
  required int seq,
  required String type,
  Map<String, Object?> raw = const <String, Object?>{},
}) =>
    ConversationEvent(
      seq: seq,
      conversationId: 'conv_1',
      type: type,
      createdAt: DateTime.parse('2026-05-18T00:00:02.000Z'),
      raw: raw,
    );

class _FakeConversationRepository implements ConversationRepository {
  final List<String> calls = <String>[];
  Completer<ConversationSummary>? updateCompleter;
  ConversationRepositoryException? updateError;

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    calls.add('create:$workspaceId:$adapter:$permissionMode:$model');
    return _conversation(adapter: adapter, model: model);
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    String text,
  ) async {
    calls.add('send:$conversationId:$text');
    return _conversation();
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async {
    calls.add('update-model:$conversationId:$model');
    final error = updateError;
    if (error != null) throw error;
    final completer = updateCompleter;
    if (completer != null) return completer.future;
    return _conversation(model: model);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      const <ConversationEvent>[];

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      _conversation();

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async =>
      _conversation();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      _conversation();
}
