import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';
import 'view_models/diagnostics_view_model.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({
    super.key,
    required this.onBack,
    required this.viewModel,
  });

  final VoidCallback onBack;
  final DiagnosticsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => PageScroll(children: [
        TopBar(title: l10n.diagnosticsTitle, leading: true, action: '?'),
        const SizedBox(height: 10),
        Text(l10n.diagnosticsDescription,
            style: const TextStyle(color: theme.muted, fontSize: 12)),
        const SizedBox(height: 14),
        GlassCard(
            child: Column(children: [
          _DiagRow(l10n.diagnosticsSystemInfo),
          const Hairline(),
          _DiagRow(l10n.diagnosticsAdapterStatus),
          const Hairline(),
          _DiagRow(l10n.diagnosticsRunLogsRecent),
          const Hairline(),
          _DiagRow(l10n.diagnosticsEventRecordsRecent),
          const Hairline(),
          _DiagRow(l10n.diagnosticsConfigInfo)
        ])),
        if (viewModel.error != null) ...[
          const SizedBox(height: 12),
          Text(viewModel.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: theme.red, fontSize: 12)),
        ],
        if (viewModel.bundle != null) ...[
          const SizedBox(height: 12),
          Text(viewModel.bundle!.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: theme.green, fontSize: 12)),
        ],
        const SizedBox(height: 18),
        PrimaryButton(
          l10n.diagnosticsGenerateAction,
          onTap: viewModel.isLoading ? null : viewModel.createBundle,
        ),
        const SizedBox(height: 8),
        GhostButton(l10n.commonBack, color: theme.purple, onTap: onBack),
      ]),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: theme.green, size: 17),
        const SizedBox(width: 9),
        Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800))),
      ]));
}
