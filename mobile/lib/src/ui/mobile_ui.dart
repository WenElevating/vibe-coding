import 'package:flutter/material.dart';

import '../data/repositories/daemon_connection_config_repository.dart';
import '../services/daemon_client.dart';
import '../services/daemon_connection_config_store.dart';
import '../workflows/connection/daemon_connection_workflow.dart';
import 'features/connection/view_models/daemon_connection_view_model.dart';
import 'features/connection/views/mobile_connection_gate.dart';

class MobileUi extends StatefulWidget {
  const MobileUi({super.key, this.connectionController});

  final DaemonConnectionViewModel? connectionController;

  @override
  State<MobileUi> createState() => _MobileUiState();
}

class _MobileUiState extends State<MobileUi> {
  late final DaemonConnectionViewModel _connectionController;
  late final bool _ownsConnectionController;

  @override
  void initState() {
    super.initState();
    _ownsConnectionController = widget.connectionController == null;
    _connectionController = widget.connectionController ?? _createViewModel();
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
  Widget build(BuildContext context) =>
      MobileConnectionGate(viewModel: _connectionController);

  DaemonConnectionViewModel _createViewModel() {
    final store = DaemonConnectionConfigStore();
    final repository = DaemonConnectionConfigRepository(store: store);
    final tokenStore = MemoryTokenStore();
    return DaemonConnectionViewModel(
      configRepository: repository,
      workflow: DaemonConnectionWorkflow(
        configRepository: repository,
        tokenStore: tokenStore,
      ),
    );
  }
}
