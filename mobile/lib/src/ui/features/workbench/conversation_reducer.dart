import '../../../models/protocol.dart';

class ConversationMessage {
  const ConversationMessage({
    required this.role,
    required this.text,
    this.eventSeq,
    this.questionId,
    this.approvalId,
    this.toolUseId,
    this.toolName,
    this.summary,
    this.taskId,
    this.source,
    this.taskItems = const <TaskProgressItem>[],
    this.completedCount,
    this.totalCount,
    this.input = const <String, Object?>{},
    this.completed = false,
    this.startedAt,
    this.completedAt,
    this.output,
    this.exitCode,
    this.isError = false,
    this.suggestions = const <String>[],
    this.attachments = const <CommittedAttachment>[],
    this.clientMessageId,
    this.fileChanges = const <ConversationFileChange>[],
  });

  final String role;
  final String text;
  final int? eventSeq;
  final String? questionId;
  final String? approvalId;
  final String? toolUseId;
  final String? toolName;
  final String? summary;
  final String? taskId;
  final String? source;
  final List<TaskProgressItem> taskItems;
  final int? completedCount;
  final int? totalCount;
  final Map<String, Object?> input;
  final bool completed;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? output;
  final int? exitCode;
  final bool isError;
  final List<String> suggestions;
  final List<CommittedAttachment> attachments;
  final String? clientMessageId;
  final List<ConversationFileChange> fileChanges;
}

class ConversationFileChange {
  const ConversationFileChange({
    required this.path,
    required this.kind,
    this.diff,
  });

  final String path;
  final String kind;
  final String? diff;
}

class ConversationViewState {
  const ConversationViewState({
    this.messages = const <ConversationMessage>[],
    this.lastSeq = 0,
    this.status = 'idle',
    this.pendingPartial = '',
  });

  final List<ConversationMessage> messages;
  final int lastSeq;
  final String status;
  final String pendingPartial;

  ConversationViewState apply(Iterable<ConversationEvent> events,
      {bool streamOutput = false}) {
    final iterator = events.iterator;
    if (!iterator.moveNext()) return this;
    final firstEvent = iterator.current;
    if (!iterator.moveNext()) {
      if (firstEvent.seq <= lastSeq) return this;
      if (firstEvent.type == 'assistant.partial') {
        return _applySingleAssistantPartial(firstEvent,
            streamOutput: streamOutput);
      }
      return _applyFreshEvents(<ConversationEvent>[firstEvent],
          streamOutput: streamOutput);
    }
    final newEvents = <ConversationEvent>[];
    if (firstEvent.seq > lastSeq) newEvents.add(firstEvent);
    final secondEvent = iterator.current;
    if (secondEvent.seq > lastSeq) newEvents.add(secondEvent);
    while (iterator.moveNext()) {
      final event = iterator.current;
      if (event.seq > lastSeq) newEvents.add(event);
    }
    if (newEvents.isEmpty) return this;
    if (newEvents.length == 1 && newEvents.single.type == 'assistant.partial') {
      return _applySingleAssistantPartial(newEvents.single,
          streamOutput: streamOutput);
    }
    newEvents.sort((a, b) => a.seq.compareTo(b.seq));
    return _applyFreshEvents(newEvents, streamOutput: streamOutput);
  }

  ConversationViewState _applySingleAssistantPartial(
    ConversationEvent event, {
    required bool streamOutput,
  }) {
    final partial = _mergeAssistantPartial(pendingPartial, event.text ?? '');
    if (!streamOutput || partial.trim().isEmpty) {
      return ConversationViewState(
        messages: messages,
        lastSeq: event.seq,
        status: status,
        pendingPartial: partial,
      );
    }
    final streamMessage = ConversationMessage(
        role: 'assistant_stream', text: partial, eventSeq: event.seq);
    final streamIndex =
        messages.indexWhere((message) => message.role == 'assistant_stream');
    if (streamIndex < 0) {
      return ConversationViewState(
        messages: <ConversationMessage>[...messages, streamMessage],
        lastSeq: event.seq,
        status: status,
        pendingPartial: partial,
      );
    }
    final nextMessages = List<ConversationMessage>.of(messages);
    nextMessages[streamIndex] = streamMessage;
    return ConversationViewState(
      messages: nextMessages,
      lastSeq: event.seq,
      status: status,
      pendingPartial: partial,
    );
  }

