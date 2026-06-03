import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_dependencies.dart';
import '../../app/connected_session_scope.dart';
import '../../domain/models/daemon_connection_config.dart';
import '../../domain/models/daemon_initial_data.dart';
import '../../models/protocol.dart';
import '../../services/approval_notification_handler.dart';
import '../../services/local_approval_notification_service.dart';
import '../../services/mobile_app_event_bus.dart';
import '../../workflows/workspace/create_workspace_workflow.dart';
import '../features/workspace_picker/workspace_picker.dart';
import '../features/settings/settings.dart'
    show
        AppUpdateCheckTrigger,
        AppUpdateStatus,
        AppUpdateViewModel,
        SettingsViewModel;
import '../features/workbench/workbench.dart';
import '../pages/pages.dart';
import 'coding_adapter_gate.dart';
import 'connected_main_shell.dart';
import 'main_shell_view_model.dart';

class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.initialData,
    required this.connectionConfig,
    required this.pageDependencies,
    this.forceAndroidForTesting,
  });

  const MainPage.fromInitialData({
    super.key,
    required this.initialData,
    required this.connectionConfig,
    required this.pageDependencies,
    this.forceAndroidForTesting,
  });

  final DaemonInitialData initialData;
  final DaemonConnectionConfig connectionConfig;
  final MainDependencies pageDependencies;
  final bool? forceAndroidForTesting;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  MainShellViewModel? _viewModel;
  HomeViewModel? _homeViewModel;
  SettingsViewModel? _settingsViewModel;
  late final MobileAppEventBus _mobileAppEventBus;
  late final ApprovalNotificationHandler _approvalNotificationHandler;
  StreamSubscription<ApprovalNotificationTap>?
      _approvalNotificationTapSubscription;
  late ConnectedDataDependencies _connectedData;
  late WorkbenchDependencies _workbenchDependencies;
  AppUpdateViewModel? _appUpdateViewModel;
  DaemonInitialData? _connectedInitialData;
  var _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();
  Object? _workspaceActionError;
  bool _creatingWorkspace = false;
  bool _loadingWorkspace = false;
  int _appUpdateGeneration = 0;

  ConnectedSessionRepositories get _repositories =>
      widget.pageDependencies.sessionScope.repositories;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mobileAppEventBus = MobileAppEventBus();
    _approvalNotificationHandler = ApprovalNotificationHandler(
      eventBus: _mobileAppEventBus,
      presenter: SystemApprovalNotificationPresenter(),
    );
    _approvalNotificationTapSubscription = _approvalNotificationHandler.taps
        .listen(_handleApprovalNotificationTap);
    _connectedData = widget.pageDependencies.connectedData;
    _workbenchDependencies = widget.pageDependencies.workbenchDependencies
        .copyWith(mobileAppEventBus: _mobileAppEventBus);
    widget.pageDependencies.codingPreferencesRepository.addListener(
      _handleCodingPreferencesRepositoryChanged,
    );
    _connectedInitialData = widget.initialData;
    _viewModel = MainShellViewModel();
    _createRepositoryBackedViewModels(widget.initialData);
    unawaited(_loadCodingPreferences(_viewModel!));
    _loadCodingAdapters();
    unawaited(_createAppUpdateViewModel());
  }

  @override
  void didUpdateWidget(covariant MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageDependencies != widget.pageDependencies) {
      if (oldWidget.pageDependencies.codingPreferencesRepository !=
          widget.pageDependencies.codingPreferencesRepository) {
        oldWidget.pageDependencies.codingPreferencesRepository.removeListener(
          _handleCodingPreferencesRepositoryChanged,
        );
        widget.pageDependencies.codingPreferencesRepository.addListener(
          _handleCodingPreferencesRepositoryChanged,
        );
      }
      final oldWorkbenchDependencies = _workbenchDependencies;
      _connectedData = widget.pageDependencies.connectedData;
      _workbenchDependencies = widget.pageDependencies.workbenchDependencies
          .copyWith(mobileAppEventBus: _mobileAppEventBus);
      _disposeAppUpdateViewModel();
      _disposeRepositoryBackedViewModels();
      unawaited(_createAppUpdateViewModel());
      _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();
      final initialData = widget.initialData;
      _workspaceActionError = null;
      _creatingWorkspace = false;
      _loadingWorkspace = false;
      _connectedInitialData = initialData;
      _viewModel?.dispose();
      _viewModel = MainShellViewModel();
      _createRepositoryBackedViewModels(initialData);
      unawaited(_loadCodingPreferences(_viewModel!));
      _loadCodingAdapters();
      _disposeWorkbenchDependenciesAfterBuild(oldWorkbenchDependencies);
      unawaited(oldWidget.pageDependencies.sessionScope.dispose());
      return;
    }
    if (oldWidget.initialData != widget.initialData) {
      _connectedInitialData = widget.initialData;
      final shellWasMissing = _viewModel == null;
      _viewModel ??= MainShellViewModel();
      if (_homeViewModel == null || _settingsViewModel == null) {
        _createRepositoryBackedViewModels(widget.initialData);
      } else {
        _updateHomeViewModelInputs(widget.initialData);
        _updateSettingsViewModelInputs(widget.initialData);
      }
      if (shellWasMissing) {
        unawaited(_loadCodingPreferences(_viewModel!));
        _loadCodingAdapters();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.pageDependencies.codingPreferencesRepository.removeListener(
      _handleCodingPreferencesRepositoryChanged,
    );
    unawaited(_approvalNotificationTapSubscription?.cancel());
    unawaited(_approvalNotificationHandler.dispose());
    unawaited(_mobileAppEventBus.dispose());
    _disposeWorkbenchDependencies(_workbenchDependencies);
    _disposeRepositoryBackedViewModels();
    _disposeAppUpdateViewModel();
    unawaited(widget.pageDependencies.sessionScope.dispose());
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _approvalNotificationHandler.updateLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppUpdateForeground(AppUpdateCheckTrigger.appResumed));
      return;
    }
    final viewModel = _appUpdateViewModel;
    if (viewModel != null) {
      unawaited(viewModel.handleAppLifecycleStateChanged(state));
    }
  }

  void _handleApprovalNotificationTap(ApprovalNotificationTap tap) {
    final viewModel = _viewModel;
    if (viewModel == null) return;
    viewModel.selectTab(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _codingWorkbenchKey.currentState?.openConversationFromNotification(
              workspaceId: tap.workspaceId,
              conversationId: tap.conversationId,
            ) ??
            Future<bool>.value(false),
      );
    });
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
    _repositories.recordDiagnosticEvent(
      'update.silent_check.skipped',
      {
        'trigger': trigger.diagnosticName,
        'reason': reason,
      },
      path: 'app_update',
    );
  }

  Future<void> _loadCodingPreferences(MainShellViewModel viewModel) async {
    try {
      final repository = widget.pageDependencies.codingPreferencesRepository;
      await repository.load();
      if (!mounted || _viewModel != viewModel) {
        return;
      }
      viewModel.setPermissionMode(repository.permissionMode);
      viewModel.setExpandToolDetails(repository.expandToolDetails);
    } catch (error) {
      if (!mounted) return;
      _repositories.recordDiagnosticEvent(
        'settings.permission_mode.load_failed',
        {'error': '$error'},
        path: 'settings',
      );
    }
  }

  void _loadCodingAdapters() {
    unawaited(_probeCodingAdapters());
  }

  Future<void> _probeCodingAdapters() async {
    try {
      await _repositories.cliAdapterRepository.probe();
    } catch (error) {
      if (!mounted) return;
      _repositories.recordDiagnosticEvent(
        'coding.adapters.load_failed',
        {'error': '$error'},
        path: 'coding',
      );
    }
  }

  void _retryCodingAdapters() {
    unawaited(
      _probeCodingAdapters(),
    );
  }

  void _handleCodingPreferencesRepositoryChanged() {
    final permissionMode =
        widget.pageDependencies.normalizeCodingPermissionMode(
      widget.pageDependencies.codingPreferencesRepository.permissionMode,
    );
    _viewModel?.setPermissionMode(permissionMode);
    _viewModel?.setExpandToolDetails(
      widget.pageDependencies.codingPreferencesRepository.expandToolDetails,
    );
  }

  void _createRepositoryBackedViewModels(DaemonInitialData data) {
    _disposeRepositoryBackedViewModels();
    final homeViewModel =
        widget.pageDependencies.featureDependencies.createHomeViewModel(
      _connectedData,
      signalMetrics: const HomeWorkspaceSignalMetrics(),
    );
    _homeViewModel = homeViewModel;
    _settingsViewModel =
        widget.pageDependencies.featureDependencies.createSettingsViewModel(
      connectedData: _connectedData,
      connectionConfig: widget.connectionConfig,
      health: data.health,
      activeConversationProvider: () =>
          _codingWorkbenchKey.currentState?.activeConversation,
    );
  }

  void _updateHomeViewModelInputs(DaemonInitialData data) {
    _homeViewModel?.updateSignalMetrics(const HomeWorkspaceSignalMetrics());
  }

  void _updateSettingsViewModelInputs(DaemonInitialData data) {
    _settingsViewModel?.updateShellInputs(
      connectionConfig: widget.connectionConfig,
      health: data.health,
    );
  }

  void _disposeRepositoryBackedViewModels() {
    _homeViewModel?.dispose();
    _homeViewModel = null;
    _settingsViewModel?.dispose();
    _settingsViewModel = null;
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
    if (viewModel == null) return;
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
    final viewModel = _viewModel;
    final initialData = _connectedInitialData;
    final homeViewModel = _homeViewModel;
    final settingsViewModel = _settingsViewModel;
    if (viewModel == null ||
        initialData == null ||
        homeViewModel == null ||
        settingsViewModel == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ConnectedMainShell(
      viewModel: viewModel,
      initialData: initialData,
      homeViewModel: homeViewModel,
      settingsViewModel: settingsViewModel,
      appUpdateViewModel: _appUpdateViewModel,
      connectedData: _connectedData,
      repositories: _repositories,
      featureDependencies: widget.pageDependencies.featureDependencies,
      codingTab: _buildCodingTab(),
      creatingWorkspace: _creatingWorkspace,
      loadingWorkspace: _loadingWorkspace,
      workspaceActionError: _workspaceActionError,
      onCreateWorkspace: _showCreateWorkspace,
      onOpenWorkspace: (workspace) => unawaited(
        _openWorkspace(workspace, _repositories.workspaceRepository.workspaces),
      ),
      onSystemBack: () => unawaited(_handleSystemBack()),
    );
  }

  Future<void> _showCreateWorkspace() async {
    if (_creatingWorkspace) return;
    final request = await showModalBottomSheet<WorkspaceCreationRequest>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AddWorkspaceSheet(
              workspaceRepository: _repositories.workspaceRepository,
            ));
    if (request == null || !mounted) return;
    setState(() {
      _creatingWorkspace = true;
      _workspaceActionError = null;
    });
    final outcome = await CreateWorkspaceWorkflow(
      client: _repositories.workspaceRepository,
      timeout: const Duration(seconds: 15),
    ).create(path: request.path, name: request.name);
    if (!mounted) return;
    switch (outcome) {
      case CreateWorkspaceSuccess(:final workspace, :final workspaces):
        await _openWorkspace(workspace, workspaces);
      case CreateWorkspaceNotConfirmed(:final workspaceId):
        setState(() {
          _creatingWorkspace = false;
          _workspaceActionError = StateError(
              'Workspace $workspaceId was created but not listed yet.');
        });
      case CreateWorkspaceFailure(:final error):
        setState(() {
          _creatingWorkspace = false;
          _workspaceActionError = error;
        });
      case CreateWorkspaceTimeout():
        setState(() {
          _creatingWorkspace = false;
          _workspaceActionError =
              TimeoutException('Workspace creation timed out.');
        });
    }
  }

  Future<void> _openWorkspace(
    WorkspaceSummary workspace,
    List<WorkspaceSummary> workspaces,
  ) async {
    setState(() {
      _loadingWorkspace = true;
      _workspaceActionError = null;
    });
    try {
      final initialData = await widget
          .pageDependencies.sessionScope.useCases.openWorkspace
          .open(
        workspaces: workspaces,
        workspace: workspace,
      );
      if (!mounted) return;
      final openedWorkspace = initialData.workspace;
      if (openedWorkspace?.id != workspace.id) {
        setState(() {
          _creatingWorkspace = false;
          _loadingWorkspace = false;
          _connectedInitialData = initialData;
          _workspaceActionError = _workspaceOpenConfirmationError(
            requested: workspace,
            opened: openedWorkspace,
          );
          _updateHomeViewModelInputs(initialData);
          _updateSettingsViewModelInputs(initialData);
        });
        return;
      }
      setState(() {
        _creatingWorkspace = false;
        _loadingWorkspace = false;
        _connectedInitialData = initialData;
        _viewModel ??= MainShellViewModel();
        if (_homeViewModel == null || _settingsViewModel == null) {
          _createRepositoryBackedViewModels(initialData);
        } else {
          _updateHomeViewModelInputs(initialData);
          _updateSettingsViewModelInputs(initialData);
        }
      });
      if (_viewModel != null) {
        unawaited(_loadCodingPreferences(_viewModel!));
        _loadCodingAdapters();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creatingWorkspace = false;
        _loadingWorkspace = false;
        _workspaceActionError = error;
      });
    }
  }

  StateError _workspaceOpenConfirmationError({
    required WorkspaceSummary requested,
    required WorkspaceSummary? opened,
  }) {
    final openedId = opened?.id;
    if (openedId == null) {
      return StateError(
          'Workspace ${requested.name} was not confirmed by the daemon.');
    }
    return StateError(
      'Workspace ${requested.name} was not opened; daemon selected $openedId.',
    );
  }

  Widget _buildCodingTab() {
    final viewModel = _viewModel;
    if (viewModel == null) return const SizedBox.shrink();
    // TODO(arch): Remove direct repository access when CodingGateViewModel
    // owns coding gate state. Tracked by migration Slice 4.
    return ListenableBuilder(
      listenable: _repositories.cliAdapterRepository,
      builder: (context, _) => _buildCodingTabContent(viewModel),
    );
  }

  Widget _buildCodingTabContent(MainShellViewModel viewModel) {
    final adapterRepo = _repositories.cliAdapterRepository;
    if (adapterRepo.loading || adapterRepo.error != null) {
      return CodingAdapterGate(
        failed: adapterRepo.error != null,
        error: adapterRepo.error,
        onRetry: _retryCodingAdapters,
      );
    }
    return CodingPage(
      workbenchDependencies: _workbenchDependencies,
      workbenchKey: _codingWorkbenchKey,
      onBack: () => viewModel.selectTab(0),
      onSessionListChanged: viewModel.reportSessionListOpen,
      openSessionListRequest: viewModel.openSessionListRequest,
      streamOutput: viewModel.streamOutput,
      expandThinking: viewModel.expandThinking,
      expandToolDetails: viewModel.expandToolDetails,
      permissionMode: viewModel.permissionMode,
    );
  }
}
