import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../domain/repositories/conversation_repository.dart';
import '../../../models/protocol.dart';
import '../../../services/asr_model_manager.dart';
import '../../../shell/shell.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';
import '../../../workflows/workspace/create_workspace_workflow.dart'
    show
        CreateWorkspaceFailure,
        CreateWorkspaceNotConfirmed,
        CreateWorkspaceSuccess,
        CreateWorkspaceTimeout;
import 'attachments/attachment_picker.dart';
import 'coding_composer.dart';
import 'voice_input.dart';
import 'workbench_event_cards.dart';
import 'workbench_messages.dart';
import '../sessions/sessions.dart';
import '../workspace_picker/workspace_picker.dart';
import 'coding_workbench_controller.dart';
import 'view_models/workbench_view_model.dart';
import 'workbench_dependencies.dart';

class CodingWorkbenchPage extends StatefulWidget {
  const CodingWorkbenchPage({
    super.key,
    required this.data,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.streamOutput,
    required this.expandThinking,
    required this.permissionMode,
    required this.dependencies,
    this.speechInputService,
  });
  final AppSnapshot data;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;
  final SpeechInputService? speechInputService;
  final WorkbenchDependencies dependencies;

  @override
  State<CodingWorkbenchPage> createState() => CodingWorkbenchPageState();
}

