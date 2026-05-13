import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';
import '../core/widgets/widgets.dart';
import '../core/theme/theme.dart' as theme;
import 'run_status_color.dart';

class RunsPage extends StatelessWidget {
  const RunsPage({super.key, required this.open, required this.data});
  final ValueChanged<RoutePage> open;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(
      floating: FloatingPlus(onTap: () => open(RoutePage.detail)),
      children: [
        TopBar(title: l10n.runsTitle),
        const SizedBox(height: 20),
        Row(children: [
          Pill(l10n.runsAllPill(data.runs.length), selected: true),
          Pill(l10n.runsRunningPill(data.runningRuns.length)),
          Pill(l10n.runsCompletedPill(data.completedRuns.length)),
          Pill(l10n.runsFailedPill(data.failedRuns.length)),
        ]),
        const SizedBox(height: 14),
        const AppSearchBar(),
        const SizedBox(height: 14),
        if (data.runs.isEmpty)
          GlassCard(
              child: Text(l10n.runsEmpty,
                  style: const TextStyle(color: theme.muted)))
        else
          for (final run in data.runs) ...[
            RunCard(
                title: run.id,
                tool: run.tool,
                time: 'workspace: ${run.workspaceId}',
                status: run.status,
                progress: run.status == 'completed' ? 1 : .48,
                statusColor: runStatusColor(run.status),
                onTap: () => open(RoutePage.detail)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}
