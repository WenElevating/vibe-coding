import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/models/connected_app_session.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/recent_daemon_address_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/domain/use_cases/connect_to_daemon_use_case.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/features/connection/view_models/daemon_connection_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loads stored config on startup', () async {
    final store = DaemonConnectionConfigStore();
    await store.save(const DaemonConnectionConfig(
      addressInput: '192.168.1.23:4317',
      proxyMode: DaemonProxyMode.system,
      manualProxyInput: '',
    ));
    final controller = DaemonConnectionController(
      store: store,
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );

    await controller.load();

    expect(controller.addressInput, '192.168.1.23:4317');
    expect(controller.proxyMode, DaemonProxyMode.system);
    expect(controller.status, DaemonConnectionStatus.idle);
  });

  test('failed connection keeps latest editable values and error summary',
      () async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async {
        throw const DaemonClientException(502, <String, Object?>{
          'error': 'invalid_response',
          'message': 'daemon returned an empty response body',
        });
      },
    );
    await controller.load();
    controller.setAddressInput('127.0.0.1:4317');
    controller.setProxyMode(DaemonProxyMode.system);

    await controller.connect();

    expect(controller.status, DaemonConnectionStatus.failed);
    expect(controller.addressInput, '127.0.0.1:4317');
    expect(controller.proxyMode, DaemonProxyMode.system);
    expect(controller.errorSummary, contains('proxy or gateway'));
  });

  test('failed connection redacts sensitive error detail', () async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async {
        throw StateError(
          r'GET https://example.test/status?token=query-secret '
          r'Authorization: Bearer bearer-secret '
          r'C:\Users\Alice\repo\main.dart api_key=key-secret',
        );
      },
    );
    await controller.load();

    await controller.connect();

    expect(controller.status, DaemonConnectionStatus.failed);
    expect(controller.errorDetail, contains('[REDACTED_QUERY]'));
    expect(controller.errorDetail, contains('Bearer [REDACTED]'));
    expect(controller.errorDetail, contains(r'[USER_PATH]\main.dart'));
    expect(controller.errorDetail, contains('api_key=[REDACTED]'));
    expect(controller.errorDetail, isNot(contains('query-secret')));
    expect(controller.errorDetail, isNot(contains('bearer-secret')));
    expect(controller.errorDetail, isNot(contains('key-secret')));
    expect(controller.errorDetail, isNot(contains('Alice')));
  });

  test('invalid editable config exposes stable input error code', () async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    await controller.load();
    controller.setAddressInput(' ');

    await controller.connect();

    expect(controller.status, DaemonConnectionStatus.failed);
    expect(controller.inputError, 'Enter a daemon address.');
    expect(
      controller.inputErrorCode,
      DaemonConnectionConfigErrorCode.emptyDaemonAddress,
    );
  });

  test('editable setters are ignored after dispose', () async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    await controller.load();
    controller.dispose();

    expect(() => controller.setAddressInput('192.168.1.23'), returnsNormally);
    expect(
      () => controller.setProxyMode(DaemonProxyMode.manual),
      returnsNormally,
    );
    expect(() => controller.setManualProxyInput('http://proxy.local:8080'),
        returnsNormally);
    expect(() => controller.selectRecentAddress('192.168.1.50:4317'),
        returnsNormally);

    expect(controller.addressInput, DaemonConnectionConfig.fallback.addressInput);
    expect(controller.proxyMode, DaemonConnectionConfig.fallback.proxyMode);
    expect(
      controller.manualProxyInput,
      DaemonConnectionConfig.fallback.manualProxyInput,
    );
  });

  test('successful connection saves config and exposes snapshot', () async {
    final store = DaemonConnectionConfigStore();
    final snapshot = _snapshot();
    final controller = DaemonConnectionController(
      store: store,
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => snapshot,
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setAddressInput('192.168.1.23');
    controller.setProxyMode(DaemonProxyMode.manual);
    controller.setManualProxyInput('http://proxy.local:8080');

    await controller.connect();

    expect(controller.status, DaemonConnectionStatus.connected);
    expect(controller.initialData, isNotNull);
    final workspace = controller.initialData!.workspace;
    expect(workspace, isNotNull);
    expect(workspace!.id, snapshot.workspace.id);
    final saved = await store.load();
    expect(saved.addressInput, '192.168.1.23');
    expect(saved.proxyMode, DaemonProxyMode.manual);
    expect(saved.manualProxyInput, 'http://proxy.local:8080');
  });

  test('default connection timeout is thirty seconds for bootstrap loading',
      () {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );

    expect(controller.connectionTimeout, const Duration(seconds: 30));
  });

  test('connection timeout restores idle affordance and ignores late success',
      () async {
    final healthCompleter = Completer<void>();
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      connectionTimeout: const Duration(milliseconds: 20),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) => healthCompleter.future,
    );
    await controller.load();

    final connection = controller.connect();
    expect(controller.isBusy, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(controller.status, DaemonConnectionStatus.failed);
    expect(controller.isBusy, isFalse);
    expect(controller.errorSummary, 'The daemon did not respond in time.');

    healthCompleter.complete();
    await connection;

    expect(controller.status, DaemonConnectionStatus.failed);
    expect(controller.initialData, isNull);
  });

  test('connection timeout closes abandoned late client', () async {
    final sessionCompleter = Completer<ConnectedAppSession<DaemonClient>>();
    final lateClient = _CloseTrackingDaemonClient();
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      connectionTimeout: Duration.zero,
      connectToDaemon: _DeferredConnectUseCase(sessionCompleter.future),
    );
    await controller.load();

    await controller.connect();

    sessionCompleter.complete(ConnectedAppSession<DaemonClient>(
      client: lateClient,
      initialData: _snapshot().toDaemonInitialData(),
      connectedConfig: const DaemonConnectionConfig(
        addressInput: '127.0.0.1:4317',
        proxyMode: DaemonProxyMode.direct,
        manualProxyInput: '',
      ),
    ));
    await sessionCompleter.future;

    expect(lateClient.closeCount, 1);
    expect(controller.client, isNull);
  });

  test('loads recent addresses without blocking stored config', () async {
    final store = DaemonConnectionConfigStore();
    await store.save(const DaemonConnectionConfig(
      addressInput: '192.168.1.23:4317',
      proxyMode: DaemonProxyMode.system,
      manualProxyInput: '',
    ));
    final recentRepository = _FakeRecentAddressRepository(
      addresses: const <String>['192.168.1.22:4317'],
    );
    final controller = DaemonConnectionController(
      store: store,
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );

    await controller.load();

    expect(controller.addressInput, '192.168.1.23:4317');
    expect(controller.recentAddresses, <String>['192.168.1.22:4317']);
  });

  test('recent address load failure falls back to empty history', () async {
    final diagnostics = <String>[];
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _FakeRecentAddressRepository(
        loadError: StateError('corrupt history'),
      ),
      recordDiagnostic: (event, metadata) => diagnostics.add(event),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );

    await controller.load();

    expect(controller.status, DaemonConnectionStatus.idle);
    expect(controller.recentAddresses, isEmpty);
    expect(
      diagnostics,
      contains('connection.recent_addresses.load_failed'),
    );
  });

  test('selecting recent address only fills input', () async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _FakeRecentAddressRepository(),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setProxyMode(DaemonProxyMode.manual);
    controller.setManualProxyInput('http://proxy.local:8080');

    controller.selectRecentAddress('192.168.1.50:4317');

    expect(controller.addressInput, '192.168.1.50:4317');
    expect(controller.proxyMode, DaemonProxyMode.manual);
    expect(controller.manualProxyInput, 'http://proxy.local:8080');
    expect(controller.status, DaemonConnectionStatus.idle);
  });

  test('successful connection records and refreshes recent address', () async {
    final recentRepository = _FakeRecentAddressRepository();
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setAddressInput('192.168.1.23');

    await controller.connect();

    expect(recentRepository.recordedAddresses, <String>['192.168.1.23']);
    expect(controller.recentAddresses, <String>['192.168.1.23']);
    expect(controller.status, DaemonConnectionStatus.connected);
  });

  test('recent address record failure does not block connection', () async {
    final diagnostics = <String>[];
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _FakeRecentAddressRepository(
        recordError: StateError('write failed'),
      ),
      recordDiagnostic: (event, metadata) => diagnostics.add(event),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setAddressInput('192.168.1.24');

    await controller.connect();

    expect(controller.status, DaemonConnectionStatus.connected);
    expect(
      diagnostics,
      contains('connection.recent_addresses.record_failed'),
    );
  });

  test('dispose during recent address load does not notify or throw', () async {
    final recentLoad = Completer<List<String>>();
    final recentRepository = _FakeRecentAddressRepository()
      ..loadCompleters.add(recentLoad);
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    final load = controller.load();
    await pumpEventQueue();
    controller.dispose();
    recentLoad.complete(const <String>['192.168.1.30:4317']);

    await expectLater(load, completes);
    expect(notifications, 0);
  });

  test('dispose during post-connected refresh does not notify after dispose',
      () async {
    final refreshLoad = Completer<List<String>>();
    final recentRepository = _FakeRecentAddressRepository();
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.load();
    controller.setAddressInput('192.168.1.31');
    recentRepository.loadCompleters.add(refreshLoad);

    final connection = controller.connect();
    await pumpEventQueue();
    expect(controller.status, DaemonConnectionStatus.connected);
    final notificationsBeforeDispose = notifications;
    controller.dispose();
    refreshLoad.complete(const <String>['192.168.1.31']);

    await expectLater(connection, completes);
    expect(notifications, notificationsBeforeDispose);
  });

  test('stale connection refresh cannot overwrite newer recent addresses',
      () async {
    final staleRefresh = Completer<List<String>>();
    final recentRepository = _FakeRecentAddressRepository();
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    recentRepository.loadCompleters.add(staleRefresh);
    controller.setAddressInput('192.168.1.40');

    final firstConnection = controller.connect();
    await pumpEventQueue();
    expect(controller.status, DaemonConnectionStatus.connected);
    expect(controller.recentAddresses, isEmpty);

    controller.setAddressInput('192.168.1.41');
    final secondConnection = controller.connect();
    await pumpEventQueue();
    expect(controller.recentAddresses, <String>[
      '192.168.1.41',
      '192.168.1.40',
    ]);

    staleRefresh.complete(const <String>['192.168.1.40']);
    await Future.wait(<Future<void>>[firstConnection, secondConnection]);

    expect(controller.recentAddresses, <String>[
      '192.168.1.41',
      '192.168.1.40',
    ]);
  });

  test('delayed stale record cannot reorder newer recent address', () async {
    final staleRecord = Completer<void>();
    final recentRepository = _FakeRecentAddressRepository()
      ..recordCompleters.add(staleRecord);
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setAddressInput('192.168.1.50');

    final firstConnection = controller.connect();
    await pumpEventQueue();
    expect(controller.status, DaemonConnectionStatus.connected);
    expect(recentRepository.addresses, isEmpty);

    controller.setAddressInput('192.168.1.51');
    final secondConnection = controller.connect();
    await pumpEventQueue();
    expect(recentRepository.addresses, <String>['192.168.1.51']);

    staleRecord.complete();
    await Future.wait(<Future<void>>[firstConnection, secondConnection]);

    expect(recentRepository.addresses, <String>[
      '192.168.1.51',
      '192.168.1.50',
    ]);
    expect(controller.recentAddresses, <String>[
      '192.168.1.51',
      '192.168.1.50',
    ]);
  });
}

