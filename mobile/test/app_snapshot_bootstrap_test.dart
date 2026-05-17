import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/device_identity_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';

void main() {
  test('bootstrap loads only connection-critical home data', () async {
    final deviceStore = MemoryDeviceIdentityStore(deviceId: 'device-123');
    final client = _BootstrapDaemonClient(deviceStore: deviceStore);

    final snapshot = await AppSnapshot.loadBootstrap(client,
        deviceIdentityStore: deviceStore);

    expect(snapshot.health.status, 'ok');
    expect(snapshot.workspace.id, 'workspace_1');
    expect(snapshot.runs, hasLength(1));
    expect(snapshot.conversations, hasLength(1));
    expect(snapshot.queue, hasLength(1));
    expect(snapshot.gitStatus, isNull);
    expect(snapshot.diagnostics.available, isFalse);
    expect(snapshot.overview.recentFiles, isEmpty);
    expect(snapshot.fileTree.entries, isEmpty);
    expect(client.calls, <String>[
      'health',
      'ensurePaired',
      'listWorkspaces',
      'listRuns',
      'listConversations',
      'listQueue',
    ]);
  });

  test('bootstrap accepts an empty workspace catalog', () async {
    final deviceStore = MemoryDeviceIdentityStore(deviceId: 'device-123');
    final client = _BootstrapDaemonClient(
      deviceStore: deviceStore,
      workspaces: const <WorkspaceSummary>[],
    );

    final initialData = await loadDaemonInitialDataBootstrap(client,
        deviceIdentityStore: deviceStore);

    expect(initialData.health.status, 'ok');
    expect(initialData.workspaces, isEmpty);
    expect(initialData.workspace, isNull);
    expect(initialData.runs, isEmpty);
    expect(initialData.conversations, isEmpty);
    expect(initialData.queue, isEmpty);
    expect(client.calls, <String>[
      'health',
      'ensurePaired',
      'listWorkspaces',
    ]);
  });
}

class _BootstrapDaemonClient extends DaemonClient {
  _BootstrapDaemonClient({
    required this.deviceStore,
    this.workspaces = const <WorkspaceSummary>[
      WorkspaceSummary(
          id: 'workspace_1',
          name: 'vibe-coding',
          path: r'D:\AiProject\vibe-coding')
    ],
  }) : super(
          baseUri: Uri.parse('http://127.0.0.1:4317'),
          tokenStore: MemoryTokenStore(),
        );

  final DeviceIdentityStore deviceStore;
  final List<WorkspaceSummary> workspaces;
  final List<String> calls = <String>[];

  @override
  Future<void> ensurePaired({
    required DeviceIdentityStore deviceIdentityStore,
    String label = 'Android device',
  }) async {
    calls.add('ensurePaired');
    expect(deviceIdentityStore, deviceStore);
  }

  @override
  Future<DaemonHealth> health() async {
    calls.add('health');
    return DaemonHealth.fromJson(const <String, Object?>{
      'status': 'ok',
      'daemonVersion': 'test',
      'mode': 'test',
      'lanMode': false,
      'bindAddress': '127.0.0.1',
      'port': 4317,
      'security': {'tokenRequired': false}
    });
  }

  @override
  Future<String> createPairingCode() async {
    calls.add('createPairingCode');
    return '123456';
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    calls.add('listWorkspaces');
    return workspaces;
  }

  @override
  Future<List<RunSummary>> listRuns(
      {String? tool, String? workspaceId, String? status}) async {
    calls.add('listRuns');
    expect(workspaceId, 'workspace_1');
    return const <RunSummary>[
      RunSummary(
          id: 'run_1',
          tool: 'codex',
          workspaceId: 'workspace_1',
          status: 'running')
    ];
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    calls.add('listConversations');
    return <ConversationSummary>[
      ConversationSummary(
        id: 'conversation_1',
        workspaceId: 'workspace_1',
        adapter: 'codex',
        status: 'active',
        capabilities:
            ConversationCapabilities.fromJson(const <String, Object?>{}),
        createdAt: '2026-05-07T00:00:00.000Z',
        updatedAt: '2026-05-07T00:00:00.000Z',
      )
    ];
  }

  @override
  Future<List<QueueItem>> listQueue() async {
    calls.add('listQueue');
    return const <QueueItem>[
      QueueItem(
          runId: 'run_2',
          workspaceId: 'workspace_1',
          position: 1,
          status: 'queued',
          reason: 'busy')
    ];
  }

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) async =>
      throw StateError('projectOverview should be deferred');

  @override
  Future<List<AdapterStatus>> listAdapters() async =>
      throw StateError('listAdapters should be deferred');

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      throw StateError('listCommandTemplates should be deferred');

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) async =>
      throw StateError('gitStatus should be deferred');

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) async =>
      throw StateError('gitDiff should be deferred');

  @override
  Future<List<GitCommitSummary>> gitCommits(String workspaceId,
          {int limit = 20}) async =>
      throw StateError('gitCommits should be deferred');

  @override
  Future<FileTreeResponse> fileTree(String workspaceId,
          {String path = '', int maxDepth = 8}) async =>
      throw StateError('fileTree should be deferred');

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) async =>
      throw StateError('codeDiagnostics should be deferred');

  @override
  Future<List<ExtensionSummary>> listExtensions() async =>
      throw StateError('listExtensions should be deferred');
}
