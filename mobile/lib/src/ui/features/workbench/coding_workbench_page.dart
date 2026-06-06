import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../domain/models/approval_response.dart';
import '../../../domain/repositories/conversation_repository.dart';
import '../../../models/protocol.dart';
import '../../../services/asr_model_manager.dart';
import '../../../services/mobile_app_event_bus.dart';
import '../../core/theme/theme.dart' as theme;
import '../../../workflows/workspace/create_workspace_workflow.dart'
    show
        CreateWorkspaceFailure,
        CreateWorkspaceNotConfirmed,
        CreateWorkspaceSuccess,
        CreateWorkspaceTimeout;
import 'attachments/attachment_picker.dart';
import 'controllers/slash_command_menu_controller.dart';
import 'dialogs/asr_model_download_dialog.dart';
import 'dialogs/voice_input_error_dialog.dart';
import 'messages/approval_event_card.dart';
import 'sheets/model_picker_sheet.dart';
import 'views/workbench_conversation_route.dart';
import 'views/workbench_session_route.dart';
import 'views/workbench_workspace_route.dart';
import 'voice_input.dart';
import 'widgets/workbench_message_list.dart';
import 'workbench_messages.dart';
import '../sessions/sessions.dart';
import '../workspace_picker/workspace_picker.dart';
import 'coding_workbench_controller.dart';
import 'view_models/workbench_view_model.dart';
import 'workbench_dependencies.dart';

class CodingWorkbenchPage extends StatefulWidget {
  const CodingWorkbenchPage({
    super.key,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.streamOutput,
    required this.expandThinking,
    this.expandToolDetails = false,
    required this.permissionMode,
    required this.dependencies,
    this.speechInputService,
  });
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final bool streamOutput;
  final bool expandThinking;
  final bool expandToolDetails;
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
  static const int _conversationHistoryPageSize = 80;
  static const Duration _backgroundEventDisconnectDelay = Duration(seconds: 30);

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _prompt = TextEditingController();
  final _scrollController = ScrollController();
  late final VoiceInputViewModel _voiceInput;
  late final AsrModelManager _asrModelManager;
  late final WorkbenchAttachmentPicker _attachmentPicker;
  SpeechInputService? _ownedSpeechInputService;
  late final WorkbenchViewModel _workbenchViewModel;
  StreamSubscription<void>? _conversationEventSubscription;
  Timer? _backgroundEventDisconnectTimer;
  Timer? _initialConversationPendingRevealTimer;
  bool _conversationEventsSuspendedForBackground = false;
  int _conversationEventSubscriptionGeneration = 0;
  String? _lastVoiceErrorNotice;
  bool _voiceErrorDialogOpen = false;
  bool _applyingVoiceText = false;
  String _currentRoute = _routeWorkspaces;
  bool? _lastReportedListOpen = true;
  late int _handledOpenSessionListRequest;
  bool _bottomAnchorTranscript = false;
  bool _bottomAnchorTranscriptUnderflow = false;
  bool _loadingInitialConversationEvents = false;
  bool _showPendingDuringInitialConversationLoad = false;
  List<SlashCommand> _visibleSlashCommands = const <SlashCommand>[];
  final Set<String> _loadingSlashAdapters = <String>{};
  SlashCommandToken? _activeSlashToken;
  String? _lastSlashAdapter;

  List<SessionItem> get _sessionItems => _workbenchViewModel.sessionItems;

  List<WorkspaceSummary> get _workspaces => _workbenchViewModel.workspaces;