class CodingWorkbenchPageState extends State<CodingWorkbenchPage>
    with WidgetsBindingObserver {
  static const String _routeWorkspaces = 'workspaces';
  static const String _routeSessions = 'sessions';
  static const String _routeConversation = 'conversation';
  static const int _conversationTitleMaxLength = 18;

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _prompt = TextEditingController();
  final _scrollController = ScrollController();
  late final VoiceInputViewModel _voiceInput;
  late final AsrModelManager _asrModelManager;
  late final WorkbenchAttachmentPicker _attachmentPicker;
  SpeechInputService? _ownedSpeechInputService;
  late final WorkbenchViewModel _workbenchViewModel;
  StreamSubscription<void>? _conversationEventSubscription;
  int _conversationEventSubscriptionGeneration = 0;
  String? _lastVoiceErrorNotice;
  bool _voiceErrorDialogOpen = false;
  bool _applyingVoiceText = false;
  String _currentRoute = _routeWorkspaces;
  bool? _lastReportedListOpen = true;
  late int _handledOpenSessionListRequest;
  bool _bottomAnchorTranscript = false;
  bool _bottomAnchorTranscriptUnderflow = false;

  List<SessionItem> get _sessionItems => _workbenchViewModel.sessionItems(
      widget.data.conversations, widget.data.runs);

  List<WorkspaceSummary> get _workspaces => _workbenchViewModel.workspaces;

  WorkspaceSummary? get _routeWorkspace => _workbenchViewModel.routeWorkspace;
  String? get _activeRunId => _workbenchViewModel.activeRunId;
  String? get _activeConversationId => _workbenchViewModel.activeConversationId;
  ConversationSummary? get _activeConversation =>
      _workbenchViewModel.activeConversation;
  List<WorkbenchMessage> get _messages => _workbenchViewModel.messages;
  List<ConversationEvent> get _conversationEvents =>
      _workbenchViewModel.conversationEvents;
  bool get _sending => _workbenchViewModel.sending;
  String? get _error => _workbenchViewModel.error;
  String? get _errorTraceId => _workbenchViewModel.errorTraceId;
  bool get _useReverseTranscript =>
      _bottomAnchorTranscript && !_bottomAnchorTranscriptUnderflow;

  Future<bool> handleSystemBack() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    return navigator.maybePop<void>();
  }

  void showSessionListFromShell() {
    _goToWorkspaces();
  }

  void _setCurrentRoute(String route) {
    if (_currentRoute != route) {
      setState(() => _currentRoute = route);
    }
    if (route != _routeConversation && _voiceInput.isBusy) {
      unawaited(_cancelVoiceInput());
    }
    final listOpen = route != _routeConversation;
    if (_lastReportedListOpen == listOpen) return;
    _lastReportedListOpen = listOpen;
    widget.onSessionListChanged(listOpen);
  }

  void _goToWorkspaces() {
    unawaited(_cancelConversationEventSubscription());
    _navigatorKey.currentState
        ?.pushNamedAndRemoveUntil(_routeWorkspaces, (route) => false);
  }

  void _openWorkspaceList() {
    if (_isRunningCli) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('CLI is running; workspace cannot be switched right now'),
          duration: Duration(seconds: 2)));
      return;
    }
    _goToWorkspaces();
  }

  void _returnToWorkspaceList() {
    _goToWorkspaces();
  }

  void _openWorkspaceSessions(WorkspaceSummary workspace) {
    _goToSessions(workspace);
  }

  void _goToSessions(WorkspaceSummary workspace) {
    unawaited(_cancelConversationEventSubscription());
    _workbenchViewModel.showSessions(workspace);
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        _routeSessions, (route) => route.settings.name == _routeWorkspaces);
  }

  void _goToConversation() {
    final workspace = _routeWorkspace;
    if (workspace != null &&
        _workbenchViewModel.routeState is! ConversationRouteState) {
      _workbenchViewModel.showConversation(workspace);
    }
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        _routeConversation, (route) => route.settings.name == _routeSessions);
  }

  void _resetConversationState({bool bottomAnchorTranscript = false}) {
    unawaited(_cancelConversationEventSubscription());
    _bottomAnchorTranscript = bottomAnchorTranscript;
    _bottomAnchorTranscriptUnderflow = false;
    _workbenchViewModel.resetConversationDisplay(notify: false);
  }

  Future<void> _openSession(SessionItem item) async {
    await _cancelConversationEventSubscription();
    setState(() {
      _resetConversationState(
          bottomAnchorTranscript: item.conversation != null);
      _workbenchViewModel.openSession(item, notify: false);
      _workbenchViewModel.clearOperationError(notify: false);
    });
    _workbenchViewModel.showConversation(_workspaceForId(item.run.workspaceId));
    if (item.conversation != null) {
      await _restartConversationEventSubscription();
    }
    if (!mounted) return;
    _goToConversation();
    _scrollToBottom(jump: true);
  }

  WorkspaceSummary _workspaceForId(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return _routeWorkspace ?? widget.data.workspace;
  }

  Future<void> _cancelActiveRun() async {
    final runId = _activeRunId;
    final conversationId = _activeConversationId;
    if ((runId == null && conversationId == null) || _sending) return;
    _workbenchViewModel.beginOperation();
    try {
      final result = await _workbenchViewModel.cancelActiveRun(
        conversationId: conversationId,
        runId: runId,
      );
      final run = result.run;
      final conversation = result.conversation;
      if (!mounted) return;
      setState(() {
        _workbenchViewModel.setCancelledConversationDisplayStatus(conversation,
            run: run, notify: false);
      });
      await _cancelConversationEventSubscription();
    } catch (err) {
      if (mounted) _workbenchViewModel.setOperationError(err.toString());
    } finally {
      if (mounted) _workbenchViewModel.finishOperation();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    _workbenchViewModel = WorkbenchViewModel(
      initialData: widget.data,
      conversationRepository: widget.dependencies.conversationRepository,
      diagnosticsRepository: widget.dependencies.diagnosticsRepository,
      runRepository: widget.dependencies.runRepository,
      workspaceRepository: widget.dependencies.workspaceRepository,
      attachmentPreviewCache: widget.dependencies.attachmentPreviewCache,
    )..addListener(_syncWorkbenchViewModel);
    _attachmentPicker = const WorkbenchAttachmentPicker();
    _asrModelManager = widget.dependencies.asrModelManager;
    _voiceInput = VoiceInputViewModel(service: _createSpeechInputService())
      ..addListener(_syncVoicePreviewText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setCurrentRoute(_routeWorkspaces);
    });
  }

  @override
  void didUpdateWidget(covariant CodingWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _workbenchViewModel.updateFromSnapshot(widget.data);
    if (widget.openSessionListRequest == _handledOpenSessionListRequest) return;
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showSessionListFromShell();
    });
  }

  void _syncWorkbenchViewModel() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conversationEventSubscriptionGeneration += 1;
    unawaited(_conversationEventSubscription?.cancel());
    if (_voiceInput.isBusy) unawaited(_voiceInput.cancel());
    _voiceInput.removeListener(_syncVoicePreviewText);
    _voiceInput.dispose();
    _workbenchViewModel.removeListener(_syncWorkbenchViewModel);
    _workbenchViewModel.dispose();
    _ownedSpeechInputService = null;
    _scrollController.dispose();
    _prompt.dispose();
    super.dispose();
  }

  SpeechInputService _createSpeechInputService() {
    final injected = widget.speechInputService;
    if (injected != null) return injected;
    final owned = _ownedSpeechInputService;
    if (owned != null) return owned;
    return const DisabledSpeechInputService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed && _voiceInput.isBusy) {
      unawaited(_cancelVoiceInput());
    }
  }

  void _syncVoicePreviewText() {
    if (!mounted) return;
    if (_voiceInput.state == VoiceInputState.listening) {
      final preview = _voiceInput.previewValue();
      if (preview.text != _prompt.text ||
          preview.selection != _prompt.selection) {
        _applyingVoiceText = true;
        _prompt.value = preview;
        _applyingVoiceText = false;
      }
    }
    final voiceError = _voiceInput.error;
    if (_voiceInput.state == VoiceInputState.failed &&
        voiceError != null &&
        voiceError != _lastVoiceErrorNotice) {
      _lastVoiceErrorNotice = voiceError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showVoiceErrorDialog(voiceError);
      });
    } else if (_voiceInput.state != VoiceInputState.failed) {
      _lastVoiceErrorNotice = null;
    }
    setState(() {});
  }

  Future<void> _showVoiceErrorDialog(String message) async {
    if (_voiceErrorDialogOpen) return;
    _voiceErrorDialogOpen = true;
    await showDialog<void>(
        context: context,
        builder: (context) => _VoiceInputErrorDialog(message: message));
    _voiceErrorDialogOpen = false;
  }

  Future<void> _startVoiceInput() async {
    if (widget.speechInputService == null && _ownedSpeechInputService == null) {
      final readyState = _asrModelManager.state;
      final modelDirectory = readyState.status == AsrModelStatus.ready
          ? readyState.modelDirectory
          : await _showAsrDownloadDialog();
      if (modelDirectory == null || !mounted) return;
      final nextService =
          widget.dependencies.speechInputServiceBuilder(modelDirectory);
      _ownedSpeechInputService = nextService;
      _voiceInput.updateService(nextService);
    }
    await _voiceInput.startValue(currentPrompt: _prompt.value);
  }

  Future<String?> _showAsrDownloadDialog() {
    return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _AsrModelDownloadDialog(manager: _asrModelManager));
  }

  Future<void> _stopVoiceInput() async {
    final merged = await _voiceInput.stopValue(currentPrompt: _prompt.value);
    if (!mounted) return;
    _applyingVoiceText = true;
    _prompt.value = merged;
    _applyingVoiceText = false;
    setState(() {});
  }

  Future<void> _cancelVoiceInput() async {
    await _voiceInput.cancel();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _finishVoiceInputForTextEdit() async {
    if (_applyingVoiceText || !_voiceInput.isBusy) return;
    await _voiceInput.cancelIfBusy();
    if (mounted) setState(() {});
  }

  void _handleComposerTextChanged(String text) {
    unawaited(_finishVoiceInputForTextEdit());
    if (mounted) setState(() {});
  }

  Future<void> _finishVoiceInputForSend() async {
    final merged =
        await _voiceInput.finishForSendValue(currentPrompt: _prompt.value);
    if (merged != null && mounted) {
      _applyingVoiceText = true;
      _prompt.value = merged;
      _applyingVoiceText = false;
      setState(() {});
    } else if (mounted) {
      setState(() {});
    }
  }

  bool get _isTerminal {
    return _workbenchViewModel.isTerminalConversation;
  }

  bool get _isRunningCli =>
      _activeConversationId != null &&
      _workbenchViewModel.effectiveConversationStatus == 'running';

  bool get _isBusyCli =>
      _isRunningCli ||
      (_activeConversationId != null &&
          _workbenchViewModel.effectiveConversationStatus == 'sending');

  bool get _isConversationAdapterLocked =>
      _activeConversationId != null || _sending;

  bool get _isModelSelectionLocked {
    if (_sending || _workbenchViewModel.modelUpdating) return true;
    if (_activeConversationId == null) return false;
    return isActiveConversationStatus(
        _workbenchViewModel.effectiveConversationStatus);
  }

  bool get _isModelSelectionDisabled =>
      _activeConversationId != null &&
      _workbenchViewModel.conversationModelUpdatesUnsupported;

  List<AdapterStatus> get _availableAdapters => widget.data.adapters
      .where((adapter) => adapter.available && _isSelectableCliAdapter(adapter))
      .toList();

  void _showAdapterPicker() {
    final adapters = _availableAdapters;
    if (adapters.isEmpty || _isConversationAdapterLocked) return;
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AdapterPickerSheet(
            adapters: adapters,
            selected: _workbenchViewModel.selectedAdapter,
            onSelected: (adapter) {
              _workbenchViewModel.setSelectedAdapter(adapter);
              Navigator.of(context).pop();
            }));
  }

  void _showModelPicker() {
    if (_isModelSelectionLocked) return;
    _workbenchViewModel.clearModelNotice();
    final status = _workbenchViewModel.selectedAdapterStatus;
    final models = status?.canSelectModel == true
        ? _workbenchViewModel.availableModels
        : const <AdapterModelOption>[];
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => AnimatedBuilder(
            animation: _workbenchViewModel,
            builder: (context, _) {
              return ModelPickerSheet(
                  models: models,
                  selected: _workbenchViewModel.selectedModel,
                  updating: _workbenchViewModel.modelUpdating,
                  selectionDisabled: _isModelSelectionDisabled,
                  pendingModel: null,
                  errorText: _modelUpdateErrorLabel(context),
                  onSelected: (model) =>
                      unawaited(_selectModelFromPicker(sheetContext, model)));
            }));
  }

  Future<void> _selectModelFromPicker(
      BuildContext sheetContext, String? model) async {
    final changed = await _workbenchViewModel.selectModel(model);
    if (!mounted) return;
    if (changed && sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }
  }

  void _showWorkspacePicker() => _openWorkspaceList();

  Future<void> _pickAttachments() async {
    if (_isRunningCli || _sending) return;
    final attachments = await _attachmentPicker.pickAttachments();
    if (!mounted || attachments.isEmpty) return;
    _workbenchViewModel.addDraftAttachments(attachments);
  }

  Future<void> _refreshAdapterCapabilities() async {
    final adapters = await widget.dependencies.adapterRepository.listAdapters();
    if (!mounted) return;
    _workbenchViewModel.updateAdapters(adapters);
  }

  Future<void> _showCreateWorkspaceFromWorkspaceList() async {
    final request = await showModalBottomSheet<WorkspaceCreationRequest>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AddWorkspaceSheet(
              workspaceRepository: widget.dependencies.workspaceRepository,
            ));
    if (request == null || !mounted) return;
    final previousWorkspaces = List<WorkspaceSummary>.of(_workspaces);
    _workbenchViewModel.showCreatingWorkspace(
        requestLabel: request.name ?? request.path);
    setState(() {
      _resetConversationState();
      _workbenchViewModel.clearOperationError(notify: false);
    });
    _navigatorKey.currentState
        ?.pushNamedAndRemoveUntil(_routeWorkspaces, (route) => false);

    final outcome = await _workbenchViewModel.createWorkspace(
      path: request.path,
      name: request.name,
    );
    if (!mounted) return;

    switch (outcome) {
      case CreateWorkspaceSuccess(:final workspace, :final workspaces):
        _workbenchViewModel.confirmWorkspaceCreated(
          workspace: workspace,
          workspaces: workspaces,
        );
        setState(() {
          _resetConversationState();
          _workbenchViewModel.clearOperationError(notify: false);
        });
        _goToSessions(workspace);
      case CreateWorkspaceNotConfirmed(:final workspaces):
        _workbenchViewModel.cancelWorkspaceCreation(workspaces);
        setState(() {
          _workbenchViewModel.clearOperationError(notify: false);
        });
        await _showWorkspaceCreationDialog(
          title: 'Workspace not ready',
          message:
              'The workspace was created, but the daemon did not include it in the refreshed list yet.',
        );
      case CreateWorkspaceTimeout():
        _workbenchViewModel.cancelWorkspaceCreation(previousWorkspaces);
        setState(() {
          _workbenchViewModel.clearOperationError(notify: false);
        });
        await _showWorkspaceCreationDialog(
          title: 'Workspace creation timed out',
          message: 'The daemon did not finish creating the workspace in time.',
        );
      case CreateWorkspaceFailure(:final error):
        _workbenchViewModel.cancelWorkspaceCreation(previousWorkspaces);
        setState(() {
          _workbenchViewModel.setOperationError(error.toString(),
              notify: false);
        });
        await _showWorkspaceCreationDialog(
          title: 'Workspace creation failed',
          message: error.toString(),
        );
    }
  }

  Future<void> _showWorkspaceCreationDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK')),
              ],
            ));
  }

  String _pendingStatusText(AppLocalizations l10n) =>
      conversationPendingStatusText(l10n,
          _workbenchViewModel.effectiveConversationStatus, _conversationEvents);

  void _applyConversationSendAcknowledgement(
    ConversationSummary conversation, {
    required int sendStartSeq,
  }) {
    if (_activeConversationId != conversation.id) return;
    final shouldApply = shouldApplyConversationSendAcknowledgement(
      sendStartSeq: sendStartSeq,
      currentSeq: _workbenchViewModel.lastSeq,
      acknowledgementStatus: conversation.status,
      reducerStatus: _workbenchViewModel.conversationState.status,
    );
    if (!shouldApply) return;
    _workbenchViewModel.updateActiveConversation(conversation, notify: false);
  }

  List<String> get _recentActionSummaries {
    return const <String>[];
  }

  // ignore: unused_element
  String? _eventActionSummary(AgentEvent event) {
    if (event.type == 'run.started') {
      return 'Started ${event.raw['tool'] ?? _workbenchViewModel.selectedAdapter ?? 'CLI'} session';
    }
    if (event.type == 'approval.required') {
      return 'Waiting for permission confirmation';
    }
    if (event.type == 'tool.started') {
      final name = event.name ?? _toolNameFromRaw(event) ?? 'Tool';
      final target = _toolTargetFromRaw(event);
      return target == null ? 'Call $name' : 'Call $name: $target';
    }
    if (event.type == 'tool.output') {
      final target = _toolTargetFromRaw(event);
      return target == null ? 'Tool returned output' : 'Processed: $target';
    }
    if (event.type == 'diff.summary' && event.diff != null) {
      return 'Changed ${event.diff!.filePath}  +${event.diff!.additions} -${event.diff!.deletions}';
    }
    if (event.type == 'raw.output') {
      final text = event.text?.trim();
      if (text == null || text.isEmpty || text.startsWith('{')) return null;
      return text.length > 64 ? '${text.substring(0, 64)}…' : text;
    }
    if (event.type == 'run.completed') return 'Run completed';
    if (event.type == 'run.failed') return 'Run failed';
    return null;
  }

  String? _toolNameFromRaw(AgentEvent event) {
    final raw = event.raw['raw'];
    if (raw is Map<String, Object?>) {
      final name = raw['name'] ?? raw['tool'] ?? raw['command'];
      if (name is String && name.trim().isNotEmpty) return name;
    }
    return null;
  }

  String? _toolTargetFromRaw(AgentEvent event) {
    final raw = event.raw['raw'];
    if (raw is Map<String, Object?>) {
      final input = raw['input'];
      if (input is Map<String, Object?>) {
        final file = input['file_path'] ?? input['path'] ?? input['filename'];
        if (file is String && file.trim().isNotEmpty) {
          return file.split('\\').last;
        }
      }
    }
    return null;
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _useReverseTranscript
          ? _scrollController.position.minScrollExtent
          : _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _syncTranscriptUnderflow() {
    if (!_bottomAnchorTranscript) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_bottomAnchorTranscript ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final underflows =
          position.maxScrollExtent <= position.minScrollExtent + .5;
      if (_bottomAnchorTranscriptUnderflow == underflows) return;
      final resumedReverseRendering =
          _bottomAnchorTranscriptUnderflow && !underflows;
      setState(() => _bottomAnchorTranscriptUnderflow = underflows);
      if (resumedReverseRendering) _scrollToBottom(jump: true);
    });
  }

  Future<void> _sendPrompt() async {
    await _finishVoiceInputForSend();
    if (!mounted) return;
    final prompt = _prompt.text.trim();
    final draft = _prompt.text;
    final adapter = _workbenchViewModel.selectedAdapter;
    final pendingQuestionId = _workbenchViewModel.pendingQuestionId;
    if (adapter == null ||
        _sending ||
        !_workbenchViewModel.canSendComposer(text: prompt) ||
        (pendingQuestionId != null &&
            pendingQuestionId.isNotEmpty &&
            _workbenchViewModel.draftAttachments.isNotEmpty)) {
      return;
    }
    final routeWorkspace = _routeWorkspace;
    if (_activeRunId == null && routeWorkspace == null) {
      _goToWorkspaces();
      return;
    }
    setState(() {
      _workbenchViewModel.beginOperation(notify: false);
      final hasDraftAttachment =
          _workbenchViewModel.draftAttachments.any((item) => item.isValid);
      if (prompt.isNotEmpty || hasDraftAttachment) {
        _workbenchViewModel.addUserMessage(prompt,
            includeDraftAttachments: true, notify: false);
      }
      _prompt.clear();
    });
    _scrollToBottom();
    try {
      final existingConversationId = _activeConversationId;
      if (existingConversationId == null) {
        final model =
            _workbenchViewModel.selectedAdapterStatus?.canSelectModel == true
                ? _workbenchViewModel.selectedModel
                : null;
        final sendStartSeq = _workbenchViewModel.lastSeq;
        final result = await _workbenchViewModel.createAndSend(
          workspace: routeWorkspace!,
          prompt: prompt,
          adapter: adapter,
          permissionMode: widget.permissionMode,
          model: model,
        );
        setState(() {
          _workbenchViewModel.prepareNewConversationSend(
              result.runningConversation,
              run: result.run,
              notify: false);
        });
        if (mounted) _goToConversation();
        await _restartConversationEventSubscription();
        final updated = await result.updatedConversation;
        if (mounted) {
          setState(() {
            _applyConversationSendAcknowledgement(
              updated,
              sendStartSeq: sendStartSeq,
            );
          });
        }
      } else if (pendingQuestionId != null && pendingQuestionId.isNotEmpty) {
        final conversation =
            await _workbenchViewModel.answerConversationQuestion(
          conversationId: existingConversationId,
          questionId: pendingQuestionId,
          text: prompt,
        );
        setState(() {
          _workbenchViewModel.updateActiveConversation(conversation,
              notify: false);
          _workbenchViewModel.removeQuestionMessages(notify: false);
        });
      } else {
        if (_isRunningCli) return;
        final sendStartSeq = _workbenchViewModel.lastSeq;
        setState(() {
          _workbenchViewModel.markConversationRunning(notify: false);
        });
        final conversation =
            await _workbenchViewModel.sendExistingConversationPrompt(
          conversationId: existingConversationId,
          prompt: prompt,
          restartPolling: _restartConversationEventSubscription,
        );
        if (mounted) {
          setState(() {
            _applyConversationSendAcknowledgement(
              conversation,
              sendStartSeq: sendStartSeq,
            );
          });
        }
      }
      _scrollToBottom();
    } catch (err, stack) {
      if (err is ConversationRepositoryException &&
          err.code == 'capability_stale') {
        try {
          await _refreshAdapterCapabilities();
        } catch (_) {
          // Preserve the original send error; retry uses any refreshed data.
        }
      }
      final sendAcknowledgementTimedOut = isSendAcknowledgementTimeout(
        err,
        activeConversationId: _activeConversationId,
        activeRunId: _activeRunId,
      );
      if (sendAcknowledgementTimedOut) {
        setState(() {
          _workbenchViewModel.clearOperationError(notify: false);
        });
        await _restartConversationEventSubscription();
        return;
      }
      final traced = await _recordWorkbenchException(
        err,
        stack,
        operation: 'sendMessage',
      );
      setState(() {
        if (_prompt.text.isEmpty && draft.isNotEmpty) {
          _prompt.value = TextEditingValue(
              text: draft,
              selection: TextSelection.collapsed(offset: draft.length));
        }
        _workbenchViewModel.setOperationError(traced.message,
            traceId: traced.traceId, notify: false);
      });
    } finally {
      if (mounted) _workbenchViewModel.finishOperation();
    }
  }

  Future<_WorkbenchTraceError> _recordWorkbenchException(
    Object error,
    StackTrace stack, {
    required String operation,
    String? path,
  }) async {
    final message = error.toString();
    try {
      final traceId = await _workbenchViewModel.recordException(
        message: message,
        stack: stack.toString(),
        path: path,
        conversationId: _activeConversationId,
        runId: _activeRunId,
        operation: operation,
      );
      return _WorkbenchTraceError(message, traceId);
    } catch (_) {
      return _WorkbenchTraceError(message, null);
    }
  }

  Future<void> _cancelConversationEventSubscription() async {
    _conversationEventSubscriptionGeneration += 1;
    final subscription = _conversationEventSubscription;
    _conversationEventSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _restartConversationEventSubscription() async {
    await _cancelConversationEventSubscription();
    final runId = _activeRunId;
    final conversationId = _activeConversationId;
    if (!mounted || runId == null || conversationId == null) return;
    final afterSeq = _workbenchViewModel.lastSeq;
    final generation = _conversationEventSubscriptionGeneration;
    _conversationEventSubscription = _workbenchViewModel
        .watchConversationEvents(
            conversationId: conversationId, afterSeq: afterSeq)
        .asyncMap((event) => _applyConversationEventFromStream(
              event,
              conversationId: conversationId,
              runId: runId,
              generation: generation,
            ))
        .listen((_) {}, onError: (Object error, StackTrace stack) {
      if (generation != _conversationEventSubscriptionGeneration) return;
      unawaited(_workbenchViewModel.recordException(
        message: error.toString(),
        stack: stack.toString(),
        path: '/api/notifications/ws',
        conversationId: conversationId,
        runId: runId,
        operation: 'watchConversationEvents',
      ));
    });
  }

  Future<void> _applyConversationEventFromStream(
    ConversationEvent event, {
    required String conversationId,
    required String runId,
    required int generation,
  }) async {
    bool isStillCurrent() =>
        generation == _conversationEventSubscriptionGeneration &&
        mounted &&
        conversationId == _activeConversationId &&
        runId == _activeRunId;

    if (!isStillCurrent()) {
      return;
    }
    final changed = await _workbenchViewModel.applyConversationEventsAsync(
      <ConversationEvent>[event],
      streamOutput: widget.streamOutput,
      notify: true,
      isCurrent: isStillCurrent,
    );
    if (!isStillCurrent()) {
      return;
    }
    if (changed) {
      _scrollToBottom();
    }
  }

  void _startNewSessionFromList() {
    final workspace = _routeWorkspace;
    if (workspace == null) {
      _goToWorkspaces();
      return;
    }
    _workbenchViewModel.showConversation(workspace);
    setState(() {
      _resetConversationState();
      _workbenchViewModel.clearOperationError(notify: false);
      _prompt.clear();
    });
    _goToConversation();
  }

  Future<void> _respondApproval(AgentEvent event, String decision) async {
    final approvalId = event.approvalId;
    if (approvalId == null || approvalId.isEmpty) return;
    try {
      final conversationId = _activeConversationId;
      if (conversationId != null) {
        final conversation =
            await _workbenchViewModel.respondConversationApproval(
          conversationId: conversationId,
          approvalId: approvalId,
          decision: decision,
        );
        _workbenchViewModel.updateActiveConversation(conversation,
            notify: false);
      } else {
        await _workbenchViewModel.respondRunApproval(
          approvalId: approvalId,
          decision: decision,
        );
      }
      setState(() {
        _workbenchViewModel.applyApprovalResponse(event, decision,
            notify: false);
      });
      final conversation = _activeConversation;
      if (conversation != null && shouldPollAfterApproval(conversation)) {
        await _restartConversationEventSubscription();
      }
    } catch (err) {
      _workbenchViewModel.setOperationError(err.toString());
    }
  }

  void _useQuestionSuggestion(String text) {
    _prompt.text = text;
    _prompt.selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navigatorKey,
      initialRoute: _routeWorkspaces,
      onGenerateRoute: (settings) {
        final name = settings.name ?? _routeWorkspaces;
        return PageRouteBuilder<void>(
          settings: RouteSettings(name: name),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => _buildRoute(name),
        );
      },
      observers: [_CodingRouteObserver(_setCurrentRoute)],
    );
  }

  Widget _buildRoute(String route) {
    if (_workbenchViewModel.routeState is CreatingWorkspaceRouteState) {
      return _buildCreatingWorkspaceTransition();
    }
    if (route == _routeSessions) return _buildSessionList();
    if (route == _routeConversation) return _buildConversationDetail();
    return _buildWorkspaceList();
  }

  Widget _buildCreatingWorkspaceTransition() {
    final state = _workbenchViewModel.routeState;
    final label =
        state is CreatingWorkspaceRouteState ? state.requestLabel : 'workspace';
    return Center(
      key: const ValueKey('creating-workspace-transition'),
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xEE0A0B0D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.purple,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Creating workspace',
              style: TextStyle(
                color: theme.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: theme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceList() => WorkspaceListPage(
      workspaces: _workspaces,
      onSelected: _openWorkspaceSessions,
      onAddWorkspace: _showCreateWorkspaceFromWorkspaceList);

  Widget _buildSessionList() {
    final workspace = _routeWorkspace;
    if (workspace == null) return _buildWorkspaceList();
    return CodingSessionListPage(
        data: widget.data,
        items: _sessionItems,
        currentWorkspace: workspace,
        onNewSession: _startNewSessionFromList,
        onSelectItem: _openSession,
        onBackToWorkspaces: _returnToWorkspaceList);
  }

  String? _selectedModelLabel() {
    if (_workbenchViewModel.selectedAdapterStatus?.canSelectModel != true) {
      return null;
    }
    final selected = _workbenchViewModel.selectedModel;
    if (selected == null || selected.isEmpty) {
      return AppLocalizations.of(context).modelPickerDefaultModel;
    }
    for (final model in _workbenchViewModel.availableModels) {
      if (model.id == selected) {
        return model.label.isEmpty ? model.id : model.label;
      }
    }
    return selected;
  }

  String? _modelUpdateErrorLabel(BuildContext context) {
    if (_workbenchViewModel.conversationModelUpdatesUnsupported) {
      return _modelPickerUnsupportedDaemonText(context);
    }
    final error = _workbenchViewModel.modelUpdateError?.trim();
    if (error == null || error.isEmpty) return null;
    final normalized = error.toLowerCase();
    if (normalized.contains('current turn') || normalized.contains('active')) {
      return _modelPickerBusyText(context);
    }
    return error;
  }

  Widget _buildConversationDetail() {
    final l10n = AppLocalizations.of(context);
    final workspace = _routeWorkspace;
    if (workspace == null) return _buildWorkspaceList();
    final adapter = _workbenchViewModel.selectedAdapter;
    final modelLabel = _selectedModelLabel();
    final pendingQuestionId = _workbenchViewModel.pendingQuestionId;
    final pendingQuestionCanSendAttachments =
        pendingQuestionId == null || pendingQuestionId.isEmpty;
    final canSend = adapter != null &&
        !_sending &&
        canSendInConversationStatus(
            _workbenchViewModel.effectiveConversationStatus) &&
        (pendingQuestionCanSendAttachments ||
            _workbenchViewModel.draftAttachments.isEmpty) &&
        _workbenchViewModel.canSendComposer(text: _prompt.text);
    return Column(key: const ValueKey('coding-workbench-detail'), children: [
      Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
          decoration: BoxDecoration(
              color: const Color(0xEE0A0B0D),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: .075)))),
          child: _CodingHeader(
              title: _conversationTitle(l10n),
              workspace: workspace,
              adapter: adapter,
              running: _isRunningCli,
              onBack: () => _navigatorKey.currentState?.popUntil(
                  (route) => route.settings.name == _routeSessions))),
      Expanded(child: _buildMessageList(adapter, l10n)),
      CodingComposer(
          controller: _prompt,
          adapter: adapter,
          model: modelLabel,
          modelNotice: _modelNoticeLabel(l10n),
          workspace: workspace,
          running: _isRunningCli,
          cliLocked: _isConversationAdapterLocked,
          modelLocked: _isModelSelectionLocked,
          canSend: canSend,
          sending: _sending,
          voiceState: _voiceInput.state,
          voiceEnabled: widget.speechInputService != null ||
              isVoiceInputPlatformSupported,
          voiceError: null,
          draftAttachments: _workbenchViewModel.draftAttachments,
          onAttachmentTap: () => unawaited(_pickAttachments()),
          onRemoveAttachment: _workbenchViewModel.removeDraftAttachment,
          onCliTap: _showAdapterPicker,
          onModelTap: _showModelPicker,
          onVoiceStart: () => unawaited(_startVoiceInput()),
          onVoiceStop: () => unawaited(_stopVoiceInput()),
          onVoiceCancel: () => unawaited(_cancelVoiceInput()),
          onTextChanged: _handleComposerTextChanged,
          onSend: _sendPrompt,
          onCancel: _cancelActiveRun),
      ComposerWorkspaceCloud(
          workspace: workspace,
          running: _isRunningCli,
          onTap: _showWorkspacePicker),
    ]);
  }

  String? _modelNoticeLabel(AppLocalizations l10n) =>
      switch (_workbenchViewModel.modelNotice) {
        WorkbenchModelNotice.changedToAvailableOption =>
          l10n.workbenchComposerModelChangedNotice,
        null => null,
      };

  Widget _buildMessageList(String? adapter, AppLocalizations l10n) {
    final hasStatus = _activeRunId != null;
    final hasError = _error != null;
    final hasPending = _isBusyCli;
    final useReverseTranscript = _useReverseTranscript;
    final itemCount = (hasStatus ? 1 : 0) +
        _messages.length +
        (hasError ? 1 : 0) +
        (hasPending ? 1 : 0);
    _syncTranscriptUnderflow();
    return ListView.builder(
      key: ValueKey(
        'workbench-message-list-${useReverseTranscript ? 'reverse' : 'normal'}',
      ),
      controller: _scrollController,
      reverse: useReverseTranscript,
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final logicalIndex =
            useReverseTranscript ? itemCount - 1 - index : index;
        var messageIndex = logicalIndex;
        if (hasStatus) {
          if (logicalIndex == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: WorkbenchInlineStatus(
                adapter: adapter,
                runId: _activeRunId,
                eventCount: _conversationEvents.length,
                terminal: _isTerminal,
              ),
            );
          }
          messageIndex -= 1;
        }
        if (messageIndex < _messages.length) {
          final message = _messages[messageIndex];
          return Padding(
            key: ValueKey('workbench-message-$messageIndex-${message.role}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: WorkbenchMessageCard(
              message: message,
              expandThinking: widget.expandThinking,
              onSuggestion: (text) => _useQuestionSuggestion(text),
              onApproval: (decision) =>
                  _respondApproval(message.event!, decision),
            ),
          );
        }
        messageIndex -= _messages.length;
        if (hasError) {
          if (messageIndex == 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _buildRunErrorCard(),
            );
          }
          messageIndex -= 1;
        }
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: PendingSentinel(
            adapter: adapter ?? 'CLI',
            statusText: _pendingStatusText(l10n),
            actions: _recentActionSummaries,
          ),
        );
      },
    );
  }

  Widget _buildRunErrorCard() => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Run error: $_error',
              style: const TextStyle(
                  color: theme.red, fontSize: 12, height: 1.45)),
          if (_errorTraceId != null) ...[
            const SizedBox(height: 8),
            Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableText('Trace ID: $_errorTraceId',
                      style: const TextStyle(
                          color: theme.muted, fontSize: 12, height: 1.35)),
                  TinyActionButton('Copy Trace ID', onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                        ClipboardData(text: _errorTraceId!));
                    messenger.showSnackBar(
                        const SnackBar(content: Text('Trace ID copied')));
                  })
                ]),
          ],
        ]),
      );

  String _conversationTitle(AppLocalizations l10n) {
    final persistedTitle = _activeConversation?.title?.trim();
    if (persistedTitle != null && persistedTitle.isNotEmpty) {
      return _truncateConversationTitle(persistedTitle);
    }
    final userMessage = _messages.where((message) => message.role == 'user');
    if (userMessage.isEmpty) return l10n.workbenchNewSessionTitle;
    final first = userMessage.first;
    final text = first.body.trim().isNotEmpty
        ? first.body.trim()
        : first.attachments.isNotEmpty
            ? first.attachments.first.name
            : '';
    if (text.isEmpty) return l10n.workbenchNewSessionTitle;
    return _truncateConversationTitle(text);
  }

  String _truncateConversationTitle(String title) {
    if (title.length <= _conversationTitleMaxLength) return title;
    return '${title.substring(0, _conversationTitleMaxLength)}…';
  }
}

