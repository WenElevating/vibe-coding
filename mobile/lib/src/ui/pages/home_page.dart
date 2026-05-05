import 'package:flutter/material.dart';

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
    return PageScroll(
      children: [
        TopBar(
            title: data.overview.name,
            subtitle:
                '${data.health.bindAddress}:${data.health.port}  ${data.health.status}',
            showScan: true),
        const SizedBox(height: 18),
        SectionTitle('概览'),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: MetricCard(
                    label: '运行中',
                    value: '${data.runningRuns.length}',
                    note: '活跃任务',
                    colors: [Color(0xFF322A8D), Color(0xFF18204C)])),
            const SizedBox(width: 8),
            Expanded(
                child: MetricCard(
                    label: '待审批',
                    value: '${data.queue.length}',
                    note: '队列任务',
                    colors: [Color(0xFF073B32), Color(0xFF0B2728)])),
            const SizedBox(width: 8),
            Expanded(
                child: MetricCard(
                    label: '已完成 (24h)',
                    value: '${data.overview.analysisScore}',
                    note:
                        '${data.overview.fileCount} 文件 · ${data.overview.codeLineCount} 行',
                    colors: [Color(0xFF18212D), Color(0xFF101721)])),
          ],
        ),
        const SizedBox(height: 18),
        SectionTitle('最近运行', action: '查看全部', onAction: () => selectTab(1)),
        const SizedBox(height: 10),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (data.runs.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无运行记录', style: TextStyle(color: theme.muted)))
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
        const SectionTitle('快捷操作'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: QuickAction(
                    icon: Icons.add_box_rounded,
                    title: '新建任务',
                    subtitle: '创建新任务',
                    color: theme.purple,
                    onTap: () => selectTab(1))),
            const SizedBox(width: 10),
            Expanded(
                child: QuickAction(
                    icon: Icons.drive_file_move_rounded,
                    title: '命令模板',
                    subtitle: '执行预设命令',
                    color: theme.green,
                    onTap: () => selectTab(2))),
            const SizedBox(width: 10),
            Expanded(
                child: QuickAction(
                    icon: Icons.view_list_rounded,
                    title: '查看队列',
                    subtitle: '查看排队任务',
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
