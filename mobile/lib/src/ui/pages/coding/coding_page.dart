import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../../features/workbench/workbench.dart';
import '../../../services/daemon_client.dart';
import '../../../shell/app_snapshot.dart';

class CodingPage extends StatefulWidget {
  const CodingPage({
    super.key,
    required this.data,
    required this.client,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.dependencies,
    required this.workbenchKey,
    required this.streamOutput,
    required this.expandThinking,
    required this.permissionMode,
  });

  final AppSnapshot data;
  final DaemonClient client;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final AppDependencies dependencies;
  final GlobalKey<CodingWorkbenchPageState> workbenchKey;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  State<CodingPage> createState() => _CodingPageState();
}

class _CodingPageState extends State<CodingPage> {
  late WorkbenchDependencies _workbenchDependencies;

  @override
  void initState() {
    super.initState();
    _workbenchDependencies = _createWorkbenchDependencies();
  }

  @override
  void didUpdateWidget(covariant CodingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client == widget.client) return;
    _workbenchDependencies.asrModelManager.dispose();
    _workbenchDependencies = _createWorkbenchDependencies();
  }

  @override
  void dispose() {
    _workbenchDependencies.asrModelManager.dispose();
    super.dispose();
  }

  WorkbenchDependencies _createWorkbenchDependencies() {
    return widget.dependencies.features.createWorkbenchDependencies(
      widget.client,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CodingWorkbenchPage(
      key: widget.workbenchKey,
      data: widget.data,
      client: widget.client,
      onBack: widget.onBack,
      onSessionListChanged: widget.onSessionListChanged,
      openSessionListRequest: widget.openSessionListRequest,
      streamOutput: widget.streamOutput,
      expandThinking: widget.expandThinking,
      permissionMode: widget.permissionMode,
      dependencies: _workbenchDependencies,
    );
  }
}
