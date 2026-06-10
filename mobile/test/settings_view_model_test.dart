import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/coding_preferences_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/settings_view_model.dart';

void main() {
  test('settings reflects selected workspace from repository', () async {
    final workspaceRepository = _FakeWorkspaceRepository(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
        WorkspaceSummary(id: 'w2', name: 'Two', path: r'D:\two'),
      ],
    );
    final viewModel = _settingsViewModel(workspaceRepository);

    workspaceRepository.select('w2');

    expect(viewModel.selectedWorkspace?.id, 'w2');
  });

  test('settings updates permission mode through CodingPreferencesRepository',
      () async {
    final preferences = _FakeCodingPreferencesRepository();
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      preferences: preferences,
    );

    await viewModel.setPermissionMode('default');

    expect(preferences.permissionMode, 'default');
    expect(viewModel.permissionMode, 'default');
  });

  test('settings updates background event preference through repository',
      () async {
    final preferences = _FakeCodingPreferencesRepository();
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      preferences: preferences,
    );

    await viewModel.setKeepConversationEventsInBackground(true);

    expect(preferences.keepConversationEventsInBackground, isTrue);
    expect(viewModel.keepConversationEventsInBackground, isTrue);
  });

  test('settings updates tool detail expansion preference through repository',
      () async {
    final preferences = _FakeCodingPreferencesRepository();
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      preferences: preferences,
    );

    await viewModel.setExpandToolDetails(true);

    expect(preferences.expandToolDetails, isTrue);
    expect(viewModel.expandToolDetails, isTrue);
  });

  test('settings syncs permission mode to active Claude conversation',
      () async {
    final preferences = _FakeCodingPreferencesRepository();
    final conversationRepository = _FakeConversationRepository();
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      preferences: preferences,
      conversationRepository: conversationRepository,
      activeConversationProvider: () => _conversation(
        id: 'conv_1',
        adapter: 'claude',
      ),
    );

    await viewModel.setPermissionMode('auto');

    expect(preferences.permissionMode, 'auto');
    expect(conversationRepository.permissionModeUpdates, const <String>[
      'conv_1:auto',
    ]);
  });

  test('settings does not sync permission mode to non-Claude conversations',
      () async {
    final conversationRepository = _FakeConversationRepository();
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      conversationRepository: conversationRepository,
      activeConversationProvider: () => _conversation(
        id: 'conv_1',
        adapter: 'codex',
      ),
    );

    await viewModel.setPermissionMode('auto');

    expect(conversationRepository.permissionModeUpdates, isEmpty);
  });

  test('settings records permission mode persistence failures', () async {
    final preferences = _FakeCodingPreferencesRepository()
      ..setPermissionModeError = StateError('write failed');
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      preferences: preferences,
    );

    await viewModel.setPermissionMode('default');

    expect(viewModel.error, isA<StateError>());
    expect(viewModel.permissionMode, 'default');
  });

  test('settings exposes shell connection and health inputs', () async {
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
    );

    expect(viewModel.connectionConfig.addressInput, 'http://127.0.0.1:4317');
    expect(viewModel.health.daemonVersion, '1.0.0');

    viewModel.updateShellInputs(
      connectionConfig: _connectionConfig('http://192.168.1.12:4317'),
      health: _health(daemonVersion: '1.1.0'),
    );

    expect(viewModel.connectionConfig.addressInput, 'http://192.168.1.12:4317');
    expect(viewModel.health.daemonVersion, '1.1.0');
  });

  test('settings removes repository listeners on dispose', () async {
    final workspaceRepository =
        _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]);
    final preferences = _FakeCodingPreferencesRepository();
    final viewModel = _settingsViewModel(
      workspaceRepository,
      preferences: preferences,
    );

    viewModel.dispose();
    workspaceRepository.notifyForTest();
    preferences.notifyForTest();

    expect(workspaceRepository.listenerCount, 0);
    expect(preferences.listenerCount, 0);
  });

  test('settings ignores async preference completion after dispose', () async {
    final preferences = _FakeCodingPreferencesRepository();
    final writeGate = Completer<void>();
    preferences.setPermissionModeDelay = writeGate.future;
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      preferences: preferences,
    );
    var notifications = 0;
    viewModel.addListener(() => notifications += 1);

    final update = viewModel.setPermissionMode('auto');
    viewModel.dispose();
    writeGate.complete();

    await expectLater(update, completes);
    expect(notifications, 0);
  });
}

