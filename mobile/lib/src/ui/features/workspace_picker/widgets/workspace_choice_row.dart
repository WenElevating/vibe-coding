import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workspace_display.dart';

class WorkspaceChoiceRow extends StatelessWidget {
  const WorkspaceChoiceRow({
    super.key,
    required this.workspace,
    required this.selected,
    required this.onTap,
    this.allowSelectedTap = false,
  });

  final WorkspaceSummary workspace;
  final bool selected;
  final VoidCallback onTap;
  final bool allowSelectedTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: selected && !allowSelectedTap ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
              color: selected ? theme.activePanel : const Color(0xFF101113),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected
                      ? theme.activeStroke.withValues(alpha: .9)
                      : Colors.white.withValues(alpha: .075))),
          child: Row(children: [
            Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF242B34)
                        : const Color(0xFF18191C),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected
                            ? theme.activeStroke.withValues(alpha: .55)
                            : Colors.white.withValues(alpha: .055))),
                child: Icon(Icons.folder_rounded,
                    color: selected ? theme.active : theme.muted, size: 17)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      workspaceDisplayName(workspace,
                          fallbackName: AppLocalizations.of(context)
                              .workspaceCurrentFallback),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: theme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(workspace.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF858A94),
                          fontSize: 10.8,
                          fontFamily: 'Consolas'))
                ])),
            if (selected)
              Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: theme.active.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.check_rounded,
                      color: theme.active, size: 15))
          ])));
}
