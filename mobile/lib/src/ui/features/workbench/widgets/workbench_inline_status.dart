import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;

class WorkbenchInlineStatus extends StatelessWidget {
  const WorkbenchInlineStatus({
    super.key,
    required this.adapter,
    required this.runId,
    required this.eventCount,
    required this.terminal,
  });
  final String? adapter;
  final String? runId;
  final int eventCount;
  final bool terminal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = runId == null
        ? l10n.workbenchInlineReady
        : terminal
            ? l10n.workbenchInlineCompleted(eventCount)
            : l10n.workbenchInlineConnecting(adapter ?? 'CLI', eventCount);
    return Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0x66111B2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .075))),
        child: Row(children: [
          _InlineStatusPulseDot(active: runId != null && !terminal),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: theme.muted, fontSize: 12))),
        ]));
  }
}

class _InlineStatusPulseDot extends StatelessWidget {
  const _InlineStatusPulseDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? theme.green : theme.faint,
          boxShadow: active
              ? [
                  BoxShadow(
                      color: theme.green.withValues(alpha: .45),
                      blurRadius: 12,
                      spreadRadius: 2)
                ]
              : null));
}
