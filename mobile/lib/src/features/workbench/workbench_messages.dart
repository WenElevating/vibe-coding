part of '../../app/app.dart';

class _SessionItem {
  const _SessionItem({required this.run, this.conversation});
  final RunSummary run;
  final ConversationSummary? conversation;

  String get id => conversation?.id ?? run.id;
}

List<_SessionItem> _mergeSessionItems(
    List<_SessionItem> localSessions,
    List<ConversationSummary> snapshotConversations,
    List<RunSummary> snapshotRuns) {
  final items = <_SessionItem>[];
  final seen = <String>{};
  for (final item in localSessions) {
    if (seen.add(item.id)) items.add(item);
  }
  for (final conversation in snapshotConversations) {
    if (conversation.status == 'idle' && conversation.cliSessionId == null) {
      continue;
    }
    if (seen.add(conversation.id)) {
      items.add(_SessionItem(
          run: _runSummaryFromConversation(conversation),
          conversation: conversation));
    }
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) items.add(_SessionItem(run: run));
  }
  return items;
}

String _runStatusFromConversation(String status) {
  if (status == 'idle') return 'completed';
  if (status == 'cancelled' || status == 'failed') return status;
  return 'running';
}

bool _shouldPollAfterApproval(ConversationSummary conversation) =>
    conversation.status == 'running' || conversation.status == 'waiting_input';

bool _hasExplicitWorkspaceSelectionState({
  required bool workspaceConfirmedForSession,
  required String? activeRunId,
  required bool hasLocalSessions,
}) =>
    workspaceConfirmedForSession || activeRunId != null;

List<ConversationMessage> _messagesForConversationSnapshot(
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

String? _emptyConversationCompletionDiagnostic(List<ConversationEvent> events,
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
  if (warnings.isEmpty) return 'CLI 未返回内容。请检查 Claude 是否正常启动，或查看 daemon 日志。';
  return 'CLI 未返回内容。诊断信息：\n${warnings.join('\n')}';
}

ConversationSummary _copyConversationStatus(
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
      blockingItem: blockingItem,
      idleExpiresAt: conversation.idleExpiresAt);
}

_WorkbenchMessage _workbenchMessageFromConversation(
    ConversationMessage message) {
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
      return _WorkbenchMessage.user(message.text);
    case 'assistant':
      return _WorkbenchMessage('assistant', 'CLI 助手', message.text,
          event: event, runId: 'conversation');
    case 'thinking':
      return _WorkbenchMessage('thinking', '思考过程', message.text,
          event: event, runId: 'conversation');
    case 'assistant_stream':
      return _WorkbenchMessage('assistant_stream', 'CLI 助手', message.text,
          event: event, runId: 'conversation');
    case 'question':
      return _WorkbenchMessage('question', '需要你选择方向', message.text,
          event: event,
          runId: 'conversation',
          suggestions: message.suggestions);
    case 'notice':
      return _WorkbenchMessage('notice', '系统提示', message.text,
          event: event, runId: 'conversation');
    case 'approval':
      return _WorkbenchMessage('approval', '权限确认', message.text,
          event: event, runId: 'conversation');
    case 'command':
      return _WorkbenchMessage('command', '运行命令', message.text,
          event: event,
          runId: 'conversation',
          completed: message.completed,
          isError: message.isError,
          duration: _conversationCommandDuration(message));
    default:
      return _WorkbenchMessage.status(message.text);
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

class _WorkbenchMessage {
  const _WorkbenchMessage(this.role, this.title, this.body,
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
  factory _WorkbenchMessage.user(String text) =>
      _WorkbenchMessage('user', '你', text);
  factory _WorkbenchMessage.status(String text) =>
      _WorkbenchMessage('status', '运行状态', text);
  _WorkbenchMessage copyWith(
          {String? body, bool? completed, bool? isError, Duration? duration}) =>
      _WorkbenchMessage(role, title, body ?? this.body,
          event: event,
          runId: runId,
          completed: completed ?? this.completed,
          isError: isError ?? this.isError,
          duration: duration ?? this.duration,
          suggestions: suggestions);

  static _WorkbenchMessage? fromEvent(AgentEvent event, bool streamOutput) {
    final parsed = _parseVisibleText(event);
    final visibleText = parsed?.text;
    if (event.type == 'approval.required') {
      final toolName = event.name ?? '工具';
      final target = _approvalTarget(event);
      final body =
          target == null ? '$toolName 请求权限（未提供参数）。' : '$toolName 请求访问：$target';
      return _WorkbenchMessage('approval', '权限确认', visibleText ?? body,
          event: event, runId: event.runId);
    }
    if (event.type == 'assistant.question') {
      final question = visibleText ?? event.text ?? _toolEventBody(event);
      return _WorkbenchMessage('question', '需要你选择方向', question.trim(),
          event: event,
          runId: event.runId,
          suggestions: _eventSuggestions(event));
    }
    if (visibleText != null && visibleText.trim().isNotEmpty) {
      if (parsed?.kind == _VisibleTextKind.delta) {
        if (!streamOutput) return null;
        return _WorkbenchMessage('assistant_stream', 'CLI 助手', visibleText,
            event: event, runId: event.runId);
      }
      if (parsed?.kind == _VisibleTextKind.finalMessage) {
        return _WorkbenchMessage('assistant', 'CLI 助手', visibleText.trim(),
            event: event, runId: event.runId);
      }
    }
    if (event.type == 'tool.started') {
      return _WorkbenchMessage('command', '运行命令', _toolEventBody(event),
          event: event, runId: event.runId);
    }
    if (event.type == 'diff.summary' && event.diff != null) {
      final diff = event.diff!;
      return _WorkbenchMessage('diff', '文件变更',
          '${diff.filePath}  +${diff.additions} -${diff.deletions}',
          event: event, runId: event.runId);
    }
    if (event.type == 'run.cancelled') return null;
    if (event.type == 'run.failed') {
      return _WorkbenchMessage('status', '运行结束', visibleText ?? event.type,
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

  static String _toolEventBody(AgentEvent event) {
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
    return event.name ?? 'CLI 工具调用中';
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
