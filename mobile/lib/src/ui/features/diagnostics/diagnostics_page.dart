import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../services/daemon_client.dart';
import '../../../shell/shell.dart';
import '../../../theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage(
      {super.key,
      required this.onBack,
      required this.data,
      required this.client});
  final VoidCallback onBack;
  final AppSnapshot data;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      TopBar(title: l10n.diagnosticsTitle, leading: true, action: '?'),
      const SizedBox(height: 10),
      Text(l10n.diagnosticsDescription,
          style: const TextStyle(color: theme.muted, fontSize: 12)),
      const SizedBox(height: 14),
      GlassCard(
          child: Column(children: [
        _DiagRow(l10n.diagnosticsSystemInfo, '1.2 KB'),
        const Hairline(),
        _DiagRow(l10n.diagnosticsAdapterStatus, '2.4 KB'),
        const Hairline(),
        _DiagRow(l10n.diagnosticsRunLogsRecent, '512 KB'),
        const Hairline(),
        _DiagRow(l10n.diagnosticsEventRecordsRecent, '3.1 MB'),
        const Hairline(),
        _DiagRow(l10n.diagnosticsConfigInfo, '1.8 KB')
      ])),
      const SizedBox(height: 18),
      Row(children: [
        Text(l10n.diagnosticsEstimatedSize,
            style: const TextStyle(color: theme.muted, fontSize: 12)),
        const Spacer(),
        const Text('5.1 MB', style: TextStyle(fontWeight: FontWeight.w800))
      ]),
      const SizedBox(height: 18),
      PrimaryButton(l10n.diagnosticsGenerateAction, onTap: onBack),
    ]);
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow(this.title, this.size);
  final String title, size;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: theme.green, size: 17),
        const SizedBox(width: 9),
        Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(size, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
