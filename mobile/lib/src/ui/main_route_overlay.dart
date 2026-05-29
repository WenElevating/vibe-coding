import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../app/connected_session_scope.dart';
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
    required this.repositories,
    required this.featureDependencies,
    required this.onBack,
  });

  final RoutePage route;
  final DaemonInitialData data;
  final ConnectedDataDependencies connectedData;
  final ConnectedSessionRepositories repositories;
  final FeatureDependencies featureDependencies;
  final VoidCallback onBack;

  @override
  State<MainRouteOverlay> createState() => _MainRouteOverlayState();
}

class _MainRouteOverlayState extends State<MainRouteOverlay> {
  DiagnosticsViewModel? _diagnosticsViewModel;
  RunDetailViewModel? _runDetailViewModel;
  _RunDetailViewModelKey? _runDetailViewModelKey;
  AdaptersViewModel? _adaptersViewModel;
  Object? _adaptersViewModelScope;

  @override
  void didUpdateWidget(covariant MainRouteOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedData != widget.connectedData ||
        oldWidget.featureDependencies != widget.featureDependencies ||
        oldWidget.repositories != widget.repositories) {
      _diagnosticsViewModel?.dispose();
      _diagnosticsViewModel = null;
      _runDetailViewModel?.dispose();
      _runDetailViewModel = null;
      _runDetailViewModelKey = null;
      _disposeAdaptersViewModel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.route) {
      RoutePage.detail => _buildRunDetailPage(),
      RoutePage.approval => ApprovalPage(onBack: widget.onBack),
      RoutePage.adapters => _buildAdaptersPage(),
      RoutePage.notifications => NotificationsPage(onBack: widget.onBack),
      RoutePage.diagnostics => _buildDiagnosticsPage(),
      RoutePage.tabs => const SizedBox.shrink(),
    };
  }

  Widget _buildAdaptersPage() {
    final repositories = widget.repositories;
    if (_adaptersViewModel == null || _adaptersViewModelScope != repositories) {
      _disposeAdaptersViewModel();
      _adaptersViewModel = AdaptersViewModel(
        adapterRepository: repositories.cliAdapterRepository,
        commandCatalogRepository: repositories.commandCatalogRepository,
      );
      unawaited(_adaptersViewModel!.loadCatalog());
      _adaptersViewModelScope = repositories;
    }
    return AdaptersPage(onBack: widget.onBack, viewModel: _adaptersViewModel!);
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
    _disposeAdaptersViewModel();
    super.dispose();
  }

  void _disposeAdaptersViewModel() {
    _adaptersViewModel?.dispose();
    _adaptersViewModel = null;
    _adaptersViewModelScope = null;
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
