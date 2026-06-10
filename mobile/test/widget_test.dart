import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/lan_ai_cli_control.dart';
import 'package:lan_ai_cli_control/l10n/app_localizations.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/app/language_controller.dart';
import 'package:lan_ai_cli_control/src/app/language_mode.dart';
import 'package:lan_ai_cli_control/src/app/language_scope.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/coding_preferences_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_workspace_repository.dart';
import 'package:lan_ai_cli_control/src/data/models/approval_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/slash_command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart'
    as data_repositories;
import 'package:lan_ai_cli_control/src/domain/models/approval_response.dart';
import 'package:lan_ai_cli_control/src/domain/models/connected_app_session.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_initial_data.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/recent_daemon_address_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/domain/use_cases/connect_to_daemon_use_case.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/services/android_package_installer.dart';
import 'package:lan_ai_cli_control/src/services/app_update_download_manager.dart';
import 'package:lan_ai_cli_control/src/services/asr_model_manager.dart';
import 'package:lan_ai_cli_control/src/services/coding_preferences_store.dart';
import 'package:lan_ai_cli_control/src/ui/features/diagnostics/diagnostics.dart';
import 'package:lan_ai_cli_control/src/ui/features/run_detail/run_detail.dart';
import 'package:lan_ai_cli_control/src/ui/features/sessions/sessions.dart'
    hide mergeSessionItems;
import 'package:lan_ai_cli_control/src/ui/features/settings/settings.dart'
    as settings_feature;
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/settings_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/widgets/app_update_panel.dart';
import 'package:lan_ai_cli_control/src/workflows/app_update_workflow.dart';
import 'package:lan_ai_cli_control/src/testing/testing.dart';
import 'package:lan_ai_cli_control/src/ui/features/workspace_picker/workspace_picker.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/features/connection/view_models/daemon_connection_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/core/widgets/widgets.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/draft_attachment.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/messages/approval_event_card.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/daemon_connection_controller.dart';

void _noopString(String _) {}

void _noopApproval(ApprovalResponse _) {}

WorkbenchMessage _runningCommandMessage({
  required int seq,
  required String body,
}) =>
    WorkbenchMessage('command', 'Run command', body,
        event: AgentEvent(
            type: 'tool.started',
            seq: seq,
            runId: 'run_sweep',
            createdAt: DateTime.parse('2026-05-03T00:00:0$seq.000Z'),
            name: 'Bash',
            raw: <String, Object?>{
              'toolName': 'Bash',
              'input': <String, Object?>{'command': body},
            }),
        runId: 'run_sweep');

class _WorkbenchMessageListHarness extends StatefulWidget {
  const _WorkbenchMessageListHarness({
    required this.messages,
  });

  final List<WorkbenchMessage> messages;

  @override
  State<_WorkbenchMessageListHarness> createState() =>
      _WorkbenchMessageListHarnessState();
}

class _WorkbenchMessageListHarnessState
    extends State<_WorkbenchMessageListHarness> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
      locale: theme.zhHansCnLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: theme.appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: theme.bg,
          body: SizedBox(
              width: 420,
              height: 260,
              child: WorkbenchMessageList(
                  controller: _controller,
                  messages: widget.messages,
                  adapter: 'codex-app-server',
                  runId: 'run_sweep',
                  eventCount: widget.messages.length,
                  terminal: false,
                  runError: null,
                  runErrorTraceId: null,
                  pendingStatusText: '',
                  pendingStartedAt: null,
                  pendingActions: const <String>[],
                  expandThinking: false,
                  expandToolDetails: false,
                  useReverseTranscript: false,
                  loadingOlderConversationEvents: false,
                  showPendingDuringInitialConversationLoad: false,
                  showStatus: false,
                  showError: false,
                  showPending: false,
                  onApproval: (_, __) async {},
                  onSuggestion: _noopString,
                  onScrollNotification: (_) => false))));
}

Widget _approvalComposerHarness({
  required ApprovalRequestOptions approvalOptions,
  required ValueChanged<ApprovalResponse> onApproval,
  String approvalId = 'approval_prompt_1',
}) {
  final event = AgentEvent(
    type: 'approval.requested',
    seq: 1,
    runId: 'run_approval_prompt',
    createdAt: DateTime.parse('2026-05-16T00:00:01.000Z'),
    approvalId: approvalId,
    name: 'Bash',
    raw: <String, Object?>{
      'toolName': 'Bash',
      'approvalOptions': <String, Object?>{
        'kind': approvalOptions.kind == ApprovalRequestKind.fileChange
            ? 'file_change'
            : approvalOptions.kind.name,
        'supportsSessionScope': approvalOptions.supportsSessionScope,
        'supportsCancel': approvalOptions.supportsCancel,
        'denyBehavior':
            approvalOptions.denyBehavior == ApprovalDenyBehavior.continueTurn
                ? 'continue'
                : 'interrupt',
        if (approvalOptions.command != null) 'command': approvalOptions.command,
      },
    },
  );
  return MaterialApp(
    locale: const Locale('en', 'US'),
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    theme: theme.buildAppTheme(),
    home: Scaffold(
      backgroundColor: theme.bg,
      body: ApprovalComposerPrompt(
        message: WorkbenchMessage(
          'approval',
          'Needs approval',
          'npm test',
          event: event,
          approvalOptions: approvalOptions,
        ),
        onApproval: onApproval,
      ),
    ),
  );
}

Future<void> _pumpNavigationFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void _setMockPackageInfo() {
  PackageInfo.setMockInitialValues(
    appName: 'LAN AI CLI Control',
    packageName: 'com.example.lan_ai_cli_control',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
}

class _LocalizedSettingsLabelApp extends StatefulWidget {
  const _LocalizedSettingsLabelApp();

  @override
  State<_LocalizedSettingsLabelApp> createState() =>
      _LocalizedSettingsLabelAppState();
}

class _LocalizedSettingsLabelAppState
    extends State<_LocalizedSettingsLabelApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Builder(
                  builder: (context) =>
                      Text(AppLocalizations.of(context).navSettings)))));
}

class _LocalizedSettingsPageApp extends StatefulWidget {
  const _LocalizedSettingsPageApp({this.appUpdateViewModel});

  final AppUpdateViewModel? appUpdateViewModel;

  @override
  State<_LocalizedSettingsPageApp> createState() =>
      _LocalizedSettingsPageAppState();
}

class _LocalizedSettingsPageAppState extends State<_LocalizedSettingsPageApp> {
  late final LanguageController _languageController;
  late final SettingsViewModel _settingsViewModel;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
    final snapshot = _testSnapshot();
    _settingsViewModel = SettingsViewModel(
      workspaceRepository: _SnapshotWorkspaceRepository(snapshot),
      codingPreferencesRepository:
          _WidgetCodingPreferencesRepository(permissionMode: 'default'),
      connectionConfig: const DaemonConnectionConfig(
          addressInput: '192.168.1.20:4317',
          proxyMode: DaemonProxyMode.manual,
          manualProxyInput: 'http://proxy.local:8080'),
      health: snapshot.health,
      diagnostics: snapshot.diagnostics,
      gitStatus: snapshot.gitStatus,
      extensionsCount: snapshot.extensions.length,
    );
  }

  @override
  void dispose() {
    _settingsViewModel.dispose();
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Scaffold(
                  body: settings_feature.SettingsPage(
                      open: (_) {},
                      viewModel: _settingsViewModel,
                      streamOutput: false,
                      expandThinking: false,
                      appUpdateViewModel: widget.appUpdateViewModel,
                      onStreamOutputChanged: (_) {},
                      onExpandThinkingChanged: (_) {})))));
}

class _LocalizedHomePageApp extends StatefulWidget {
  const _LocalizedHomePageApp({this.snapshot});

  final AppSnapshot? snapshot;

  @override
  State<_LocalizedHomePageApp> createState() => _LocalizedHomePageAppState();
}

class _LocalizedHomePageAppState extends State<_LocalizedHomePageApp> {
  late final LanguageController _languageController;
  late HomeViewModel _homeViewModel;
  late AppSnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
    _snapshot = widget.snapshot ?? _testSnapshot();
    _homeViewModel = _homeViewModelForSnapshot(_snapshot);
  }

  @override
  void didUpdateWidget(covariant _LocalizedHomePageApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _homeViewModel.dispose();
      _snapshot = widget.snapshot ?? _testSnapshot();
      _homeViewModel = _homeViewModelForSnapshot(_snapshot);
    }
  }

  @override
  void dispose() {
    _homeViewModel.dispose();
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Scaffold(
                  body: HomePage(
                      open: (_) {},
                      selectTab: (_) {},
                      viewModel: _homeViewModel,
                      health: _snapshot.health,
                      onCreateWorkspace: () {},
                      onOpenWorkspace: (_) {})))));
}

class _MainHarness extends StatefulWidget {
  const _MainHarness({
    required this.client,
    this.dependencies,
    this.snapshot,
    this.forceAndroidForTesting,
  });

  final DaemonClient client;
  final AppDependencies? dependencies;
  final AppSnapshot? snapshot;
  final bool? forceAndroidForTesting;

  @override
  State<_MainHarness> createState() => _MainHarnessState();
}

class _MainHarnessState extends State<_MainHarness> {
  late final LanguageController _languageController;
  late AppDependencies _dependencies;
  late MainDependencies _pageDependencies;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
    _dependencies = widget.dependencies ?? AppDependencies.createDefault();
    _pageDependencies = _dependencies.createMainDependencies(
      widget.client,
      initialData: (widget.snapshot ?? _testSnapshot()).toDaemonInitialData(),
    );
  }

  @override
  void didUpdateWidget(covariant _MainHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.dependencies != widget.dependencies ||
        oldWidget.snapshot != widget.snapshot) {
      _dependencies = widget.dependencies ?? AppDependencies.createDefault();
      _pageDependencies = _dependencies.createMainDependencies(
        widget.client,
        initialData: (widget.snapshot ?? _testSnapshot()).toDaemonInitialData(),
      );
    }
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              theme: theme.buildAppTheme(),
              home: MainPage(
                  initialData: (widget.snapshot ?? _testSnapshot())
                      .toDaemonInitialData(),
                  connectionConfig: const DaemonConnectionConfig(
                      addressInput: '127.0.0.1:4317',
                      proxyMode: DaemonProxyMode.system,
                      manualProxyInput: ''),
                  forceAndroidForTesting: widget.forceAndroidForTesting,
                  pageDependencies: _pageDependencies))));
}

class _MobileConnectionHarness extends StatefulWidget {
  const _MobileConnectionHarness({required this.controller, this.dependencies});

  final DaemonConnectionViewModel controller;
  final AppDependencies? dependencies;

  @override
  State<_MobileConnectionHarness> createState() =>
      _MobileConnectionHarnessState();
}

class _MobileConnectionHarnessState extends State<_MobileConnectionHarness> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              theme: theme.buildAppTheme(),
              home: MobileUi(
                connectionController: widget.controller,
                dependencies: widget.dependencies,
              ))));
}

FeatureDependencies _testFeatureDependencies({
  required DaemonConnectionViewModel Function() createDaemonConnectionViewModel,
  HomeViewModel Function(
    ConnectedDataDependencies connectedData, {
    HomeWorkspaceSignalMetrics? signalMetrics,
  })? createHomeViewModel,
  SettingsViewModel Function({
    required ConnectedDataDependencies connectedData,
    required DaemonConnectionConfig connectionConfig,
    required DaemonHealth health,
    ActiveConversationProvider? activeConversationProvider,
    CodeDiagnosticsSummary? diagnostics,
    GitStatusSummary? gitStatus,
    int extensionsCount,
  })? createSettingsViewModel,
  required DiagnosticsViewModel Function(
    ConnectedDataDependencies connectedData,
  ) createDiagnosticsViewModel,
  required RunDetailViewModel Function(
    ConnectedDataDependencies connectedData,
    RunSummary run,
  ) createRunDetailViewModel,
  required Future<AppUpdateViewModel> Function({
    required DaemonClient client,
    required ConnectedDataDependencies connectedData,
    required int installedVersionCode,
    required String installedVersionName,
  }) createAppUpdateViewModel,
  required WorkbenchDependencies Function(
    DaemonClient client,
    ConnectedDataDependencies connectedData,
  ) createWorkbenchDependencies,
}) =>
    FeatureDependencies(
      createDaemonConnectionViewModel: createDaemonConnectionViewModel,
      createHomeViewModel:
          createHomeViewModel ?? _defaultTestHomeViewModelFactory,
      createSettingsViewModel:
          createSettingsViewModel ?? _defaultTestSettingsViewModelFactory,
      createDiagnosticsViewModel: createDiagnosticsViewModel,
      createRunDetailViewModel: createRunDetailViewModel,
      createAppUpdateViewModel: createAppUpdateViewModel,
      createWorkbenchDependencies: createWorkbenchDependencies,
    );

HomeViewModel _defaultTestHomeViewModelFactory(
  ConnectedDataDependencies connectedData, {
  HomeWorkspaceSignalMetrics? signalMetrics,
}) =>
    HomeViewModel(
      workspaceRepository: connectedData.workspaceRepository,
      conversationRepository: connectedData.conversationRepository,
      runRepository: connectedData.runRepository,
      signalMetrics: signalMetrics ?? const HomeWorkspaceSignalMetrics(),
    );

SettingsViewModel _defaultTestSettingsViewModelFactory({
  required ConnectedDataDependencies connectedData,
  required DaemonConnectionConfig connectionConfig,
  required DaemonHealth health,
  ActiveConversationProvider? activeConversationProvider,
  CodeDiagnosticsSummary? diagnostics,
  GitStatusSummary? gitStatus,
  int extensionsCount = 0,
}) =>
    SettingsViewModel(
      workspaceRepository: connectedData.workspaceRepository,
      codingPreferencesRepository: CodingPreferencesRepository(),
      conversationRepository: connectedData.conversationRepository,
      activeConversationProvider: activeConversationProvider,
      connectionConfig: connectionConfig,
      health: health,
      diagnostics: diagnostics,
      gitStatus: gitStatus,
      extensionsCount: extensionsCount,
    );

class _AdapterRefreshClient extends DaemonClient {
  _AdapterRefreshClient({
    this.adapters = const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
      AdapterStatus(
          adapter: 'synthetic-jsonl',
          available: true,
          status: 'available',
          version: 'synthetic'),
      AdapterStatus(
          adapter: 'synthetic-text',
          available: true,
          status: 'available',
          version: 'synthetic')
    ],
    List<ConversationSummary>? conversations,
  }) : super(
            baseUri: Uri.parse('http://127.0.0.1:4317'),
            tokenStore: MemoryTokenStore()) {
    this.conversations = conversations ??
        <ConversationSummary>[
          _conversationSummary(
            id: 'conv_lazy',
            workspaceId: 'workspace_1',
            status: 'completed',
            sessionBinding: 'confirmed',
            userMessageCount: 500,
          ),
        ];
  }

  int listAdaptersCalls = 0;
  final List<AdapterStatus> adapters;
  late final List<ConversationSummary> conversations;

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    listAdaptersCalls++;
    return adapters;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      const <WorkspaceSummary>[
        WorkspaceSummary(
          id: 'workspace_1',
          name: 'Current Project',
          path: r'D:\AiProject\vibe-coding',
        ),
      ];

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) async =>
      const <RunSummary>[];

  @override
  Future<List<QueueItem>> listQueue() async => const <QueueItem>[];

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      List<ConversationSummary>.of(conversations);
}

class _NoBootstrapRefreshClient extends _AdapterRefreshClient {
  int listWorkspacesCalls = 0;
  int listConversationsCalls = 0;
  int listRunsCalls = 0;
  int listQueueCalls = 0;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    listWorkspacesCalls++;
    return const <WorkspaceSummary>[];
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    listConversationsCalls++;
    return const <ConversationSummary>[];
  }

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) async {
    listRunsCalls++;
    return const <RunSummary>[];
  }

  @override
  Future<List<QueueItem>> listQueue() async {
    listQueueCalls++;
    return const <QueueItem>[];
  }
}

class _WorkspaceSelectionClient extends _AdapterRefreshClient {
  _WorkspaceSelectionClient({required this.workspaceCatalog});

  final List<WorkspaceSummary> workspaceCatalog;
  final List<String> codexJsonPaths = <String>[];

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => workspaceCatalog;

  @override
  Future<List<RunSummary>> listRuns(
          {String? tool, String? workspaceId, String? status}) async =>
      const <RunSummary>[];

  @override
  Future<List<QueueItem>> listQueue() async => const <QueueItem>[];

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<Map<String, Object?>> getAuthorizedJson(String path) async {
    codexJsonPaths.add(path);
    if (path == '/api/codex-app-server/capabilities') {
      return const <String, Object?>{
        'routes': <Map<String, Object?>>[],
        'totalMethods': 0,
      };
    }
    if (path.startsWith('/api/codex-app-server/workspaces/') &&
        path.endsWith('/threads?limit=50')) {
      return const <String, Object?>{
        'threads': <Map<String, Object?>>[],
      };
    }
    if (path.startsWith('/api/codex-app-server/')) {
      return const <String, Object?>{};
    }
    throw StateError('Unexpected Codex app-server path: $path');
  }
}

class _WorkspaceCreationClient extends _WorkspaceSelectionClient {
  _WorkspaceCreationClient({
    required List<WorkspaceSummary> initialWorkspaces,
    required this.createdWorkspace,
  }) : super(workspaceCatalog: List<WorkspaceSummary>.of(initialWorkspaces));

  final WorkspaceSummary createdWorkspace;
  int createWorkspaceCalls = 0;

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async {
    createWorkspaceCalls++;
    final created = WorkspaceSummary(
      id: createdWorkspace.id,
      name: name ?? createdWorkspace.name,
      path: path,
    );
    workspaceCatalog
      ..removeWhere((workspace) => workspace.id == created.id)
      ..add(created);
    return created;
  }
}

class _WorkspaceBootstrapFailureClient extends _AdapterRefreshClient {
  @override
  Future<List<RunSummary>> listRuns(
          {String? tool, String? workspaceId, String? status}) async =>
      throw StateError('list runs unavailable');
}

class _ImmediateConnectUseCase implements ConnectToDaemonUseCase<DaemonClient> {
  const _ImmediateConnectUseCase(this.session);

  final ConnectedAppSession<DaemonClient> session;

  @override
  Future<ConnectedAppSession<DaemonClient>> connect({
    required String addressInput,
    required DaemonProxyMode proxyMode,
    required String manualProxyInput,
    bool Function()? shouldContinue,
    void Function()? onCheckingHealth,
    void Function()? onLoadingInitialData,
  }) async {
    onCheckingHealth?.call();
    onLoadingInitialData?.call();
    return session;
  }
}

class _PendingAdapterClient extends _AdapterRefreshClient {
  bool completeCatalogWithError = false;
  Completer<List<AdapterStatus>> adaptersCompleter =
      Completer<List<AdapterStatus>>();

  @override
  Future<List<AdapterStatus>> listAdapters() {
    listAdaptersCalls++;
    return adaptersCompleter.future;
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    if (completeCatalogWithError) {
      throw StateError('extensions failed');
    }
    return const <ExtensionSummary>[];
  }

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  void completeWithAdapters() {
    adaptersCompleter.complete(const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ]);
  }

  void completeWithError() {
    adaptersCompleter.completeError(Exception('adapter probe failed'));
  }

  void resetCompleter() {
    adaptersCompleter = Completer<List<AdapterStatus>>();
  }
}

AppUpdateManifest _widgetAppUpdateManifest() => AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: true,
      packageName: 'com.example.lan_ai_cli_control',
      versionName: '1.1.0',
      versionCode: 2,
      minSupportedVersionCode: 1,
      mandatory: false,
      apkUrl: '/api/app-updates/android/apk/2',
      sha256: 'a' * 64,
      sizeBytes: 10,
      etag: '"etag-2"',
      publishedAt: DateTime.utc(2026, 5, 24),
    );

class _WidgetAppUpdateRepository implements AppUpdateRepository {
  _WidgetAppUpdateRepository({required this.manifest});

  final AppUpdateManifest manifest;
  int fetchLatestCalls = 0;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async {
    fetchLatestCalls += 1;
    return manifest;
  }
}

class _WidgetRecentAddressRepository implements RecentDaemonAddressRepository {
  _WidgetRecentAddressRepository(this.addresses);

  final List<String> addresses;
  final recordedAddresses = <String>[];

  @override
  Future<List<String>> loadRecentAddresses() async =>
      List<String>.unmodifiable(addresses);

  @override
  Future<void> recordSuccessfulAddress(String addressInput) async {
    recordedAddresses.add(addressInput);
    addresses
      ..removeWhere(
        (address) => address.toLowerCase() == addressInput.toLowerCase(),
      )
      ..insert(0, addressInput);
  }
}

class _WidgetAppUpdateInstaller implements PackageInstallerService {
  _WidgetAppUpdateInstaller({this.recoveredEvent, this.returnNullRecoveryOnce});

  final AndroidInstallEvent? recoveredEvent;
  final bool? returnNullRecoveryOnce;
  final _events = StreamController<AndroidInstallEvent>.broadcast();
  int recoverCalls = 0;
  int installCalls = 0;
  String? installedPath;

  void close() {
    unawaited(_events.close());
  }

  @override
  Stream<AndroidInstallEvent> get events => _events.stream;

  @override
  Future<int> availableBytes() async => 1000000;

  @override
  Future<bool> canRequestPackageInstalls() async => true;

  @override
  Future<int> installApk(String filePath) async {
    installCalls += 1;
    installedPath = filePath;
    return 22;
  }

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId) async {
    recoverCalls += 1;
    if (returnNullRecoveryOnce == true && recoverCalls == 1) {
      return null;
    }
    return recoveredEvent;
  }
}

class _WidgetAppUpdateDownloader implements AppUpdateDownloader {
  _WidgetAppUpdateDownloader({
    this.result = const AppUpdateDownloadResult(
      state: AppUpdateDownloadState.failed,
    ),
  });

