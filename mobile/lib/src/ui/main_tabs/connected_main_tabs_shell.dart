import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_dependencies.dart';
import '../../app/connected_session_scope.dart';
import '../../domain/models/daemon_initial_data.dart';
import '../../shell/app_route.dart';
import '../core/widgets/widgets.dart';
import '../features/settings/settings.dart'
    show AppUpdateViewModel, SettingsViewModel;
import '../main_route_overlay.dart';
import '../main_tab_items.dart';
import '../mobile_ui_frame.dart';
import '../pages/pages.dart';
import '../view_models/main_tabs_shell_view_model.dart';

class ConnectedMainTabsShell extends StatelessWidget {
  const ConnectedMainTabsShell({
    super.key,
    required this.viewModel,
    required this.initialData,
    required this.homeViewModel,
    required this.settingsViewModel,
    required this.appUpdateViewModel,
    required this.connectedData,
    required this.repositories,
    required this.featureDependencies,
    required this.codingTab,
    required this.onSystemBack,
  });

  final MainTabsShellViewModel viewModel;
  final DaemonInitialData initialData;
  final HomeViewModel homeViewModel;
  final SettingsViewModel settingsViewModel;
  final AppUpdateViewModel? appUpdateViewModel;
  final ConnectedDataDependencies connectedData;
  final ConnectedSessionRepositories repositories;
  final FeatureDependencies featureDependencies;
  final Widget codingTab;
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
      ),
      codingTab,
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
          child: viewModel.activeRoute == RoutePage.tabs
              ? IndexedStack(index: viewModel.activeTab, children: pages)
              : MainRouteOverlay(
                  route: viewModel.activeRoute,
                  connectedData: connectedData,
                  repositories: repositories,
                  featureDependencies: featureDependencies,
                  onBack: viewModel.closeOverlay,
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