class _DeferredConnectUseCase implements ConnectToDaemonUseCase<DaemonClient> {
  const _DeferredConnectUseCase(this.session);

  final Future<ConnectedAppSession<DaemonClient>> session;

  @override
  Future<ConnectedAppSession<DaemonClient>> connect({
    required String addressInput,
    required DaemonProxyMode proxyMode,
    required String manualProxyInput,
    bool Function()? shouldContinue,
    void Function()? onCheckingHealth,
    void Function()? onLoadingInitialData,
  }) =>
      session;
}

class _CloseTrackingDaemonClient extends DaemonClient {
  _CloseTrackingDaemonClient()
      : super(
          baseUri: Uri.parse('http://127.0.0.1:4317'),
          tokenStore: MemoryTokenStore(),
        );

  int closeCount = 0;

  @override
  void close() {
    closeCount++;
    super.close();
  }
}

class _FakeRecentAddressRepository implements RecentDaemonAddressRepository {
  _FakeRecentAddressRepository({
    List<String> addresses = const <String>[],
    this.loadError,
    this.recordError,
  }) : addresses = List<String>.from(addresses);

  final List<String> addresses;
  final Object? loadError;
  final Object? recordError;
  final recordedAddresses = <String>[];
  final loadCompleters = <Completer<List<String>>>[];
  final recordCompleters = <Completer<void>>[];

  @override
  Future<List<String>> loadRecentAddresses() async {
    final error = loadError;
    if (error != null) throw error;
    if (loadCompleters.isNotEmpty) {
      final completer = loadCompleters.removeAt(0);
      return List<String>.unmodifiable(await completer.future);
    }
    return List<String>.unmodifiable(addresses);
  }

  @override
  Future<void> recordSuccessfulAddress(String addressInput) async {
    final error = recordError;
    if (error != null) throw error;
    if (recordCompleters.isNotEmpty) {
      final completer = recordCompleters.removeAt(0);
      await completer.future;
    }
    recordedAddresses.add(addressInput);
    addresses
      ..removeWhere(
        (address) => address.toLowerCase() == addressInput.toLowerCase(),
      )
      ..insert(0, addressInput);
  }
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
