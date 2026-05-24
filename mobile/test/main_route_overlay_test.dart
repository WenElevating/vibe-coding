import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/auth_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/workspace_repository.dart';
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
      final featureDependencies = _featureDependencies(
        createRunDetailViewModel: factory.create,
      );

      await tester.pumpWidget(_OverlayHarness(
        data: _snapshot(runs: const <RunSummary>[_runningRun]),
        connectedData: connectedData,
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      expect(find.text('running'), findsOneWidget);
      expect(factory.createdRuns, const <RunSummary>[_runningRun]);

      await tester.pumpWidget(_OverlayHarness(
        data: _snapshot(runs: const <RunSummary>[_completedRun]),
        connectedData: connectedData,
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
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_OverlayHarness(
        data: _snapshot(runs: const <RunSummary>[_runningRun]),
        connectedData: _connectedData(),
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
      final diagnosticsFactory = _DiagnosticsFactory();
      final featureDependencies = _featureDependencies(
        createRunDetailViewModel: _RunDetailFactory().create,
        createDiagnosticsViewModel: diagnosticsFactory.create,
      );

      await tester.pumpWidget(_OverlayHarness(
        route: RoutePage.diagnostics,
        data: _snapshot(runs: const <RunSummary>[_runningRun]),
        connectedData: connectedData,
        featureDependencies: featureDependencies,
      ));
      await tester.pumpAndSettle();

      expect(diagnosticsFactory.createdWith, [connectedData]);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(diagnosticsFactory.disposeCount, 1);
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

AppSnapshot _snapshot({required List<RunSummary> runs}) => AppSnapshot(
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
      adapters: const <AdapterStatus>[
        AdapterStatus(adapter: 'codex', available: true, status: 'available'),
      ],
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
      extensions: const <ExtensionSummary>[],
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
    required this.featureDependencies,
  });

  final RoutePage route;
  final AppSnapshot data;
  final ConnectedDataDependencies connectedData;
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
          data: data,
          connectedData: connectedData,
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

class _UnusedRepository
    implements
        AdapterRepository,
        AppUpdateRepository,
        AuthRepository,
        ConversationRepository,
        WorkspaceRepository {
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
