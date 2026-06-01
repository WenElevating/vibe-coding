import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../models/protocol.dart';
import '../../../shell/app_route.dart';
import '../../core/widgets/widgets.dart';
import 'view_models/home_view_model.dart';
import 'widgets/home_agent_console_panel.dart';
import 'widgets/home_execution_stream.dart';
import 'widgets/home_interrupt_lane.dart';
import 'widgets/home_no_workspace_panel.dart';
import 'widgets/home_quick_actions.dart';
import 'widgets/home_workspace_signals.dart';

class HomePage extends StatelessWidget {
  const HomePage(
      {super.key,
      required this.open,
      required this.selectTab,
      required this.viewModel,
      required this.health,
      required this.onCreateWorkspace,
      required this.onOpenWorkspace});

  final ValueChanged<RoutePage> open;
  final ValueChanged<int> selectTab;
  final HomeViewModel viewModel;
  final DaemonHealth health;
  final VoidCallback onCreateWorkspace;
  final ValueChanged<WorkspaceSummary> onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final deck = viewModel.deck;
        final dashboard =
            viewModel.dashboard ?? const HomeDashboardState.empty();
        if (deck == null) {
          return PageScroll(children: [
            HomeAgentConsolePanel.empty(
              daemon: health,
              l10n: l10n,
              onWorkspaceTap: () => selectTab(1),
              onPrimaryTap: () => selectTab(1),
              onTemplatesTap: () => selectTab(1),
            ),
            const SizedBox(height: 18),
            HomeNoWorkspacePanel(
              workspaces: viewModel.workspaces,
              loading: viewModel.loading,
              error: viewModel.error,
              onCreateWorkspace: onCreateWorkspace,
              onOpenWorkspace: onOpenWorkspace,
            ),
          ]);
        }

        return PageScroll(
          children: [
            HomeAgentConsolePanel(
              workspace: viewModel.currentWorkspace!,
              dashboard: dashboard,
              daemon: health,
              l10n: l10n,
              onWorkspaceTap: () => selectTab(1),
              onPrimaryTap: dashboard.needsAttention
                  ? () => open(RoutePage.approval)
                  : () => selectTab(1),
              onTemplatesTap: () => selectTab(1),
            ),
            if (dashboard.attentionItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              HomeInterruptLane(items: dashboard.attentionItems, l10n: l10n),
            ],
            const SizedBox(height: 18),
            HomeExecutionStream(
                items: dashboard.activityItems,
                l10n: l10n,
                onTap: () => open(RoutePage.detail)),
            const SizedBox(height: 18),
            HomeWorkspaceSignals(data: deck.signals, l10n: l10n),
            const SizedBox(height: 18),
            HomeQuickActions(selectTab: selectTab, l10n: l10n),
          ],
        );
      },
    );
  }
}
