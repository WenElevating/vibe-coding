import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/app/connected_session_scope.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/auth_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/coding_preferences_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_route.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/diagnostics/diagnostics.dart';
import 'package:lan_ai_cli_control/src/ui/features/run_detail/run_detail.dart';
import 'package:lan_ai_cli_control/src/ui/main_route_overlay.dart';

void main() {
  group('MainRouteOverlay', () {
    testWidgets('recreates run detail view model when run metadata changes',
        (tester) async {
      final factory = _RunDetailFactory();
      final connectedData = _connectedData();
      final repositories = _repositories();
      final featureDependencies = _featureDependencies(
        createRunDetailViewModel: factory.create,
      );

      await tester.pumpWidget(_OverlayHarness(
        data: _snapshot(runs: const <RunSummary>[_runningRun]),
        connectedData: connectedData,
        repositories: repositories,
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      expect(find.text('running'), findsOneWidget);
      expect(factory.createdRuns, const <RunSummary>[_runningRun]);

      await tester.pumpWidget(_OverlayHarness(
        data: _snapshot(runs: const <RunSummary>[_completedRun]),
        connectedData: connectedData,
        repositories: repositories,
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      expect(find.text('completed'), findsOneWidget);
      expect(find.text('running'), findsNothing);
      expect(factory.createdRuns, const <RunSummary>[
        _runningRun,
        _completedRun,
      ]);
      expect(factory.disposedRuns, const <RunSummary>[_runningRun]);
    });

    testWidgets('recreates run detail view model when repository scope changes',
        (tester) async {
      final factory = _RunDetailFactory();
      final featureDependencies = _featureDependencies(
        createRunDetailViewModel: factory.create,
      );

      await tester.pumpWidget(_OverlayHarness(
        data: _snapshot(runs: const <RunSummary>[_runningRun]),
        connectedData: _connectedData(),
        repositories: _repositories(),
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_OverlayHarness(
        data: _snapshot(runs: const <RunSummary>[_runningRun]),
        connectedData: _connectedData(),
        repositories: _repositories(),
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      expect(factory.createdRuns, const <RunSummary>[
        _runningRun,
        _runningRun,
      ]);
      expect(factory.disposedRuns, const <RunSummary>[_runningRun]);
    });

    testWidgets('creates diagnostics view model through feature dependencies',
        (tester) async {
      final connectedData = _connectedData();
      final repositories = _repositories();
      final diagnosticsFactory = _DiagnosticsFactory();
      final featureDependencies = _featureDependencies(
        createRunDetailViewModel: _RunDetailFactory().create,
        createDiagnosticsViewModel: diagnosticsFactory.create,
      );

      await tester.pumpWidget(_OverlayHarness(
        route: RoutePage.diagnostics,
        data: _snapshot(runs: const <RunSummary>[_runningRun]),
        connectedData: connectedData,
        repositories: repositories,
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      expect(diagnosticsFactory.createdWith, [connectedData]);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(diagnosticsFactory.disposeCount, 1);
    });

    testWidgets(
        'adapters overlay reads repository adapters when bootstrap data is empty',
        (tester) async {
      final repositories = _repositories();
      repositories.cliAdapterRepository.replaceFromBootstrap(
        const <AdapterStatus>[_codexAdapter],
      );

      await tester.pumpWidget(_OverlayHarness(
        route: RoutePage.adapters,
        data: _snapshot(
          runs: const <RunSummary>[],
          adapters: const <AdapterStatus>[],
          extensions: const <ExtensionSummary>[],
        ),
        connectedData: _connectedData(),
        repositories: repositories,
        featureDependencies: _featureDependencies(
          createRunDetailViewModel: _RunDetailFactory().create,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('codex'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    });
  });
}

const _workspace = WorkspaceSummary(
  id: 'workspace_1',
  name: 'Workspace',
  path: r'D:\workspace',
);

const _runningRun = RunSummary(
  id: 'run_1',
  tool: 'codex',
  workspaceId: 'workspace_1',
  status: 'running',
  cliSessionId: 'session_1',
);

const _completedRun = RunSummary(
  id: 'run_1',
  tool: 'codex',
  workspaceId: 'workspace_1',
  status: 'completed',
  cliSessionId: 'session_1',
);

const _githubExtension = ExtensionSummary(
  id: 'github',
  name: 'GitHub',
  version: '1.0.0',
  description: 'Issue sync',
  installed: true,
  status: 'installed',
);

AppSnapshot _snapshot({
  required List<RunSummary> runs,
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<ExtensionSummary> extensions = const <ExtensionSummary>[],
}) =>
    AppSnapshot(
      health: const DaemonHealth(
        status: 'ok',
        daemonVersion: 'test',
        mode: 'test',
        lanMode: false,
        bindAddress: '127.0.0.1',
        port: 4317,
        security: <String, Object?>{},
      ),
      workspaces: const <WorkspaceSummary>[_workspace],
      workspace: _workspace,
      overview: const ProjectOverview(
        workspaceId: 'workspace_1',
        name: 'Workspace',
        path: r'D:\workspace',
        fileCount: 0,
        codeLineCount: 0,
        symbolCount: 0,
        analysisScore: 0,
        recentFiles: <RecentFileSummary>[],
      ),
      adapters: adapters,
      runs: runs,
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: null,
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
        workspaceId: 'workspace_1',
        root: r'D:\workspace',
        entries: <FileTreeEntry>[],
      ),
      diagnostics: const CodeDiagnosticsSummary(
        workspaceId: 'workspace_1',
        available: false,
        diagnostics: <CodeDiagnostic>[],
      ),
      extensions: extensions,
    );

FeatureDependencies _featureDependencies({
  required RunDetailViewModel Function(RunSummary run) createRunDetailViewModel,
  DiagnosticsViewModel Function(ConnectedDataDependencies connectedData)?
      createDiagnosticsViewModel,
}) =>
    FeatureDependencies(
      createDaemonConnectionViewModel: () => throw UnimplementedError(),
      createDiagnosticsViewModel: createDiagnosticsViewModel ??
          (connectedData) => DiagnosticsViewModel(
                repository: connectedData.diagnosticsRepository,
              ),
      createHomeViewModel: (connectedData, {signalMetrics}) =>
          throw UnimplementedError(),
      createSettingsViewModel: ({
        required connectedData,
        required connectionConfig,
        required health,
        diagnostics,
        gitStatus,
        extensionsCount = 0,
      }) =>
          throw UnimplementedError(),
      createRunDetailViewModel: (connectedData, run) =>
          createRunDetailViewModel(run),
      createAppUpdateViewModel: ({
        required client,
        required connectedData,
        required installedVersionCode,
        required installedVersionName,
      }) =>
          throw UnimplementedError(),
      createWorkbenchDependencies: (client, connectedData) =>
          throw UnimplementedError(),
    );

class _OverlayHarness extends StatelessWidget {
  const _OverlayHarness({
    this.route = RoutePage.detail,
    required this.data,
    required this.connectedData,
    required this.repositories,
    required this.featureDependencies,
  });

  final RoutePage route;
  final AppSnapshot data;
  final ConnectedDataDependencies connectedData;
  final ConnectedSessionRepositories repositories;
  final FeatureDependencies featureDependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
        body: MainRouteOverlay(
          route: route,
          data: data.toDaemonInitialData(),
          connectedData: connectedData,
          repositories: repositories,
          featureDependencies: featureDependencies,
          onBack: () {},
        ),
      ),
    );
  }
}

ConnectedDataDependencies _connectedData() {
  final unused = _UnusedRepository();
  return ConnectedDataDependencies(
    authRepository: unused,
    adapterRepository: unused,
    appUpdateRepository: unused,
    conversationRepository: unused,
    diagnosticsRepository: _FakeDiagnosticsRepository(),
    runRepository: _FakeRunRepository(),
    workspaceRepository: unused,
  );
}

ConnectedSessionRepositories _repositories() {
  final adapterDelegate = _FakeAdapterRepository();
  return ConnectedSessionRepositories(
    authRepository: _UnusedRepository(),
    workspaceRepository: _FakeWorkspaceRepository(),
    conversationRepository: CachedConversationRepository(
      delegate: _UnusedRepository(),
    ),
    runRepository: CachedRunRepository(delegate: _FakeRunRepository()),
    cliAdapterRepository: CliAdapterRepository(delegate: adapterDelegate),
    commandCatalogRepository: CommandCatalogRepository(
      delegate: adapterDelegate,
    ),
    diagnosticsRepository: _FakeDiagnosticsRepository(),
    appUpdateRepository: _UnusedRepository(),
    codingPreferencesRepository: CodingPreferencesRepository(),
    recordDiagnosticEvent: (_, __, {severity = 'info', path}) {},
  );
}

class _FakeAdapterRepository implements AdapterRepository {
  @override
  Future<List<AdapterStatus>> listAdapters() async => const <AdapterStatus>[
        _codexAdapter,
      ];

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  @override
  Future<List<ExtensionSummary>> listExtensions() async =>
      const <ExtensionSummary>[_githubExtension];
}

class _DiagnosticsFactory {
  final createdWith = <ConnectedDataDependencies>[];
  var disposeCount = 0;

  DiagnosticsViewModel create(ConnectedDataDependencies connectedData) {
    createdWith.add(connectedData);
    return _TrackingDiagnosticsViewModel(
      repository: connectedData.diagnosticsRepository,
      onDispose: () => disposeCount += 1,
    );
  }
}

class _TrackingDiagnosticsViewModel extends DiagnosticsViewModel {
  _TrackingDiagnosticsViewModel({
    required super.repository,
    required this.onDispose,
  });

  final VoidCallback onDispose;

  @override
  void dispose() {
    onDispose();
    super.dispose();
  }
}

class _RunDetailFactory {
  final createdRuns = <RunSummary>[];
  final disposedRuns = <RunSummary>[];

  RunDetailViewModel create(RunSummary run) {
    createdRuns.add(run);
    return _TrackingRunDetailViewModel(
      run: run,
      onDispose: () => disposedRuns.add(run),
    );
  }
}

class _TrackingRunDetailViewModel extends RunDetailViewModel {
  _TrackingRunDetailViewModel({
    required super.run,
    required this.onDispose,
  }) : super(runRepository: _FakeRunRepository());

  final VoidCallback onDispose;

  @override
  void dispose() {
    onDispose();
    super.dispose();
  }
}

class _FakeRunRepository implements RunRepository {
  @override
  Future<RunSummary> cancelRun(String runId) => throw UnimplementedError();

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) =>
      throw UnimplementedError();

  @override
  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq = 0}) async {
    return const <AgentEvent>[];
  }

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) =>
      throw UnimplementedError();

  @override
  Future<List<QueueItem>> listQueue() => throw UnimplementedError();

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> respondApproval(String approvalId, String decision) =>
      throw UnimplementedError();

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) =>
      throw UnimplementedError();
}

class _FakeDiagnosticsRepository implements DiagnosticsRepository {
  @override
  Future<DiagnosticBundleSummary> exportDiagnostics() {
    throw UnimplementedError();
  }

  @override
  Future<String> recordException({
    required String message,
    String severity = 'error',
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }
}

class _UnusedRepository extends WorkspaceRepository
    implements
        AdapterRepository,
        AppUpdateRepository,
        AuthRepository,
        ConversationRepository {
  @override
  Future<List<AdapterStatus>> listAdapters() => throw UnimplementedError();

  @override
  Future<List<ShortcutCommand>> listShortcuts() => throw UnimplementedError();

  @override
  Future<List<CommandTemplate>> listCommandTemplates() =>
      throw UnimplementedError();

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) =>
      throw UnimplementedError();

  @override
  Future<List<ExtensionSummary>> listExtensions() => throw UnimplementedError();

  @override
  Future<DaemonHealth> health() => throw UnimplementedError();

  @override
  Future<DaemonVersionInfo> version() => throw UnimplementedError();

  @override
  Future<String> createPairingCode() => throw UnimplementedError();

  @override
  Future<void> pair({
    required String code,
    String label = '',
    String? deviceId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> refreshToken() => throw UnimplementedError();

  @override
  Future<void> revokeCurrentDevice() => throw UnimplementedError();

  @override
  Future<List<ConversationSummary>> listConversations() =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) =>
      throw UnimplementedError();

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) =>
      throw UnimplementedError();

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) =>
      throw UnimplementedError();

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() => throw UnimplementedError();

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) =>
      throw UnimplementedError();

  @override
  List<WorkspaceSummary> get workspaces => const <WorkspaceSummary>[];

  @override
  WorkspaceSummary? get selectedWorkspace => null;

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({
    required String path,
    String? name,
  }) =>
      throw UnimplementedError();

  @override
  bool select(String workspaceId) => false;

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {}

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) =>
      throw UnimplementedError();

  @override
  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path = '',
    int maxDepth = 8,
  }) =>
      throw UnimplementedError();

  @override
  Future<FileContent> fileContent(String workspaceId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) =>
      throw UnimplementedError();

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) =>
      throw UnimplementedError();

  @override
  Future<List<GitCommitSummary>> gitCommits(
    String workspaceId, {
    int limit = 20,
  }) =>
      throw UnimplementedError();

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) =>
      throw UnimplementedError();

  @override
  Future<List<DirectoryEntrySummary>> listFileSystemRoots() =>
      throw UnimplementedError();

  @override
  Future<DirectoryListing> listDirectory(String path) =>
      throw UnimplementedError();
}
