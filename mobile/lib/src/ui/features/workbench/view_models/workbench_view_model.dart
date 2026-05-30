import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/cached_conversation_repository.dart';
import '../../../../data/repositories/cached_run_repository.dart';
import '../../../../data/repositories/cli_adapter_repository.dart';
import '../../../../data/repositories/workspace_repository.dart';
import '../../../../domain/repositories/conversation_repository.dart';
import '../../../../domain/repositories/diagnostics_repository.dart';
import '../../../../domain/repositories/run_repository.dart';
import '../../../../models/protocol.dart';
import '../../../../workflows/connection/open_workspace_use_case.dart';
import '../../../../workflows/workspace/create_workspace_workflow.dart';
import '../../sessions/session_item.dart';
import '../attachments/attachment_preview_cache.dart';
import '../attachments/draft_attachment.dart';
import '../coding_workbench_controller.dart';
import '../conversation_reducer.dart';
import '../workbench_messages.dart';

typedef WorkbenchEventApplicationIsCurrent = bool Function();

enum WorkbenchModelNotice {
  changedToAvailableOption,
}

class WorkbenchViewModel extends ChangeNotifier {
  static const String _unsupportedModelUpdateMessage =
      'existing conversation model updates require a newer daemon';
  static const int _maxDraftAttachments = 4;
  static const int _maxEventTraceEntries = 200;
  static const int _claudeImageBytesLimit = 5 * 1024 * 1024;
  static const int _defaultImageBytesLimit = 10 * 1024 * 1024;
  static const int _textDocumentBytesLimit = 1024 * 1024;
  static const int _totalMultipartBytesLimit = 20 * 1024 * 1024;

  WorkbenchViewModel({
    required WorkspaceRepository workspaceRepository,
    required CliAdapterRepository adapterRepository,
    required CachedConversationRepository conversationRepository,
    required CachedRunRepository runRepository,
    DiagnosticsRepository? diagnosticsRepository,
    WorkspaceOpeningUseCase? workspaceOpeningUseCase,
    AttachmentPreviewCache attachmentPreviewCache =
        const NoopAttachmentPreviewCache(),
    Duration workspaceCreationTimeout = const Duration(seconds: 20),
  })  : _workspaceRepository = workspaceRepository,
        _adapterRepository = adapterRepository,
        _conversationRepository = conversationRepository,
        _runRepository = runRepository,
        _diagnosticsRepository = diagnosticsRepository,
        _workspaceOpeningUseCase = workspaceOpeningUseCase,
        _attachmentPreviewCache = attachmentPreviewCache,
        _workspaceCreationTimeout = workspaceCreationTimeout,
        _routeState = const WorkspaceListRouteState() {
    _workspaceRepository.addListener(_onRepositoryChanged);
    _adapterRepository.addListener(_onAdapterRepositoryChanged);
    _conversationRepository.addListener(_onRepositoryChanged);
    _runRepository.addListener(_onRepositoryChanged);
    _applyAdapters(_adapterRepository.adapters);
    _selectedAdapter = _computePreferredAdapter(_adapterRepository.adapters);
    _reconcileSelectedModel();
  }

  WorkbenchRouteState _routeState;
  final Map<String, SessionItem> _optimisticSessions = <String, SessionItem>{};
  final AttachmentPreviewCache _attachmentPreviewCache;
  final CachedConversationRepository _conversationRepository;
  final DiagnosticsRepository? _diagnosticsRepository;
  final CachedRunRepository _runRepository;
  final WorkspaceRepository _workspaceRepository;
  final CliAdapterRepository _adapterRepository;
  final WorkspaceOpeningUseCase? _workspaceOpeningUseCase;
  final Duration _workspaceCreationTimeout;
  late List<AdapterStatus> _adapters;
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
  final List<WorkbenchEventTraceEntry> _eventTraceEntries =
      <WorkbenchEventTraceEntry>[];
  final List<DraftAttachment> _draftAttachments = <DraftAttachment>[];
  final Map<String, List<AttachmentPreviewIdentity>>
      _pendingAttachmentPreviewIdentities =
      <String, List<AttachmentPreviewIdentity>>{};
  ConversationViewState _conversationState = const ConversationViewState();
  int _lastSeq = 0;
  int? _oldestLoadedConversationSeq;
  bool _hasMoreHistoricalConversationEvents = false;
  bool _loadingOlderConversationEvents = false;
  Object? _historicalConversationLoadError;
  final Set<String> _resolvedApprovalIds = <String>{};
  bool _sending = false;
  String? _openingWorkspaceId;
  String? _error;
  String? _errorTraceId;
  String? _currentAttachmentClientMessageId;
  String? _currentAttachmentConversationId;
  bool _disposed = false;

