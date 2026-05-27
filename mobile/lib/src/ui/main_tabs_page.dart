import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../app/app_dependencies.dart';
import '../services/coding_preferences_store.dart';
import '../domain/models/daemon_connection_config.dart';
import '../domain/models/daemon_initial_data.dart';
import '../models/protocol.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import '../workflows/workspace/create_workspace_workflow.dart';
import 'core/widgets/widgets.dart';
import 'core/theme/theme.dart' as theme;
import 'features/workspace_picker/workspace_picker_sheet.dart';
import 'features/settings/settings.dart'
    show
        AppUpdateCheckTrigger,
        AppUpdatePanel,
        AppUpdateState,
        AppUpdateStatus,
        AppUpdateViewModel,
        appUpdateTitleFor;
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
    required this.connectionConfig,
    required this.pageDependencies,
    this.forceAndroidForTesting,
  }) : emptyInitialData = null;

  MainTabsPage.fromInitialData({
    super.key,
    required DaemonInitialData initialData,
    required this.connectionConfig,
    required this.pageDependencies,
    this.forceAndroidForTesting,
  })  : data =
            initialData.workspace == null ? null : initialData.toAppSnapshot(),
        emptyInitialData = initialData;

  final AppSnapshot? data;
  final DaemonInitialData? emptyInitialData;
  final DaemonConnectionConfig connectionConfig;
  final MainTabsDependencies pageDependencies;
  final bool? forceAndroidForTesting;

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
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
    this.appUpdateViewModel,
  });

  final DaemonHealth? health;
  final DaemonConnectionConfig connectionConfig;
  final AppUpdateViewModel? appUpdateViewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      Subhead(l10n.settingsCurrentConnectionTitle),
      _EmptyStateCard(children: [
        _EmptyStateRow(
            title: l10n.settingsDaemonAddressLabel,
            value: connectionConfig.addressInput),
        _EmptyStateRow(
            title: l10n.settingsWorkspaceLabel,
            value: l10n.workspaceAvailableSection),
      ]),
      const SizedBox(height: 20),
      Subhead(l10n.settingsAboutSection),
      _EmptyStateCard(children: [
        _EmptyStateRow(title: 'daemon', value: health?.daemonVersion ?? '—'),
        if (appUpdateViewModel != null)
          _EmptyAppUpdateCheckRow(viewModel: appUpdateViewModel!),
      ]),
    ]);
  }
}

class _EmptyAppUpdateCheckRow extends StatelessWidget {
  const _EmptyAppUpdateCheckRow({required this.viewModel});

  final AppUpdateViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => AppUpdatePanel(
        state: viewModel.state,
        onCheck: () => unawaited(viewModel.checkForUpdates()),
        onDownload: () => unawaited(viewModel.download()),
        onInstall: () => unawaited(viewModel.install()),
        onDiscard: () => unawaited(viewModel.discard()),
        onPostpone: viewModel.postponeCurrentUpdatePrompt,
        child: _EmptyStateTapRow(
          title: l10n.appUpdateCheckAction,
          value: _emptyAppUpdateRowValue(l10n, viewModel.state),
          onTap: () => unawaited(viewModel.checkForUpdates()),
        ),
      ),
    );
  }
}

String _emptyAppUpdateRowValue(AppLocalizations l10n, AppUpdateState state) {
  if (state.status == AppUpdateStatus.idle) {
    return state.installedVersionName;
  }
  return appUpdateTitleFor(l10n, state);
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

class _EmptyStateTapRow extends StatelessWidget {
  const _EmptyStateTapRow(
      {required this.title, this.value, required this.onTap});

  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(color: theme.muted, fontSize: 12))),
          _EmptyStateTapRowTrailing(value: value),
        ]),
      ),
    );
  }
}

class _EmptyStateTapRowTrailing extends StatelessWidget {
  const _EmptyStateTapRowTrailing({required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right_rounded, color: theme.faint, size: 18),
        ],
      );
}

