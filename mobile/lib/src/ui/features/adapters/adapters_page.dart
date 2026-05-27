import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';
import 'view_models/adapters_view_model.dart';

class AdaptersPage extends StatelessWidget {
  const AdaptersPage(
      {super.key, required this.onBack, required this.viewModel});
  final VoidCallback onBack;
  final AdaptersViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => PageScroll(children: [
        TopBar(
            title: l10n.adaptersTitle,
            leading: true,
            action: l10n.adaptersCount(viewModel.adapters.length)),
        const SizedBox(height: 14),
        if (viewModel.adapters.isEmpty)
          GlassCard(
              child: Text(l10n.adaptersEmpty,
                  style: const TextStyle(color: theme.muted)))
        else
          for (final adapter in viewModel.adapters)
            _AdapterRow(
              name: adapter.adapter,
              subtitle: adapter.available
                  ? l10n.adaptersStatusOk
                  : adapter.statusText,
              trailing: displayVersion(adapter.version),
              color: adapter.available ? toolColor(adapter.adapter) : theme.red,
              healthy: adapter.available,
            ),
        const SizedBox(height: 16),
        Subhead(l10n.adaptersExtensionsSection),
        if (viewModel.extensions.isEmpty)
          GlassCard(
              child: Text(l10n.adaptersNoExtensions,
                  style: const TextStyle(color: theme.muted)))
        else
          for (final extension in viewModel.extensions)
            _AdapterRow(
              name: extension.name,
              subtitle: extension.description,
              trailing: extension.installed
                  ? extension.status
                  : l10n.adaptersNotInstalled,
              color: extension.installed ? theme.purple : theme.amber,
              healthy: extension.installed,
            ),
        const SizedBox(height: 16),
        PrimaryButton(l10n.commonBack, onTap: onBack),
      ]),
    );
  }
}

class _AdapterRow extends StatelessWidget {
  const _AdapterRow({
    required this.name,
    required this.subtitle,
    required this.trailing,
    required this.color,
    required this.healthy,
  });
  final String name, subtitle, trailing;
  final Color color;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
        child: Row(children: [
      AgentIcon(color: color),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: theme.muted, fontSize: 12, height: 1.45))
      ])),
      const SizedBox(width: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 96),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(trailing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(color: theme.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Dot(color: healthy ? theme.green : theme.amber, size: 5)
        ]),
      )
    ]));
  }
}
