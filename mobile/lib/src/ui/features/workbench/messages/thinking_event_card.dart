import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';

class ThinkingEventCard extends StatelessWidget {
  const ThinkingEventCard(
      {super.key, required this.message, required this.expanded});
  final WorkbenchMessage message;
  final bool expanded;

  @override
  Widget build(BuildContext context) =>
      _ThinkingFoldout(message: message, initiallyExpanded: expanded);
}

class _ThinkingFoldout extends StatefulWidget {
  const _ThinkingFoldout(
      {required this.message, required this.initiallyExpanded});
  final WorkbenchMessage message;
  final bool initiallyExpanded;

  @override
  State<_ThinkingFoldout> createState() => _ThinkingFoldoutState();
}

class _ThinkingFoldoutState extends State<_ThinkingFoldout> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ThinkingFoldout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.title != widget.message.title ||
        oldWidget.message.body != widget.message.body) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              AppLocalizations.of(context)
                                  .workbenchThinkingProcessTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted,
                                  fontSize: 12.4,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0))),
                      Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: theme.faint,
                          size: 16),
                    ]))),
            if (_expanded)
              Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .025),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .045))),
                      child: Text(widget.message.body,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                              color: theme.muted,
                              fontSize: 12.5,
                              height: 1.55)))),
          ]);
}