class _WorkbenchTraceError {
  const _WorkbenchTraceError(this.message, this.traceId);

  final String message;
  final String? traceId;
}

class _VoiceInputErrorDialog extends StatelessWidget {
  const _VoiceInputErrorDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF111214),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .48),
                    blurRadius: 28,
                    offset: const Offset(0, 18))
              ]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: theme.amber.withValues(alpha: .12),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.amber.withValues(alpha: .28))),
                  child: const Icon(Icons.mic_off_rounded,
                      color: theme.amber, size: 18)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('语音输入不可用',
                        style: TextStyle(
                            color: theme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.25)),
                    const SizedBox(height: 7),
                    Text(message,
                        style: const TextStyle(
                            color: theme.muted, fontSize: 13, height: 1.45))
                  ]))
            ]),
            const SizedBox(height: 18),
            Align(
                alignment: Alignment.centerRight,
                child: TinyActionButton('知道了',
                    primary: true, onTap: () => Navigator.of(context).pop()))
          ])));
}

class _AsrModelDownloadDialog extends StatefulWidget {
  const _AsrModelDownloadDialog({required this.manager});

  final AsrModelManager manager;

  @override
  State<_AsrModelDownloadDialog> createState() =>
      _AsrModelDownloadDialogState();
}

class _AsrModelDownloadDialogState extends State<_AsrModelDownloadDialog> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    unawaited(widget.manager.ensureReady().then((path) {
      if (mounted) Navigator.of(context).pop(path);
    }).catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.manager,
      builder: (context, _) {
        final state = widget.manager.state;
        final failed = state.status == AsrModelStatus.failed;
        final paused = state.status == AsrModelStatus.paused;
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
            backgroundColor: const Color(0xFF111214),
            title: Text(l10n.asrModelDialogTitle,
                style: const TextStyle(color: theme.text, fontSize: 17)),
            content: SizedBox(
                width: 340,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_statusLabel(l10n, state),
                          style: const TextStyle(
                              color: theme.muted, fontSize: 13, height: 1.35))),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                      value: state.totalBytes > 0 ? state.progress : null,
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(theme.purple)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: Text(_bytesLabel(state),
                            style: const TextStyle(
                                color: theme.faint, fontSize: 12))),
                    Text(_speedLabel(state),
                        style:
                            const TextStyle(color: theme.faint, fontSize: 12)),
                  ]),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(state.errorMessage!,
                        style: const TextStyle(
                            color: theme.red, fontSize: 12, height: 1.35)),
                  ],
                  if (state.traceId != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: SelectableText(
                              l10n.asrModelTraceId(state.traceId!),
                              style: const TextStyle(
                                  color: theme.muted, fontSize: 12))),
                      TextButton(
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: state.traceId!)),
                          child: Text(l10n.asrModelCopyAction)),
                    ]),
                  ],
                ])),
            actions: [
              if (state.status == AsrModelStatus.downloading)
                TextButton(
                    onPressed: widget.manager.pause,
                    child: Text(l10n.asrModelPauseAction)),
              if (paused)
                TextButton(
                    onPressed: widget.manager.resume,
                    child: Text(l10n.asrModelResumeAction)),
              if (failed)
                TextButton(
                    onPressed: _start, child: Text(l10n.asrModelRetryAction)),
              TextButton(
                  onPressed: () {
                    widget.manager.cancel();
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n.asrModelCancelAction)),
            ]);
      });

  String _statusLabel(AppLocalizations l10n, AsrModelState state) =>
      switch (state.status) {
        AsrModelStatus.idle => l10n.asrModelPreparing,
        AsrModelStatus.checking => l10n.asrModelChecking,
        AsrModelStatus.downloading =>
          l10n.asrModelDownloading(state.version ?? l10n.asrModelFallbackName),
        AsrModelStatus.paused => l10n.asrModelPaused,
        AsrModelStatus.verifying => l10n.asrModelVerifying,
        AsrModelStatus.extracting => l10n.asrModelExtracting,
        AsrModelStatus.ready => l10n.asrModelReady,
        AsrModelStatus.failed => l10n.asrModelFailed,
        AsrModelStatus.cancelled => l10n.asrModelCancelled,
      };

  String _bytesLabel(AsrModelState state) {
    if (state.totalBytes <= 0) {
      return AppLocalizations.of(context).asrModelWaitingSize;
    }
    return '${_formatBytes(state.downloadedBytes)} / ${_formatBytes(state.totalBytes)}';
  }

  String _speedLabel(AsrModelState state) {
    if (state.speedBytesPerSecond <= 0 ||
        state.status != AsrModelStatus.downloading) {
      return '';
    }
    return '${_formatBytes(state.speedBytesPerSecond.round())}/s';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class _CodingRouteObserver extends NavigatorObserver {
  _CodingRouteObserver(this.onRouteChanged);

  final ValueChanged<String> onRouteChanged;

  void _notify(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name is String && name.isNotEmpty) onRouteChanged(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _notify(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _notify(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _notify(newRoute);
  }
}

bool _isSelectableCliAdapter(AdapterStatus adapter) {
  final id = adapter.adapter.trim().toLowerCase();
  if (id.isEmpty || id.startsWith('synthetic-')) return false;
  return const {'claude', 'codex', 'opencode'}.contains(id);
}

class ModelPickerSheet extends StatelessWidget {
  const ModelPickerSheet({
    super.key,
    required this.models,
    required this.selected,
    required this.onSelected,
    this.updating = false,
    this.selectionDisabled = false,
    this.pendingModel,
    this.errorText,
  });

  final List<AdapterModelOption> models;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool updating;
  final bool selectionDisabled;
  final String? pendingModel;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visibleModels = models
        .where((model) => model.id.trim().isNotEmpty)
        .toList(growable: false);
    final normalizedError = errorText?.trim();
    final normalizedPending = pendingModel?.trim();
    final choicesDisabled = updating || selectionDisabled;
    return SafeArea(
        top: false,
        child: Container(
            key: const ValueKey('model-picker-sheet'),
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .72),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
                color: const Color(0xFF111820),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: .1)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .42),
                      blurRadius: 30,
                      offset: const Offset(0, 18))
                ]),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .045),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .13))),
                        child: const Icon(Icons.memory_rounded,
                            size: 17, color: theme.active)),
                    const SizedBox(width: 11),
                    Expanded(
                        child: Text(l10n.modelPickerTitle,
                            style: const TextStyle(
                                color: theme.text,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0))),
                  ]),
                  const SizedBox(height: 13),
                  if (updating)
                    Container(
                        key: const ValueKey('model-picker-updating'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .035),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.stroke)),
                        child: Row(children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: theme.active)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  normalizedPending == null ||
                                          normalizedPending.isEmpty
                                      ? _modelPickerUpdatingText(context)
                                      : '${_modelPickerUpdatingText(context)} $normalizedPending',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: theme.muted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)))
                        ])),
                  if (normalizedError != null && normalizedError.isNotEmpty)
                    Container(
                        key: const ValueKey('model-picker-error'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 10),
                        decoration: BoxDecoration(
                            color: theme.red.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: theme.red.withValues(alpha: .28))),
                        child: Row(children: [
                          Icon(Icons.error_outline_rounded,
                              color: theme.red.withValues(alpha: .92),
                              size: 16),
                          const SizedBox(width: 9),
                          Expanded(
                              child: Text(normalizedError,
                                  style: TextStyle(
                                      color: theme.red.withValues(alpha: .95),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)))
                        ])),
                  Flexible(
                      child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: visibleModels.isEmpty
                              ? <Widget>[
                                  _ModelChoiceRow(
                                      key: const ValueKey(
                                          'model-option-default'),
                                      title: l10n.modelPickerDefaultModel,
                                      source: _modelPickerCliDefaultDetailText(
                                          context),
                                      selected: selected == null,
                                      onTap: choicesDisabled
                                          ? null
                                          : () => onSelected(null)),
                                ]
                              : <Widget>[
                                  for (final model in visibleModels)
                                    _ModelChoiceRow(
                                        key: ValueKey(
                                            'model-option-${model.id}'),
                                        title: model.label.isEmpty
                                            ? model.id
                                            : model.label,
                                        source: _modelSourceLabel(
                                            l10n, model.source),
                                        selected: model.id == selected,
                                        onTap: choicesDisabled
                                            ? null
                                            : () => onSelected(model.id)),
                                ])),
                ])));
  }
}

