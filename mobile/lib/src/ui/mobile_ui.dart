import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../services/daemon_connection_config_store.dart';
import '../state/daemon_connection_controller.dart';
import 'main_tabs_page.dart';
import 'mobile_connection_page.dart';
import 'mobile_loading_page.dart';

class MobileUi extends StatefulWidget {
  const MobileUi({super.key, this.connectionController});

  final DaemonConnectionController? connectionController;

  @override
  State<MobileUi> createState() => _MobileUiState();
}

class _MobileUiState extends State<MobileUi> {
  late final DaemonConnectionController _connectionController;
  late final bool _ownsConnectionController;

  @override
  void initState() {
    super.initState();
    _ownsConnectionController = widget.connectionController == null;
    _connectionController = widget.connectionController ??
        DaemonConnectionController(
          store: DaemonConnectionConfigStore(),
          tokenStore: MemoryTokenStore(),
        );
    _connectionController.load();
  }

  @override
  void dispose() {
    if (_ownsConnectionController) {
      _connectionController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _connectionController,
      builder: (context, snapshot) {
        if (_connectionController.status ==
            DaemonConnectionStatus.loadingConfig) {
          return const MobileLoadingPage();
        }
        if (_connectionController.status == DaemonConnectionStatus.connected &&
            _connectionController.snapshot != null &&
            _connectionController.client != null) {
          return MainTabsPage(
            data: _connectionController.snapshot!,
            client: _connectionController.client!,
            connectionConfig: _connectionController.connectedConfig!,
          );
        }
        return MobileConnectionPage(controller: _connectionController);
      },
    );
  }
}
