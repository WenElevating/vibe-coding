part of '../../app/app.dart';

class _RunDetailPage extends StatelessWidget {
  const _RunDetailPage(
      {required this.onBack, required this.data, required this.client});
  final VoidCallback onBack;
  final AppSnapshot data;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(children: [
      _TopBar(title: '运行详情', leading: true, action: '⋯'),
      const SizedBox(height: 14),
      const _GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('修复登录接口测试失败',
                  style: TextStyle(fontWeight: FontWeight.w800))),
          _StatusBadge('运行中', color: _green)
        ]),
        SizedBox(height: 8),
        Row(children: [
          _AgentIcon(color: _orange),
          SizedBox(width: 6),
          Text('Claude Code', style: TextStyle(color: _muted, fontSize: 12))
        ]),
        SizedBox(height: 8),
        Text('10:32 开始 · 运行时长 12m 45s',
            style: TextStyle(color: _muted, fontSize: 12)),
      ])),
      const SizedBox(height: 14),
      const _Tabs(labels: ['概览', '事件', '文件变更', '配置']),
      const SizedBox(height: 12),
      const _Timeline('用户提示', '修复登录接口测试失败，并添加边界条件测试。', '10:32',
          Icons.person_rounded, _purple),
      const _Timeline('Claude 开始思考', '正在分析问题和相关代码...', '10:32',
          Icons.auto_awesome_rounded, _purple),
      const _Timeline('读取文件', 'tests/login_test.dart                 +128 -45',
          '10:33', Icons.file_open_rounded, _green),
      const _Timeline('搜索代码', 'search: "login failure test"\n找到 12 个结果',
          '10:34', Icons.search_rounded, _muted),
      const _Timeline('编辑文件', 'lib/services/auth_service.dart       +32 -8',
          '10:35', Icons.edit_document, _green),
      const _Timeline('运行命令', 'dart test tests/login_test.dart      运行中 ●',
          '10:36', Icons.terminal_rounded, _green),
      const SizedBox(height: 8),
      _GhostButton('返回', color: _purple, onTap: onBack),
    ]);
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.title, this.body, this.time, this.icon, this.color);
  final String title, body, time;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => _GlassCard(
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
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: _muted, fontSize: 12))
      ]));
}

class _CodeDiff extends StatelessWidget {
  const _CodeDiff();
  @override
  Widget build(BuildContext context) => _GlassCard(
      child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFF081018),
              borderRadius: BorderRadius.circular(6)),
          child: const Text(
              '@@ -48,7 +48,13 @@ Future<User?> login(String email)\n\n-  throw Exception(\'Login failed\');\n+  // 处理边界情况\n+  if (response.body == null ||\n+      response.body.isEmpty) {\n+    throw Exception(\'Empty response\');\n+  }\n+\n   final data = jsonDecode(response.body);',
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF66E69A),
                  fontSize: 11,
                  height: 1.55))));
}

class _ApprovalPreview extends StatelessWidget {
  const _ApprovalPreview({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: const _GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: _amber, size: 18),
          SizedBox(width: 8),
          Text('需要你审批', style: TextStyle(fontWeight: FontWeight.w800)),
          Spacer(),
          Text('10:35', style: TextStyle(color: _muted, fontSize: 12))
        ]),
        SizedBox(height: 8),
        Text('修改文件', style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 4),
        Text('lib/services/auth_service.dart   +32 -8',
            style: TextStyle(color: _muted, fontSize: 12))
      ])));
}
