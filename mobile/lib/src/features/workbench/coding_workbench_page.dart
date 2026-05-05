part of '../../app/app.dart';

class _CodingWorkbenchPage extends StatefulWidget {
  const _CodingWorkbenchPage(
      {required this.data,
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
  State<_CodingWorkbenchPage> createState() => _CodingWorkbenchPageState();
}

enum _WorkbenchListMode { workspaces, sessions, conversation }

class _CodingWorkbenchPageState extends State<_CodingWorkbenchPage> {
  final _prompt = TextEditingController();
  final _scrollController = ScrollController();
  final List<_WorkbenchMessage> _messages = <_WorkbenchMessage>[];
  final List<AgentEvent> _events = <AgentEvent>[];
  final List<ConversationEvent> _conversationEvents = <ConversationEvent>[];
  final List<_SessionItem> _localSessions = <_SessionItem>[];
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
  _WorkbenchListMode _listMode = _WorkbenchListMode.workspaces;
  late int _handledOpenSessionListRequest;

  List<_SessionItem> get _sessionItems => _mergeSessionItems(
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
    _listMode = _WorkbenchListMode.workspaces;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSessionListChanged(true);
    });
  }

  bool get _isListOpen => _listMode != _WorkbenchListMode.conversation;

  void _setSessionListOpen(bool open) {
    final nextMode =
        open ? _WorkbenchListMode.sessions : _WorkbenchListMode.conversation;
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
    setState(() => _listMode = _WorkbenchListMode.workspaces);
    widget.onSessionListChanged(true);
  }

  void _openWorkspaceSessions(WorkspaceSummary workspace) {
    setState(() {
      _selectedWorkspace = workspace;
      _workspaceConfirmedForSession = true;
      _listMode = _WorkbenchListMode.sessions;
    });
    widget.onSessionListChanged(true);
  }

  void _rememberRun(RunSummary run) {
    _localSessions.removeWhere((item) => item.id == run.id);
    _localSessions.insert(0, _SessionItem(run: run));
  }

  void _rememberConversation(ConversationSummary conversation) {
    _localSessions.removeWhere((item) => item.id == conversation.id);
    _localSessions.insert(
        0,
        _SessionItem(
            run: _runSummaryFromConversation(conversation),
            conversation: conversation));
  }

  void _upsertWorkspace(WorkspaceSummary workspace) {
    final index = _workspaces.indexWhere((item) => item.id == workspace.id);
    if (index >= 0) {
      _workspaces[index] = workspace;
    } else {
      _workspaces.add(workspace);
    }
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

  Future<void> _openSession(_SessionItem item) async {
    _poller?.cancel();
    setState(() {
      _resetConversationState();
      _activeRunId = item.run.id;
      _activeConversationId = item.conversation?.id;
      _activeConversation = item.conversation;
      _selectedWorkspace = _workspaceForId(item.run.workspaceId);
      _workspaceConfirmedForSession = true;
      _error = null;
      _listMode = _WorkbenchListMode.conversation;
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
        run = _runSummaryFromConversation(conversation);
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
  void didUpdateWidget(covariant _CodingWorkbenchPage oldWidget) {
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
        builder: (context) => _AdapterPickerSheet(
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
        builder: (context) => _AddWorkspaceSheet(client: widget.client));
    if (workspace == null || !mounted) return;
    setState(() {
      _upsertWorkspace(workspace);
      _selectedWorkspace = workspace;
      _workspaceConfirmedForSession = true;
      _listMode = _WorkbenchListMode.sessions;
      _resetConversationState();
      _error = null;
    });
    widget.onSessionListChanged(true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Workspace ready: ${workspace.name}'),
        duration: const Duration(seconds: 2)));
  }

  String get _pendingStatusText => _conversationPendingStatusText(
      _activeConversation?.status ?? _conversationState.status,
      _conversationEvents);

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
      setState(() => _listMode = _WorkbenchListMode.workspaces);
      widget.onSessionListChanged(true);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _messages.add(_WorkbenchMessage.user(prompt));
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
        final run = _runSummaryFromConversation(conversation);
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
          ..addAll(_messagesForConversationSnapshot(
                  _conversationState.messages, _activeConversation)
              .where((message) => message.role != 'question_hidden')
              .map(_workbenchMessageFromConversation));
        final emptyCompletionDiagnostic =
            _emptyConversationCompletionDiagnostic(
                _conversationEvents, _conversationState.messages, _isTerminal);
        if (emptyCompletionDiagnostic != null) {
          _messages.add(_WorkbenchMessage.status(emptyCompletionDiagnostic));
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
        _copyConversationStatus(current, status, blockingItem: blockingItem);
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
          _upsertCommandMessage(_WorkbenchMessage(
              'command', 'cwd resolved · permissions checked', command,
              event: event, runId: event.runId));
        }
      }
      return;
    }
    if (isTerminalAgentEventType(event.type)) {
      _markCommandMessagesCompleted(event);
    }
    final message = _WorkbenchMessage.fromEvent(event, widget.streamOutput);
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

  void _upsertCommandMessage(_WorkbenchMessage message) {
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
    return debugSameCommandDisplay(current, incoming);
  }

  String _preferDetailedCommand(String current, String incoming) {
    return debugPreferDetailedCommand(current, incoming);
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
    return _hasExplicitWorkspaceSelectionState(
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
      _listMode = _WorkbenchListMode.conversation;
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
          _upsertCommandMessage(_WorkbenchMessage(
              'command',
              'cwd resolved · permissions checked',
              _WorkbenchMessage._toolEventBody(event),
              event: event,
              runId: event.runId));
        } else {
          _messages.add(_WorkbenchMessage.status('已拒绝权限请求'));
        }
      });
      final conversation = _activeConversation;
      if (conversation != null && _shouldPollAfterApproval(conversation)) {
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
    if (_listMode == _WorkbenchListMode.workspaces) {
      return _WorkspaceListPage(
          workspaces: _workspaces,
          selected: _selectedWorkspace,
          onSelected: _openWorkspaceSessions,
          onAddWorkspace: _showCreateWorkspaceFromWorkspaceList);
    }
    if (_listMode == _WorkbenchListMode.sessions) {
      return _CodingSessionListPage(
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
            _WorkbenchInlineStatus(
                adapter: adapter,
                runId: _activeRunId,
                eventCount: _conversationEvents.length,
                terminal: _isTerminal),
            const SizedBox(height: 12),
          ],
          for (final message in _messages) ...[
            _WorkbenchMessageCard(
                message: message,
                expandThinking: widget.expandThinking,
                onSuggestion: (text) => _useQuestionSuggestion(text),
                onApproval: (decision) =>
                    _respondApproval(message.event!, decision)),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            _GlassCard(
                child: Text('运行错误：$_error',
                    style: const TextStyle(
                        color: _red, fontSize: 12, height: 1.45))),
          ],
          if (_isBusyCli) ...[
            const SizedBox(height: 10),
            _PendingSentinel(
                adapter: adapter ?? 'CLI',
                statusText: _pendingStatusText,
                actions: _recentActionSummaries),
          ],
        ],
      )),
      _CodingComposer(
          controller: _prompt,
          adapter: adapter,
          workspace: _selectedWorkspace,
          running: _isRunningCli,
          canSend: canSend,
          sending: _sending,
          onModelTap: _showAdapterPicker,
          onSend: _sendPrompt,
          onCancel: _cancelActiveRun),
      _ComposerWorkspaceCloud(
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
                    border: Border.all(color: _stroke)),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: _muted, size: 16))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.15))),
        const SizedBox(width: 46),
      ]);
}
