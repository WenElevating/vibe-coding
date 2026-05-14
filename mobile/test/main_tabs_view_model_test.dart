import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/view_models/main_tabs_view_model.dart';

class _FakeAdapterRepository implements AdapterRepository {
  _FakeAdapterRepository({this.failOnce = false});

  final bool failOnce;
  int listAdaptersCalls = 0;

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    listAdaptersCalls++;
    if (failOnce && listAdaptersCalls == 1) {
      throw StateError('adapter load failed');
    }
    return const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ];
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  @override
  Future<List<ExtensionSummary>> listExtensions() async =>
      const <ExtensionSummary>[];

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];
}

AppSnapshot _snapshot() {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AIProject\vibe-coding');
  return const AppSnapshot(
    health: DaemonHealth(
      status: 'ok',
      daemonVersion: 'test',
      mode: 'test',
      lanMode: false,
      bindAddress: '127.0.0.1',
      port: 4317,
      security: <String, Object?>{'tokenRequired': false},
    ),
    workspaces: <WorkspaceSummary>[workspace],
    workspace: workspace,
    overview: ProjectOverview(
      workspaceId: 'workspace_1',
      name: 'vibe-coding',
      path: r'D:\AIProject\vibe-coding',
      fileCount: 0,
      codeLineCount: 0,
      symbolCount: 0,
      analysisScore: 0,
      recentFiles: <RecentFileSummary>[],
    ),
    adapters: <AdapterStatus>[],
    runs: <RunSummary>[],
    conversations: <ConversationSummary>[],
    queue: <QueueItem>[],
    templates: <CommandTemplate>[],
    gitStatus: GitStatusSummary(
      workspaceId: 'workspace_1',
      clean: true,
      files: <GitStatusFile>[],
    ),
    diffs: <DiffSummary>[],
    commits: <GitCommitSummary>[],
    fileTree: FileTreeResponse(
      workspaceId: 'workspace_1',
      root: r'D:\AIProject\vibe-coding',
      entries: <FileTreeEntry>[],
    ),
    diagnostics: CodeDiagnosticsSummary(
      workspaceId: 'workspace_1',
      available: true,
      diagnostics: <CodeDiagnostic>[],
    ),
    extensions: <ExtensionSummary>[],
  );
}

void main() {
  test('loads coding adapters through repository once', () async {
    final repository = _FakeAdapterRepository();
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: repository,
    );
    addTearDown(viewModel.dispose);

    await viewModel.ensureCodingAdaptersLoaded();
    await viewModel.ensureCodingAdaptersLoaded();

    expect(repository.listAdaptersCalls, 1);
    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
    expect(viewModel.data.adapters.map((adapter) => adapter.adapter),
        contains('codex'));
  });

  test('reports adapter load failures and retries', () async {
    final repository = _FakeAdapterRepository(failOnce: true);
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: repository,
    );
    addTearDown(viewModel.dispose);

    await viewModel.ensureCodingAdaptersLoaded();

    expect(viewModel.adapterLoadState, CodingAdapterLoadState.failed);
    expect(viewModel.adapterLoadError, isA<StateError>());

    await viewModel.ensureCodingAdaptersLoaded();

    expect(repository.listAdaptersCalls, 2);
    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
  });
}
