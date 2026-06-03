import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../messages/pending_sentinel.dart';
import '../messages/workbench_message_card.dart';
import '../workbench_messages.dart';
import 'workbench_inline_status.dart';
import 'workbench_run_error_card.dart';

class WorkbenchMessageList extends StatelessWidget {
  const WorkbenchMessageList({
    super.key,
    required this.controller,
    required this.messages,
    required this.adapter,
    required this.runId,
    required this.eventCount,
    required this.terminal,
    required this.runError,
    required this.runErrorTraceId,
    required this.pendingStatusText,
    required this.pendingStartedAt,
    required this.pendingActions,
    required this.expandThinking,
    required this.expandToolDetails,
    required this.useReverseTranscript,
    required this.loadingOlderConversationEvents,
    required this.showPendingDuringInitialConversationLoad,
    required this.showStatus,
    required this.showError,
    required this.showPending,
    required this.onApproval,
    required this.onSuggestion,
    required this.onScrollNotification,
  });

  final ScrollController controller;
  final List<WorkbenchMessage> messages;
  final String? adapter;
  final String? runId;
  final int eventCount;
  final bool terminal;
  final String? runError;
  final String? runErrorTraceId;
  final String pendingStatusText;
  final DateTime? pendingStartedAt;
  final List<String> pendingActions;
  final bool expandThinking;
  final bool expandToolDetails;
  final bool useReverseTranscript;
  final bool loadingOlderConversationEvents;
  final bool showPendingDuringInitialConversationLoad;
  final bool showStatus;
  final bool showError;
  final bool showPending;
  final Future<void> Function(AgentEvent event, String decision) onApproval;
  final ValueChanged<String> onSuggestion;
  final bool Function(ScrollNotification notification) onScrollNotification;

  @override
  Widget build(BuildContext context) {
    final itemCount = (showStatus ? 1 : 0) +
        messages.length +
        (showError ? 1 : 0) +
        (showPending ? 1 : 0);
    return NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: ListView.builder(
        key: ValueKey(
          'workbench-message-list-${useReverseTranscript ? 'reverse' : 'normal'}',
        ),
        controller: controller,
        reverse: useReverseTranscript,
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final logicalIndex =
              useReverseTranscript ? itemCount - 1 - index : index;
          var messageIndex = logicalIndex;
          if (showStatus) {
            if (logicalIndex == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WorkbenchInlineStatus(
                  adapter: adapter,
                  runId: runId,
                  eventCount: eventCount,
                  terminal: terminal,
                ),
              );
            }
            messageIndex -= 1;
          }
          if (messageIndex < messages.length) {
            final message = messages[messageIndex];
            return Padding(
              key: ValueKey('workbench-message-$messageIndex-${message.role}'),
              padding: const EdgeInsets.only(bottom: 10),
              child: WorkbenchMessageCard(
                message: message,
                expandThinking: expandThinking,
                expandToolDetails: expandToolDetails,
                onSuggestion: onSuggestion,
                onApproval: (decision) => onApproval(message.event!, decision),
              ),
            );
          }
          messageIndex -= messages.length;
          if (showError) {
            if (messageIndex == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: WorkbenchRunErrorCard(
                  error: runError ?? '',
                  traceId: runErrorTraceId,
                ),
              );
            }
            messageIndex -= 1;
          }
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: PendingSentinel(
              adapter: adapter ?? 'CLI',
              statusText: pendingStatusText,
              startedAt: pendingStartedAt,
              actions: pendingActions,
            ),
          );
        },
      ),
    );
  }
}
