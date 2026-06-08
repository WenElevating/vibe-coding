import 'dart:convert';

import '../../../../l10n/app_localizations.dart';
import '../../../data/models/approval_models.dart';
import '../../../models/protocol.dart';
import 'conversation_reducer.dart';

bool shouldRestartEventsAfterApproval(ConversationSummary conversation) =>
    conversation.status == 'running' || conversation.status == 'waiting_input';

bool hasExplicitWorkspaceSelectionState({
  required bool workspaceConfirmedForSession,
  required String? activeRunId,
  required bool hasLocalSessions,
}) =>
    workspaceConfirmedForSession || activeRunId != null;

String conversationPendingStatusText(
    AppLocalizations l10n, String status, Iterable<ConversationEvent> events) {
  if (status == 'interrupted') return l10n.workbenchPendingInterrupted;
  if (status == 'waiting_input') return l10n.workbenchPendingWaitingInput;
  if (status == 'waiting_approval') {
    return l10n.workbenchPendingWaitingApproval;
  }
  if (status != 'running' && status != 'sending') return '';
  final list = events.toList(growable: false);
  if (list.isEmpty) return l10n.workbenchPendingStarting;
  final activeToolUseIds = <String>{};
  for (final event in list) {
    final toolUseId = event.toolUseId;
    if (toolUseId == null || toolUseId.isEmpty) continue;
    if (event.type == 'tool.started') {
      activeToolUseIds.add(toolUseId);
    } else if (event.type == 'tool.completed') {
      activeToolUseIds.remove(toolUseId);
    }
  }
  var toolCompletionSeen = false;
  for (final event in list.reversed) {
    final toolUseId = event.toolUseId;
    final hasToolUseId = toolUseId != null && toolUseId.isNotEmpty;
    final activeTool = hasToolUseId && activeToolUseIds.contains(toolUseId);
    if (event.type == 'tool.completed') {
      toolCompletionSeen = true;
      continue;
    }
    if (isTransitionSystemNotice(event)) {
      if (toolCompletionSeen) continue;
      final text = (event.text ?? event.summary ?? '').trim();
      if (text.isNotEmpty) return text;
    }
    if (event.type == 'assistant.partial') {
      if (toolCompletionSeen) continue;
      return l10n.workbenchPendingGenerating;
    }
    if (event.type == 'tool.started') {
      if (hasToolUseId && !activeTool) continue;
      if (!hasToolUseId && toolCompletionSeen) continue;
      if (_isWebSearchTool(event.toolName)) {
        return l10n.workbenchPendingSearchingWeb;
      }
      return l10n.workbenchPendingRunningTool(_pendingToolLabel(l10n, event));
    }
    if (event.type == 'tool.output') {
      if (hasToolUseId && !activeTool) continue;
      if (!hasToolUseId && toolCompletionSeen) continue;
      return l10n.workbenchPendingReceivingToolOutput;
    }
    if (event.type == 'diff.summary') {
      if (toolCompletionSeen) continue;
      return l10n.workbenchPendingSummarizingDiff;
    }
    if (event.type == 'conversation.started') {
      if (toolCompletionSeen) continue;
      return l10n.workbenchPendingReadingContext;
    }
  }
  return l10n.workbenchPendingWaitingNextEvent;
}

DateTime? conversationPendingStartedAt(
    String status, Iterable<ConversationEvent> events) {
  if (!_isPendingTimerStatus(status)) return null;
  final list = events.toList(growable: false)
    ..sort((a, b) => a.seq.compareTo(b.seq));
  DateTime? startedAt;
  for (final event in list) {
    if (event.type == 'conversation.status_changed') {
      final nextStatus = event.raw['status'] as String? ?? '';
      if (_isPendingTimerStatus(nextStatus)) {
        startedAt = event.createdAt;
      } else if (_isInactiveConversationStatus(nextStatus)) {
        startedAt = null;
      }
      continue;
    }
    if (event.type == 'conversation.started') {
      startedAt = event.createdAt;
      continue;
    }
    if (startedAt == null && event.type == 'user.message') {
      startedAt = event.createdAt;
    }
  }
  return startedAt;
}

