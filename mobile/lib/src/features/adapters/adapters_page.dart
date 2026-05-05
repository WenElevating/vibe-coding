import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../shell/shell.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';

class AdaptersPage extends StatelessWidget {
  const AdaptersPage({super.key, required this.onBack, required this.data});
  final VoidCallback onBack;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      TopBar(
          title: l10n.adaptersTitle,
          leading: true,
          action: l10n.adaptersCount(data.adapters.length)),
      const SizedBox(height: 14),
      if (data.adapters.isEmpty)
        GlassCard(
            child: Text(l10n.adaptersEmpty,
                style: const TextStyle(color: theme.muted)))
      else
        for (final adapter in data.adapters)
          _AdapterRow(adapter.adapter, adapter.statusText,
              displayVersion(adapter.version), toolColor(adapter.adapter)),
      const SizedBox(height: 16),
      Subhead(l10n.adaptersExtensionsSection),
      if (data.extensions.isEmpty)
        GlassCard(
            child: Text(l10n.adaptersNoExtensions,
                style: const TextStyle(color: theme.muted)))
      else
        for (final extension in data.extensions)
          _AdapterRow(
              extension.name,
              extension.description,
              extension.installed ? extension.status : l10n.adaptersNotInstalled,
              theme.purple),
      const SizedBox(height: 16),
      PrimaryButton(l10n.commonBack, onTap: onBack),
    ]);
  }
}

class _AdapterRow extends StatelessWidget {
  const _AdapterRow(this.name, this.protocol, this.version, this.color);
  final String name, protocol, version;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassCard(
        child: Row(children: [
      AgentIcon(color: color),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('${l10n.adaptersStatusOk}\n${l10n.adaptersCapabilitiesLabel}\n$protocol',
            style: const TextStyle(
                color: theme.muted, fontSize: 12, height: 1.45))
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(version, style: const TextStyle(color: theme.muted, fontSize: 12)),
        const SizedBox(height: 8),
        const Dot(color: theme.green, size: 5)
      ])
    ]));
  }
}
