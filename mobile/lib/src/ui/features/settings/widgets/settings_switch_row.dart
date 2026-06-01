import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  color: Color(0xFF858A94), fontSize: 11.5, height: 1.35))
        ])),
        Switch(
            value: value,
            activeThumbColor: theme.active,
            activeTrackColor: theme.activeStroke.withValues(alpha: .55),
            inactiveThumbColor: theme.faint,
            inactiveTrackColor: theme.panelHi,
            onChanged: onChanged),
      ]),
    );
  }
}
