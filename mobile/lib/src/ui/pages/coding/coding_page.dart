import 'package:flutter/material.dart';
import '../../features/workbench/workbench.dart';

class CodingPage extends StatelessWidget {
  const CodingPage({
    super.key,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.workbenchDependencies,
    required this.workbenchKey,
    required this.streamOutput,
    required this.expandThinking,
    this.expandToolDetails = false,
    required this.permissionMode,
    required this.adapterLoading,
    required this.adapterError,
    required this.onRetryAdapters,
  });

  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final WorkbenchDependencies workbenchDependencies;
  final GlobalKey<CodingWorkbenchPageState> workbenchKey;
  final bool streamOutput;
  final bool expandThinking;
  final bool expandToolDetails;
  final String permissionMode;
  final bool adapterLoading;
  final Object? adapterError;
  final VoidCallback onRetryAdapters;

  @override
  Widget build(BuildContext context) {
    return CodingWorkbenchPage(
      key: workbenchKey,
      onBack: onBack,
      onSessionListChanged: onSessionListChanged,
      openSessionListRequest: openSessionListRequest,
      streamOutput: streamOutput,
      expandThinking: expandThinking,
      expandToolDetails: expandToolDetails,
      permissionMode: permissionMode,
      adapterLoading: adapterLoading,
      adapterError: adapterError,
      onRetryAdapters: onRetryAdapters,
      dependencies: workbenchDependencies,
    );
  }
}
