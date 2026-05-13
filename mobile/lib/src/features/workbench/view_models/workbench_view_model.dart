import 'package:flutter/foundation.dart';

import '../../../domain/repositories/conversation_repository.dart';
import '../../../domain/repositories/diagnostics_repository.dart';
import '../../../domain/repositories/run_repository.dart';
import '../../../domain/repositories/workspace_repository.dart';
import '../../../models/protocol.dart';
import '../../../shell/app_snapshot.dart';
import '../../../ui/features/workbench/workbench_route_state.dart';
import '../../../workflows/workspace/create_workspace_workflow.dart';
import '../../sessions/session_item.dart';

class WorkbenchViewModel extends ChangeNotifier {
  WorkbenchViewModel({
    required AppSnapshot initialData,
    ConversationRepository? conversationRepository,
    DiagnosticsRepository? diagnosticsRepository,
    RunRepository? runRepository,
    WorkspaceRepository? workspaceRepository,
    Duration workspaceCreationTimeout = const Duration(seconds: 20),
  })  : _conversationRepository = conversationRepository,
        _diagnosticsRepository = diagnosticsRepository,
        _runRepository = runRepository,
        _workspaceRepository = workspaceRepository,
        _workspaceCreationTimeout = workspaceCreationTimeout,
        _routeState = WorkspaceListRouteState(
          workspaces: List.unmodifiable(initialData.workspaces),
        ),
        _selectedAdapter = _computePreferredAdapter(initialData.adapters);

  WorkbenchRouteState _routeState;
  final List<SessionItem> _localSessions = <SessionItem>[];
  final ConversationRepository? _conversationRepository;
  final DiagnosticsRepository? _diagnosticsRepository;
  final RunRepository? _runRepository;
  final WorkspaceRepository? _workspaceRepository;
  final Duration _workspaceCreationTimeout;
  String? _selectedAdapter;

  WorkbenchRouteState get routeState => _routeState;
  List<SessionItem> get localSessions => List.unmodifiable(_localSessions);
  String? get selectedAdapter => _selectedAdapter;
  List<WorkspaceSummary> get workspaces => _routeState.workspaces;

  List<SessionItem> sessionItems(
    List<ConversationSummary> snapshotConversations,
    List<RunSummary> snapshotRuns,
  ) =>
      mergeSessionItems(_localSessions, snapshotConversations, snapshotRuns);

  void showWorkspaceList({String? notice}) {
    _routeState = WorkspaceListRouteState(
      workspaces: _routeState.workspaces,
      notice: notice,
    );
    notifyListeners();
  }

  void showSessions(WorkspaceSummary workspace) {
    _routeState = WorkspaceSessionsRouteState(
      workspace: workspace,
      workspaces: _routeState.workspaces,
    );
    notifyListeners();
  }

  void showConversation(WorkspaceSummary workspace) {
    _routeState = ConversationRouteState(
      workspace: workspace,
      workspaces: _routeState.workspaces,
    );
    notifyListeners();
  }

  void showCreatingWorkspace({required String requestLabel}) {
    _routeState = CreatingWorkspaceRouteState(
      previousWorkspaces: _routeState.workspaces,
      requestLabel: requestLabel,
    );
    notifyListeners();
  }

