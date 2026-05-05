import 'package:flutter/material.dart';

import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';
import '../../widgets/widgets.dart';
import '../../theme/theme.dart' as theme;
import 'run_status_color.dart';

class RunsPage extends StatelessWidget {
  const RunsPage({super.key, required this.open, required this.data});
  final ValueChanged<RoutePage> open;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    return PageScroll(
      floating: FloatingPlus(onTap: () => open(RoutePage.detail)),
      children: [
        TopBar(title: '运行列表'),
        const SizedBox(height: 20),
        Row(children: [
          Pill('全部 ${data.runs.length}', selected: true),
          Pill('运行中 ${data.runningRuns.length}'),
          Pill('已完成 ${data.completedRuns.length}'),
          Pill('失败 ${data.failedRuns.length}'),
        ]),
        const SizedBox(height: 14),
        const AppSearchBar(),
        const SizedBox(height: 14),
        if (data.runs.isEmpty)
          const GlassCard(
              child: Text('暂无运行。可从命令模板发起真实 AI CLI 任务。',
                  style: TextStyle(color: theme.muted)))
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
