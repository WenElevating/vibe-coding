import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/approval_response.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../messages/codex_command_run_card.dart';
import '../messages/pending_transcript_transition.dart';
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
    this.elapsedSegments = const <ConversationElapsedSegment>[],
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
    this.now,
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
  final List<ConversationElapsedSegment> elapsedSegments;
  final List<String> pendingActions;
  final bool expandThinking;
  final bool expandToolDetails;
  final bool useReverseTranscript;
  final bool loadingOlderConversationEvents;
  final bool showPendingDuringInitialConversationLoad;
  final bool showStatus;
  final bool showError;
  final bool showPending;
  final DateTime Function()? now;
  final Future<void> Function(AgentEvent event, ApprovalResponse response)
      onApproval;
  final ValueChanged<String> onSuggestion;
  final bool Function(ScrollNotification notification) onScrollNotification;

  @override
  State<WorkbenchMessageList> createState() => _WorkbenchMessageListState();
}

class _WorkbenchMessageListState extends State<WorkbenchMessageList> {
  static const double _listHorizontalPadding = 15;
  static const double _listVerticalPadding = 16;

  final Set<String> _expandedCommandRuns = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final displayItems =
        projectWorkbenchTranscriptDisplayItems(widget.messages);
    final hasActiveCommandActivity = displayItems.any(_isActiveCommandItem);
    final displaySlots = _displaySlots(displayItems);
    final showPendingTail = widget.showPending &&
        !hasActiveCommandActivity &&
        !isPendingTranscriptRunningTool(l10n, widget.pendingStatusText);
    final displaySlotCount = displaySlots.length;
    final itemCount = (widget.loadingOlderConversationEvents ? 1 : 0) +
        (widget.showStatus ? 1 : 0) +
        displaySlotCount +
        (widget.showError ? 1 : 0) +
        (showPendingTail ? 1 : 0);
    return NotificationListener<ScrollNotification>(
      onNotification: widget.onScrollNotification,
      child: ListView.builder(
        key: ValueKey(
          'workbench-message-list-${widget.useReverseTranscript ? 'reverse' : 'normal'}',
        ),
        controller: widget.controller,
        reverse: widget.useReverseTranscript,
        padding: const EdgeInsets.fromLTRB(
          _listHorizontalPadding,
          _listVerticalPadding,
          _listHorizontalPadding,
          _listVerticalPadding,
        ),
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
          if (messageIndex < displaySlotCount) {
            return switch (displaySlots[messageIndex]) {
              _DisplayItemSlot(:final displayIndex, :final item) => Padding(
                  key: ValueKey(_displayItemKey(displayIndex, item)),
                  padding: EdgeInsets.only(
                    bottom: _displayItemBottomPadding(item),
                  ),
                  child: _buildDisplayItem(item),
                ),
              _ElapsedSlot(:final segment) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PendingTranscriptElapsedProgress(
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    now: widget.now,
                  ),
                ),
            };
          }
          messageIndex -= displaySlotCount;
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
            child: PendingTranscriptTransition(
              statusText: widget.pendingStatusText,
              startedAt: widget.pendingStartedAt,
              showElapsed: false,
              now: widget.now,
            ),
          );
        },
      ),
    );
  }

  List<_DisplaySlot> _displaySlots(
      List<WorkbenchTranscriptDisplayItem> displayItems) {
    final insertions = _elapsedSegmentsForDisplay(displayItems);
    final slots = <_DisplaySlot>[];
    for (var displayIndex = 0;
        displayIndex <= displayItems.length;
        displayIndex += 1) {
      for (final segment in insertions[displayIndex] ??
          const <ConversationElapsedSegment>[]) {
        slots.add(_ElapsedSlot(segment));
      }
      if (displayIndex < displayItems.length) {
        slots.add(_DisplayItemSlot(displayIndex, displayItems[displayIndex]));
      }
    }
    return slots;
  }

  Map<int, List<ConversationElapsedSegment>> _elapsedSegmentsForDisplay(
      List<WorkbenchTranscriptDisplayItem> displayItems) {
    final insertions = <int, List<ConversationElapsedSegment>>{};
    void addInsertion(int index, ConversationElapsedSegment segment) {
      insertions
          .putIfAbsent(index, () => <ConversationElapsedSegment>[])
          .add(segment);
    }

    if (widget.elapsedSegments.isNotEmpty) {
      for (final segment in widget.elapsedSegments) {
        addInsertion(
          _displayIndexAfterEventSeq(displayItems, segment.afterSeq),
          segment,
        );
      }
    }
    final l10n = AppLocalizations.of(context);
    final shouldInsertSingleElapsed = widget.showPending &&
        (shouldShowPendingTranscriptElapsed(l10n, widget.pendingStatusText) ||
            displayItems.any((item) =>
                item is SingleCommandDisplayItem ||
                item is CommandRunGroupDisplayItem));
    final alreadyHasActiveElapsed = insertions.values
        .expand((items) => items)
        .any((segment) => segment.endedAt == null);
    if (!shouldInsertSingleElapsed || alreadyHasActiveElapsed) {
      return insertions;
    }
    addInsertion(
      _pendingElapsedDisplayIndex(displayItems),
      ConversationElapsedSegment(
        afterSeq: _lastUserEventSeq(displayItems) ?? 0,
        startedAt: widget.pendingStartedAt,
      ),
    );
    return insertions;
  }

  int _pendingElapsedDisplayIndex(
      List<WorkbenchTranscriptDisplayItem> displayItems) {
    for (var index = displayItems.length - 1; index >= 0; index -= 1) {
      final item = displayItems[index];
      if (item is WorkbenchMessageDisplayItem && item.message.role == 'user') {
        return index + 1;
      }
    }
    return 0;
  }

  int? _lastUserEventSeq(List<WorkbenchTranscriptDisplayItem> displayItems) {
    for (var index = displayItems.length - 1; index >= 0; index -= 1) {
      final item = displayItems[index];
      if (item is WorkbenchMessageDisplayItem && item.message.role == 'user') {
        return item.message.eventSeq;
      }
    }
    return null;
  }

  int _displayIndexAfterEventSeq(
      List<WorkbenchTranscriptDisplayItem> displayItems, int afterSeq) {
    for (var index = 0; index < displayItems.length; index += 1) {
      final item = displayItems[index];
      if (item is WorkbenchMessageDisplayItem &&
          item.message.role == 'user' &&
          item.message.eventSeq == afterSeq) {
        return index + 1;
      }
    }
    return 0;
  }

  bool _isActiveCommandItem(WorkbenchTranscriptDisplayItem item) =>
      switch (item) {
        SingleCommandDisplayItem(:final message) => !message.completed,
        CommandRunGroupDisplayItem(:final messages) =>
          messages.any((message) => !message.completed),
        WorkbenchMessageDisplayItem() => false,
      };

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
          color: const Color(0xCC111214),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .085)),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: RepaintBoundary(
                  child: _HistoryLoadingSpinner(
                    color: theme.text.withValues(alpha: .82),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                l10n.workbenchLoadingEarlierEvents,
                style: TextStyle(
                  color: theme.text.withValues(alpha: .82),
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

sealed class _DisplaySlot {
  const _DisplaySlot();
}

class _DisplayItemSlot extends _DisplaySlot {
  const _DisplayItemSlot(this.displayIndex, this.item);

  final int displayIndex;
  final WorkbenchTranscriptDisplayItem item;
}

class _ElapsedSlot extends _DisplaySlot {
  const _ElapsedSlot(this.segment);

  final ConversationElapsedSegment segment;
}

class _HistoryLoadingSpinner extends StatefulWidget {
  const _HistoryLoadingSpinner({required this.color});

  final Color color;

  @override
  State<_HistoryLoadingSpinner> createState() => _HistoryLoadingSpinnerState();
}

class _HistoryLoadingSpinnerState extends State<_HistoryLoadingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const ValueKey('workbench-history-loading-spinner'),
        painter: _HistoryLoadingSpinnerPainter(
          progress: _controller,
          color: widget.color,
        ),
      );
}

class _HistoryLoadingSpinnerPainter extends CustomPainter {
  _HistoryLoadingSpinnerPainter({
    required Animation<double> progress,
    required this.color,
  })  : _progress = progress,
        super(repaint: progress);

  final Animation<double> _progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 2) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = color.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      rect,
      _progress.value * 6.283185307179586,
      4.1887902047863905,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HistoryLoadingSpinnerPainter oldDelegate) =>
      oldDelegate.color != color;
}
