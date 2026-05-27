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
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: isEnabled
                    ? const LinearGradient(
                        colors: [theme.purple, theme.purple2])
                    : null,
                color:
                    isEnabled ? null : Colors.white.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(8),
                border: isEnabled ? null : Border.all(color: theme.stroke)),
            child: Text(text,
                style: TextStyle(
                    color: isEnabled ? theme.text : theme.muted,
                    fontWeight: FontWeight.w900))));
  }
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

class TinyActionButton extends StatelessWidget {
  const TinyActionButton(this.label,
      {super.key, required this.onTap, this.primary = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: primary
                  ? theme.purple.withValues(alpha: .24)
                  : Colors.white.withValues(alpha: .04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: primary
                      ? theme.purple.withValues(alpha: .42)
                      : theme.stroke)),
          child: Text(label,
              style: TextStyle(
                  color: primary ? theme.text : theme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900))));
}
