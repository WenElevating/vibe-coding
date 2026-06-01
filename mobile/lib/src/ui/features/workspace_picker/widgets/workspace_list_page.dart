import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import 'workspace_choice_row.dart';

class WorkspaceListPage extends StatelessWidget {
  const WorkspaceListPage({
    super.key,
    required this.workspaces,
    required this.onSelected,
    required this.onAddWorkspace,
  });

  final List<WorkspaceSummary> workspaces;
  final ValueChanged<WorkspaceSummary> onSelected;
  final VoidCallback onAddWorkspace;

  @override
  Widget build(BuildContext context) {
    final visibleWorkspaces = dedupeWorkspacesByPath(workspaces);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(key: const ValueKey('workspace-list'), children: [
      Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: const Color(0xEE0A0B0D),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: .07)))),
          child: Row(children: [
            const SizedBox(width: 36),
            Expanded(
                child: Text(AppLocalizations.of(context).workspaceListTitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: theme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0))),
            _WorkspaceAddIconButton(onTap: onAddWorkspace),
          ])),
      Expanded(
          child: ListView(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 96 + bottomInset),
              children: [
            const SessionSearchBox(),
            const SizedBox(height: 14),
            _WorkspaceSectionHeader(
                title: AppLocalizations.of(context).workspaceAvailableSection,
                meta: '${visibleWorkspaces.length}'),
            const SizedBox(height: 8),
            for (final workspace in visibleWorkspaces)
              WorkspaceChoiceRow(
                  workspace: workspace,
                  selected: false,
                  allowSelectedTap: true,
                  onTap: () => onSelected(workspace)),
            Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(AppLocalizations.of(context).workspaceListFootnote,
                    style: const TextStyle(
                        color: Color(0xFF666D77),
                        fontSize: 11.5,
                        height: 1.5))),
          ])),
    ]);
  }
}

class _WorkspaceSectionHeader extends StatelessWidget {
  const _WorkspaceSectionHeader({required this.title, required this.meta});

  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(title,
            style: const TextStyle(
                color: Color(0xFFD8D8D8),
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        Text(meta,
            style: const TextStyle(
                color: Color(0xFF6F757E),
                fontSize: 10.5,
                fontFamily: 'Consolas')),
      ]);
}

class _WorkspaceAddIconButton extends StatelessWidget {
  const _WorkspaceAddIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
      message: AppLocalizations.of(context).workspaceAddTitle,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: theme.purple.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: theme.purple.withValues(alpha: .42))),
              child:
                  const Icon(Icons.add_rounded, color: theme.text, size: 24))));
}
