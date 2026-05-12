import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import 'features/connection/view_models/daemon_connection_view_model.dart';
import 'features/connection/views/mobile_connection_gate.dart';

class MobileUi extends StatefulWidget {
  const MobileUi({super.key, this.dependencies, this.connectionController});

  final AppDependencies? dependencies;
  final DaemonConnectionViewModel? connectionController;

  @override
  State<MobileUi> createState() => _MobileUiState();
}

class _MobileUiState extends State<MobileUi> {
  late final AppDependencies _dependencies;
  late final DaemonConnectionViewModel _connectionController;
  late final bool _ownsConnectionController;

  @override
  void initState() {
    super.initState();
    _dependencies = widget.dependencies ?? AppDependencies.createDefault();
    _ownsConnectionController = widget.connectionController == null;
    _connectionController = widget.connectionController ??
        _dependencies.features.createDaemonConnectionViewModel();
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
}