  ConversationViewState _applyFreshEvents(
    List<ConversationEvent> newEvents, {
    required bool streamOutput,
  }) {
    final nextMessages = <ConversationMessage>[...messages];
    var nextSeq = lastSeq;
    var nextStatus = status;
    var partial = pendingPartial;
    for (final event in newEvents) {
      if (event.seq <= nextSeq) continue;
      nextSeq = event.seq;
      switch (event.type) {
        case 'conversation.status_changed':
          nextStatus = event.raw['status'] as String? ?? nextStatus;
          break;
        case 'assistant.thinking':
          if ((event.text ?? '').trim().isNotEmpty) {
            _upsertThinkingMessage(
                nextMessages,
                ConversationMessage(
                    role: 'thinking', text: event.text!, eventSeq: event.seq));
          }
          break;
        case 'user.message':
          nextMessages.add(ConversationMessage(
              role: 'user',
              text: event.text ?? '',
              eventSeq: event.seq,
              attachments: event.attachments,
              clientMessageId: event.raw['clientMessageId'] as String?));
          break;
        case 'assistant.partial':
          partial = _mergeAssistantPartial(partial, event.text ?? '');
          if (streamOutput && partial.trim().isNotEmpty) {
            _upsertAssistantStreamMessage(
                nextMessages,
                ConversationMessage(
                    role: 'assistant_stream',
                    text: partial,
                    eventSeq: event.seq));
          }
          break;
        case 'assistant.message':
          final text = event.text ?? partial;
          nextMessages
              .removeWhere((message) => message.role == 'assistant_stream');
          if (text.trim().isNotEmpty) {
            _upsertAssistantMessage(
                nextMessages,
                ConversationMessage(
                    role: 'assistant', text: text, eventSeq: event.seq));
          }
          partial = '';
          if (conversationEventCompletesTurn(event)) nextStatus = 'idle';
          break;
        case 'assistant.question':
          final hadPartialContext = partial.trim().isNotEmpty;
          if (partial.trim().isNotEmpty &&
              !nextMessages.any((message) =>
                  message.role == 'assistant' && message.text == partial)) {
            nextMessages
                .removeWhere((message) => message.role == 'assistant_stream');
            _upsertAssistantMessage(
                nextMessages,
                ConversationMessage(
                    role: 'assistant', text: partial, eventSeq: event.seq));
          }
          partial = '';
          final isFallbackQuestion =
              hadPartialContext && _isFallbackQuestionText(event.text);
          nextMessages.add(ConversationMessage(
            role: isFallbackQuestion ? 'question_hidden' : 'question',
            text: event.text ?? '',
            eventSeq: event.seq,
            questionId: event.questionId,
            suggestions: event.suggestions,
          ));
          nextStatus = 'waiting_input';
          break;
        case 'task.progress.updated':
          final taskId = event.taskId;
          if (taskId == null || taskId.isEmpty || event.taskItems.isEmpty) {
            break;
          }
          final existing = _existingTaskProgress(nextMessages, taskId);
          final taskItems = _mergeTaskProgressItems(
              existing?.taskItems ?? const <TaskProgressItem>[],
              event.taskItems,
              preserveMissing: event.source == 'claude' &&
                  taskId == 'claude_tasks' &&
                  existing != null);
          final completedCount =
              taskItems.where((item) => item.status == 'completed').length;
          _upsertTaskProgressMessage(
              nextMessages,
              ConversationMessage(
                role: 'task_progress',
                text: 'Task Progress',
                eventSeq: event.seq,
                taskId: taskId,
                source: event.source,
                taskItems: taskItems,
                completedCount:
                    existing == null ? event.completedCount : completedCount,
                totalCount:
                    existing == null ? event.totalCount : taskItems.length,
              ));
          break;
        case 'approval.requested':
          nextMessages.removeWhere((message) =>
              message.role == 'approval' &&
              message.approvalId == event.approvalId);
          nextMessages.add(ConversationMessage(
            role: 'approval',
            text: event.summary ?? event.toolName ?? 'Approval required',
            eventSeq: event.seq,
            approvalId: event.approvalId,
            toolUseId: event.toolUseId,
            toolName: event.toolName,
            summary: event.summary,
            input: event.input,
          ));
          nextStatus = 'waiting_approval';
          break;
        case 'approval.resolved':
          nextMessages.removeWhere((message) =>
              message.role == 'approval' &&
              message.approvalId == event.approvalId);
          if ((event.raw['decision'] as String?) == 'allow') {
            final command = _approvalCommandText(event);
            if (command != null) {
              _upsertCommandMessage(
                  nextMessages,
                  ConversationMessage(
                      role: 'command',
                      text: command,
                      eventSeq: event.seq,
                      approvalId: event.approvalId,
                      toolUseId: event.toolUseId,
                      toolName: event.toolName,
                      summary: event.summary,
                      input: event.input,
                      startedAt: event.createdAt));
            }
          }
          nextStatus = 'running';
          break;
        case 'blocking.request_cancelled':
          final approvalId = event.approvalId;
          final questionId = event.questionId;
          nextMessages.removeWhere((message) =>
              (approvalId != null &&
                  message.role == 'approval' &&
                  message.approvalId == approvalId) ||
              (questionId != null &&
                  (message.role == 'question' ||
                      message.role == 'question_hidden') &&
                  message.questionId == questionId));
          nextStatus = 'running';
          break;
        case 'system.notice':
          if (event.raw['visible'] == false) break;
          if (isHiddenSystemNotice(event)) break;
          if (isTransitionSystemNotice(event)) break;
          if (isCodexFileChangeNotice(event)) {
            nextMessages.add(ConversationMessage(
              role: 'file_change',
              text: event.text ?? event.summary ?? '',
              eventSeq: event.seq,
              fileChanges: conversationFileChangesFromEvent(event),
            ));
            break;
          }
          nextMessages.add(ConversationMessage(
            role: 'notice',
            text: event.text ?? event.summary ?? '',
            eventSeq: event.seq,
          ));
          break;
        case 'tool.started':
          final toolUseId = event.toolUseId;
          if (toolUseId == null || toolUseId.isEmpty) break;
          if (_isHiddenClaudeToolEvent(event)) {
            _removeCommandMessage(nextMessages, event);
            break;
          }
          if (_isClaudeTaskToolEvent(event)) {
            _upsertClaudeTaskProgressFromTool(nextMessages, event);
            break;
          }
          _upsertCommandMessage(
              nextMessages,
              ConversationMessage(
                role: 'command',
                text: _toolCommandText(event),
                eventSeq: event.seq,
                toolUseId: toolUseId,
                toolName: event.toolName,
                summary: event.summary,
                input: event.input,
                startedAt: event.createdAt,
              ));
          break;
        case 'tool.delta':
        case 'tool.output':
          if (_isAskUserQuestionEvent(event)) {
            _removeCommandMessage(nextMessages, event);
            break;
          }
          if (_isClaudeTaskToolEvent(event)) {
            _upsertClaudeTaskProgressFromTool(nextMessages, event);
            break;
          }
          if (_isExitPlanModePromptEvent(event)) {
            _removeCommandMessage(nextMessages, event);
            _upsertQuestionMessage(
                nextMessages,
                ConversationMessage(
                  role: 'question',
                  text: event.text ?? 'Exit plan mode?',
                  eventSeq: event.seq,
                  questionId: event.toolUseId,
                  toolUseId: event.toolUseId,
                  toolName: event.toolName,
                  input: event.input,
                  suggestions: const ['批准计划并继续', '调整计划'],
                ));
            break;
          }
          if (_isExitPlanModeEvent(event)) {
            _removeCommandMessage(nextMessages, event);
            break;
          }
          if (_toolOutputCompletesCommand(event)) {
            _completeCommandMessage(nextMessages, event);
          } else {
            _appendCommandOutput(nextMessages, event);
          }
          break;
        case 'tool.completed':
          if (_isHiddenClaudeToolEvent(event) ||
              _isClaudeTaskToolEvent(event)) {
            _removeCommandMessage(nextMessages, event);
            break;
          }
          _completeCommandMessage(nextMessages, event);
          break;
        case 'conversation.completed':
          _completeCommandMessages(nextMessages, event);
          nextStatus = 'idle';
          partial = '';
          break;
        case 'conversation.cancelled':
          _completeCommandMessages(nextMessages, event);
          nextStatus = 'cancelled';
          partial = '';
          break;
        case 'run.error':
          _completeCommandMessages(nextMessages, event);
          final errorText = _runErrorText(event);
          if (errorText != null) {
            nextMessages.add(ConversationMessage(
              role: 'notice',
              text: errorText,
              eventSeq: event.seq,
              isError: true,
            ));
          }
          nextStatus = 'failed';
          partial = '';
          break;
        case 'conversation.started':
          // Lifecycle marker — no UI state change needed.
          break;
        case 'protocol.warning':
          if (event.raw['visible'] != true) break;
          if (event.text != null && event.text!.isNotEmpty) {
            nextMessages.add(ConversationMessage(
              role: 'notice',
              text: event.text!,
              eventSeq: event.seq,
              isError: event.isError || isAuthenticationProtocolWarning(event),
            ));
          }
          break;
        case 'turn.completed':
        case 'conversation.cancel':
        case 'conversation.cancel_error':
        case 'conversation.approval':
        case 'conversation.message':
        case 'conversation.question_answer':
          // Internal audit/lifecycle events — no UI state change needed.
          break;
        default:
          assert(false, 'Unknown conversation event type: ${event.type}');
      }
    }
    return ConversationViewState(
      messages: nextMessages,
      lastSeq: nextSeq,
      status: nextStatus,
      pendingPartial: partial,
    );
  }
}

