import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../view_models/codex_app_server_view_model.dart';
import '../widgets/codex_app_server_discovery_view.dart';
import '../widgets/codex_app_server_history_view.dart';
import '../widgets/codex_app_server_risk_view.dart';
import '../widgets/codex_app_server_ui.dart';

class CodexAppServerPage extends StatelessWidget {
  const CodexAppServerPage({
    super.key,
    required this.viewModel,
    required this.workspace,
  });

  final CodexAppServerViewModel viewModel;
  final WorkspaceSummary? workspace;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final state = viewModel.state;
        final workspace = this.workspace;
        return DefaultTabController(
          length: 3,
          child: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _CodexAppServerHeader(
                    title: l10n.codexAppServerTitle,
                    workspaceName:
                        workspace?.name ?? l10n.codexAppServerNoWorkspace,
                    workspacePath: workspace?.path,
                    statusLabel: _codexStatusLabel(l10n, state, workspace),
                    healthy: state.error == null && workspace != null,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CodexBoundaryStrip(l10n: l10n),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CodexAppServerTabs(l10n: l10n),
                ),
                if (state.loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _CodexAppServerError(
                      title: l10n.codexAppServerErrorTitle,
                      message: state.error!,
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      CodexAppServerHistoryView(
                        threads: state.threads,
                        workspace: workspace,
                      ),
                      CodexAppServerDiscoveryView(
                        discovery: state.discovery,
                        capabilities: state.capabilities,
                      ),
                      CodexAppServerRiskView(
                        capabilities: state.capabilities,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _codexStatusLabel(
  AppLocalizations l10n,
  CodexAppServerState state,
  WorkspaceSummary? workspace,
) {
  if (state.loading) return l10n.codexAppServerStatusSyncing;
  if (workspace == null) return l10n.codexAppServerStatusUnavailable;
  final error = state.error?.toLowerCase();
  if (error != null) {
    if (error.contains('busy') ||
        error.contains('pool') ||
        error.contains('process limit') ||
        error.contains('maximum codex app-server process limit')) {
      return l10n.codexAppServerStatusBusy;
    }
    return l10n.codexAppServerStatusUnavailable;
  }
  if (state.capabilities != null) return l10n.codexAppServerStatusReady;
  return l10n.codexAppServerStatusUnavailable;
}

class _CodexAppServerHeader extends StatelessWidget {
  const _CodexAppServerHeader({
    required this.title,
    required this.workspaceName,
    required this.workspacePath,
    required this.statusLabel,
    required this.healthy,
  });

  final String title;
  final String workspaceName;
  final String? workspacePath;
  final String statusLabel;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final statusColor = healthy ? codexSuccess : codexWarning;
    return SizedBox(
      height: 68,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _workspaceSubtitle(workspaceName, workspacePath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: theme.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    _StatusDot(color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: codexPanel,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: codexLine),
            ),
            child: const Icon(
              Icons.more_horiz_rounded,
              color: theme.muted,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .40), blurRadius: 9),
        ],
      ),
    );
  }
}

class _CodexBoundaryStrip extends StatelessWidget {
  const _CodexBoundaryStrip({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: codexPanel.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: codexLine),
      ),
      child: Row(
        children: [
          _BoundaryItem(
            icon: Icons.folder_open_rounded,
            label: l10n.codexAppServerWorkspaceScoped,
          ),
          const _BoundaryDivider(),
          _BoundaryItem(
            icon: Icons.visibility_outlined,
            label: l10n.codexAppServerReadOnly,
          ),
          const _BoundaryDivider(),
          _BoundaryItem(
            icon: Icons.shield_outlined,
            label: l10n.codexAppServerGuardedRisk,
          ),
        ],
      ),
    );
  }
}

class _BoundaryItem extends StatelessWidget {
  const _BoundaryItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: theme.faint),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: theme.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundaryDivider extends StatelessWidget {
  const _BoundaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 18, color: codexLine);
  }
}

class _CodexAppServerTabs extends StatelessWidget {
  const _CodexAppServerTabs({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: codexPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: codexLine),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: EdgeInsets.zero,
        labelColor: theme.text,
        unselectedLabelColor: theme.muted,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        indicator: BoxDecoration(
          color: codexPanelRaised,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: codexLineStrong),
        ),
        tabs: [
          Tab(text: l10n.codexAppServerHistoryTab),
          Tab(text: l10n.codexAppServerDiscoveryTab),
          Tab(text: l10n.codexAppServerRiskTab),
        ],
      ),
    );
  }
}

String _workspaceSubtitle(String name, String? path) {
  final trimmedPath = path?.trim();
  if (trimmedPath == null || trimmedPath.isEmpty) return name;
  if (trimmedPath == name) return name;
  return '$name · $trimmedPath';
}

class _CodexAppServerError extends StatelessWidget {
  const _CodexAppServerError({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2B1717),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7F2B2B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
