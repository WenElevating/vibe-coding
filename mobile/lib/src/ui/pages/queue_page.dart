import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../shell/app_snapshot.dart';
import '../core/widgets/widgets.dart';
import '../core/theme/theme.dart' as theme;

class QueuePage extends StatelessWidget {
  const QueuePage({super.key, required this.data});
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active =
        data.queue.where((item) => item.status == 'running').toList();
    final waiting =
        data.queue.where((item) => item.status != 'running').toList();
    return PageScroll(
      children: [
        TopBar(
            title: l10n.queueTitle,
            leading: true,
            action: l10n.queueCountAction(data.queue.length)),
        const SizedBox(height: 20),
        Row(children: [
          Pill(l10n.queueRunningPill(active.length),
              selected: true, green: true),
          Pill(l10n.queueWaitingPill(waiting.length), amber: true),
          Pill(l10n.queueTotalPill(data.queue.length))
        ]),
        const SizedBox(height: 22),
        Subhead(l10n.queueRunningSection),
        GlassCard(
          child: active.isEmpty
              ? Text(l10n.queueNoRunning,
                  style: const TextStyle(color: theme.muted))
              : Column(children: [
                  for (final item in active) ...[
                    QueueRow(
                        title: item.runId,
                        tool: item.reason.isEmpty ? item.status : item.reason,
                        iconColor: theme.green),
                    if (item != active.last) const Hairline(),
                  ],
                ]),
        ),
        const SizedBox(height: 24),
        Subhead(l10n.queueWaitingSection),
        GlassCard(
          padding: EdgeInsets.zero,
          child: waiting.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(l10n.queueNoWaiting,
                      style: const TextStyle(color: theme.muted)))
              : Column(children: [
                  for (final item in waiting) ...[
                    WaitingRow(
                        index: '${item.position}',
                        title: item.runId,
                        tool: item.reason.isEmpty ? item.status : item.reason,
                        statusLabel: l10n.queueWaitingStatus),
                    if (item != waiting.last) const Hairline(),
                  ],
                ]),
        ),
        const SizedBox(height: 20),
        Text(l10n.queueFootnote,
            style: const TextStyle(color: theme.muted, fontSize: 12)),
      ],
    );
  }
}
