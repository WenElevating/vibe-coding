import 'package:flutter/material.dart';

import '../../shell/shell.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';

class AdaptersPage extends StatelessWidget {
  const AdaptersPage({super.key, required this.onBack, required this.data});
  final VoidCallback onBack;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) => PageScroll(children: [
        TopBar(
            title: '适配器状态', leading: true, action: '${data.adapters.length} 个'),
        const SizedBox(height: 14),
        if (data.adapters.isEmpty)
          const GlassCard(
              child:
                  Text('daemon 未返回适配器', style: TextStyle(color: theme.muted)))
        else
          for (final adapter in data.adapters)
            _AdapterRow(adapter.adapter, adapter.statusText,
                displayVersion(adapter.version), toolColor(adapter.adapter)),
        const SizedBox(height: 16),
        const Subhead('扩展'),
        if (data.extensions.isEmpty)
          const GlassCard(
              child: Text('暂无扩展信息', style: TextStyle(color: theme.muted)))
        else
          for (final extension in data.extensions)
            _AdapterRow(
                extension.name,
                extension.description,
                extension.installed ? extension.status : 'not installed',
                theme.purple),
        const SizedBox(height: 16),
        PrimaryButton('返回', onTap: onBack),
      ]);
}

class _AdapterRow extends StatelessWidget {
  const _AdapterRow(this.name, this.protocol, this.version, this.color);
  final String name, protocol, version;
  final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
          child: Row(children: [
        AgentIcon(color: color),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('状态                         正常\n能力\n$protocol',
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.45))
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(version,
              style: const TextStyle(color: theme.muted, fontSize: 12)),
          const SizedBox(height: 8),
          const Dot(color: theme.green, size: 5)
        ])
      ]));
}
