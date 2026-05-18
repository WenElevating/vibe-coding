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
      expect(viewModel.modelNotice, isNull);
    });

    test('setSelectedModel updates draft model state', () {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );

      viewModel.setSelectedModel('gpt-5-mini');

      expect(viewModel.selectedModel, 'gpt-5-mini');
      expect(viewModel.modelNotice, isNull);
    });

    test('setSelectedModel ignores unsupported model ids', () {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );

      viewModel.setSelectedModel('not-configured');

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

    test('active conversation state allows model changes', () {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(adapters: const <AdapterStatus>[_codexModels]),
      );
      viewModel.updateActiveConversation(_conversation(adapter: 'codex'));

      viewModel.setSelectedModel('gpt-5-mini');

      expect(viewModel.selectedModel, 'gpt-5-mini');
    });

    test('sending operation state refuses adapter and model changes', () {
      final viewModel = WorkbenchViewModel(
        initialData: _snapshot(
          adapters: const <AdapterStatus>[_codexModels, _claudeAvailable],
        ),
      );

      viewModel.beginOperation();
      viewModel.setSelectedAdapter('claude');
      viewModel.setSelectedModel('gpt-5-mini');

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

ConversationSummary _conversation({String adapter = 'codex'}) =>
    ConversationSummary(
      id: 'conv_1',
      workspaceId: _workspace.id,
      adapter: adapter,
      status: 'idle',
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-18T00:00:00.000Z',
      updatedAt: '2026-05-18T00:00:01.000Z',
    );

class _FakeConversationRepository implements ConversationRepository {
  final List<String> calls = <String>[];

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    calls.add('create:$workspaceId:$adapter:$permissionMode:$model');
    return _conversation(adapter: adapter);
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