bool isHiddenSystemNotice(ConversationEvent event) {
  if (event.type != 'system.notice') return false;
  final noticeKind = '${event.raw['noticeKind'] ?? ''}'.toLowerCase();
  if (noticeKind == 'codex_unknown_event') return true;
  final text = (event.text ?? event.summary ?? '').toLowerCase();
  return text.startsWith('codex event:');
}

bool isTransitionSystemNotice(ConversationEvent event) {
  if (event.type != 'system.notice') return false;
  final noticeKind = '${event.raw['noticeKind'] ?? ''}'.toLowerCase();
  if (noticeKind.contains('reconnect')) return true;
  final text = (event.text ?? event.summary ?? '').toLowerCase();
  if (text.contains('reconnecting')) return true;
  if (text.contains('stream disconnected')) return true;
  if (text.contains('stream closed before response.completed')) return true;
  return false;
}

bool isCodexFileChangeNotice(ConversationEvent event) {
  if (event.type != 'system.notice') return false;
  return '${event.raw['noticeKind'] ?? ''}'.toLowerCase() ==
      'codex_file_change';
}

bool isAuthenticationProtocolWarning(ConversationEvent event) {
  if (event.type != 'protocol.warning') return false;
  final subtype = '${_protocolRawField(event, 'subtype') ?? ''}'.toLowerCase();
  final status = '${_protocolRawField(event, 'error_status') ?? ''}'.trim();
  final error = '${_protocolRawField(event, 'error') ?? ''}'.toLowerCase();
  final text = (event.text ?? event.summary ?? '').toLowerCase();
  if (subtype == 'api_retry' && (status == '401' || error.contains('auth'))) {
    return true;
  }
  return text.contains('claude api 401') ||
      text.contains('authentication_failed') ||
      text.contains('authentication failed');
}

