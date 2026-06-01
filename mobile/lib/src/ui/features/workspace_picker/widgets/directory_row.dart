import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class DirectoryRow extends StatelessWidget {
  const DirectoryRow({
    super.key,
    required this.name,
    required this.path,
    required this.onTap,
    this.icon = Icons.folder_rounded,
    this.emphasized = false,
  });

  final String name;
  final String path;
  final VoidCallback onTap;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: emphasized
                        ? theme.activePanel.withValues(alpha: .72)
                        : const Color(0xFF151A20),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: emphasized
                            ? theme.activeStroke.withValues(alpha: .44)
                            : Colors.white.withValues(alpha: .045))),
                child: Icon(icon,
                    color: emphasized ? theme.active : theme.muted, size: 16)),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: emphasized ? theme.active : theme.text,
                          fontSize: 12.8,
                          fontWeight:
                              emphasized ? FontWeight.w900 : FontWeight.w800,
                          letterSpacing: 0)),
                  const SizedBox(height: 3),
                  Text(path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: theme.faint,
                          fontSize: 10.8,
                          fontFamily: 'Consolas',
                          height: 1.15)),
                ])),
            const Icon(Icons.chevron_right_rounded,
                color: theme.faint, size: 18)
          ])));
}
