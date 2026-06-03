import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';

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
      borderRadius: BorderRadius.circular(14),
      child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: primary
                  ? const LinearGradient(
                      colors: [Color(0xFFF1F3F5), Color(0xFFE0E3E7)])
                  : null,
              color: primary ? null : color.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: primary
                      ? Colors.white.withValues(alpha: .18)
                      : color.withValues(alpha: .42))),
          child: Text(text,
              style: TextStyle(
                  color: primary ? const Color(0xFF08090B) : color,
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final approvalId = message.event?.approvalId?.trim();
    final hasApprovalId = approvalId != null && approvalId.isNotEmpty;
    return Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
        decoration: BoxDecoration(
            color: const Color(0xFF101113),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .075))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ApprovalTitleRow(
              title: l10n.workbenchApprovalCardTitle,
              meta: _approvalMeta(message.event),
              dense: false),
          const SizedBox(height: 10),
          Text(message.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: theme.muted,
                  fontSize: 12.5,
                  height: 1.48,
                  letterSpacing: 0)),
          const SizedBox(height: 12),
          if (!hasApprovalId)
            _ApprovalMissingId(l10n.workbenchApprovalMissingId)
          else
            Row(children: [
              Expanded(
                  child: ApprovalActionButton(l10n.workbenchRejectAction,
                      color: theme.red, onTap: () => onApproval('deny'))),
              const SizedBox(width: 10),
              Expanded(
                  child: ApprovalActionButton(l10n.workbenchApproveAction,
                      color: theme.text,
                      primary: true,
                      onTap: () => onApproval('allow'))),
            ])
        ]));
  }

  static String _approvalMeta(AgentEvent? event) {
    if (event == null) return 'permission request';
    return '${event.name ?? 'Tool'} · write access';
  }
}

class ApprovalComposerPrompt extends StatefulWidget {
  const ApprovalComposerPrompt(
      {super.key, required this.message, required this.onApproval});

  final WorkbenchMessage message;
  final ValueChanged<String> onApproval;

  @override
  State<ApprovalComposerPrompt> createState() => _ApprovalComposerPromptState();
}

enum _ApprovalChoice { allow, deny }

class _ApprovalComposerPromptState extends State<ApprovalComposerPrompt> {
  _ApprovalChoice _selected = _ApprovalChoice.allow;

  String get _selectedDecision =>
      _selected == _ApprovalChoice.allow ? 'allow' : 'deny';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final event = widget.message.event;
    final approvalId = event?.approvalId?.trim();
    final hasApprovalId = approvalId != null && approvalId.isNotEmpty;
    return Container(
        key: const ValueKey('workbench-approval-composer'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
                key: const ValueKey('workbench-approval-choice-panel'),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: BoxDecoration(
                    color: const Color(0xFF28292B),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .095)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .30),
                          blurRadius: 22,
                          offset: const Offset(0, 10)),
                    ]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.workbenchApprovalPromptQuestion,
                          key: const ValueKey('workbench-approval-question'),
                          style: const TextStyle(
                              color: theme.text,
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0))),
                  const SizedBox(height: 11),
                  _ApprovalCommandPreview(
                      text: _approvalPreviewText(widget.message)),
                  const SizedBox(height: 10),
                  if (!hasApprovalId)
                    _ApprovalMissingId(l10n.workbenchApprovalMissingId)
                  else
                    Column(children: [
                      _ApprovalOptionRow(
                          key:
                              const ValueKey('workbench-approval-option-allow'),
                          index: 1,
                          text: l10n.workbenchApprovalPromptAllowOption,
                          selected: _selected == _ApprovalChoice.allow,
                          onTap: () => setState(
                              () => _selected = _ApprovalChoice.allow)),
                      const SizedBox(height: 3),
                      _ApprovalOptionRow(
                          key: const ValueKey('workbench-approval-option-deny'),
                          index: 2,
                          text: l10n.workbenchApprovalPromptDenyOption,
                          selected: _selected == _ApprovalChoice.deny,
                          onTap: () =>
                              setState(() => _selected = _ApprovalChoice.deny)),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Spacer(),
                        KeyedSubtree(
                            key: const ValueKey(
                                'workbench-approval-deny-button'),
                            child: TextButton(
                                onPressed: () => widget.onApproval('deny'),
                                style: TextButton.styleFrom(
                                    foregroundColor: theme.muted,
                                    textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0)),
                                child: Text(l10n.workbenchApprovalPromptSkip))),
                        const SizedBox(width: 8),
                        KeyedSubtree(
                            key: const ValueKey(
                                'workbench-approval-approve-button'),
                            child: _ApprovalSubmitButton(
                                key: const ValueKey(
                                    'workbench-approval-submit-button'),
                                text: l10n.workbenchApprovalPromptSubmit,
                                onTap: () =>
                                    widget.onApproval(_selectedDecision))),
                      ])
                    ])
                ]))));
  }
}

