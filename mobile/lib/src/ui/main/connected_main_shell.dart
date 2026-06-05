import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_dependencies.dart';
import '../../app/connected_session_scope.dart';
import '../../domain/models/daemon_initial_data.dart';
import '../../models/protocol.dart';
import '../../shell/app_route.dart';
import '../core/widgets/widgets.dart';
import '../features/codex_app_server/codex_app_server.dart';
import '../features/settings/settings.dart'
    show AppUpdateViewModel, SettingsViewModel;
import '../main_route_overlay.dart';
import '../main_tab_items.dart';
import '../mobile_ui_frame.dart';
import '../pages/pages.dart';
import 'main_shell_view_model.dart';
import 'widgets/main_error_banner.dart';
import 'widgets/main_loading_overlay.dart';

class ConnectedMainShell extends StatelessWidget {
  const ConnectedMainShell({
    super.key,
    required this.viewModel,
    required this.initialData,
    required this.homeViewModel,
    required this.settingsViewModel,
    required this.codexAppServerViewModel,
    required this.appUpdateViewModel,
    required this.connectedData,
    required this.repositories,
    required this.featureDependencies,
    required this.codingTab,
    required this.creatingWorkspace,
    required this.loadingWorkspace,
    required this.workspaceActionError,
    required this.onCreateWorkspace,
    required this.onOpenWorkspace,
    required this.onSystemBack,
  });

  final MainShellViewModel viewModel;
  final DaemonInitialData initialData;
  final HomeViewModel homeViewModel;
  final SettingsViewModel settingsViewModel;
  final CodexAppServerViewModel codexAppServerViewModel;
  final AppUpdateViewModel? appUpdateViewModel;
  final ConnectedDataDependencies connectedData;
  final ConnectedSessionRepositories repositories;
  final FeatureDependencies featureDependencies;
  final Widget codingTab;
  final bool creatingWorkspace;
  final bool loadingWorkspace;
  final Object? workspaceActionError;
  final VoidCallback onCreateWorkspace;
  final ValueChanged<WorkspaceSummary> onOpenWorkspace;
  final VoidCallback onSystemBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = [
      HomePage(
        open: viewModel.openOverlay,
        selectTab: viewModel.selectTab,
        viewModel: homeViewModel,
        health: initialData.health,
        onCreateWorkspace: onCreateWorkspace,
        onOpenWorkspace: onOpenWorkspace,
      ),
      codingTab,
      CodexAppServerPage(
        viewModel: codexAppServerViewModel,
        workspace: initialData.workspace,
      ),
      SettingsPage(
        open: viewModel.openOverlay,
        viewModel: settingsViewModel,
        streamOutput: viewModel.streamOutput,
        expandThinking: viewModel.expandThinking,
        appUpdateViewModel: appUpdateViewModel,
        onStreamOutputChanged: viewModel.setStreamOutput,
        onExpandThinkingChanged: viewModel.setExpandThinking,
      ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onSystemBack();
      },
      child: Scaffold(
        body: MobileUiFrame(
          child: Stack(
            children: [
              viewModel.activeRoute == RoutePage.tabs
                  ? IndexedStack(index: viewModel.activeTab, children: pages)
                  : MainRouteOverlay(
                      route: viewModel.activeRoute,
                      connectedData: connectedData,
                      repositories: repositories,
                      featureDependencies: featureDependencies,
                      onBack: viewModel.closeOverlay,
                    ),
              if (creatingWorkspace || loadingWorkspace)
                const MainLoadingOverlay(label: 'Loading workspace...'),
              if (workspaceActionError != null)
                MainErrorBanner(error: workspaceActionError!),
            ],
          ),
        ),
        bottomNavigationBar: viewModel.activeRoute == RoutePage.tabs &&
                (viewModel.activeTab != 1 || viewModel.codingSessionListOpen)
            ? BottomNav(
                selected: viewModel.activeTab,
                items: mainTabItems(l10n),
                onTap: viewModel.selectTab,
              )
            : null,
        extendBody: true,
      ),
    );
  }
}