bool _isPendingTimerStatus(String status) =>
    status == 'sending' || status == 'running';

bool _isInactiveConversationStatus(String status) =>
    status == 'idle' ||
    status == 'completed' ||
    status == 'cancelled' ||
    status == 'failed' ||
    status == 'interrupted';

String _pendingToolLabel(AppLocalizations l10n, ConversationEvent event) {
  final command = event.input['command'];
  if (command is String &&
      command.trim().isNotEmpty &&
      (event.toolName == null || event.toolName == 'command_execution')) {
    return _compactCommandLabel(command.trim());
  }
  return event.toolName ?? l10n.workbenchPendingToolFallback;
}

bool _isWebSearchTool(String? toolName) {
  final normalized = toolName?.trim().toLowerCase();
  return normalized == 'websearch' ||
      normalized == 'web_search' ||
      normalized == 'web search';
}

String _compactCommandLabel(String command) {
  var value = command.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = value.toLowerCase();
  final commandMarker = lower.indexOf('-command ');
  if (commandMarker >= 0 && commandMarker + 9 < value.length) {
    value = value.substring(commandMarker + 9).trim();
    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      value = value.substring(1, value.length - 1).trim();
    }
  }
  return value.length > 72 ? '${value.substring(0, 69)}...' : value;
}

List<ConversationMessage> messagesForConversationSnapshot(
    List<ConversationMessage> messages, ConversationSummary? conversation) {
  final blockingItem = conversation?.blockingItem;
  if (conversation?.status != 'waiting_approval' ||
      blockingItem?.type != 'approval_request') {
    return messages
        .where((message) => message.role != 'approval')
        .toList(growable: false);
  }
  final currentApprovalId = blockingItem?.approvalId;
  return messages
      .where((message) =>
          message.role != 'approval' ||
          (currentApprovalId != null &&
              message.approvalId == currentApprovalId))
      .toList(growable: false);
}

String? emptyConversationCompletionDiagnostic(List<ConversationEvent> events,
    List<ConversationMessage> messages, bool terminal) {
  if (!terminal || events.isEmpty || messages.isNotEmpty) return null;
  final hasCompletion = events.any((event) =>
      event.type == 'conversation.completed' || event.type == 'run.error');
  if (!hasCompletion) return null;
  final warnings = events
      .where((event) => event.type == 'protocol.warning')
      .map((event) => event.text?.trim())
      .whereType<String>()
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
  if (warnings.isEmpty) {
    return 'CLI returned no content. Check whether Claude started correctly, or inspect daemon logs.';
  }
  return 'CLI returned no content. Diagnostics:\n${warnings.join('\n')}';
}

ConversationSummary copyConversationStatus(
        ConversationSummary conversation, String status,
        {ConversationBlockingItem? blockingItem}) =>
    conversation.copyWithStatus(status, blockingItem: blockingItem);

