import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class SheetIconButton extends StatelessWidget {
  const SheetIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: const Color(0xFF171E26),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withValues(alpha: .12))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: theme.muted, size: 15),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800)),
          ])));
}
