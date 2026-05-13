import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';

class ApprovalPage extends StatelessWidget {
  const ApprovalPage({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      TopBar(
          title: l10n.workbenchApprovalPageTitle, leading: true, action: '?'),
      const SizedBox(height: 14),
      GlassCard(
          child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: theme.amber),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.workbenchModifyFileTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('lib/services/auth_service.dart     +32 -8',
              style: TextStyle(color: theme.muted, fontSize: 12))
        ])),
        const Text('10:35', style: TextStyle(color: theme.muted, fontSize: 12))
      ])),
      const SizedBox(height: 12),
      Tabs(labels: [l10n.workbenchDiffTab, l10n.workbenchFileContentTab]),
      const SizedBox(height: 10),
      const CodeDiff(),
      const SizedBox(height: 18),
      SectionTitle(l10n.workbenchApprovalActionsSection),
      GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.workbenchClaudeSuggestionTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(l10n.workbenchMockFixEmptyResponse,
            style: const TextStyle(color: theme.muted, fontSize: 12))
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: GhostButton(l10n.workbenchRejectAction,
                color: theme.red, onTap: onBack)),
        const SizedBox(width: 10),
        Expanded(
            child: PrimaryButton(l10n.workbenchApproveAction, onTap: onBack))
      ]),
    ]);
  }
}
