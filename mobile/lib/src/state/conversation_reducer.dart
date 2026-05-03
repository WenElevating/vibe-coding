import '../models/protocol.dart';

class ConversationMessage {
  const ConversationMessage({
    required this.role,
    required this.text,
    this.eventSeq,
    this.questionId,
    this.approvalId,
    this.suggestions = const <String>[],
  });

  final String role;
  final String text;
  final int? eventSeq;
  final String? questionId;
  final String? approvalId;
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
          nextStatus = 'idle';
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
            text: event.summary ?? event.toolName ?? '需要批准',
            eventSeq: event.seq,
            approvalId: event.approvalId,
          ));
          nextStatus = 'waiting_approval';
          break;
        case 'approval.resolved':
          nextMessages.removeWhere((message) =>
              message.role == 'approval' &&
              message.approvalId == event.approvalId);
          nextStatus = 'running';
          break;
        case 'conversation.cancelled':
          nextStatus = 'cancelled';
          partial = '';
          break;
        case 'run.error':
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

void _upsertThinkingMessage(
    List<ConversationMessage> messages, ConversationMessage incoming) {
  final text = incoming.text.trim();
  if (text.isEmpty) return;
  final lastIndex = messages.lastIndexWhere((message) => message.role == 'thinking');
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
      value == '需要你补充更多信息。' ||
      value == 'Need more information.';
}
