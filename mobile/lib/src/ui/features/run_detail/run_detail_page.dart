import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../services/daemon_client.dart';
import '../../../shell/shell.dart';
import '../../../theme/theme.dart' as theme;
import '../../../widgets/widgets.dart';

class RunDetailPage extends StatelessWidget {
  const RunDetailPage(
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
      TopBar(title: l10n.runDetailTitle, leading: true, action: '?'),
      const SizedBox(height: 14),
      GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(l10n.runDetailMockTask,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          StatusBadge(l10n.runDetailRunningStatus, color: theme.green)
        ]),
        const SizedBox(height: 8),
        const Row(children: [
          AgentIcon(color: theme.orange),
          SizedBox(width: 6),
          Text('Claude Code',
              style: TextStyle(color: theme.muted, fontSize: 12))
        ]),
        const SizedBox(height: 8),
        Text(l10n.runDetailStartedDuration,
            style: const TextStyle(color: theme.muted, fontSize: 12)),
      ])),
      const SizedBox(height: 14),
      Tabs(labels: [
        l10n.runDetailTabOverview,
        l10n.runDetailTabEvents,
        l10n.runDetailTabFileChanges,
        l10n.runDetailTabConfig
      ]),
      const SizedBox(height: 12),
      _Timeline(l10n.runDetailUserPromptTitle, l10n.runDetailUserPromptBody,
          '10:32', Icons.person_rounded, theme.purple),
      _Timeline(l10n.runDetailThinkingTitle, l10n.runDetailThinkingBody,
          '10:32', Icons.auto_awesome_rounded, theme.purple),
      _Timeline(
          l10n.runDetailReadFileTitle,
          'tests/login_test.dart                 +128 -45',
          '10:33',
          Icons.file_open_rounded,
          theme.green),
      _Timeline(l10n.runDetailSearchCodeTitle, l10n.runDetailSearchBody,
          '10:34', Icons.search_rounded, theme.muted),
      _Timeline(
          l10n.runDetailEditFileTitle,
          'lib/services/auth_service.dart       +32 -8',
          '10:35',
          Icons.edit_document,
          theme.green),
      _Timeline(l10n.runDetailRunCommandTitle, l10n.runDetailCommandBody,
          '10:36', Icons.terminal_rounded, theme.green),
      const SizedBox(height: 8),
      GhostButton(l10n.commonBack, color: theme.purple, onTap: onBack),
    ]);
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.title, this.body, this.time, this.icon, this.color);
  final String title, body, time;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withValues(alpha: .18)),
            child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(body,
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: theme.muted, fontSize: 12))
      ]));
}
