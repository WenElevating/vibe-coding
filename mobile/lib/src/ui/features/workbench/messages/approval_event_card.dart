import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';
import 'event_card_frame.dart';

class ApprovalActionButton extends StatelessWidget {
  const ApprovalActionButton(this.text,
      {super.key,
      required this.color,
      required this.onTap,
      this.primary = false});
  final String text;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: primary
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2F3034), Color(0xFF1A1B1E)])
                  : null,
              color: primary ? null : color.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: primary
                      ? Colors.white.withValues(alpha: .14)
                      : color.withValues(alpha: .34))),
          child: Text(text,
              style: TextStyle(
                  color: primary ? theme.text : color,
                  fontSize: 13,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w800))));
}

class ApprovalEventCard extends StatelessWidget {
  const ApprovalEventCard(
      {super.key, required this.message, required this.onApproval});
  final WorkbenchMessage message;
  final ValueChanged<String> onApproval;

  @override
  Widget build(BuildContext context) => AgentEventCard(
      icon: Icons.priority_high_rounded,
      title: AppLocalizations.of(context).workbenchApprovalCardTitle,
      meta: _approvalMeta(message.event),
      trailing: _eventTime(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message.body,
            style: const TextStyle(
                color: theme.muted, fontSize: 12.5, height: 1.55)),
        const SizedBox(height: 12),
        if (message.event?.approvalId == null)
          Text(AppLocalizations.of(context).workbenchApprovalMissingId,
              style: TextStyle(color: theme.red, fontSize: 12))
        else
          Row(children: [
            Expanded(
                child: ApprovalActionButton(
                    AppLocalizations.of(context).workbenchRejectAction,
                    color: theme.red,
                    onTap: () => onApproval('deny'))),
            const SizedBox(width: 10),
            Expanded(
                child: ApprovalActionButton(
                    AppLocalizations.of(context).workbenchApproveAction,
                    color: theme.text,
                    primary: true,
                    onTap: () => onApproval('allow'))),
          ])
      ]));

  static String _approvalMeta(AgentEvent? event) {
    if (event == null) return 'permission request';
    return '${event.name ?? 'Tool'} · write access';
  }

  static String _eventTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}