  void confirmWorkspaceCreated({
    required WorkspaceSummary workspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    _routeState = WorkspaceSessionsRouteState(
      workspace: workspace,
      workspaces: List.unmodifiable(workspaces),
    );
    notifyListeners();
  }

  void cancelWorkspaceCreation(List<WorkspaceSummary> workspaces) {
    _routeState = WorkspaceListRouteState(
      workspaces: List.unmodifiable(workspaces),
    );
    notifyListeners();
  }

  void rememberSession(SessionItem item) {
    _localSessions.removeWhere((s) => s.id == item.id);
    _localSessions.insert(0, item);
    notifyListeners();
  }

  void setSelectedAdapter(String? adapter) {
    if (_selectedAdapter == adapter) return;
    _selectedAdapter = adapter;
    notifyListeners();
  }

  void updateFromSnapshot(AppSnapshot snapshot) {
    final workspaces = List<WorkspaceSummary>.unmodifiable(snapshot.workspaces);
    _routeState = _rebuildRouteState(workspaces);
    final stillAvailable = _selectedAdapter != null &&
        snapshot.adapters.any((a) =>
            a.adapter == _selectedAdapter &&
            a.available &&
            _isSelectableAdapter(a));
    if (!stillAvailable) {
      _selectedAdapter = _computePreferredAdapter(snapshot.adapters);
    }
    notifyListeners();
  }

  Future<WorkbenchNewConversationSendResult> sendNewConversationPrompt({
    required WorkspaceSummary workspace,
    required String prompt,
    required String adapter,
    required String permissionMode,
  }) async {
    final repository = _requireConversationRepository();
    final conversation = await repository.createConversation(
      workspaceId: workspace.id,
      adapter: adapter,
      permissionMode: permissionMode,
    );
    final runningConversation =
        _copyConversationStatus(conversation, 'running');
    return WorkbenchNewConversationSendResult(
      conversation: conversation,
      runningConversation: runningConversation,
      run: runSummaryFromConversation(conversation),
      updatedConversation:
          repository.sendConversationMessage(conversation.id, prompt),
    );
  }

  Future<ConversationSummary> sendExistingConversationPrompt({
    required String conversationId,
    required String prompt,
    Future<void> Function()? restartPolling,
  }) async {
    final repository = _requireConversationRepository();
    final send = repository.sendConversationMessage(conversationId, prompt);
    await restartPolling?.call();
    return send;
  }

  Future<ConversationSummary> answerConversationQuestion({
    required String conversationId,
    required String questionId,
    required String text,
  }) =>
      _requireConversationRepository().answerConversationQuestion(
        conversationId,
        questionId,
        text,
      );

  Future<List<ConversationEvent>> fetchConversationEvents({
    required String conversationId,
    required int afterSeq,
  }) =>
      _requireConversationRepository().fetchConversationEvents(
        conversationId,
        afterSeq: afterSeq,
      );

  Future<ConversationSummary> respondConversationApproval({
    required String conversationId,
    required String approvalId,
    required String decision,
  }) =>
      _requireConversationRepository().respondConversationApproval(
        conversationId,
        approvalId,
        decision,
      );

  Future<WorkbenchCancelResult> cancelActiveRun({
    String? conversationId,
    String? runId,
  }) async {
    if (conversationId != null) {
      final conversation = await _requireConversationRepository()
          .cancelConversation(conversationId);
      return WorkbenchCancelResult(
        conversation: conversation,
        run: runSummaryFromConversation(conversation),
      );
    }
    if (runId != null) {
      final run = await _requireRunRepository().cancelRun(runId);
      return WorkbenchCancelResult(run: run);
    }
    throw StateError('A conversationId or runId is required to cancel work.');
  }

  Future<String> recordException({
    required String message,
    required String stack,
    String? path,
    String? conversationId,
    String? runId,
    required String operation,
  }) =>
      _requireDiagnosticsRepository().recordException(
        message: message,
        stack: stack,
        path: path,
        method: path == null ? null : 'GET',
        conversationId: conversationId,
        runId: runId,
        metadata: <String, Object?>{'operation': operation},
      );

  Future<CreateWorkspaceOutcome> createWorkspace({
    required String path,
    String? name,
  }) =>
      CreateWorkspaceWorkflow(
        client: _requireWorkspaceRepository(),
        timeout: _workspaceCreationTimeout,
      ).create(path: path, name: name);

  ConversationRepository _requireConversationRepository() {
    final repository = _conversationRepository;
    if (repository == null) {
      throw StateError(
          'ConversationRepository is required for workbench sends.');
    }
    return repository;
  }

  DiagnosticsRepository _requireDiagnosticsRepository() {
    final repository = _diagnosticsRepository;
    if (repository == null) {
      throw StateError(
          'DiagnosticsRepository is required for exception tracing.');
    }
    return repository;
  }

  WorkspaceRepository _requireWorkspaceRepository() {
    final repository = _workspaceRepository;
    if (repository == null) {
      throw StateError(
          'WorkspaceRepository is required for workspace creation.');
    }
    return repository;
  }

  RunRepository _requireRunRepository() {
    final repository = _runRepository;
    if (repository == null) {
      throw StateError('RunRepository is required for run cancellation.');
    }
    return repository;
  }

  WorkbenchRouteState _rebuildRouteState(List<WorkspaceSummary> workspaces) =>
      switch (_routeState) {
        WorkspaceListRouteState(:final notice) =>
          WorkspaceListRouteState(workspaces: workspaces, notice: notice),
        WorkspaceSessionsRouteState(:final workspace) =>
          WorkspaceSessionsRouteState(
            workspace: _resolveWorkspace(workspaces, workspace),
            workspaces: workspaces,
          ),
        ConversationRouteState(:final workspace) => ConversationRouteState(
            workspace: _resolveWorkspace(workspaces, workspace),
            workspaces: workspaces,
          ),
        CreatingWorkspaceRouteState(:final requestLabel) =>
          CreatingWorkspaceRouteState(
            previousWorkspaces: workspaces,
            requestLabel: requestLabel,
          ),
      };

  static WorkspaceSummary _resolveWorkspace(
    List<WorkspaceSummary> workspaces,
    WorkspaceSummary fallback,
  ) {
    for (final w in workspaces) {
      if (w.id == fallback.id) return w;
    }
    return fallback;
  }

  static String? _computePreferredAdapter(List<AdapterStatus> adapters) {
    for (final name in const ['claude', 'codex', 'opencode']) {
      final found = adapters.where(
          (a) => a.adapter == name && a.available && _isSelectableAdapter(a));
      if (found.isNotEmpty) return found.first.adapter;
    }
    final available =
        adapters.where((a) => a.available && _isSelectableAdapter(a));
    return available.isEmpty ? null : available.first.adapter;
  }

  static bool _isSelectableAdapter(AdapterStatus adapter) {
    final id = adapter.adapter.trim().toLowerCase();
    if (id.isEmpty || id.startsWith('synthetic-')) return false;
    return const {'claude', 'codex', 'opencode'}.contains(id);
  }

  static ConversationSummary _copyConversationStatus(
    ConversationSummary conversation,
    String status,
  ) =>
      ConversationSummary(
        id: conversation.id,
        workspaceId: conversation.workspaceId,
        adapter: conversation.adapter,
        status: status,
        capabilities: conversation.capabilities,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
        cliSessionId: conversation.cliSessionId,
        sessionBinding: conversation.sessionBinding,
        userMessageCount: conversation.userMessageCount,
        blockingItem: conversation.blockingItem,
        idleExpiresAt: conversation.idleExpiresAt,
      );

  static RunSummary runSummaryFromConversation(
    ConversationSummary conversation,
  ) =>
      RunSummary(
        id: conversation.id,
        tool: conversation.adapter,
        workspaceId: conversation.workspaceId,
        status: _runStatusFromConversation(conversation.status),
        cliSessionId: conversation.cliSessionId,
      );

  static String _runStatusFromConversation(String status) {
    if (status == 'idle') return 'completed';
    if (status == 'cancelled' ||
        status == 'failed' ||
        status == 'interrupted') {
      return status;
    }
    return 'running';
  }
}

class WorkbenchNewConversationSendResult {
  const WorkbenchNewConversationSendResult({
    required this.conversation,
    required this.runningConversation,
    required this.run,
    required this.updatedConversation,
  });

