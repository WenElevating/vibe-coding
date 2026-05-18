import 'package:flutter/foundation.dart';

import '../../../../domain/repositories/conversation_repository.dart';
import '../../../../domain/repositories/diagnostics_repository.dart';
import '../../../../domain/repositories/run_repository.dart';
import '../../../../domain/repositories/workspace_repository.dart';
import '../../../../models/protocol.dart';
import '../../../../shell/app_snapshot.dart';
import '../../../../workflows/workspace/create_workspace_workflow.dart';
import '../../sessions/session_item.dart';
import '../coding_workbench_controller.dart';
import '../conversation_reducer.dart';
import '../workbench_messages.dart';

enum WorkbenchModelNotice {
  changedToAvailableOption,
}

class WorkbenchViewModel extends ChangeNotifier {
  static const String _unsupportedModelUpdateMessage =
      'existing conversation model updates require a newer daemon';

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
        _adapters = List<AdapterStatus>.unmodifiable(initialData.adapters),
        _selectedAdapter = _computePreferredAdapter(initialData.adapters),
        _draftModel = _initialSelectedModel(initialData.adapters);

  WorkbenchRouteState _routeState;
  final Map<String, SessionItem> _optimisticSessions = <String, SessionItem>{};
  final ConversationRepository? _conversationRepository;
  final DiagnosticsRepository? _diagnosticsRepository;
  final RunRepository? _runRepository;
  final WorkspaceRepository? _workspaceRepository;
  final Duration _workspaceCreationTimeout;
  List<AdapterStatus> _adapters;
  String? _selectedAdapter;
  String? _draftModel;
  String? _confirmedConversationModel;
  bool _modelUpdating = false;
  String? _modelUpdateError;
  bool _conversationModelUpdatesUnsupported = false;
  int _modelUpdateGeneration = 0;
  WorkbenchModelNotice? _modelNotice;
  String? _activeRunId;
  String? _activeConversationId;
  ConversationSummary? _activeConversation;
  final List<WorkbenchMessage> _messages = <WorkbenchMessage>[];
  final List<ConversationEvent> _conversationEvents = <ConversationEvent>[];
  ConversationViewState _conversationState = const ConversationViewState();
  int _lastSeq = 0;
  final Set<String> _resolvedApprovalIds = <String>{};
  bool _sending = false;
  String? _error;
  String? _errorTraceId;

  WorkbenchRouteState get routeState => _routeState;
  List<SessionItem> get optimisticSessions =>
      List.unmodifiable(_optimisticSessions.values);
  String? get selectedAdapter => _selectedAdapter;
  AdapterStatus? get selectedAdapterStatus => _adapterStatusFor(
        _selectedAdapter,
      );
  List<AdapterModelOption> get availableModels =>
      selectedAdapterStatus?.models ?? const <AdapterModelOption>[];
  String? get draftModel => _draftModel;
  String? get confirmedConversationModel => _confirmedConversationModel;
  String? get selectedModel =>
      _activeConversationId == null ? _draftModel : _confirmedConversationModel;
  bool get modelUpdating => _modelUpdating;
  String? get modelUpdateError => _modelUpdateError;
  bool get conversationModelUpdatesUnsupported =>
      _conversationModelUpdatesUnsupported;
  WorkbenchModelNotice? get modelNotice => _modelNotice;
  String? get activeRunId => _activeRunId;
  String? get activeConversationId => _activeConversationId;
  ConversationSummary? get activeConversation => _activeConversation;
  List<WorkbenchMessage> get messages => List.unmodifiable(_messages);
  List<ConversationEvent> get conversationEvents =>
      List.unmodifiable(_conversationEvents);
  ConversationViewState get conversationState => _conversationState;
  int get lastSeq => _lastSeq;
  String? get pendingQuestionId {
    for (final message in _conversationState.messages.reversed) {
      if (message.role == 'question' || message.role == 'question_hidden') {
        return message.questionId;
      }
    }
    return null;
  }

