import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import '../../../features/workspace_picker/workspace_display.dart';
import 'home_controls.dart';
import 'home_surface.dart';

class HomeNoWorkspacePanel extends StatelessWidget {
  const HomeNoWorkspacePanel({
    super.key,
    required this.workspaces,
    required this.loading,
    required this.error,
    required this.onCreateWorkspace,
    required this.onOpenWorkspace,
  });

  final List<WorkspaceSummary> workspaces;
  final bool loading;
  final Object? error;
  final VoidCallback onCreateWorkspace;
  final ValueChanged<WorkspaceSummary> onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visibleWorkspaces = dedupeWorkspacesByPath(workspaces).take(4);
    return HomeSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open_rounded,
                    color: theme.active, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    l10n.workspaceListTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: theme.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.workspaceListFootnote,
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.4),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                '$error',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: theme.red, fontSize: 11.5),
              ),
            ],
            const SizedBox(height: 12),
            for (final workspace in visibleWorkspaces)
              _HomeWorkspaceRow(
                workspace: workspace,
                onTap: () => onOpenWorkspace(workspace),
              ),
            const SizedBox(height: 10),
            HomeCommandButton(
              icon: Icons.add_rounded,
              label: l10n.workspaceAddTitle,
              color: theme.purple,
              primary: workspaces.isEmpty,
              onTap: onCreateWorkspace,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeWorkspaceRow extends StatelessWidget {
  const _HomeWorkspaceRow({required this.workspace, required this.onTap});

  final WorkspaceSummary workspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(11, 10, 9, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_rounded, color: theme.faint, size: 17),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspaceDisplayName(workspace),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: theme.text,
                        fontSize: 12.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      compactWorkspacePath(workspace.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: theme.muted,
                        fontSize: 10.8,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: theme.faint, size: 19),
            ],
          ),
        ),
      );
}
