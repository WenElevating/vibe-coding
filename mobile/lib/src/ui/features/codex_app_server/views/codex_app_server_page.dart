import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/widgets/widgets.dart';
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
          child: Column(
            children: [
              TopBar(
                title: l10n.codexAppServerTitle,
                subtitle: workspace?.name ?? l10n.codexAppServerNoWorkspace,
                statusLabel: _codexStatusLabel(l10n, state, workspace),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _CodexAppServerTabs(l10n: l10n),
              ),
              if (state.loading) const LinearProgressIndicator(minHeight: 2),
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

class _CodexAppServerTabs extends StatelessWidget {
  const _CodexAppServerTabs({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: codexPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: codexLine),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: EdgeInsets.zero,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        indicator: const BoxDecoration(
          color: codexPanelHi,
          borderRadius: BorderRadius.all(Radius.circular(10)),
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