  String get effectiveConversationStatus =>
      _activeConversation?.status ?? _conversationState.status;
  bool get isTerminalConversation =>
      !isActiveConversationStatus(effectiveConversationStatus);
  bool get sending => _sending;
  String? get error => _error;
  String? get errorTraceId => _errorTraceId;
  List<WorkspaceSummary> get workspaces => _routeState.workspaces;
  WorkspaceSummary? get routeWorkspace => switch (_routeState) {
        WorkspaceSessionsRouteState(:final workspace) => workspace,
        ConversationRouteState(:final workspace) => workspace,
        _ => null,
      };

  List<SessionItem> sessionItems(
    List<ConversationSummary> snapshotConversations,
    List<RunSummary> snapshotRuns,
  ) =>
      mergeSessionItems(
          _optimisticSessions, snapshotConversations, snapshotRuns);

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

  void openSession(SessionItem item, {bool notify = true}) {
    final conversationChanged = _activeConversationId != item.conversation?.id;
    _activeRunId = item.run.id;
    _activeConversationId = item.conversation?.id;
    _activeConversation = item.conversation;
    if (conversationChanged) {
      _resetConversationModelUpdateState();
    }
    _selectActiveConversationAdapter(item.conversation);
    if (notify) notifyListeners();
  }

  void updateActiveConversation(
    ConversationSummary conversation, {
    String? runId,
    bool notify = true,
  }) {
    final conversationChanged = _activeConversationId != conversation.id;
    _activeConversation = conversation;
    _activeConversationId = conversation.id;
    _activeRunId = runId ?? _activeRunId ?? conversation.id;
    if (conversationChanged) {
      _resetConversationModelUpdateState();
    }
    _selectActiveConversationAdapter(conversation);
    if (notify) notifyListeners();
  }

  void clearActiveConversation({bool notify = true}) {
    final changed = _activeRunId != null ||
        _activeConversationId != null ||
        _activeConversation != null ||
        _confirmedConversationModel != null ||
        _modelUpdating ||
        _modelUpdateError != null ||
        _conversationModelUpdatesUnsupported;
    _activeRunId = null;
    _activeConversationId = null;
    _activeConversation = null;
    _confirmedConversationModel = null;
    _modelUpdating = false;
    _modelUpdateError = null;
    _conversationModelUpdatesUnsupported = false;
    _modelUpdateGeneration++;
    if (changed && notify) notifyListeners();
  }

  void resetConversationDisplay({
    bool clearActiveConversation = true,
    bool notify = true,
  }) {
    final changed = _messages.isNotEmpty ||
        _conversationEvents.isNotEmpty ||
        _conversationState.messages.isNotEmpty ||
        _conversationState.status != 'idle' ||
        _conversationState.pendingPartial.isNotEmpty ||
        _lastSeq != 0 ||
        _resolvedApprovalIds.isNotEmpty ||
        (clearActiveConversation &&
            (_activeRunId != null ||
                _activeConversationId != null ||
                _activeConversation != null ||
                _confirmedConversationModel != null ||
                _modelUpdating ||
                _modelUpdateError != null ||
                _conversationModelUpdatesUnsupported));
    _messages.clear();
    _conversationEvents.clear();
    _conversationState = const ConversationViewState();
    _lastSeq = 0;
    _resolvedApprovalIds.clear();
    if (clearActiveConversation) {
      _activeRunId = null;
      _activeConversationId = null;
      _activeConversation = null;
      _confirmedConversationModel = null;
      _modelUpdating = false;
      _modelUpdateError = null;
      _conversationModelUpdatesUnsupported = false;
      _modelUpdateGeneration++;
    }
    if (changed && notify) notifyListeners();
  }

  void setCancelledConversationDisplayStatus(
    ConversationSummary? conversation, {
    RunSummary? run,
    bool notify = true,
  }) {
    if (conversation != null) {
      final cancelled = applyCancelledConversationSummary(conversation);
      updateActiveConversation(
        cancelled,
        runId: run?.id ?? cancelled.id,
        notify: false,
      );
      _conversationState = ConversationViewState(
        messages: _conversationState.messages,
        lastSeq: _conversationState.lastSeq,
        status: cancelled.status,
        pendingPartial: _conversationState.pendingPartial,
      );
    } else {
      _conversationState = const ConversationViewState(status: 'cancelled');
      clearActiveConversation(notify: false);
    }
    _lastSeq = 0;
    if (notify) notifyListeners();
  }