Object? _protocolRawField(ConversationEvent event, String key) {
  final nested = event.raw['raw'];
  if (nested is Map && nested.containsKey(key)) return nested[key];
  return event.raw[key];
}

List<ConversationFileChange> conversationFileChangesFromEvent(
    ConversationEvent event) {
  final changes = event.raw['changes'];
  if (changes is! Iterable) return const <ConversationFileChange>[];
  final parsed = <ConversationFileChange>[];
  for (final item in changes) {
    if (item is! Map) continue;
    final path = item['path'];
    if (path is! String || path.trim().isEmpty) continue;
    final kind = item['kind'];
    final diff = item['diff'];
    parsed.add(ConversationFileChange(
      path: path.trim(),
      kind: kind is String && kind.trim().isNotEmpty ? kind.trim() : 'change',
      diff: diff is String && diff.trim().isNotEmpty ? diff : null,
    ));
  }
  return parsed.isEmpty
      ? const <ConversationFileChange>[]
      : List<ConversationFileChange>.unmodifiable(parsed);
}

void _upsertCommandMessage(
    List<ConversationMessage> messages, ConversationMessage command) {
  final existingIndex = _commandIndexForCorrelation(messages,
      toolUseId: command.toolUseId, approvalId: command.approvalId);
  if (existingIndex >= 0) {
    final current = messages[existingIndex];
    messages[existingIndex] = ConversationMessage(
      role: command.role,
      text: command.text,
      eventSeq: command.eventSeq,
      questionId: current.questionId,
      approvalId: command.approvalId,
      toolUseId: command.toolUseId ?? current.toolUseId,
      toolName: command.toolName ?? current.toolName,
      summary: command.summary ?? current.summary,
      input: command.input.isNotEmpty ? command.input : current.input,
      completed: current.completed || command.completed,
      startedAt: current.startedAt ?? command.startedAt,
      completedAt: command.completedAt ?? current.completedAt,
      output: command.output ?? current.output,
      exitCode: command.exitCode ?? current.exitCode,
      isError: current.isError || command.isError,
      suggestions: command.suggestions,
    );
  } else {
    messages.add(command);
  }
}