class _ModelChoiceRow extends StatelessWidget {
  const _ModelChoiceRow({
    super.key,
    required this.title,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String source;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1A212A)
                    : Colors.white.withValues(alpha: .03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected
                        ? theme.activeStroke.withValues(alpha: .75)
                        : theme.stroke)),
            child: Row(children: [
              Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .045),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .08))),
                  child: const Icon(Icons.memory_rounded,
                      color: theme.muted, size: 14)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: enabled
                                ? theme.text
                                : theme.text.withValues(alpha: .45),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0)),
                    const SizedBox(height: 2),
                    Text(source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: enabled
                                ? theme.muted
                                : theme.muted.withValues(alpha: .45),
                            fontSize: 11.5))
                  ])),
              if (selected)
                Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .06),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: theme.activeStroke.withValues(alpha: .7))),
                    child: const Icon(Icons.check_rounded,
                        color: theme.active, size: 12))
            ])));
  }
}

String _modelSourceLabel(AppLocalizations l10n, String source) =>
    switch (source) {
      'codex_config' => l10n.modelPickerSourceCodexConfig,
      'codex_catalog' => l10n.modelPickerSourceCodexCatalog,
      'claude_config' => l10n.modelPickerSourceClaudeEnv,
      'claude_env' => l10n.modelPickerSourceClaudeEnv,
      'cli_default' => l10n.modelPickerSourceCliDefault,
      _ => l10n.modelPickerSourceUnknown,
    };