class _ApprovalCommandPreview extends StatelessWidget {
  const _ApprovalCommandPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
      key: const ValueKey('workbench-approval-command-preview'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: .035))),
      child: Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: theme.muted,
              fontSize: 11.5,
              height: 1.34,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w500,
              letterSpacing: 0)));
}

class _ApprovalOptionRow extends StatelessWidget {
  const _ApprovalOptionRow({
    super.key,
    required this.index,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: .075)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                SizedBox(
                    width: 22,
                    child: Text('$index.',
                        style: TextStyle(
                            color: selected ? theme.text : theme.faint,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0))),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: selected ? theme.text : theme.muted,
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            letterSpacing: 0))),
                if (selected)
                  const Icon(Icons.keyboard_return_rounded,
                      color: theme.faint, size: 15),
              ]))));
}

class _ApprovalSubmitButton extends StatelessWidget {
  const _ApprovalSubmitButton({
    super.key,
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xFFE8EAED),
              borderRadius: BorderRadius.circular(999)),
          child: Text(text,
              style: const TextStyle(
                  color: Color(0xFF111214),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0))));
}

String _approvalPreviewText(WorkbenchMessage message) {
  final input = message.event?.raw['input'];
  if (input is Map) {
    for (final key in const <String>[
      'command',
      'cmd',
      'file_path',
      'path',
      'pattern',
      'query',
    ]) {
      final value = input[key];
      if (value is String && value.trim().isNotEmpty) {
        return _prefixToolName(message.event, value.trim());
      }
    }
  }
  final body = message.body.trim();
  if (body.isNotEmpty) return _prefixToolName(message.event, body);
  return ApprovalEventCard._approvalMeta(message.event);
}

String _prefixToolName(AgentEvent? event, String text) {
  final tool = event?.name ?? event?.raw['toolName'];
  if (tool is! String || tool.trim().isEmpty) return text;
  final label = tool.trim();
  if (text.toLowerCase().startsWith(label.toLowerCase())) return text;
  return '$label $text';
}

class _ApprovalTitleRow extends StatelessWidget {
  const _ApprovalTitleRow({
    required this.title,
    required this.meta,
    required this.dense,
  });

  final String title;
  final String meta;
  final bool dense;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
              width: dense ? 24 : 22,
              height: dense ? 24 : 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: theme.amber.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(7),
                  border:
                      Border.all(color: theme.amber.withValues(alpha: .24))),
              child: const Icon(Icons.priority_high_rounded,
                  color: theme.amber, size: 15)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: theme.text,
                      fontSize: dense ? 14.5 : 13.2,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: 0))),
          const SizedBox(width: 10),
          Flexible(
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: theme.faint,
                          fontSize: dense ? 11.5 : 10.8,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          letterSpacing: 0)))),
        ],
      );
}

class _ApprovalMissingId extends StatelessWidget {
  const _ApprovalMissingId(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.error_outline_rounded, color: theme.red, size: 15),
        const SizedBox(width: 7),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: theme.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0)))
      ]);
}