void _upsertQuestionMessage(
    List<ConversationMessage> messages, ConversationMessage question) {
  final questionId = question.questionId;
  final existingIndex = questionId == null || questionId.isEmpty
      ? -1
      : messages.indexWhere((message) =>
          message.role == 'question' && message.questionId == questionId);
  if (existingIndex >= 0) {
    messages[existingIndex] = question;
  } else {
    messages.add(question);
  }
}

void _removeCommandMessage(
    List<ConversationMessage> messages, ConversationEvent event) {
  final index = _commandIndexForToolUseId(messages, event.toolUseId);
  if (index >= 0) messages.removeAt(index);
}

bool _isExitPlanModeEvent(ConversationEvent event) =>
    (event.toolName ?? '').toLowerCase() == 'exitplanmode';

bool _isAskUserQuestionEvent(ConversationEvent event) =>
    (event.toolName ?? '').toLowerCase() == 'askuserquestion';

bool _isHiddenClaudeToolEvent(ConversationEvent event) =>
    _isExitPlanModeEvent(event) || _isAskUserQuestionEvent(event);

bool _isExitPlanModePromptEvent(ConversationEvent event) {
  if (!_isExitPlanModeEvent(event)) return false;
  final text = (event.text ?? event.summary ?? '').trim().toLowerCase();
  return text == 'exit plan mode?';
}

bool _isClaudeTaskToolEvent(ConversationEvent event) {
  final toolName = (event.toolName ?? '').toLowerCase();
  return toolName == 'taskcreate' || toolName == 'taskupdate';
}

