import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_app_update_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/auth_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/daemon_connection_config_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_notification_client.dart';
import 'package:lan_ai_cli_control/src/services/device_identity_store.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/view_models/workbench_view_model.dart';

void main() {
  test('connected data disposal closes notification client', () async {
    final notificationClient = _CloseRecordingNotificationClient();
    final data = DataDependencies(
      connectionConfigRepository: _FakeConnectionConfigRepository(),
      createNotificationClient: (_) => notificationClient,
    );
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
    );
    final connectedData = data.forDaemonClient(client);

    expect(connectedData.appUpdateRepository, isA<DaemonAppUpdateRepository>());

    await connectedData.dispose();
    await connectedData.dispose();
    client.close();

    expect(notificationClient.closeCalls, 1);
  });

  test('connected data disposal suppresses notification close failures',
      () async {
    final notificationClient = _FailingCloseNotificationClient();
    final data = DataDependencies(
      connectionConfigRepository: _FakeConnectionConfigRepository(),
      createNotificationClient: (_) => notificationClient,
    );
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
    );
    final connectedData = data.forDaemonClient(client);

    await connectedData.dispose();
    await connectedData.dispose();
    client.close();

    expect(notificationClient.closeCalls, 1);
  });

  test('workbench uses the same warmed CLI adapter repository', () async {
    final data = DataDependencies(
      connectionConfigRepository: _FakeConnectionConfigRepository(),
    );
    final features = FeatureDependencies.createDefault(
      data: data,
      domain: DomainDependencies.createDefault(
        data: data,
        network: NetworkDependencies(
          tokenStore: MemoryTokenStore(),
          deviceIdentityStore: MemoryDeviceIdentityStore(deviceId: 'device'),
        ),
      ),
    );
    final connectedData = ConnectedDataDependencies(
      authRepository: _UnusedRepository(),
      adapterRepository: _FakeAdapterRepository(),
      appUpdateRepository: _UnusedRepository(),
      conversationRepository: _UnusedRepository(),
      diagnosticsRepository: _UnusedRepository(),
      runRepository: _UnusedRepository(),
      workspaceRepository: _FakeWorkspaceRepository(),
    );
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
    );

    final workbenchDependencies =
        features.createWorkbenchDependencies(client, connectedData);
    await connectedData.cliAdapterRepository.probe();
    final viewModel = WorkbenchViewModel(
      workspaceRepository: connectedData.workspaceRepository,
      adapterRepository: workbenchDependencies.adapterRepository,
      conversationRepository: CachedConversationRepository(
        delegate: _UnusedRepository(),
      ),
      runRepository: CachedRunRepository(delegate: _UnusedRepository()),
    );

    expect(
      identical(
        workbenchDependencies.adapterRepository,
        connectedData.cliAdapterRepository,
      ),
      isTrue,
    );
    expect(viewModel.availableAdaptersFromCache.single.adapter, 'codex');
    expect(viewModel.selectedAdapter, 'codex');

    viewModel.dispose();
    workbenchDependencies.asrModelManager.dispose();
    await connectedData.dispose();
    client.close();
  });
}

class _FakeConnectionConfigRepository
    implements DaemonConnectionConfigRepository {
  @override
  Future<DaemonConnectionConfig> load() async =>
      DaemonConnectionConfig.fallback;

  @override
  Future<void> save(DaemonConnectionConfig config) async {}
}

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

class _FailingCloseNotificationClient extends DaemonNotificationClient {
  _FailingCloseNotificationClient()
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
    throw StateError('notification close unavailable');
  }
}

class _FakeAdapterRepository implements AdapterRepository {
  @override
  Future<List<AdapterStatus>> listAdapters() async {
    return const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ];
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async {
    return const <CommandTemplate>[];
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    return const <ExtensionSummary>[];
  }

  @override
  Future<List<ShortcutCommand>> listShortcuts() async {
    return const <ShortcutCommand>[];
  }
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  static const _workspace = WorkspaceSummary(
    id: 'workspace_1',
    name: 'Workspace',
    path: r'D:\workspace',
  );

  @override
  List<WorkspaceSummary> get workspaces => const <WorkspaceSummary>[_workspace];

  @override
  WorkspaceSummary? get selectedWorkspace => _workspace;

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) {
    throw UnimplementedError();
  }

  @override
  bool select(String workspaceId) => workspaceId == _workspace.id;

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {}

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => workspaces;

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) =>
      create(path: path, name: name);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedRepository
    implements
        AuthRepository,
        AppUpdateRepository,
        ConversationRepository,
        DiagnosticsRepository,
        RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
