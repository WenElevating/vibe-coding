import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../features/workspace_picker/workspace_display.dart';
import '../view_models/home_view_model.dart';
import 'home_controls.dart';

class HomeAgentConsolePanel extends StatelessWidget {
  const HomeAgentConsolePanel({
    super.key,
    required this.workspace,
    required this.dashboard,
    required this.daemon,
    required this.l10n,
    required this.onWorkspaceTap,
    required this.onPrimaryTap,
    required this.onTemplatesTap,
  });

  const HomeAgentConsolePanel.empty({
    super.key,
    required this.daemon,
    required this.l10n,
    required this.onWorkspaceTap,
    required this.onPrimaryTap,
    required this.onTemplatesTap,
  })  : workspace = null,
        dashboard = const HomeDashboardState.empty();

  final WorkspaceSummary? workspace;
  final HomeDashboardState dashboard;
  final DaemonHealth daemon;
  final AppLocalizations l10n;
  final VoidCallback onWorkspaceTap;
  final VoidCallback onPrimaryTap;
  final VoidCallback onTemplatesTap;

  @override
  Widget build(BuildContext context) {
    final workspace = this.workspace;
    final accent = dashboard.needsAttention ? theme.amber : theme.green;
    final primaryLabel = dashboard.needsAttention
        ? l10n.homeInterruptsTitle
        : l10n.homeNewTaskTitle;
    final healthLabel = daemon.status.toLowerCase() == 'ok'
        ? l10n.homeDaemonOnline
        : daemon.status;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111820), Color(0xFF080B10)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('vibe-coding',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.0)),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _LiveMark(color: accent),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(healthLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted, fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              HomeRoundIconButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: onWorkspaceTap),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ConsoleMetric(
                  label: l10n.homeInterruptsTitle,
                  value: '${dashboard.attentionCount}',
                  color: dashboard.needsAttention ? theme.amber : theme.muted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ConsoleMetric(
                  label: l10n.homeRunningMetricLabel,
                  value: '${dashboard.runningCount}',
                  color: theme.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ConsoleMetric(
                  label: l10n.homeQueueLabel,
                  value: '${dashboard.queueCount}',
                  color: theme.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (workspace != null)
            InkWell(
              onTap: onWorkspaceTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 11, 11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .035),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .055)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded,
                        color: theme.faint, size: 17),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(workspaceDisplayName(workspace),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1)),
                          const SizedBox(height: 4),
                          Text(compactWorkspacePath(workspace.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: theme.faint, size: 20),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: HomeCommandButton(
                  icon: dashboard.needsAttention
                      ? Icons.priority_high_rounded
                      : Icons.add_rounded,
                  label: primaryLabel,
                  color: accent,
                  primary: true,
                  onTap: onPrimaryTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HomeCommandButton(
                  icon: Icons.terminal_rounded,
                  label: l10n.homeCommandTemplatesTitle,
                  color: theme.purple,
                  onTap: onTemplatesTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConsoleMetric extends StatelessWidget {
  const _ConsoleMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: .045)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: theme.muted, fontSize: 10.5)),
          ],
        ),
      );
}

class _LiveMark extends StatelessWidget {
  const _LiveMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .38), blurRadius: 10),
          ],
        ),
      );
}
