import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/state/daemon_connection_controller.dart';
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
    expect(controller.snapshot, same(snapshot));
    final saved = await store.load();
    expect(saved.addressInput, '192.168.1.23');
    expect(saved.proxyMode, DaemonProxyMode.manual);
    expect(saved.manualProxyInput, 'http://proxy.local:8080');
  });

  test('default connection timeout is ten seconds for bootstrap loading', () {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );

    expect(controller.connectionTimeout, const Duration(seconds: 10));
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
    expect(controller.snapshot, isNull);
  });
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
