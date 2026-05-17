import 'package:flutter/material.dart';

import '../../../../app/app_dependencies.dart';
import '../../../main_tabs_page.dart';
import '../../../mobile_connection_page.dart';
import '../../../mobile_loading_page.dart';
import '../view_models/daemon_connection_view_model.dart';

class MobileConnectionGate extends StatelessWidget {
  const MobileConnectionGate({
    super.key,
    required this.viewModel,
    required this.dependencies,
  });

  final DaemonConnectionViewModel viewModel;
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        if (viewModel.status == DaemonConnectionStatus.loadingConfig) {
          return const MobileLoadingPage();
        }
        if (viewModel.status == DaemonConnectionStatus.connected &&
            viewModel.initialData != null &&
            viewModel.client != null) {
          final initialData = viewModel.initialData!;
          if (!initialData.hasWorkspace) {
            return ConnectedEmptyWorkspacePage(
              health: initialData.health,
              initialWorkspaces: initialData.workspaces,
              client: viewModel.client!,
              connectionConfig: viewModel.connectedConfig!,
              dependencies: dependencies,
            );
          }
          return MainTabsPage.fromInitialData(
            initialData: initialData,
            client: viewModel.client!,
            connectionConfig: viewModel.connectedConfig!,
            dependencies: dependencies,
          );
        }
        return MobileConnectionPage(controller: viewModel);
      },
    );
  }
}