  void addUserMessage(String prompt, {bool notify = true}) {
    _messages.add(WorkbenchMessage.user(prompt));
    if (notify) notifyListeners();
  }

  void prepareNewConversationSend(
    ConversationSummary runningConversation, {
    required RunSummary run,
    bool notify = true,
  }) {
    updateActiveConversation(runningConversation, runId: run.id, notify: false);
    _lastSeq = 0;
    _resolvedApprovalIds.clear();
    if (notify) notifyListeners();
  }

  void markConversationRunning({bool notify = true}) {
    final conversation = _activeConversation;
    if (conversation == null) return;
    updateActiveConversation(
      copyConversationStatus(conversation, 'running'),
      notify: notify,
    );
  }

  void removeQuestionMessages({bool notify = true}) {
    final before = _messages.length;
    _messages.removeWhere((message) => message.role == 'question');
    if (notify && _messages.length != before) notifyListeners();
  }

  bool applyConversationEvents(
    List<ConversationEvent> events, {
    required bool streamOutput,
    bool notify = true,
  }) {
    final newEvents = events.where((event) => event.seq > _lastSeq).toList();
    if (newEvents.isEmpty) return false;
    newEvents.sort((a, b) => a.seq.compareTo(b.seq));
    for (final event in newEvents) {
      _conversationEvents.add(event);
      if (event.seq > _lastSeq) _lastSeq = event.seq;
      _applyConversationStatusEvent(event);
    }
    _conversationState =
        _conversationState.apply(newEvents, streamOutput: streamOutput);
    _rebuildMessagesFromConversationState();
    if (notify) notifyListeners();
    return true;
  }

  void applyApprovalResponse(
    AgentEvent event,
    String decision, {
    bool notify = true,
  }) {
    final approvalId = event.approvalId;
    if (approvalId == null || approvalId.isEmpty) return;
    _resolvedApprovalIds.add(approvalId);
    _messages.removeWhere((item) =>
        item.role == 'approval' && item.event?.approvalId == approvalId);
    if (decision == 'allow') {
      _upsertCommandMessage(WorkbenchMessage(
        'command',
        'cwd resolved · permissions checked',
        WorkbenchMessage.toolEventBody(event),
        event: event,
        runId: event.runId,
      ));
    } else {
      _messages.add(WorkbenchMessage.status('Denied permission request'));
    }
    if (notify) notifyListeners();
  }

  void beginOperation({bool notify = true}) {
    _sending = true;
    _error = null;
    _errorTraceId = null;
    if (notify) notifyListeners();
  }

  void finishOperation({bool notify = true}) {
    if (!_sending) return;
    _sending = false;
    if (notify) notifyListeners();
  }

  void setOperationError(
    String message, {
    String? traceId,
    bool notify = true,
  }) {
    _error = message;
    _errorTraceId = traceId;
    if (notify) notifyListeners();
  }

  void clearOperationError({bool notify = true}) {
    final changed = _error != null || _errorTraceId != null;
    _error = null;
    _errorTraceId = null;
    if (changed && notify) notifyListeners();
  }

  void setSelectedAdapter(String? adapter) {
    if (_activeConversationId != null || _sending) return;
    if (_selectedAdapter == adapter) return;
    _selectedAdapter = adapter;
    _draftModel = _preferredModelFor(selectedAdapterStatus);
    _modelNotice = null;
    notifyListeners();
  }

