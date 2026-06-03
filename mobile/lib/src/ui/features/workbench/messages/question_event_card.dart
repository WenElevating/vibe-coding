import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';

class QuestionEventCard extends StatelessWidget {
  const QuestionEventCard(
      {super.key, required this.message, required this.onSuggestion});
  final WorkbenchMessage message;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF0F1012),
          border: Border.all(color: Colors.white.withValues(alpha: .07))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _QuestionKindBadge(),
          const SizedBox(width: 10),
          Expanded(
              child: Text(AppLocalizations.of(context).workbenchQuestionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: theme.text,
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0))),
        ]),
        const SizedBox(height: 10),
        Text(message.body,
            style: const TextStyle(
                color: theme.muted,
                fontSize: 12.8,
                height: 1.48,
                letterSpacing: 0)),
        if (message.suggestions.isNotEmpty) ...[
          const SizedBox(height: 11),
          Wrap(
              spacing: 7,
              runSpacing: 7,
              children: message.suggestions
                  .map((item) => _QuestionSuggestionChip(
                      text: item, onTap: () => onSuggestion(item)))
                  .toList(growable: false)),
        ]
      ]));
}

class _QuestionKindBadge extends StatelessWidget {
  const _QuestionKindBadge();

  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minWidth: 38),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: theme.purple2.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: theme.purple2.withValues(alpha: .18))),
      child: const Text('ASK',
          style: TextStyle(
              color: theme.purple2,
              fontSize: 9.5,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w900,
              letterSpacing: 0)));
}

class _QuestionSuggestionChip extends StatelessWidget {
  const _QuestionSuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withValues(alpha: .038),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .105))),
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: theme.text,
                          fontSize: 12,
                          height: 1.18,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w800))))));
}
