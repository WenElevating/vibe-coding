import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';
import 'view_models/run_detail_view_model.dart';

class RunDetailPage extends StatefulWidget {
  const RunDetailPage({
    super.key,
    required this.onBack,
    required this.viewModel,
  });

  final VoidCallback onBack;
  final RunDetailViewModel viewModel;

  @override
  State<RunDetailPage> createState() => _RunDetailPageState();
}

class _RunDetailPageState extends State<RunDetailPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.loadEvents());
  }

  @override
  void didUpdateWidget(covariant RunDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      unawaited(widget.viewModel.loadEvents());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final run = widget.viewModel.run;
    return PageScroll(children: [
      TopBar(title: l10n.runDetailTitle, leading: true, action: '?'),
      const SizedBox(height: 14),
      GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(run.id,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          StatusBadge(run.status, color: _colorForRunStatus(run.status))
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const AgentIcon(color: theme.orange),
          const SizedBox(width: 6),
          Text(run.tool,
              style: const TextStyle(color: theme.muted, fontSize: 12))
        ]),
        const SizedBox(height: 8),
        Text(l10n.runDetailWorkspaceLabel(run.workspaceId),
            style: const TextStyle(color: theme.muted, fontSize: 12)),
      ])),
      const SizedBox(height: 14),
      Tabs(labels: [
        l10n.runDetailTabOverview,
        l10n.runDetailTabEvents,
        l10n.runDetailTabFileChanges,
        l10n.runDetailTabConfig
      ]),
      const SizedBox(height: 12),
      if (widget.viewModel.error != null) ...[
        GlassCard(
            child: Text(widget.viewModel.error!,
                style: const TextStyle(color: theme.red, fontSize: 12))),
        const SizedBox(height: 12),
      ],
      if (widget.viewModel.events.isEmpty) ...[
        _EmptyTimelineState(
          isLoading: widget.viewModel.isLoading,
          l10n: l10n,
        ),
      ] else
        for (final event in widget.viewModel.events)
          _Timeline(
            event.name ?? event.type,
            event.text ?? event.type,
            _formatEventTime(event.createdAt),
            _iconForEvent(event.type),
            _colorForEvent(event.type),
          ),
      const SizedBox(height: 8),
      GhostButton(l10n.commonBack, color: theme.purple, onTap: widget.onBack),
    ]);
  }
}

String _formatEventTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

IconData _iconForEvent(String type) {
  if (type.contains('tool') || type.contains('command')) {
    return Icons.terminal_rounded;
  }
  if (type.contains('file') || type.contains('diff')) {
    return Icons.file_open_rounded;
  }
  if (type.contains('approval')) {
    return Icons.verified_user_rounded;
  }
  if (type.contains('run.')) {
    return Icons.play_circle_fill_rounded;
  }
  return Icons.auto_awesome_rounded;
}

Color _colorForEvent(String type) {
  if (type == 'run.failed' || type.contains('error')) {
    return theme.red;
  }
  if (type == 'run.completed' || type.contains('diff')) {
    return theme.green;
  }
  if (type.contains('approval')) {
    return theme.orange;
  }
  return theme.purple;
}

Color _colorForRunStatus(String status) {
  switch (status) {
    case 'completed':
      return theme.green;
    case 'failed':
    case 'cancelled':
      return theme.red;
    case 'queued':
      return theme.orange;
    default:
      return theme.purple;
  }
}

class _EmptyTimelineState extends StatelessWidget {
  const _EmptyTimelineState({required this.isLoading, required this.l10n});

  final bool isLoading;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.purple.withValues(alpha: .18)),
              child: Icon(
                  isLoading ? Icons.sync_rounded : Icons.timeline_rounded,
                  color: theme.purple,
                  size: 15)),
          const SizedBox(width: 10),
          Text(isLoading ? l10n.runDetailLoadingEvents : l10n.runDetailNoEvents,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 7),
        Text(l10n.runDetailEmptyEventsDescription,
            style: const TextStyle(
                color: theme.muted, fontSize: 12, height: 1.45)),
      ]));
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.title, this.body, this.time, this.icon, this.color);
  final String title, body, time;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withValues(alpha: .18)),
            child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(body,
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
