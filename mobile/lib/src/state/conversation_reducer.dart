import '../models/protocol.dart';

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
    this.input = const <String, Object?>{},
    this.completed = false,
    this.startedAt,
    this.completedAt,
    this.output,
    this.exitCode,
    this.isError = false,
    this.suggestions = const <String>[],
  });

  final String role;
  final String text;
  final int? eventSeq;
  final String? questionId;
  final String? approvalId;
  final String? toolUseId;
  final String? toolName;
  final String? summary;
  final Map<String, Object?> input;
  final bool completed;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? output;
  final int? exitCode;
  final bool isError;
  final List<String> suggestions;
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
    final nextMessages = <ConversationMessage>[...messages];
    var nextSeq = lastSeq;
    var nextStatus = status;
    var partial = pendingPartial;
    for (final event in events.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq))) {
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
              role: 'user', text: event.text ?? '', eventSeq: event.seq));
          break;
        case 'assistant.partial':
          partial = _mergeAssistantPartial(partial, event.text ?? '');
          if (streamOutput && partial.trim().isNotEmpty) {
            nextMessages
                .removeWhere((message) => message.role == 'assistant_stream');
            nextMessages.add(ConversationMessage(
                role: 'assistant_stream', text: partial, eventSeq: event.seq));
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
        case 'system.notice':
          if (event.raw['visible'] == false) break;
          nextMessages.add(ConversationMessage(
            role: 'notice',
            text: event.text ?? event.summary ?? '',
            eventSeq: event.seq,
          ));
          break;
        case 'tool.started':
          final toolUseId = event.toolUseId;
          if (toolUseId == null || toolUseId.isEmpty) break;
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
          _appendCommandOutput(nextMessages, event);
          break;
        case 'tool.completed':
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
          nextStatus = 'failed';
          partial = '';
          break;
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

void _completeCommandMessage(
    List<ConversationMessage> messages, ConversationEvent event) {
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
    completed: true,
    startedAt: command.startedAt,
    completedAt: event.createdAt,
    output: command.output,
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