void _upsertClaudeTaskProgressFromTool(
    List<ConversationMessage> messages, ConversationEvent event) {
  final toolName = (event.toolName ?? '').toLowerCase();
  final input = event.input;
  final taskId = _claudeTaskIdForToolEvent(event);
  if (taskId == null || taskId.isEmpty) return;
  final existing = _existingClaudeTaskProgress(messages);
  final existingItems = existing?.taskItems ?? const <TaskProgressItem>[];
  final items = List<TaskProgressItem>.from(existingItems);
  final index = items.indexWhere((item) => item.id == taskId);
  if (toolName == 'taskcreate') {
    final created = _claudeTaskCreateResult(event);
    final title = created.title ?? _claudeTaskTitleForCreate(event);
    if (title.isEmpty) return;
    final existingByToolUseId = event.toolUseId == null
        ? -1
        : items.indexWhere((item) => item.id == event.toolUseId);
    final effectiveTaskId = created.id ?? taskId;
    if (created.id != null &&
        existingByToolUseId >= 0 &&
        items[existingByToolUseId].id != effectiveTaskId) {
      items.removeAt(existingByToolUseId);
    }
    final effectiveIndex =
        items.indexWhere((item) => item.id == effectiveTaskId);
    final incoming = TaskProgressItem(
        id: effectiveTaskId,
        title: title,
        status: _normalizeClaudeTaskStatus(input['status']));
    if (effectiveIndex >= 0) {
      items[effectiveIndex] = incoming;
    } else {
      items.add(incoming);
    }
  } else if (toolName == 'taskupdate') {
    final previous = index >= 0 ? items[index] : null;
    final title = previous?.title ?? _claudeTaskTitleForUpdate(event, taskId);
    final incoming = TaskProgressItem(
        id: taskId,
        title: title,
        status: _normalizeClaudeTaskStatus(input['status']));
    if (index >= 0) {
      items[index] = incoming;
    } else {
      items.add(incoming);
    }
  }
  final completed = items.where((item) => item.status == 'completed').length;
  _upsertTaskProgressMessage(
      messages,
      ConversationMessage(
        role: 'task_progress',
        text: 'Task Progress',
        eventSeq: event.seq,
        taskId: 'claude_tasks',
        source: 'claude',
        taskItems: items,
        completedCount: completed,
        totalCount: items.length,
      ));
}

ConversationMessage? _existingClaudeTaskProgress(
    List<ConversationMessage> messages) {
  return _existingTaskProgress(messages, 'claude_tasks');
}

ConversationMessage? _existingTaskProgress(
    List<ConversationMessage> messages, String taskId) {
  final index = messages.indexWhere(
      (message) => message.role == 'task_progress' && message.taskId == taskId);
  return index < 0 ? null : messages[index];
}

String? _claudeTaskIdForToolEvent(ConversationEvent event) {
  final input = event.input;
  final id = input['taskId'] ?? input['id'] ?? event.toolUseId;
  if (id == null) return null;
  final text = id.toString().trim();
  return text.isEmpty ? null : text;
}

