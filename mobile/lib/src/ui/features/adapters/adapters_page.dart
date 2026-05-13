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
            _AdapterRow(adapter.adapter, adapter.statusText,
                displayVersion(adapter.version), toolColor(adapter.adapter)),
        const SizedBox(height: 16),
        Subhead(l10n.adaptersExtensionsSection),
        if (viewModel.extensions.isEmpty)
          GlassCard(
              child: Text(l10n.adaptersNoExtensions,
                  style: const TextStyle(color: theme.muted)))
        else
          for (final extension in viewModel.extensions)
            _AdapterRow(
                extension.name,
                extension.description,
                extension.installed
                    ? extension.status
                    : l10n.adaptersNotInstalled,
                theme.purple),
        const SizedBox(height: 16),
        PrimaryButton(l10n.commonBack, onTap: onBack),
      ]),
    );
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
        Text(
            '${l10n.adaptersStatusOk}\n${l10n.adaptersCapabilitiesLabel}\n$protocol',
            style:
                const TextStyle(color: theme.muted, fontSize: 12, height: 1.45))
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(version, style: const TextStyle(color: theme.muted, fontSize: 12)),
        const SizedBox(height: 8),
        const Dot(color: theme.green, size: 5)
      ])
    ]));
  }
}
