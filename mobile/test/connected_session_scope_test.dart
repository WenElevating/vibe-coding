import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/app/connected_session_scope.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_initial_data.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/daemon_connection_config_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_notification_client.dart';
import 'package:lan_ai_cli_control/src/services/device_identity_store.dart';

void main() {
  test('main tabs dependencies expose hydrated connected session scope',
      () async {
    final appDependencies = AppDependencies.createDefault();
    final client = _daemonClient();
    final dependencies = appDependencies.createMainTabsDependencies(
      client,
      initialData: _initialData(),
    );

    final scope = dependencies.sessionScope;
    expect(scope, isA<ConnectedSessionScope>());
    expect(scope.repositories.workspaceRepository.selectedWorkspace?.id, 'w1');
    expect(scope.repositories.conversationRepository.loadedWorkspaceId, 'w1');
    expect(scope.repositories.runRepository.loadedWorkspaceId, 'w1');
    expect(
      scope.repositories.cliAdapterRepository.adapters.single.adapter,
      'codex',
    );

    await scope.dispose();
    client.close();
  });

  test(
    'composition root hydrates workspace catalog when no workspace is selected',
    () async {
      final appDependencies = AppDependencies.createDefault();
      final client = _daemonClient();
      final dependencies = appDependencies.createMainTabsDependencies(
        client,
        initialData: _initialDataWithoutSelectedWorkspace(),
      );

      final repositories = dependencies.sessionScope.repositories;
      expect(
        repositories.workspaceRepository.workspaces.map(
          (workspace) => workspace.id,
        ),
        const <String>['w1'],
      );
      expect(repositories.workspaceRepository.selectedWorkspace, isNull);
      expect(repositories.conversationRepository.loadedWorkspaceId, isNull);
      expect(repositories.runRepository.loadedWorkspaceId, isNull);
      expect(
        repositories.cliAdapterRepository.adapters.single.adapter,
        'codex',
      );

      await dependencies.sessionScope.dispose();
      client.close();
    },
  );

  test('session scope disposal closes the notification client once', () async {
    final notificationClient = _CloseRecordingNotificationClient();
    final appDependencies = _appDependencies(notificationClient);
    final client = _daemonClient();
    final dependencies = appDependencies.createMainTabsDependencies(
      client,
      initialData: _initialData(),
    );

    await dependencies.sessionScope.dispose();
    await dependencies.sessionScope.dispose();
    client.close();

    expect(notificationClient.closeCalls, 1);
  });
}

AppDependencies _appDependencies(DaemonNotificationClient notificationClient) {
  final network = NetworkDependencies(
    tokenStore: MemoryTokenStore(),
    deviceIdentityStore: MemoryDeviceIdentityStore(deviceId: 'device'),
  );
  final data = DataDependencies(
    connectionConfigRepository: _FakeConnectionConfigRepository(),
    createNotificationClient: (_) => notificationClient,
  );
  final domain = DomainDependencies.createDefault(data: data, network: network);
  return AppDependencies(
    network: network,
    data: data,
    domain: domain,
    features: FeatureDependencies.createDefault(data: data, domain: domain),
  );
}

DaemonClient _daemonClient() => DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
    );

DaemonInitialData _initialData() {
  const workspace = WorkspaceSummary(
    id: 'w1',
    name: 'Workspace',
    path: r'D:\workspace',
  );
  const capabilities = ConversationCapabilities(
    longLivedProcess: false,
    waitingInput: false,
    waitingApproval: false,
    resume: false,
    partialOutput: false,
  );
  return const DaemonInitialData(
    health: _health,
    workspaces: <WorkspaceSummary>[workspace],
    workspace: workspace,
    adapters: <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ],
    conversations: <ConversationSummary>[
      ConversationSummary(
        id: 'c1',
        workspaceId: 'w1',
        adapter: 'codex',
        status: 'idle',
        capabilities: capabilities,
        createdAt: '2026-05-29T00:00:00.000Z',
        updatedAt: '2026-05-29T00:00:00.000Z',
      ),
    ],
    runs: <RunSummary>[
      RunSummary(
        id: 'r1',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'completed',
      ),
    ],
    queue: <QueueItem>[
      QueueItem(
        runId: 'r1',
        workspaceId: 'w1',
        position: 1,
        status: 'queued',
        reason: 'waiting',
      ),
    ],
  );
}

DaemonInitialData _initialDataWithoutSelectedWorkspace() {
  const workspace = WorkspaceSummary(
    id: 'w1',
    name: 'Workspace',
    path: r'D:\workspace',
  );
  return const DaemonInitialData(
    health: _health,
    workspaces: <WorkspaceSummary>[workspace],
    workspace: null,
    adapters: <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ],
    conversations: <ConversationSummary>[],
    runs: <RunSummary>[],
    queue: <QueueItem>[],
  );
}

const _health = DaemonHealth(
  status: 'ok',
  daemonVersion: 'test',
  mode: 'test',
  lanMode: false,
  bindAddress: '127.0.0.1',
  port: 4317,
  security: <String, Object?>{},
);

class _CloseRecordingNotificationClient extends DaemonNotificationClient {
  _CloseRecordingNotificationClient()
      : super(
          baseUri: Uri.parse('http://127.0.0.1:4317'),
          tokenProvider: () => null,
          fetchBackfill: (_, {required afterSeq}) async =>
              const <ConversationEvent>[],
        );

  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

class _FakeConnectionConfigRepository
    implements DaemonConnectionConfigRepository {
  @override
  Future<DaemonConnectionConfig> load() async =>
      DaemonConnectionConfig.fallback;

  @override
  Future<void> save(DaemonConnectionConfig config) async {}
}
