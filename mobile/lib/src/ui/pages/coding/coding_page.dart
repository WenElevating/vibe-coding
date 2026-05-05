import 'package:flutter/material.dart';

import '../../../features/workbench/workbench.dart';
import '../../../services/daemon_client.dart';
import '../../../shell/app_snapshot.dart';

class CodingPage extends StatelessWidget {
  const CodingPage({
    super.key,
    required this.data,
    required this.client,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.streamOutput,
    required this.expandThinking,
    required this.permissionMode,
  });

  final AppSnapshot data;
  final DaemonClient client;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  Widget build(BuildContext context) {
    return CodingWorkbenchPage(
      data: data,
      client: client,
      onBack: onBack,
      onSessionListChanged: onSessionListChanged,
      openSessionListRequest: openSessionListRequest,
      streamOutput: streamOutput,
      expandThinking: expandThinking,
      permissionMode: permissionMode,
    );
  }
}
