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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF101113),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: theme.purple.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: theme.purple.withValues(alpha: .26))),
              child: const Icon(Icons.tune_rounded,
                  color: theme.purple2, size: 15)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(AppLocalizations.of(context).workbenchQuestionTitle,
                  style: TextStyle(
                      color: theme.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        Text(message.body,
            style: const TextStyle(
                color: theme.muted, fontSize: 13.5, height: 1.55)),
        if (message.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.suggestions
                  .map((item) => _QuestionSuggestionChip(
                      text: item, onTap: () => onSuggestion(item)))
                  .toList(growable: false)),
        ]
      ]));
}

class _QuestionSuggestionChip extends StatelessWidget {
  const _QuestionSuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: .045),
              border: Border.all(color: Colors.white.withValues(alpha: .10))),
          child: Text(text,
              style: const TextStyle(
                  color: Color(0xFFDCE2EE),
                  fontSize: 12,
                  fontWeight: FontWeight.w700))));
}
