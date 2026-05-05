import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../shell/shell.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';

class RunDetailPage extends StatelessWidget {
  const RunDetailPage(
      {super.key,
      required this.onBack,
      required this.data,
      required this.client});
  final VoidCallback onBack;
  final AppSnapshot data;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) {
    return PageScroll(children: [
      TopBar(title: '运行详情', leading: true, action: '⋯'),
      const SizedBox(height: 14),
      const GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('修复登录接口测试失败',
                  style: TextStyle(fontWeight: FontWeight.w800))),
          StatusBadge('运行中', color: theme.green)
        ]),
        SizedBox(height: 8),
        Row(children: [
          AgentIcon(color: theme.orange),
          SizedBox(width: 6),
          Text('Claude Code', style: TextStyle(color: theme.muted, fontSize: 12))
        ]),
        SizedBox(height: 8),
        Text('10:32 开始 · 运行时长 12m 45s',
            style: TextStyle(color: theme.muted, fontSize: 12)),
      ])),
      const SizedBox(height: 14),
      const Tabs(labels: ['概览', '事件', '文件变更', '配置']),
      const SizedBox(height: 12),
      const _Timeline('用户提示', '修复登录接口测试失败，并添加边界条件测试。', '10:32',
          Icons.person_rounded, theme.purple),
      const _Timeline('Claude 开始思考', '正在分析问题和相关代码...', '10:32',
          Icons.auto_awesome_rounded, theme.purple),
      const _Timeline('读取文件', 'tests/login_test.dart                 +128 -45',
          '10:33', Icons.file_open_rounded, theme.green),
      const _Timeline('搜索代码', 'search: "login failure test"\n找到 12 个结果',
          '10:34', Icons.search_rounded, theme.muted),
      const _Timeline('编辑文件', 'lib/services/auth_service.dart       +32 -8',
          '10:35', Icons.edit_document, theme.green),
      const _Timeline('运行命令', 'dart test tests/login_test.dart      运行中 ●',
          '10:36', Icons.terminal_rounded, theme.green),
      const SizedBox(height: 8),
      GhostButton('返回', color: theme.purple, onTap: onBack),
    ]);
  }
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
              style: const TextStyle(color: theme.muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