class _MainTabsPageState extends State<MainTabsPage>
    with WidgetsBindingObserver {
  MainTabsViewModel? _viewModel;
  late ConnectedDataDependencies _connectedData;
  late WorkbenchDependencies _workbenchDependencies;
  late final CodingPreferencesStore _codingPreferencesStore;
  AppUpdateViewModel? _appUpdateViewModel;
  var _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();
  var _emptyActiveTab = 1;
  late List<WorkspaceSummary> _emptyWorkspaces;
  Object? _emptyError;
  bool _creatingWorkspace = false;
  bool _loadingWorkspace = false;
  int _appUpdateGeneration = 0;
  int _codingPreferencesGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectedData = widget.pageDependencies.connectedData;
    _workbenchDependencies = widget.pageDependencies.workbenchDependencies;
    _codingPreferencesStore = CodingPreferencesStore();
    _emptyWorkspaces = List<WorkspaceSummary>.unmodifiable(
        widget.emptyInitialData?.workspaces ?? const <WorkspaceSummary>[]);
    unawaited(_createAppUpdateViewModel());
    final data = widget.data;
    if (data != null) {
      _viewModel = MainTabsViewModel(
        initialData: data,
        adapterRepository: _connectedData.adapterRepository,
      );
      unawaited(_loadCodingPreferences(_viewModel!));
      unawaited(_viewModel!.ensureCodingAdaptersLoaded());
    }
  }

  @override
  void didUpdateWidget(covariant MainTabsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageDependencies != widget.pageDependencies) {
      final oldWorkbenchDependencies = _workbenchDependencies;
      final oldConnectedData = _connectedData;
      _connectedData = widget.pageDependencies.connectedData;
      _workbenchDependencies = widget.pageDependencies.workbenchDependencies;
      _disposeAppUpdateViewModel();
      unawaited(_createAppUpdateViewModel());
      _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();
      final data = widget.data;
      _viewModel?.dispose();
      _viewModel = data == null
          ? null
          : MainTabsViewModel(
              initialData: data,
              adapterRepository: _connectedData.adapterRepository,
            );
      if (_viewModel != null) {
        unawaited(_loadCodingPreferences(_viewModel!));
        unawaited(_viewModel!.ensureCodingAdaptersLoaded());
      }
      _disposeWorkbenchDependenciesAfterBuild(oldWorkbenchDependencies);
      unawaited(oldConnectedData.dispose());
      return;
    }
    if (oldWidget.data != widget.data &&
        widget.data != null &&
        _viewModel?.adapterLoadState != CodingAdapterLoadState.loaded) {
      _viewModel?.updateData(widget.data!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeWorkbenchDependencies(_workbenchDependencies);
    _disposeAppUpdateViewModel();
    unawaited(_connectedData.dispose());
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppUpdateForeground(AppUpdateCheckTrigger.appResumed));
    }
  }

  Future<void> _createAppUpdateViewModel() async {
    final generation = ++_appUpdateGeneration;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final versionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      final viewModel = await widget.pageDependencies.createAppUpdateViewModel(
        installedVersionCode: versionCode,
        installedVersionName: packageInfo.version,
      );
      if (!mounted || generation != _appUpdateGeneration) {
        viewModel.dispose();
        return;
      }
      setState(() => _appUpdateViewModel = viewModel);
      unawaited(
        _handleAppUpdateForeground(AppUpdateCheckTrigger.connectedShellCreated),
      );
    } catch (_) {
      if (!mounted || generation != _appUpdateGeneration) return;
      setState(() => _appUpdateViewModel = null);
      if (widget.forceAndroidForTesting ?? Platform.isAndroid) {
        _recordAppUpdateSilentCheckSkipped(
          AppUpdateCheckTrigger.connectedShellCreated,
          'viewModelMissing',
        );
      }
    }
  }

  void _disposeAppUpdateViewModel() {
    _appUpdateGeneration += 1;
    _appUpdateViewModel?.dispose();
    _appUpdateViewModel = null;
  }

  Future<void> _handleAppUpdateForeground(AppUpdateCheckTrigger trigger) async {
    if (!(widget.forceAndroidForTesting ?? Platform.isAndroid)) {
      return;
    }
    final viewModel = _appUpdateViewModel;
    if (viewModel == null) {
      _recordAppUpdateSilentCheckSkipped(trigger, 'viewModelMissing');
      return;
    }
    await viewModel.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (!mounted || _appUpdateViewModel != viewModel) return;
    if (_shouldSkipForegroundUpdateCheckAfterRecovery(viewModel.state.status)) {
      _recordAppUpdateSilentCheckSkipped(trigger, 'activeOperation');
      return;
    }
    await viewModel.checkForUpdates(trigger: trigger);
  }

  void _recordAppUpdateSilentCheckSkipped(
    AppUpdateCheckTrigger trigger,
    String reason,
  ) {
    _connectedData.recordDiagnosticEvent(
      'update.silent_check.skipped',
      {
        'trigger': trigger.diagnosticName,
        'reason': reason,
      },
      path: 'app_update',
    );
  }

  Future<void> _loadCodingPreferences(MainTabsViewModel viewModel) async {
    final generation = _codingPreferencesGeneration;
    try {
      final permissionMode = await _codingPreferencesStore.loadPermissionMode();
      if (!mounted ||
          _viewModel != viewModel ||
          generation != _codingPreferencesGeneration) {
        return;
      }
      viewModel.setPermissionMode(permissionMode);
    } catch (error) {
      if (!mounted) return;
      _connectedData.recordDiagnosticEvent(
        'settings.permission_mode.load_failed',
        {'error': '$error'},
        path: 'settings',
      );
    }
  }

  void _handlePermissionModeChanged(String value) {
    _codingPreferencesGeneration += 1;
    final permissionMode =
        CodingPreferencesStore.normalizePermissionMode(value);
    _viewModel?.setPermissionMode(permissionMode);
    unawaited(_savePermissionMode(permissionMode));
  }

  Future<void> _savePermissionMode(String value) async {
    try {
      await _codingPreferencesStore.savePermissionMode(value);
    } catch (error) {
      if (!mounted) return;
      _connectedData.recordDiagnosticEvent(
        'settings.permission_mode.save_failed',
        {'error': '$error'},
        path: 'settings',
      );
    }
  }

  bool _shouldSkipForegroundUpdateCheckAfterRecovery(AppUpdateStatus status) {
    return status == AppUpdateStatus.downloading ||
        status == AppUpdateStatus.verifying ||
        status == AppUpdateStatus.readyToInstall ||
        status == AppUpdateStatus.installPermissionNeeded ||
        status == AppUpdateStatus.installing ||
        status == AppUpdateStatus.awaitingUserConfirmation ||
        status == AppUpdateStatus.installCancelled ||
        status == AppUpdateStatus.installFailed;
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
    final viewModel = _viewModel;
    if (viewModel == null) {
      if (_emptyActiveTab != 0) {
        setState(() => _emptyActiveTab = 0);
        return;
      }
      await SystemNavigator.pop();
      return;
    }
    if (viewModel.isOverlayActive) {
      viewModel.closeOverlay();
      return;
    }
    if (viewModel.activeTab == 1) {
      final consumed =
          await (_codingWorkbenchKey.currentState?.handleSystemBack() ??
              Future<bool>.value(false));
      if (consumed) return;
      viewModel.selectTab(0);
      return;
    }
    if (viewModel.activeTab != 0) {
      viewModel.selectTab(0);
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel;
    if (viewModel == null) return _buildShell(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = _viewModel;
    if (viewModel == null) return _buildEmptyShell(context, l10n);
    final data = viewModel.data;
    final pages = [
      HomePage(
          open: viewModel.openOverlay,
          selectTab: viewModel.selectTab,
          data: data),
      _buildCodingTab(),
      SettingsPage(
        open: viewModel.openOverlay,
        data: data,
        connectionConfig: widget.connectionConfig,
        streamOutput: viewModel.streamOutput,
        expandThinking: viewModel.expandThinking,
        permissionMode: viewModel.permissionMode,
        appUpdateViewModel: _appUpdateViewModel,
        onPermissionModeChanged: _handlePermissionModeChanged,
        onStreamOutputChanged: viewModel.setStreamOutput,
        onExpandThinkingChanged: viewModel.setExpandThinking,
      ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Scaffold(
        body: MobileUiFrame(
          child: viewModel.activeRoute == RoutePage.tabs
              ? IndexedStack(index: viewModel.activeTab, children: pages)
              : MainRouteOverlay(
                  route: viewModel.activeRoute,
                  data: data,
                  connectedData: _connectedData,
                  featureDependencies:
                      widget.pageDependencies.featureDependencies,
                  onBack: viewModel.closeOverlay,
                ),
        ),
        bottomNavigationBar: viewModel.activeRoute == RoutePage.tabs &&
                (viewModel.activeTab != 1 || viewModel.codingSessionListOpen)
            ? BottomNav(
                selected: viewModel.activeTab,
                items: mainTabItems(l10n),
                onTap: viewModel.selectTab)
            : null,
        extendBody: true,
      ),
    );
  }

  Widget _buildEmptyShell(BuildContext context, AppLocalizations l10n) {
    final initialData = widget.emptyInitialData;
    final health = initialData?.health;
    final pages = [
      _ConnectedEmptyHomePage(onCreateWorkspace: _showCreateWorkspace),
      _buildEmptyWorkspaceListPage(),
      _ConnectedEmptySettingsPage(
        health: health,
        connectionConfig: widget.connectionConfig,
        appUpdateViewModel: _appUpdateViewModel,
      ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Scaffold(
        body: MobileUiFrame(
          child: Stack(children: [
            IndexedStack(index: _emptyActiveTab, children: pages),
            if (_creatingWorkspace || _loadingWorkspace)
              Container(
                color: Colors.black.withValues(alpha: .24),
                alignment: Alignment.center,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111820),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .1)),
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
            if (_emptyError != null)
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
                      child: Text('$_emptyError',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: theme.red, fontSize: 11.5)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        bottomNavigationBar: BottomNav(
          selected: _emptyActiveTab,
          items: mainTabItems(l10n),
          onTap: (index) => setState(() => _emptyActiveTab = index),
        ),
        extendBody: true,
      ),
    );
  }

  Widget _buildEmptyWorkspaceListPage() => WorkspaceListPage(
        workspaces: _emptyWorkspaces,
        onSelected: (workspace) =>
            unawaited(_openWorkspace(workspace, _emptyWorkspaces)),
        onAddWorkspace: _showCreateWorkspace,
      );

  Future<void> _showCreateWorkspace() async {
    if (_creatingWorkspace) return;
    final request = await showModalBottomSheet<WorkspaceCreationRequest>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AddWorkspaceSheet(
              workspaceRepository: _connectedData.workspaceRepository,
            ));
    if (request == null || !mounted) return;
    setState(() {
      _creatingWorkspace = true;
      _emptyError = null;
    });
    final outcome = await CreateWorkspaceWorkflow(
      client: _connectedData.workspaceRepository,
      timeout: const Duration(seconds: 15),
    ).create(path: request.path, name: request.name);
    if (!mounted) return;
    switch (outcome) {
      case CreateWorkspaceSuccess(:final workspace, :final workspaces):
        await _openWorkspace(workspace, workspaces);
      case CreateWorkspaceNotConfirmed(:final workspaceId, :final workspaces):
        setState(() {
          _creatingWorkspace = false;
          _emptyWorkspaces = List<WorkspaceSummary>.unmodifiable(workspaces);
          _emptyError = StateError(
              'Workspace $workspaceId was created but not listed yet.');
        });
      case CreateWorkspaceFailure(:final error):
        setState(() {
          _creatingWorkspace = false;
          _emptyError = error;
        });
      case CreateWorkspaceTimeout():
        setState(() {
          _creatingWorkspace = false;
          _emptyError = TimeoutException('Workspace creation timed out.');
        });
    }
  }

  Future<void> _openWorkspace(
    WorkspaceSummary workspace,
    List<WorkspaceSummary> workspaces,
  ) async {
    final health = widget.emptyInitialData?.health;
    if (health == null) return;
    setState(() {
      _loadingWorkspace = true;
      _emptyError = null;
    });
    try {
      final snapshot = await widget.pageDependencies.loadWorkspaceBootstrap(
        health: health,
        workspaces: workspaces,
        workspace: workspace,
      );
      if (!mounted) return;
      setState(() {
        _creatingWorkspace = false;
        _loadingWorkspace = false;
        _viewModel = MainTabsViewModel(
          initialData: snapshot,
          adapterRepository: _connectedData.adapterRepository,
        );
      });
      unawaited(_loadCodingPreferences(_viewModel!));
      unawaited(_viewModel!.ensureCodingAdaptersLoaded());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creatingWorkspace = false;
        _loadingWorkspace = false;
        _emptyError = error;
      });
    }
  }

  Widget _buildCodingTab() {
    final viewModel = _viewModel;
    if (viewModel == null) return _buildEmptyWorkspaceListPage();
    if (viewModel.adapterLoadState == CodingAdapterLoadState.loaded) {
      return CodingPage(
        data: viewModel.data,
        workbenchDependencies: _workbenchDependencies,
        workbenchKey: _codingWorkbenchKey,
        onBack: () => viewModel.selectTab(0),
        onSessionListChanged: viewModel.reportSessionListOpen,
        openSessionListRequest: viewModel.openSessionListRequest,
        streamOutput: viewModel.streamOutput,
        expandThinking: viewModel.expandThinking,
        permissionMode: viewModel.permissionMode,
      );
    }
    return _CodingAdapterGate(
      failed: viewModel.adapterLoadState == CodingAdapterLoadState.failed,
      error: viewModel.adapterLoadError,
      onRetry: () => unawaited(viewModel.ensureCodingAdaptersLoaded()),
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
