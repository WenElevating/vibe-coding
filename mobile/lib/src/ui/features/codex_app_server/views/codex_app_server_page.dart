import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../../../core/widgets/widgets.dart';
import '../view_models/codex_app_server_view_model.dart';
import '../widgets/codex_app_server_discovery_view.dart';
import '../widgets/codex_app_server_history_view.dart';
import '../widgets/codex_app_server_risk_view.dart';

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
        final state = viewModel.state;
        final workspace = this.workspace;
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              TopBar(
                title: 'Codex app-server',
                subtitle: workspace?.name ?? 'No workspace selected',
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _CodexAppServerTabs(),
              ),
              if (state.loading) const LinearProgressIndicator(minHeight: 2),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _CodexAppServerError(message: state.error!),
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

class _CodexAppServerTabs extends StatelessWidget {
  const _CodexAppServerTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: const TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: [
          Tab(text: 'History'),
          Tab(text: 'Discovery'),
          Tab(text: 'Risk Controls'),
        ],
      ),
    );
  }
}

class _CodexAppServerError extends StatelessWidget {
  const _CodexAppServerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1616),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF7F2B2B)),
      ),
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