  Future<bool> selectModel(String? model) async {
    if (_sending || _modelUpdating) return false;
    final normalized = _normalizeModel(model);
    final status = selectedAdapterStatus;
    if (normalized != null &&
        (status?.canSelectModel != true ||
            !_modelStillAvailable(normalized, status))) {
      return false;
    }

    final conversationId = _activeConversationId;
    if (conversationId == null) {
      final changed = _draftModel != normalized || _modelNotice != null;
      _draftModel = normalized;
      _modelNotice = null;
      if (changed) notifyListeners();
      return true;
    }

    if (_conversationModelUpdatesUnsupported) {
      _modelUpdateError = _unsupportedModelUpdateMessage;
      notifyListeners();
      return false;
    }

    final repository = _requireConversationRepository();
    final modelUpdateGeneration = ++_modelUpdateGeneration;
    _modelUpdating = true;
    _modelUpdateError = null;
    notifyListeners();
    try {
      final conversation =
          await repository.updateConversationModel(conversationId, normalized);
      if (!_isCurrentModelUpdate(modelUpdateGeneration, conversationId)) {
        return false;
      }
      _activeConversation = conversation;
      _activeConversationId = conversation.id;
      _selectActiveConversationAdapter(conversation);
      _modelUpdateError = null;
      _modelUpdating = false;
      notifyListeners();
      return true;
    } on ConversationRepositoryException catch (error) {
      if (!_isCurrentModelUpdate(modelUpdateGeneration, conversationId)) {
        return false;
      }
      _modelUpdating = false;
      if (_isUnsupportedModelUpdate(error)) {
        _conversationModelUpdatesUnsupported = true;
        _modelUpdateError = _unsupportedModelUpdateMessage;
      } else {
        final message = error.message?.trim();
        _modelUpdateError = message == null || message.isEmpty
            ? error.toString()
            : message;
      }
      notifyListeners();
      return false;
    } catch (error) {
      if (!_isCurrentModelUpdate(modelUpdateGeneration, conversationId)) {
        return false;
      }
      _modelUpdating = false;
      _modelUpdateError = error.toString();
      notifyListeners();
      return false;
    }
  }

  void clearModelNotice({bool notify = true}) {
    if (_modelNotice == null) return;
    _modelNotice = null;
    if (notify) notifyListeners();
  }

  void updateFromSnapshot(AppSnapshot snapshot) {
    reconcile(snapshot, notify: false);
    _adapters = List<AdapterStatus>.unmodifiable(snapshot.adapters);
    final workspaces = List<WorkspaceSummary>.unmodifiable(snapshot.workspaces);
    _routeState = _rebuildRouteState(workspaces);
    final activeConversation = _activeConversation;
    if (activeConversation != null) {
      _selectActiveConversationAdapter(activeConversation);
    } else if (!_selectedAdapterStillAvailable(snapshot.adapters)) {
      _selectedAdapter = _computePreferredAdapter(snapshot.adapters);
    }
    if (_activeConversationId == null) {
      _reconcileSelectedModel();
    }
    notifyListeners();
  }

  void _selectActiveConversationAdapter(ConversationSummary? conversation) {
    _confirmedConversationModel = conversation?.model;
    _modelUpdateError = null;
    final adapter = conversation?.adapter.trim();
    if (adapter == null || adapter.isEmpty) return;
    _selectedAdapter = adapter;
  }

  AdapterStatus? _adapterStatusFor(String? adapter) =>
      _adapterStatusForSelection(_adapters, adapter);

  void _reconcileSelectedModel() {
    final status = selectedAdapterStatus;
    if (_draftModel != null && _modelStillAvailable(_draftModel, status)) {
      return;
    }
    final previous = _draftModel;
    final fallback = _preferredModelFor(status);
    if (previous == null && fallback == null) return;
    _draftModel = fallback;
    if (previous != null && fallback != null && previous != fallback) {
      _modelNotice = WorkbenchModelNotice.changedToAvailableOption;
    } else if (fallback == null) {
      _modelNotice = null;
    }
  }

  String? _modelForCreate({required String adapter, String? requested}) {
    final status = _adapterStatusFor(adapter);
    if (status?.canSelectModel != true) return null;
    final normalized = _normalizeModel(requested) ?? _draftModel;
    return _modelStillAvailable(normalized, status) ? normalized : null;
  }

  bool _isCurrentModelUpdate(int generation, String conversationId) =>
      _modelUpdateGeneration == generation &&
      _activeConversationId == conversationId;

  void _resetConversationModelUpdateState() {
    _modelUpdateGeneration++;
    _modelUpdating = false;
    _modelUpdateError = null;
    _conversationModelUpdatesUnsupported = false;
  }

