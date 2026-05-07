import '../models/protocol.dart';
import '../services/daemon_client.dart';

class AppSnapshot {
  const AppSnapshot(
      {required this.health,
      required this.workspaces,
      required this.workspace,
      required this.overview,
      required this.adapters,
      required this.runs,
      required this.conversations,
      required this.queue,
      required this.templates,
      required this.gitStatus,
      required this.diffs,
      required this.commits,
      required this.fileTree,
      required this.diagnostics,
      required this.extensions});

  final DaemonHealth health;
  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary workspace;
  final ProjectOverview overview;
  final List<AdapterStatus> adapters;
  final List<RunSummary> runs;
  final List<ConversationSummary> conversations;
  final List<QueueItem> queue;
  final List<CommandTemplate> templates;
  final GitStatusSummary? gitStatus;
  final List<DiffSummary> diffs;
  final List<GitCommitSummary> commits;
  final FileTreeResponse fileTree;
  final CodeDiagnosticsSummary diagnostics;
  final List<ExtensionSummary> extensions;

  List<RunSummary> get runningRuns => runs
      .where((run) => run.status == 'running' || run.status == 'starting')
      .toList();
  List<RunSummary> get completedRuns =>
      runs.where((run) => run.status == 'completed').toList();
  List<RunSummary> get failedRuns =>
      runs.where((run) => run.status == 'failed').toList();

  static Future<AppSnapshot> load(DaemonClient client,
      {DaemonHealth? health}) async {
    final resolvedHealth = health ?? await client.health();
    final pairingCode = await client.createPairingCode();
    await client.pair(code: pairingCode, label: 'Windows preview');
    final workspaces = await client.listWorkspaces();
    final workspace = workspaces.first;
    final results = await Future.wait<Object?>([
      _loadStep('overview', () => client.projectOverview(workspace.id)),
      _loadStep('adapters', client.listAdapters),
      _loadStep('runs', () => client.listRuns(workspaceId: workspace.id)),
      _loadStep('conversations', client.listConversations),
      _loadStep('queue', client.listQueue),
      _loadStep('command templates', client.listCommandTemplates),
      _tryOrNull(() => client.gitStatus(workspace.id)),
      client.gitDiff(workspace.id).catchError((_) => <DiffSummary>[]),
      client.gitCommits(workspace.id).catchError((_) => <GitCommitSummary>[]),
      _loadStep('file tree', () => client.fileTree(workspace.id, maxDepth: 6)),
      _loadStep('code diagnostics', () => client.codeDiagnostics(workspace.id)),
      _loadStep('extensions', client.listExtensions),
    ]);
    return AppSnapshot(
      health: resolvedHealth,
      workspaces: workspaces,
      workspace: workspace,
      overview: results[0] as ProjectOverview,
      adapters: results[1] as List<AdapterStatus>,
      runs: results[2] as List<RunSummary>,
      conversations: results[3] as List<ConversationSummary>,
      queue: results[4] as List<QueueItem>,
      templates: results[5] as List<CommandTemplate>,
      gitStatus: results[6] as GitStatusSummary?,
      diffs: results[7] as List<DiffSummary>,
      commits: results[8] as List<GitCommitSummary>,
      fileTree: results[9] as FileTreeResponse,
      diagnostics: results[10] as CodeDiagnosticsSummary,
      extensions: results[11] as List<ExtensionSummary>,
    );
  }

  static Future<AppSnapshot> loadBootstrap(DaemonClient client,
      {DaemonHealth? health}) async {
    final resolvedHealth = health ?? await client.health();
    final pairingCode = await client.createPairingCode();
    await client.pair(code: pairingCode, label: 'Windows preview');
    final workspaces = await client.listWorkspaces();
    final workspace = workspaces.first;
    final results = await Future.wait<Object?>([
      _loadStep('runs', () => client.listRuns(workspaceId: workspace.id)),
      _loadStep('conversations', client.listConversations),
      _loadStep('queue', client.listQueue),
    ]);
    return AppSnapshot(
      health: resolvedHealth,
      workspaces: workspaces,
      workspace: workspace,
      overview: _deferredOverview(workspace),
      adapters: const <AdapterStatus>[],
      runs: results[0] as List<RunSummary>,
      conversations: results[1] as List<ConversationSummary>,
      queue: results[2] as List<QueueItem>,
      templates: const <CommandTemplate>[],
      gitStatus: null,
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: _deferredFileTree(workspace),
      diagnostics: _deferredDiagnostics(workspace),
      extensions: const <ExtensionSummary>[],
    );
  }
}

ProjectOverview _deferredOverview(WorkspaceSummary workspace) => ProjectOverview(
      workspaceId: workspace.id,
      name: workspace.name,
      path: workspace.path,
      fileCount: 0,
      codeLineCount: 0,
      symbolCount: 0,
      analysisScore: 0,
      recentFiles: const <RecentFileSummary>[],
    );

FileTreeResponse _deferredFileTree(WorkspaceSummary workspace) =>
    FileTreeResponse(
      workspaceId: workspace.id,
      root: workspace.path,
      entries: const <FileTreeEntry>[],
    );

CodeDiagnosticsSummary _deferredDiagnostics(WorkspaceSummary workspace) =>
    CodeDiagnosticsSummary(
      workspaceId: workspace.id,
      available: false,
      diagnostics: const <CodeDiagnostic>[],
    );

Future<T> _loadStep<T>(String label, Future<T> Function() load) async {
  try {
    return await load();
  } catch (error) {
    throw StateError('$label: $error');
  }
}

Future<T?> _tryOrNull<T>(Future<T> Function() load) async {
  try {
    return await load();
  } catch (_) {
    return null;
  }
}
