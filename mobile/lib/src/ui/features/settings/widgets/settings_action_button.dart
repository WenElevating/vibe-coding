import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton(
    this.text, {
    super.key,
    required this.icon,
    required this.onTap,
    this.fullWidth = false,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
          height: 46,
          width: fullWidth ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: const Color(0xFF101113),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: .075))),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: theme.active, size: 16),
                const SizedBox(width: 8),
                Text(text,
                    style: const TextStyle(
                        color: theme.active,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ])));
}