  AppUpdateDownloadResult result;
  AppUpdateInstallSessionRecord? installSession;
  int readSessionCalls = 0;

  @override
  Future<void> clearInstallSession(
    AppUpdateManifest manifest, {
    int? sessionId,
  }) async {}

  @override
  Future<void> clearAllInstallSessions() async {}

  @override
  Future<void> discard(int versionCode) async {}

  @override
  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri, {
    AppUpdateDownloadProgressCallback? onProgress,
  }) async =>
      result;

  @override
  Future<File?> readDownloadedUpdate(AppUpdateManifest manifest) async => null;

  @override
  Future<AppUpdateInstallSessionRecord?> readInstallSession(
    AppUpdateManifest manifest,
  ) async {
    readSessionCalls += 1;
    return installSession;
  }

  @override
  Future<void> recordInstallSession(
    AppUpdateManifest manifest,
    int sessionId,
  ) async {}
}

Finder _workbenchMessageList() => find.byWidgetPredicate(
      (widget) =>
          widget is ListView &&
          widget.key is ValueKey<String> &&
          ((widget.key as ValueKey<String>).value ==
                  'workbench-message-list-normal' ||
              (widget.key as ValueKey<String>).value ==
                  'workbench-message-list-reverse'),
    );

const _slashCommandWorkspace = WorkspaceSummary(
  id: 'workspace_1',
  name: 'Current Project',
  path: r'D:\AiProject\vibe-coding',
);

SlashCommandCatalogRepository _slashCommandCatalogRepository(
  Map<String, List<SlashCommand>> commandsByAdapter,
) =>
    SlashCommandCatalogRepository(
      client: (adapter, {workspaceId}) async =>
          commandsByAdapter[adapter.trim().toLowerCase()] ??
          const <SlashCommand>[],
    );

class _RecordingSlashCommandCatalogRepository
    extends SlashCommandCatalogRepository {
  _RecordingSlashCommandCatalogRepository(this.commandsByAdapter)
      : super(
          client: (adapter, {workspaceId}) async =>
              commandsByAdapter[adapter.trim().toLowerCase()] ??
              const <SlashCommand>[],
        );

  final Map<String, List<SlashCommand>> commandsByAdapter;
  final List<String> loadCalls = <String>[];

  @override
  Future<List<SlashCommand>> loadForAdapter(
    String adapterId, {
    String? workspaceId,
    bool force = false,
  }) {
    loadCalls.add(adapterId.trim().toLowerCase());
    return super.loadForAdapter(
      adapterId,
      workspaceId: workspaceId,
      force: force,
    );
  }
}

Future<void> _pumpWorkbenchForSlashCommands(
  WidgetTester tester,
  SlashCommandCatalogRepository catalog, {
  List<AdapterStatus> adapters = const <AdapterStatus>[
    AdapterStatus(adapter: 'codex', available: true, status: 'available'),
  ],
}) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'en-US'});
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenStore: MemoryTokenStore(),
  );
  final adapterRepository = CliAdapterRepository(
    delegate: DaemonAdapterRepository(client: client),
  )..replaceFromBootstrap(adapters);
  final conversationRepository = CachedConversationRepository(
      delegate: _NewSessionConversationRepository())
    ..replaceFromBootstrap(
      workspaceId: _slashCommandWorkspace.id,
      conversations: const <ConversationSummary>[],
    );
  final runRepository =
      CachedRunRepository(delegate: DaemonRunRepository(client: client))
        ..replaceFromBootstrap(
          workspaceId: _slashCommandWorkspace.id,
          runs: const <RunSummary>[],
          queue: const <QueueItem>[],
        );
  final workspaceRepository = DaemonWorkspaceRepository(client: client)
    ..applyBootstrapCatalog(
      selectedWorkspace: _slashCommandWorkspace,
      workspaces: const <WorkspaceSummary>[_slashCommandWorkspace],
    );

  await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
          body: CodingWorkbenchPage(
              onBack: () {},
              onSessionListChanged: (_) {},
              openSessionListRequest: 0,
              streamOutput: false,
              expandThinking: false,
              permissionMode: 'default',
              dependencies: WorkbenchDependencies(
                adapterRepository: adapterRepository,
                asrModelManager:
                    AsrModelManager(client: client.createAsrModelClient()),
                conversationRepository: conversationRepository,
                diagnosticsRepository:
                    DaemonDiagnosticsRepository(client: client),
                runRepository: runRepository,
                speechInputServiceBuilder: (_) =>
                    const DisabledSpeechInputService(),
                slashCommandCatalogRepository: catalog,
                workspaceRepository: workspaceRepository,
              )))));
  await tester.pumpAndSettle();
}

Future<void> _openNewSlashCommandConversation(WidgetTester tester) async {
  await tester.tap(find.text('Current Project'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('session-new-button')));
  await tester.pumpAndSettle();
}

Widget _pagedWorkbenchHarness({
  required ConversationRepository conversationRepository,
  required List<ConversationSummary> conversations,
}) {
  final dependencies = AppDependencies.createDefault();
  final client = _AdapterRefreshClient(conversations: conversations);
  final connectedData = dependencies.data.forDaemonClient(client);
  final workbenchDependencies =
      dependencies.features.createWorkbenchDependencies(client, connectedData);
  final cachedConversationRepository =
      _cachedConversationRepositoryForWorkbenchTest(
    delegate: conversationRepository,
    conversations: conversations,
  );
  final testDependencies = AppDependencies(
    network: dependencies.network,
    data: dependencies.data,
    domain: dependencies.domain,
    features: _testFeatureDependencies(
      createDaemonConnectionViewModel:
          dependencies.features.createDaemonConnectionViewModel,
      createDiagnosticsViewModel:
          dependencies.features.createDiagnosticsViewModel,
      createRunDetailViewModel: dependencies.features.createRunDetailViewModel,
      createAppUpdateViewModel: dependencies.features.createAppUpdateViewModel,
      createWorkbenchDependencies: (_, connectedData) => WorkbenchDependencies(
        adapterRepository: connectedData.cliAdapterRepository,
        asrModelManager: workbenchDependencies.asrModelManager,
        conversationRepository: cachedConversationRepository,
        diagnosticsRepository: connectedData.diagnosticsRepository,
        runRepository: connectedData.runRepository,
        speechInputServiceBuilder:
            workbenchDependencies.speechInputServiceBuilder,
        workspaceRepository: connectedData.workspaceRepository,
      ),
    ),
  );
  return _MainHarness(
    client: client,
    dependencies: testDependencies,
    snapshot: _testSnapshot(conversations: conversations),
  );
}

ConversationEvent _pagedConversationEvent({
  required int seq,
  required String text,
  String conversationId = 'conv_paged',
  String type = 'assistant.message',
}) =>
    ConversationEvent.fromJson(<String, Object?>{
      'seq': seq,
      'conversationId': conversationId,
      'type': type,
      'createdAt': '2026-05-30T00:00:00.000Z',
      'text': text,
    });

Widget _connectionPage(DaemonConnectionController controller) => MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      localeResolutionCallback: (locale, supportedLocales) =>
          resolveSupportedLocale(locale, supportedLocales),
      theme: theme.buildAppTheme(),
      home: MobileConnectionPage(controller: controller),
    );

class _LazyConversationRepository implements ConversationRepository {
  _LazyConversationRepository(this.messages);

  final List<ConversationEvent> messages;

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      messages;

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    final pageEvents = beforeSeq == null
        ? messages.length <= limit
            ? messages
            : messages.sublist(messages.length - limit)
        : messages
            .where((event) => event.seq < beforeSeq)
            .toList(growable: false);
    final limitedEvents = pageEvents.length <= limit
        ? pageEvents
        : pageEvents.sublist(pageEvents.length - limit);
    return ConversationEventPage(
      events: limitedEvents,
      oldestSeq: limitedEvents.isEmpty ? null : limitedEvents.first.seq,
      newestSeq: limitedEvents.isEmpty ? null : limitedEvents.last.seq,
      hasMoreBefore: limitedEvents.isNotEmpty && limitedEvents.length == limit,
    );
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      Stream<ConversationEvent>.fromIterable(messages);

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_lazy',
          workspaceId: 'workspace_1',
          status: 'completed',
          sessionBinding: 'confirmed',
          userMessageCount: messages.length,
        ),
      ];

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    ApprovalResponse response,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      _conversationSummary(
        id: conversationId,
        workspaceId: 'workspace_1',
        status: 'idle',
        model: model,
      );

  @override
  Future<ConversationSummary> updateConversationPermissionMode(
    String conversationId,
    String permissionMode,
  ) async =>
      _conversationSummary(
        id: conversationId,
        workspaceId: 'workspace_1',
        status: 'idle',
      );
}

CachedConversationRepository _cachedConversationRepositoryForWorkbenchTest({
  required ConversationRepository delegate,
  required List<ConversationSummary> conversations,
  String workspaceId = 'workspace_1',
}) =>
    CachedConversationRepository(delegate: delegate)
      ..replaceFromBootstrap(
        workspaceId: workspaceId,
        conversations: conversations,
      );

class _PagedHistoryConversationRepository extends _LazyConversationRepository {
  _PagedHistoryConversationRepository({
    required this.pages,
  }) : super(const <ConversationEvent>[]);

  final Queue<ConversationEventPage> pages;
  final List<String> pageCalls = <String>[];
  final List<int> watchAfterSeqs = <int>[];

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    pageCalls.add('$conversationId:$beforeSeq:$limit');
    return pages.removeFirst();
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    watchAfterSeqs.add(afterSeq);
    return const Stream<ConversationEvent>.empty();
  }
}

class _DelayedOlderPageConversationRepository
    extends _PagedHistoryConversationRepository {
  _DelayedOlderPageConversationRepository({
    required ConversationEventPage firstPage,
  }) : super(
            pages: Queue<ConversationEventPage>.from(
          <ConversationEventPage>[firstPage],
        ));

  final Completer<ConversationEventPage> olderPageCompleter =
      Completer<ConversationEventPage>();

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    pageCalls.add('$conversationId:$beforeSeq:$limit');
    if (beforeSeq != null) {
      return olderPageCompleter.future;
    }
    return pages.removeFirst();
  }
}

class _StoredHistoryConversationRepository extends _LazyConversationRepository {
  _StoredHistoryConversationRepository(super.messages);

  final List<int> fetchAfterSeqs = <int>[];
  final List<String> pageCalls = <String>[];
  final List<int> watchAfterSeqs = <int>[];

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async {
    fetchAfterSeqs.add(afterSeq);
    return messages
        .where((event) => event.seq > afterSeq)
        .toList(growable: false);
  }

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    pageCalls.add('$conversationId:$beforeSeq:$limit');
    return super.fetchConversationEventPage(
      conversationId,
      beforeSeq: beforeSeq,
      limit: limit,
    );
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    watchAfterSeqs.add(afterSeq);
    return const Stream<ConversationEvent>.empty();
  }
}

class _HangingFetchConversationRepository extends _LazyConversationRepository {
  _HangingFetchConversationRepository() : super(const <ConversationEvent>[]);

  final fetchCompleter = Completer<List<ConversationEvent>>();
  bool fetchStarted = false;

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) {
    fetchStarted = true;
    return fetchCompleter.future;
  }

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    final events = await fetchConversationEvents(conversationId);
    return ConversationEventPage(
      events: events,
      oldestSeq: events.isEmpty ? null : events.first.seq,
      newestSeq: events.isEmpty ? null : events.last.seq,
      hasMoreBefore: false,
    );
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      const Stream<ConversationEvent>.empty();

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_slow_history',
          workspaceId: 'workspace_1',
          status: 'completed',
          sessionBinding: 'confirmed',
          userMessageCount: 1,
          title: 'Slow history conversation',
        ),
      ];
}

class _HangingPageConversationRepository extends _LazyConversationRepository {
  _HangingPageConversationRepository() : super(const <ConversationEvent>[]);

  final fetchCompleter = Completer<ConversationEventPage>();
  bool pageFetchStarted = false;

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) {
    pageFetchStarted = true;
    return fetchCompleter.future;
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      const Stream<ConversationEvent>.empty();
}

class _LifecycleConversationRepository implements ConversationRepository {
  _LifecycleConversationRepository({
    this.cancelError,
    this.sendError,
    this.events = const <ConversationEvent>[],
  });

  final Object? cancelError;
  Object? sendError;
  Completer<ConversationSummary>? sendCompleter;
  final List<ConversationEvent> events;
  final List<int> afterSeqs = <int>[];
  int cancelCalls = 0;
  int watchCalls = 0;
  String? sentText;
  String? answeredQuestionId;
  String? answeredText;
  String? approvalConversationId;
  String? approvalId;
  String? approvalDecision;
  ApprovalDecision? approvalResponseDecision;

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async {
    answeredQuestionId = questionId;
    answeredText = text;
    return _conversationSummary(
      id: conversationId,
      workspaceId: 'workspace_1',
      status: 'running',
      sessionBinding: 'confirmed',
      userMessageCount: 2,
    );
  }

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      events.where((event) => event.seq > afterSeq).toList(growable: false);

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    final pageEvents = events
        .where((event) => beforeSeq == null || event.seq < beforeSeq)
        .toList(growable: false);
    final limitedEvents = pageEvents.length <= limit
        ? pageEvents
        : pageEvents.sublist(pageEvents.length - limit);
    return ConversationEventPage(
      events: limitedEvents,
      oldestSeq: limitedEvents.isEmpty ? null : limitedEvents.first.seq,
      newestSeq: limitedEvents.isEmpty ? null : limitedEvents.last.seq,
      hasMoreBefore: false,
    );
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    watchCalls += 1;
    afterSeqs.add(afterSeq);
    late final StreamController<ConversationEvent> controller;
    controller = StreamController<ConversationEvent>(
      onListen: () {
        for (final event in events.where((event) => event.seq > afterSeq)) {
          controller.add(event);
        }
      },
      onCancel: () {
        cancelCalls += 1;
        final error = cancelError;
        if (error != null) throw error;
      },
    );
    return controller.stream;
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    ApprovalResponse response,
  ) async {
    approvalConversationId = conversationId;
    this.approvalId = approvalId;
    approvalDecision = response.legacyDecision;
    approvalResponseDecision = response.decision;
    return _conversationSummary(
      id: conversationId,
      workspaceId: 'workspace_1',
      status: 'idle',
      sessionBinding: 'confirmed',
      userMessageCount: 1,
    );
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async {
    sentText = request.text;
    final error = sendError;
    if (error != null) {
      sendError = null;
      throw error;
    }
    final completer = sendCompleter;
    if (completer != null) return completer.future;
    return _conversationSummary(
      id: conversationId,
      workspaceId: 'workspace_1',
      status: 'running',
      sessionBinding: 'confirmed',
      userMessageCount: 2,
    );
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> updateConversationPermissionMode(
    String conversationId,
    String permissionMode,
  ) async =>
      throw UnimplementedError();
}

class _NewSessionConversationRepository implements ConversationRepository {
  _NewSessionConversationRepository({this.createCompleter});

  final Completer<ConversationSummary>? createCompleter;
  final sendCompleter = Completer<ConversationSummary>();

  String? sentText;
  final List<String> createdAdapters = <String>[];
  final List<String> createdPermissionModes = <String>[];

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    createdAdapters.add(adapter);
    createdPermissionModes.add(permissionMode);
    final createCompleter = this.createCompleter;
    if (createCompleter != null) return createCompleter.future;
    return _conversationSummary(
      id: 'conv_new_running',
      workspaceId: workspaceId,
      status: 'idle',
      sessionBinding: 'pending',
      userMessageCount: 0,
    );
  }

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      const <ConversationEvent>[];

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async =>
      const ConversationEventPage(
        events: <ConversationEvent>[],
        oldestSeq: null,
        newestSeq: null,
        hasMoreBefore: false,
      );

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      const Stream<ConversationEvent>.empty();

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    ApprovalResponse response,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) {
    sentText = request.text;
    return sendCompleter.future;
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      _conversationSummary(
        id: conversationId,
        workspaceId: 'workspace_1',
        status: 'idle',
        model: model,
      );

  @override
  Future<ConversationSummary> updateConversationPermissionMode(
    String conversationId,
    String permissionMode,
  ) async =>
      _conversationSummary(
        id: conversationId,
        workspaceId: 'workspace_1',
        status: 'idle',
      );
}

HomeViewModel _homeViewModelForSnapshot(AppSnapshot snapshot) => HomeViewModel(
      workspaceRepository: _SnapshotWorkspaceRepository(snapshot),
      conversationRepository:
          _SnapshotCachedConversationRepository(snapshot.conversations),
      runRepository: _SnapshotCachedRunRepository(
        runs: snapshot.runs,
        queue: snapshot.queue,
      ),
      signalMetrics: HomeWorkspaceSignalMetrics(
        changedFiles: snapshot.gitStatus?.files.length,
        diagnostics: snapshot.diagnostics.available
            ? snapshot.diagnostics.diagnostics.length
            : null,
        recentFiles: snapshot.diagnostics.available
            ? snapshot.overview.recentFiles.length
            : null,
      ),
    );

class _SnapshotWorkspaceRepository
    extends data_repositories.WorkspaceRepository {
  _SnapshotWorkspaceRepository(this.snapshot)
      : _selectedWorkspaceId = snapshot.workspace.id;

  final AppSnapshot snapshot;
  String? _selectedWorkspaceId;

  @override
  List<WorkspaceSummary> get workspaces => snapshot.workspaces;

  @override
  WorkspaceSummary? get selectedWorkspace {
    final selectedWorkspaceId = _selectedWorkspaceId;
    if (selectedWorkspaceId == null) return null;
    for (final workspace in snapshot.workspaces) {
      if (workspace.id == selectedWorkspaceId) return workspace;
    }
    return null;
  }

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) async =>
      throw UnimplementedError();

  @override
  bool select(String workspaceId) {
    if (!snapshot.workspaces.any((workspace) => workspace.id == workspaceId)) {
      return false;
    }
    _selectedWorkspaceId = workspaceId;
    notifyListeners();
    return true;
  }

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    _selectedWorkspaceId = selectedWorkspace?.id;
    notifyListeners();
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => snapshot.workspaces;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SnapshotCachedConversationRepository
    extends CachedConversationRepository {
  _SnapshotCachedConversationRepository(this._conversations)
      : super(delegate: _UnusedConversationRepository());

  final List<ConversationSummary> _conversations;

  @override
  List<ConversationSummary> get conversations => _conversations;

  @override
  Future<void> refresh() async {}
}

class _SnapshotCachedRunRepository extends CachedRunRepository {
  _SnapshotCachedRunRepository({
    required List<RunSummary> runs,
    required List<QueueItem> queue,
  })  : _runs = runs,
        _queue = queue,
        super(delegate: _UnusedRunRepository());

  final List<RunSummary> _runs;
  final List<QueueItem> _queue;

  @override
  List<RunSummary> get runs => _runs;

  @override
  List<QueueItem> get queue => _queue;

  @override
  Future<void> refresh() async {}
}

class _WidgetCodingPreferencesRepository extends CodingPreferencesRepository {
  _WidgetCodingPreferencesRepository({
    required String permissionMode,
    bool expandToolDetails = false,
  })  : _expandToolDetails = expandToolDetails,
        _permissionMode =
            CodingPreferencesRepository.normalizePermissionMode(permissionMode);

  String _permissionMode;
  bool _expandToolDetails;

  @override
  String get permissionMode => _permissionMode;

  @override
  bool get expandToolDetails => _expandToolDetails;

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> setPermissionMode(String value) async {
    _permissionMode =
        CodingPreferencesRepository.normalizePermissionMode(value);
    notifyListeners();
  }

  @override
  Future<void> setExpandToolDetails(bool value) async {
    _expandToolDetails = value;
    notifyListeners();
  }
}

class _UnusedRunRepository implements RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedConversationRepository implements ConversationRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WidgetTestWorkspaceRepository implements WorkspaceRepository {
  _WidgetTestWorkspaceRepository({
    List<DirectoryEntrySummary> roots = const <DirectoryEntrySummary>[],
    Map<String, DirectoryListing> directories =
        const <String, DirectoryListing>{},
  })  : _roots = roots,
        _directories = directories;

  final List<DirectoryEntrySummary> _roots;
  final Map<String, DirectoryListing> _directories;

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async =>
      throw UnimplementedError();

  @override
  Future<FileContent> fileContent(String workspaceId, String path) async =>
      throw UnimplementedError();

  @override
  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path = '',
    int maxDepth = 8,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<List<GitCommitSummary>> gitCommits(
    String workspaceId, {
    int limit = 20,
  }) async =>
      throw UnimplementedError();

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<DirectoryListing> listDirectory(String path) async =>
      _directories[path] ??
      (throw StateError('No test directory listing for $path'));

  @override
  Future<List<DirectoryEntrySummary>> listFileSystemRoots() async => _roots;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      const <WorkspaceSummary>[];

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) async =>
      throw UnimplementedError();
}

AppSnapshot _testSnapshot({
  List<WorkspaceSummary>? workspaces,
  List<RunSummary> runs = const <RunSummary>[],
  List<ConversationSummary> conversations = const <ConversationSummary>[],
  List<QueueItem> queue = const <QueueItem>[],
  List<RecentFileSummary> recentFiles = const <RecentFileSummary>[],
  GitStatusSummary? gitStatus,
  CodeDiagnosticsSummary diagnostics = const CodeDiagnosticsSummary(
      workspaceId: 'workspace_1',
      available: true,
      diagnostics: <CodeDiagnostic>[]),
}) {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  final resolvedWorkspaces = workspaces ?? const <WorkspaceSummary>[workspace];
  return AppSnapshot(
      health: DaemonHealth.fromJson(const <String, Object?>{
        'status': 'ok',
        'daemonVersion': 'test',
        'mode': 'test',
        'lanMode': false,
        'bindAddress': '127.0.0.1',
        'port': 4317,
        'security': {'tokenRequired': false}
      }),
      workspaces: resolvedWorkspaces,
      workspace: workspace,
      overview: ProjectOverview(
          workspaceId: 'workspace_1',
          name: 'vibe-coding',
          path: r'D:\AiProject\vibe-coding',
          fileCount: 0,
          codeLineCount: 0,
          symbolCount: 0,
          analysisScore: 0,
          recentFiles: recentFiles),
      adapters: const <AdapterStatus>[],
      runs: runs,
      conversations: conversations,
      queue: queue,
      templates: const <CommandTemplate>[],
      gitStatus: gitStatus ??
          const GitStatusSummary(
              workspaceId: 'workspace_1',
              clean: true,
              files: <GitStatusFile>[]),
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
          workspaceId: 'workspace_1', root: '', entries: <FileTreeEntry>[]),
      diagnostics: diagnostics,
      extensions: const <ExtensionSummary>[]);
}

