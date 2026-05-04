part of '../../app/app.dart';

class _ApprovalPage extends StatelessWidget {
  const _ApprovalPage({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(children: [
      _TopBar(title: '需要你审批', leading: true, action: '⋯'),
      const SizedBox(height: 14),
      const _GlassCard(
          child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: _amber),
        SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('修改文件', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('lib/services/auth_service.dart     +32 -8',
              style: TextStyle(color: _muted, fontSize: 12))
        ])),
        Text('10:35', style: TextStyle(color: _muted, fontSize: 12))
      ])),
      const SizedBox(height: 12),
      const _Tabs(labels: ['差异', '文件内容']),
      const SizedBox(height: 10),
      const _CodeDiff(),
      const SizedBox(height: 18),
      const _SectionTitle('审批操作'),
      const _GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Claude 建议的变更', style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text('修复空响应导致的测试失败问题', style: TextStyle(color: _muted, fontSize: 12))
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _GhostButton('拒绝', color: _red, onTap: onBack)),
        const SizedBox(width: 10),
        Expanded(child: _PrimaryButton('批准', onTap: onBack))
      ]),
    ]);
  }
}
