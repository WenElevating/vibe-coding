import 'package:flutter/material.dart';

import '../../../shell/app_snapshot.dart';
import '../../features/workbench/workbench.dart';

class CodingPage extends StatelessWidget {
  const CodingPage({
    super.key,
    required this.data,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.workbenchDependencies,
    required this.workbenchKey,
    required this.streamOutput,
    required this.expandThinking,
    required this.permissionMode,
  });

  final AppSnapshot data;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final WorkbenchDependencies workbenchDependencies;
  final GlobalKey<CodingWorkbenchPageState> workbenchKey;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  Widget build(BuildContext context) {
    return CodingWorkbenchPage(
      key: workbenchKey,
      data: data,
      onBack: onBack,
      onSessionListChanged: onSessionListChanged,
      openSessionListRequest: openSessionListRequest,
      streamOutput: streamOutput,
      expandThinking: expandThinking,
      permissionMode: permissionMode,
      dependencies: workbenchDependencies,
    );
  }
}
