import 'package:flutter/material.dart';

import '../../../../domain/models/daemon_connection_config.dart';
import '../../../core/theme/theme.dart' as theme;

class ProxyModeRow extends StatelessWidget {
  const ProxyModeRow({
    super.key,
    required this.mode,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DaemonProxyMode mode;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF151A20) : const Color(0xFF0D0F12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF586574)
                  : Colors.white.withValues(alpha: .065),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: selected ? theme.green : theme.faint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? theme.text : theme.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: theme.active, size: 17),
            ],
          ),
        ),
      );
}
