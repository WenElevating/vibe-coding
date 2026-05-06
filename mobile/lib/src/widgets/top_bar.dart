import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;

class TopBar extends StatelessWidget {
  const TopBar(
      {super.key,
      required this.title,
      this.subtitle,
      this.showScan = false,
      this.leading = false,
      this.action});
  final String title;
  final String? subtitle;
  final bool showScan;
  final bool leading;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (leading) ...[
              const Icon(Icons.chevron_left_rounded,
                  color: theme.text, size: 26),
              const SizedBox(width: 8)
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(subtitle!.replaceAll('online', ''),
                          style: const TextStyle(
                              color: theme.muted,
                              fontSize: 12,
                              letterSpacing: .5)),
                      const Text('online',
                          style: TextStyle(
                              color: theme.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const Dot(color: theme.green, size: 5),
                    ]),
                  ],
                ],
              ),
            ),
            if (action != null)
              Text(action!,
                  style: const TextStyle(
                      color: theme.purple, fontWeight: FontWeight.w700)),
            if (showScan)
              const Icon(Icons.center_focus_weak_rounded,
                  color: theme.muted, size: 24),
            if (!showScan && action == null)
              const Icon(Icons.more_horiz_rounded,
                  color: theme.muted, size: 26),
          ],
        ),
      ],
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: theme.stroke);
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 6});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .45), blurRadius: 8)
          ]));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const Spacer(),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(action!,
              style: const TextStyle(
                  color: theme.purple,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        )
    ]);
  }
}

class Subhead extends StatelessWidget {
  const Subhead(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style:
              const TextStyle(fontWeight: FontWeight.w800, color: theme.text)));
}