  bool _selectedAdapterStillAvailable(List<AdapterStatus> adapters) =>
      _selectedAdapter != null &&
      adapters.any((a) =>
          a.adapter == _selectedAdapter &&
          a.available &&
          _isSelectableAdapter(a));

  void reconcile(AppSnapshot snapshot, {bool notify = true}) {
    var changed = false;
    for (final conversation in snapshot.conversations) {
      if (!_optimisticSessions.containsKey(conversation.id)) continue;
      if (!_isPendingSnapshotConversation(conversation)) {
        _optimisticSessions.remove(conversation.id);
        changed = true;
      }
    }
    if (changed && notify) notifyListeners();
  }

  Future<WorkbenchNewConversationSendResult> createAndSend({
    required WorkspaceSummary workspace,
    required String prompt,
    required String adapter,
    required String permissionMode,
    String? model,
  }) async {
    final repository = _requireConversationRepository();
    final modelToSend = _modelForCreate(adapter: adapter, requested: model);
    final conversation = await repository.createConversation(
      workspaceId: workspace.id,
      adapter: adapter,
      permissionMode: permissionMode,
      model: modelToSend,
    );
    _modelNotice = null;
    final runningConversation =
        _copyConversationStatus(conversation, 'sending');
    _optimisticSessions[conversation.id] = SessionItem(
      run: runSummaryFromConversation(runningConversation),
      conversation: runningConversation,
    );
    notifyListeners();
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

  Future<void> respondRunApproval({
    required String approvalId,
    required String decision,
  }) =>
      _requireRunRepository().respondApproval(approvalId, decision);

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

  void _applyConversationStatusEvent(ConversationEvent event) {
    final current = _activeConversation;
    if (current == null) return;
    var status = current.status;
    ConversationBlockingItem? blockingItem = current.blockingItem;
    if (event.type == 'conversation.status_changed') {
      status = event.raw['status'] as String? ?? status;
    } else if (conversationEventCompletesTurn(event)) {
      status = 'idle';
      blockingItem = null;
    } else if (event.type == 'assistant.question') {
      status = 'waiting_input';
      blockingItem = ConversationBlockingItem(
        type: 'input_request',
        questionId: event.questionId,
        toolUseId: event.toolUseId,
        text: event.text,
        suggestions: event.suggestions,
        input: event.input,
      );
    } else if (event.type == 'approval.requested') {
      status = 'waiting_approval';
      blockingItem = ConversationBlockingItem(
        type: 'approval_request',
        approvalId: event.approvalId,
        toolUseId: event.toolUseId,
        toolName: event.toolName,
        summary: event.summary,
        input: event.input,
      );
    } else if (event.type == 'approval.resolved') {
      status = 'running';
      blockingItem = null;
    } else if (event.type == 'conversation.cancelled') {
      status = event.raw['status'] as String? ?? 'cancelled';
      blockingItem = null;
    } else if (event.type == 'run.error') {
      status = 'failed';
      blockingItem = null;
    }
    updateActiveConversation(
      copyConversationStatus(current, status, blockingItem: blockingItem),
      notify: false,
    );
  }

  void _rebuildMessagesFromConversationState() {
    _messages
      ..clear()
      ..addAll(
        messagesForConversationSnapshot(
          _conversationState.messages,
          _activeConversation,
        )
            .where((message) => message.role != 'question_hidden')
            .map(workbenchMessageFromConversation),
      );
    final emptyCompletionDiagnostic = emptyConversationCompletionDiagnostic(
      _conversationEvents,
      _conversationState.messages,
      isTerminalConversation,
    );
    if (emptyCompletionDiagnostic != null) {
      _messages.add(WorkbenchMessage.status(emptyCompletionDiagnostic));
    }
  }

  void _upsertCommandMessage(WorkbenchMessage message) {
    final command = message.body.trim();
    final existingIndex = _messages.indexWhere((item) =>
        item.role == 'command' &&
        item.runId == message.runId &&
        _sameCommandDisplay(item.body.trim(), command));
    if (existingIndex >= 0) {
      final current = _messages[existingIndex];
      final body = _preferDetailedCommand(current.body.trim(), command);
      _messages[existingIndex] = current.copyWith(
        body: body,
        completed: current.completed || message.completed,
        isError: current.isError || message.isError,
        duration: message.duration ?? current.duration,
      );
    } else {
      _messages.add(message);
    }
  }

  bool _sameCommandDisplay(String current, String incoming) {
    if (current == incoming) return true;
    if (current.isEmpty || incoming.isEmpty) return false;
    final currentHead = current.split(RegExp(r'\s+')).first;
    final incomingHead = incoming.split(RegExp(r'\s+')).first;
    return currentHead == incomingHead &&
        (incoming.startsWith('$current ') || current.startsWith('$incoming '));
  }

  String _preferDetailedCommand(String current, String incoming) {
    return incoming.length > current.length ? incoming : current;
  }

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

  static String? _initialSelectedModel(List<AdapterStatus> adapters) {
    final selectedAdapter = _computePreferredAdapter(adapters);
    return _preferredModelFor(
      _adapterStatusForSelection(adapters, selectedAdapter),
    );
  }

  static AdapterStatus? _adapterStatusForSelection(
    List<AdapterStatus> adapters,
    String? adapter,
  ) {
    final id = adapter?.trim();
    if (id == null || id.isEmpty) return null;
    for (final status in adapters) {
      if (status.adapter == id &&
          status.available &&
          _isSelectableAdapter(status)) {
        return status;
      }
    }
    return null;
  }

  static String? _preferredModelFor(AdapterStatus? adapter) {
    final models = adapter?.models ?? const <AdapterModelOption>[];
    if (models.isEmpty) return null;
    final selectedModel = _normalizeModel(adapter?.selectedModel);
    if (selectedModel != null &&
        models.any((model) => model.id == selectedModel)) {
      return selectedModel;
    }
    for (final model in models) {
      final id = _normalizeModel(model.id);
      if (model.selected && id != null) return id;
    }
    for (final model in models) {
      final id = _normalizeModel(model.id);
      if (id != null) return id;
    }
    return null;
  }

  static bool _modelStillAvailable(
    String? model,
    AdapterStatus? adapter,
  ) {
    final id = _normalizeModel(model);
    if (id == null) return true;
    final models = adapter?.models ?? const <AdapterModelOption>[];
    return models.any((model) => model.id == id);
  }

  static String? _normalizeModel(String? model) {
    final trimmed = model?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool _isUnsupportedModelUpdate(ConversationRepositoryException error) {
    if (error.statusCode == 405) return true;
    if (error.statusCode != 404) return false;
    return error.code != 'NOT_FOUND';
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
        model: conversation.model,
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
  Map<String, SessionItem> optimisticSessions,
  List<ConversationSummary> snapshotConversations,
  List<RunSummary> snapshotRuns,
) {
  final items = <SessionItem>[];
  final seen = <String>{};
  for (final conversation in snapshotConversations) {
    final optimistic = optimisticSessions[conversation.id];
    if (optimistic != null && _isPendingSnapshotConversation(conversation)) {
      if (seen.add(optimistic.id)) items.add(optimistic);
      continue;
    }
    if (!shouldShowConversationInSessionList(conversation,
        isOptimistic: optimistic != null)) {
      continue;
    }
    if (seen.add(conversation.id)) {
      items.add(
        SessionItem(
          run: runSummaryFromConversation(conversation),
          conversation: conversation,
        ),
      );
    }
  }
  for (final item in optimisticSessions.values) {
    if (seen.add(item.id)) items.add(item);
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) items.add(SessionItem(run: run));
  }
  return items;
}

bool shouldShowConversationInSessionList(
  ConversationSummary conversation, {
  bool isOptimistic = false,
}) {
  if (isOptimistic) return true;
  if (conversation.status == 'idle' &&
      conversation.cliSessionId == null &&
      conversation.userMessageCount == 0) {
    return false;
  }
  return true;
}

bool _isPendingSnapshotConversation(ConversationSummary conversation) =>
    conversation.status == 'idle' && conversation.userMessageCount == 0;

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
