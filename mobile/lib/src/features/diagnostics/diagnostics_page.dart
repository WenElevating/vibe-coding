part of '../../app/app.dart';

class _DiagnosticsPage extends StatelessWidget {
  const _DiagnosticsPage(
      {required this.onBack, required this.data, required this.client});
  final VoidCallback onBack;
  final _AppSnapshot data;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) => _PageScroll(children: [
        _TopBar(title: '诊断信息', leading: true, action: '⋯'),
        const SizedBox(height: 10),
        const Text('导出诊断包用于问题排查（已脱敏）',
            style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 14),
        const _GlassCard(
            child: Column(children: [
          _DiagRow('系统信息', '1.2 KB'),
          _Hairline(),
          _DiagRow('适配器状态', '2.4 KB'),
          _Hairline(),
          _DiagRow('运行日志 (最近 7 天)', '512 KB'),
          _Hairline(),
          _DiagRow('事件记录 (最近 7 天)', '3.1 MB'),
          _Hairline(),
          _DiagRow('配置信息', '1.8 KB')
        ])),
        const SizedBox(height: 18),
        const Row(children: [
          Text('预计大小', style: TextStyle(color: _muted, fontSize: 12)),
          Spacer(),
          Text('5.1 MB', style: TextStyle(fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 18),
        _PrimaryButton('生成诊断包', onTap: onBack),
      ]);
}

class _DiagRow extends StatelessWidget {
  const _DiagRow(this.title, this.size);
  final String title, size;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: _green, size: 17),
        const SizedBox(width: 9),
        Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(size, style: const TextStyle(color: _muted, fontSize: 12))
      ]));
}