WorkbenchMessage workbenchMessageFromConversation(ConversationMessage message) {
  final event = AgentEvent(
      type: message.role == 'approval'
          ? 'approval.required'
          : message.role == 'question'
              ? 'assistant.question'
              : message.role == 'notice'
                  ? 'system.notice'
                  : message.role == 'thinking'
                      ? 'assistant.thinking'
                      : message.role == 'assistant_stream'
                          ? 'assistant.delta'
                          : message.role == 'assistant'
                              ? 'assistant.delta'
                              : 'raw.output',
      seq: message.eventSeq ?? 0,
      runId: 'conversation',
      createdAt: DateTime.now(),
      text: message.text,
      name: message.toolName,
      approvalId: message.approvalId,
      raw: <String, Object?>{
        'questionId': message.questionId,
        'approvalId': message.approvalId,
        'toolUseId': message.toolUseId,
        'toolName': message.toolName,
        'summary': message.summary,
        'taskId': message.taskId,
        'source': message.source,
        'noticeKind': message.noticeKind,
        'isError': message.isError,
        if (message.input.isNotEmpty) 'input': message.input,
        if (message.role == 'approval')
          'approvalOptions': message.approvalOptions.toJson(),
        'suggestions': message.suggestions,
        if (message.fileChanges.isNotEmpty)
          'changes': message.fileChanges
              .map((change) => <String, Object?>{
                    'path': change.path,
                    'kind': change.kind,
                    if (change.diff != null) 'diff': change.diff,
                  })
              .toList(growable: false),
        if (message.output != null) 'output': message.output,
        if (message.attachments.isNotEmpty)
          'attachments': message.attachments.map((item) => item.name).toList(),
        if (message.role == 'assistant') 'result': message.text,
      });
  switch (message.role) {
    case 'user':
      return WorkbenchMessage.user(message.text,
          attachments: message.attachments,
          clientMessageId: message.clientMessageId);
    case 'assistant':
      return WorkbenchMessage('assistant', 'CLI assistant', message.text,
          event: event, runId: 'conversation');
    case 'thinking':
      return WorkbenchMessage('thinking', 'Thinking process', message.text,
          event: event, runId: 'conversation');
    case 'assistant_stream':
      return WorkbenchMessage('assistant_stream', 'CLI assistant', message.text,
          event: event, runId: 'conversation');
    case 'question':
      return WorkbenchMessage('question', 'Needs your direction', message.text,
          event: event,
          runId: 'conversation',
          suggestions: message.suggestions);
    case 'notice':
      return WorkbenchMessage(
          'notice', _noticeTitleFallback(message), message.text,
          event: event, runId: 'conversation', isError: message.isError);
    case 'file_change':
      return WorkbenchMessage('file_change', 'File changes', message.text,
          event: event,
          runId: 'conversation',
          fileChanges: message.fileChanges);
    case 'approval':
      return WorkbenchMessage(
          'approval', 'Permission confirmation', message.text,
          event: event,
          runId: 'conversation',
          approvalOptions: message.approvalOptions);
    case 'command':
      return WorkbenchMessage('command', 'Run command', message.text,
          event: event,
          runId: 'conversation',
          completed: message.completed,
          isError: message.isError,
          duration: _conversationCommandDuration(message));
    case 'task_progress':
      return WorkbenchMessage('task_progress', 'Task progress', message.text,
          event: event,
          runId: 'conversation',
          taskId: message.taskId,
          taskItems: message.taskItems,
          completedCount: message.completedCount,
          totalCount: message.totalCount);
    default:
      return WorkbenchMessage.status(message.text);
  }
}

Duration? _conversationCommandDuration(ConversationMessage message) {
  final startedAt = message.startedAt;
  final completedAt = message.completedAt;
  if (startedAt == null || completedAt == null) return null;
  if (completedAt.isBefore(startedAt)) return null;
  return completedAt.difference(startedAt);
}

String _noticeTitleFallback(ConversationMessage message) {
  if (!message.isError) return 'System notice';
  if (message.noticeKind == 'run_failed') return 'Run failed';
  final text = message.text.toLowerCase();
  if (text.contains('claude') &&
      (text.contains('auth') || text.contains('401'))) {
    return 'Claude authentication failed';
  }
  if (text.startsWith('run error:')) return 'Run failed';
  return 'CLI error';
}

// ignore: unused_element
AgentEvent _agentEventFromConversation(ConversationEvent event, String runId) {
  final raw = <String, Object?>{...event.raw, 'runId': runId};
  final type = switch (event.type) {
    'conversation.started' => 'run.started',
    'conversation.status_changed' =>
      event.raw['status'] == 'idle' ? 'run.completed' : 'raw.output',
    'assistant.partial' => 'assistant.delta',
    'assistant.message' => 'assistant.delta',
    'approval.requested' => 'approval.required',
    'approval.resolved' => 'approval.responded',
    'conversation.cancelled' => 'run.cancelled',
    'run.error' => 'run.failed',
    _ => event.type,
  };
  if (event.type == 'assistant.message' && event.text != null) {
    raw['result'] = event.text;
  }
  if (event.type == 'approval.requested') {
    raw['approvalOptions'] = event.approvalOptions.toJson();
  }
  return AgentEvent(
      type: type,
      seq: event.seq,
      runId: runId,
      createdAt: event.createdAt,
      text: event.text ?? event.summary,
      name: event.toolName,
      approvalId: event.approvalId,
      raw: raw);
}

