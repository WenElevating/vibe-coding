import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_connection_config_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/workflows/connection/daemon_connection_workflow.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('connect probes health, loads initial data, and saves config', () async {
    final calls = <String>[];
    final store = DaemonConnectionConfigStore();
    final client = _WorkflowDaemonClient();
    final workflow = DaemonConnectionWorkflow(
      configRepository: DaemonConnectionConfigRepository(store: store),
      tokenStore: MemoryTokenStore(),
      clientFactory: ({
        required baseUri,
        required tokenStore,
        required proxyMode,
        manualProxy,
      }) {
        calls.add('createClient:${baseUri.toString()}');
        expect(proxyMode, DaemonProxyMode.manual);
        expect(manualProxy.toString(), 'http://proxy.local:8080');
        return client;
      },
      healthProbe: (_) async => calls.add('health'),
      initialDataLoader: (_) async {
        calls.add('loadInitialData');
        return _snapshot();
      },
    );

    final session = await workflow.connect(
      addressInput: '192.168.1.23',
      proxyMode: DaemonProxyMode.manual,
      manualProxyInput: 'proxy.local:8080',
    );

    expect(calls, <String>[
      'createClient:http://192.168.1.23:4317',
      'health',
      'loadInitialData',
    ]);
    expect(session.client, same(client));
    expect(session.initialData.workspace.id, 'workspace_1');
    final saved = await store.load();
    expect(saved.addressInput, '192.168.1.23');
    expect(saved.proxyMode, DaemonProxyMode.manual);
    expect(saved.manualProxyInput, 'proxy.local:8080');
  });

  test('connect does not load initial data when health fails', () async {
    var loadedInitialData = false;
    final workflow = DaemonConnectionWorkflow(
      configRepository: DaemonConnectionConfigRepository(
          store: DaemonConnectionConfigStore()),
      tokenStore: MemoryTokenStore(),
      clientFactory: ({
        required baseUri,
        required tokenStore,
        required proxyMode,
        manualProxy,
      }) =>
          _WorkflowDaemonClient(),
      healthProbe: (_) async => throw StateError('health failed'),
      initialDataLoader: (_) async {
        loadedInitialData = true;
        return _snapshot();
      },
    );

    await expectLater(
      workflow.connect(
        addressInput: '127.0.0.1:4317',
        proxyMode: DaemonProxyMode.direct,
        manualProxyInput: '',
      ),
      throwsA(isA<StateError>()),
    );

    expect(loadedInitialData, isFalse);
  });

  test('connect does not save config when initial data loading fails',
      () async {
    final store = DaemonConnectionConfigStore();
    final workflow = DaemonConnectionWorkflow(
      configRepository: DaemonConnectionConfigRepository(store: store),
      tokenStore: MemoryTokenStore(),
      clientFactory: ({
        required baseUri,
        required tokenStore,
        required proxyMode,
        manualProxy,
      }) =>
          _WorkflowDaemonClient(),
      healthProbe: (_) async {},
      initialDataLoader: (_) async => throw StateError('load failed'),
    );

    await expectLater(
      workflow.connect(
        addressInput: '192.168.1.23',
        proxyMode: DaemonProxyMode.system,
        manualProxyInput: '',
      ),
      throwsA(isA<StateError>()),
    );

    final saved = await store.load();
    expect(saved.addressInput, DaemonConnectionConfig.fallback.addressInput);
  });
}

class _WorkflowDaemonClient extends DaemonClient {
  _WorkflowDaemonClient()
      : super(
          baseUri: Uri.parse('http://127.0.0.1:4317'),
          tokenStore: MemoryTokenStore(),
        );
}

DaemonHealth _health() => DaemonHealth.fromJson(const <String, Object?>{
      'status': 'ok',
      'daemonVersion': 'test',
      'mode': 'test',
      'lanMode': false,
      'bindAddress': '127.0.0.1',
      'port': 4317,
      'security': {'tokenRequired': false}
    });

AppSnapshot _snapshot() {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  return AppSnapshot(
      health: _health(),
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
          recentFiles: <RecentFileSummary>[]),
      adapters: const <AdapterStatus>[],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: const GitStatusSummary(
          workspaceId: 'workspace_1', clean: true, files: <GitStatusFile>[]),
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
          workspaceId: 'workspace_1', root: '', entries: <FileTreeEntry>[]),
      diagnostics: const CodeDiagnosticsSummary(
          workspaceId: 'workspace_1',
          available: true,
          diagnostics: <CodeDiagnostic>[]),
      extensions: const <ExtensionSummary>[]);
}
