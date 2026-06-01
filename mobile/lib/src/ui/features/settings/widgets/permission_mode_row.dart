import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;

class PermissionModeRow extends StatelessWidget {
  const PermissionModeRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.l10n,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(l10n.settingsPermissionModeTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14))),
          PermissionChip(
              label: l10n.settingsPermissionDefault,
              selected: value == 'default',
              onTap: () => onChanged('default')),
          const SizedBox(width: 8),
          PermissionChip(
              label: l10n.settingsPermissionAuto,
              selected: value == 'auto',
              onTap: () => onChanged('auto')),
        ]),
        const SizedBox(height: 8),
        Text(l10n.settingsPermissionSubtitle,
            style: const TextStyle(
                color: Color(0xFF858A94), fontSize: 11.5, height: 1.35)),
      ]));
}

class PermissionChip extends StatelessWidget {
  const PermissionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? theme.activePanel
                  : Colors.white.withValues(alpha: .04),
              border: Border.all(
                  color: selected
                      ? theme.activeStroke.withValues(alpha: .9)
                      : theme.stroke)),
          child: Text(label,
              style: TextStyle(
                  color: selected ? theme.active : theme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900))));
}
