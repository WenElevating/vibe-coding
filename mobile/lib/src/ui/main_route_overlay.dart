import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../domain/models/daemon_initial_data.dart';
import '../models/protocol.dart';
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
    required this.connectedData,
    required this.featureDependencies,
    required this.onBack,
  });

  final RoutePage route;
  final DaemonInitialData data;
  final ConnectedDataDependencies connectedData;
  final FeatureDependencies featureDependencies;
  final VoidCallback onBack;

  @override
  State<MainRouteOverlay> createState() => _MainRouteOverlayState();
}

class _MainRouteOverlayState extends State<MainRouteOverlay> {
  DiagnosticsViewModel? _diagnosticsViewModel;
  RunDetailViewModel? _runDetailViewModel;
  _RunDetailViewModelKey? _runDetailViewModelKey;

  @override
  void didUpdateWidget(covariant MainRouteOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedData != widget.connectedData ||
        oldWidget.featureDependencies != widget.featureDependencies) {
      _diagnosticsViewModel?.dispose();
      _diagnosticsViewModel = null;
      _runDetailViewModel?.dispose();
      _runDetailViewModel = null;
      _runDetailViewModelKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data.toAppSnapshot();
    return switch (widget.route) {
      RoutePage.detail => _buildRunDetailPage(),
      RoutePage.approval => ApprovalPage(onBack: widget.onBack),
      RoutePage.adapters => AdaptersPage(
          onBack: widget.onBack,
          viewModel: AdaptersViewModel(snapshot: data),
        ),
      RoutePage.notifications => NotificationsPage(onBack: widget.onBack),
      RoutePage.diagnostics => _buildDiagnosticsPage(),
      RoutePage.tabs => const SizedBox.shrink(),
    };
  }

  Widget _buildDiagnosticsPage() {
    _diagnosticsViewModel ??= widget.featureDependencies
        .createDiagnosticsViewModel(widget.connectedData);
    return DiagnosticsPage(
      onBack: widget.onBack,
      viewModel: _diagnosticsViewModel!,
    );
  }

  Widget _buildRunDetailPage() {
    final selectedRun = _selectedRun(widget.data.toAppSnapshot());
    final viewModelKey = _RunDetailViewModelKey(
      run: selectedRun,
      scope: widget.connectedData,
    );
    if (_runDetailViewModel == null || _runDetailViewModelKey != viewModelKey) {
      _runDetailViewModel?.dispose();
      _runDetailViewModel = widget.featureDependencies
          .createRunDetailViewModel(widget.connectedData, selectedRun);
      _runDetailViewModelKey = viewModelKey;
    }

    return RunDetailPage(
      onBack: widget.onBack,
      viewModel: _runDetailViewModel!,
    );
  }

  @override
  void dispose() {
    _diagnosticsViewModel?.dispose();
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