class WorkbenchMessage {
  const WorkbenchMessage(this.role, this.title, this.body,
      {this.event,
      this.runId,
      this.completed = false,
      this.isError = false,
      this.duration,
      this.taskId,
      this.taskItems = const <TaskProgressItem>[],
      this.completedCount,
      this.totalCount,
      this.suggestions = const <String>[],
      this.approvalOptions = const ApprovalRequestOptions(),
      this.attachments = const <CommittedAttachment>[],
      this.clientMessageId,
      this.fileChanges = const <ConversationFileChange>[]});
  final String role;
  final String title;
  final String body;
  final AgentEvent? event;
  final String? runId;
  final bool completed;
  final bool isError;
  final Duration? duration;
  final String? taskId;
  final List<TaskProgressItem> taskItems;
  final int? completedCount;
  final int? totalCount;
  final List<String> suggestions;
  final ApprovalRequestOptions approvalOptions;
  final List<CommittedAttachment> attachments;
  final String? clientMessageId;
  final List<ConversationFileChange> fileChanges;
  factory WorkbenchMessage.user(
    String text, {
    List<CommittedAttachment> attachments = const <CommittedAttachment>[],
    String? clientMessageId,
  }) =>
      WorkbenchMessage('user', 'You', text,
          attachments: attachments, clientMessageId: clientMessageId);
  factory WorkbenchMessage.status(String text) =>
      WorkbenchMessage('status', 'Run status', text);
  WorkbenchMessage copyWith(
          {String? body,
          bool? completed,
          bool? isError,
          Duration? duration,
          List<CommittedAttachment>? attachments,
          String? clientMessageId,
          List<ConversationFileChange>? fileChanges}) =>
      WorkbenchMessage(role, title, body ?? this.body,
          event: event,
          runId: runId,
          completed: completed ?? this.completed,
          isError: isError ?? this.isError,
          duration: duration ?? this.duration,
          taskId: taskId,
          taskItems: taskItems,
          completedCount: completedCount,
          totalCount: totalCount,
          suggestions: suggestions,
          approvalOptions: approvalOptions,
          attachments: attachments ?? this.attachments,
          clientMessageId: clientMessageId ?? this.clientMessageId,
          fileChanges: fileChanges ?? this.fileChanges);

  static WorkbenchMessage? fromEvent(AgentEvent event, bool streamOutput) {
    final parsed = _parseVisibleText(event);
    final visibleText = parsed?.text;
    if (event.type == 'approval.required') {
      final toolName = event.name ?? 'Tool';
      final target = _approvalTarget(event);
      final body = target == null
          ? '$toolName requested permission without arguments.'
          : '$toolName requested access: $target';
      return WorkbenchMessage(
          'approval', 'Permission confirmation', visibleText ?? body,
          event: event,
          runId: event.runId,
          approvalOptions:
              ApprovalRequestOptions.fromJson(event.raw['approvalOptions']));
    }
    if (event.type == 'assistant.question') {
      final question = visibleText ?? event.text ?? toolEventBody(event);
      return WorkbenchMessage(
          'question', 'Needs your direction', question.trim(),
          event: event,
          runId: event.runId,
          suggestions: _eventSuggestions(event));
    }
    if (visibleText != null && visibleText.trim().isNotEmpty) {
      if (parsed?.kind == _VisibleTextKind.delta) {
        if (!streamOutput) return null;
        return WorkbenchMessage(
            'assistant_stream', 'CLI assistant', visibleText,
            event: event, runId: event.runId);
      }
      if (parsed?.kind == _VisibleTextKind.finalMessage) {
        return WorkbenchMessage(
            'assistant', 'CLI assistant', visibleText.trim(),
            event: event, runId: event.runId);
      }
    }
    if (event.type == 'tool.started') {
      return WorkbenchMessage('command', 'Run command', toolEventBody(event),
          event: event, runId: event.runId);
    }
    if (event.type == 'diff.summary' && event.diff != null) {
      final diff = event.diff!;
      return WorkbenchMessage('diff', 'File changes',
          '${diff.filePath}  +${diff.additions} -${diff.deletions}',
          event: event, runId: event.runId);
    }
    if (event.type == 'run.cancelled') return null;
    if (event.type == 'run.failed') {
      return WorkbenchMessage('status', 'Run ended', visibleText ?? event.type,
          event: event, runId: event.runId);
    }
    return null;
  }