SettingsViewModel _settingsViewModel(
  _FakeWorkspaceRepository workspaceRepository, {
  _FakeCodingPreferencesRepository? preferences,
  _FakeConversationRepository? conversationRepository,
  ConversationSummary? Function()? activeConversationProvider,
}) =>
    SettingsViewModel(
      workspaceRepository: workspaceRepository,
      codingPreferencesRepository:
          preferences ?? _FakeCodingPreferencesRepository(),
      conversationRepository: conversationRepository,
      activeConversationProvider: activeConversationProvider,
      connectionConfig: _connectionConfig('http://127.0.0.1:4317'),
      health: _health(daemonVersion: '1.0.0'),
    );

DaemonConnectionConfig _connectionConfig(String address) =>
    DaemonConnectionConfig(
      addressInput: address,
      proxyMode: DaemonProxyMode.direct,
      manualProxyInput: '',
    );

DaemonHealth _health({required String daemonVersion}) => DaemonHealth(
      status: 'ok',
      daemonVersion: daemonVersion,
      mode: 'development',
      lanMode: true,
      bindAddress: '127.0.0.1',
      port: 4317,
      security: const <String, Object?>{},
    );

ConversationSummary _conversation({
  required String id,
  required String adapter,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: 'workspace_1',
      adapter: adapter,
      status: 'running',
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-30T00:00:00.000Z',
      updatedAt: '2026-05-30T00:00:01.000Z',
    );

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({required List<WorkspaceSummary> workspaces})
      : _workspaces = List<WorkspaceSummary>.unmodifiable(workspaces),
        _selectedWorkspaceId = workspaces.isEmpty ? null : workspaces.first.id;

  final List<WorkspaceSummary> _workspaces;
  String? _selectedWorkspaceId;
  int listenerCount = 0;

  @override
  List<WorkspaceSummary> get workspaces => _workspaces;

  @override
  WorkspaceSummary? get selectedWorkspace {
    final selectedId = _selectedWorkspaceId;
    if (selectedId == null) return null;
    for (final workspace in _workspaces) {
      if (workspace.id == selectedId) return workspace;
    }
    return null;
  }

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) =>
      throw UnimplementedError();

  @override
  bool select(String workspaceId) {
    if (!_workspaces.any((workspace) => workspace.id == workspaceId)) {
      return false;
    }
    _selectedWorkspaceId = workspaceId;
    notifyListeners();
    return true;
  }

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    throw UnimplementedError();
  }

  void notifyForTest() => notifyListeners();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCodingPreferencesRepository extends CodingPreferencesRepository {
  String _permissionMode = 'default';
  bool _keepConversationEventsInBackground = false;
  bool _expandToolDetails = false;
  int listenerCount = 0;
  Object? setPermissionModeError;
  Future<void>? setPermissionModeDelay;

  @override
  String get permissionMode => _permissionMode;

  @override
  bool get keepConversationEventsInBackground =>
      _keepConversationEventsInBackground;

  @override
  bool get expandToolDetails => _expandToolDetails;

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> setPermissionMode(String value) async {
    final delay = setPermissionModeDelay;
    if (delay != null) {
      await delay;
    }
    final error = setPermissionModeError;
    if (error != null) throw error;
    _permissionMode =
        CodingPreferencesRepository.normalizePermissionMode(value);
    notifyListeners();
  }

  @override
  Future<void> setKeepConversationEventsInBackground(bool value) async {
    _keepConversationEventsInBackground = value;
    notifyListeners();
  }

  @override
  Future<void> setExpandToolDetails(bool value) async {
    _expandToolDetails = value;
    notifyListeners();
  }

  void notifyForTest() => notifyListeners();
}

class _FakeConversationRepository implements ConversationRepository {
  final List<String> permissionModeUpdates = <String>[];

  @override
  Future<ConversationSummary> updateConversationPermissionMode(
    String conversationId,
    String permissionMode,
  ) async {
    permissionModeUpdates.add('$conversationId:$permissionMode');
    return _conversation(id: conversationId, adapter: 'claude');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
