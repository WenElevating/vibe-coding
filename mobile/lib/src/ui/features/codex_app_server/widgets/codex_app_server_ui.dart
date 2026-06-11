import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

const codexPanel = Color(0xFF101113);
const codexPanelHi = Color(0xFF15171A);
const codexPanelRaised = Color(0xFF181A1D);
const codexLine = Color(0x1FFFFFFF);
const codexLineStrong = Color(0x33FFFFFF);
const codexAccent = Color(0xFF98B8FF);
const codexSuccess = Color(0xFF6EE7B7);
const codexWarning = Color(0xFFF1C76E);

class CodexSurface extends StatelessWidget {
  const CodexSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: codexPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: codexLine),
      ),
      child: child,
    );
  }
}

class CodexSectionHeader extends StatelessWidget {
  const CodexSectionHeader({
    super.key,
    required this.label,
    this.trailing,
  });

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: theme.faint,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                color: theme.faint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class CodexStatusPill extends StatelessWidget {
  const CodexStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .08)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class CodexEmptyState extends StatelessWidget {
  const CodexEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 24, 34, 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: codexPanelHi,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: codexLine),
              ),
              child: Icon(icon, color: theme.muted, size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: theme.muted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
