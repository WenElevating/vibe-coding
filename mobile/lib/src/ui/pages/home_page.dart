import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';
import '../../widgets/widgets.dart';
import '../../theme/theme.dart' as theme;
import 'run_status_color.dart';

class HomePage extends StatelessWidget {
  const HomePage(
      {super.key,
      required this.open,
      required this.selectTab,
      required this.data});
  final ValueChanged<RoutePage> open;
  final ValueChanged<int> selectTab;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(
      children: [
        TopBar(
            title: data.overview.name,
            subtitle:
                '${data.health.bindAddress}:${data.health.port}  ${data.health.status}',
            showScan: true),
        const SizedBox(height: 18),
        SectionTitle(l10n.homeOverviewTitle),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: MetricCard(
                    label: l10n.homeRunningMetricLabel,
                    value: '${data.runningRuns.length}',
                    note: l10n.homeRunningMetricNote,
                    colors: [Color(0xFF322A8D), Color(0xFF18204C)])),
            const SizedBox(width: 8),
            Expanded(
                child: MetricCard(
                    label: l10n.homeQueuedMetricLabel,
                    value: '${data.queue.length}',
                    note: l10n.homeQueuedMetricNote,
                    colors: [Color(0xFF073B32), Color(0xFF0B2728)])),
            const SizedBox(width: 8),
            Expanded(
                child: MetricCard(
                    label: l10n.homeCompletedMetricLabel,
                    value: '${data.overview.analysisScore}',
                    note: l10n.homeFilesLinesNote(
                        data.overview.fileCount, data.overview.codeLineCount),
                    colors: [Color(0xFF18212D), Color(0xFF101721)])),
          ],
        ),
        const SizedBox(height: 18),
        SectionTitle(l10n.homeRecentRunsTitle,
            action: l10n.homeViewAllAction, onAction: () => selectTab(1)),
        const SizedBox(height: 10),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (data.runs.isEmpty)
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(l10n.homeNoRuns,
                        style: const TextStyle(color: theme.muted)))
              else
                for (final run in data.runs.take(4).toList()) ...[
                  CompactRun(
                      title: run.id,
                      tool: run.tool,
                      time: run.workspaceId,
                      status: run.status,
                      color: runStatusColor(run.status),
                      iconColor: runToolColor(run.tool),
                      onTap: () => open(RoutePage.detail)),
                  if (run != data.runs.take(4).last) const Hairline(),
                ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionTitle(l10n.homeQuickActionsTitle),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: QuickAction(
                    icon: Icons.add_box_rounded,
                    title: l10n.homeNewTaskTitle,
                    subtitle: l10n.homeNewTaskSubtitle,
                    color: theme.purple,
                    onTap: () => selectTab(1))),
            const SizedBox(width: 10),
            Expanded(
                child: QuickAction(
                    icon: Icons.drive_file_move_rounded,
                    title: l10n.homeCommandTemplatesTitle,
                    subtitle: l10n.homeCommandTemplatesSubtitle,
                    color: theme.green,
                    onTap: () => selectTab(2))),
            const SizedBox(width: 10),
            Expanded(
                child: QuickAction(
                    icon: Icons.view_list_rounded,
                    title: l10n.homeViewQueueTitle,
                    subtitle: l10n.homeViewQueueSubtitle,
                    color: theme.orange,
                    onTap: () => selectTab(3))),
          ],
        ),
        const SizedBox(height: 18),
        ApprovalPreview(onTap: () => open(RoutePage.approval)),
      ],
    );
  }
}
