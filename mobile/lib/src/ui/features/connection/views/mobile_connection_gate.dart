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
          return _ConnectedMainTabsHost(
            viewModel: viewModel,
            dependencies: dependencies,
          );
        }
        return MobileConnectionPage(controller: viewModel);
      },
    );
  }
}

class _ConnectedMainTabsHost extends StatefulWidget {
  const _ConnectedMainTabsHost({
    required this.viewModel,
    required this.dependencies,
  });

  final DaemonConnectionViewModel viewModel;
  final AppDependencies dependencies;

  @override
  State<_ConnectedMainTabsHost> createState() => _ConnectedMainTabsHostState();
}

class _ConnectedMainTabsHostState extends State<_ConnectedMainTabsHost> {
  Object? _clientIdentity;
  Object? _initialDataIdentity;
  MainTabsDependencies? _pageDependencies;

  @override
  void didUpdateWidget(covariant _ConnectedMainTabsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dependencies != widget.dependencies) {
      _clientIdentity = null;
      _initialDataIdentity = null;
      _pageDependencies = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.viewModel.client!;
    final initialData = widget.viewModel.initialData!;
    if (!identical(_clientIdentity, client)) {
      _clientIdentity = client;
      _initialDataIdentity = initialData;
      _pageDependencies = widget.dependencies.createMainTabsDependencies(
        client,
        initialData: initialData,
      );
    } else if (!identical(_initialDataIdentity, initialData)) {
      _initialDataIdentity = initialData;
      _pageDependencies!.sessionScope.hydrateFromBootstrap(initialData);
    }
    return MainTabsPage.fromInitialData(
      initialData: initialData,
      connectionConfig: widget.viewModel.connectedConfig!,
      pageDependencies: _pageDependencies!,
    );
  }
}
