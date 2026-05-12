import 'package:flutter/material.dart';

import '../features/adapters/adapters.dart';
import '../features/diagnostics/diagnostics.dart';
import '../features/notifications/notifications.dart';
import '../features/run_detail/run_detail.dart';
import '../features/workbench/workbench.dart';
import '../services/daemon_client.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';

class MainRouteOverlay extends StatelessWidget {
  const MainRouteOverlay({
    super.key,
    required this.route,
    required this.data,
    required this.client,
    required this.onBack,
  });

  final RoutePage route;
  final AppSnapshot data;
  final DaemonClient client;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return switch (route) {
      RoutePage.detail => RunDetailPage(
          onBack: onBack,
          data: data,
          client: client,
        ),
      RoutePage.approval => ApprovalPage(onBack: onBack),
      RoutePage.adapters => AdaptersPage(
          onBack: onBack,
          viewModel: AdaptersViewModel(snapshot: data),
        ),
      RoutePage.notifications => NotificationsPage(onBack: onBack),
      RoutePage.diagnostics => DiagnosticsPage(
          onBack: onBack,
          data: data,
          client: client,
        ),
      RoutePage.tabs => const SizedBox.shrink(),
    };
  }
}
