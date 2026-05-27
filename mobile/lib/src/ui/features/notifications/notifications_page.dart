import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      TopBar(title: l10n.notificationsTitle, leading: true, action: '?'),
      const SizedBox(height: 14),
      Tabs(labels: [
        l10n.notificationsTabAll,
        l10n.notificationsTabUnread,
        l10n.notificationsTabMentions
      ]),
      const SizedBox(height: 12),
      GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: theme.purple.withValues(alpha: .22)),
            child: const Icon(Icons.notifications_rounded,
                color: theme.purple, size: 16)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(l10n.homeNoRecentActivity,
                style: const TextStyle(fontWeight: FontWeight.w800))),
      ])),
      const SizedBox(height: 8),
      GhostButton(l10n.commonBack, color: theme.purple, onTap: onBack),
    ]);
  }
}