  WorkbenchRouteState get routeState => _routeState;
  List<SessionItem> get optimisticSessions =>
      List.unmodifiable(_optimisticSessions.values);
  String? get selectedAdapter => _selectedAdapter;
  AdapterStatus? get selectedAdapterStatus => _adapterStatusFor(
        _selectedAdapter,
      );
  List<AdapterModelOption> get availableModels =>
      selectedAdapterStatus?.models ?? const <AdapterModelOption>[];
  List<AdapterStatus> get availableAdaptersFromCache =>
      _adapterRepository.adapters;
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
  List<WorkbenchEventTraceEntry> get eventTraceEntries =>
      List.unmodifiable(_eventTraceEntries);
  List<DraftAttachment> get draftAttachments =>
      List.unmodifiable(_draftAttachments);

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _workspaceRepository.removeListener(_onRepositoryChanged);
    _adapterRepository.removeListener(_onAdapterRepositoryChanged);
    _conversationRepository.removeListener(_onRepositoryChanged);
    _runRepository.removeListener(_onRepositoryChanged);
    _disposed = true;
    _modelUpdateGeneration++;
    super.dispose();
  }

  void _onRepositoryChanged() => _notifyListeners();

  void _onAdapterRepositoryChanged() {
    _applyAdapters(_adapterRepository.adapters);
    final activeConversation = _activeConversation;
    if (activeConversation != null) {
      _selectActiveConversationAdapter(activeConversation);
    } else if (!_selectedAdapterStillAvailable(_adapterRepository.adapters)) {
      _selectedAdapter = _computePreferredAdapter(_adapterRepository.adapters);
    }
    if (_activeConversationId == null) {
      _reconcileSelectedModel();
    }
    _revalidateDraftAttachments();
    _notifyListeners();
  }

  ConversationViewState get conversationState => _conversationState;
  int get lastSeq => _lastSeq;
  int? get oldestLoadedConversationSeq => _oldestLoadedConversationSeq;
  bool get hasMoreHistoricalConversationEvents =>
      _hasMoreHistoricalConversationEvents;
  bool get loadingOlderConversationEvents => _loadingOlderConversationEvents;
  Object? get historicalConversationLoadError =>
      _historicalConversationLoadError;
  String? get pendingQuestionId {
    final conversation = _activeConversation;
    final blockingItem = conversation?.blockingItem;
    if (conversation?.status == 'waiting_input' &&
        blockingItem?.type == 'input_request') {
      return blockingItem?.questionId;
    }
    return null;
  }

  String get effectiveConversationStatus =>
      _activeConversation?.status ?? _conversationState.status;
  bool get isTerminalConversation =>
      !isActiveConversationStatus(effectiveConversationStatus);
  bool get sending => _sending;
  String? get openingWorkspaceId => _openingWorkspaceId;
  bool get openingWorkspace => _openingWorkspaceId != null;
  String? get error => _error;
  String? get errorTraceId => _errorTraceId;
  List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
  WorkspaceSummary? get selectedWorkspace =>
      _workspaceRepository.selectedWorkspace;

  WorkspaceSummary? get routeWorkspace => switch (_routeState) {
        WorkspaceSessionsRouteState(:final workspaceId) =>
          _workspaceById(workspaceId),
        ConversationRouteState(:final workspaceId) =>
          _workspaceById(workspaceId),
        _ => null,
      };

  WorkspaceSummary? _workspaceById(String id) {
    for (final workspace in _workspaceRepository.workspaces) {
      if (workspace.id == id) return workspace;
    }
    return null;
  }

  List<SessionItem> get sessionItems => mergeSessionItems(
        _optimisticSessions,
        _conversationRepository.conversations,
        _runRepository.runs,
      );

  void showWorkspaceList({String? notice}) {
    _routeState = WorkspaceListRouteState(notice: notice);
    _notifyListeners();
  }

  void showSessions(String workspaceId) {
    _routeState = WorkspaceSessionsRouteState(workspaceId: workspaceId);
    _notifyListeners();
  }

  void showConversation(String workspaceId) {
    _routeState = WorkspaceSessionsRouteState(workspaceId: workspaceId);
    _notifyListeners();
  }

  void showConversationRoute(String workspaceId, String conversationId) {
    _routeState = ConversationRouteState(
      workspaceId: workspaceId,
      conversationId: conversationId,
    );
    _notifyListeners();
  }

  void showCreatingWorkspace({required String requestLabel}) {
    _routeState = CreatingWorkspaceRouteState(requestLabel: requestLabel);
    _notifyListeners();
  }

  void confirmWorkspaceCreated({required String workspaceId}) {
    _routeState = WorkspaceSessionsRouteState(workspaceId: workspaceId);
    _notifyListeners();
  }

  void cancelWorkspaceCreation() {
    _routeState = const WorkspaceListRouteState();
    _notifyListeners();
  }

  Future<void> createWorkspaceAndOpen({
    required String path,
    String? name,
  }) async {
    showCreatingWorkspace(requestLabel: name ?? path);
    try {
      final created = await _workspaceRepository.create(path: path, name: name);
      _routeState = WorkspaceSessionsRouteState(workspaceId: created.id);
      _error = null;
    } catch (error) {
      _routeState = WorkspaceListRouteState(notice: error.toString());
      _error = error.toString();
    }
    _notifyListeners();
  }

  Future<void> openWorkspaceSessions(String workspaceId) async {
    if (_openingWorkspaceId != null) return;
    final workspace = _workspaceById(workspaceId);
    if (workspace == null) {
      _routeState = const WorkspaceListRouteState(
        notice: 'Workspace is no longer available.',
      );
      _notifyListeners();
      return;
    }
    final useCase = _workspaceOpeningUseCase;
    if (useCase == null) {
      final accepted = _workspaceRepository.select(workspaceId);
      _routeState = accepted
          ? WorkspaceSessionsRouteState(workspaceId: workspaceId)
          : const WorkspaceListRouteState(
              notice: 'Workspace is no longer available.',
            );
      _notifyListeners();
      return;
    }
    _openingWorkspaceId = workspaceId;
    _notifyListeners();
    try {
      final initialData = await useCase.open(
        workspaces: _workspaceRepository.workspaces,
        workspace: workspace,
      );
      final openedWorkspace = initialData.workspace;
      _routeState = openedWorkspace?.id == workspaceId
          ? WorkspaceSessionsRouteState(workspaceId: workspaceId)
          : const WorkspaceListRouteState(
              notice: 'Workspace is no longer available.',
            );
    } finally {
      _openingWorkspaceId = null;
      _notifyListeners();
    }
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
    if (notify) _notifyListeners();
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
    if (_optimisticSessions.containsKey(conversation.id)) {
      _optimisticSessions[conversation.id] = SessionItem(
        run: runSummaryFromConversation(conversation),
        conversation: conversation,
      );
    }
    if (conversationChanged) {
      _resetConversationModelUpdateState();
    }
    _selectActiveConversationAdapter(conversation);
    if (notify) _notifyListeners();
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
    if (changed && notify) _notifyListeners();
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
        _eventTraceEntries.isNotEmpty ||
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
    _oldestLoadedConversationSeq = null;
    _hasMoreHistoricalConversationEvents = false;
    _loadingOlderConversationEvents = false;
    _historicalConversationLoadError = null;
    _resolvedApprovalIds.clear();
    _eventTraceEntries.clear();
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
    if (changed && notify) _notifyListeners();
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
    if (notify) _notifyListeners();
  }

  void addUserMessage(String prompt,
      {bool includeDraftAttachments = false, bool notify = true}) {
    final attachments = includeDraftAttachments
        ? _draftAttachmentsForOptimisticMessage()
        : const <CommittedAttachment>[];
    _messages.add(WorkbenchMessage.user(prompt, attachments: attachments));
    if (notify) _notifyListeners();
  }

  void prepareNewConversationSend(
    ConversationSummary runningConversation, {
    required RunSummary run,
    bool notify = true,
  }) {
    updateActiveConversation(runningConversation, runId: run.id, notify: false);
    _lastSeq = 0;
    _resolvedApprovalIds.clear();
    if (notify) _notifyListeners();
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
    if (notify && _messages.length != before) _notifyListeners();
  }

  bool applyConversationEvents(
    List<ConversationEvent> events, {
    required bool streamOutput,
    bool notify = true,
  }) {
    final newEvents = events.where((event) => event.seq > _lastSeq).toList();
    if (newEvents.isEmpty) return false;
    final optimisticUserMessages = _messages
        .where((message) => message.role == 'user' && message.event == null)
        .toList(growable: false);
    newEvents.sort((a, b) => a.seq.compareTo(b.seq));
    for (final event in newEvents) {
      _conversationEvents.add(event);
      if (event.seq > _lastSeq) _lastSeq = event.seq;
      _applyConversationStatusEvent(event);
    }
    _conversationState =
        _conversationState.apply(newEvents, streamOutput: streamOutput);
    _rebuildMessagesFromConversationState();
    _restorePendingOptimisticUserMessages(optimisticUserMessages);
    if (notify) _notifyListeners();
    return true;
  }

  Future<bool> applyConversationEventsAsync(
    List<ConversationEvent> events, {
    required bool streamOutput,
    bool notify = true,
    WorkbenchEventApplicationIsCurrent? isCurrent,
  }) async {
    final stillCurrent = isCurrent ?? () => true;
    if (!stillCurrent()) return false;
    final changed = applyConversationEvents(
      events,
      streamOutput: streamOutput,
      notify: false,
    );
    if (!changed) return false;
    if (!stillCurrent()) {
      if (notify) _notifyListeners();
      return false;
    }
    final previewChanged = await _bindAndResolveAttachmentPreviews(
      events,
      isCurrent: stillCurrent,
    );
    if (!stillCurrent()) {
      if (notify) _notifyListeners();
      return false;
    }
    final hasChanged = changed || previewChanged;
    if (notify && hasChanged) _notifyListeners();
    return hasChanged;
  }

  List<ConversationEvent> _mergeConversationEventWindow(
    List<ConversationEvent> incoming,
  ) {
    final bySeq = <int, ConversationEvent>{
      for (final event in _conversationEvents) event.seq: event,
    };
    for (final event in incoming) {
      bySeq.putIfAbsent(event.seq, () => event);
    }
    final merged = bySeq.values.toList(growable: false)
      ..sort((left, right) => left.seq.compareTo(right.seq));
    return merged;
  }

  bool _replaceConversationEventWindow(
    List<ConversationEvent> events, {
    required bool streamOutput,
  }) {
    final sorted = events.toList(growable: false)
      ..sort((left, right) => left.seq.compareTo(right.seq));
    _conversationEvents
      ..clear()
      ..addAll(sorted);
    _lastSeq = sorted.isEmpty ? 0 : sorted.last.seq;
    _conversationState =
        const ConversationViewState().apply(sorted, streamOutput: streamOutput);
    _rebuildMessagesFromConversationState();
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
    if (notify) _notifyListeners();
  }

  void beginOperation({bool notify = true}) {
    _sending = true;
    _error = null;
    _errorTraceId = null;
    if (notify) _notifyListeners();
  }

  void finishOperation({bool notify = true}) {
    if (!_sending) return;
    _sending = false;
    if (notify) _notifyListeners();
  }

  void setOperationError(
    String message, {
    String? traceId,
    bool notify = true,
  }) {
    _error = message;
    _errorTraceId = traceId;
    if (notify) _notifyListeners();
  }

  void clearOperationError({bool notify = true}) {
    final changed = _error != null || _errorTraceId != null;
    _error = null;
    _errorTraceId = null;
    if (changed && notify) _notifyListeners();
  }

  void setSelectedAdapter(String? adapter) {
    if (_activeConversationId != null || _sending) return;
    if (_selectedAdapter == adapter) return;
    _selectedAdapter = adapter;
    _draftModel = _preferredModelFor(selectedAdapterStatus);
    _modelNotice = null;
    _revalidateDraftAttachments();
    _notifyListeners();
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
      _revalidateDraftAttachments();
      if (changed) _notifyListeners();
      return true;
    }

    if (_conversationModelUpdatesUnsupported) {
      _modelUpdateError = _unsupportedModelUpdateMessage;
      _notifyListeners();
      return false;
    }

    final repository = _requireConversationRepository();
    final modelUpdateGeneration = ++_modelUpdateGeneration;
    _modelUpdating = true;
    _modelUpdateError = null;
    _notifyListeners();
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
      _revalidateDraftAttachments();
      _notifyListeners();
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
        _modelUpdateError =
            message == null || message.isEmpty ? error.toString() : message;
      }
      _notifyListeners();
      return false;
    } catch (error) {
      if (!_isCurrentModelUpdate(modelUpdateGeneration, conversationId)) {
        return false;
      }
      _modelUpdating = false;
      _modelUpdateError = error.toString();
      _notifyListeners();
      return false;
    }
  }

  void clearModelNotice({bool notify = true}) {
    if (_modelNotice == null) return;
    _modelNotice = null;
    if (notify) _notifyListeners();
  }

  void updateAdapters(List<AdapterStatus> adapters, {bool notify = true}) {
    _applyAdapters(adapters);
    final activeConversation = _activeConversation;
    if (activeConversation != null) {
      _selectActiveConversationAdapter(activeConversation);
    } else if (!_selectedAdapterStillAvailable(adapters)) {
      _selectedAdapter = _computePreferredAdapter(adapters);
    }
    if (_activeConversationId == null) {
      _reconcileSelectedModel();
    }
    _revalidateDraftAttachments();
    if (notify) _notifyListeners();
  }

  void _applyAdapters(List<AdapterStatus> adapters) {
    _adapters = List<AdapterStatus>.unmodifiable(adapters);
  }

  void _selectActiveConversationAdapter(ConversationSummary? conversation) {
    _confirmedConversationModel = conversation?.model;
    _modelUpdateError = null;
    final adapter = conversation?.adapter.trim();
    if (adapter == null || adapter.isEmpty) return;
    _selectedAdapter = adapter;
    _revalidateDraftAttachments();
  }

  void addDraftAttachments(List<DraftAttachment> attachments) {
    if (attachments.isEmpty) return;
    _resetAttachmentClientMessageId(orphanPending: true);
    _draftAttachments.addAll(attachments);
    if (_draftAttachments.length > _maxDraftAttachments) {
      _draftAttachments.removeRange(
        _maxDraftAttachments,
        _draftAttachments.length,
      );
    }
    _revalidateDraftAttachments();
    _notifyListeners();
  }

  @visibleForTesting
  void addDraftAttachmentForTest(DraftAttachment attachment) {
    addDraftAttachments(<DraftAttachment>[attachment]);
  }

  void removeDraftAttachment(int index) {
    if (index < 0 || index >= _draftAttachments.length) return;
    _resetAttachmentClientMessageId(orphanPending: true);
    _draftAttachments.removeAt(index);
    _revalidateDraftAttachments();
    _notifyListeners();
  }

  bool canSendComposer({required String text}) {
    if (_sending) return false;
    final hasText = text.trim().isNotEmpty;
    final hasAttachment = _draftAttachments.any((item) => item.isValid);
    final hasError = _draftAttachments.any((item) => !item.isValid);
    return !hasError && (hasText || hasAttachment);
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
      !_disposed &&
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
    _notifyListeners();
    return WorkbenchNewConversationSendResult(
      conversation: conversation,
      runningConversation: runningConversation,
      run: runSummaryFromConversation(conversation),
      updatedConversation: _sendConversationMessageWithDrafts(
        repository,
        conversation.id,
        prompt,
      ),
    );
  }

  Future<ConversationSummary> sendExistingConversationPrompt({
    required String conversationId,
    required String prompt,
  }) {
    final repository = _requireConversationRepository();
    return _sendConversationMessageWithDrafts(
      repository,
      conversationId,
      prompt,
    );
  }

  Future<ConversationSummary> _sendConversationMessageWithDrafts(
    ConversationRepository repository,
    String conversationId,
    String prompt,
  ) async {
    final request =
        await _buildConversationMessageRequest(conversationId, prompt);
    try {
      final conversation =
          await repository.sendConversationMessage(conversationId, request);
      if (request.attachments.isNotEmpty) {
        _draftAttachments.clear();
        _clearAttachmentClientMessageId();
      }
      return conversation;
    } on ConversationRepositoryException catch (error) {
      if (request.attachments.isNotEmpty &&
          !_keepsAttachmentClientMessageId(error)) {
        _resetAttachmentClientMessageId(orphanPending: true);
      }
      rethrow;
    }
  }

  Future<ConversationMessageSendRequest> _buildConversationMessageRequest(
    String conversationId,
    String prompt,
  ) async {
    final attachments = _draftAttachments
        .where((item) => item.isValid)
        .map((item) => ConversationMessageAttachment(
              localPath: item.localPath,
              name: item.name,
              mimeType: item.mimeType,
              kind: item.kind,
              sizeBytes: item.sizeBytes,
            ))
        .toList(growable: false);
    if (attachments.isEmpty) {
      return ConversationMessageSendRequest(text: prompt);
    }
    if (_currentAttachmentConversationId != null &&
        _currentAttachmentConversationId != conversationId) {
      _resetAttachmentClientMessageId(orphanPending: true);
    }
    _currentAttachmentClientMessageId ??= _generateUuidV4();
    _currentAttachmentConversationId = conversationId;
    final clientMessageId = _currentAttachmentClientMessageId!;
    final pendingIdentities = <AttachmentPreviewIdentity>[];
    for (var index = 0; index < _draftAttachments.length; index += 1) {
      final draft = _draftAttachments[index];
      if (!draft.isValid || draft.kind != AttachmentKind.image) continue;
      try {
        final identity = await _attachmentPreviewCache.rememberPending(
          conversationId: conversationId,
          clientMessageId: clientMessageId,
          attachmentIndex: index,
          draft: draft,
        );
        pendingIdentities.add(identity);
      } catch (_) {
        // Preview cache failures must not block sending the message.
      }
    }
    if (pendingIdentities.isNotEmpty) {
      _pendingAttachmentPreviewIdentities[
              _pendingAttachmentPreviewKey(conversationId, clientMessageId)] =
          List.unmodifiable(pendingIdentities);
    }
    return ConversationMessageSendRequest(
      text: prompt,
      clientMessageId: clientMessageId,
      capabilityVersion: selectedAdapterStatus?.capabilityVersion,
      attachments: attachments,
    );
  }

  List<CommittedAttachment> _draftAttachmentsForOptimisticMessage() {
    final attachments = <CommittedAttachment>[];
    for (var i = 0; i < _draftAttachments.length; i++) {
      final item = _draftAttachments[i];
      if (!item.isValid) continue;
      attachments.add(CommittedAttachment(
        id: 'draft_$i',
        name: item.name,
        kind: item.kind,
        mimeType: item.mimeType,
        sizeBytes: item.sizeBytes,
        handling: _draftAttachmentHandling(item.kind),
        localPath: item.localPath,
      ));
    }
    return List.unmodifiable(attachments);
  }

  Future<bool> _bindAndResolveAttachmentPreviews(
    Iterable<ConversationEvent> events, {
    required WorkbenchEventApplicationIsCurrent isCurrent,
  }) async {
    var previewChanged = false;
    final activeConversationId = _activeConversationId;
    for (final event in events) {
      if (!isCurrent()) return false;
      if (event.type != 'user.message' || event.attachments.isEmpty) continue;
      final clientMessageId = event.raw['clientMessageId'] as String?;
      if (clientMessageId == null || clientMessageId.isEmpty) continue;
      final pendingKey = _pendingAttachmentPreviewKey(
        event.conversationId,
        clientMessageId,
      );
      try {
        await _attachmentPreviewCache.bindCommitted(
          conversationId: event.conversationId,
          clientMessageId: clientMessageId,
          attachments: event.attachments,
          pendingIdentities: _pendingAttachmentPreviewIdentities[pendingKey],
        );
        if (!isCurrent()) return false;
        previewChanged = true;
      } catch (_) {
        // Cache binding is best-effort; event projection should still proceed.
      } finally {
        if (isCurrent()) {
          _pendingAttachmentPreviewIdentities.remove(pendingKey);
        }
      }
    }
    if (!isCurrent()) return false;
    if (activeConversationId == null) return previewChanged;

    final resolvedMessages = <WorkbenchMessage>[];
    for (final message in _messages) {
      if (!isCurrent()) return false;
      if (message.role != 'user' || message.attachments.isEmpty) {
        resolvedMessages.add(message);
        continue;
      }
      final attachments = <CommittedAttachment>[];
      for (final attachment in message.attachments) {
        if (attachment.kind != AttachmentKind.image ||
            attachment.id.startsWith('draft_')) {
          attachments.add(attachment);
          continue;
        }
        CachedAttachmentPreview? cached;
        try {
          cached = await _attachmentPreviewCache.resolve(
            conversationId: activeConversationId,
            attachment: attachment,
          );
        } catch (_) {
          cached = null;
        }
        if (!isCurrent()) return false;
        attachments.add(cached == null
            ? attachment
            : attachment.copyWith(localPath: cached.cachePath));
      }
      resolvedMessages.add(message.copyWith(attachments: attachments));
    }
    if (_sameWorkbenchAttachmentPaths(_messages, resolvedMessages)) {
      return previewChanged;
    }
    if (!isCurrent()) return false;
    _messages
      ..clear()
      ..addAll(resolvedMessages);
    return true;
  }

  bool _sameWorkbenchAttachmentPaths(
    List<WorkbenchMessage> left,
    List<WorkbenchMessage> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i += 1) {
      final leftAttachments = left[i].attachments;
      final rightAttachments = right[i].attachments;
      if (leftAttachments.length != rightAttachments.length) return false;
      for (var j = 0; j < leftAttachments.length; j += 1) {
        if (leftAttachments[j].localPath != rightAttachments[j].localPath) {
          return false;
        }
      }
    }
    return true;
  }

  String _pendingAttachmentPreviewKey(
    String conversationId,
    String clientMessageId,
  ) =>
      '$conversationId|$clientMessageId';

  void _resetAttachmentClientMessageId({required bool orphanPending}) {
    final clientMessageId = _currentAttachmentClientMessageId;
    final conversationId = _currentAttachmentConversationId;
    _clearAttachmentClientMessageId();
    if (clientMessageId == null || conversationId == null) return;
    _pendingAttachmentPreviewIdentities.remove(
      _pendingAttachmentPreviewKey(conversationId, clientMessageId),
    );
    if (orphanPending) {
      unawaited(_markAttachmentClientMessageOrphanedBestEffort(
        conversationId: conversationId,
        clientMessageId: clientMessageId,
      ));
    }
  }

  void _clearAttachmentClientMessageId() {
    _currentAttachmentClientMessageId = null;
    _currentAttachmentConversationId = null;
  }

  Future<void> _markAttachmentClientMessageOrphanedBestEffort({
    required String conversationId,
    required String clientMessageId,
  }) async {
    try {
      await _attachmentPreviewCache.markClientMessageOrphaned(
        conversationId: conversationId,
        clientMessageId: clientMessageId,
      );
    } catch (_) {
      // Preview cache cleanup is best-effort and must not block editing drafts.
    }
  }

  AttachmentHandling _draftAttachmentHandling(AttachmentKind kind) {
    final capabilities = _selectedAttachmentCapabilities();
    return switch (kind) {
      AttachmentKind.image => capabilities.image,
      AttachmentKind.textDocument => capabilities.textDocument,
      AttachmentKind.pdf => capabilities.pdf,
      AttachmentKind.unsupported => AttachmentHandling.unsupported,
    };
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

  Future<bool> loadInitialConversationEventPage({
    required String conversationId,
    required int limit,
    required bool streamOutput,
    WorkbenchEventApplicationIsCurrent? isCurrent,
  }) async {
    final stillCurrent = isCurrent ?? () => true;
    if (!stillCurrent()) return false;
    final page = await _requireConversationRepository()
        .fetchConversationEventPage(conversationId, limit: limit);
    if (!stillCurrent()) return false;
    _oldestLoadedConversationSeq =
        page.oldestSeq ?? (page.events.isEmpty ? null : page.events.first.seq);
    _hasMoreHistoricalConversationEvents = page.hasMoreBefore;
    _historicalConversationLoadError = null;
    _replaceConversationEventWindow(page.events, streamOutput: streamOutput);
    _notifyListeners();
    final previewChanged = await _bindAndResolveAttachmentPreviews(
      page.events,
      isCurrent: stillCurrent,
    );
    if (!stillCurrent()) return false;
    if (previewChanged) {
      _rebuildMessagesFromConversationState();
      _notifyListeners();
    }
    return page.events.isNotEmpty || previewChanged;
  }

  Future<bool> loadOlderConversationEventPage({
    required String conversationId,
    required int limit,
    required bool streamOutput,
    WorkbenchEventApplicationIsCurrent? isCurrent,
  }) async {
    final beforeSeq = _oldestLoadedConversationSeq;
    if (beforeSeq == null ||
        !_hasMoreHistoricalConversationEvents ||
        _loadingOlderConversationEvents) {
      return false;
    }
    final stillCurrent = isCurrent ?? () => true;
    _loadingOlderConversationEvents = true;
    _historicalConversationLoadError = null;
    _notifyListeners();
    try {
      final page =
          await _requireConversationRepository().fetchConversationEventPage(
        conversationId,
        beforeSeq: beforeSeq,
        limit: limit,
      );
      if (!stillCurrent()) return false;
      if (page.events.isEmpty) {
        _hasMoreHistoricalConversationEvents = false;
        _loadingOlderConversationEvents = false;
        _notifyListeners();
        return false;
      }
      _oldestLoadedConversationSeq = page.oldestSeq ?? page.events.first.seq;
      _hasMoreHistoricalConversationEvents = page.hasMoreBefore;
      _replaceConversationEventWindow(
        _mergeConversationEventWindow(page.events),
        streamOutput: streamOutput,
      );
      _loadingOlderConversationEvents = false;
      _notifyListeners();
      final previewChanged = await _bindAndResolveAttachmentPreviews(
        page.events,
        isCurrent: stillCurrent,
      );
      if (!stillCurrent()) return false;
      if (previewChanged) {
        _rebuildMessagesFromConversationState();
        _notifyListeners();
      }
      return true;
    } catch (error) {
      if (stillCurrent()) _historicalConversationLoadError = error;
      rethrow;
    } finally {
      if (stillCurrent() && _loadingOlderConversationEvents) {
        _loadingOlderConversationEvents = false;
        _notifyListeners();
      }
    }
  }

  Stream<ConversationEvent> watchConversationEvents({
    required String conversationId,
    required int afterSeq,
  }) =>
      _requireConversationRepository().watchConversationEvents(
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

  Future<void> recordEventTrace(WorkbenchEventTraceEntry entry) async {
    _eventTraceEntries.add(entry);
    if (_eventTraceEntries.length > _maxEventTraceEntries) {
      _eventTraceEntries.removeRange(
          0, _eventTraceEntries.length - _maxEventTraceEntries);
    }
    final repository = _diagnosticsRepository;
    if (repository == null) return;
    try {
      await repository.recordException(
        message: entry.message,
        severity: entry.isError ? 'error' : 'info',
        path: entry.path,
        method: 'GET',
        conversationId: entry.conversationId,
        runId: entry.runId,
        metadata: entry.toMetadata(),
      );
    } catch (_) {
      // Event tracing must never interfere with the notification stream.
    }
  }

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

  void _restorePendingOptimisticUserMessages(
      List<WorkbenchMessage> optimisticUserMessages) {
    for (final message in optimisticUserMessages) {
      final committedIndex = _messages.indexWhere(
          (item) => item.role == 'user' && item.body == message.body);
      if (committedIndex >= 0) {
        final committed = _messages[committedIndex];
        if (committed.attachments.isEmpty && message.attachments.isNotEmpty) {
          _messages[committedIndex] = message;
        } else if (committed.attachments.isNotEmpty &&
            message.attachments.isNotEmpty) {
          _messages[committedIndex] = committed.copyWith(
            attachments: _mergeOptimisticAttachmentLocalPaths(
              committed.attachments,
              message.attachments,
            ),
          );
        }
      } else {
        _messages.add(message);
      }
    }
  }

  List<CommittedAttachment> _mergeOptimisticAttachmentLocalPaths(
    List<CommittedAttachment> committed,
    List<CommittedAttachment> optimistic,
  ) {
    final usedOptimisticIndexes = <int>{};
    return committed.map((attachment) {
      if (attachment.localPath != null) return attachment;
      final matchIndex = _findOptimisticAttachmentMatch(
        attachment,
        optimistic,
        usedOptimisticIndexes,
      );
      if (matchIndex == -1) return attachment;
      usedOptimisticIndexes.add(matchIndex);
      return attachment.copyWith(localPath: optimistic[matchIndex].localPath);
    }).toList(growable: false);
  }

  int _findOptimisticAttachmentMatch(
    CommittedAttachment attachment,
    List<CommittedAttachment> optimistic,
    Set<int> usedIndexes,
  ) {
    for (var index = 0; index < optimistic.length; index += 1) {
      if (usedIndexes.contains(index)) continue;
      final candidate = optimistic[index];
      if (candidate.localPath == null) continue;
      if (candidate.kind == attachment.kind &&
          candidate.name == attachment.name &&
          candidate.sizeBytes == attachment.sizeBytes &&
          _compatibleAttachmentMimeType(
            candidate.mimeType,
            attachment.mimeType,
            attachment.kind,
          )) {
        return index;
      }
    }
    return -1;
  }

  bool _compatibleAttachmentMimeType(
    String left,
    String right,
    AttachmentKind kind,
  ) {
    final normalizedLeft = _normalizeMimeType(left);
    final normalizedRight = _normalizeMimeType(right);
    if (normalizedLeft == normalizedRight) return true;
    return kind == AttachmentKind.image &&
        _isImageMimeType(normalizedLeft) &&
        _isImageMimeType(normalizedRight);
  }

  String _normalizeMimeType(String value) =>
      value.split(';').first.trim().toLowerCase();

  bool _isImageMimeType(String value) => value.startsWith('image/');

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
        client: _workspaceRepository,
        timeout: _workspaceCreationTimeout,
      ).create(path: path, name: name);

  ConversationRepository _requireConversationRepository() {
    return _conversationRepository;
  }

  DiagnosticsRepository _requireDiagnosticsRepository() {
    final repository = _diagnosticsRepository;
    if (repository == null) {
      throw StateError(
          'DiagnosticsRepository is required for exception tracing.');
    }
    return repository;
  }

  RunRepository _requireRunRepository() {
    return _runRepository;
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

  void _revalidateDraftAttachments() {
    if (_draftAttachments.isEmpty) return;
    final capabilities = _selectedAttachmentCapabilities();
    final imageLimit = _selectedAdapter == 'claude'
        ? _claudeImageBytesLimit
        : _defaultImageBytesLimit;
    final totalBytes =
        _draftAttachments.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    for (var i = 0; i < _draftAttachments.length; i++) {
      final attachment = _draftAttachments[i];
      final validation = _validateDraftAttachment(
        attachment,
        capabilities: capabilities,
        imageLimit: imageLimit,
        totalBytes: totalBytes,
      );
      _draftAttachments[i] = attachment.copyWith(
        errorCode: validation.$1,
        errorMessage: validation.$2,
      );
    }
  }

  (String?, String?) _validateDraftAttachment(
    DraftAttachment attachment, {
    required AttachmentCapabilities capabilities,
    required int imageLimit,
    required int totalBytes,
  }) {
    if (attachment.sizeBytes < 1) {
      return ('attachment_empty', 'This file is empty.');
    }
    if (totalBytes > _totalMultipartBytesLimit) {
      return ('attachment_total_too_large', 'Selected files are too large.');
    }
    switch (attachment.kind) {
      case AttachmentKind.image:
        if (capabilities.image != AttachmentHandling.native) {
          return (
            'attachment_kind_unsupported',
            'This file is not supported by the selected model.'
          );
        }
        if (attachment.sizeBytes > imageLimit) {
          return ('attachment_too_large', 'This image is too large.');
        }
      case AttachmentKind.textDocument:
        if (capabilities.textDocument != AttachmentHandling.native &&
            capabilities.textDocument != AttachmentHandling.textExtract) {
          return (
            'attachment_kind_unsupported',
            'This file is not supported by the selected model.'
          );
        }
        if (attachment.sizeBytes > _textDocumentBytesLimit) {
          return ('attachment_too_large', 'This document is too large.');
        }
      case AttachmentKind.pdf:
        if (capabilities.pdf == AttachmentHandling.unsupported) {
          return (
            'attachment_kind_unsupported',
            'This file is not supported by the selected model.'
          );
        }
      case AttachmentKind.unsupported:
        return (
          'attachment_kind_unsupported',
          'This file is not supported by the selected model.'
        );
    }
    return (null, null);
  }

  AttachmentCapabilities _selectedAttachmentCapabilities() {
    final status = selectedAdapterStatus;
    if (status == null) return const AttachmentCapabilities();
    final selected = selectedModel;
    if (selected == null) return status.attachmentCapabilities;
    for (final model in status.models) {
      if (model.id == selected) {
        return model.attachmentCapabilities;
      }
    }
    return status.attachmentCapabilities;
  }

  static bool _keepsAttachmentClientMessageId(
    ConversationRepositoryException error,
  ) {
    if (error.statusCode == 413 ||
        error.statusCode == 415 ||
        error.statusCode == 422 ||
        error.statusCode == 429) {
      return true;
    }
    if (error.statusCode != 409) return false;
    return error.code == 'capability_stale' ||
        error.code == 'message_already_in_flight';
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
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
        title: conversation.title,
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
