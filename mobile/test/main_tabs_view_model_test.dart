import 'dart:async';

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

class _ManualAdapterRepository implements AdapterRepository {
  _ManualAdapterRepository();

  int listAdaptersCalls = 0;
  Completer<List<AdapterStatus>> completer = Completer<List<AdapterStatus>>();

  @override
  Future<List<AdapterStatus>> listAdapters() {
    listAdaptersCalls++;
    return completer.future;
  }

  void completeWithAdapter(String adapter) {
    completer.complete(<AdapterStatus>[
      AdapterStatus(adapter: adapter, available: true, status: 'available'),
    ]);
  }

  void completeWithError(Object error) {
    completer.completeError(error);
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

List<String> _adapterNames(MainTabsViewModel viewModel) =>
    viewModel.data.adapters.map((adapter) => adapter.adapter).toList();

void main() {
  test('defaults new coding sessions to auto permission mode', () {
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: _FakeAdapterRepository(),
    );
    addTearDown(viewModel.dispose);

    expect(viewModel.permissionMode, 'auto');
  });

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
    expect(_adapterNames(viewModel), const <String>['codex']);
  });

  test('updates workspace catalog without replacing selected workspace data',
      () {
    const created = WorkspaceSummary(
      id: 'workspace_new',
      name: 'New Workspace',
      path: r'D:\AIProject\new-workspace',
    );
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: _FakeAdapterRepository(),
    );
    addTearDown(viewModel.dispose);

    viewModel.updateWorkspaceCatalog(<WorkspaceSummary>[
      viewModel.data.workspace,
      created,
    ]);

    expect(viewModel.data.workspaces, contains(created));
    expect(viewModel.data.workspace.id, 'workspace_1');
    expect(viewModel.data.overview.workspaceId, 'workspace_1');
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

  test('ignores stale adapter success after repository reset', () async {
    final repositoryA = _ManualAdapterRepository();
    final repositoryB = _ManualAdapterRepository();
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: repositoryA,
    );
    addTearDown(viewModel.dispose);

    final loadA = viewModel.ensureCodingAdaptersLoaded();
    expect(repositoryA.listAdaptersCalls, 1);

    viewModel.resetForNewClient(
      adapterRepository: repositoryB,
      data: _snapshot(),
    );
    final loadB = viewModel.ensureCodingAdaptersLoaded();
    expect(repositoryB.listAdaptersCalls, 1);

    repositoryB.completeWithAdapter('claude');
    await loadB;

    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
    expect(_adapterNames(viewModel), const <String>['claude']);

    repositoryA.completeWithAdapter('codex');
    await loadA;

    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
    expect(_adapterNames(viewModel), const <String>['claude']);
  });

  test('ignores stale adapter failure after repository reset', () async {
    final repositoryA = _ManualAdapterRepository();
    final repositoryB = _ManualAdapterRepository();
    final viewModel = MainTabsViewModel(
      initialData: _snapshot(),
      adapterRepository: repositoryA,
    );
    addTearDown(viewModel.dispose);

    final loadA = viewModel.ensureCodingAdaptersLoaded();

    viewModel.resetForNewClient(
      adapterRepository: repositoryB,
      data: _snapshot(),
    );
    final loadB = viewModel.ensureCodingAdaptersLoaded();
    expect(repositoryB.listAdaptersCalls, 1);

    repositoryB.completeWithAdapter('claude');
    await loadB;

    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
    expect(_adapterNames(viewModel), const <String>['claude']);

    repositoryA.completeWithError(StateError('stale adapter load failed'));
    await loadA;

    expect(viewModel.adapterLoadState, CodingAdapterLoadState.loaded);
    expect(viewModel.adapterLoadError, isNull);
    expect(_adapterNames(viewModel), const <String>['claude']);
  });
}
