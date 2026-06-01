import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class AgentEventCard extends StatelessWidget {
  const AgentEventCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.meta,
      required this.child,
      this.trailing,
      this.accentColor});
  final IconData icon;
  final String title;
  final String meta;
  final Widget child;
  final String? trailing;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? theme.amber;
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF101113),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: accentColor == null
                    ? Colors.white.withValues(alpha: .075)
                    : accent.withValues(alpha: .18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: accentColor == null
                        ? const Color(0xFF191A1D)
                        : accent.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: accent, size: 15)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: theme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: theme.faint,
                          fontSize: 10.5,
                          fontFamily: 'Consolas')),
                ])),
            if (trailing != null)
              Text(trailing!,
                  style: const TextStyle(
                      color: theme.faint,
                      fontSize: 10.5,
                      fontFamily: 'Consolas'))
          ]),
          const SizedBox(height: 12),
          child,
        ]));
  }
}

class EventCodeLine extends StatelessWidget {
  const EventCodeLine({super.key, required this.text, required this.ok});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF0B0C0E),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: .055))),
      child: Row(children: [
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    height: 1.35))),
        if (ok) ...[
          const SizedBox(width: 8),
          const Text('ok',
              style: TextStyle(
                  color: theme.green,
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w800))
        ]
      ]));
}