ConversationSummary _conversationSummary({
  required String id,
  required String workspaceId,
  required String status,
  String? cliSessionId,
  String sessionBinding = 'unknown',
  int userMessageCount = 0,
  ConversationCapabilities? capabilities,
  ConversationBlockingItem? blockingItem,
  String? model,
  String? title,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: 'codex',
      model: model,
      status: status,
      title: title,
      cliSessionId: cliSessionId,
      sessionBinding: sessionBinding,
      userMessageCount: userMessageCount,
      capabilities: capabilities ??
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-06T10:00:00.000Z',
      updatedAt: '2026-05-06T10:01:00.000Z',
      blockingItem: blockingItem,
    );

void main() {
  testWidgets('app renders English when forced to English',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsLabelApp());
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('app renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const _LocalizedSettingsLabelApp());
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
  });

  testWidgets(
      'home command deck renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const _LocalizedHomePageApp());
    await tester.pumpAndSettle();

    expect(find.text('新建任务'), findsWidgets);
    expect(find.text('工作区信号'), findsOneWidget);
    expect(find.text('vibe-coding'), findsWidgets);
    expect(find.text('daemon 在线'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('快捷操作'), findsOneWidget);
    expect(find.text('命令模板'), findsWidgets);
    expect(find.text('已连接'), findsNothing);
    expect(find.text('Command templates'), findsNothing);
    expect(find.text('Needs your approval'), findsNothing);
    expect(find.text('Modify file'), findsNothing);
    expect(find.text('daemon online'), findsNothing);
    expect(find.text('online'), findsNothing);
  });

  testWidgets('home command deck hides connection controls',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedHomePageApp());
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsNothing);
    expect(find.text('127.0.0.1:4317'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
  });

  testWidgets('connected startup opens coding without bootstrap refetching',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    _setMockPackageInfo();
    final client = _NoBootstrapRefreshClient();
    addTearDown(client.close);
    var createdHomeViewModels = 0;
    final dependencies = AppDependencies.createDefault();
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createHomeViewModel: (connectedData, {signalMetrics}) {
          createdHomeViewModels += 1;
          final viewModel = _defaultTestHomeViewModelFactory(
            connectedData,
            signalMetrics: signalMetrics,
          );
          return viewModel;
        },
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies:
            dependencies.features.createWorkbenchDependencies,
      ),
    );
    final snapshot = _testSnapshot(
      runs: const <RunSummary>[
        RunSummary(
          id: 'run_bootstrap',
          tool: 'codex',
          workspaceId: 'workspace_1',
          status: 'completed',
        ),
      ],
      queue: const <QueueItem>[
        QueueItem(
          runId: 'run_bootstrap',
          workspaceId: 'workspace_1',
          position: 1,
          status: 'queued',
          reason: 'waiting',
        ),
      ],
    );

    await tester.pumpWidget(_MainHarness(
      client: client,
      dependencies: testDependencies,
      snapshot: snapshot,
    ));
    await _pumpNavigationFrame(tester);

    expect(createdHomeViewModels, 0);
    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(client.listWorkspacesCalls, 0);
    expect(client.listConversationsCalls, 0);
    expect(client.listRunsCalls, 0);
    expect(client.listQueueCalls, 0);
  });

  testWidgets('home command deck shows global attention and activity',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final snapshot = _testSnapshot(
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_failed',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'failed'),
      ],
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_approval',
          workspaceId: 'workspace_1',
          status: 'waiting_approval',
          blockingItem: const ConversationBlockingItem(
            type: 'approval_request',
            approvalId: 'ap1',
            summary: 'Modify file',
          ),
        ),
      ],
    );

    await tester.pumpWidget(_LocalizedHomePageApp(snapshot: snapshot));
    await tester.pumpAndSettle();

    expect(find.text('Modify file'), findsWidgets);
    expect(find.textContaining('run_failed'), findsWidgets);
  });

  testWidgets('home command deck surfaces other workspace running activity',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final snapshot = _testSnapshot(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(
            id: 'workspace_1',
            name: 'Current Project',
            path: r'D:\AiProject\vibe-coding'),
        WorkspaceSummary(
            id: 'workspace_2', name: 'daemon', path: r'D:\AiProject\daemon'),
      ],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_other',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'running'),
      ],
    );

    await tester.pumpWidget(_LocalizedHomePageApp(snapshot: snapshot));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(find.textContaining('daemon'), findsWidgets);
  });

  testWidgets('settings language picker shows self-identifying language names',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsPageApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
  });

  testWidgets('settings permission mode selection is persisted',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(_MainHarness(client: _AdapterRefreshClient()));
    await _pumpNavigationFrame(tester);

    await tester.tap(find.text('Settings').last);
    await _pumpNavigationFrame(tester);
    await tester.tap(find.text('Auto'));
    await _pumpNavigationFrame(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CodingPreferencesStore.permissionModeStorageKey),
        'auto');
  });

  testWidgets('settings tool detail expansion preference is persisted',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(_MainHarness(client: _AdapterRefreshClient()));
    await _pumpNavigationFrame(tester);

    await tester.tap(find.text('Settings').last);
    await _pumpNavigationFrame(tester);

    expect(find.text('Show tool call details'), findsOneWidget);
    final row = find.ancestor(
      of: find.text('Show tool call details'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byType(Switch)),
    );
    await _pumpNavigationFrame(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(CodingPreferencesStore.expandToolDetailsStorageKey),
      isTrue,
    );
  });

  testWidgets('settings shows active daemon address and proxy mode',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsPageApp());
    await tester.pumpAndSettle();

    expect(find.text('Daemon address'), findsOneWidget);
    expect(find.text('192.168.1.20:4317'), findsOneWidget);
    expect(find.text('Proxy mode'), findsOneWidget);
    expect(find.text('Manual proxy'), findsOneWidget);
  });

  testWidgets('settings hides update check when update service is unavailable',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsPageApp());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Check for updates'), findsNothing);
  });

  testWidgets('settings update check lives in about and starts manual check',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final installer = _WidgetAppUpdateInstaller();
    addTearDown(installer.close);
    final repository =
        _WidgetAppUpdateRepository(manifest: _widgetAppUpdateManifest());
    final appUpdateViewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: AppUpdateWorkflow(
        repository: repository,
        installerService: installer,
        downloaderService: _WidgetAppUpdateDownloader(),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(appUpdateViewModel.dispose);

    await tester.pumpWidget(
        _LocalizedSettingsPageApp(appUpdateViewModel: appUpdateViewModel));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('About'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('App update'), findsNothing);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Check for updates'), findsNothing);
    final updateVersionRight = tester.getTopRight(find.text('1.0.0')).dx;
    expect(
      updateVersionRight,
      greaterThan(tester.getTopRight(find.text('Check for updates')).dx + 24),
    );
    expect(
      tester.getTopLeft(find.byIcon(Icons.chevron_right_rounded).last).dx -
          updateVersionRight,
      inInclusiveRange(4, 16),
    );

    await tester.tap(find.text('Check for updates'));
    for (var attempt = 0;
        attempt < 10 && repository.fetchLatestCalls < 1;
        attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(repository.fetchLatestCalls, 1);
    expect(find.text('Update available'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pumpAndSettle();
  });

  testWidgets('app update download dialog shows determinate progress',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: AppUpdatePanel(
        state: const AppUpdateState(
          status: AppUpdateStatus.downloading,
          installedVersionName: '1.0.0',
          installedVersionCode: 1,
          downloadedBytes: 50,
          totalBytes: 100,
        ),
        onCheck: () {},
        onDownload: () {},
        onInstall: () {},
        onDiscard: () {},
        onPostpone: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const ValueKey('app-update-progress-dialog')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(indicator.value, .5);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.textContaining('50 B / 100 B'), findsOneWidget);
  });

  testWidgets('renders assistant markdown instead of raw syntax',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildAssistantMarkdownPreview(
        'Hello\n\n- **Code and debug**\n- `inline code`\n\n<script>alert(1)</script>'));
    await tester.pumpAndSettle();

    expect(find.text('Code and debug'), findsOneWidget);
    expect(find.text('inline code'), findsOneWidget);
    expect(find.textContaining('**Code and debug**'), findsNothing);
    expect(find.textContaining('<script>'), findsNothing);
  });

  testWidgets('app starts on editable connection page without bottom nav',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const LanAiCliControlApp());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('System proxy'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);

    final header = find.byKey(const ValueKey('connection-header'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.byType(PopupMenuButton<dynamic>),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'connection page renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const LanAiCliControlApp());
    await tester.pumpAndSettle();

    expect(find.text('\u8fde\u63a5'), findsWidgets);
    expect(find.text('\u8fde\u63a5\u5730\u5740'), findsOneWidget);
    expect(find.text('\u7f51\u7edc\u4ee3\u7406'), findsOneWidget);
    expect(find.text('\u76f4\u8fde'), findsWidgets);
    expect(find.text('\u672a\u8fde\u63a5'), findsOneWidget);
    expect(find.text('\u76ee\u6807'), findsOneWidget);
    expect(find.text('\u4ee3\u7406'), findsOneWidget);
    expect(find.text('Connection'), findsNothing);
    expect(find.text('Network proxy'), findsNothing);
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('connection error page uses active locale',
      (WidgetTester tester) async {
    var retried = false;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: MobileConnectionErrorPage(
        error: 'boom',
        onRetry: () => retried = true,
      ),
    ));

    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('无法连接到本地 daemon'), findsOneWidget);
    expect(find.text('重试连接'), findsOneWidget);
    expect(find.textContaining('start-daemon.bat'), findsOneWidget);
    expect(find.text('Retry connection'), findsNothing);

    await tester.tap(find.text('重试连接'));

    expect(retried, isTrue);
  });

  testWidgets('connection input validation uses active locale',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();

    await tester.pumpWidget(MaterialApp(
      locale: const Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: MobileConnectionPage(controller: controller),
    ));

    await tester.enterText(find.byType(TextField), ' ');
    await tester.tap(find.text('连接').last);
    await tester.pump();

    expect(find.text('请输入 daemon 地址。'), findsOneWidget);
    expect(find.text('Enter a daemon address.'), findsNothing);
  });

  testWidgets('connection page keeps address and proxy editable after failure',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async {
        throw const DaemonClientException(502, <String, Object?>{
          'error': 'invalid_response',
          'message': 'daemon returned an empty response body',
        });
      },
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();

    await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      localeResolutionCallback: (locale, supportedLocales) =>
          resolveSupportedLocale(locale, supportedLocales),
      theme: theme.buildAppTheme(),
      home: MobileConnectionPage(controller: controller),
    ));

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.textContaining('proxy or gateway'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('System proxy'), findsOneWidget);
    expect(find.text('Manual proxy'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);
  });

  testWidgets('connection address field shows recent addresses on focus',
      (WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(<String>[
        '192.168.1.50:4317',
        'http://devbox.local:4317',
      ]),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();
    controller.setAddressInput('');

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(find.text('192.168.1.50:4317'), findsOneWidget);
    expect(find.text('http://devbox.local:4317'), findsOneWidget);
    expect(find.bySemanticsLabel('192.168.1.50:4317'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('192.168.1.50:4317'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.50:4317'), findsNothing);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.50:4317'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.50:4317'), findsNothing);
    expect(find.text('Connection'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('connection recent dropdown floats without moving form sections',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(<String>[
        '192.168.1.50:4317',
        'http://devbox.local:4317',
      ]),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();
    controller.setAddressInput('');

    await tester.pumpWidget(_connectionPage(controller));

    final proxySection = find.text('NETWORK PROXY');
    final proxyTopBefore = tester.getTopLeft(proxySection).dy;

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    final dropdown =
        find.byKey(const ValueKey('connection-recent-address-dropdown'));
    expect(dropdown, findsOneWidget);
    expect(tester.getTopLeft(proxySection).dy, proxyTopBefore);
    expect(
      tester.getTopLeft(dropdown).dy,
      greaterThan(tester.getBottomLeft(find.byType(TextField).first).dy),
    );
  });

  testWidgets('connection recent addresses filter and fill without connecting',
      (WidgetTester tester) async {
    var connectCalls = 0;
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(<String>[
        '192.168.1.50:4317',
        'http://devbox.local:4317',
        'https://prod.local:443',
      ]),
      snapshotLoader: (_) async {
        connectCalls += 1;
        throw StateError('must not connect');
      },
      healthProbe: (_) async => throw StateError('must not connect'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();
    controller.setProxyMode(DaemonProxyMode.manual);
    controller.setManualProxyInput('http://proxy.local:8080');

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'DEV');
    await tester.pumpAndSettle();

    const selectedAddress = 'http://devbox.local:4317';
    expect(find.text(selectedAddress), findsOneWidget);
    expect(find.text('192.168.1.50:4317'), findsNothing);

    await tester.tap(find.text(selectedAddress));
    await tester.pumpAndSettle();

    expect(controller.addressInput, selectedAddress);
    final addressField = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      addressField.controller?.selection,
      TextSelection.collapsed(offset: selectedAddress.length),
    );
    expect(controller.proxyMode, DaemonProxyMode.manual);
    expect(controller.manualProxyInput, 'http://proxy.local:8080');
    expect(controller.status, DaemonConnectionStatus.idle);
    expect(connectCalls, 0);
    expect(find.byKey(const ValueKey('connection-recent-address-dropdown')),
        findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('connection recent dropdown clamps long history',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(<String>[
        for (var index = 1; index <= 8; index++) '192.168.1.$index:4317',
      ]),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();
    controller.setAddressInput('');

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    final dropdown =
        find.byKey(const ValueKey('connection-recent-address-dropdown'));
    expect(dropdown, findsOneWidget);
    expect(tester.getSize(dropdown).height, lessThanOrEqualTo(184));
    expect(find.text('192.168.1.1:4317'), findsOneWidget);
    expect(find.text('192.168.1.8:4317'), findsNothing);
  });

  testWidgets('connected empty workspace catalog keeps bottom tabs',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      connectToDaemon: _ImmediateConnectUseCase(
        ConnectedAppSession<DaemonClient>(
          client: _AdapterRefreshClient(),
          initialData: DaemonInitialData(
            health: _testSnapshot().health,
            workspaces: const <WorkspaceSummary>[],
            workspace: null,
            adapters: const <AdapterStatus>[],
            runs: const <RunSummary>[],
            conversations: const <ConversationSummary>[],
            queue: const <QueueItem>[],
          ),
          connectedConfig: const DaemonConnectionConfig(
            addressInput: '127.0.0.1:4317',
            proxyMode: DaemonProxyMode.system,
            manualProxyInput: '',
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _setMockPackageInfo();
    final installer = _WidgetAppUpdateInstaller();
    addTearDown(installer.close);
    final appUpdateViewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: AppUpdateWorkflow(
        repository: _WidgetAppUpdateRepository(
          manifest: _widgetAppUpdateManifest(),
        ),
        installerService: installer,
        downloaderService: _WidgetAppUpdateDownloader(),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    final dependencies = AppDependencies.createDefault();
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel: ({
          required DaemonClient client,
          required ConnectedDataDependencies connectedData,
          required int installedVersionCode,
          required String installedVersionName,
        }) async =>
            appUpdateViewModel,
        createWorkbenchDependencies:
            dependencies.features.createWorkbenchDependencies,
      ),
    );

    await tester.pumpWidget(_MobileConnectionHarness(
      controller: controller,
      dependencies: testDependencies,
    ));
    await controller.load();
    await controller.connect();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byType(BottomNav), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Coding'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Workspaces'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Daemon address'), findsOneWidget);
    expect(find.text('127.0.0.1:4317'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('About'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('App update'), findsNothing);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(find.textContaining('Bad state'), findsNothing);
  });

  testWidgets(
      'opening second workspace pins repository-backed home and settings',
      (WidgetTester tester) async {
    const workspaces = <WorkspaceSummary>[
      WorkspaceSummary(id: 'workspace_1', name: 'One', path: r'D:\one'),
      WorkspaceSummary(id: 'workspace_2', name: 'Two', path: r'D:\two'),
    ];
    final client = _WorkspaceSelectionClient(workspaceCatalog: workspaces);
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      connectToDaemon: _ImmediateConnectUseCase(
        ConnectedAppSession<DaemonClient>(
          client: client,
          initialData: DaemonInitialData(
            health: _testSnapshot().health,
            workspaces: workspaces,
            workspace: null,
            adapters: const <AdapterStatus>[],
            runs: const <RunSummary>[],
            conversations: const <ConversationSummary>[],
            queue: const <QueueItem>[],
          ),
          connectedConfig: const DaemonConnectionConfig(
            addressInput: '127.0.0.1:4317',
            proxyMode: DaemonProxyMode.system,
            manualProxyInput: '',
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _setMockPackageInfo();
    final dependencies = AppDependencies.createDefault();
    SettingsViewModel? openedSettingsViewModel;
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createSettingsViewModel: ({
          required ConnectedDataDependencies connectedData,
          required DaemonConnectionConfig connectionConfig,
          required DaemonHealth health,
          ActiveConversationProvider? activeConversationProvider,
          CodeDiagnosticsSummary? diagnostics,
          GitStatusSummary? gitStatus,
          int extensionsCount = 0,
        }) {
          final viewModel = _defaultTestSettingsViewModelFactory(
            connectedData: connectedData,
            connectionConfig: connectionConfig,
            health: health,
            activeConversationProvider: activeConversationProvider,
            diagnostics: diagnostics,
            gitStatus: gitStatus,
            extensionsCount: extensionsCount,
          );
          openedSettingsViewModel = viewModel;
          return viewModel;
        },
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel: ({
          required DaemonClient client,
          required ConnectedDataDependencies connectedData,
          required int installedVersionCode,
          required String installedVersionName,
        }) async =>
            throw StateError('not used'),
        createWorkbenchDependencies:
            dependencies.features.createWorkbenchDependencies,
      ),
    );

    await tester.pumpWidget(_MobileConnectionHarness(
      controller: controller,
      dependencies: testDependencies,
    ));
    await controller.load();
    await controller.connect();
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);

    await tester.tap(find.text('Two'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(openedSettingsViewModel?.selectedWorkspace?.id, 'workspace_2');
    expect(
      client.codexJsonPaths,
      contains('/api/codex-app-server/workspaces/workspace_2/threads?limit=50'),
    );

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(TopBar), matching: find.text('Two')),
      findsOneWidget,
    );
    expect(find.text('No workspace selected'), findsNothing);
  });

  testWidgets('workspace bootstrap failure stays in main workspace state',
      (WidgetTester tester) async {
    const workspace = WorkspaceSummary(
        id: 'workspace_1',
        name: 'Current Project',
        path: r'D:\AiProject\vibe-coding');
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      connectToDaemon: _ImmediateConnectUseCase(
        ConnectedAppSession<DaemonClient>(
          client: _WorkspaceBootstrapFailureClient(),
          initialData: DaemonInitialData(
            health: _testSnapshot().health,
            workspaces: const <WorkspaceSummary>[workspace],
            workspace: null,
            adapters: const <AdapterStatus>[],
            runs: const <RunSummary>[],
            conversations: const <ConversationSummary>[],
            queue: const <QueueItem>[],
          ),
          connectedConfig: const DaemonConnectionConfig(
            addressInput: '127.0.0.1:4317',
            proxyMode: DaemonProxyMode.system,
            manualProxyInput: '',
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(_MobileConnectionHarness(controller: controller));
    await controller.load();
    await controller.connect();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byType(BottomNav), findsOneWidget);
    expect(find.text('Loading workspace...'), findsNothing);
    expect(find.textContaining('list runs unavailable'), findsOneWidget);
  });

  testWidgets('MobileUiFrame renders supplied child',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MobileUiFrame(child: Text('frame child')),
    ));

    expect(find.text('frame child'), findsOneWidget);
  });

  testWidgets('top bar uses neutral letter spacing',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme.buildAppTheme(),
      home: const Scaffold(
        body: TopBar(
          title: 'Title',
          subtitle: 'Subtitle',
          statusLabel: 'Ready',
        ),
      ),
    ));

    expect(tester.widget<Text>(find.text('Title')).style?.letterSpacing, 0);
    expect(tester.widget<Text>(find.text('Subtitle')).style?.letterSpacing, 0);
  });

  testWidgets('coding composer exposes voice input semantics',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
  });

  testWidgets('coding composer does not send when voice pointer is released',
      (WidgetTester tester) async {
    var sends = 0;
    final controller = TextEditingController(text: 'hello');
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: true,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () => sends++,
                onCancel: () {}))));

    await tester.tap(find.bySemanticsLabel('Voice input'));
    await tester.pumpAndSettle();

    expect(sends, 0);
  });

  testWidgets('coding composer shows listening state while recording',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.textContaining('Listening'), findsOneWidget);
  });

  testWidgets('coding composer voice strings use active locale',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.text('输入你的需求...'), findsOneWidget);
    expect(find.text('正在听写...松开后完成'), findsOneWidget);
    expect(find.bySemanticsLabel('语音输入'), findsOneWidget);
  });

  testWidgets('coding composer reports text edits while voice is listening',
      (WidgetTester tester) async {
    String? editedText;
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (text) => editedText = text,
                onSend: () {},
                onCancel: () {}))));

    await tester.enterText(find.byType(TextField), 'manual edit');

    expect(editedText, 'manual edit');
  });

  testWidgets('coding composer does not render voice errors inline',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.failed,
                voiceEnabled: true,
                voiceError: '未检测到可用麦克风，请连接或启用录音设备后重试。',
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.textContaining('未检测到可用麦克风'), findsNothing);
  });

  testWidgets('coding composer keeps model chip in the input surface',
      (WidgetTester tester) async {
    var modelTaps = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                model: 'GPT-5 Codex',
                modelNotice: 'Model changed to an available option',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                cliLocked: false,
                modelLocked: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                onCliTap: () {},
                onModelTap: () => modelTaps++,
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.text('codex'), findsNothing);
    expect(find.text('GPT-5 Codex'), findsOneWidget);
    expect(find.text('Model changed to an available option'), findsOneWidget);

    await tester.tap(find.text('GPT-5 Codex'));

    expect(modelTaps, 1);
  });

  testWidgets('composer workspace cloud renders CLI selector on the left',
      (WidgetTester tester) async {
    var cliTaps = 0;
    var workspaceTaps = 0;
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: ComposerWorkspaceCloud(
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                adapter: 'codex',
                running: false,
                cliLocked: false,
                onCliTap: () => cliTaps++,
                onTap: () => workspaceTaps++))));

    expect(find.text('vibe-coding'), findsOneWidget);
    expect(find.text('codex'), findsOneWidget);

    final cliRight = tester.getTopRight(find.text('codex')).dx;
    final workspaceLeft = tester.getTopLeft(find.text('vibe-coding')).dx;
    expect(cliRight, lessThan(workspaceLeft));

    await tester.tap(find.text('codex'));
    await tester.tap(find.text('vibe-coding'));

    expect(cliTaps, 1);
    expect(workspaceTaps, 1);
  });

  testWidgets('composer workspace cloud blends into composer dock',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: ComposerWorkspaceCloud(
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                adapter: 'codex',
                running: false,
                cliLocked: false,
                onCliTap: () {},
                onTap: () {}))));

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ComposerWorkspaceCloud),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF151515));
    expect(decoration.border, isNull);
  });

  testWidgets('composer workspace cloud can lock CLI selection',
      (WidgetTester tester) async {
    var cliTaps = 0;
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: ComposerWorkspaceCloud(
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                adapter: 'codex',
                running: false,
                cliLocked: true,
                onCliTap: () => cliTaps++,
                onTap: () {}))));

    await tester.tap(find.text('codex'));

    expect(cliTaps, 0);
  });

  testWidgets('coding composer keeps actions right-aligned on compact width',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'very-long-codex-compatible-cli',
                model: 'GPT-5 Codex Experimental Long Context',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                cliLocked: false,
                modelLocked: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    final sendRight = tester
        .getTopRight(find.byKey(const ValueKey('workbench-send-prompt-button')))
        .dx;
    expect(sendRight, greaterThan(280));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'coding composer renders attachment tray above input and deletes draft attachment',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    var deleted = -1;
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: true,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                model: 'gpt-5.3-codex',
                draftAttachments: const <DraftAttachment>[
                  DraftAttachment(
                    localPath: r'D:\tmp\screenshot.png',
                    name: 'screenshot.png',
                    mimeType: 'image/png',
                    kind: AttachmentKind.image,
                    sizeBytes: 120034,
                  ),
                ],
                onAttachmentTap: () {},
                onRemoveAttachment: (index) => deleted = index,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    final inputTop = tester.getTopLeft(find.byType(TextField)).dy;
    final trayTop = tester.getTopLeft(find.text('screenshot.png')).dy;
    expect(trayTop, lessThan(inputTop));

    await tester.tap(find.byTooltip('Remove screenshot.png'));
    expect(deleted, 0);
  });

  testWidgets(
      'coding composer shows visible invalid attachment status for unsupported model',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: '这个图片里面有什么?');
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                model: 'text-only-model',
                draftAttachments: const <DraftAttachment>[
                  DraftAttachment(
                    localPath: r'D:\tmp\screenshot.png',
                    name: 'screenshot.png',
                    mimeType: 'image/png',
                    kind: AttachmentKind.image,
                    sizeBytes: 120034,
                    errorCode: 'attachment_kind_unsupported',
                  ),
                ],
                onAttachmentTap: () {},
                onRemoveAttachment: (_) {},
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(
      find.text('This file is not supported by the selected model.'),
      findsOneWidget,
    );
  });

  testWidgets('coding back target renders workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingSessionListPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Other Project'), findsOneWidget);
  });

  testWidgets('coding entry defaults to workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
    expect(find.byKey(const ValueKey('coding-workbench-detail')), findsNothing);
  });

  testWidgets('workbench conversation lazily builds large message lists',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = List<ConversationEvent>.generate(
      500,
      (index) => ConversationEvent.fromJson(<String, Object?>{
        'seq': index + 1,
        'conversationId': 'conv_lazy',
        'type': 'user.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': 'message $index',
      }),
    );
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LazyConversationRepository(messages);
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_lazy',
        workspaceId: 'workspace_1',
        status: 'completed',
        sessionBinding: 'confirmed',
        userMessageCount: messages.length,
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex task lazy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('message '), findsWidgets);
    expect(find.text('message 250'), findsNothing);
  });

  testWidgets('opening existing conversation scrolls to latest message',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = List<ConversationEvent>.generate(
      80,
      (index) => ConversationEvent.fromJson(<String, Object?>{
        'seq': index + 1,
        'conversationId': 'conv_scroll',
        'type': index.isEven ? 'user.message' : 'assistant.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': index == 79 ? 'latest visible sentinel' : 'message $index',
      }),
    );
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LazyConversationRepository(messages);
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_scroll',
        workspaceId: 'workspace_1',
        status: 'completed',
        sessionBinding: 'confirmed',
        userMessageCount: messages.length,
        title: 'Scroll regression conversation',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scroll regression conversation'));
    await tester.pumpAndSettle();

    expect(find.text('latest visible sentinel'), findsOneWidget);
    expect(find.text('message 0'), findsNothing);
  });

  testWidgets('pending approval replaces the conversation composer',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    const approvalTarget =
        r'D:\AiProject\vibe-coding\python_concurrency_learn.py';
    final repository = _LifecycleConversationRepository(
      events: <ConversationEvent>[
        ConversationEvent.fromJson(const <String, Object?>{
          'seq': 1,
          'conversationId': 'conv_approval_prompt',
          'type': 'user.message',
          'createdAt': '2026-05-16T00:00:00.000Z',
          'text': 'Update the Python notes'
        }),
        ConversationEvent.fromJson(const <String, Object?>{
          'seq': 2,
          'conversationId': 'conv_approval_prompt',
          'type': 'approval.requested',
          'createdAt': '2026-05-16T00:00:01.000Z',
          'approvalId': 'approval_prompt_1',
          'toolName': 'Write',
          'summary': approvalTarget,
          'input': {'file_path': approvalTarget}
        }),
      ],
    );
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_approval_prompt',
        workspaceId: 'workspace_1',
        status: 'waiting_approval',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Approval prompt task',
        capabilities: capabilities,
        blockingItem: const ConversationBlockingItem(
          type: 'approval_request',
          approvalId: 'approval_prompt_1',
          toolName: 'Write',
          summary: approvalTarget,
          input: {'file_path': approvalTarget},
        ),
      ),
    ];

    Future<void> pumpUntilApprovalPrompt() async {
      for (var attempt = 0;
          attempt < 20 &&
              find
                  .byKey(const ValueKey('workbench-approval-composer'))
                  .evaluate()
                  .isEmpty;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilApprovalResponse() async {
      for (var attempt = 0;
          attempt < 20 && repository.approvalDecision == null;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: conversations,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approval prompt task'));
    await pumpUntilApprovalPrompt();

    expect(find.byKey(const ValueKey('workbench-approval-composer')),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Allow this tool request?'), findsOneWidget);
    expect(find.textContaining('python_concurrency_learn.py'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('workbench-approval-submit-button')));
    await pumpUntilApprovalResponse();

    expect(repository.approvalConversationId, 'conv_approval_prompt');
    expect(repository.approvalId, 'approval_prompt_1');
    expect(repository.approvalDecision, 'allow');
  });

  testWidgets('conversation approval cancel preserves cancel decision',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    const approvalOptions = ApprovalRequestOptions(
      kind: ApprovalRequestKind.command,
      supportsCancel: true,
      command: 'npm test',
    );
    final repository = _LifecycleConversationRepository(
      events: <ConversationEvent>[
        ConversationEvent.fromJson(const <String, Object?>{
          'seq': 1,
          'conversationId': 'conv_approval_cancel',
          'type': 'approval.requested',
          'createdAt': '2026-05-16T00:00:01.000Z',
          'approvalId': 'approval_cancel_1',
          'toolName': 'Bash',
          'summary': 'npm test',
          'input': {'command': 'npm test'},
          'approvalOptions': <String, Object?>{
            'kind': 'command',
            'supportsCancel': true,
            'command': 'npm test',
          },
        }),
      ],
    );
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_approval_cancel',
        workspaceId: 'workspace_1',
        status: 'waiting_approval',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Approval cancel task',
        capabilities: capabilities,
        blockingItem: const ConversationBlockingItem(
          type: 'approval_request',
          approvalId: 'approval_cancel_1',
          toolName: 'Bash',
          summary: 'npm test',
          input: {'command': 'npm test'},
          approvalOptions: approvalOptions,
        ),
      ),
    ];

    Future<void> pumpUntilApprovalPrompt() async {
      for (var attempt = 0;
          attempt < 20 &&
              find
                  .byKey(const ValueKey('workbench-approval-composer'))
                  .evaluate()
                  .isEmpty;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilApprovalResponse() async {
      for (var attempt = 0;
          attempt < 20 && repository.approvalResponseDecision == null;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: conversations,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approval cancel task'));
    await pumpUntilApprovalPrompt();

    await tester
        .tap(find.byKey(const ValueKey('workbench-approval-cancel-button')));
    await pumpUntilApprovalResponse();

    expect(repository.approvalConversationId, 'conv_approval_cancel');
    expect(repository.approvalId, 'approval_cancel_1');
    expect(repository.approvalDecision, 'deny');
    expect(repository.approvalResponseDecision, ApprovalDecision.cancel);
  });

  testWidgets('approval composer uses compact Codex-style approval panel',
      (WidgetTester tester) async {
    final event = AgentEvent(
      type: 'approval.requested',
      seq: 1,
      runId: 'run_approval_prompt',
      createdAt: DateTime.parse('2026-05-16T00:00:01.000Z'),
      approvalId: 'approval_prompt_1',
      name: 'Write',
      raw: const <String, Object?>{'toolName': 'Write'},
    );

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      localeResolutionCallback: (locale, supportedLocales) =>
          resolveSupportedLocale(locale, supportedLocales),
      theme: theme.buildAppTheme(),
      home: Scaffold(
        backgroundColor: theme.bg,
        body: ApprovalComposerPrompt(
          message: WorkbenchMessage(
            'approval',
            'Needs approval',
            r'D:\AiProject\vibe-coding\python_concurrency_learn.py',
            event: event,
          ),
          onApproval: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workbench-approval-choice-panel')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-approval-question')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-approval-command-preview')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-approval-option-allow-once')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-approval-option-deny')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-approval-submit-button')),
        findsOneWidget);
    expect(find.text('Allow this tool request?'), findsOneWidget);
    expect(find.textContaining('Write'), findsOneWidget);
    expect(find.textContaining('python_concurrency_learn.py'), findsOneWidget);
  });

  testWidgets('approval composer shows session option when supported',
      (WidgetTester tester) async {
    final approvals = <ApprovalResponse>[];
    await tester.pumpWidget(_approvalComposerHarness(
      approvalOptions: const ApprovalRequestOptions(
        kind: ApprovalRequestKind.command,
        supportsSessionScope: true,
        supportsCancel: false,
        denyBehavior: ApprovalDenyBehavior.interrupt,
        command: 'npm test',
      ),
      onApproval: approvals.add,
    ));

    expect(find.text('Allow once'), findsOneWidget);
    expect(find.text('Allow for this session'), findsOneWidget);
    expect(find.text('No, tell the agent how to adjust'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('workbench-approval-option-session')));
    await tester
        .tap(find.byKey(const ValueKey('workbench-approval-submit-button')));
    expect(approvals.single.decision, ApprovalDecision.allow);
    expect(approvals.single.scope, ApprovalScope.session);
  });

  testWidgets(
      'approval composer resets session selection when next approval does not support it',
      (WidgetTester tester) async {
    final approvals = <ApprovalResponse>[];
    await tester.pumpWidget(_approvalComposerHarness(
      approvalId: 'approval_session_scope',
      approvalOptions: const ApprovalRequestOptions(
        supportsSessionScope: true,
        command: 'npm test',
      ),
      onApproval: approvals.add,
    ));

    await tester
        .tap(find.byKey(const ValueKey('workbench-approval-option-session')));
    await tester.pump();

    await tester.pumpWidget(_approvalComposerHarness(
      approvalId: 'approval_once_only',
      approvalOptions: const ApprovalRequestOptions(command: 'npm test'),
      onApproval: approvals.add,
    ));

    expect(find.text('Allow for this session'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('workbench-approval-submit-button')));

    expect(approvals.single.decision, ApprovalDecision.allow);
    expect(approvals.single.scope, ApprovalScope.once);
  });

  testWidgets('approval composer shows cancel only when supported',
      (WidgetTester tester) async {
    final approvals = <ApprovalResponse>[];
    await tester.pumpWidget(_approvalComposerHarness(
      approvalOptions: const ApprovalRequestOptions(supportsCancel: true),
      onApproval: approvals.add,
    ));

    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    expect(approvals.single.decision, ApprovalDecision.cancel);
  });

  testWidgets(
      'opening historical conversation loads stored events before watch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = <ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_history',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'status': 'running'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_history',
        'type': 'user.message',
        'createdAt': '2026-05-16T00:00:01.000Z',
        'text': 'historical prompt'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_history',
        'type': 'tool.started',
        'createdAt': '2026-05-16T00:00:02.000Z',
        'toolUseId': 'tool_1',
        'toolName': 'command_execution',
        'input': {'command': 'dir'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 4,
        'conversationId': 'conv_history',
        'type': 'tool.completed',
        'createdAt': '2026-05-16T00:00:03.000Z',
        'toolUseId': 'tool_1',
        'toolName': 'command_execution',
        'exitCode': 0
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 5,
        'conversationId': 'conv_history',
        'type': 'assistant.message',
        'createdAt': '2026-05-16T00:00:04.000Z',
        'text': 'historical answer'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 6,
        'conversationId': 'conv_history',
        'type': 'conversation.completed',
        'createdAt': '2026-05-16T00:00:05.000Z'
      }),
    ];
    final dependencies = AppDependencies.createDefault();
    final conversationRepository =
        _StoredHistoryConversationRepository(messages);
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_history',
        workspaceId: 'workspace_1',
        status: 'completed',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Historical task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final cachedConversationRepository =
        _cachedConversationRepositoryForWorkbenchTest(
      delegate: conversationRepository,
      conversations: conversations,
    );
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: cachedConversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Historical task'));
    await tester.pumpAndSettle();

    expect(conversationRepository.fetchAfterSeqs, isEmpty);
    expect(conversationRepository.pageCalls, <String>['conv_history:null:80']);
    expect(conversationRepository.watchAfterSeqs, <int>[6]);
    expect(find.text('historical prompt'), findsOneWidget);
    expect(find.text('historical answer'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
  });

  testWidgets('opening large historical conversation loads every history page',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _PagedHistoryConversationRepository(
      pages: Queue<ConversationEventPage>.from(<ConversationEventPage>[
        ConversationEventPage(
          events: <ConversationEvent>[
            _pagedConversationEvent(
                seq: 119, type: 'user.message', text: 'recent prompt'),
            _pagedConversationEvent(seq: 120, text: 'latest sentinel'),
          ],
          oldestSeq: 119,
          newestSeq: 120,
          hasMoreBefore: true,
        ),
        ConversationEventPage(
          events: <ConversationEvent>[
            _pagedConversationEvent(
                seq: 1, type: 'user.message', text: 'oldest prompt'),
            _pagedConversationEvent(seq: 2, text: 'oldest answer'),
          ],
          oldestSeq: 1,
          newestSeq: 2,
          hasMoreBefore: false,
        ),
      ]),
    );

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 120,
          title: 'Paged history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged history conversation'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls, <String>[
      'conv_paged:null:80',
      'conv_paged:119:80',
    ]);
    expect(repository.watchAfterSeqs, <int>[120]);
    expect(find.text('oldest prompt'), findsOneWidget);
    expect(find.text('oldest answer'), findsOneWidget);
    expect(find.text('latest sentinel'), findsOneWidget);
    expect(find.text('recent prompt'), findsOneWidget);
  });

  testWidgets('opening paged conversation shows tail before older pages finish',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _DelayedOlderPageConversationRepository(
      firstPage: ConversationEventPage(
        events: <ConversationEvent>[
          _pagedConversationEvent(
              seq: 119, type: 'user.message', text: 'recent prompt'),
          _pagedConversationEvent(seq: 120, text: 'latest sentinel'),
        ],
        oldestSeq: 119,
        newestSeq: 120,
        hasMoreBefore: true,
      ),
    );

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 120,
          title: 'Paged history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged history conversation'));
    await tester.pump();
    await tester.pump();

    expect(repository.pageCalls, <String>[
      'conv_paged:null:80',
      'conv_paged:119:80',
    ]);
    expect(repository.watchAfterSeqs, isEmpty);
    expect(find.text('recent prompt'), findsOneWidget);
    expect(find.text('latest sentinel'), findsOneWidget);
    expect(find.text('oldest prompt'), findsNothing);

    repository.olderPageCompleter.complete(ConversationEventPage(
      events: <ConversationEvent>[
        _pagedConversationEvent(
            seq: 1, type: 'user.message', text: 'oldest prompt'),
        _pagedConversationEvent(seq: 2, text: 'oldest answer'),
      ],
      oldestSeq: 1,
      newestSeq: 2,
      hasMoreBefore: false,
    ));
    await tester.pumpAndSettle();

    expect(repository.watchAfterSeqs, <int>[120]);
    expect(find.text('oldest prompt'), findsOneWidget);
    expect(find.text('oldest answer'), findsOneWidget);
  });

  testWidgets('empty tail starts conversation watch from zero',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _PagedHistoryConversationRepository(
      pages: Queue<ConversationEventPage>.from(const <ConversationEventPage>[
        ConversationEventPage(
          events: <ConversationEvent>[],
          oldestSeq: null,
          newestSeq: null,
          hasMoreBefore: false,
        ),
      ]),
    );

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 1,
          title: 'Paged history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged history conversation'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls, <String>['conv_paged:null:80']);
    expect(repository.watchAfterSeqs, <int>[0]);
  });

  testWidgets('opening paged conversation loads previous history immediately',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _PagedHistoryConversationRepository(
      pages: Queue<ConversationEventPage>.from(<ConversationEventPage>[
        ConversationEventPage(
          events: List<ConversationEvent>.generate(
            100,
            (index) => _pagedConversationEvent(
              seq: index + 21,
              text: index == 99 ? 'latest sentinel' : 'recent $index',
            ),
          ),
          oldestSeq: 21,
          newestSeq: 120,
          hasMoreBefore: true,
        ),
        ConversationEventPage(
          events: <ConversationEvent>[
            _pagedConversationEvent(
                seq: 19, type: 'user.message', text: 'older prompt'),
            _pagedConversationEvent(seq: 20, text: 'older answer'),
          ],
          oldestSeq: 19,
          newestSeq: 20,
          hasMoreBefore: false,
        ),
      ]),
    );

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 120,
          title: 'Paged history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged history conversation'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls, <String>[
      'conv_paged:null:80',
      'conv_paged:21:80',
    ]);
    expect(repository.watchAfterSeqs, <int>[120]);

    await tester.fling(_workbenchMessageList(), const Offset(0, 5000), 10000);
    await tester.pump();
    await tester.fling(_workbenchMessageList(), const Offset(0, 5000), 10000);
    await tester.pump();
    await tester.fling(_workbenchMessageList(), const Offset(0, 5000), 10000);
    await tester.pumpAndSettle();

    expect(find.text('older prompt'), findsOneWidget);
  });

  testWidgets('leaving conversation before tail returns discards stale page',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _HangingPageConversationRepository();

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_slow_history',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 1,
          title: 'Slow history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow history conversation'));
    await tester.pump();
    expect(repository.pageFetchStarted, isTrue);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    repository.fetchCompleter.complete(ConversationEventPage(
      events: <ConversationEvent>[
        _pagedConversationEvent(
          seq: 1,
          conversationId: 'conv_slow_history',
          text: 'stale history',
        ),
      ],
      oldestSeq: 1,
      newestSeq: 1,
      hasMoreBefore: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('stale history'), findsNothing);
    expect(find.text('Slow history conversation'), findsOneWidget);
  });

  testWidgets('opening existing conversation navigates before history returns',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding',
    );
    final conversationRepository = _HangingFetchConversationRepository();
    final client = DaemonClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore());
    final adapterRepository = CliAdapterRepository(
        delegate: DaemonAdapterRepository(client: client))
      ..replaceFromBootstrap(const <AdapterStatus>[
        AdapterStatus(adapter: 'codex', available: true, status: 'available')
      ]);
    final cachedConversationRepository =
        CachedConversationRepository(delegate: conversationRepository)
          ..replaceFromBootstrap(
            workspaceId: workspace.id,
            conversations: <ConversationSummary>[
              _conversationSummary(
                id: 'conv_slow_history',
                workspaceId: workspace.id,
                status: 'completed',
                sessionBinding: 'confirmed',
                userMessageCount: 1,
                title: 'Slow history conversation',
              ),
            ],
          );
    final runRepository =
        CachedRunRepository(delegate: DaemonRunRepository(client: client))
          ..replaceFromBootstrap(
              workspaceId: workspace.id,
              runs: const <RunSummary>[],
              queue: const <QueueItem>[]);
    final workspaceRepository = DaemonWorkspaceRepository(client: client)
      ..applyBootstrapCatalog(
          selectedWorkspace: workspace,
          workspaces: const <WorkspaceSummary>[workspace]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: CodingWorkbenchPage(
                onBack: () {},
                onSessionListChanged: (_) {},
                openSessionListRequest: 0,
                streamOutput: false,
                expandThinking: false,
                permissionMode: 'default',
                dependencies: WorkbenchDependencies(
                  adapterRepository: adapterRepository,
                  asrModelManager:
                      AsrModelManager(client: client.createAsrModelClient()),
                  conversationRepository: cachedConversationRepository,
                  diagnosticsRepository:
                      DaemonDiagnosticsRepository(client: client),
                  runRepository: runRepository,
                  speechInputServiceBuilder: (_) =>
                      const DisabledSpeechInputService(),
                  workspaceRepository: workspaceRepository,
                )))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow history conversation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(conversationRepository.fetchStarted, isTrue);
    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
  });

  testWidgets(
      'opening stale active conversation waits for history before pending animation',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding',
    );
    final conversationRepository = _HangingFetchConversationRepository();
    final client = DaemonClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore());
    final adapterRepository = CliAdapterRepository(
        delegate: DaemonAdapterRepository(client: client))
      ..replaceFromBootstrap(const <AdapterStatus>[
        AdapterStatus(adapter: 'codex', available: true, status: 'available')
      ]);
    final cachedConversationRepository =
        CachedConversationRepository(delegate: conversationRepository)
          ..replaceFromBootstrap(
            workspaceId: workspace.id,
            conversations: <ConversationSummary>[
              _conversationSummary(
                id: 'conv_slow_history',
                workspaceId: workspace.id,
                status: 'running',
                sessionBinding: 'confirmed',
                userMessageCount: 1,
                title: 'Slow history conversation',
              ),
            ],
          );
    final runRepository =
        CachedRunRepository(delegate: DaemonRunRepository(client: client))
          ..replaceFromBootstrap(
              workspaceId: workspace.id,
              runs: const <RunSummary>[],
              queue: const <QueueItem>[]);
    final workspaceRepository = DaemonWorkspaceRepository(client: client)
      ..applyBootstrapCatalog(
          selectedWorkspace: workspace,
          workspaces: const <WorkspaceSummary>[workspace]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: CodingWorkbenchPage(
                onBack: () {},
                onSessionListChanged: (_) {},
                openSessionListRequest: 0,
                streamOutput: false,
                expandThinking: false,
                permissionMode: 'default',
                dependencies: WorkbenchDependencies(
                  adapterRepository: adapterRepository,
                  asrModelManager:
                      AsrModelManager(client: client.createAsrModelClient()),
                  conversationRepository: cachedConversationRepository,
                  diagnosticsRepository:
                      DaemonDiagnosticsRepository(client: client),
                  runRepository: runRepository,
                  speechInputServiceBuilder: (_) =>
                      const DisabledSpeechInputService(),
                  workspaceRepository: workspaceRepository,
                )))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow history conversation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(conversationRepository.fetchStarted, isTrue);
    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);
    expect(find.text('Running'), findsNothing);
    expect(find.text('Generating reply...'), findsNothing);
    expect(find.text('00:00'), findsNothing);

    conversationRepository.fetchCompleter.complete(<ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_slow_history',
        'type': 'user.message',
        'createdAt': '2026-05-30T00:00:00.000Z',
        'text': 'review code'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_slow_history',
        'type': 'assistant.message',
        'createdAt': '2026-05-30T00:00:01.000Z',
        'text': 'review complete'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_slow_history',
        'type': 'conversation.completed',
        'createdAt': '2026-05-30T00:00:02.000Z'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 4,
        'conversationId': 'conv_slow_history',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-30T00:00:02.000Z',
        'status': 'idle'
      }),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('review complete'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
    expect(find.text('Generating reply...'), findsNothing);
    expect(find.text('00:00'), findsNothing);
  });

  testWidgets(
      'opening active conversation reveals pending animation when history stalls',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding',
    );
    final conversationRepository = _HangingFetchConversationRepository();
    final client = DaemonClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore());
    final adapterRepository = CliAdapterRepository(
        delegate: DaemonAdapterRepository(client: client))
      ..replaceFromBootstrap(const <AdapterStatus>[
        AdapterStatus(adapter: 'codex', available: true, status: 'available')
      ]);
    final cachedConversationRepository =
        CachedConversationRepository(delegate: conversationRepository)
          ..replaceFromBootstrap(
            workspaceId: workspace.id,
            conversations: <ConversationSummary>[
              _conversationSummary(
                id: 'conv_slow_history',
                workspaceId: workspace.id,
                status: 'running',
                sessionBinding: 'confirmed',
                userMessageCount: 1,
                title: 'Slow history conversation',
              ),
            ],
          );
    final runRepository =
        CachedRunRepository(delegate: DaemonRunRepository(client: client))
          ..replaceFromBootstrap(
              workspaceId: workspace.id,
              runs: const <RunSummary>[],
              queue: const <QueueItem>[]);
    final workspaceRepository = DaemonWorkspaceRepository(client: client)
      ..applyBootstrapCatalog(
          selectedWorkspace: workspace,
          workspaces: const <WorkspaceSummary>[workspace]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: CodingWorkbenchPage(
                onBack: () {},
                onSessionListChanged: (_) {},
                openSessionListRequest: 0,
                streamOutput: false,
                expandThinking: false,
                permissionMode: 'default',
                dependencies: WorkbenchDependencies(
                  adapterRepository: adapterRepository,
                  asrModelManager:
                      AsrModelManager(client: client.createAsrModelClient()),
                  conversationRepository: cachedConversationRepository,
                  diagnosticsRepository:
                      DaemonDiagnosticsRepository(client: client),
                  runRepository: runRepository,
                  speechInputServiceBuilder: (_) =>
                      const DisabledSpeechInputService(),
                  workspaceRepository: workspaceRepository,
                )))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow history conversation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(conversationRepository.fetchStarted, isTrue);
    expect(find.text('Running'), findsNothing);
    expect(find.text('00:00'), findsNothing);

    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'workbench lifecycle restarts event subscription after background',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository();
    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void backgroundApp() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }

    void resumeApp() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_lifecycle',
        workspaceId: 'workspace_1',
        status: 'running',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Lifecycle task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Lifecycle task'));
    await pumpUntilWatchCalls(1);

    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    backgroundApp();
    await tester.pump(const Duration(seconds: 5));
    resumeApp();
    await tester.pump();
    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    backgroundApp();
    await tester.pump(const Duration(seconds: 29));
    expect(conversationRepository.cancelCalls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(conversationRepository.cancelCalls, 1);

    resumeApp();
    await pumpUntilWatchCalls(2);
    expect(conversationRepository.watchCalls, 2);
    expect(conversationRepository.afterSeqs, <int>[0, 0]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'workbench lifecycle keeps event subscription in background when enabled',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    await dependencies.data.codingPreferencesRepository
        .setKeepConversationEventsInBackground(true);
    final conversationRepository = _LifecycleConversationRepository();

    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void backgroundApp() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }

    void resumeApp() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_lifecycle_keep',
        workspaceId: 'workspace_1',
        status: 'running',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Keep live task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          codingPreferencesRepository:
              dependencies.data.codingPreferencesRepository,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Keep live task'));
    await pumpUntilWatchCalls(1);

    backgroundApp();
    await tester.pump(const Duration(seconds: 31));
    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    resumeApp();
    await tester.pump();
    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'workbench lifecycle cancels queued background disconnect when enabled',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository();

    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void backgroundApp() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }

    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_lifecycle_toggle',
        workspaceId: 'workspace_1',
        status: 'running',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Toggle live task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          codingPreferencesRepository:
              dependencies.data.codingPreferencesRepository,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Toggle live task'));
    await pumpUntilWatchCalls(1);

    backgroundApp();
    await tester.pump(const Duration(seconds: 5));
    await dependencies.data.codingPreferencesRepository
        .setKeepConversationEventsInBackground(true);
    await tester.pump(const Duration(seconds: 27));

    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'disposing workbench consumes conversation event cancellation failures',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository(
      cancelError: StateError('cancel failed'),
    );

    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_cancel_failure',
        workspaceId: 'workspace_1',
        status: 'running',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Cancel failure task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Cancel failure task'));
    await pumpUntilWatchCalls(1);

    expect(conversationRepository.watchCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(conversationRepository.cancelCalls, 1);
  });

  testWidgets('app update recovery runs on create and resume',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    PackageInfo.setMockInitialValues(
      appName: 'LAN AI CLI Control',
      packageName: 'com.example.lan_ai_cli_control',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final manifest = _widgetAppUpdateManifest();
    final installer = _WidgetAppUpdateInstaller(
      recoveredEvent: const AndroidInstallEvent(
        status: AndroidInstallStatus.pendingUserAction,
        sessionId: 22,
        message: 'Confirm install in Android.',
      ),
    );
    addTearDown(installer.close);
    final downloader = _WidgetAppUpdateDownloader();
    final repository = _WidgetAppUpdateRepository(manifest: manifest);
    final appUpdateViewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: AppUpdateWorkflow(
        repository: repository,
        installerService: installer,
        downloaderService: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    final dependencies = AppDependencies.createDefault();
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_send_existing',
        workspaceId: 'workspace_1',
        status: 'idle',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Follow-up task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel: ({
          required DaemonClient client,
          required ConnectedDataDependencies connectedData,
          required int installedVersionCode,
          required String installedVersionName,
        }) async =>
            appUpdateViewModel,
        createWorkbenchDependencies:
            dependencies.features.createWorkbenchDependencies,
      ),
    );

    Future<void> pumpUntilRecoveryReads(int expected) async {
      for (var attempt = 0;
          attempt < 20 && downloader.readSessionCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilFetches(int expected) async {
      for (var attempt = 0;
          attempt < 20 && repository.fetchLatestCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void resumeAppThroughMain() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        forceAndroidForTesting: true,
      ),
    );
    await pumpUntilRecoveryReads(1);
    await pumpUntilFetches(2);
    await tester.pump();

    expect(downloader.readSessionCalls, 1);
    expect(repository.fetchLatestCalls, 2);
    expect(installer.recoverCalls, 0);

    downloader.installSession = AppUpdateInstallSessionRecord(
      sessionId: 22,
      file: File('ready.apk'),
    );
    resumeAppThroughMain();
    await pumpUntilRecoveryReads(2);
    await pumpUntilFetches(3);
    await tester.pump();

    expect(downloader.readSessionCalls, 2);
    expect(repository.fetchLatestCalls, 3);
    expect(installer.recoverCalls, 1);
    expect(appUpdateViewModel.state.status, AppUpdateStatus.readyToInstall);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('app update auto install waits for foreground after background',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    PackageInfo.setMockInitialValues(
      appName: 'LAN AI CLI Control',
      packageName: 'com.example.lan_ai_cli_control',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final manifest = _widgetAppUpdateManifest();
    final installer = _WidgetAppUpdateInstaller();
    addTearDown(installer.close);
    final readyDir =
        Directory.systemTemp.createTempSync('widget-ready-update-');
    addTearDown(() => readyDir.delete(recursive: true));
    final readyFile = File('${readyDir.path}/ready.apk')
      ..writeAsBytesSync(const <int>[1, 2, 3]);
    final downloader = _WidgetAppUpdateDownloader(
      result: AppUpdateDownloadResult(
        state: AppUpdateDownloadState.readyToInstall,
        file: readyFile,
      ),
    );
    final repository = _WidgetAppUpdateRepository(manifest: manifest);
    final appUpdateViewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: AppUpdateWorkflow(
        repository: repository,
        installerService: installer,
        downloaderService: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    final dependencies = AppDependencies.createDefault();
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel: ({
          required DaemonClient client,
          required ConnectedDataDependencies connectedData,
          required int installedVersionCode,
          required String installedVersionName,
        }) async =>
            appUpdateViewModel,
        createWorkbenchDependencies:
            dependencies.features.createWorkbenchDependencies,
      ),
    );

    Future<void> pumpUntilFetches(int expected) async {
      for (var attempt = 0;
          attempt < 20 && repository.fetchLatestCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
      _MainHarness(
        client: _AdapterRefreshClient(),
        dependencies: testDependencies,
        forceAndroidForTesting: true,
      ),
    );
    await pumpUntilFetches(2);
    await appUpdateViewModel.checkForUpdates();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await appUpdateViewModel.download(installWhenReady: true);

    expect(installer.installCalls, 0);
    expect(appUpdateViewModel.state.status, AppUpdateStatus.readyToInstall);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var attempt = 0;
        attempt < 20 && installer.installCalls < 1;
        attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    expect(installer.installCalls, 1);
    expect(installer.installedPath, readyFile.path);
    expect(appUpdateViewModel.state.status, AppUpdateStatus.installing);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('app update stale recovery keeps ready install state',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    PackageInfo.setMockInitialValues(
      appName: 'LAN AI CLI Control',
      packageName: 'com.example.lan_ai_cli_control',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final manifest = _widgetAppUpdateManifest();
    final installer = _WidgetAppUpdateInstaller(returnNullRecoveryOnce: true);
    addTearDown(installer.close);
    final downloader = _WidgetAppUpdateDownloader()
      ..installSession = AppUpdateInstallSessionRecord(
        sessionId: 22,
        file: File('ready.apk'),
      );
    final repository = _WidgetAppUpdateRepository(manifest: manifest);
    final appUpdateViewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: AppUpdateWorkflow(
        repository: repository,
        installerService: installer,
        downloaderService: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    final dependencies = AppDependencies.createDefault();
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_send_existing',
        workspaceId: 'workspace_1',
        status: 'idle',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Follow-up task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel: ({
          required DaemonClient client,
          required ConnectedDataDependencies connectedData,
          required int installedVersionCode,
          required String installedVersionName,
        }) async =>
            appUpdateViewModel,
        createWorkbenchDependencies:
            dependencies.features.createWorkbenchDependencies,
      ),
    );

    Future<void> pumpUntilRecoveryReads(int expected) async {
      for (var attempt = 0;
          attempt < 20 && downloader.readSessionCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        forceAndroidForTesting: true,
      ),
    );
    await pumpUntilRecoveryReads(1);
    await tester.pump();

    expect(downloader.readSessionCalls, 1);
    expect(installer.recoverCalls, 1);
    expect(repository.fetchLatestCalls, 1);
    expect(appUpdateViewModel.state.status, AppUpdateStatus.readyToInstall);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('sending existing conversation keeps current event subscription',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository();

    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilTextField() async {
      for (var attempt = 0;
          attempt < 20 && find.byType(TextField).evaluate().isEmpty;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilSentText() async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.sentText == null;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_send_existing',
        workspaceId: 'workspace_1',
        status: 'idle',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Follow-up task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Follow-up task'));
    await pumpUntilWatchCalls(1);

    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    await pumpUntilTextField();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'continue');
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await pumpUntilSentText();

    expect(conversationRepository.sentText, 'continue');
    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.controller?.text, isEmpty);
    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'existing conversation send can recover pending animation after daemon disconnect',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository(
      sendError: StateError('Connection refused'),
    );

    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilTextField() async {
      for (var attempt = 0;
          attempt < 20 && find.byType(TextField).evaluate().isEmpty;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_send_existing',
        workspaceId: 'workspace_1',
        status: 'idle',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'Follow-up task',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Follow-up task'));
    await pumpUntilWatchCalls(1);
    await pumpUntilTextField();

    await tester.enterText(find.byType(TextField), 'first retry');
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Running'), findsNothing);
    expect(find.byKey(const ValueKey('workbench-send-prompt-button')),
        findsOneWidget);

    conversationRepository.sentText = null;
    conversationRepository.sendCompleter = Completer<ConversationSummary>();
    await tester.enterText(find.byType(TextField), 'second retry');
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(conversationRepository.sentText, 'second retry');
    final pageState = tester
        .state<CodingWorkbenchPageState>(find.byType(CodingWorkbenchPage));
    expect(pageState.activeConversation?.status, 'running');
    expect(find.text('00:00'), findsOneWidget);
    expect(conversationRepository.sendCompleter!.isCompleted, isFalse);

    conversationRepository.sendCompleter!.complete(_conversationSummary(
      id: 'conv_send_existing',
      workspaceId: 'workspace_1',
      status: 'running',
      sessionBinding: 'confirmed',
      userMessageCount: 2,
    ));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('question suggestion immediately sends an input response',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository(
      events: <ConversationEvent>[
        ConversationEvent.fromJson(const <String, Object?>{
          'seq': 1,
          'conversationId': 'conv_waiting_input',
          'type': 'assistant.question',
          'createdAt': '2026-05-16T00:00:00.000Z',
          'questionId': 'question_api_key',
          'text': 'API Key storage',
          'suggestions': <String>[
            'DPAPI encryption',
            'Keep current behavior',
          ],
        }),
      ],
    );
    const blockingItem = ConversationBlockingItem(
      type: 'input_request',
      questionId: 'question_api_key',
      text: 'API Key storage',
      suggestions: <String>[
        'DPAPI encryption',
        'Keep current behavior',
      ],
    );
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_waiting_input',
        workspaceId: 'workspace_1',
        status: 'waiting_input',
        sessionBinding: 'confirmed',
        userMessageCount: 1,
        title: 'API key review',
        blockingItem: blockingItem,
      ),
    ];
    final client = _AdapterRefreshClient();
    final pageDependencies = dependencies.createMainDependencies(
      client,
      initialData:
          _testSnapshot(conversations: conversations).toDaemonInitialData(),
    );
    final cachedConversationRepository =
        CachedConversationRepository(delegate: conversationRepository)
          ..replaceFromBootstrap(
            workspaceId: 'workspace_1',
            conversations: conversations,
          );
    final directDependencies = WorkbenchDependencies(
      adapterRepository: pageDependencies.connectedData.cliAdapterRepository,
      asrModelManager: pageDependencies.workbenchDependencies.asrModelManager,
      conversationRepository: cachedConversationRepository,
      diagnosticsRepository:
          pageDependencies.connectedData.diagnosticsRepository,
      runRepository: pageDependencies.connectedData.runRepository,
      speechInputServiceBuilder:
          pageDependencies.workbenchDependencies.speechInputServiceBuilder,
      workspaceRepository: pageDependencies.connectedData.workspaceRepository,
      workspaceOpeningUseCase:
          pageDependencies.workbenchDependencies.workspaceOpeningUseCase,
      attachmentPreviewCache:
          pageDependencies.workbenchDependencies.attachmentPreviewCache,
    );

    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilAnswered() async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.answeredText == null;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: CodingWorkbenchPage(
                onBack: () {},
                onSessionListChanged: (_) {},
                openSessionListRequest: 0,
                streamOutput: false,
                expandThinking: false,
                permissionMode: 'default',
                dependencies: directDependencies))));
    await pumpNavigationFrame();

    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('API key review'));
    await pumpNavigationFrame();

    expect(find.text('DPAPI encryption'), findsOneWidget);

    await tester.tap(find.text('DPAPI encryption'));
    await pumpUntilAnswered();

    expect(conversationRepository.answeredQuestionId, 'question_api_key');
    expect(conversationRepository.answeredText, 'DPAPI encryption');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opening short existing conversation keeps transcript near top',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = <ConversationEvent>[
      ConversationEvent.fromJson(<String, Object?>{
        'seq': 1,
        'conversationId': 'conv_short',
        'type': 'user.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': 'short opening prompt',
      }),
      ConversationEvent.fromJson(<String, Object?>{
        'seq': 2,
        'conversationId': 'conv_short',
        'type': 'assistant.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': 'short assistant response',
      }),
    ];
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LazyConversationRepository(messages);
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_short',
        workspaceId: 'workspace_1',
        status: 'completed',
        sessionBinding: 'confirmed',
        userMessageCount: messages.length,
        title: 'Short regression conversation',
      ),
    ];
    final client = _AdapterRefreshClient(conversations: conversations);
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: _cachedConversationRepositoryForWorkbenchTest(
            delegate: conversationRepository,
            conversations: conversations,
          ),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(conversations: conversations),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short regression conversation'));
    await tester.pumpAndSettle();

    final transcriptList = _workbenchMessageList();
    expect(transcriptList, findsOneWidget);
    final scrollTop = tester.getTopLeft(transcriptList).dy;
    final scrollBottom = tester.getBottomLeft(transcriptList).dy;
    final promptTop = tester.getTopLeft(find.text('short opening prompt')).dy;

    expect(promptTop, lessThan(scrollTop + (scrollBottom - scrollTop) * .45));
  });

  testWidgets('new conversation keeps short transcript near top while running',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final conversationRepository = _NewSessionConversationRepository();
    final dependencies = AppDependencies.createDefault();
    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository:
              CachedConversationRepository(delegate: conversationRepository),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-new-button')));
    await tester.pumpAndSettle();

    const prompt = 'Who are you?';
    await tester.enterText(find.byType(TextField).last, prompt);
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(conversationRepository.sentText, prompt);
    expect(conversationRepository.sendCompleter.isCompleted, isFalse);
    final promptMessage = find.descendant(
      of: find.byKey(const ValueKey('workbench-message-0-user')),
      matching: find.text(prompt),
    );
    expect(promptMessage, findsOneWidget);

    final transcriptList = _workbenchMessageList();
    expect(transcriptList, findsOneWidget);
    final scrollTop = tester.getTopLeft(transcriptList).dy;
    final scrollBottom = tester.getBottomLeft(transcriptList).dy;
    final promptTop = tester.getTopLeft(promptMessage).dy;

    expect(promptTop, lessThan(scrollTop + (scrollBottom - scrollTop) * .45));

    conversationRepository.sendCompleter.complete(_conversationSummary(
      id: 'conv_new_running',
      workspaceId: 'workspace_1',
      status: 'completed',
      sessionBinding: 'confirmed',
      userMessageCount: 1,
    ));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('new conversation send completion after dispose is ignored',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final createCompleter = Completer<ConversationSummary>();
    final conversationRepository =
        _NewSessionConversationRepository(createCompleter: createCompleter);
    final dependencies = AppDependencies.createDefault();
    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository:
              CachedConversationRepository(delegate: conversationRepository),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
      ),
    );
    await _pumpNavigationFrame(tester);

    await tester.tap(find.text('Coding'));
    await _pumpNavigationFrame(tester);
    await tester.tap(find.text('Current Project'));
    await _pumpNavigationFrame(tester);
    await tester.tap(find.byKey(const ValueKey('session-new-button')));
    await _pumpNavigationFrame(tester);

    await tester.enterText(
        find.byType(TextField).last, 'Dispose while sending');
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await tester.pump();

    expect(conversationRepository.createdAdapters, <String>['codex']);

    await tester.pumpWidget(const SizedBox.shrink());
    createCompleter.complete(_conversationSummary(
      id: 'conv_new_running',
      workspaceId: 'workspace_1',
      status: 'running',
      sessionBinding: 'pending',
      userMessageCount: 0,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'default permission mode is used by default for new Claude sessions',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppLanguage.storageKey: 'en-US',
    });
    final conversationRepository = _NewSessionConversationRepository();
    final dependencies = AppDependencies.createDefault();
    final client = _AdapterRefreshClient(
      adapters: const <AdapterStatus>[
        AdapterStatus(adapter: 'claude', available: true, status: 'available'),
      ],
    );
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: _testFeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.cliAdapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository:
              CachedConversationRepository(delegate: conversationRepository),
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainHarness(
        client: client,
        dependencies: testDependencies,
      ),
    );
    await _pumpNavigationFrame(tester);

    await tester.tap(find.text('Coding'));
    await _pumpNavigationFrame(tester);
    await tester.tap(find.text('Current Project'));
    await _pumpNavigationFrame(tester);
    await tester.tap(find.byKey(const ValueKey('session-new-button')));
    await _pumpNavigationFrame(tester);

    await tester.enterText(find.byType(TextField).last, 'Check permissions');
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(conversationRepository.createdAdapters, <String>['claude']);
    expect(conversationRepository.createdPermissionModes, <String>['default']);

    conversationRepository.sendCompleter.complete(_conversationSummary(
      id: 'conv_new_running',
      workspaceId: 'workspace_1',
      status: 'completed',
      sessionBinding: 'confirmed',
      userMessageCount: 1,
    ));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('slash command menu filters by command text only',
      (WidgetTester tester) async {
    final catalog = _slashCommandCatalogRepository(
      const <String, List<SlashCommand>>{
        'codex': <SlashCommand>[
          SlashCommand(command: '/compact', description: 'summarize context'),
          SlashCommand(command: '/code-review', description: 'review changes'),
          SlashCommand(command: '/fast', description: 'contains co in details'),
        ],
      },
    );

    await _pumpWorkbenchForSlashCommands(tester, catalog);
    await _openNewSlashCommandConversation(tester);
    await tester.enterText(find.byType(TextField).last, '/co');
    await tester.pumpAndSettle();

    expect(find.text('/code-review'), findsOneWidget);
    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('/fast'), findsNothing);

    final selectedRow = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('slash-command-row-/code-review')),
    );
    final selectedDecoration = selectedRow.decoration as BoxDecoration;
    expect(selectedDecoration.color, isNot(Colors.transparent));
  });

  testWidgets('slash command menu inserts selected command at cursor',
      (WidgetTester tester) async {
    final catalog = _slashCommandCatalogRepository(
      const <String, List<SlashCommand>>{
        'codex': <SlashCommand>[
          SlashCommand(command: '/compact', description: 'summarize context'),
          SlashCommand(command: '/code-review', description: 'review changes'),
        ],
      },
    );

    await _pumpWorkbenchForSlashCommands(tester, catalog);
    await _openNewSlashCommandConversation(tester);
    final input = find.byType(TextField).last;
    await tester.tap(input);
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(input).controller!;
    controller.value = const TextEditingValue(
      text: 'please /CO now',
      selection: TextSelection.collapsed(offset: 10),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('/compact'));
    await tester.pumpAndSettle();

    expect(controller.text, 'please /compact  now');
    expect(controller.selection.baseOffset, 'please /compact '.length);
  });

  testWidgets('slash command filtering does not move composer text field',
      (WidgetTester tester) async {
    final catalog = _slashCommandCatalogRepository(
      const <String, List<SlashCommand>>{
        'codex': <SlashCommand>[
          SlashCommand(command: '/compact', description: 'summarize context'),
          SlashCommand(command: '/code-review', description: 'review changes'),
          SlashCommand(command: '/config', description: 'edit config'),
          SlashCommand(command: '/continue', description: 'continue session'),
          SlashCommand(command: '/context', description: 'show context'),
          SlashCommand(command: '/copy', description: 'copy output'),
        ],
      },
    );

    await _pumpWorkbenchForSlashCommands(tester, catalog);
    await _openNewSlashCommandConversation(tester);
    final input = find.byType(TextField).last;
    await tester.enterText(input, '/co');
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(input);

    await tester.enterText(input, '/comp');
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(input);

    expect(after, before);
  });

  testWidgets('slash command menu hides when composer focus is lost',
      (WidgetTester tester) async {
    final catalog = _slashCommandCatalogRepository(
      const <String, List<SlashCommand>>{
        'codex': <SlashCommand>[
          SlashCommand(command: '/compact', description: 'summarize context'),
        ],
      },
    );

    await _pumpWorkbenchForSlashCommands(tester, catalog);
    await _openNewSlashCommandConversation(tester);
    final input = find.byType(TextField).last;
    await tester.enterText(input, '/');
    await tester.pumpAndSettle();

    expect(find.text('/compact'), findsOneWidget);

    FocusScope.of(tester.element(input)).unfocus();
    await tester.pumpAndSettle();

    expect(find.text('/compact'), findsNothing);
  });

  testWidgets('slash command catalog loads once when entering conversation',
      (WidgetTester tester) async {
    final catalog = _RecordingSlashCommandCatalogRepository(
      const <String, List<SlashCommand>>{
        'codex': <SlashCommand>[
          SlashCommand(command: '/model', description: 'choose model'),
        ],
      },
    );

    await _pumpWorkbenchForSlashCommands(tester, catalog);
    expect(catalog.loadCalls, isEmpty);

    await _openNewSlashCommandConversation(tester);
    await tester.enterText(find.byType(TextField).last, '/');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '/m');
    await tester.pumpAndSettle();

    expect(
        catalog.loadCalls.where((adapter) => adapter == 'codex'), hasLength(1));
    expect(find.text('/model'), findsOneWidget);
  });

  testWidgets(
      'slash command catalog preloads all adapters on conversation entry',
      (WidgetTester tester) async {
    final catalog = _RecordingSlashCommandCatalogRepository(
      const <String, List<SlashCommand>>{
        'codex': <SlashCommand>[
          SlashCommand(command: '/model', description: 'codex model'),
        ],
        'claude': <SlashCommand>[
          SlashCommand(command: '/compact', description: 'claude compact'),
        ],
      },
    );

    await _pumpWorkbenchForSlashCommands(
      tester,
      catalog,
      adapters: const <AdapterStatus>[
        AdapterStatus(adapter: 'codex', available: true, status: 'available'),
        AdapterStatus(adapter: 'claude', available: true, status: 'available'),
      ],
    );
    await _openNewSlashCommandConversation(tester);

    await tester.tap(find.byKey(const ValueKey('composer-cli-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('codex').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '/mo');
    await tester.pumpAndSettle();

    expect(
        catalog.loadCalls.where((adapter) => adapter == 'codex'), hasLength(1));
    expect(catalog.loadCalls.where((adapter) => adapter == 'claude'),
        hasLength(1));
    expect(find.text('/model'), findsOneWidget);
    expect(find.text('/compact'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('composer-cli-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('claude').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '/co');
    await tester.pumpAndSettle();

    expect(
        catalog.loadCalls.where((adapter) => adapter == 'codex'), hasLength(1));
    expect(catalog.loadCalls.where((adapter) => adapter == 'claude'),
        hasLength(1));
    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('/model'), findsNothing);
  });

  testWidgets('connected app preloads adapters before new session',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _AdapterRefreshClient();

    await tester.pumpWidget(_MainHarness(client: client));
    await tester.pumpAndSettle();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-new-button')));
    await tester.pumpAndSettle();

    expect(find.text('codex'), findsWidgets);
    expect(find.text('No available CLI adapter'), findsNothing);

    await tester.tap(find.text('codex').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('adapter-picker-sheet')), findsOneWidget);
    expect(find.text('synthetic-jsonl'), findsNothing);
    expect(find.text('synthetic-text'), findsNothing);
  });

  testWidgets('coding keeps workspace UI visible during adapter preload',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _PendingAdapterClient();

    await tester.pumpWidget(_MainHarness(client: client));
    await tester.pump();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Coding'));
    await tester.pump();

    expect(find.text('Loading CLI...'), findsNothing);
    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
    expect(find.text('New Session'), findsNothing);
    expect(client.listAdaptersCalls, 1);

    client.completeWithAdapters();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
  });

  testWidgets('coding adapter preload failure can retry',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _PendingAdapterClient();

    await tester.pumpWidget(_MainHarness(client: client));
    await tester.pump();
    client.completeWithError();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load CLI adapters'), findsNothing);
    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);

    client.resetCompleter();
    await tester.tap(find.text('Current Project').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.workbenchAdapterUnavailableTitle), findsOneWidget);

    await tester.tap(find.text(l10n.workbenchAdapterRetryAction));
    await tester.pump();

    expect(find.text(l10n.workbenchAdapterLoadingTitle), findsOneWidget);
    expect(client.listAdaptersCalls, 2);

    client.completeWithAdapters();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.text(l10n.workbenchAdapterUnavailableTitle), findsNothing);
    expect(find.text(l10n.workbenchAdapterLoadingTitle), findsNothing);
  });

  testWidgets('coding gate ignores command catalog failure after adapters load',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _PendingAdapterClient()..completeCatalogWithError = true;

    await tester.pumpWidget(_MainHarness(client: client));
    await tester.pump();

    final harnessState =
        tester.state<_MainHarnessState>(find.byType(_MainHarness));
    final commandCatalogRepository = harnessState
        ._pageDependencies.sessionScope.repositories.commandCatalogRepository;
    await expectLater(
      commandCatalogRepository.load(),
      throwsA(isA<StateError>()),
    );
    expect(commandCatalogRepository.error, isA<StateError>());

    client.completeWithAdapters();
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load CLI adapters'), findsNothing);
    expect(find.byType(CodingPage), findsOneWidget);
  });

  testWidgets('adapter picker scrolls on compact screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: AdapterPickerSheet(
                selected: 'codex',
                onSelected: (_) {},
                adapters: const <AdapterStatus>[
                  AdapterStatus(
                      adapter: 'claude',
                      available: true,
                      status: 'available',
                      version: '2.1.112 (Claude Code)'),
                  AdapterStatus(
                      adapter: 'codex',
                      available: true,
                      status: 'available',
                      version: 'codex-cli 0.128.0'),
                  AdapterStatus(
                      adapter: 'opencode',
                      available: true,
                      status: 'available',
                      version: '0.9.0'),
                  AdapterStatus(
                      adapter: 'custom-a',
                      available: true,
                      status: 'available',
                      version: '1.0.0'),
                  AdapterStatus(
                      adapter: 'custom-b',
                      available: true,
                      status: 'available',
                      version: '1.0.0'),
                ]))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('adapter-picker-sheet')), findsOneWidget);
  });

  testWidgets('model picker shows fallback row when no model list exists',
      (WidgetTester tester) async {
    String? selected = 'unchanged';
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: null,
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[]))));

    expect(find.byKey(const ValueKey('model-picker-sheet')), findsOneWidget);
    expect(find.text('Default model'), findsOneWidget);
    expect(find.text('Uses the CLI configured default.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-default')));

    expect(selected, isNull);
  });

  testWidgets('open workbench model picker reflects adapter refresh',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AIProject\vibe-coding',
    );
    final client = DaemonClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore());
    final adapterRepository =
        CliAdapterRepository(delegate: DaemonAdapterRepository(client: client))
          ..replaceFromBootstrap(const <AdapterStatus>[
            AdapterStatus(
              adapter: 'codex-app-server',
              available: true,
              status: 'available',
              canSelectModel: true,
              models: <AdapterModelOption>[],
            )
          ]);
    final conversationRepository = CachedConversationRepository(
        delegate: _NewSessionConversationRepository())
      ..replaceFromBootstrap(
        workspaceId: workspace.id,
        conversations: const <ConversationSummary>[],
      );
    final runRepository =
        CachedRunRepository(delegate: DaemonRunRepository(client: client))
          ..replaceFromBootstrap(
            workspaceId: workspace.id,
            runs: const <RunSummary>[],
            queue: const <QueueItem>[],
          );
    final workspaceRepository = DaemonWorkspaceRepository(client: client)
      ..applyBootstrapCatalog(
        selectedWorkspace: workspace,
        workspaces: const <WorkspaceSummary>[workspace],
      );

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: CodingWorkbenchPage(
                onBack: () {},
                onSessionListChanged: (_) {},
                openSessionListRequest: 0,
                streamOutput: false,
                expandThinking: false,
                permissionMode: 'default',
                dependencies: WorkbenchDependencies(
                  adapterRepository: adapterRepository,
                  asrModelManager:
                      AsrModelManager(client: client.createAsrModelClient()),
                  conversationRepository: conversationRepository,
                  diagnosticsRepository:
                      DaemonDiagnosticsRepository(client: client),
                  runRepository: runRepository,
                  speechInputServiceBuilder: (_) =>
                      const DisabledSpeechInputService(),
                  workspaceRepository: workspaceRepository,
                )))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-new-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('composer-model-pill')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('model-option-default')), findsOneWidget);

    adapterRepository.replaceFromBootstrap(const <AdapterStatus>[
      AdapterStatus(
        adapter: 'codex-app-server',
        available: true,
        status: 'available',
        canSelectModel: true,
        selectedModel: 'gpt-5.5',
        models: <AdapterModelOption>[
          AdapterModelOption(
              id: 'gpt-5.5',
              label: 'gpt-5.5',
              source: 'codex_config',
              selected: true),
        ],
      )
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('model-option-default')), findsNothing);
    expect(find.byKey(const ValueKey('model-option-gpt-5.5')), findsOneWidget);
    expect(find.text('gpt-5.5'), findsWidgets);
  });

  testWidgets('model picker renders model source labels',
      (WidgetTester tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: 'gpt-5-codex',
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[
                  AdapterModelOption(
                      id: 'gpt-5-codex',
                      label: 'GPT-5 Codex',
                      source: 'codex_config',
                      selected: true),
                  AdapterModelOption(
                      id: 'gpt-5-catalog',
                      label: 'GPT-5 Catalog',
                      source: 'codex_catalog',
                      selected: false),
                  AdapterModelOption(
                      id: 'gpt-5-app-server',
                      label: 'GPT-5 App Server',
                      source: 'app_server',
                      selected: false),
                  AdapterModelOption(
                      id: 'claude-sonnet',
                      label: 'Claude Sonnet',
                      source: 'claude_config',
                      selected: false),
                  AdapterModelOption(
                      id: 'cli-default',
                      label: 'CLI Default',
                      source: 'cli_default',
                      selected: false),
                  AdapterModelOption(
                      id: 'mystery',
                      label: 'Mystery',
                      source: 'future_source',
                      selected: false),
                ]))));

    expect(find.text('GPT-5 Codex'), findsOneWidget);
    expect(find.text('Codex config'), findsOneWidget);
    expect(find.text('Codex catalog'), findsOneWidget);
    expect(find.text('App Server'), findsOneWidget);
    expect(find.text('Claude config'), findsOneWidget);
    expect(find.text('CLI default'), findsOneWidget);
    expect(find.text('Unknown source'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-claude-sonnet')));

    expect(selected, 'claude-sonnet');
  });

  testWidgets('model picker shows pending update and disables selections',
      (WidgetTester tester) async {
    String? selected = 'unchanged';
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: 'gpt-5-codex',
                updating: true,
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[
                  AdapterModelOption(
                      id: 'gpt-5-codex',
                      label: 'GPT-5 Codex',
                      source: 'codex_config',
                      selected: true),
                  AdapterModelOption(
                      id: 'claude-sonnet',
                      label: 'Claude Sonnet',
                      source: 'claude_config',
                      selected: false),
                ]))));

    expect(find.byKey(const ValueKey('model-picker-updating')), findsOneWidget);
    expect(find.text('Updating model...'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-claude-sonnet')));

    expect(selected, 'unchanged');
  });

  testWidgets('model picker displays model update errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: null,
                errorText: 'Model backend rejected this model.',
                onSelected: (_) {},
                models: const <AdapterModelOption>[]))));

    expect(find.byKey(const ValueKey('model-picker-error')), findsOneWidget);
    expect(find.text('Model backend rejected this model.'), findsOneWidget);
  });

  testWidgets('model picker keeps unsupported errors visible while disabled',
      (WidgetTester tester) async {
    String? selected = 'unchanged';
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: 'gpt-5-codex',
                selectionDisabled: true,
                errorText:
                    'Update the desktop daemon to change models in existing '
                    'conversations.',
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[
                  AdapterModelOption(
                      id: 'gpt-5-codex',
                      label: 'GPT-5 Codex',
                      source: 'codex_config',
                      selected: true),
                  AdapterModelOption(
                      id: 'claude-sonnet',
                      label: 'Claude Sonnet',
                      source: 'claude_config',
                      selected: false),
                ]))));

    expect(find.byKey(const ValueKey('model-picker-error')), findsOneWidget);
    expect(
        find.text('Update the desktop daemon to change models in existing '
            'conversations.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-claude-sonnet')));

    expect(selected, 'unchanged');
  });

  testWidgets('tapping current project opens workspace session list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.textContaining(RegExp('New Session|\u65b0\u5efa\u4f1a\u8bdd')),
        findsOneWidget);
    expect(find.text('Select workspace for this coding session'), findsNothing);
  });

  testWidgets('notification tap for missing workspace stays on workspace list',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final client = _AdapterRefreshClient();
    final pageDependencies = dependencies.createMainDependencies(
      client,
      initialData: _testSnapshot().toDaemonInitialData(),
    );
    final workbenchKey = GlobalKey<CodingWorkbenchPageState>();

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: CodingWorkbenchPage(
                key: workbenchKey,
                onBack: () {},
                onSessionListChanged: (_) {},
                openSessionListRequest: 0,
                streamOutput: false,
                expandThinking: false,
                permissionMode: 'default',
                dependencies: pageDependencies.workbenchDependencies))));
    await tester.pumpAndSettle();

    final opened =
        await workbenchKey.currentState!.openConversationFromNotification(
      workspaceId: 'workspace_missing',
      conversationId: 'conv_missing',
    );
    await tester.pumpAndSettle();

    expect(opened, isFalse);
    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning to coding tab from Codex shows workspace list',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
  });

  testWidgets('created workspace remains visible after tab switch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    const initialWorkspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding',
    );
    const createdWorkspace = WorkspaceSummary(
      id: 'workspace_created',
      name: 'Created Project',
      path: r'D:\created',
    );
    final client = _WorkspaceCreationClient(
      initialWorkspaces: const <WorkspaceSummary>[initialWorkspace],
      createdWorkspace: createdWorkspace,
    );

    await tester.pumpWidget(_MainHarness(client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    final addWorkspace = find.descendant(
      of: find.byKey(const ValueKey('workspace-list')),
      matching: find.byIcon(Icons.add_rounded),
    );
    await tester.tap(addWorkspace);
    await tester.pumpAndSettle();

    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), r'D:\created');
    await tester.enterText(inputs.at(1), 'Created Project');
    await tester.tap(find.text('Create and use'));
    await tester.pumpAndSettle();

    expect(client.createWorkspaceCalls, 1);
    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.text('Created Project'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Created Project'), findsOneWidget);

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Created Project'), findsOneWidget);
  });

  testWidgets('system back walks coding nested navigator before app exit',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-new-button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.byType(BottomNav), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
  });

  testWidgets('system back returns conversation to sessions',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-new-button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-workbench-detail')), findsNothing);
  });

  testWidgets('new coding session title uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.textContaining(RegExp('New Session|\u65b0\u5efa\u4f1a\u8bdd')));
    await tester.pumpAndSettle();

    expect(find.text('新的编码会话'), findsOneWidget);
    expect(find.text('New coding session'), findsNothing);
  });

  testWidgets('session list shows only selected workspace sessions',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildWorkspaceScopedSessionPreview());
    await tester.pumpAndSettle();

    expect(find.textContaining('current-1'), findsWidgets);
    expect(find.textContaining('other-1'), findsNothing);
  });

  testWidgets('session list localizes running session badge',
      (WidgetTester tester) async {
    const workspace = WorkspaceSummary(
        id: 'workspace_1',
        name: 'Current Project',
        path: r'D:\AiProject\vibe-coding');
    await tester.pumpWidget(MaterialApp(
      locale: theme.zhHansCnLocale,
      supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: theme.appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: theme.appFontFallback,
          useMaterial3: true),
      home: Scaffold(
        backgroundColor: theme.bg,
        body: CodingSessionListPage(
          items: const <SessionItem>[
            SessionItem(
              run: RunSummary(
                id: 'run_live',
                tool: 'codex',
                workspaceId: 'workspace_1',
                status: 'running',
              ),
            ),
          ],
          currentWorkspace: workspace,
          onNewSession: () {},
          onSelectItem: (_) {},
          onBackToWorkspaces: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('实时'), findsOneWidget);
    expect(find.text('live'), findsNothing);
  });

  testWidgets('session list prefers stable conversation title over uuid labels',
      (WidgetTester tester) async {
    const workspace = WorkspaceSummary(
        id: 'workspace_1',
        name: 'Current Project',
        path: r'D:\AiProject\vibe-coding');
    final conversation = _conversationSummary(
      id: 'conv_019e4d98',
      workspaceId: workspace.id,
      status: 'interrupted',
      cliSessionId: '019e4d98-348d-7840-b8ef-9b2dda2c1235',
      sessionBinding: 'confirmed',
      userMessageCount: 1,
      title: 'Fix mobile title rendering',
    );
    await tester.pumpWidget(MaterialApp(
      locale: theme.zhHansCnLocale,
      supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: theme.appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: theme.appFontFallback,
          useMaterial3: true),
      home: Scaffold(
        backgroundColor: theme.bg,
        body: CodingSessionListPage(
          items: <SessionItem>[
            SessionItem(
              run: const RunSummary(
                id: 'conv_019e4d98',
                tool: 'codex',
                workspaceId: 'workspace_1',
                status: 'interrupted',
                cliSessionId: '019e4d98-348d-7840-b8ef-9b2dda2c1235',
              ),
              conversation: conversation,
            ),
          ],
          currentWorkspace: workspace,
          onNewSession: () {},
          onSelectItem: (_) {},
          onBackToWorkspaces: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fix mobile title rendering'), findsOneWidget);
    expect(find.text('Codex 会话 019e4d98'), findsNothing);
  });

  testWidgets('missing selected workspace falls back to workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildMissingWorkspaceFallbackPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Stale Workspace'), findsNothing);
  });

  test('newly created coding runs appear before snapshot runs', () {
    const created = RunSummary(
        id: 'run_created',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'running');
    const staleCreated = RunSummary(
        id: 'run_created',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'completed');
    const older = RunSummary(
        id: 'run_older',
        tool: 'codex',
        workspaceId: 'workspace_1',
        status: 'completed');

    expect(
        debugMergeSessionRunIds(const <RunSummary>[created],
            const <RunSummary>[staleCreated, older]),
        const <String>['run_created', 'run_older']);
  });

  test('persisted coding conversations appear after Flutter restart', () {
    const local = RunSummary(
        id: 'conv_local',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'running');
    const persisted = ConversationSummary(
        id: 'conv_persisted',
        workspaceId: 'workspace_1',
        adapter: 'claude',
        status: 'interrupted',
        capabilities: ConversationCapabilities(
            longLivedProcess: true,
            waitingInput: true,
            waitingApproval: true,
            resume: true,
            partialOutput: true),
        createdAt: '2026-05-03T00:00:00.000Z',
        updatedAt: '2026-05-03T00:00:01.000Z',
        cliSessionId: 'claude-session');
    const emptyDraft = ConversationSummary(
        id: 'conv_empty',
        workspaceId: 'workspace_1',
        adapter: 'claude',
        status: 'idle',
        capabilities: ConversationCapabilities(
            longLivedProcess: true,
            waitingInput: true,
            waitingApproval: true,
            resume: true,
            partialOutput: true),
        createdAt: '2026-05-03T00:00:00.000Z',
        updatedAt: '2026-05-03T00:00:01.000Z');
    const legacyRun = RunSummary(
        id: 'run_legacy',
        tool: 'codex',
        workspaceId: 'workspace_1',
        status: 'completed');

    expect(
        debugMergeSessionIds(
            const <RunSummary>[local],
            const <ConversationSummary>[persisted, emptyDraft],
            const <RunSummary>[legacyRun]),
        const <String>['conv_local', 'conv_persisted', 'run_legacy']);
  });

  test(
      'cancelled failed and interrupted conversations stay conversation backed in session list',
      () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_cancelled',
        workspaceId: 'workspace_1',
        status: 'cancelled',
        cliSessionId: 'claude-session-1',
        sessionBinding: 'confirmed',
        capabilities: capabilities,
      ),
      _conversationSummary(
        id: 'conv_failed',
        workspaceId: 'workspace_1',
        status: 'failed',
        cliSessionId: 'claude-session-2',
        sessionBinding: 'confirmed',
        capabilities: capabilities,
      ),
      _conversationSummary(
        id: 'conv_interrupted',
        workspaceId: 'workspace_1',
        status: 'interrupted',
        sessionBinding: 'unknown',
        userMessageCount: 1,
        capabilities: capabilities,
      ),
    ];

    final items = mergeSessionItems(
      const <String, SessionItem>{},
      conversations,
      const <RunSummary>[],
    );

    expect(
      items.map((item) => item.id),
      <String>['conv_cancelled', 'conv_failed', 'conv_interrupted'],
    );
    expect(items.every((item) => item.conversation != null), isTrue);
    expect(items.last.run.status, 'interrupted');
  });

  test('idle empty draft without messages remains hidden from session list',
      () {
    final items = mergeSessionItems(
      const <String, SessionItem>{},
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_empty',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'unknown',
          userMessageCount: 0,
        ),
      ],
      const <RunSummary>[],
    );

    expect(items, isEmpty);
  });

  test('approval response restarts events only for active conversations', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const running = ConversationSummary(
      id: 'conv_running',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:01.000Z',
    );
    const idle = ConversationSummary(
      id: 'conv_idle',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'idle',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:01.000Z',
    );

    expect(debugShouldRestartEventsAfterApproval(running), isTrue);
    expect(debugShouldRestartEventsAfterApproval(idle), isFalse);
  });

  test('historical sessions do not count as explicit workspace selection', () {
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: false,
          activeRunId: null,
          hasLocalSessions: true,
        ),
        isFalse);
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: true,
          activeRunId: null,
          hasLocalSessions: false,
        ),
        isTrue);
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: false,
          activeRunId: 'conv_1',
          hasLocalSessions: false,
        ),
        isTrue);
  });

  test('approval cards only show the current blocking approval', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'waiting_approval',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
      blockingItem: ConversationBlockingItem(
        type: 'approval_request',
        approvalId: 'ap2',
        toolName: 'Bash',
        summary: 'python intro.py',
      ),
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'ap1',
        'toolName': 'Write',
        'summary': r'C:\Users\W2830\intro.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'ap2',
        'toolName': 'Bash',
        'summary': r'python intro.py'
      },
    ];

    expect(debugVisibleApprovalIdsForConversation(events, conversation),
        const <String>['ap2']);
  });

  testWidgets('running composer shows stop action instead of send',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildRunningComposerPreview());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('new coding session workspace preview shows workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildNewSessionWorkspacePickerPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
  });

  test('workspace list presentation deduplicates duplicate paths', () {
    final visible = dedupeWorkspacesByPath(const <WorkspaceSummary>[
      WorkspaceSummary(
          id: 'workspace_a', name: 'Agent', path: r'D:\AiProject\Agent'),
      WorkspaceSummary(
          id: 'workspace_b', name: 'Agent copy', path: r'D:\AiProject\Agent'),
      WorkspaceSummary(
          id: 'workspace_trailing',
          name: 'Agent trailing',
          path: 'D:\\AiProject\\Agent\\'),
      WorkspaceSummary(
          id: 'workspace_case',
          name: 'Agent case',
          path: r'd:\aiproject\agent'),
      WorkspaceSummary(
          id: 'workspace_c', name: 'cli-ui', path: r'D:\AiProject\cli-ui'),
    ]);

    expect(visible.map((workspace) => workspace.id),
        const <String>['workspace_a', 'workspace_c']);
  });

  testWidgets('workspace search placeholder uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildNewSessionWorkspacePickerPreview());
    await tester.pumpAndSettle();

    expect(find.text('搜索会话、命令或文件路径...'), findsOneWidget);
    expect(find.text('Search sessions, commands, file paths...'), findsNothing);
  });

  testWidgets('add workspace sheet uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: AddWorkspaceSheet(
                workspaceRepository: _WidgetTestWorkspaceRepository()))));

    expect(find.text('添加工作区'), findsOneWidget);
    expect(find.text('浏览'), findsOneWidget);
    expect(find.text('选择或输入文件夹路径'), findsOneWidget);
    expect(find.text('名称（可选）'), findsOneWidget);
    expect(find.text('创建并使用'), findsOneWidget);
    expect(find.text('Add workspace'), findsNothing);
    expect(find.text('Browse'), findsNothing);
  });

  testWidgets('directory browser localizes labels and returns to drive list',
      (WidgetTester tester) async {
    final repository = _WidgetTestWorkspaceRepository(
      roots: const <DirectoryEntrySummary>[
        DirectoryEntrySummary(name: r'D:\', path: r'D:\'),
      ],
      directories: const <String, DirectoryListing>{
        r'D:\': DirectoryListing(
          path: r'D:\',
          directories: <DirectoryEntrySummary>[
            DirectoryEntrySummary(name: 'AIProject', path: r'D:\AIProject'),
          ],
        ),
      },
    );

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: DirectoryBrowserSheet.forWorkspaceRepository(
                repository: repository))));
    await tester.pumpAndSettle();

    expect(find.text('选择文件夹'), findsOneWidget);
    expect(find.text('选择磁盘或根目录后继续进入文件夹'), findsOneWidget);
    expect(find.text('Choose folder'), findsNothing);

    await tester.tap(find.text(r'D:\').first);
    await tester.pumpAndSettle();

    expect(find.text('选择当前'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('选择磁盘或根目录后继续进入文件夹'), findsOneWidget);
    expect(find.text('选择当前'), findsNothing);
  });

  testWidgets('completed command card collapses details by default',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCompletedCommandCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('npm run lint && npm test'), findsWidgets);
    expect(find.textContaining('执行 1 条命令'), findsNothing);
    expect(find.textContaining('cwd resolved'), findsNothing);
    expect(find.textContaining('2.1s'), findsNothing);
    expect(find.byKey(const ValueKey('tool-status-ok')), findsOneWidget);

    await tester.tap(find.text('npm run lint && npm test').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('执行 1 条命令'), findsOneWidget);
    expect(find.textContaining('cwd resolved'), findsOneWidget);
    expect(find.textContaining('2.1s'), findsOneWidget);
  });

  testWidgets('command output opens a full detail sheet',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        buildConversationCommandCardPreview(expandToolDetails: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hello from intro').first);
    await tester.pumpAndSettle();

    expect(find.text('输出详情'), findsOneWidget);
    expect(find.byTooltip('复制全文'), findsOneWidget);
    expect(find.text('hello from intro'), findsWidgets);
  });

  testWidgets('command preview wraps long text but defaults to two lines',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longCommand =
        r'"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -Command "Get-ChildItem D:\AIProject\vibe-coding\mobile\lib\src\ui\features\workbench\workbench_event_cards.dart"';

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'command', 'command_execution', longCommand,
                        completed: true,
                        duration: Duration(milliseconds: 2550)),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false,
                    expandToolDetails: true)))));
    await tester.pumpAndSettle();

    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.data == longCommand &&
            widget.maxLines == 2 &&
            widget.overflow == TextOverflow.ellipsis),
        findsOneWidget);

    await tester.tap(find.text(longCommand).last);
    await tester.pumpAndSettle();

    expect(find.text('命令详情'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.data == longCommand &&
            widget.maxLines == null),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal),
        findsNothing);
  });

  testWidgets(
      'large command output defaults to two-line preview and opens details',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        buildLargeOutputCommandCardPreview(expandToolDetails: true));
    await tester.pumpAndSettle();

    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.data?.startsWith('line 0') == true &&
            widget.maxLines == 2 &&
            widget.overflow == TextOverflow.ellipsis),
        findsOneWidget);
    expect(find.text('Show more'), findsNothing);

    await tester.tap(find.textContaining('line 0'));
    await tester.pumpAndSettle();

    expect(find.text('Output details'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.data?.contains('line 204') == true),
        findsOneWidget);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets(
      'pending sentinel is compact and does not show adapter or action list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildPendingSentinelPreview());
    await tester.pump();

    expect(find.text('claude running'), findsNothing);
    expect(find.text('Claude requesting'), findsNothing);
  });

  testWidgets('pending sentinel shows elapsed running time',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildPendingSentinelPreview());
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.text('00:02'), findsOneWidget);
  });

  testWidgets('pending sentinel sweeps localized waiting text',
      (WidgetTester tester) async {
    final zh = lookupAppLocalizations(theme.zhHansCnLocale);
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: PendingSentinel(
                    adapter: 'claude',
                    statusText: zh.workbenchPendingWaitingNextEvent)))));
    await tester.pump();

    expect(
        find.byWidgetPredicate((widget) =>
            widget is SweepingStatusText && widget.text == '酝酿中...'),
        findsOneWidget);
    expect(find.text('正在等待下一个事件...'), findsNothing);
    expect(find.byType(SweepingStatusText), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));

    final progressFinder =
        find.byKey(const ValueKey('workbench-pending-status-sweep-progress'));
    expect(progressFinder, findsOneWidget);
    final progress = tester.getSize(progressFinder).width;
    expect(progress, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 900));

    expect(tester.getSize(progressFinder).width, greaterThan(progress));

    await tester.pump(const Duration(seconds: 5));

    expect(
        find.byWidgetPredicate((widget) =>
            widget is SweepingStatusText && widget.text == '正在推演下一步...'),
        findsOneWidget);
  });

  testWidgets('pending sentinel resumes elapsed time from stable start',
      (WidgetTester tester) async {
    var now = DateTime.utc(2026, 5, 25, 12);
    final startedAt = now.subtract(const Duration(seconds: 65));
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: PendingSentinel(
                  adapter: 'claude',
                  statusText: 'Receiving CLI output...',
                  startedAt: startedAt,
                  now: () => now,
                )))));
    await tester.pump();

    expect(find.text('01:05'), findsOneWidget);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('01:07'), findsOneWidget);
  });

  testWidgets('file change card shows edited path and diff preview',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'file_change',
                        'File changes',
                        'File changed: updated mobile/test/example_test.dart',
                        fileChanges: <ConversationFileChange>[
                          ConversationFileChange(
                              path: 'mobile/test/example_test.dart',
                              kind: 'update',
                              diff:
                                  '@@ -1,3 +1,3 @@\n-  old expectation\n+  new expectation')
                        ]),
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('Edited example_test.dart'), findsOneWidget);
    expect(find.text('mobile/test/example_test.dart'), findsOneWidget);
    expect(find.text('@@ -1,3 +1,3 @@'), findsOneWidget);
    expect(find.text('  old expectation'), findsOneWidget);
    expect(find.text('  new expectation'), findsOneWidget);
    expect(find.text('System notice'), findsNothing);
  });

  testWidgets('file change card renders patch transcript gutters and stats',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage('file_change',
                        'File changes', 'File changed: updated lib/main.dart',
                        fileChanges: <ConversationFileChange>[
                          ConversationFileChange(
                              path: 'lib/main.dart', kind: 'update', diff: '''
diff --git a/lib/main.dart b/lib/main.dart
@@ -7,3 +7,3 @@ void main() {
   final app = App();
-  runApp(app);
+  runApp(const App());
 }
''')
                        ]),
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('Edited main.dart'), findsOneWidget);
    expect(find.text('+1 -1'), findsOneWidget);
    expect(find.text('@@ -7,3 +7,3 @@ void main() {'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('8'), findsNWidgets(2));
    expect(find.text('9'), findsOneWidget);
    expect(find.text('  runApp(app);'), findsOneWidget);
    expect(find.text('  runApp(const App());'), findsOneWidget);
  });

  testWidgets('file change card truncates long diffs until expanded',
      (WidgetTester tester) async {
    final diff = StringBuffer('@@ -1,90 +1,90 @@\n');
    for (var i = 1; i <= 85; i += 1) {
      diff.writeln(' line $i');
    }

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: WorkbenchMessageCard(
                        message: WorkbenchMessage('file_change', 'File changes',
                            'File changed: updated lib/long.dart',
                            fileChanges: <ConversationFileChange>[
                              ConversationFileChange(
                                  path: 'lib/long.dart',
                                  kind: 'update',
                                  diff: diff.toString())
                            ]),
                        onApproval: _noopApproval,
                        onSuggestion: _noopString,
                        expandThinking: false))))));
    await tester.pumpAndSettle();

    expect(find.text('line 80'), findsOneWidget);
    expect(find.text('line 81'), findsNothing);
    expect(find.text('Show full diff'), findsOneWidget);

    await tester.ensureVisible(find.text('Show full diff'));
    await tester.tap(find.text('Show full diff'));
    await tester.pumpAndSettle();

    expect(find.text('line 85'), findsOneWidget);
  });

  testWidgets('file change card folds additional files after two entries',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'file_change', 'File changes', 'Files changed',
                        fileChanges: <ConversationFileChange>[
                          ConversationFileChange(
                              path: 'lib/one.dart',
                              kind: 'update',
                              diff: '@@ -1 +1 @@\n-old\n+new'),
                          ConversationFileChange(
                              path: 'lib/two.dart',
                              kind: 'update',
                              diff: '@@ -1 +1 @@\n-old\n+new'),
                          ConversationFileChange(
                              path: 'lib/three.dart',
                              kind: 'update',
                              diff: '@@ -1 +1 @@\n-old\n+new'),
                        ]),
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('Edited 3 files'), findsOneWidget);
    expect(find.text('lib/one.dart'), findsOneWidget);
    expect(find.text('lib/two.dart'), findsOneWidget);
    expect(find.text('lib/three.dart'), findsNothing);
    expect(find.text('+1 more files'), findsOneWidget);
  });

  testWidgets('Claude auth warning renders as an error notice',
      (WidgetTester tester) async {
    final message = workbenchMessageFromConversation(const ConversationMessage(
      role: 'notice',
      text: 'Claude API 401 authentication_failed (retry 1/10)',
      isError: true,
    ));

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: message,
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('服务商认证异常'), findsOneWidget);
    expect(find.text('认证'), findsOneWidget);
    expect(find.text('Claude API 401 authentication_failed (retry 1/10)'),
        findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('System notice'), findsNothing);
    expect(find.text('provider auth'), findsNothing);
    expect(find.text('non-blocking'), findsNothing);
  });

  testWidgets('Codex policy notice uses localized compact styling',
      (WidgetTester tester) async {
    final message = workbenchMessageFromConversation(const ConversationMessage(
      role: 'notice',
      text: 'Codex CLI blocked this command under the current local policy.',
      noticeKind: 'codex_policy_blocked',
    ));

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: message,
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('已被本地策略阻止'), findsOneWidget);
    expect(find.text('策略'), findsOneWidget);
    expect(find.text('当前本地审批策略不允许执行这条命令。'), findsOneWidget);
    expect(find.byIcon(Icons.gpp_maybe_outlined), findsOneWidget);
    expect(find.text('System notice'), findsNothing);
    expect(find.text('notice'), findsNothing);
    expect(
        find.text(
            'Codex CLI blocked this command under the current local policy.'),
        findsNothing);
  });

  testWidgets('OpenCode expired session notice uses zh recovery copy',
      (WidgetTester tester) async {
    final message = workbenchMessageFromConversation(const ConversationMessage(
      role: 'notice',
      text:
          'The previous OpenCode session is no longer available. Start a new message to create a fresh session.',
      noticeKind: 'opencode_session_expired',
    ));

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: message,
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('OpenCode 会话已重置'), findsOneWidget);
    expect(find.text('会话'), findsOneWidget);
    expect(find.text('之前的 OpenCode 会话已不可用。发送新消息即可创建新的会话。'), findsOneWidget);
    expect(find.text('System notice'), findsNothing);
    expect(find.text('系统提示'), findsNothing);
    expect(
        find.text(
            'The previous OpenCode session is no longer available. Start a new message to create a fresh session.'),
        findsNothing);
  });

  testWidgets('OpenCode unreadable diff notice uses localized copy',
      (WidgetTester tester) async {
    final state = const ConversationViewState().apply([
      ConversationEvent(
        type: 'system.notice',
        seq: 8,
        conversationId: 'conv_opencode_diff_notice',
        createdAt: DateTime(2026, 6, 9),
        text: 'OpenCode event: session.diff',
        raw: const <String, Object?>{
          'noticeKind': 'opencode_session_diff',
          'visible': true,
        },
      ),
    ]);
    final message = workbenchMessageFromConversation(state.messages.single);

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: message,
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('OpenCode 报告了文件变更'), findsOneWidget);
    expect(find.text('变更'), findsOneWidget);
    expect(find.text('OpenCode 报告了变更事件，但没有提供可读取的文件差异。'), findsOneWidget);
    expect(find.text('OpenCode event: session.diff'), findsNothing);
    expect(find.text('系统提示'), findsNothing);
  });

  testWidgets('OpenCode file edited notice uses localized path copy',
      (WidgetTester tester) async {
    final state = const ConversationViewState().apply([
      ConversationEvent(
        type: 'system.notice',
        seq: 9,
        conversationId: 'conv_opencode_file_notice',
        createdAt: DateTime(2026, 6, 9),
        text: 'OpenCode edited lib/src/main.dart',
        raw: const <String, Object?>{
          'noticeKind': 'opencode_file_edited',
          'path': 'lib/src/main.dart',
        },
      ),
    ]);
    final message = workbenchMessageFromConversation(state.messages.single);

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: message,
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('OpenCode 已编辑文件'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('OpenCode 已编辑 lib/src/main.dart'), findsOneWidget);
    expect(find.text('OpenCode edited lib/src/main.dart'), findsNothing);
  });

  testWidgets(
      'OpenCode file edited notice without path uses localized fallback',
      (WidgetTester tester) async {
    final state = const ConversationViewState().apply([
      ConversationEvent(
        type: 'system.notice',
        seq: 10,
        conversationId: 'conv_opencode_file_notice_missing_path',
        createdAt: DateTime(2026, 6, 9),
        text: 'OpenCode edited an unknown provider file',
        raw: const <String, Object?>{
          'noticeKind': 'opencode_file_edited',
        },
      ),
    ]);
    final message = workbenchMessageFromConversation(state.messages.single);

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: message,
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('OpenCode 已编辑文件'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('OpenCode 已编辑一个文件。'), findsOneWidget);
    expect(find.text('OpenCode edited an unknown provider file'), findsNothing);
  });

  testWidgets('run error notice uses localized title without prefixing body',
      (WidgetTester tester) async {
    final message = workbenchMessageFromConversation(const ConversationMessage(
      role: 'notice',
      text: 'Provider session is no longer available.',
      noticeKind: 'run_failed',
      isError: true,
    ));

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: message,
                    onApproval: _noopApproval,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('运行失败'), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
    expect(
        find.text('Provider session is no longer available.'), findsOneWidget);
    expect(find.textContaining('Run error:'), findsNothing);
  });

  testWidgets('run error card uses active locale for trace actions',
      (WidgetTester tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (MethodCall methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final data = methodCall.arguments as Map<Object?, Object?>;
        clipboardText = data['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: const Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: EdgeInsets.all(16),
                child: WorkbenchRunErrorCard(
                    error: 'Provider session is no longer available.',
                    traceId: 'trace_1')))));
    await tester.pumpAndSettle();

    expect(find.text('运行错误：Provider session is no longer available.'),
        findsOneWidget);
    expect(find.text('追踪 ID：trace_1'), findsOneWidget);
    expect(find.text('复制追踪 ID'), findsOneWidget);
    expect(find.textContaining('Run error:'), findsNothing);

    await tester.tap(find.text('复制追踪 ID'));
    await tester.pumpAndSettle();

    expect(clipboardText, 'trace_1');
    expect(find.text('追踪 ID 已复制'), findsOneWidget);
  });

  testWidgets('thinking card title uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'thinking', 'Thinking process', '正在分析上下文'),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.text('思考过程'), findsOneWidget);
    expect(find.text('Thinking process'), findsNothing);
  });

  testWidgets('assistant code blocks expose a compact copy action',
      (WidgetTester tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (MethodCall methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final data = methodCall.arguments as Map<Object?, Object?>;
        clipboardText = data['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage('assistant', 'Codex',
                        'Run this:\n\n```powershell\nflutter analyze\n```\n\nThen continue.'),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    final copyButton = find.byKey(const Key('workbench-markdown-code-copy'));
    expect(copyButton, findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

    final feedbackFinder =
        find.byKey(const Key('workbench-markdown-code-copy-feedback'));
    expect(tester.getSize(feedbackFinder), const Size(24, 24));

    final codeBlockFinder =
        find.byKey(const Key('workbench-markdown-code-block'));
    final codeTextFinder =
        find.byKey(const Key('workbench-markdown-code-text'));
    expect(tester.getBottomRight(feedbackFinder).dy,
        lessThanOrEqualTo(tester.getTopLeft(codeTextFinder).dy + 1));
    final topInset = tester.getTopLeft(codeTextFinder).dy -
        tester.getTopLeft(codeBlockFinder).dy;
    final bottomInset = tester.getBottomRight(codeBlockFinder).dy -
        tester.getBottomRight(codeTextFinder).dy;
    expect((topInset - bottomInset).abs(), lessThanOrEqualTo(1));

    await tester.tap(copyButton);
    await tester.pump();

    expect(clipboardText, 'flutter analyze');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    final feedbackShell = tester.widget<AnimatedContainer>(feedbackFinder);
    final decoration = feedbackShell.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFE7ECF8));
    expect(decoration.border, isNotNull);
    final copiedIcon = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(copiedIcon.color, const Color(0xFF0B0C0E));

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    clipboardText = null;

    await tester.tap(copyButton);
    await tester.pump();

    expect(clipboardText, 'flutter analyze');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 180));
  });

  testWidgets('user message card splits image attachment and text preview',
      (WidgetTester tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('workbench-preview-test-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}workbench-preview.png',
    );
    imageFile.writeAsBytesSync(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '这个图片里面有什么？',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'screenshot.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1219716,
                          handling: AttachmentHandling.native,
                          localPath: imageFile.path,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.text('这个图片里面有什么？'), findsOneWidget);
    expect(find.text('screenshot.png'), findsOneWidget);
    expect(find.byKey(const Key('workbench-user-attachment-bubble')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-user-text-bubble')), findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview-shell')),
        findsOneWidget);
    final imagePreviewShell = tester.widget<Container>(
        find.byKey(const Key('workbench-message-image-preview-shell')));
    expect((imagePreviewShell.decoration! as BoxDecoration).border, isNotNull);
    final borderedAttachmentContainers = tester
        .widgetList<Container>(find.descendant(
            of: find.byKey(const Key('workbench-user-attachment-bubble')),
            matching: find.byType(Container)))
        .where((container) =>
            container.decoration is BoxDecoration &&
            (container.decoration! as BoxDecoration).border != null);
    expect(borderedAttachmentContainers.map((container) => container.key),
        <Key>[const Key('workbench-message-image-preview-shell')]);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('user message card shows image placeholder on cache miss',
      (WidgetTester tester) async {
    final tempDir = Directory.systemTemp.createTempSync('workbench-miss-test-');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final missingPath =
        '${tempDir.path}${Platform.pathSeparator}missing-preview.png';

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '重启后缓存没命中',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'persisted.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1219716,
                          handling: AttachmentHandling.native,
                          localPath: missingPath,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.text('重启后缓存没命中'), findsOneWidget);
    expect(find.text('persisted.png'), findsOneWidget);
    expect(find.byKey(const Key('workbench-user-attachment-bubble')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-user-text-bubble')), findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview-shell')),
        findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNWidgets(2));
    expect(find.text('1.2 MB'), findsOneWidget);
    final borderedAttachmentContainers = tester
        .widgetList<Container>(find.descendant(
            of: find.byKey(const Key('workbench-user-attachment-bubble')),
            matching: find.byType(Container)))
        .where((container) =>
            container.decoration is BoxDecoration &&
            (container.decoration! as BoxDecoration).border != null)
        .toList(growable: false);
    expect(borderedAttachmentContainers.length, 1);
    expect(borderedAttachmentContainers.map((container) => container.key),
        <Key>[const Key('workbench-message-image-preview-shell')]);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('user message card opens image attachment viewer',
      (WidgetTester tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('workbench-image-viewer-test-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}workbench-viewer.png',
    )..writeAsBytesSync(<int>[0x00]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '查看这张图',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'viewer.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1,
                          handling: AttachmentHandling.native,
                          localPath: imageFile.path,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    await tester.tap(find.byKey(const Key('workbench-message-image-preview')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workbench-message-image-viewer')),
        findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-viewer-image')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('workbench-message-image-viewer-close')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
      'user message card ignores deleted cached image before viewer tap',
      (WidgetTester tester) async {
    final tempDir = Directory.systemTemp
        .createTempSync('workbench-image-viewer-eviction-test-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}evicted-viewer.png',
    )..writeAsBytesSync(<int>[0x00]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '查看这张已缓存图片',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'evicted-viewer.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1,
                          handling: AttachmentHandling.native,
                          localPath: imageFile.path,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.byKey(const Key('workbench-message-image-preview')),
        findsOneWidget);
    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    imageFile.deleteSync();
    await tester.tap(find.byKey(const Key('workbench-message-image-preview')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('conversation pending status text uses active locale', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'conversation.started',
      'createdAt': '2026-05-03T00:00:00.000Z',
    });

    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('zh', 'CN'),
            events: <ConversationEvent>[event]),
        'CLI 会话已启动，正在读取上下文...');
    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('en', 'US'),
            events: <ConversationEvent>[event]),
        'CLI session started. Reading context...');
  });

  test('conversation pending status text surfaces reconnect notices', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'system.notice',
      'createdAt': '2026-05-09T00:00:00.000Z',
      'text': 'Reconnecting... 1/5 (stream disconnected before completion)'
    });

    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('en', 'US'),
            events: <ConversationEvent>[event]),
        'Reconnecting... 1/5 (stream disconnected before completion)');
  });

  test('ASR model download dialog strings use active locale', () {
    final zh = lookupAppLocalizations(theme.zhHansCnLocale);
    final en = lookupAppLocalizations(const Locale('en', 'US'));

    expect(zh.asrModelDialogTitle, '语音模型');
    expect(zh.asrModelDownloading('zipformer'), '正在下载 zipformer');
    expect(zh.asrModelPauseAction, '暂停');
    expect(zh.asrModelCancelAction, '取消');
    expect(zh.workbenchComposerPromptHint, '输入你的需求...');
    expect(zh.workbenchAttachmentRemoveTooltip('image.png'), '移除 image.png');
    expect(en.asrModelDialogTitle, 'Voice model');
    expect(en.asrModelDownloading('zipformer'), 'Downloading zipformer');
    expect(en.workbenchComposerPromptHint, 'Add feedback...');
    expect(
        en.workbenchAttachmentRemoveTooltip('image.png'), 'Remove image.png');
  });

  test('duplicate approvals collapse and approval response becomes command',
      () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      },
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      },
      const <String, Object?>{
        'type': 'approval.responded',
        'seq': 3,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'approvalId': 'approval_1',
        'decision': 'allow',
        'toolName': 'Write',
        'input': {'command': 'Write'}
      },
      const <String, Object?>{
        'type': 'tool.started',
        'seq': 4,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:03.000Z',
        'toolName': 'Write',
        'input': {'command': r'Write C:\Users\W2830\python_intro.py'}
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events),
        const <String>[r'command:Write C:\Users\W2830\python_intro.py']);
  });

  test('conversation approval resolution becomes a command card', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'python intro.py'},
        'summary': 'python intro.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.resolved',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'decision': 'allow',
        'toolName': 'Bash',
        'input': {'command': 'python intro.py'},
        'summary': 'python intro.py'
      },
    ];

    expect(
        debugWorkbenchMessageRolesForConversationEvents(events, conversation),
        const <String>['command:python intro.py']);
  });

  test('conversation approval preserves command metadata from blocking item',
      () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolUseId': 'toolu_1',
        'toolName': 'Write',
        'input': {
          'file_path': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
        },
        'summary': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.resolved',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'toolUseId': 'toolu_1',
        'decision': 'allow',
        'toolName': 'Write',
        'input': {
          'file_path': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
        },
        'summary': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
      },
    ];

    expect(
        debugWorkbenchMessageRolesForConversationEvents(events, conversation),
        const <String>[
          r'command:D:\AiProject\vibe-coding\python_concurrency_learn.py'
        ]);
  });

  test('ExitPlanMode prompt becomes a question instead of a failed tool card',
      () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_plan',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'idle',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_plan',
        'type': 'tool.started',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'toolUseId': 'toolu_exit',
        'toolName': 'ExitPlanMode',
        'summary': 'ExitPlanMode',
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_plan',
        'type': 'tool.output',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'toolUseId': 'toolu_exit',
        'toolName': 'ExitPlanMode',
        'text': 'Exit plan mode?',
        'isError': true,
      },
      const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_plan',
        'type': 'tool.completed',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'toolUseId': 'toolu_exit',
        'toolName': 'ExitPlanMode',
        'isError': true,
      },
    ];

    expect(
        debugWorkbenchMessageRolesForConversationEvents(events, conversation),
        const <String>['question:Exit plan mode?']);
  });

  testWidgets('conversation command card shows output and duration',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        buildConversationCommandCardPreview(expandToolDetails: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workbench-tool-foldout-row')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-tool-foldout-expanded')),
        findsOneWidget);
    expect(find.text('python intro.py'), findsWidgets);
    expect(find.textContaining('执行 1 条命令'), findsOneWidget);
    expect(find.text('hello from intro'), findsOneWidget);
    expect(find.textContaining('2.0s'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-status-ok')), findsOneWidget);
  });

  test('continuous command messages project into Codex command display items',
      () {
    const assistant = WorkbenchMessage('assistant', 'CLI assistant', 'Done.');
    const approval = WorkbenchMessage('approval', 'Needs approval', 'npm test');
    const first = WorkbenchMessage(
        'command', 'Bash', 'Get-Content -Path pubspec.yaml',
        completed: true);
    const second =
        WorkbenchMessage('command', 'Bash', 'dart analyze', completed: true);
    const third = WorkbenchMessage('command', 'Bash', 'flutter test');

    final items = projectWorkbenchTranscriptDisplayItems(
        <WorkbenchMessage>[assistant, first, second, approval, third]);

    expect(debugWorkbenchTranscriptDisplayItemRoles(items), const <String>[
      'message:assistant',
      'command_group:2',
      'message:approval',
      'single_command:flutter test',
    ]);
  });

  testWidgets('running command group uses sweeping status text',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCommandRunGroupPreview(running: true));
    await tester.pump();

    expect(find.byType(SweepingStatusText), findsOneWidget);
    expect(find.text('正在运行 2 条命令'), findsWidgets);
    expect(find.byKey(const ValueKey('workbench-command-run-group-shell')),
        findsNothing);
  });

  testWidgets('running command group keeps sweep progress across new events',
      (WidgetTester tester) async {
    await tester
        .pumpWidget(_WorkbenchMessageListHarness(messages: <WorkbenchMessage>[
      _runningCommandMessage(seq: 1, body: 'Get-Content pubspec.yaml'),
      _runningCommandMessage(seq: 2, body: 'dart analyze'),
    ]));
    await tester.pump(const Duration(milliseconds: 900));

    final progressFinder =
        find.byKey(const ValueKey('workbench-command-run-sweep-progress'));
    expect(progressFinder, findsOneWidget);
    final progressBeforeUpdate = tester.getSize(progressFinder).width;
    expect(progressBeforeUpdate, greaterThan(0));

    await tester
        .pumpWidget(_WorkbenchMessageListHarness(messages: <WorkbenchMessage>[
      _runningCommandMessage(seq: 1, body: 'Get-Content pubspec.yaml'),
      _runningCommandMessage(seq: 2, body: 'dart analyze'),
      _runningCommandMessage(seq: 3, body: 'flutter test'),
    ]));
    await tester.pump();

    expect(tester.getSize(progressFinder).width,
        greaterThan(progressBeforeUpdate * .8));
  });

  testWidgets(
      'completed command group expands to shell blocks in command order',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCommandRunGroupPreview());
    await tester.pumpAndSettle();

    expect(find.text('已运行 2 条命令'), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-command-run-group-shell')),
        findsNothing);

    await tester.tap(find.text('已运行 2 条命令'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workbench-command-run-group-shell')),
        findsOneWidget);
    expect(find.text('Shell'), findsNWidgets(2));
    expect(find.text(r'$ Get-Content -Path pubspec.yaml'), findsWidgets);
    expect(find.text('name: lan_ai_cli_control'), findsOneWidget);
    expect(find.text('退出码 0'), findsNWidgets(2));
  });

  testWidgets('command shell blocks use distinguishable charcoal surfaces',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCommandRunGroupPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('已运行 2 条命令'));
    await tester.pumpAndSettle();

    final shellBlock = tester.widget<Container>(
        find.byKey(const ValueKey('workbench-command-shell-block')).first);
    final shellDecoration = shellBlock.decoration! as BoxDecoration;
    expect(shellDecoration.color, const Color(0xFF2C2D30));

    final commandPanelFinder =
        find.byKey(const ValueKey('workbench-command-shell-command')).first;
    final panelContainer = tester.widget<Container>(find.descendant(
        of: commandPanelFinder,
        matching: find.byWidgetPredicate((widget) => widget is Container)));
    final panelDecoration = panelContainer.decoration! as BoxDecoration;
    expect(panelDecoration.color, const Color(0xFF25262A));
  });

  testWidgets('command group toggle appears on hover and points down expanded',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCommandRunGroupPreview());
    await tester.pumpAndSettle();

    final opacityFinder =
        find.byKey(const ValueKey('workbench-command-run-toggle-opacity'));
    expect(opacityFinder, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0);
    expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('已运行 2 条命令')));
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1);

    await tester.tap(find.text('已运行 2 条命令'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1);
    await gesture.removePointer();
  });

  testWidgets('failed command summary stays compact and preserves output',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSingleCommandPreview(failed: true));
    await tester.pumpAndSettle();

    expect(find.text('已失败 dart analyze'), findsOneWidget);
    expect(find.text('analysis failed'), findsNothing);

    await tester.tap(find.text('已失败 dart analyze'));
    await tester.pumpAndSettle();

    expect(find.text('analysis failed'), findsOneWidget);
    expect(find.text('退出码 2'), findsOneWidget);
  });

  testWidgets('Agent tool call renders as a sub-agent card',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubAgentCallCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('Review the repository changes'), findsOneWidget);
    expect(find.text('Run command'), findsNothing);
    expect(find.text('No blocking issues found.'), findsNothing);

    await tester.tap(find.text('Review the repository changes'));
    await tester.pumpAndSettle();

    expect(find.text('No blocking issues found.'), findsOneWidget);
  });

  testWidgets('question card uses compact Codex-style prompt row',
      (WidgetTester tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'question', 'Needs your direction', '请选择修复范围',
                        suggestions: <String>['全部修复', '仅关键问题']),
                    onApproval: (_) {},
                    onSuggestion: (value) => selected = value,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('ASK'), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    expect(find.text('需要你补充方向'), findsOneWidget);
    expect(find.text('请选择修复范围'), findsOneWidget);

    await tester.tap(find.text('仅关键问题'));
    await tester.pump();

    expect(selected, '仅关键问题');
  });

  testWidgets('task progress card shows desktop-style rows and statuses',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildTaskProgressCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('任务'), findsOneWidget);
    expect(find.text('1/3 已完成'), findsOneWidget);
    expect(find.text('分析工作区结构'), findsOneWidget);
    expect(find.text('实现进度卡片'), findsOneWidget);
    expect(find.text('运行回归测试'), findsOneWidget);
    expect(find.text('完成'), findsWidgets);
    expect(find.text('进行中'), findsWidgets);
    expect(find.text('排队'), findsWidgets);
  });

  test('empty completed conversation shows diagnostic warning', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_empty',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'idle',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final diagnostic = debugEmptyConversationCompletionDiagnostic(
      const <Map<String, Object?>>[
        <String, Object?>{
          'seq': 1,
          'conversationId': 'conv_empty',
          'type': 'conversation.started',
          'createdAt': '2026-05-03T00:00:00.000Z'
        },
        <String, Object?>{
          'seq': 2,
          'conversationId': 'conv_empty',
          'type': 'protocol.warning',
          'createdAt': '2026-05-03T00:00:01.000Z',
          'text': 'Claude exited before returning content'
        },
        <String, Object?>{
          'seq': 3,
          'conversationId': 'conv_empty',
          'type': 'conversation.completed',
          'createdAt': '2026-05-03T00:00:02.000Z'
        },
      ],
      conversation,
    );

    expect(diagnostic, contains('CLI returned no content'));
    expect(diagnostic, contains('Claude exited before returning content'));
  });

  test('cancelled run does not render a visible status card', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'run.cancelled',
      'seq': 9,
      'runId': 'run_1',
      'createdAt': '2026-05-03T00:00:04.000Z',
      'reason': 'user_cancelled'
    });

    expect(body, isNull);
  });

  test('AskUserQuestion command card shows the actual question', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'tool.started',
      'seq': 10,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:05.000Z',
      'toolName': 'AskUserQuestion',
      'input': {'question': 'Which script direction do you want?'}
    });

    expect(body, 'Which script direction do you want?');
    expect(body, isNot('AskUserQuestion'));
  });

  test('AskUserQuestion approval card shows the actual question', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'approval.required',
      'seq': 11,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:06.000Z',
      'approvalId': 'approval_ask',
      'toolName': 'AskUserQuestion',
      'input': {
        'question': 'Which advanced features should the script include?'
      }
    });

    expect(
        body, contains('Which advanced features should the script include?'));
    expect(body, isNot('AskUserQuestion'));
  });

  test('AskUserQuestion approval reads nested control request input', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'approval.required',
      'seq': 12,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:07.000Z',
      'approvalId': 'approval_nested',
      'toolName': 'AskUserQuestion',
      'raw': {
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'AskUserQuestion',
          'input': {'question': 'Files, network, or concurrency?'}
        }
      }
    });

    expect(body, contains('Files, network, or concurrency?'));
  });

  test(
      'AskUserQuestion approval without input does not infer from assistant text',
      () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 1,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'raw': {'type': 'result', 'result': 'What should this script do?'}
      },
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 2,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'approvalId': 'approval_ask',
        'toolName': 'AskUserQuestion'
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events).first,
        'assistant:What should this script do?');
    expect(debugWorkbenchMessageRolesAfterEvents(events).last,
        contains('AskUserQuestion'));
  });

  test('assistant question event shows suggestions without approval', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.question',
        'seq': 1,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'text': 'Which direction should this Python script take?',
        'suggestions': ['automation', 'async', 'logs']
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'question:Which direction should this Python script take?'
    ]);
    expect(debugVisibleWorkbenchBodyFromEvent(events.first),
        'Which direction should this Python script take?');
  });

  test('final assistant result replaces partial same-run response', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'raw': {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'I need more detail.'}
            ]
          }
        }
      },
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'raw': {
          'type': 'result',
          'result':
              'Advanced script is broad. What should it do?\n\n1. automation\n2. async\n3. logs'
        }
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'assistant:Advanced script is broad. What should it do?\n\n1. automation\n2. async\n3. logs'
    ]);
  });

  test('final assistant result removes temporary question card', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.question',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'text': 'Need more info.',
        'suggestions': ['automation', 'async']
      },
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'raw': {
          'type': 'result',
          'result':
              'Advanced Python script can mean many things. Pick a direction:\n\n- web scraping\n- CLI tool\n- data processing\n- automation\n- API service\n- AI integration'
        }
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'assistant:Advanced Python script can mean many things. Pick a direction:\n\n- web scraping\n- CLI tool\n- data processing\n- automation\n- API service\n- AI integration'
    ]);
  });

  test('filters escaped Claude protocol payloads from assistant bubbles', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'assistant.delta',
      'seq': 12,
      'runId': 'run_1',
      'createdAt': '2026-05-02T00:00:00.000Z',
      'raw': {
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {
              'type': 'text',
              'text':
                  '\\n"Fix this bug" -> debugging first, then domain-specific skills.\\n\\n## Skill Types\\n\\nRigid (TDD, debugging): Follow exactly.'
            }
          ]
        },
        'parent_tool_use_id': null,
        'session_id': 'leaked-session'
      }
    });

    expect(body, isNull);
  });
}
