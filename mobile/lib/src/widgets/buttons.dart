import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;

class FloatingPlus extends StatelessWidget {
  const FloatingPlus({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient:
                  const LinearGradient(colors: [theme.purple, theme.purple2]),
              boxShadow: [
                BoxShadow(
                    color: theme.purple.withValues(alpha: .42), blurRadius: 24)
              ]),
          child: const Icon(Icons.add_rounded, size: 34, color: Colors.white),
        ));
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.text, {super.key, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [theme.purple, theme.purple2]),
              borderRadius: BorderRadius.circular(8)),
          child:
              Text(text, style: const TextStyle(fontWeight: FontWeight.w900))));
}

class GhostButton extends StatelessWidget {
  const GhostButton(this.text,
      {super.key, required this.color, required this.onTap});
  final String text;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: theme.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: .35))),
          child: Text(text,
              style: TextStyle(color: color, fontWeight: FontWeight.w900))));
}
