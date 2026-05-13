import 'package:flutter/material.dart';

import '../../../features/workbench/workbench.dart';
import '../../../services/asr_model_manager.dart';
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
  final GlobalKey<CodingWorkbenchPageState> workbenchKey;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  State<CodingPage> createState() => _CodingPageState();
}

class _CodingPageState extends State<CodingPage> {
  late AsrModelManager _asrModelManager;

  @override
  void initState() {
    super.initState();
    _asrModelManager = _createAsrModelManager();
  }

  @override
  void didUpdateWidget(covariant CodingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client == widget.client) return;
    _asrModelManager.dispose();
    _asrModelManager = _createAsrModelManager();
  }

  @override
  void dispose() {
    _asrModelManager.dispose();
    super.dispose();
  }

  AsrModelManager _createAsrModelManager() =>
      AsrModelManager(client: widget.client.createAsrModelClient());

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
      asrModelManager: _asrModelManager,
    );
  }
}
