import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';

class TaskProgressCard extends StatelessWidget {
  const TaskProgressCard({super.key, required this.message});

  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final completed = message.completedCount ??
        message.taskItems.where((item) => item.status == 'completed').length;
    final total = message.totalCount ?? message.taskItems.length;
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
        decoration: BoxDecoration(
            color: const Color(0xFF111316).withValues(alpha: .96),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: .085))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.checklist_rounded, color: theme.muted, size: 15),
            const SizedBox(width: 7),
            Expanded(
                child: Text(l10n.workbenchTaskProgressTitle,
                    style: const TextStyle(
                        color: theme.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0))),
            TaskProgressBadge(completed: completed, total: total, l10n: l10n),
          ]),
          const SizedBox(height: 9),
          ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                  value: total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: Colors.white.withValues(alpha: .055),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(theme.green))),
          const SizedBox(height: 6),
          ...List<Widget>.generate(message.taskItems.length, (index) {
            final item = message.taskItems[index];
            return TaskProgressRow(
                item: item,
                l10n: l10n,
                index: index + 1,
                last: index == message.taskItems.length - 1);
          }),
        ]));
  }
}

class TaskProgressBadge extends StatelessWidget {
  const TaskProgressBadge(
      {super.key,
      required this.completed,
      required this.total,
      required this.l10n});

  final int completed;
  final int total;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final done = total > 0 && completed >= total;
    return Text(
        done
            ? l10n.workbenchTaskProgressComplete
            : l10n.workbenchTaskProgressDoneCount(completed, total),
        style: TextStyle(
            color: done ? theme.green : theme.faint,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0));
  }
}

class TaskProgressRow extends StatelessWidget {
  const TaskProgressRow({
    super.key,
    required this.item,
    required this.l10n,
    required this.index,
    required this.last,
  });

  final TaskProgressItem item;
  final AppLocalizations l10n;
  final int index;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final status = taskProgressStatus(l10n, item.status);
    return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: last
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: .055)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
              width: 20,
              child: Text(index.toString().padLeft(2, '0'),
                  style: const TextStyle(
                      color: theme.faint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0))),
          TaskProgressDot(color: status.color, icon: status.icon),
          const SizedBox(width: 9),
          Expanded(
              child: Text(item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color:
                          item.status == 'completed' ? theme.muted : theme.text,
                      fontSize: 12.8,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0))),
          const SizedBox(width: 8),
          TaskProgressStatePill(status: status),
        ]));
  }
}

class TaskProgressDot extends StatelessWidget {
  const TaskProgressDot({super.key, required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .12),
          border: Border.all(color: color.withValues(alpha: .32))),
      child: Icon(icon, color: color, size: 11));
}

class TaskProgressStatePill extends StatelessWidget {
  const TaskProgressStatePill({super.key, required this.status});

  final ({Color color, IconData icon, String label}) status;

  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minWidth: 62),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: status.color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: status.color.withValues(alpha: .18))),
      child: Text(status.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: status.color.withValues(alpha: .9),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0)));
}

({Color color, IconData icon, String label}) taskProgressStatus(
        AppLocalizations l10n, String status) =>
    switch (status) {
      'completed' => (
          color: theme.green,
          icon: Icons.check_rounded,
          label: l10n.workbenchTaskProgressStatusDone
        ),
      'in_progress' => (
          color: theme.amber,
          icon: Icons.more_horiz_rounded,
          label: l10n.workbenchTaskProgressStatusActive
        ),
      'pending' => (
          color: theme.faint,
          icon: Icons.circle_outlined,
          label: l10n.workbenchTaskProgressStatusQueued
        ),
      _ => (
          color: theme.muted,
          icon: Icons.circle_outlined,
          label:
              status.isEmpty ? l10n.workbenchTaskProgressStatusQueued : status
        ),
    };

@visibleForTesting
Widget buildTaskProgressCardPreview() {
  const message = WorkbenchMessage(
      'task_progress', 'Task progress', 'Task progress updated',
      runId: 'conversation',
      taskId: 'task_1',
      completedCount: 1,
      totalCount: 3,
      taskItems: <TaskProgressItem>[
        TaskProgressItem(
            id: 'task_1_item_1', title: '分析工作区结构', status: 'completed'),
        TaskProgressItem(
            id: 'task_1_item_2', title: '实现进度卡片', status: 'in_progress'),
        TaskProgressItem(
            id: 'task_1_item_3', title: '运行回归测试', status: 'pending'),
      ]);
  return MaterialApp(
      locale: theme.zhHansCnLocale,
      supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: theme.appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: theme.appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: theme.bg,
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: TaskProgressCard(message: message))));
}
