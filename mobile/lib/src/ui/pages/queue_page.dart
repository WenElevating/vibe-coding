import 'package:flutter/material.dart';

import '../../shell/app_snapshot.dart';
import '../../widgets/widgets.dart';
import '../../theme/theme.dart' as theme;

class QueuePage extends StatelessWidget {
  const QueuePage({super.key, required this.data});
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    final active =
        data.queue.where((item) => item.status == 'running').toList();
    final waiting =
        data.queue.where((item) => item.status != 'running').toList();
    return PageScroll(
      children: [
        TopBar(title: '运行队列', leading: true, action: '${data.queue.length} 项'),
        const SizedBox(height: 20),
        Row(children: [
          Pill('运行中 ${active.length}', selected: true, green: true),
          Pill('排队中 ${waiting.length}', amber: true),
          Pill('总计 ${data.queue.length}')
        ]),
        const SizedBox(height: 22),
        const Subhead('运行中'),
        GlassCard(
          child: active.isEmpty
              ? const Text('暂无运行中队列', style: TextStyle(color: theme.muted))
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
        const Subhead('排队中'),
        GlassCard(
          padding: EdgeInsets.zero,
          child: waiting.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('暂无等待任务', style: TextStyle(color: theme.muted)))
              : Column(children: [
                  for (final item in waiting) ...[
                    WaitingRow(
                        index: '${item.position}',
                        title: item.runId,
                        tool: item.reason.isEmpty ? item.status : item.reason),
                    if (item != waiting.last) const Hairline(),
                  ],
                ]),
        ),
        const SizedBox(height: 20),
        const Text('队列数据来自 daemon，任务按工作区顺序执行。',
            style: TextStyle(color: theme.muted, fontSize: 12)),
      ],
    );
  }
}
