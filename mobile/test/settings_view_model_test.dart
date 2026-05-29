import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/coding_preferences_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
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

  test('settings records permission mode persistence failures', () async {
    final preferences = _FakeCodingPreferencesRepository()
      ..setPermissionModeError = StateError('write failed');
    final viewModel = _settingsViewModel(
      _FakeWorkspaceRepository(workspaces: const <WorkspaceSummary>[]),
      preferences: preferences,
    );

    await viewModel.setPermissionMode('default');

    expect(viewModel.error, isA<StateError>());
    expect(viewModel.permissionMode, 'auto');
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
}

SettingsViewModel _settingsViewModel(
  _FakeWorkspaceRepository workspaceRepository, {
  _FakeCodingPreferencesRepository? preferences,
}) =>
    SettingsViewModel(
      workspaceRepository: workspaceRepository,
      codingPreferencesRepository:
          preferences ?? _FakeCodingPreferencesRepository(),
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
  String _permissionMode = 'auto';
  int listenerCount = 0;
  Object? setPermissionModeError;

  @override
  String get permissionMode => _permissionMode;

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
    final error = setPermissionModeError;
    if (error != null) throw error;
    _permissionMode =
        CodingPreferencesRepository.normalizePermissionMode(value);
    notifyListeners();
  }

  void notifyForTest() => notifyListeners();
}
