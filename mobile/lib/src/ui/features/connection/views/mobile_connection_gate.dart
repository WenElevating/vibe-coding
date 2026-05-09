import 'package:flutter/material.dart';

import '../../../main_tabs_page.dart';
import '../../../mobile_connection_page.dart';
import '../../../mobile_loading_page.dart';
import '../view_models/daemon_connection_view_model.dart';

class MobileConnectionGate extends StatelessWidget {
  const MobileConnectionGate({super.key, required this.viewModel});

  final DaemonConnectionViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        if (viewModel.status == DaemonConnectionStatus.loadingConfig) {
          return const MobileLoadingPage();
        }
        if (viewModel.status == DaemonConnectionStatus.connected &&
            viewModel.snapshot != null &&
            viewModel.client != null) {
          return MainTabsPage(
            data: viewModel.snapshot!,
            client: viewModel.client!,
            connectionConfig: viewModel.connectedConfig!,
          );
        }
        return MobileConnectionPage(controller: viewModel);
      },
    );
  }
}
