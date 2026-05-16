import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/features/adapters/adapters.dart';

void main() {
  group('AdaptersViewModel', () {
    test('exposes immutable adapter and extension state', () {
      final viewModel = AdaptersViewModel(
        snapshot: _snapshot(
          adapters: const <AdapterStatus>[_codexAdapter],
          extensions: const <ExtensionSummary>[_githubExtension],
        ),
      );

      expect(viewModel.adapters, hasLength(1));
      expect(viewModel.extensions, hasLength(1));
      expect(
        () => viewModel.adapters.add(_claudeAdapter),
        throwsUnsupportedError,
      );
      expect(
        () => viewModel.extensions.clear(),
        throwsUnsupportedError,
      );
    });

    test('notifies once when snapshot state changes', () {
      final viewModel = AdaptersViewModel(snapshot: _snapshot());
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.updateFromSnapshot(
        _snapshot(adapters: const <AdapterStatus>[_codexAdapter]),
      );

      expect(notifications, 1);
      expect(viewModel.adapters.single.adapter, 'codex');
    });

    test('copies snapshot lists instead of exposing mutable inputs', () {
      final adapters = <AdapterStatus>[_codexAdapter];
      final viewModel = AdaptersViewModel(
        snapshot: _snapshot(adapters: adapters),
      );

      adapters.add(_claudeAdapter);

      expect(viewModel.adapters, hasLength(1));
      expect(viewModel.adapters.single.adapter, 'codex');
    });
  });
}

const _codexAdapter = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
);

const _claudeAdapter = AdapterStatus(
  adapter: 'claude',
  available: false,
  status: 'missing',
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
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<ExtensionSummary> extensions = const <ExtensionSummary>[],
}) {
  const workspace = WorkspaceSummary(
    id: 'workspace_1',
    name: 'Current Project',
    path: r'D:\AiProject\vibe-coding',
  );
  return AppSnapshot(
    health: DaemonHealth.fromJson(const <String, Object?>{
      'status': 'ok',
      'daemonVersion': 'test',
      'mode': 'test',
      'lanMode': false,
      'bindAddress': '127.0.0.1',
      'port': 4317,
      'security': {'tokenRequired': false},
    }),
    workspaces: const <WorkspaceSummary>[workspace],
    workspace: workspace,
    overview: const ProjectOverview(
      workspaceId: 'workspace_1',
      name: 'vibe-coding',
      path: r'D:\AiProject\vibe-coding',
      fileCount: 0,
      codeLineCount: 0,
      symbolCount: 0,
      analysisScore: 0,
      recentFiles: <RecentFileSummary>[],
    ),
    adapters: adapters,
    runs: const <RunSummary>[],
    conversations: const <ConversationSummary>[],
    queue: const <QueueItem>[],
    templates: const <CommandTemplate>[],
    gitStatus: const GitStatusSummary(
      workspaceId: 'workspace_1',
      clean: true,
      files: <GitStatusFile>[],
    ),
    diffs: const <DiffSummary>[],
    commits: const <GitCommitSummary>[],
    fileTree: const FileTreeResponse(
      workspaceId: 'workspace_1',
      root: '',
      entries: <FileTreeEntry>[],
    ),
    diagnostics: const CodeDiagnosticsSummary(
      workspaceId: 'workspace_1',
      available: true,
      diagnostics: <CodeDiagnostic>[],
    ),
    extensions: extensions,
  );
}
