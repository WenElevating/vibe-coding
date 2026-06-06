import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/approval_response.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../messages/pending_sentinel.dart';
import '../messages/codex_command_run_card.dart';
import '../messages/workbench_message_card.dart';
import '../workbench_messages.dart';
import '../workbench_transcript_display_items.dart';
import 'workbench_inline_status.dart';
import 'workbench_run_error_card.dart';

class WorkbenchMessageList extends StatefulWidget {
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
  final Future<void> Function(AgentEvent event, ApprovalResponse response)
      onApproval;
  final ValueChanged<String> onSuggestion;
  final bool Function(ScrollNotification notification) onScrollNotification;

  @override
  State<WorkbenchMessageList> createState() => _WorkbenchMessageListState();
}

class _WorkbenchMessageListState extends State<WorkbenchMessageList> {
  final Set<String> _expandedCommandRuns = <String>{};

  @override
  Widget build(BuildContext context) {
    final displayItems =
        projectWorkbenchTranscriptDisplayItems(widget.messages);
    final itemCount = (widget.loadingOlderConversationEvents ? 1 : 0) +
        (widget.showStatus ? 1 : 0) +
        displayItems.length +
        (widget.showError ? 1 : 0) +
        (widget.showPending ? 1 : 0);
    return NotificationListener<ScrollNotification>(
      onNotification: widget.onScrollNotification,
      child: ListView.builder(
        key: ValueKey(
          'workbench-message-list-${widget.useReverseTranscript ? 'reverse' : 'normal'}',
        ),
        controller: widget.controller,
        reverse: widget.useReverseTranscript,
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final logicalIndex =
              widget.useReverseTranscript ? itemCount - 1 - index : index;
          var messageIndex = logicalIndex;
          if (widget.loadingOlderConversationEvents) {
            if (logicalIndex == 0) {
              return const Padding(
                key: ValueKey('workbench-history-loading-row'),
                padding: EdgeInsets.only(bottom: 12),
                child: _HistoryLoadingRow(),
              );
            }
            messageIndex -= 1;
          }
          if (widget.showStatus) {
            if (messageIndex == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WorkbenchInlineStatus(
                  adapter: widget.adapter,
                  runId: widget.runId,
                  eventCount: widget.eventCount,
                  terminal: widget.terminal,
                ),
              );
            }
            messageIndex -= 1;
          }
          if (messageIndex < displayItems.length) {
            final displayItem = displayItems[messageIndex];
            return Padding(
              key: ValueKey(_displayItemKey(messageIndex, displayItem)),
              padding: EdgeInsets.only(
                bottom: _displayItemBottomPadding(displayItem),
              ),
              child: _buildDisplayItem(displayItem),
            );
          }
          messageIndex -= displayItems.length;
          if (widget.showError) {
            if (messageIndex == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: WorkbenchRunErrorCard(
                  error: widget.runError ?? '',
                  traceId: widget.runErrorTraceId,
                ),
              );
            }
            messageIndex -= 1;
          }
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: PendingSentinel(
              adapter: widget.adapter ?? 'CLI',
              statusText: widget.pendingStatusText,
              startedAt: widget.pendingStartedAt,
              actions: widget.pendingActions,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDisplayItem(WorkbenchTranscriptDisplayItem item) {
    switch (item) {
      case WorkbenchMessageDisplayItem(:final message):
        return WorkbenchMessageCard(
          message: message,
          expandThinking: widget.expandThinking,
          expandToolDetails: widget.expandToolDetails,
          onSuggestion: widget.onSuggestion,
          onApproval: (decision) => widget.onApproval(message.event!, decision),
        );
      case SingleCommandDisplayItem(:final message):
        final key = _singleCommandKey(message);
        return SingleCommandRunCard(
          message: message,
          expanded: _expandedCommandRuns.contains(key),
          onToggleExpanded: () => _toggle(key),
        );
      case CommandRunGroupDisplayItem(:final messages):
        final key = _commandGroupKey(messages);
        return CommandRunGroupCard(
          messages: messages,
          expanded: _expandedCommandRuns.contains(key),
          onToggleExpanded: () => _toggle(key),
        );
    }
  }

  double _displayItemBottomPadding(WorkbenchTranscriptDisplayItem item) =>
      switch (item) {
        SingleCommandDisplayItem() || CommandRunGroupDisplayItem() => 4,
        WorkbenchMessageDisplayItem() => 10,
      };

  void _toggle(String key) {
    setState(() {
      if (!_expandedCommandRuns.add(key)) {
        _expandedCommandRuns.remove(key);
      }
    });
  }

  String _displayItemKey(int index, WorkbenchTranscriptDisplayItem item) =>
      switch (item) {
        WorkbenchMessageDisplayItem(:final message) =>
          'workbench-message-$index-${message.role}',
        SingleCommandDisplayItem(:final message) =>
          'workbench-single-command-${_singleCommandKey(message)}',
        CommandRunGroupDisplayItem(:final messages) =>
          'workbench-command-group-${_commandGroupKey(messages)}',
      };

  String _singleCommandKey(WorkbenchMessage message) {
    final event = message.event;
    if (event != null) return 'event-${event.runId}-${event.seq}';
    return '${message.runId ?? 'run'}-${message.title}-${message.body}';
  }

  String _commandGroupKey(List<WorkbenchMessage> messages) {
    final first = messages.first;
    final firstEvent = first.event;
    if (firstEvent != null) {
      return 'events-${firstEvent.runId}-${firstEvent.seq}';
    }
    return '${first.runId ?? 'run'}-${messages.length}-${first.title}-${first.body}';
  }
}

class _HistoryLoadingRow extends StatelessWidget {
  const _HistoryLoadingRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x66111B2A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .075)),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.purple2,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                l10n.workbenchLoadingEarlierEvents,
                style: const TextStyle(
                  color: theme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
