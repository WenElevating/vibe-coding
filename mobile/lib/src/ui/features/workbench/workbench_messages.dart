import 'dart:convert';

import '../../../../l10n/app_localizations.dart';
import '../../../models/protocol.dart';
import 'conversation_reducer.dart';

bool shouldPollAfterApproval(ConversationSummary conversation) =>
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
  final list = events.toList(growable: false);
  if (list.isEmpty) return l10n.workbenchPendingStarting;
  for (final event in list.reversed) {
    if (isTransitionSystemNotice(event)) {
      final text = (event.text ?? event.summary ?? '').trim();
      if (text.isNotEmpty) return text;
    }
    if (event.type == 'assistant.partial') {
      return l10n.workbenchPendingGenerating;
    }
    if (event.type == 'tool.started') {
      return l10n.workbenchPendingRunningTool(
          event.toolName ?? l10n.workbenchPendingToolFallback);
    }
    if (event.type == 'tool.output') {
      return l10n.workbenchPendingReceivingToolOutput;
    }
    if (event.type == 'diff.summary') {
      return l10n.workbenchPendingSummarizingDiff;
    }
    if (event.type == 'conversation.started') {
      return l10n.workbenchPendingReadingContext;
    }
  }
  return l10n.workbenchPendingWaitingNextEvent;
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
    {ConversationBlockingItem? blockingItem}) {
  return ConversationSummary(
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
      blockingItem: blockingItem,
      idleExpiresAt: conversation.idleExpiresAt);
}

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
        'isError': message.isError,
        if (message.input.isNotEmpty) 'input': message.input,
        'suggestions': message.suggestions,
        if (message.output != null) 'output': message.output,
        if (message.role == 'assistant') 'result': message.text,
      });
  switch (message.role) {
    case 'user':
      return WorkbenchMessage.user(message.text);
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
      return WorkbenchMessage('notice', 'System notice', message.text,
          event: event, runId: 'conversation');
    case 'approval':
      return WorkbenchMessage(
          'approval', 'Permission confirmation', message.text,
          event: event, runId: 'conversation');
    case 'command':
      return WorkbenchMessage('command', 'Run command', message.text,
          event: event,
          runId: 'conversation',
          completed: message.completed,
          isError: message.isError,
          duration: _conversationCommandDuration(message));
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
      this.suggestions = const <String>[]});
  final String role;
  final String title;
  final String body;
  final AgentEvent? event;
  final String? runId;
  final bool completed;
  final bool isError;
  final Duration? duration;
  final List<String> suggestions;
  factory WorkbenchMessage.user(String text) =>
      WorkbenchMessage('user', 'You', text);
  factory WorkbenchMessage.status(String text) =>
      WorkbenchMessage('status', 'Run status', text);
  WorkbenchMessage copyWith(
          {String? body, bool? completed, bool? isError, Duration? duration}) =>
      WorkbenchMessage(role, title, body ?? this.body,
          event: event,
          runId: runId,
          completed: completed ?? this.completed,
          isError: isError ?? this.isError,
          duration: duration ?? this.duration,
          suggestions: suggestions);

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
          event: event, runId: event.runId);
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
