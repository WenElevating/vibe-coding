import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../app/app_dependencies.dart';
import '../services/daemon_client.dart';
import '../domain/models/daemon_connection_config.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import 'core/widgets/widgets.dart';
import 'features/workbench/workbench.dart';
import 'main_tab_items.dart';
import 'main_route_overlay.dart';
import 'mobile_ui_frame.dart';
import 'pages/pages.dart';
import 'view_models/main_tabs_view_model.dart';

class MainTabsPage extends StatefulWidget {
  const MainTabsPage({
    super.key,
    required this.data,
    required this.client,
    required this.connectionConfig,
    required this.dependencies,
  });

  final AppSnapshot data;
  final DaemonClient client;
  final DaemonConnectionConfig connectionConfig;
  final AppDependencies dependencies;

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}

class _MainTabsPageState extends State<MainTabsPage> {
  late MainTabsViewModel _viewModel;
  late ConnectedDataDependencies _connectedData;
  late WorkbenchDependencies _workbenchDependencies;
  var _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();

  @override
  void initState() {
    super.initState();
    _connectedData = widget.dependencies.data.forDaemonClient(widget.client);
    _workbenchDependencies =
        widget.dependencies.features.createWorkbenchDependencies(widget.client);
    _viewModel = MainTabsViewModel(
      initialData: widget.data,
      adapterRepository: _connectedData.adapterRepository,
    );
    unawaited(_viewModel.ensureCodingAdaptersLoaded());
  }

  @override
  void didUpdateWidget(covariant MainTabsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      final oldWorkbenchDependencies = _workbenchDependencies;
      _connectedData = widget.dependencies.data.forDaemonClient(widget.client);
      _workbenchDependencies = widget.dependencies.features
          .createWorkbenchDependencies(widget.client);
      _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();
      _viewModel.resetForNewClient(
        adapterRepository: _connectedData.adapterRepository,
        data: widget.data,
      );
      _disposeWorkbenchDependenciesAfterBuild(oldWorkbenchDependencies);
      return;
    }
    if (oldWidget.data != widget.data &&
        _viewModel.adapterLoadState != CodingAdapterLoadState.loaded) {
      _viewModel.updateData(widget.data);
    }
  }

  @override
  void dispose() {
    _disposeWorkbenchDependencies(_workbenchDependencies);
    _viewModel.dispose();
    super.dispose();
  }

  void _disposeWorkbenchDependencies(WorkbenchDependencies dependencies) {
    dependencies.asrModelManager.dispose();
  }

  void _disposeWorkbenchDependenciesAfterBuild(
    WorkbenchDependencies dependencies,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposeWorkbenchDependencies(dependencies);
    });
  }

  Future<void> _handleSystemBack() async {
    if (_viewModel.isOverlayActive) {
      _viewModel.closeOverlay();
      return;
    }
    if (_viewModel.activeTab == 2) {
      final consumed =
          await (_codingWorkbenchKey.currentState?.handleSystemBack() ??
              Future<bool>.value(false));
      if (consumed) return;
      _viewModel.selectTab(0);
      return;
    }
    if (_viewModel.activeTab != 0) {
      _viewModel.selectTab(0);
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _viewModel.data;
    final pages = [
      HomePage(
          open: _viewModel.openOverlay,
          selectTab: _viewModel.selectTab,
          data: data),
      RunsPage(open: _viewModel.openOverlay, data: data),
      _buildCodingTab(),
      QueuePage(data: data),
      SettingsPage(
        open: _viewModel.openOverlay,
        data: data,
        connectionConfig: widget.connectionConfig,
        streamOutput: _viewModel.streamOutput,
        expandThinking: _viewModel.expandThinking,
        permissionMode: _viewModel.permissionMode,
        onPermissionModeChanged: _viewModel.setPermissionMode,
        onStreamOutputChanged: _viewModel.setStreamOutput,
        onExpandThinkingChanged: _viewModel.setExpandThinking,
      ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Scaffold(
        body: MobileUiFrame(
          child: _viewModel.activeRoute == RoutePage.tabs
              ? IndexedStack(index: _viewModel.activeTab, children: pages)
              : MainRouteOverlay(
                  route: _viewModel.activeRoute,
                  data: data,
                  connectedData: _connectedData,
                  featureDependencies: widget.dependencies.features,
                  onBack: _viewModel.closeOverlay,
                ),
        ),
        bottomNavigationBar: _viewModel.activeRoute == RoutePage.tabs &&
                (_viewModel.activeTab != 2 || _viewModel.codingSessionListOpen)
            ? BottomNav(
                selected: _viewModel.activeTab,
                items: mainTabItems(l10n),
                onTap: _viewModel.selectTab)
            : null,
        extendBody: true,
      ),
    );
  }

  Widget _buildCodingTab() {
    if (_viewModel.adapterLoadState == CodingAdapterLoadState.loaded) {
      return CodingPage(
        data: _viewModel.data,
        workbenchDependencies: _workbenchDependencies,
        workbenchKey: _codingWorkbenchKey,
        onBack: () => _viewModel.selectTab(0),
        onSessionListChanged: _viewModel.reportSessionListOpen,
        openSessionListRequest: _viewModel.openSessionListRequest,
        streamOutput: _viewModel.streamOutput,
        expandThinking: _viewModel.expandThinking,
        permissionMode: _viewModel.permissionMode,
      );
    }
    return _CodingAdapterGate(
      failed: _viewModel.adapterLoadState == CodingAdapterLoadState.failed,
      error: _viewModel.adapterLoadError,
      onRetry: () => unawaited(_viewModel.ensureCodingAdaptersLoaded()),
    );
  }
}

class _CodingAdapterGate extends StatelessWidget {
  const _CodingAdapterGate({
    required this.failed,
    required this.error,
    required this.onRetry,
  });

  final bool failed;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!failed) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading CLI...'),
            ] else ...[
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              const Text('Unable to load CLI adapters'),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              PrimaryButton('Retry loading CLI', onTap: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
