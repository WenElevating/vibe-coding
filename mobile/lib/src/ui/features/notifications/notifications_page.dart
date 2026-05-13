import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../theme/theme.dart' as theme;
import '../../../widgets/widgets.dart';

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
      _Notice(Icons.warning_rounded, l10n.notificationsApprovalRequired,
          l10n.notificationsRequestModify, '10:58', theme.amber),
      _Notice(Icons.done_rounded, l10n.notificationsTaskComplete,
          l10n.notificationsRunCompletedDuration, '09:44', theme.green),
      _Notice(
          Icons.error_rounded,
          l10n.notificationsTaskFailed,
          l10n.notificationsDataSyncBody,
          l10n.notificationsYesterday1422,
          theme.red),
      _Notice(
          Icons.sync_rounded,
          l10n.notificationsQueueUpdate,
          l10n.notificationsCacheBody,
          l10n.notificationsYesterday1315,
          theme.purple),
      _Notice(
          Icons.notifications_rounded,
          l10n.notificationsSystemMessage,
          l10n.notificationsConnectedBody,
          l10n.notificationsYesterday1001,
          theme.purple),
      const SizedBox(height: 8),
      GhostButton(l10n.commonBack, color: theme.purple, onTap: onBack),
    ]);
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.icon, this.title, this.body, this.time, this.color);
  final IconData icon;
  final String title, body, time;
  final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: color.withValues(alpha: .22)),
            child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
