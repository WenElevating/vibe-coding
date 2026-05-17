import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../app/app_dependencies.dart';
import '../services/daemon_client.dart';
import '../domain/models/daemon_connection_config.dart';
import '../domain/models/daemon_initial_data.dart';
import '../models/protocol.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import '../workflows/workspace/create_workspace_workflow.dart';
import 'core/widgets/widgets.dart';
import 'core/theme/theme.dart' as theme;
import 'features/workspace_picker/workspace_picker_sheet.dart';
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

  MainTabsPage.fromInitialData({
    super.key,
    required DaemonInitialData initialData,
    required this.client,
    required this.connectionConfig,
    required this.dependencies,
  }) : data = initialData.toAppSnapshot();

  final AppSnapshot data;
  final DaemonClient client;
  final DaemonConnectionConfig connectionConfig;
  final AppDependencies dependencies;

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}

class ConnectedEmptyWorkspaceShell extends StatefulWidget {
  const ConnectedEmptyWorkspaceShell({
    super.key,
    required this.health,
    required this.initialWorkspaces,
    required this.client,
    required this.connectionConfig,
    required this.dependencies,
  });

  final DaemonHealth health;
  final List<WorkspaceSummary> initialWorkspaces;
  final DaemonClient client;
  final DaemonConnectionConfig connectionConfig;
  final AppDependencies dependencies;

  @override
  State<ConnectedEmptyWorkspaceShell> createState() =>
      _ConnectedEmptyWorkspaceShellState();
}

class _ConnectedEmptyWorkspaceShellState
    extends State<ConnectedEmptyWorkspaceShell> {
  late final ConnectedDataDependencies _connectedData;
  late List<WorkspaceSummary> _workspaces;
  var _activeTab = 1;
  Object? _error;
  bool _creating = false;
  bool _loadingWorkspace = false;

  @override
  void initState() {
    super.initState();
    _connectedData = widget.dependencies.data.forDaemonClient(widget.client);
    _workspaces = List<WorkspaceSummary>.unmodifiable(widget.initialWorkspaces);
  }

  Future<void> _showCreateWorkspace() async {
    if (_creating) return;
    final request = await showModalBottomSheet<WorkspaceCreationRequest>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AddWorkspaceSheet(
              workspaceRepository: _connectedData.workspaceRepository,
            ));
    if (request == null || !mounted) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    final outcome = await CreateWorkspaceWorkflow(
      client: _connectedData.workspaceRepository,
      timeout: const Duration(seconds: 15),
    ).create(path: request.path, name: request.name);
    if (!mounted) return;
    switch (outcome) {
      case CreateWorkspaceSuccess(:final workspace, :final workspaces):
        await _openMainTabs(workspace, workspaces);
      case CreateWorkspaceNotConfirmed(:final workspaceId, :final workspaces):
        setState(() {
          _creating = false;
          _workspaces = List<WorkspaceSummary>.unmodifiable(workspaces);
          _error = StateError(
              'Workspace $workspaceId was created but not listed yet.');
        });
      case CreateWorkspaceFailure(:final error):
        setState(() {
          _creating = false;
          _error = error;
        });
      case CreateWorkspaceTimeout():
        setState(() {
          _creating = false;
          _error = TimeoutException('Workspace creation timed out.');
        });
    }
  }

  Future<void> _openMainTabs(
    WorkspaceSummary workspace,
    List<WorkspaceSummary> workspaces,
  ) async {
    setState(() {
      _loadingWorkspace = true;
      _error = null;
    });
    final snapshot = await loadWorkspaceBootstrap(
      widget.client,
      health: widget.health,
      workspaces: workspaces,
      workspace: workspace,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (context) => MainTabsPage.fromInitialData(
              initialData: snapshot.toDaemonInitialData(),
              client: widget.client,
              connectionConfig: widget.connectionConfig,
              dependencies: widget.dependencies,
            )));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = [
      _ConnectedEmptyHomePage(onCreateWorkspace: _showCreateWorkspace),
      _buildWorkspaceListPage(),
      _ConnectedEmptySettingsPage(
        health: widget.health,
        connectionConfig: widget.connectionConfig,
      ),
    ];
    return Scaffold(
      body: MobileUiFrame(
        child: Stack(children: [
          IndexedStack(index: _activeTab, children: pages),
          if (_creating || _loadingWorkspace)
            Container(
              color: Colors.black.withValues(alpha: .24),
              alignment: Alignment.center,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111820),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: .1)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Loading workspace...',
                        style: TextStyle(color: theme.text, fontSize: 12)),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20 + MediaQuery.paddingOf(context).bottom,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.red.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.red.withValues(alpha: .24)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: theme.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('$_error',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: theme.red, fontSize: 11.5)),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      bottomNavigationBar: BottomNav(
        selected: _activeTab,
        items: mainTabItems(l10n),
        onTap: (index) => setState(() => _activeTab = index),
      ),
    );
  }

  Widget _buildWorkspaceListPage() => WorkspaceListPage(
        workspaces: _workspaces,
        onSelected: (workspace) =>
            unawaited(_openMainTabs(workspace, _workspaces)),
        onAddWorkspace: _showCreateWorkspace,
      );
}

class _ConnectedEmptyHomePage extends StatelessWidget {
  const _ConnectedEmptyHomePage({required this.onCreateWorkspace});

  final VoidCallback onCreateWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      const SizedBox(height: 8),
      Text(l10n.workspaceListTitle,
          style: const TextStyle(
              color: theme.text, fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      Text(
        l10n.workspaceListFootnote,
        style: const TextStyle(color: theme.muted, fontSize: 13, height: 1.45),
      ),
      const SizedBox(height: 18),
      PrimaryButton(l10n.workspaceAddTitle, onTap: onCreateWorkspace),
    ]);
  }
}

class _ConnectedEmptySettingsPage extends StatelessWidget {
  const _ConnectedEmptySettingsPage({
    required this.health,
    required this.connectionConfig,
  });

  final DaemonHealth health;
  final DaemonConnectionConfig connectionConfig;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      Subhead(l10n.settingsCurrentConnectionTitle),
      _EmptyStateCard(children: [
        _EmptyStateRow(title: 'daemon', value: health.daemonVersion),
        _EmptyStateRow(
            title: l10n.settingsDaemonAddressLabel,
            value: connectionConfig.addressInput),
        _EmptyStateRow(
            title: l10n.settingsWorkspaceLabel,
            value: l10n.workspaceAvailableSection),
      ]),
    ]);
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.stroke),
        ),
        child: Column(children: children),
      );
}

class _EmptyStateRow extends StatelessWidget {
  const _EmptyStateRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(title, style: const TextStyle(color: theme.muted, fontSize: 12)),
          const Spacer(),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class _MainTabsPageState extends State<MainTabsPage> {
  late MainTabsViewModel _viewModel;
  late ConnectedDataDependencies _connectedData;
  late WorkbenchDependencies _workbenchDependencies;
  var _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();

  @override
  void initState() {
    super.initState();
    final pageDependencies =
        widget.dependencies.createMainTabsDependencies(widget.client);
    _connectedData = pageDependencies.connectedData;
    _workbenchDependencies = pageDependencies.workbenchDependencies;
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
      final pageDependencies =
          widget.dependencies.createMainTabsDependencies(widget.client);
      _connectedData = pageDependencies.connectedData;
      _workbenchDependencies = pageDependencies.workbenchDependencies;
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
    if (_viewModel.activeTab == 1) {
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
      _buildCodingTab(),
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
                (_viewModel.activeTab != 1 || _viewModel.codingSessionListOpen)
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
