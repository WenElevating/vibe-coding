import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/protocol.dart';
import '../../services/daemon_client.dart';
import '../../shell/shell.dart';
import '../../state/conversation_reducer.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';
import '../sessions/sessions.dart';
import '../workspace_picker/workspace_picker.dart';
import 'coding_composer.dart';
import 'coding_workbench_controller.dart';
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
      required this.permissionMode});
  final AppSnapshot data;
  final DaemonClient client;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  State<CodingWorkbenchPage> createState() => CodingWorkbenchPageState();
}

class CodingWorkbenchPageState extends State<CodingWorkbenchPage> {
  final _prompt = TextEditingController();
  final _scrollController = ScrollController();
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
  bool _workspaceConfirmedForSession = false;
  final Set<String> _resolvedApprovalIds = <String>{};
  CodingWorkbenchListMode _listMode = CodingWorkbenchListMode.workspaces;
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
    _listMode = CodingWorkbenchListMode.workspaces;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSessionListChanged(true);
    });
  }

  bool get _isListOpen => _listMode != CodingWorkbenchListMode.conversation;

  void _setSessionListOpen(bool open) {
    final nextMode = open
        ? CodingWorkbenchListMode.sessions
        : CodingWorkbenchListMode.conversation;
    if (_listMode == nextMode) return;
    setState(() => _listMode = nextMode);
    widget.onSessionListChanged(open);
  }

  void _openWorkspaceList() {
    if (_isRunningCli) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('CLI is running; workspace cannot be switched right now'),
          duration: Duration(seconds: 2)));
      return;
    }
    setState(() => _listMode = CodingWorkbenchListMode.workspaces);
    widget.onSessionListChanged(true);
  }

  void _openWorkspaceSessions(WorkspaceSummary workspace) {
    setState(() {
      _selectedWorkspace = workspace;
      _workspaceConfirmedForSession = true;
      _listMode = CodingWorkbenchListMode.sessions;
    });
    widget.onSessionListChanged(true);
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
      _listMode = CodingWorkbenchListMode.conversation;
    });
    widget.onSessionListChanged(false);
    if (item.conversation == null) return;
    await _pollEvents();
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
      if (conversationId != null) {
        final conversation =
            await widget.client.cancelConversation(conversationId);
        run = runSummaryFromConversation(conversation);
      } else if (runId != null) {
        run = await widget.client.cancelRun(runId);
      }
      if (!mounted) return;
      setState(() {
        if (run != null) _rememberRun(run);
        _conversationState = const ConversationViewState(status: 'cancelled');
        _activeRunId = null;
        _activeConversationId = null;
        _activeConversation = null;
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
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    _selectedAdapter = _preferredAdapter()?.adapter;
    _workspaces = List<WorkspaceSummary>.of(widget.data.workspaces);
    _selectedWorkspace = widget.data.workspace;
    _syncWorkspacesFromSnapshot(widget.data.workspaces);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSessionListChanged(_isListOpen);
    });
  }

  @override
  void didUpdateWidget(covariant CodingWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWorkspacesFromSnapshot(widget.data.workspaces);
    if (widget.openSessionListRequest == _handledOpenSessionListRequest) return;
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    if (_isListOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setSessionListOpen(true);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _scrollController.dispose();
    _prompt.dispose();
    super.dispose();
  }

  AdapterStatus? _preferredAdapter() {
    for (final name in const ['claude', 'codex', 'opencode']) {
      final found =
          widget.data.adapters.where((a) => a.adapter == name && a.available);
      if (found.isNotEmpty) return found.first;
    }
    final available = widget.data.adapters.where((a) => a.available);
    return available.isEmpty ? null : available.first;
  }

  bool get _isTerminal {
    final status = _activeConversation?.status ?? _conversationState.status;
    return status == 'idle' ||
        status == 'failed' ||
        status == 'cancelled' ||
        status == 'interrupted' ||
        status == 'expired';
  }

  bool get _isRunningCli =>
      _activeConversationId != null &&
      (_activeConversation?.status ?? _conversationState.status) == 'running';

  bool get _isBusyCli =>
      _activeConversationId != null &&
      !_isTerminal &&
      (_activeConversation?.status ?? _conversationState.status) !=
          'waiting_input' &&
      (_activeConversation?.status ?? _conversationState.status) !=
          'waiting_approval';

  List<AdapterStatus> get _availableAdapters =>
      widget.data.adapters.where((adapter) => adapter.available).toList();

  void _showAdapterPicker() {
    final adapters = _availableAdapters;
    if (adapters.isEmpty || _isRunningCli) return;
    showModalBottomSheet<void>(
        context: context,
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
            listMode: _listMode,
          ),
          daemonWorkspaces,
          selectedWorkspaceId: workspace.id,
        );
        _workspaces = next.workspaces;
        _selectedWorkspace = next.selectedWorkspace;
        _listMode = CodingWorkbenchListMode.workspaces;
        _workspaceConfirmedForSession = true;
        _resetConversationState();
        _error = null;
      });
      widget.onSessionListChanged(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Workspace ready: ${workspace.name}'),
          duration: const Duration(seconds: 2)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            'Workspace was saved, but the list could not be refreshed: $error';
        _listMode = CodingWorkbenchListMode.workspaces;
      });
      widget.onSessionListChanged(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Workspace saved. Refresh workspaces to see it.'),
          duration: Duration(seconds: 3)));
    }
  }

  String get _pendingStatusText => _conversationPendingStatusText(
      _activeConversation?.status ?? _conversationState.status,
      _conversationEvents);

  String _conversationPendingStatusText(
      String status, Iterable<ConversationEvent> events) {
    return conversationPendingStatusText(status, events);
  }

  List<String> get _recentActionSummaries {
    return const <String>[];
  }

  // ignore: unused_element
  String? _eventActionSummary(AgentEvent event) {
    if (event.type == 'run.started') {
      return '已启动 ${event.raw['tool'] ?? _selectedAdapter ?? 'CLI'} 会话';
    }
    if (event.type == 'approval.required') return '等待权限确认';
    if (event.type == 'tool.started') {
      final name = event.name ?? _toolNameFromRaw(event) ?? '工具';
      final target = _toolTargetFromRaw(event);
      return target == null ? '调用 $name' : '调用 $name：$target';
    }
    if (event.type == 'tool.output') {
      final target = _toolTargetFromRaw(event);
      return target == null ? '工具返回结果' : '处理完成：$target';
    }
    if (event.type == 'diff.summary' && event.diff != null) {
      return '修改 ${event.diff!.filePath}  +${event.diff!.additions} -${event.diff!.deletions}';
    }
    if (event.type == 'raw.output') {
      final text = event.text?.trim();
      if (text == null || text.isEmpty || text.startsWith('{')) return null;
      return text.length > 64 ? '${text.substring(0, 64)}…' : text;
    }
    if (event.type == 'run.completed') return '本轮运行完成';
    if (event.type == 'run.failed') return '运行失败';
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendPrompt() async {
    final prompt = _prompt.text.trim();
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
      setState(() => _listMode = CodingWorkbenchListMode.workspaces);
      widget.onSessionListChanged(true);
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
        setState(() {
          _activeConversation = conversation;
          _rememberConversation(conversation);
          _activeRunId = run.id;
          _activeConversationId = conversation.id;
          _lastSeq = 0;
          _events.clear();
          _resolvedApprovalIds.clear();
        });
        final updated = await widget.client
            .sendConversationMessage(conversation.id, prompt);
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
        final conversation = await widget.client
            .sendConversationMessage(existingConversationId, prompt);
        setState(() {
          _activeConversation = conversation;
          _rememberConversation(conversation);
          _events.removeWhere((event) => event.type == 'run.completed');
        });
      }
      _scrollToBottom();
      await _restartConversationPolling();
    } catch (err) {
      setState(() => _error = err.toString());
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
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    }
  }

  Future<void> _restartConversationPolling() async {
    _poller?.cancel();
    await _pollEvents();
    if (!mounted || _activeConversationId == null || _isTerminal) return;
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
    } else if (event.type == 'assistant.message') {
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
      status = 'cancelled';
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
      _listMode = CodingWorkbenchListMode.conversation;
    });
    widget.onSessionListChanged(false);
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
          _messages.add(WorkbenchMessage.status('已拒绝权限请求'));
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
    if (_listMode == CodingWorkbenchListMode.workspaces) {
      return WorkspaceListPage(
          workspaces: _workspaces,
          selected: _selectedWorkspace,
          onSelected: _openWorkspaceSessions,
          onAddWorkspace: _showCreateWorkspaceFromWorkspaceList);
    }
    if (_listMode == CodingWorkbenchListMode.sessions) {
      return CodingSessionListPage(
          data: widget.data,
          items: _sessionItems,
          currentWorkspace: _selectedWorkspace,
          onNewSession: _startNewSessionFromList,
          onSelectItem: _openSession,
          onBackToWorkspaces: _openWorkspaceList);
    }
    final adapter = _selectedAdapter;
    final canSend = adapter != null && !_sending;
    return Column(key: const ValueKey('coding-workbench-detail'), children: [
      Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
          decoration: BoxDecoration(
              color: const Color(0xEE0A0B0D),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: .075)))),
          child: _CodingHeader(
              title: _conversationTitle,
              workspace: _selectedWorkspace,
              adapter: adapter,
              running: _isRunningCli,
              onBack: () => _setSessionListOpen(true))),
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
                child: Text('运行错误：$_error',
                    style: const TextStyle(
                        color: theme.red, fontSize: 12, height: 1.45))),
          ],
          if (_isBusyCli) ...[
            const SizedBox(height: 10),
            PendingSentinel(
                adapter: adapter ?? 'CLI',
                statusText: _pendingStatusText,
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
          onModelTap: _showAdapterPicker,
          onSend: _sendPrompt,
          onCancel: _cancelActiveRun),
      ComposerWorkspaceCloud(
          workspace: _selectedWorkspace,
          running: _isRunningCli,
          onTap: _showWorkspacePicker),
    ]);
  }

  String get _conversationTitle {
    final userMessage = _messages.where((message) => message.role == 'user');
    if (userMessage.isEmpty) return '新的编码会话';
    final text = userMessage.last.body.trim();
    if (text.length <= 18) return text;
    return '${text.substring(0, 18)}…';
  }
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
