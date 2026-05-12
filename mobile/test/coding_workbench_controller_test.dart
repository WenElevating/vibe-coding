import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/features/workbench/workbench.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/workflows/workspace/create_workspace_workflow.dart';

void main() {
  test('workspace list route exposes daemon-confirmed workspaces', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const route = WorkspaceListRouteState(
      workspaces: <WorkspaceSummary>[current],
    );

    expect(route.workspaces, const <WorkspaceSummary>[current]);
  });

  test(
      'creating workspace route keeps previous workspaces only as display state',
      () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const state = CreatingWorkspaceRouteState(
      previousWorkspaces: <WorkspaceSummary>[current],
      requestLabel: 'Created Workspace',
    );

    expect(state.workspaces, const <WorkspaceSummary>[current]);
    expect(state.requestLabel, 'Created Workspace');
  });

  test('sessions route carries workspace context and workspace list', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const created = WorkspaceSummary(
      id: 'workspace_created',
      name: 'Created Workspace',
      path: r'D:\created',
    );

    const route = WorkspaceSessionsRouteState(
      workspace: created,
      workspaces: <WorkspaceSummary>[current, created],
    );

    expect(route.workspace, created);
    expect(route.workspaces, const <WorkspaceSummary>[current, created]);
  });

  test('conversation route carries workspace context and workspace list', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const conversationWorkspace = WorkspaceSummary(
      id: 'workspace_conversation',
      name: 'Conversation Workspace',
      path: r'D:\conversation',
    );

    const route = ConversationRouteState(
      workspace: conversationWorkspace,
      workspaces: <WorkspaceSummary>[current, conversationWorkspace],
    );

    expect(route.workspace, conversationWorkspace);
    expect(route.workspaces,
        const <WorkspaceSummary>[current, conversationWorkspace]);
  });

  test('reusable conversation statuses can send another message', () {
    expect(canSendInConversationStatus(null), isTrue);
    expect(canSendInConversationStatus('idle'), isTrue);
    expect(canSendInConversationStatus('cancelled'), isTrue);
    expect(canSendInConversationStatus('failed'), isTrue);
    expect(canSendInConversationStatus('interrupted'), isTrue);
    expect(canSendInConversationStatus('running'), isFalse);
    expect(canSendInConversationStatus('waiting_input'), isFalse);
    expect(canSendInConversationStatus('waiting_approval'), isFalse);
  });

  test('active conversation status helper matches executor states', () {
    expect(isActiveConversationStatus('running'), isTrue);
    expect(isActiveConversationStatus('waiting_input'), isTrue);
    expect(isActiveConversationStatus('waiting_approval'), isTrue);
    expect(isActiveConversationStatus('cancelled'), isFalse);
    expect(isActiveConversationStatus('interrupted'), isFalse);
  });

  test('cancelled conversation summary keeps product identity and binding', () {
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'cancelled',
      cliSessionId: 'claude-session-1',
      sessionBinding: 'confirmed',
      userMessageCount: 2,
      capabilities: ConversationCapabilities(
        longLivedProcess: true,
        waitingInput: true,
        waitingApproval: true,
        resume: true,
        partialOutput: true,
      ),
      blockingItem: ConversationBlockingItem(type: 'approval_request'),
      createdAt: '2026-05-08T00:00:00.000Z',
      updatedAt: '2026-05-08T00:00:01.000Z',
    );

    final cancelled = applyCancelledConversationSummary(conversation);

    expect(cancelled.id, 'conv_1');
    expect(cancelled.cliSessionId, 'claude-session-1');
    expect(cancelled.sessionBinding, 'confirmed');
    expect(cancelled.userMessageCount, 2);
    expect(cancelled.blockingItem, isNull);
  });

  test('workbench view model coordinates new conversation send flow', () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final result = await viewModel.sendNewConversationPrompt(
      workspace: _workspace,
      prompt: 'hello',
      adapter: 'codex',
      permissionMode: 'default',
    );
    final updated = await result.updatedConversation;

    expect(repository.calls, <String>[
      'create:workspace_1:codex:default',
      'send:conv_1:hello',
    ]);
    expect(result.conversation.id, 'conv_1');
    expect(result.runningConversation.status, 'running');
    expect(result.run.id, 'conv_1');
    expect(updated.status, 'idle');
  });

  test('workbench view model sends existing conversation prompt', () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final updated = await viewModel.sendExistingConversationPrompt(
      conversationId: 'conv_existing',
      prompt: 'continue',
    );

    expect(repository.calls, <String>['send:conv_existing:continue']);
    expect(updated.id, 'conv_existing');
    expect(updated.status, 'idle');
  });

  test('workbench view model fetches conversation events after sequence',
      () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final events = await viewModel.fetchConversationEvents(
      conversationId: 'conv_existing',
      afterSeq: 7,
    );

    expect(repository.calls, <String>['events:conv_existing:7']);
    expect(events.single.seq, 8);
    expect(events.single.type, 'assistant.message');
  });

  test('workbench view model responds to conversation approval', () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final updated = await viewModel.respondConversationApproval(
      conversationId: 'conv_existing',
      approvalId: 'approval_1',
      decision: 'allow',
    );

    expect(repository.calls, <String>[
      'approval:conv_existing:approval_1:allow',
    ]);
    expect(updated.id, 'conv_existing');
    expect(updated.status, 'running');
  });

  test('workbench view model creates workspace through workflow', () async {
    const created = WorkspaceSummary(
      id: 'workspace_new',
      name: 'New Workspace',
      path: r'D:\new',
    );
    final repository = _FakeWorkspaceRepository(
      createdWorkspace: created,
      listedWorkspaces: const <WorkspaceSummary>[_workspace, created],
    );
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
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
}

const _workspace = WorkspaceSummary(
  id: 'workspace_1',
  name: 'Workspace',
  path: r'D:\workspace',
);

AppSnapshot _snapshot({required List<WorkspaceSummary> workspaces}) =>
    AppSnapshot(
      health: const DaemonHealth(
        status: 'ok',
        daemonVersion: '1.0.0',
        mode: 'lan',
        lanMode: true,
        bindAddress: '127.0.0.1',
        port: 4317,
        security: <String, Object?>{},
      ),
      workspaces: workspaces,
      workspace: workspaces.first,
      overview: ProjectOverview(
        workspaceId: workspaces.first.id,
        name: 'Workspace',
        path: workspaces.first.path,
        fileCount: 0,
        codeLineCount: 0,
        symbolCount: 0,
        analysisScore: 0,
        recentFiles: const <RecentFileSummary>[],
      ),
      adapters: const <AdapterStatus>[],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: null,
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: FileTreeResponse(
        workspaceId: workspaces.first.id,
        root: '',
        entries: const <FileTreeEntry>[],
      ),
      diagnostics: CodeDiagnosticsSummary(
        workspaceId: workspaces.first.id,
        available: false,
        diagnostics: const <CodeDiagnostic>[],
      ),
      extensions: const <ExtensionSummary>[],
    );

class _FakeConversationRepository implements ConversationRepository {
  final List<String> calls = <String>[];

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
  }) async {
    calls.add('create:$workspaceId:$adapter:$permissionMode');
    return _conversation(
        id: 'conv_1', workspaceId: workspaceId, status: 'idle');
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    String text,
  ) async {
    calls.add('send:$conversationId:$text');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'idle',
    );
  }

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async {
    calls.add('answer:$conversationId:$questionId:$text');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'idle',
    );
  }

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      throw UnimplementedError();

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
  Future<List<ConversationSummary>> listConversations() async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async {
    calls.add('approval:$conversationId:$approvalId:$decision');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'running',
    );
  }
}

class _FakeWorkspaceRepository implements WorkspaceRepository {
  _FakeWorkspaceRepository({
    required this.createdWorkspace,
    required this.listedWorkspaces,
  });

  final WorkspaceSummary createdWorkspace;
  final List<WorkspaceSummary> listedWorkspaces;
  final List<String> calls = <String>[];

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async {
    calls.add('create:$path:$name');
    return createdWorkspace;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    calls.add('list');
    return listedWorkspaces;
  }

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<FileContent> fileContent(String workspaceId, String path) async =>
      throw UnimplementedError();

  @override
  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path = '',
    int maxDepth = 8,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<List<GitCommitSummary>> gitCommits(
    String workspaceId, {
    int limit = 20,
  }) async =>
      throw UnimplementedError();

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<DirectoryListing> listDirectory(String path) async =>
      throw UnimplementedError();

  @override
  Future<List<DirectoryEntrySummary>> listFileSystemRoots() async =>
      throw UnimplementedError();

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) async =>
      throw UnimplementedError();
}

ConversationSummary _conversation({
  required String id,
  required String workspaceId,
  required String status,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: 'codex',
      status: status,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-12T00:00:00.000Z',
      updatedAt: '2026-05-12T00:00:01.000Z',
    );