String _claudeTaskTitleForCreate(ConversationEvent event) {
  final input = event.input;
  for (final key in const <String>['subject', 'title', 'description']) {
    final value = input[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return (event.summary ?? event.toolUseId ?? '').trim();
}

String _claudeTaskTitleForUpdate(ConversationEvent event, String taskId) {
  final input = event.input;
  for (final key in const <String>['subject', 'title']) {
    final value = input[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return 'Task #$taskId';
}

({String? id, String? title}) _claudeTaskCreateResult(ConversationEvent event) {
  final text = (event.text ?? event.summary ?? '').trim();
  if (text.isEmpty) return (id: null, title: null);
  final match = RegExp(r'task\s*#?\s*([A-Za-z0-9_-]+)', caseSensitive: false)
      .firstMatch(text);
  final id = match?.group(1);
  String? title;
  final colonIndex = text.indexOf(':');
  if (colonIndex >= 0 && colonIndex < text.length - 1) {
    final parsed = text.substring(colonIndex + 1).trim();
    if (parsed.isNotEmpty) title = parsed;
  }
  return (id: id, title: title);
}

String _normalizeClaudeTaskStatus(Object? status) {
  final value = status?.toString().trim().toLowerCase() ?? '';
  if (value == 'completed' ||
      value == 'complete' ||
      value == 'done' ||
      value == 'success') {
    return 'completed';
  }
  if (value == 'in_progress' ||
      value == 'in-progress' ||
      value == 'running' ||
      value == 'active') {
    return 'in_progress';
  }
  return 'pending';
}

void _upsertAssistantStreamMessage(
    List<ConversationMessage> messages, ConversationMessage streamMessage) {
  final index =
      messages.indexWhere((message) => message.role == 'assistant_stream');
  if (index < 0) {
    messages.add(streamMessage);
    return;
  }
  messages[index] = streamMessage;
}

void _appendCommandOutput(
    List<ConversationMessage> messages, ConversationEvent event) {
  final output = event.text ?? event.summary;
  if (output == null || output.trim().isEmpty) return;
  final index = _commandIndexForToolUseId(messages, event.toolUseId);
  if (index < 0) return;
  final command = messages[index];
  messages[index] = ConversationMessage(
    role: command.role,
    text: command.text,
    eventSeq: event.seq,
    questionId: command.questionId,
    approvalId: command.approvalId,
    toolUseId: command.toolUseId,
    toolName: command.toolName,
    summary: command.summary,
    input: command.input,
    completed: command.completed,
    startedAt: command.startedAt,
    completedAt: command.completedAt,
    output: _mergeCommandOutput(command.output, output.trim()),
    exitCode: event.exitCode ?? command.exitCode,
    isError: command.isError || event.isError,
    suggestions: command.suggestions,
  );
}

bool _toolOutputCompletesCommand(ConversationEvent event) {
  if (event.type != 'tool.output') return false;
  final rawEvent = event.raw['raw'];
  if (rawEvent is! Map<String, Object?>) return false;
  if (rawEvent['type'] != 'item.completed') return false;
  final item = rawEvent['item'];
  return item is Map<String, Object?> && item['type'] == 'command_execution';
}

void _completeCommandMessage(
    List<ConversationMessage> messages, ConversationEvent event) {
  final index = _commandIndexForToolUseId(messages, event.toolUseId);
  if (index < 0) return;
  final command = messages[index];
  final output = event.text ?? event.summary;
  messages[index] = ConversationMessage(
    role: command.role,
    text: command.text,
    eventSeq: event.seq,
    questionId: command.questionId,
    approvalId: command.approvalId,
    toolUseId: command.toolUseId,
    toolName: command.toolName,
    summary: command.summary,
    input: command.input,
    completed: true,
    startedAt: command.startedAt,
    completedAt: event.createdAt,
    output: output == null || output.trim().isEmpty
        ? command.output
        : _mergeCommandOutput(command.output, output.trim()),
    exitCode: event.exitCode ?? command.exitCode,
    isError: command.isError || event.isError,
    suggestions: command.suggestions,
  );
}

void _completeCommandMessages(
    List<ConversationMessage> messages, ConversationEvent event) {
  for (var index = 0; index < messages.length; index++) {
    final command = messages[index];
    if (command.role != 'command' || command.completed) continue;
    messages[index] = ConversationMessage(
      role: command.role,
      text: command.text,
      eventSeq: event.seq,
      questionId: command.questionId,
      approvalId: command.approvalId,
      toolUseId: command.toolUseId,
      toolName: command.toolName,
      summary: command.summary,
      input: command.input,
      completed: true,
      startedAt: command.startedAt,
      completedAt: event.createdAt,
      output: command.output,
      exitCode: command.exitCode,
      isError: command.isError || event.isError,
      suggestions: command.suggestions,
    );
  }
}

int _commandIndexForCorrelation(List<ConversationMessage> messages,
    {String? toolUseId, String? approvalId}) {
  final toolIndex = _commandIndexForToolUseId(messages, toolUseId);
  if (toolIndex >= 0) return toolIndex;
  if (approvalId == null || approvalId.isEmpty) return -1;
  return messages.indexWhere((message) =>
      message.role == 'command' && message.approvalId == approvalId);
}

int _commandIndexForToolUseId(
    List<ConversationMessage> messages, String? toolUseId) {
  if (toolUseId == null || toolUseId.isEmpty) return -1;
  return messages.indexWhere(
      (message) => message.role == 'command' && message.toolUseId == toolUseId);
}

String _mergeCommandOutput(String? current, String incoming) {
  final existing = current?.trim();
  if (existing == null || existing.isEmpty) return incoming;
  if (existing.contains(incoming)) return existing;
  if (incoming.contains(existing)) return incoming;
  return '$existing\n$incoming';
}

String? _approvalCommandText(ConversationEvent event) {
  final command = event.input['command'];
  if (command is String && command.trim().isNotEmpty) return command.trim();
  final summary = event.summary;
  if (summary != null && summary.trim().isNotEmpty) return summary.trim();
  final file = event.input['file_path'] ??
      event.input['path'] ??
      event.input['filename'];
  if (file is String && file.trim().isNotEmpty) {
    final toolName = event.toolName ?? 'Tool';
    return '$toolName ${file.trim()}';
  }
  return null;
}

String? _runErrorText(ConversationEvent event) {
  final message = event.raw['message'];
  final text =
      event.text ?? event.summary ?? (message is String ? message : null);
  final value = text?.trim();
  if (value == null || value.isEmpty) return null;
  return 'Run error: $value';
}

String _toolCommandText(ConversationEvent event) {
  final command = event.input['command'];
  if (command is String && command.trim().isNotEmpty) return command.trim();
  final file = event.input['file_path'] ??
      event.input['path'] ??
      event.input['filename'];
  if (file is String && file.trim().isNotEmpty) {
    return '${event.toolName ?? 'Tool'} ${file.trim()}';
  }
  final summary = event.summary;
  if (summary != null && summary.trim().isNotEmpty) return summary.trim();
  return event.toolName ?? 'Tool';
}

void _upsertThinkingMessage(
    List<ConversationMessage> messages, ConversationMessage incoming) {
  final text = incoming.text.trim();
  if (text.isEmpty) return;
  final lastIndex =
      messages.lastIndexWhere((message) => message.role == 'thinking');
  if (lastIndex < 0 || lastIndex != messages.length - 1) {
    messages.add(incoming);
    return;
  }
  final current = messages[lastIndex].text.trim();
  if (current.isEmpty) {
    messages[lastIndex] = incoming;
    return;
  }
  if (current.contains(text)) return;
  final merged = text.contains(current) ? text : '$current\n\n$text';
  messages[lastIndex] = ConversationMessage(
      role: 'thinking', text: merged, eventSeq: incoming.eventSeq);
}

void _upsertTaskProgressMessage(
    List<ConversationMessage> messages, ConversationMessage incoming) {
  final taskId = incoming.taskId;
  if (taskId == null || taskId.isEmpty) return;
  final index = messages.indexWhere(
      (message) => message.role == 'task_progress' && message.taskId == taskId);
  if (index < 0) {
    messages.add(incoming);
    return;
  }
  messages[index] = incoming;
}

List<TaskProgressItem> _mergeTaskProgressItems(
  List<TaskProgressItem> existing,
  List<TaskProgressItem> incoming, {
  bool preserveMissing = false,
}) {
  if (existing.isEmpty) return incoming;
  final existingById = <String, TaskProgressItem>{
    for (final item in existing) item.id: item
  };
  final merged = <TaskProgressItem>[];
  final incomingIds = <String>{};
  for (final item in incoming) {
    incomingIds.add(item.id);
    final previous = existingById[item.id];
    final title = _isFallbackTaskTitle(item) && previous != null
        ? previous.title
        : item.title;
    merged
        .add(TaskProgressItem(id: item.id, title: title, status: item.status));
  }
  if (preserveMissing) {
    for (final item in existing) {
      if (!incomingIds.contains(item.id)) merged.add(item);
    }
  }
  return merged;
}

bool _isFallbackTaskTitle(TaskProgressItem item) {
  return item.title.trim() == 'Task #${item.id}';
}

String _mergeAssistantPartial(String current, String incoming) {
  if (incoming.isEmpty) return current;
  if (current.isEmpty) return incoming;
  if (incoming.startsWith(current)) return incoming;
  if (current.endsWith(incoming)) return current;
  return current + incoming;
}

void _upsertAssistantMessage(
    List<ConversationMessage> messages, ConversationMessage incoming) {
  final text = incoming.text.trim();
  if (text.isEmpty) return;
  final lastAssistantIndex = messages.lastIndexWhere((message) =>
      message.role == 'assistant' || message.role == 'assistant_stream');
  if (lastAssistantIndex >= 0) {
    final current = messages[lastAssistantIndex].text.trim();
    if (text.contains(current) || current.contains(text)) {
      messages[lastAssistantIndex] = incoming;
      return;
    }
  }
  messages.add(incoming);
}

bool _isFallbackQuestionText(String? text) {
  final value = text?.trim();
  return value == null ||
      value.isEmpty ||
      value == 'Needs more information.' ||
      value == 'Need more information.';
}
