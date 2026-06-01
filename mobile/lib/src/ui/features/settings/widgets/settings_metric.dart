import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';

class SettingsMetric extends StatelessWidget {
  const SettingsMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF0B0C0E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .055))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                const TextStyle(color: theme.faint, fontSize: 10.5, height: 1)),
        const SizedBox(height: 7),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
      ]));
}

class SettingsPill extends StatelessWidget {
  const SettingsPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: theme.active.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.active.withValues(alpha: .16))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Dot(color: theme.green, size: 5),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                color: theme.active,
                fontSize: 11,
                fontWeight: FontWeight.w900)),
      ]));
}
