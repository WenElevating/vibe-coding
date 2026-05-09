import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/protocol.dart';
import '../../services/asr_model_manager.dart';
import '../../services/daemon_client.dart';
import '../../services/speech_input_service.dart';
import '../../shell/shell.dart';
import '../../state/conversation_reducer.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';
import '../sessions/sessions.dart';
import '../workspace_picker/workspace_picker.dart';
import 'coding_composer.dart';
import 'coding_workbench_controller.dart';
import 'voice_input.dart';
import 'workbench_event_cards.dart';
import 'workbench_messages.dart';

class CodingWorkbenchPage extends StatefulWidget {
  const CodingWorkbenchPage(
      {super.key,
      required this.data,
      required this.client,
      required this.onBack,
      required this.onSessionListChanged,
      required this.openSessionListRequest,
      required this.streamOutput,
      required this.expandThinking,
      required this.permissionMode,
      this.speechInputService,
      this.asrModelManager});
  final AppSnapshot data;
  final DaemonClient client;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;
  final SpeechInputService? speechInputService;
  final AsrModelManager? asrModelManager;

  @override
  State<CodingWorkbenchPage> createState() => CodingWorkbenchPageState();
}

class CodingWorkbenchPageState extends State<CodingWorkbenchPage>
    with WidgetsBindingObserver {
  static const String _routeWorkspaces = 'workspaces';
  static const String _routeSessions = 'sessions';
  static const String _routeConversation = 'conversation';

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _prompt = TextEditingController();
  final _scrollController = ScrollController();
  late final VoiceInputController _voiceInput;
  late final AsrModelManager _asrModelManager;
  late final bool _ownsAsrModelManager;
  SherpaSpeechInputService? _ownedSpeechInputService;
  final List<WorkbenchMessage> _messages = <WorkbenchMessage>[];
  final List<AgentEvent> _events = <AgentEvent>[];
  final List<ConversationEvent> _conversationEvents = <ConversationEvent>[];
  final List<SessionItem> _localSessions = <SessionItem>[];
  late List<WorkspaceSummary> _workspaces;
  Timer? _poller;
  String? _activeRunId;
  String? _activeConversationId;
  ConversationSummary? _activeConversation;
  ConversationViewState _conversationState = const ConversationViewState();
  String? _selectedAdapter;
  late WorkspaceSummary _selectedWorkspace;
  int _lastSeq = 0;
  bool _sending = false;
  String? _error;
  String? _errorTraceId;
  String? _lastVoiceErrorNotice;
  bool _voiceErrorDialogOpen = false;
  bool _workspaceConfirmedForSession = false;
  final Set<String> _resolvedApprovalIds = <String>{};
  String _currentRoute = _routeWorkspaces;
  bool? _lastReportedListOpen = true;
  late int _handledOpenSessionListRequest;

  List<SessionItem> get _sessionItems => mergeSessionItems(
      _localSessions, widget.data.conversations, widget.data.runs);

  void _syncWorkspacesFromSnapshot(List<WorkspaceSummary> snapshot) {
    if (snapshot.isEmpty) return;
    _workspaces = List<WorkspaceSummary>.of(snapshot);
    final stillExists =
        _workspaces.any((workspace) => workspace.id == _selectedWorkspace.id);
    if (stillExists) return;
    _selectedWorkspace = _workspaces.first;
    _resetConversationState();
    _error = null;
    _workspaceConfirmedForSession = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _goToWorkspaces());
  }

  Future<bool> handleSystemBack() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    return navigator.maybePop<void>();
  }

  void showSessionListFromShell() {
    if (_workspaceConfirmedForSession) {
      _goToSessions(_selectedWorkspace);
    } else {
      _goToWorkspaces();
    }
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
    setState(() {
      _selectedWorkspace = workspace;
      _workspaceConfirmedForSession = true;
    });
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        _routeSessions, (route) => route.settings.name == _routeWorkspaces);
  }

  void _goToConversation() {
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        _routeConversation, (route) => route.settings.name == _routeSessions);
  }

  void _rememberRun(RunSummary run) {
    _localSessions.removeWhere((item) => item.id == run.id);
    _localSessions.insert(0, SessionItem(run: run));
  }

  void _rememberConversation(ConversationSummary conversation) {
    _localSessions.removeWhere((item) => item.id == conversation.id);
    _localSessions.insert(
        0,
        SessionItem(
            run: runSummaryFromConversation(conversation),
            conversation: conversation));
  }

  void _resetConversationState() {
    _messages.clear();
    _events.clear();
    _conversationEvents.clear();
    _conversationState = const ConversationViewState();
    _resolvedApprovalIds.clear();
    _activeRunId = null;
    _activeConversationId = null;
    _activeConversation = null;
    _lastSeq = 0;
  }

  Future<void> _openSession(SessionItem item) async {
    _poller?.cancel();
    setState(() {
      _resetConversationState();
      _activeRunId = item.run.id;
      _activeConversationId = item.conversation?.id;
      _activeConversation = item.conversation;
      _selectedWorkspace = _workspaceForId(item.run.workspaceId);
      _workspaceConfirmedForSession = true;
      _error = null;
    });
    if (item.conversation != null) await _pollEvents();
    if (!mounted) return;
    _goToConversation();
    _scrollToBottom(jump: true);
  }

  WorkspaceSummary _workspaceForId(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return _selectedWorkspace;
  }

  Future<void> _cancelActiveRun() async {
    final runId = _activeRunId;
    final conversationId = _activeConversationId;
    if ((runId == null && conversationId == null) || _sending) return;
    setState(() => _sending = true);
    try {
      RunSummary? run;
      ConversationSummary? conversation;
      if (conversationId != null) {
        conversation = await widget.client.cancelConversation(conversationId);
        run = runSummaryFromConversation(conversation);
      } else if (runId != null) {
        run = await widget.client.cancelRun(runId);
      }
      if (!mounted) return;
      setState(() {
        if (conversation != null) {
          final cancelled = applyCancelledConversationSummary(conversation);
          _activeConversation = cancelled;
          _activeConversationId = cancelled.id;
          _activeRunId = run?.id ?? cancelled.id;
          _rememberConversation(cancelled);
          _conversationState = ConversationViewState(
              messages: _conversationState.messages,
              lastSeq: _conversationState.lastSeq,
              status: cancelled.status,
              pendingPartial: _conversationState.pendingPartial);
        } else {
          if (run != null) _rememberRun(run);
          _conversationState = const ConversationViewState(status: 'cancelled');
          _activeRunId = null;
          _activeConversationId = null;
          _activeConversation = null;
        }
        _lastSeq = 0;
      });
      _poller?.cancel();
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    _selectedAdapter = _preferredAdapter()?.adapter;
    _workspaces = List<WorkspaceSummary>.of(widget.data.workspaces);
    _selectedWorkspace = widget.data.workspace;
    final injectedAsrModelManager = widget.asrModelManager;
    _ownsAsrModelManager = injectedAsrModelManager == null;
    _asrModelManager = injectedAsrModelManager ??
        AsrModelManager(client: widget.client.createAsrModelClient());
    _voiceInput = VoiceInputController(service: _createSpeechInputService())
      ..addListener(_syncVoicePreviewText);
    _syncWorkspacesFromSnapshot(widget.data.workspaces);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setCurrentRoute(_routeWorkspaces);
    });
  }

  @override
  void didUpdateWidget(covariant CodingWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWorkspacesFromSnapshot(widget.data.workspaces);
    _syncSelectedAdapterFromSnapshot();
    if (widget.openSessionListRequest == _handledOpenSessionListRequest) return;
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showSessionListFromShell();
    });
  }

  void _syncSelectedAdapterFromSnapshot() {
    final selected = _selectedAdapter;
    final selectedStillAvailable = selected != null &&
        widget.data.adapters
            .any((adapter) => adapter.adapter == selected && adapter.available);
    if (selectedStillAvailable) return;
    _selectedAdapter = _preferredAdapter()?.adapter;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    if (_voiceInput.isBusy) unawaited(_voiceInput.cancel());
    _voiceInput.removeListener(_syncVoicePreviewText);
    _voiceInput.dispose();
    if (_ownsAsrModelManager) _asrModelManager.dispose();
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
      final preview = _voiceInput.previewText();
      if (preview != _prompt.text) {
        _prompt.value = TextEditingValue(
            text: preview,
            selection: TextSelection.collapsed(offset: preview.length));
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
    if (widget.speechInputService == null) {
      final modelDirectory = await _showAsrDownloadDialog();
      if (modelDirectory == null || !mounted) return;
      final nextService =
          SherpaSpeechInputService(modelDirectory: modelDirectory);
      _ownedSpeechInputService = nextService;
      _voiceInput.updateService(nextService);
    }
    await _voiceInput.start(currentPrompt: _prompt.text);
  }

  Future<String?> _showAsrDownloadDialog() {
    return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _AsrModelDownloadDialog(manager: _asrModelManager));
  }

  Future<void> _stopVoiceInput() async {
    final merged = await _voiceInput.stop(currentPrompt: _prompt.text);
    if (!mounted) return;
    _prompt.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length));
    setState(() {});
  }

  Future<void> _cancelVoiceInput() async {
    await _voiceInput.cancel();
    if (!mounted) return;
    final restored = _voiceInput.restoreBaseText();
    if (_prompt.text != restored) {
      _prompt.value = TextEditingValue(
          text: restored,
          selection: TextSelection.collapsed(offset: restored.length));
    }
    setState(() {});
  }

  AdapterStatus? _preferredAdapter() {
    for (final name in const ['claude', 'codex', 'opencode']) {
      final found = widget.data.adapters.where((a) =>
          a.adapter == name && a.available && _isSelectableCliAdapter(a));
      if (found.isNotEmpty) return found.first;
    }
    final available = widget.data.adapters
        .where((a) => a.available && _isSelectableCliAdapter(a));
    return available.isEmpty ? null : available.first;
  }

  bool get _isTerminal {
    final status = _activeConversation?.status ?? _conversationState.status;
    return !isActiveConversationStatus(status);
  }

  bool get _isRunningCli =>
      _activeConversationId != null &&
      (_activeConversation?.status ?? _conversationState.status) == 'running';

  bool get _isBusyCli =>
      _activeConversationId != null &&
      isActiveConversationStatus(
          _activeConversation?.status ?? _conversationState.status) &&
      (_activeConversation?.status ?? _conversationState.status) !=
          'waiting_input' &&
      (_activeConversation?.status ?? _conversationState.status) !=
          'waiting_approval';

  List<AdapterStatus> get _availableAdapters => widget.data.adapters
      .where((adapter) => adapter.available && _isSelectableCliAdapter(adapter))
      .toList();

  void _showAdapterPicker() {
    final adapters = _availableAdapters;
    if (adapters.isEmpty || _isRunningCli) return;
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AdapterPickerSheet(
            adapters: adapters,
            selected: _selectedAdapter,
            onSelected: (adapter) {
              setState(() => _selectedAdapter = adapter);
              Navigator.of(context).pop();
            }));
  }

  void _showWorkspacePicker() => _openWorkspaceList();

  Future<void> _showCreateWorkspaceFromWorkspaceList() async {
    final workspace = await showModalBottomSheet<WorkspaceSummary>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AddWorkspaceSheet(client: widget.client));
    if (workspace == null || !mounted) return;
    try {
      final daemonWorkspaces = await widget.client.listWorkspaces();
      if (!mounted) return;
      setState(() {
        final next = replaceWorkspacesFromDaemon(
          CodingWorkbenchState(
            workspaces: _workspaces,
            selectedWorkspace: _selectedWorkspace,
            listMode: CodingWorkbenchListMode.workspaces,
          ),
          daemonWorkspaces,
          selectedWorkspaceId: workspace.id,
        );
        _workspaces = next.workspaces;
        _selectedWorkspace = next.selectedWorkspace;
        _workspaceConfirmedForSession = true;
        _resetConversationState();
        _error = null;
      });
      _goToWorkspaces();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Workspace ready: ${workspace.name}'),
          duration: const Duration(seconds: 2)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            'Workspace was saved, but the list could not be refreshed: $error';
      });
      _goToWorkspaces();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Workspace saved. Refresh workspaces to see it.'),
          duration: Duration(seconds: 3)));
    }
  }

  String _pendingStatusText(AppLocalizations l10n) =>
      _conversationPendingStatusText(
          l10n,
          _activeConversation?.status ?? _conversationState.status,
          _conversationEvents);

  String _conversationPendingStatusText(AppLocalizations l10n, String status,
      Iterable<ConversationEvent> events) {
    return conversationPendingStatusText(l10n, status, events);
  }

  List<String> get _recentActionSummaries {
    return const <String>[];
  }

  // ignore: unused_element
  String? _eventActionSummary(AgentEvent event) {
    if (event.type == 'run.started') {
      return 'Started ${event.raw['tool'] ?? _selectedAdapter ?? 'CLI'} session';
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

  void _scrollToBottom({bool jump = false, int retries = 2}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        if (retries > 0) _scrollToBottom(jump: jump, retries: retries - 1);
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
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

  Future<void> _sendPrompt() async {
    final prompt = _prompt.text.trim();
    final draft = _prompt.text;
    final adapter = _selectedAdapter;
    if (prompt.isEmpty || adapter == null || _sending) return;
    final pendingQuestion = _conversationState.messages
        .cast<ConversationMessage?>()
        .lastWhere(
            (message) =>
                message?.role == 'question' ||
                message?.role == 'question_hidden',
            orElse: () => null);
    final pendingQuestionId = pendingQuestion?.questionId;
    if (_activeRunId == null && !_hasExplicitWorkspaceSelection) {
      _goToWorkspaces();
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _messages.add(WorkbenchMessage.user(prompt));
      _prompt.clear();
    });
    _scrollToBottom();
    try {
      final existingConversationId = _activeConversationId;
      if (existingConversationId == null) {
        final conversation = await widget.client.createConversation(
            workspaceId: _selectedWorkspace.id,
            adapter: adapter,
            permissionMode: widget.permissionMode);
        final run = runSummaryFromConversation(conversation);
        final runningConversation =
            copyConversationStatus(conversation, 'running');
        setState(() {
          _activeConversation = runningConversation;
          _rememberConversation(runningConversation);
          _activeRunId = run.id;
          _activeConversationId = conversation.id;
          _lastSeq = 0;
          _events.clear();
          _resolvedApprovalIds.clear();
        });
        if (mounted) _goToConversation();
        final send =
            widget.client.sendConversationMessage(conversation.id, prompt);
        await _restartConversationPolling();
        final updated = await send;
        if (mounted) setState(() => _activeConversation = updated);
      } else if (pendingQuestionId != null && pendingQuestionId.isNotEmpty) {
        final conversation = await widget.client.answerConversationQuestion(
            existingConversationId, pendingQuestionId, prompt);
        setState(() {
          _activeConversation = conversation;
          _rememberConversation(conversation);
          _messages.removeWhere((message) => message.role == 'question');
        });
      } else {
        if (_isRunningCli) return;
        setState(() {
          if (_activeConversation != null) {
            _activeConversation =
                copyConversationStatus(_activeConversation!, 'running');
            _rememberConversation(_activeConversation!);
          }
          _events.removeWhere((event) => event.type == 'run.completed');
        });
        final send = widget.client
            .sendConversationMessage(existingConversationId, prompt);
        await _restartConversationPolling();
        final conversation = await send;
        if (mounted) {
          setState(() {
            _activeConversation = conversation;
            _rememberConversation(conversation);
          });
        }
      }
      _scrollToBottom();
    } catch (err, stack) {
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
        _error = traced.message;
        _errorTraceId = traced.traceId;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pollEvents() async {
    final runId = _activeRunId;
    final conversationId = _activeConversationId;
    if (runId == null || conversationId == null) {
      _poller?.cancel();
      return;
    }
    try {
      final conversationEvents = await widget.client
          .fetchConversationEvents(conversationId, afterSeq: _lastSeq);
      if (conversationEvents.isEmpty || !mounted) return;
      setState(() {
        for (final event in conversationEvents) {
          _conversationEvents.add(event);
          if (event.seq > _lastSeq) _lastSeq = event.seq;
          _applyConversationStatusEvent(event);
        }
        _conversationState = _conversationState.apply(conversationEvents,
            streamOutput: widget.streamOutput);
        _messages
          ..clear()
          ..addAll(messagesForConversationSnapshot(
                  _conversationState.messages, _activeConversation)
              .where((message) => message.role != 'question_hidden')
              .map(workbenchMessageFromConversation));
        final emptyCompletionDiagnostic = emptyConversationCompletionDiagnostic(
            _conversationEvents, _conversationState.messages, _isTerminal);
        if (emptyCompletionDiagnostic != null) {
          _messages.add(WorkbenchMessage.status(emptyCompletionDiagnostic));
        }
      });
      _scrollToBottom();
      if (!_isRunningCli) _poller?.cancel();
    } catch (err, stack) {
      final traced = await _recordWorkbenchException(
        err,
        stack,
        operation: 'pollConversationEvents',
        path: '/api/conversations/$conversationId/events?afterSeq=$_lastSeq',
      );
      if (mounted) {
        setState(() {
          _error = traced.message;
          _errorTraceId = traced.traceId;
        });
      }
      _poller?.cancel();
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
      final trace = await widget.client.recordException(
        message: message,
        stack: stack.toString(),
        path: path,
        method: path == null ? null : 'GET',
        conversationId: _activeConversationId,
        runId: _activeRunId,
        metadata: <String, Object?>{'operation': operation},
      );
      return _WorkbenchTraceError(message, trace.traceId);
    } catch (_) {
      return _WorkbenchTraceError(message, null);
    }
  }

  Future<void> _restartConversationPolling() async {
    _poller?.cancel();
    await _pollEvents();
    if (!mounted ||
        _activeConversationId == null ||
        !isActiveConversationStatus(
            _activeConversation?.status ?? _conversationState.status)) {
      return;
    }
    _poller =
        Timer.periodic(const Duration(milliseconds: 900), (_) => _pollEvents());
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
          input: event.input);
    } else if (event.type == 'approval.requested') {
      status = 'waiting_approval';
      blockingItem = ConversationBlockingItem(
          type: 'approval_request',
          approvalId: event.approvalId,
          toolUseId: event.toolUseId,
          toolName: event.toolName,
          summary: event.summary,
          input: event.input);
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
    _activeConversation =
        copyConversationStatus(current, status, blockingItem: blockingItem);
  }

  // ignore: unused_element
  void _mergeEventMessage(AgentEvent event) {
    if (event.type == 'approval.responded') {
      final approvalId = event.approvalId ?? event.raw['approvalId'] as String?;
      if (approvalId != null && approvalId.isNotEmpty) {
        _resolvedApprovalIds.add(approvalId);
        _messages.removeWhere((item) =>
            item.role == 'approval' && item.event?.approvalId == approvalId);
      }
      final command = _approvalResolvedCommand(event);
      if (command != null) {
        final exists = _messages.any((item) =>
            item.role == 'command' &&
            item.runId == event.runId &&
            item.body.trim() == command.trim());
        if (!exists) {
          _upsertCommandMessage(WorkbenchMessage(
              'command', 'cwd resolved · permissions checked', command,
              event: event, runId: event.runId));
        }
      }
      return;
    }
    if (isTerminalAgentEventType(event.type)) {
      _markCommandMessagesCompleted(event);
    }
    final message = WorkbenchMessage.fromEvent(event, widget.streamOutput);
    if (message == null) return;
    if (message.role == 'approval' &&
        message.event?.approvalId != null &&
        _resolvedApprovalIds.contains(message.event!.approvalId)) {
      return;
    }
    if (message.role == 'approval') {
      final approvalId = message.event?.approvalId;
      final messageKey = approvalId ?? message.body.trim();
      final existingIndex = _messages.indexWhere((item) {
        if (item.role != 'approval') return false;
        final itemKey = item.event?.approvalId ?? item.body.trim();
        return itemKey == messageKey;
      });
      if (existingIndex >= 0) {
        _messages[existingIndex] = message;
      } else {
        _messages.add(message);
      }
      return;
    }
    if (message.role == 'assistant_stream') {
      final lastIndex = _messages.lastIndexWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      if (lastIndex >= 0) {
        final current = _messages[lastIndex];
        _messages[lastIndex] =
            current.copyWith(body: current.body + message.body);
      } else {
        _messages.add(message);
      }
      return;
    }
    if (message.role == 'assistant') {
      _messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      _messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      final sameRunIndex = _messages.lastIndexWhere(
          (item) => item.role == 'assistant' && item.runId == event.runId);
      if (sameRunIndex >= 0) {
        _messages[sameRunIndex] = message;
      } else {
        final exists = _messages.any((item) =>
            item.role == 'assistant' &&
            item.body.trim() == message.body.trim());
        if (!exists) _messages.add(message);
      }
      return;
    }
    if (message.role == 'question') {
      final hasAssistantForRun = _messages
          .any((item) => item.role == 'assistant' && item.runId == event.runId);
      if (hasAssistantForRun) return;
      _messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      _messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      _messages.add(message);
      return;
    }
    if (message.role == 'command') {
      _upsertCommandMessage(message.copyWith(
          completed: _isTerminal,
          duration: _commandDurationFor(
              message.runId ?? event.runId, event.createdAt)));
      return;
    }
    _messages.add(message);
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
          duration: message.duration ?? current.duration);
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

  void _markCommandMessagesCompleted(AgentEvent terminalEvent) {
    for (var index = 0; index < _messages.length; index += 1) {
      final message = _messages[index];
      if (message.role != 'command' || message.runId != terminalEvent.runId) {
        continue;
      }
      _messages[index] = message.copyWith(
          completed: true,
          duration:
              _commandDurationFor(message.runId, terminalEvent.createdAt));
    }
  }

  Duration? _commandDurationFor(String? runId, DateTime completedAt) {
    if (runId == null) return null;
    AgentEvent? started;
    for (final event in _events) {
      if (event.runId == runId && event.type == 'run.started') {
        started = event;
        break;
      }
    }
    started ??= _events
        .cast<AgentEvent?>()
        .firstWhere((event) => event?.runId == runId, orElse: () => null);
    if (started == null || completedAt.isBefore(started.createdAt)) return null;
    return completedAt.difference(started.createdAt);
  }

  bool get _hasExplicitWorkspaceSelection {
    return hasExplicitWorkspaceSelectionState(
      workspaceConfirmedForSession: _workspaceConfirmedForSession,
      activeRunId: _activeRunId,
      hasLocalSessions: _localSessions.isNotEmpty,
    );
  }

  void _startNewSessionFromList() {
    setState(() {
      _resetConversationState();
      _error = null;
      _workspaceConfirmedForSession = true;
      _prompt.clear();
    });
    _goToConversation();
  }

  String? _approvalResolvedCommand(AgentEvent event) {
    final decision = event.raw['decision'];
    if (decision != 'allow') return null;
    final input = event.raw['input'];
    if (input is Map<String, Object?>) {
      final command = input['command'];
      if (command is String && command.trim().isNotEmpty) return command.trim();
      final target = input['file_path'] ?? input['path'] ?? input['filename'];
      if (target is String && target.trim().isNotEmpty) {
        return '${event.name ?? 'Tool'} ${target.trim()}';
      }
    }
    final text = event.text;
    return text == null || text.trim().isEmpty ? null : text.trim();
  }

  Future<void> _respondApproval(AgentEvent event, String decision) async {
    final approvalId = event.approvalId;
    if (approvalId == null || approvalId.isEmpty) return;
    try {
      final conversationId = _activeConversationId;
      if (conversationId != null) {
        final conversation = await widget.client
            .respondConversationApproval(conversationId, approvalId, decision);
        _activeConversation = conversation;
        _rememberConversation(conversation);
      } else {
        await widget.client.respondApproval(approvalId, decision);
      }
      setState(() {
        _resolvedApprovalIds.add(approvalId);
        _messages.removeWhere((item) =>
            item.role == 'approval' && item.event?.approvalId == approvalId);
        if (decision == 'allow') {
          _upsertCommandMessage(WorkbenchMessage(
              'command',
              'cwd resolved · permissions checked',
              WorkbenchMessage.toolEventBody(event),
              event: event,
              runId: event.runId));
        } else {
          _messages.add(WorkbenchMessage.status('Denied permission request'));
        }
      });
      final conversation = _activeConversation;
      if (conversation != null && shouldPollAfterApproval(conversation)) {
        await _restartConversationPolling();
      }
    } catch (err) {
      setState(() => _error = err.toString());
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
    if (route == _routeSessions) return _buildSessionList();
    if (route == _routeConversation) return _buildConversationDetail();
    return _buildWorkspaceList();
  }

  Widget _buildWorkspaceList() => WorkspaceListPage(
      workspaces: _workspaces,
      selected: _selectedWorkspace,
      onSelected: _openWorkspaceSessions,
      onAddWorkspace: _showCreateWorkspaceFromWorkspaceList);

  Widget _buildSessionList() => CodingSessionListPage(
      data: widget.data,
      items: _sessionItems,
      currentWorkspace: _selectedWorkspace,
      onNewSession: _startNewSessionFromList,
      onSelectItem: _openSession,
      onBackToWorkspaces: _returnToWorkspaceList);

  Widget _buildConversationDetail() {
    final l10n = AppLocalizations.of(context);
    final adapter = _selectedAdapter;
    final canSend = adapter != null &&
        !_sending &&
        canSendInConversationStatus(
            _activeConversation?.status ?? _conversationState.status);
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
              workspace: _selectedWorkspace,
              adapter: adapter,
              running: _isRunningCli,
              onBack: () => _navigatorKey.currentState?.popUntil(
                  (route) => route.settings.name == _routeSessions))),
      Expanded(
          child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
        children: [
          if (_activeRunId != null) ...[
            WorkbenchInlineStatus(
                adapter: adapter,
                runId: _activeRunId,
                eventCount: _conversationEvents.length,
                terminal: _isTerminal),
            const SizedBox(height: 12),
          ],
          for (final message in _messages) ...[
            WorkbenchMessageCard(
                message: message,
                expandThinking: widget.expandThinking,
                onSuggestion: (text) => _useQuestionSuggestion(text),
                onApproval: (decision) =>
                    _respondApproval(message.event!, decision)),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            GlassCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                  color: theme.muted,
                                  fontSize: 12,
                                  height: 1.35)),
                          TinyActionButton('Copy Trace ID', onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await Clipboard.setData(
                                ClipboardData(text: _errorTraceId!));
                            messenger.showSnackBar(const SnackBar(
                                content: Text('Trace ID copied')));
                          })
                        ])
                  ]
                ])),
          ],
          if (_isBusyCli) ...[
            const SizedBox(height: 10),
            PendingSentinel(
                adapter: adapter ?? 'CLI',
                statusText: _pendingStatusText(l10n),
                actions: _recentActionSummaries),
          ],
        ],
      )),
      CodingComposer(
          controller: _prompt,
          adapter: adapter,
          workspace: _selectedWorkspace,
          running: _isRunningCli,
          canSend: canSend,
          sending: _sending,
          voiceState: _voiceInput.state,
          voiceEnabled: widget.speechInputService != null ||
              isVoiceInputPlatformSupported,
          voiceError: null,
          onModelTap: _showAdapterPicker,
          onVoiceStart: () => unawaited(_startVoiceInput()),
          onVoiceStop: () => unawaited(_stopVoiceInput()),
          onVoiceCancel: () => unawaited(_cancelVoiceInput()),
          onSend: _sendPrompt,
          onCancel: _cancelActiveRun),
      ComposerWorkspaceCloud(
          workspace: _selectedWorkspace,
          running: _isRunningCli,
          onTap: _showWorkspacePicker),
    ]);
  }

  String _conversationTitle(AppLocalizations l10n) {
    final userMessage = _messages.where((message) => message.role == 'user');
    if (userMessage.isEmpty) return l10n.workbenchNewSessionTitle;
    final text = userMessage.last.body.trim();
    if (text.length <= 18) return text;
    return '${text.substring(0, 18)}…';
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