  final ConversationSummary conversation;
  final ConversationSummary runningConversation;
  final RunSummary run;
  final Future<ConversationSummary> updatedConversation;
}

class WorkbenchCancelResult {
  const WorkbenchCancelResult({this.conversation, this.run});

  final ConversationSummary? conversation;
  final RunSummary? run;
}

List<SessionItem> mergeSessionItems(
  List<SessionItem> localSessions,
  List<ConversationSummary> snapshotConversations,
  List<RunSummary> snapshotRuns,
) {
  final items = <SessionItem>[];
  final seen = <String>{};
  for (final item in localSessions) {
    if (seen.add(item.id)) items.add(item);
  }
  for (final conversation in snapshotConversations) {
    if (!shouldShowConversationInSessionList(conversation)) continue;
    if (seen.add(conversation.id)) {
      items.add(SessionItem(
        run: runSummaryFromConversation(conversation),
        conversation: conversation,
      ));
    }
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) items.add(SessionItem(run: run));
  }
  return items;
}

bool shouldShowConversationInSessionList(ConversationSummary conversation) {
  if (conversation.status == 'idle' &&
      conversation.cliSessionId == null &&
      conversation.userMessageCount == 0) {
    return false;
  }
  return true;
}

RunSummary runSummaryFromConversation(ConversationSummary conversation) {
  return RunSummary(
    id: conversation.id,
    tool: conversation.adapter,
    workspaceId: conversation.workspaceId,
    status: runStatusFromConversation(conversation.status),
    cliSessionId: conversation.cliSessionId,
  );
}

String runStatusFromConversation(String status) {
  if (status == 'idle') return 'completed';
  if (status == 'cancelled' || status == 'failed' || status == 'interrupted') {
    return status;
  }
  return 'running';
}