  static String? _approvalTarget(AgentEvent event) {
    final input = _eventInput(event);
    if (input is Map<String, Object?>) {
      final question = _firstNonEmptyInputString(input, const [
        'question',
        'prompt',
        'message',
        'content',
        'text',
        'query',
        'description'
      ]);
      if (question != null) return question;
      final target = input['file_path'] ??
          input['path'] ??
          input['command'] ??
          input['pattern'] ??
          input['description'];
      if (target is String && target.trim().isNotEmpty) return target;
    }
    return null;
  }

  static _VisibleText? _parseVisibleText(AgentEvent event) {
    if (_isInternalProtocolObject(event.raw) ||
        _isInternalProtocolObject(event.raw['raw'])) {
      return null;
    }
    if (!_canExposeAsAssistantText(event)) return null;
    final nested = _parseRawObject(event.raw['raw']);
    if (nested != null) return nested;
    final topLevel = _parseRawObject(event.raw);
    if (topLevel != null) return topLevel;
    final text = event.text;
    if (text == null || text.trim().isEmpty) return null;
    final trimmed = text.trim();
    if (!trimmed.startsWith('{')) {
      return event.type.startsWith('assistant')
          ? _VisibleText(_VisibleTextKind.delta, trimmed)
          : null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      if (_isInternalProtocolObject(decoded)) return null;
      final directMessage = decoded['message'];
      if (directMessage is Map<String, dynamic>) {
        final content = directMessage['content'];
        final extracted = _extractContent(content);
        if (extracted != null) {
          return _VisibleText(_VisibleTextKind.finalMessage, extracted);
        }
      }
      final eventPayload = decoded['event'];
      if (eventPayload is Map<String, dynamic>) {
        final content = eventPayload['content'];
        final extracted = _extractContent(content);
        if (extracted != null) {
          return _VisibleText(_VisibleTextKind.finalMessage, extracted);
        }
        final delta = eventPayload['delta'];
        if (delta is Map<String, dynamic>) {
          final deltaText = delta['text'];
          if (deltaText is String && deltaText.trim().isNotEmpty) {
            return _VisibleText(_VisibleTextKind.delta, deltaText);
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _canExposeAsAssistantText(AgentEvent event) {
    return event.type.startsWith('assistant') ||
        event.type == 'run.failed' ||
        event.type == 'run.cancelled';
  }

  static bool _isInternalProtocolObject(Object? value) {
    if (value is! Map<String, Object?> && value is! Map<String, dynamic>) {
      return false;
    }
    final raw = Map<String, dynamic>.from(value as Map);
    final type = raw['type'];
    final subtype = raw['subtype'];
    if (type == 'control_request' ||
        type == 'control_response' ||
        type == 'control_cancel_request' ||
        type == 'transcript_mirror') {
      return true;
    }
    if (raw.containsKey('hookSpecificOutput') ||
        raw.containsKey('suppressOutput') ||
        raw.containsKey('callback_id') ||
        raw.containsKey('hookEventName') ||
        raw.containsKey('hook_event_name')) {
      return true;
    }
    if (raw.containsKey('continue') && raw.containsKey('suppressOutput')) {
      return true;
    }
    if (type == 'system' &&
        (subtype == 'hook_callback' ||
            subtype == 'session_start' ||
            subtype == 'session_end')) {
      return true;
    }
    return false;
  }

  static _VisibleText? _parseRawObject(Object? value) {
    if (value is! Map<String, Object?> && value is! Map<String, dynamic>) {
      return null;
    }
    final raw = Map<String, dynamic>.from(value as Map);
    final result = raw['result'];
    if (result is String && result.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(result)) return null;
      return _VisibleText(_VisibleTextKind.finalMessage, result);
    }
    final output = raw['output'];
    if (output is String && output.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(output)) return null;
      return _VisibleText(_VisibleTextKind.finalMessage, output);
    }
    final message = raw['message'];
    if (message is String && message.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(message)) return null;
      return _VisibleText(_VisibleTextKind.finalMessage, message);
    }
    if (message is Map<String, dynamic>) {
      final extracted = _extractContent(message['content']);
      if (extracted != null) {
        return _VisibleText(_VisibleTextKind.finalMessage, extracted);
      }
    }
    final content = raw['content'];
    final contentText = _extractContent(content);
    if (contentText != null) {
      final type = raw['type'];
      final kind = type is String && type.contains('delta')
          ? _VisibleTextKind.delta
          : _VisibleTextKind.finalMessage;
      return _VisibleText(kind, contentText);
    }
    final delta = raw['delta'];
    if (delta is String && delta.trim().isNotEmpty) {
      return _VisibleText(_VisibleTextKind.delta, delta);
    }
    if (delta is Map<String, dynamic>) {
      final deltaText = delta['text'];
      if (deltaText is String && deltaText.trim().isNotEmpty) {
        return _VisibleText(_VisibleTextKind.delta, deltaText);
      }
    }
    return null;
  }

  static String? _extractContent(Object? content) {
    if (content is String && content.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(content)) return null;
      return content;
    }
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map<String, dynamic>) {
          if (item['type'] != null && item['type'] != 'text') continue;
          final text = item['text'];
          if (text is String &&
              text.trim().isNotEmpty &&
              !_looksLikeProtocolLeak(text)) {
            parts.add(text.trim());
          }
        }
      }
      if (parts.isNotEmpty) return parts.join('\n\n');
    }
    return null;
  }

  static String toolEventBody(AgentEvent event) {
    final input = _eventInput(event);
    if (input is Map<String, Object?>) {
      final question = _firstNonEmptyInputString(input, const [
        'question',
        'prompt',
        'message',
        'content',
        'text',
        'query',
        'description'
      ]);
      if (question != null) return question;
      final command = input['command'];
      if (command is String && command.trim().isNotEmpty) return command.trim();
      final file = input['file_path'] ?? input['path'] ?? input['filename'];
      if (file is String && file.trim().isNotEmpty) return file.trim();
    }
    return event.name ?? 'CLI tool running';
  }

  static Object? _eventInput(AgentEvent event) {
    final direct = event.raw['input'];
    if (direct != null) return direct;
    final raw = event.raw['raw'];
    if (raw is Map<String, Object?>) {
      final rawInput = raw['input'];
      if (rawInput != null) return rawInput;
      final request = raw['request'];
      if (request is Map<String, Object?>) return request['input'];
    }
    return null;
  }

  static List<String> _eventSuggestions(AgentEvent event) {
    final raw = event.raw['suggestions'];
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item is String ? item.trim() : '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _firstNonEmptyInputString(
      Map<String, Object?> input, List<String> keys) {
    for (final key in keys) {
      final value = input[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in input.values) {
      if (value is Map<String, Object?>) {
        final nested = _firstNonEmptyInputString(value, keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static bool _looksLikeProtocolLeak(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith(r'\n"') ||
        trimmed.contains(r'\n\n## Skill Types') ||
        trimmed.contains(r'\n\n## User Instructions')) {
      return true;
    }
    final sample = trimmed.length > 1400 ? trimmed.substring(0, 1400) : trimmed;
    final normalized = sample
        .replaceAll('\\n', '\n')
        .replaceAll('\\"', '"')
        .replaceAll("'", '"');
    if (normalized.contains('"type":"control_') ||
        normalized.contains('"type": "control_') ||
        normalized.contains('"suppressOutput"') ||
        normalized.contains('"hookSpecificOutput"') ||
        normalized.contains('"parent_tool_use_id"') ||
        normalized.contains('"session_id"') &&
            normalized.contains('"message"') &&
            normalized.contains('"role"')) {
      return true;
    }
    if ((normalized.startsWith('{') || normalized.startsWith('"{')) &&
        normalized.contains('"type"') &&
        normalized.contains('"message"')) {
      return true;
    }
    return false;
  }
}

enum _VisibleTextKind { delta, finalMessage }

class _VisibleText {
  const _VisibleText(this.kind, this.text);
  final _VisibleTextKind kind;
  final String text;
}
