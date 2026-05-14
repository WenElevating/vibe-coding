import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../services/daemon_client.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import 'features/adapters/adapters.dart';
import 'features/diagnostics/diagnostics.dart';
import 'features/notifications/notifications.dart';
import 'features/run_detail/run_detail.dart';
import 'features/workbench/workbench.dart';

class MainRouteOverlay extends StatefulWidget {
  const MainRouteOverlay({
    super.key,
    required this.route,
    required this.data,
    required this.client,
    required this.diagnosticsViewModel,
    required this.runDetailViewModelScope,
    required this.createRunDetailViewModel,
    required this.onBack,
  });

  final RoutePage route;
  final AppSnapshot data;
  final DaemonClient client;
  final DiagnosticsViewModel diagnosticsViewModel;
  final Object runDetailViewModelScope;
  final RunDetailViewModel Function(RunSummary run) createRunDetailViewModel;
  final VoidCallback onBack;

  @override
  State<MainRouteOverlay> createState() => _MainRouteOverlayState();
}

class _MainRouteOverlayState extends State<MainRouteOverlay> {
  RunDetailViewModel? _runDetailViewModel;
  _RunDetailViewModelKey? _runDetailViewModelKey;

  @override
  Widget build(BuildContext context) {
    return switch (widget.route) {
      RoutePage.detail => _buildRunDetailPage(),
      RoutePage.approval => ApprovalPage(onBack: widget.onBack),
      RoutePage.adapters => AdaptersPage(
          onBack: widget.onBack,
          viewModel: AdaptersViewModel(snapshot: widget.data),
        ),
      RoutePage.notifications => NotificationsPage(onBack: widget.onBack),
      RoutePage.diagnostics => DiagnosticsPage(
          onBack: widget.onBack,
          viewModel: widget.diagnosticsViewModel,
        ),
      RoutePage.tabs => const SizedBox.shrink(),
    };
  }

  Widget _buildRunDetailPage() {
    final selectedRun = _selectedRun(widget.data);
    final viewModelKey = _RunDetailViewModelKey(
      run: selectedRun,
      scope: widget.runDetailViewModelScope,
    );
    if (_runDetailViewModel == null || _runDetailViewModelKey != viewModelKey) {
      _runDetailViewModel?.dispose();
      _runDetailViewModel = widget.createRunDetailViewModel(selectedRun);
      _runDetailViewModelKey = viewModelKey;
    }

    return RunDetailPage(
      onBack: widget.onBack,
      viewModel: _runDetailViewModel!,
    );
  }

  @override
  void dispose() {
    _runDetailViewModel?.dispose();
    super.dispose();
  }
}

class _RunDetailViewModelKey {
  _RunDetailViewModelKey({
    required RunSummary run,
    required this.scope,
  })  : id = run.id,
        tool = run.tool,
        workspaceId = run.workspaceId,
        status = run.status,
        cliSessionId = run.cliSessionId;

  final Object scope;
  final String id;
  final String tool;
  final String workspaceId;
  final String status;
  final String? cliSessionId;

  @override
  bool operator ==(Object other) =>
      other is _RunDetailViewModelKey &&
      other.scope == scope &&
      other.id == id &&
      other.tool == tool &&
      other.workspaceId == workspaceId &&
      other.status == status &&
      other.cliSessionId == cliSessionId;

  @override
  int get hashCode => Object.hash(
        scope,
        id,
        tool,
        workspaceId,
        status,
        cliSessionId,
      );
}

RunSummary _selectedRun(AppSnapshot data) {
  if (data.runs.isNotEmpty) return data.runs.first;
  // Temporary bridge until detail routes carry the tapped run id.
  return RunSummary(
    id: '',
    tool: data.adapters.isNotEmpty ? data.adapters.first.adapter : '',
    workspaceId: data.workspace.id,
    status: 'unknown',
  );
}