String _modelPickerUpdatingText(BuildContext context) =>
    _modelPickerFallbackText(
        context: context,
        en: 'Updating model...',
        zh: '\u6b63\u5728\u66f4\u65b0\u6a21\u578b...');

String _modelPickerUnsupportedDaemonText(BuildContext context) =>
    _modelPickerFallbackText(
        context: context,
        en: 'Update the desktop daemon to change models in existing '
            'conversations.',
        zh: '\u8bf7\u66f4\u65b0\u684c\u9762\u7aef daemon \u540e\u518d\u4fee\u6539\u5df2\u6709\u5bf9\u8bdd\u7684\u6a21\u578b\u3002');

String _modelPickerBusyText(BuildContext context) => _modelPickerFallbackText(
    context: context,
    en: 'Wait for the current turn to finish before changing model.',
    zh: '\u5f53\u524d\u8f6e\u6b21\u7ed3\u675f\u540e\u624d\u80fd\u5207\u6362\u6a21\u578b\u3002');

String _modelPickerCliDefaultDetailText(BuildContext context) =>
    _modelPickerFallbackText(
        context: context,
        en: 'Uses the CLI configured default.',
        zh: '\u4f7f\u7528 CLI \u5f53\u524d\u914d\u7f6e\u7684\u9ed8\u8ba4\u6a21\u578b\u3002');

String _modelPickerFallbackText(
    {required BuildContext context, required String en, required String zh}) {
  return Localizations.localeOf(context).languageCode.toLowerCase() == 'zh'
      ? zh
      : en;
}

class _CodingHeader extends StatelessWidget {
  const _CodingHeader(
      {required this.title,
      required this.workspace,
      required this.adapter,
      required this.running,
      required this.onBack});
  final String title;
  final WorkspaceSummary workspace;
  final String? adapter;
  final bool running;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(children: [
        InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(11),
            child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: const Color(0xFF141518),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: theme.stroke)),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: theme.muted, size: 16))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.15))),
        const SizedBox(width: 46),
      ]);
}
