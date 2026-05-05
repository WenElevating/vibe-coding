import 'package:flutter/material.dart';

import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => PageScroll(children: [
        TopBar(title: '通知', leading: true, action: '⋯'),
        const SizedBox(height: 14),
        const Tabs(labels: ['全部', '未读', '@我']),
        const SizedBox(height: 12),
        const _Notice(
            Icons.warning_rounded,
            '需要审批',
            'Claude Code 请求修改\nlib/services/auth_service.dart',
            '10:58',
            theme.amber),
        const _Notice(
            Icons.done_rounded,
            '任务完成',
            'Add unit tests for user service\n运行完成，耗时 28m 15s',
            '09:44',
            theme.green),
        const _Notice(Icons.error_rounded, '任务失败', '优化数据同步逻辑\n运行失败，查看详情',
            '昨天 14:22', theme.red),
        const _Notice(Icons.sync_rounded, '队列更新', '优化缓存策略\n已开始运行', '昨天 13:15',
            theme.purple),
        const _Notice(Icons.notifications_rounded, '系统消息', '已连接到 DESKTOP-DEV',
            '昨天 10:01', theme.purple),
        const SizedBox(height: 8),
        GhostButton('返回', color: theme.purple, onTap: onBack),
      ]);
}

class _Notice extends StatelessWidget {
  const _Notice(this.icon, this.title, this.body, this.time, this.color);
  final IconData icon;
  final String title, body, time;
  final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: color.withValues(alpha: .22)),
            child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
