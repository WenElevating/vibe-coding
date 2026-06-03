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

class ApprovalComposerPrompt extends StatelessWidget {
  const ApprovalComposerPrompt(
      {super.key, required this.message, required this.onApproval});

  final WorkbenchMessage message;
  final ValueChanged<String> onApproval;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final event = message.event;
    final approvalId = event?.approvalId?.trim();
    final hasApprovalId = approvalId != null && approvalId.isNotEmpty;
    return Container(
        key: const ValueKey('workbench-approval-composer'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
            color: const Color(0xF608090B),
            border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: .06))),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .28),
                  blurRadius: 24,
                  offset: const Offset(0, -10))
            ]),
        child: SafeArea(
            top: false,
            child: Container(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
                decoration: BoxDecoration(
                    color: const Color(0xFF161719),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .085))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: theme.amber.withValues(alpha: .11),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                                color: theme.amber.withValues(alpha: .22))),
                        child: const Icon(Icons.priority_high_rounded,
                            color: theme.amber, size: 15)),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Text(l10n.workbenchApprovalCardTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0))),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 132),
                        child: Text(ApprovalEventCard._approvalMeta(event),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.faint,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0))),
                  ]),
                  const SizedBox(height: 8),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(message.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: theme.muted,
                              fontSize: 12.5,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0))),
                  const SizedBox(height: 11),
                  if (!hasApprovalId)
                    Row(children: [
                      const Icon(Icons.error_outline_rounded,
                          color: theme.red, size: 15),
                      const SizedBox(width: 7),
                      Expanded(
                          child: Text(l10n.workbenchApprovalMissingId,
                              style: const TextStyle(
                                  color: theme.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0)))
                    ])
                  else
                    Row(children: [
                      Expanded(
                          child: _ApprovalComposerActionButton(
                              key: const ValueKey(
                                  'workbench-approval-deny-button'),
                              l10n.workbenchRejectAction,
                              color: theme.red,
                              onTap: () => onApproval('deny'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _ApprovalComposerActionButton(
                              key: const ValueKey(
                                  'workbench-approval-approve-button'),
                              l10n.workbenchApproveAction,
                              color: theme.text,
                              primary: true,
                              onTap: () => onApproval('allow'))),
                    ])
                ]))));
  }
}

class _ApprovalComposerActionButton extends StatelessWidget {
  const _ApprovalComposerActionButton(this.text,
      {super.key,
      required this.color,
      required this.onTap,
      this.primary = false});

  final String text;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final textColor = primary ? const Color(0xFF08090B) : color;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: primary
                    ? const LinearGradient(
                        colors: [Color(0xFFF2F3F5), Color(0xFFD9DDE2)])
                    : null,
                color: primary ? null : color.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: primary
                        ? Colors.white.withValues(alpha: .18)
                        : color.withValues(alpha: .30))),
            child: Text(text,
                style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0))));
  }
}