  WorkspaceSummary? get _routeWorkspace => _workbenchViewModel.routeWorkspace;
  String? get _activeRunId => _workbenchViewModel.activeRunId;
  String? get _activeConversationId => _workbenchViewModel.activeConversationId;
  ConversationSummary? get _activeConversation =>
      _workbenchViewModel.activeConversation;
  ConversationSummary? get activeConversation =>
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
    if (_currentRoute == _routeWorkspaces) return false;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    return navigator.maybePop<void>();
  }

  void showSessionListFromShell() {
    _goToWorkspaces();
  }

  Future<bool> openConversationFromNotification({
    required String workspaceId,
    required String conversationId,
  }) async {
    if (!mounted) return false;
    SessionItem? item;
    for (final candidate in _sessionItems) {
      if (candidate.conversation?.id == conversationId) {
        item = candidate;
        break;
      }
    }
    if (item == null) {
      final workspace = _workspaceForId(workspaceId);
      _workbenchViewModel.showSessions(workspace.id);
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
          _routeSessions, (route) => route.settings.name == _routeWorkspaces);
      return false;
    }
    await _openSession(item);
    return true;
  }

  // Slice 3 subscription ownership: route switch decides whether conversation stream should stay active.
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
    if (route == _routeConversation) {
      _ensureSlashCatalogForConversationRoute();
    } else {
      _setSlashCommands(const <SlashCommand>[], null);
    }
  }

  // Slice 3 subscription ownership: route reset cancels active conversation event stream.
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
    if (_workbenchViewModel.openingWorkspace) return;
    unawaited(_goToSessions(workspace));
  }

  Future<bool> _goToSessions(WorkspaceSummary workspace) async {
    if (_workbenchViewModel.openingWorkspace) return false;
    await _cancelConversationEventSubscription();
    try {
      await _workbenchViewModel.openWorkspaceSessions(workspace.id);
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Workspace failed to open: $error'),
          duration: const Duration(seconds: 2),
        ),
      );
      return false;
    }
    if (!mounted ||
        _workbenchViewModel.routeState is! WorkspaceSessionsRouteState) {
      return false;
    }
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        _routeSessions, (route) => route.settings.name == _routeWorkspaces);
    return true;
  }

  void _goToConversation() {
    final workspace = _routeWorkspace;
    if (workspace != null &&
        _workbenchViewModel.routeState is! ConversationRouteState) {
      _workbenchViewModel.showConversation(workspace.id);
    }
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        _routeConversation, (route) => route.settings.name == _routeSessions);
  }

  void _resetConversationState({bool bottomAnchorTranscript = false}) {
    unawaited(_cancelConversationEventSubscription());
    _bottomAnchorTranscript = bottomAnchorTranscript;
    _bottomAnchorTranscriptUnderflow = false;
    _cancelInitialConversationPendingReveal();
    _loadingInitialConversationEvents = false;
    _showPendingDuringInitialConversationLoad = false;
    _workbenchViewModel.resetConversationDisplay(notify: false);
  }

  // Slice 3 subscription ownership: opening a session loads initial events then restarts stream.
  Future<void> _openSession(SessionItem item) async {
    await _cancelConversationEventSubscription();
    if (!mounted) return;
    setState(() {
      _resetConversationState(
          bottomAnchorTranscript: item.conversation != null);
      _workbenchViewModel.openSession(item, notify: false);
      _workbenchViewModel.clearOperationError(notify: false);
      _loadingInitialConversationEvents = item.conversation != null;
      _showPendingDuringInitialConversationLoad = false;
    });
    if (item.conversation != null &&
        isActiveConversationStatus(item.conversation!.status)) {
      _scheduleInitialConversationPendingReveal();
    }
    _workbenchViewModel.showConversationRoute(
        _workspaceForId(item.run.workspaceId).id, item.conversation?.id ?? '');
    final conversation = item.conversation;
    _goToConversation();
    _scrollToBottom(jump: true);
    if (conversation != null) {
      final generation = _conversationEventSubscriptionGeneration;
      try {
        await _loadInitialConversationEventPage(
          conversationId: conversation.id,
          runId: item.run.id,
          generation: generation,
          streamOutput: widget.streamOutput &&
              isActiveConversationStatus(conversation.status),
        );
        if (!_isCurrentConversationEventTarget(
          conversationId: conversation.id,
          runId: item.run.id,
          generation: generation,
        )) {
          return;
        }
        await _restartConversationEventSubscription();
      } catch (error, stack) {
        if (!mounted ||
            !_isCurrentConversationEventTarget(
              conversationId: conversation.id,
              runId: item.run.id,
              generation: generation,
            )) {
          return;
        }
        final traced = await _recordWorkbenchException(
          error,
          stack,
          operation: 'openConversation',
          path: '/api/conversations/${conversation.id}/events',
        );
        if (!mounted) return;
        setState(() {
          _workbenchViewModel.setOperationError(
            traced.message,
            traceId: traced.traceId,
            notify: false,
          );
        });
      } finally {
        if (mounted &&
            _isCurrentConversationEventTarget(
              conversationId: conversation.id,
              runId: item.run.id,
              generation: generation,
            )) {
          setState(() => _loadingInitialConversationEvents = false);
          _cancelInitialConversationPendingReveal();
        }
      }
    }
  }

  void _scheduleInitialConversationPendingReveal() {
    _cancelInitialConversationPendingReveal();
    _initialConversationPendingRevealTimer =
        Timer(const Duration(milliseconds: 650), () {
      if (!mounted || !_loadingInitialConversationEvents) return;
      setState(() => _showPendingDuringInitialConversationLoad = true);
    });
  }

  void _cancelInitialConversationPendingReveal() {
    _initialConversationPendingRevealTimer?.cancel();
    _initialConversationPendingRevealTimer = null;
    _showPendingDuringInitialConversationLoad = false;
  }

  void _clearInitialConversationLoadingGate() {
    _cancelInitialConversationPendingReveal();
    _loadingInitialConversationEvents = false;
    _showPendingDuringInitialConversationLoad = false;
  }

  // Slice 3 subscription ownership: initial event page controls when live stream may append.
  Future<void> _loadInitialConversationEventPage({
    required String conversationId,
    required String runId,
    required int generation,
    required bool streamOutput,
  }) async {
    await _workbenchViewModel.loadInitialConversationEventPage(
      conversationId: conversationId,
      limit: _conversationHistoryPageSize,
      streamOutput: streamOutput,
      isCurrent: () => _isCurrentConversationEventTarget(
        conversationId: conversationId,
        runId: runId,
        generation: generation,
      ),
    );
  }

  WorkspaceSummary _workspaceForId(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return _routeWorkspace ??
        _workbenchViewModel.selectedWorkspace ??
        _workspaces.first;
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
      workspaceRepository: widget.dependencies.workspaceRepository,
      adapterRepository: widget.dependencies.adapterRepository,
      conversationRepository: widget.dependencies.conversationRepository,
      runRepository: widget.dependencies.runRepository,
      diagnosticsRepository: widget.dependencies.diagnosticsRepository,
      workspaceOpeningUseCase: widget.dependencies.workspaceOpeningUseCase,
      attachmentPreviewCache: widget.dependencies.attachmentPreviewCache,
    )..addListener(_syncWorkbenchViewModel);
    _attachmentPicker = const WorkbenchAttachmentPicker();
    _asrModelManager = widget.dependencies.asrModelManager;
    _voiceInput = VoiceInputViewModel(service: _createSpeechInputService())
      ..addListener(_syncVoicePreviewText);
    _prompt.addListener(_handlePromptValueChanged);
    widget.dependencies.codingPreferencesRepository.addListener(
      _handleCodingPreferencesChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setCurrentRoute(_routeWorkspaces);
    });
  }

  @override
  void didUpdateWidget(covariant CodingWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dependencies.codingPreferencesRepository !=
        widget.dependencies.codingPreferencesRepository) {
      oldWidget.dependencies.codingPreferencesRepository.removeListener(
        _handleCodingPreferencesChanged,
      );
      widget.dependencies.codingPreferencesRepository.addListener(
        _handleCodingPreferencesChanged,
      );
      _handleCodingPreferencesChanged();
    }
    if (widget.openSessionListRequest == _handledOpenSessionListRequest) return;
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showSessionListFromShell();
    });
  }

  void _syncWorkbenchViewModel() {
    final adapter = _normalizedAdapter(_workbenchViewModel.selectedAdapter);
    if (adapter != _lastSlashAdapter) {
      _lastSlashAdapter = adapter;
      _visibleSlashCommands = const <SlashCommand>[];
      _activeSlashToken = null;
      _ensureSlashCatalogForConversationRoute();
    } else if (_currentRoute == _routeConversation) {
      _ensureSlashCatalogForConversationRoute();
    }
    if (mounted) setState(() {});
  }

  void _handleCodingPreferencesChanged() {
    if (widget.dependencies.codingPreferencesRepository
        .keepConversationEventsInBackground) {
      _cancelBackgroundEventDisconnectTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.dependencies.codingPreferencesRepository.removeListener(
      _handleCodingPreferencesChanged,
    );
    unawaited(_cancelConversationEventSubscription());
    _cancelInitialConversationPendingReveal();
    _voiceInput.removeListener(_syncVoicePreviewText);
    _voiceInput.dispose();
    _prompt.removeListener(_handlePromptValueChanged);
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
    switch (state) {
      case AppLifecycleState.resumed:
        final shouldRestartEvents = _conversationEventsSuspendedForBackground;
        _conversationEventsSuspendedForBackground = false;
        _cancelBackgroundEventDisconnectTimer();
        if (shouldRestartEvents) {
          unawaited(_restartConversationEventSubscription());
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _scheduleBackgroundEventDisconnect();
        break;
      case AppLifecycleState.inactive:
        break;
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
    if (_voiceErrorDialogOpen || !mounted) return;
    _voiceErrorDialogOpen = true;
    try {
      await showDialog<void>(
          context: context,
          builder: (context) => VoiceInputErrorDialog(message: message));
    } catch (_) {
      // Voice error presentation must not introduce a secondary async failure.
    } finally {
      _voiceErrorDialogOpen = false;
    }
  }

  Future<void> _startVoiceInput() async {
    try {
      if (widget.speechInputService == null &&
          _ownedSpeechInputService == null) {
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
    } catch (error) {
      if (!mounted) return;
      await _showVoiceErrorDialog(friendlyVoiceInputError(error));
    }
  }

  Future<String?> _showAsrDownloadDialog() {
    return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            AsrModelDownloadDialog(manager: _asrModelManager));
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
    _updateSlashCommandMenu(_prompt.value);
    if (mounted) setState(() {});
  }

  void _handlePromptValueChanged() {
    if (_applyingVoiceText) return;
    _updateSlashCommandMenu(_prompt.value);
  }

  void _ensureSlashCatalogForAvailableAdapters({
    bool onlyInConversation = true,
  }) {
    if (onlyInConversation && _currentRoute != _routeConversation) return;
    final adapters = _availableSlashCommandAdapters();
    for (final adapter in adapters) {
      unawaited(_ensureSlashCommandsLoaded(adapter));
    }
  }

  void _ensureSlashCatalogForConversationRoute() {
    _ensureSlashCatalogForAvailableAdapters(onlyInConversation: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentRoute != _routeConversation) return;
      _ensureSlashCatalogForAvailableAdapters(onlyInConversation: false);
    });
  }

  List<String> _availableSlashCommandAdapters() {
    final adapters = <String>{
      for (final adapter in _workbenchViewModel.availableAdaptersFromCache)
        if (adapter.available)
          if (_normalizedAdapter(adapter.adapter) case final normalized?)
            normalized,
      if (_normalizedAdapter(_workbenchViewModel.selectedAdapter)
          case final selected?)
        selected,
    }.toList(growable: false);
    adapters.sort();
    return adapters;
  }

  Future<void> _ensureSlashCommandsLoaded(String adapter) async {
    final normalized = _normalizedAdapter(adapter);
    final workspaceId = _routeWorkspace?.id;
    final loadKey = _slashLoadKey(normalized, workspaceId);
    if (normalized == null ||
        _loadingSlashAdapters.contains(loadKey) ||
        widget.dependencies.slashCommandCatalogRepository
            .hasLoadedAdapter(normalized, workspaceId: workspaceId)) {
      return;
    }
    _loadingSlashAdapters.add(loadKey);
    try {
      await widget.dependencies.slashCommandCatalogRepository.loadForAdapter(
        normalized,
        workspaceId: workspaceId,
      );
    } catch (_) {
      return;
    } finally {
      _loadingSlashAdapters.remove(loadKey);
    }
    if (!mounted ||
        _normalizedAdapter(_workbenchViewModel.selectedAdapter) != normalized) {
      return;
    }
    _updateSlashCommandMenu(_prompt.value);
  }

  void _updateSlashCommandMenu(TextEditingValue value) {
    final adapter = _normalizedAdapter(_workbenchViewModel.selectedAdapter);
    final token = _activeSlashTokenFor(value);
    if (adapter == null || token == null || _sending || _isRunningCli) {
      _setSlashCommands(const <SlashCommand>[], null);
      return;
    }
    unawaited(_ensureSlashCommandsLoaded(adapter));
    final commands =
        widget.dependencies.slashCommandCatalogRepository.commandsForAdapter(
      adapter,
      workspaceId: _routeWorkspace?.id,
    );
    final query = token.query.toLowerCase();
    final prefixMatches = <SlashCommand>[];
    final containsMatches = <SlashCommand>[];
    for (final command in commands) {
      final key = command.matchingKey;
      if (query.isEmpty || key.startsWith(query)) {
        prefixMatches.add(command);
      } else if (key.contains(query)) {
        containsMatches.add(command);
      }
    }
    _setSlashCommands(
      <SlashCommand>[...prefixMatches, ...containsMatches],
      token,
    );
  }

  void _setSlashCommands(
      List<SlashCommand> commands, SlashCommandToken? token) {
    final changed = !_sameSlashCommandList(_visibleSlashCommands, commands) ||
        _activeSlashToken != token;
    if (!changed) return;
    _visibleSlashCommands = List<SlashCommand>.unmodifiable(commands);
    _activeSlashToken = token;
    if (mounted) setState(() {});
  }

  void _insertSlashCommand(SlashCommand command) {
    final token = _activeSlashToken;
    if (token == null) return;
    final value = _prompt.value;
    if (token.start < 0 ||
        token.end > value.text.length ||
        token.start > token.end) {
      return;
    }
    final insertText = '${normalizeSlashCommand(command.command)} ';
    final text = value.text.replaceRange(token.start, token.end, insertText);
    final offset = token.start + insertText.length;
    _prompt.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    _setSlashCommands(const <SlashCommand>[], null);
  }

  SlashCommandToken? _activeSlashTokenFor(TextEditingValue value) =>
      SlashCommandMenuController.activeTokenFor(value);

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

  List<AdapterStatus> get _availableAdapters => _workbenchViewModel
      .availableAdaptersFromCache
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
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => AnimatedBuilder(
            animation: _workbenchViewModel,
            builder: (context, _) {
              final status = _workbenchViewModel.selectedAdapterStatus;
              final models = status?.canSelectModel == true
                  ? _workbenchViewModel.availableModels
                  : const <AdapterModelOption>[];
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
    try {
      final attachments = await _attachmentPicker.pickAttachments();
      if (!mounted || attachments.isEmpty) return;
      _workbenchViewModel.addDraftAttachments(attachments);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workbenchViewModel.setOperationError(
          'Attachment selection failed. Please try again.',
          notify: false,
        );
      });
    }
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
      case CreateWorkspaceSuccess(:final workspace):
        _workbenchViewModel.confirmWorkspaceCreated(
          workspaceId: workspace.id,
        );
        setState(() {
          _resetConversationState();
          _workbenchViewModel.clearOperationError(notify: false);
        });
        final opened = await _goToSessions(workspace);
        if (!opened && mounted) {
          _workbenchViewModel.cancelWorkspaceCreation();
          await _showWorkspaceCreationDialog(
            title: 'Workspace not opened',
            message:
                'The workspace was created, but the daemon did not confirm it as the active workspace.',
          );
        }
      case CreateWorkspaceNotConfirmed():
        _workbenchViewModel.cancelWorkspaceCreation();
        setState(() {
          _workbenchViewModel.clearOperationError(notify: false);
        });
        await _showWorkspaceCreationDialog(
          title: 'Workspace not ready',
          message:
              'The workspace was created, but the daemon did not include it in the refreshed list yet.',
        );
      case CreateWorkspaceTimeout():
        _workbenchViewModel.cancelWorkspaceCreation();
        setState(() {
          _workbenchViewModel.clearOperationError(notify: false);
        });
        await _showWorkspaceCreationDialog(
          title: 'Workspace creation timed out',
          message: 'The daemon did not finish creating the workspace in time.',
        );
      case CreateWorkspaceFailure(:final error):
        _workbenchViewModel.cancelWorkspaceCreation();
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
      _clearInitialConversationLoadingGate();
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
    ConversationSummary? restoreConversationAfterExistingSendFailure;
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
        if (!mounted) return;
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
        if (!mounted) return;
        setState(() {
          _workbenchViewModel.updateActiveConversation(conversation,
              notify: false);
          _workbenchViewModel.removeQuestionMessages(notify: false);
        });
      } else {
        if (_isRunningCli) return;
        final sendStartSeq = _workbenchViewModel.lastSeq;
        restoreConversationAfterExistingSendFailure = _activeConversation;
        setState(() {
          _workbenchViewModel.markConversationRunning(notify: false);
        });
        final conversation =
            await _workbenchViewModel.sendExistingConversationPrompt(
          conversationId: existingConversationId,
          prompt: prompt,
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
      if (!mounted) return;
      if (sendAcknowledgementTimedOut) {
        setState(() {
          _workbenchViewModel.clearOperationError(notify: false);
        });
        await _restartConversationEventSubscription();
        return;
      }
      final conversationToRestore = restoreConversationAfterExistingSendFailure;
      final traced = await _recordWorkbenchException(
        err,
        stack,
        operation: 'sendMessage',
      );
      if (!mounted) return;
      setState(() {
        if (_prompt.text.isEmpty && draft.isNotEmpty) {
          _prompt.value = TextEditingValue(
              text: draft,
              selection: TextSelection.collapsed(offset: draft.length));
        }
        if (conversationToRestore != null &&
            conversationToRestore.id == _activeConversationId) {
          _workbenchViewModel.updateActiveConversation(conversationToRestore,
              notify: false);
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

  Future<void> _cancelConversationEventSubscription({
    bool suspendedForBackground = false,
  }) async {
    _cancelBackgroundEventDisconnectTimer();
    _conversationEventsSuspendedForBackground = suspendedForBackground;
    _conversationEventSubscriptionGeneration += 1;
    final subscription = _conversationEventSubscription;
    _conversationEventSubscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // Cleanup is best-effort; cancellation failures must not escape lifecycle changes.
    }
  }

  void _cancelBackgroundEventDisconnectTimer() {
    _backgroundEventDisconnectTimer?.cancel();
    _backgroundEventDisconnectTimer = null;
  }

  // Slice 3 subscription ownership: background preference suspends or keeps the stream.
  void _scheduleBackgroundEventDisconnect() {
    if (widget.dependencies.codingPreferencesRepository
        .keepConversationEventsInBackground) {
      _cancelBackgroundEventDisconnectTimer();
      return;
    }
    if (_conversationEventSubscription == null ||
        _backgroundEventDisconnectTimer != null) {
      return;
    }
    _backgroundEventDisconnectTimer =
        Timer(_backgroundEventDisconnectDelay, () {
      _backgroundEventDisconnectTimer = null;
      unawaited(_cancelConversationEventSubscription(
        suspendedForBackground: true,
      ));
    });
  }

  // Slice 3 subscription ownership: this is the live event subscription owner before controller extraction.
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
      unawaited(_workbenchViewModel
          .recordException(
            message: error.toString(),
            stack: stack.toString(),
            path: '/api/notifications/ws',
            conversationId: conversationId,
            runId: runId,
            operation: 'watchConversationEvents',
          )
          .catchError((Object _) => ''));
    });
  }

  Future<void> _applyConversationEventFromStream(
    ConversationEvent event, {
    required String conversationId,
    required String runId,
    required int generation,
  }) async {
    bool isStillCurrent() => _isCurrentConversationEventTarget(
          conversationId: conversationId,
          runId: runId,
          generation: generation,
        );

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
      _publishApprovalNotificationEvent(event);
      _scrollToBottom();
    }
  }

  void _publishApprovalNotificationEvent(ConversationEvent event) {
    final bus = widget.dependencies.mobileAppEventBus;
    if (bus == null) return;
    final approvalId = event.approvalId;
    final conversation = _workbenchViewModel.activeConversation;
    final conversationId = conversation?.id ?? event.conversationId;
    if (conversationId.isEmpty) return;
    switch (event.type) {
      case 'approval.requested':
        if (approvalId == null || approvalId.isEmpty) return;
        final workspaceId = conversation?.workspaceId ??
            _routeWorkspace?.id ??
            (_workspaces.isNotEmpty ? _workspaces.first.id : '');
        if (workspaceId.isEmpty) return;
        final l10n = AppLocalizations.of(context);
        final body = event.summary?.trim().isNotEmpty == true
            ? event.summary!.trim()
            : event.toolName?.trim().isNotEmpty == true
                ? event.toolName!.trim()
                : l10n.workbenchApprovalCardTitle;
        bus.publish(MobileApprovalRequested(
          workspaceId: workspaceId,
          conversationId: conversationId,
          approvalId: approvalId,
          title: l10n.notificationsApprovalRequired,
          body: body,
          createdAt: event.createdAt,
          conversationTitle: conversation?.title,
          toolName: event.toolName,
          summary: event.summary,
        ));
        break;
      case 'approval.resolved':
      case 'blocking.request_cancelled':
      case 'conversation.completed':
      case 'conversation.cancelled':
      case 'run.error':
        bus.publish(MobileApprovalResolved(
          conversationId: conversationId,
          approvalId: approvalId,
        ));
        break;
    }
  }

  bool _isCurrentConversationEventTarget({
    required String conversationId,
    required String runId,
    required int generation,
  }) =>
      generation == _conversationEventSubscriptionGeneration &&
      mounted &&
      conversationId == _activeConversationId &&
      runId == _activeRunId;

  void _startNewSessionFromList() {
    final workspace = _routeWorkspace;
    if (workspace == null) {
      _goToWorkspaces();
      return;
    }
    _workbenchViewModel.showConversation(workspace.id);
    setState(() {
      _resetConversationState();
      _workbenchViewModel.clearOperationError(notify: false);
      _prompt.clear();
    });
    _goToConversation();
  }

  Future<void> _respondApproval(
    AgentEvent event,
    ApprovalResponse response,
  ) async {
    final approvalId = event.approvalId;
    if (approvalId == null || approvalId.isEmpty) return;
    try {
      final conversationId = _activeConversationId;
      if (conversationId != null) {
        final conversation =
            await _workbenchViewModel.respondConversationApproval(
          conversationId: conversationId,
          approvalId: approvalId,
          response: response,
        );
        _workbenchViewModel.updateActiveConversation(conversation,
            notify: false);
      } else {
        await _workbenchViewModel.respondRunApproval(
          approvalId: approvalId,
          decision: response.legacyDecision,
        );
      }
      setState(() {
        _workbenchViewModel.applyApprovalResponse(
            event, response.legacyDecision,
            notify: false);
      });
      final conversation = _activeConversation;
      if (conversation != null &&
          shouldRestartEventsAfterApproval(conversation)) {
        await _restartConversationEventSubscription();
      }
    } catch (err) {
      _workbenchViewModel.setOperationError(err.toString());
    }
  }

  Future<void> _useQuestionSuggestion(String text) async {
    final conversationId = _activeConversationId;
    final pendingQuestionId = _workbenchViewModel.pendingQuestionId;
    final answer = text.trim();
    if (conversationId == null ||
        pendingQuestionId == null ||
        pendingQuestionId.isEmpty ||
        answer.isEmpty ||
        _sending) {
      setState(() {
        _prompt.text = text;
        _prompt.selection = TextSelection.collapsed(offset: text.length);
      });
      return;
    }
    setState(() {
      _workbenchViewModel.beginOperation(notify: false);
      _workbenchViewModel.addUserMessage(answer, notify: false);
      _prompt.clear();
    });
    _scrollToBottom();
    try {
      final conversation = await _workbenchViewModel.answerConversationQuestion(
        conversationId: conversationId,
        questionId: pendingQuestionId,
        text: answer,
      );
      if (!mounted) return;
      setState(() {
        _workbenchViewModel.updateActiveConversation(conversation,
            notify: false);
        _workbenchViewModel.removeQuestionMessages(notify: false);
      });
      _scrollToBottom();
    } catch (err, stack) {
      final traced = await _recordWorkbenchException(
        err,
        stack,
        operation: 'sendQuestionSuggestion',
      );
      if (!mounted) return;
      setState(() {
        _prompt.value = TextEditingValue(
            text: answer,
            selection: TextSelection.collapsed(offset: answer.length));
        _workbenchViewModel.setOperationError(traced.message,
            traceId: traced.traceId, notify: false);
      });
    } finally {
      if (mounted) _workbenchViewModel.finishOperation();
    }
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

  Widget _buildWorkspaceList() => WorkbenchWorkspaceRoute(
        workspaces: _workspaces,
        onSelected: _openWorkspaceSessions,
        onAddWorkspace: _showCreateWorkspaceFromWorkspaceList,
      );

  Widget _buildSessionList() {
    final workspace = _routeWorkspace;
    if (workspace == null) return _buildWorkspaceList();
    return WorkbenchSessionRoute(
      items: _sessionItems,
      currentWorkspace: workspace,
      onNewSession: _startNewSessionFromList,
      onSelectItem: _openSession,
      onBackToWorkspaces: _returnToWorkspaceList,
    );
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
      return modelPickerUnsupportedDaemonText(context);
    }
    final error = _workbenchViewModel.modelUpdateError?.trim();
    if (error == null || error.isEmpty) return null;
    final normalized = error.toLowerCase();
    if (normalized.contains('current turn') || normalized.contains('active')) {
      return modelPickerBusyText(context);
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
    final pendingApproval = _pendingApprovalMessage();
    final pendingQuestionCanSendAttachments =
        pendingQuestionId == null || pendingQuestionId.isEmpty;
    final canSend = adapter != null &&
        !_sending &&
        canSendInConversationStatus(
            _workbenchViewModel.effectiveConversationStatus) &&
        (pendingQuestionCanSendAttachments ||
            _workbenchViewModel.draftAttachments.isEmpty) &&
        _workbenchViewModel.canSendComposer(text: _prompt.text);
    return WorkbenchConversationRoute(
      title: _conversationTitle(l10n),
      workspace: workspace,
      adapter: adapter,
      modelLabel: modelLabel,
      modelNotice: _modelNoticeLabel(l10n),
      running: _isRunningCli,
      cliLocked: _isConversationAdapterLocked,
      modelLocked: _isModelSelectionLocked,
      canSend: canSend,
      sending: _sending,
      voiceState: _voiceInput.state,
      voiceEnabled:
          widget.speechInputService != null || isVoiceInputPlatformSupported,
      draftAttachments: _workbenchViewModel.draftAttachments,
      slashCommands: _visibleSlashCommands,
      promptController: _prompt,
      messageList:
          _buildMessageList(adapter, l10n, hiddenApproval: pendingApproval),
      approvalPrompt: pendingApproval == null
          ? null
          : ApprovalComposerPrompt(
              message: pendingApproval,
              onApproval: (response) {
                final event = pendingApproval.event;
                if (event != null) {
                  unawaited(_respondApproval(event, response));
                }
              },
            ),
      onBack: () => _navigatorKey.currentState
          ?.popUntil((route) => route.settings.name == _routeSessions),
      onSlashCommandSelected: _insertSlashCommand,
      onAttachmentTap: () => unawaited(_pickAttachments()),
      onRemoveAttachment: _workbenchViewModel.removeDraftAttachment,
      onCliTap: _showAdapterPicker,
      onModelTap: _showModelPicker,
      onVoiceStart: () => unawaited(_startVoiceInput()),
      onVoiceStop: () => unawaited(_stopVoiceInput()),
      onVoiceCancel: () => unawaited(_cancelVoiceInput()),
      onTextChanged: _handleComposerTextChanged,
      onSend: _sendPrompt,
      onCancel: _cancelActiveRun,
      onWorkspaceTap: _showWorkspacePicker,
    );
  }

  String? _modelNoticeLabel(AppLocalizations l10n) =>
      switch (_workbenchViewModel.modelNotice) {
        WorkbenchModelNotice.changedToAvailableOption =>
          l10n.workbenchComposerModelChangedNotice,
        null => null,
      };

  WorkbenchMessage? _pendingApprovalMessage() {
    for (final message in _messages.reversed) {
      if (message.role == 'approval') return message;
    }
    return null;
  }

  Widget _buildMessageList(
    String? adapter,
    AppLocalizations l10n, {
    WorkbenchMessage? hiddenApproval,
  }) {
    _syncTranscriptUnderflow();
    final messages = hiddenApproval == null
        ? _messages
        : _messages
            .where((message) => !identical(message, hiddenApproval))
            .toList(growable: false);
    return WorkbenchMessageList(
      controller: _scrollController,
      messages: messages,
      adapter: adapter,
      runId: _activeRunId,
      eventCount: _conversationEvents.length,
      terminal: _isTerminal,
      runError: _error,
      runErrorTraceId: _errorTraceId,
      pendingStatusText: _pendingStatusText(l10n),
      pendingStartedAt: conversationPendingStartedAt(
          _workbenchViewModel.effectiveConversationStatus, _conversationEvents),
      pendingActions: _recentActionSummaries,
      expandThinking: widget.expandThinking,
      expandToolDetails: widget.expandToolDetails,
      useReverseTranscript: _useReverseTranscript,
      loadingOlderConversationEvents:
          _workbenchViewModel.loadingOlderConversationEvents,
      showPendingDuringInitialConversationLoad:
          _showPendingDuringInitialConversationLoad,
      showStatus: _activeRunId != null,
      showError: _error != null,
      showPending: _isBusyCli &&
          (!_loadingInitialConversationEvents ||
              _showPendingDuringInitialConversationLoad),
      onApproval: _respondApproval,
      onSuggestion: (text) => unawaited(_useQuestionSuggestion(text)),
      onScrollNotification: (_) => false,
    );
  }

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
  return true;
}

String? _normalizedAdapter(String? adapter) {
  final normalized = adapter?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

String _slashLoadKey(String? adapterId, String? workspaceId) {
  final adapter = adapterId ?? '';
  final workspace = (workspaceId ?? '').trim();
  return workspace.isEmpty ? adapter : '$adapter\u0000$workspace';
}

bool _sameSlashCommandList(
  List<SlashCommand> left,
  List<SlashCommand> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].command != right[index].command ||
        left[index].description != right[index].description) {
      return false;
    }
  }
  return true;
}
