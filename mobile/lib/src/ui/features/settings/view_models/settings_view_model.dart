import 'package:flutter/foundation.dart';

import '../../../../data/repositories/coding_preferences_repository.dart';
import '../../../../data/repositories/workspace_repository.dart';
import '../../../../domain/models/daemon_connection_config.dart';
import '../../../../models/protocol.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required WorkspaceRepository workspaceRepository,
    required CodingPreferencesRepository codingPreferencesRepository,
    required DaemonConnectionConfig connectionConfig,
    required DaemonHealth health,
    CodeDiagnosticsSummary? diagnostics,
    GitStatusSummary? gitStatus,
    int extensionsCount = 0,
  })  : _workspaceRepository = workspaceRepository,
        _codingPreferencesRepository = codingPreferencesRepository,
        _connectionConfig = connectionConfig,
        _health = health,
        _diagnostics = diagnostics,
        _gitStatus = gitStatus,
        _extensionsCount = extensionsCount {
    _workspaceRepository.addListener(_onRepositoryChanged);
    _codingPreferencesRepository.addListener(_onRepositoryChanged);
  }

  final WorkspaceRepository _workspaceRepository;
  final CodingPreferencesRepository _codingPreferencesRepository;
  DaemonConnectionConfig _connectionConfig;
  DaemonHealth _health;
  CodeDiagnosticsSummary? _diagnostics;
  GitStatusSummary? _gitStatus;
  int _extensionsCount;

  WorkspaceSummary? get selectedWorkspace =>
      _workspaceRepository.selectedWorkspace;
  List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
  String get permissionMode => _codingPreferencesRepository.permissionMode;
  DaemonConnectionConfig get connectionConfig => _connectionConfig;
  DaemonHealth get health => _health;
  CodeDiagnosticsSummary? get diagnostics => _diagnostics;
  GitStatusSummary? get gitStatus => _gitStatus;
  int get extensionsCount => _extensionsCount;
  bool get loading =>
      _workspaceRepository.loading || _codingPreferencesRepository.loading;
  Object? get error =>
      _workspaceRepository.error ?? _codingPreferencesRepository.error;

  void updateShellInputs({
    required DaemonConnectionConfig connectionConfig,
    required DaemonHealth health,
    CodeDiagnosticsSummary? diagnostics,
    GitStatusSummary? gitStatus,
    int? extensionsCount,
  }) {
    _connectionConfig = connectionConfig;
    _health = health;
    _diagnostics = diagnostics;
    _gitStatus = gitStatus;
    if (extensionsCount != null) {
      _extensionsCount = extensionsCount;
    }
    notifyListeners();
  }

  Future<void> setPermissionMode(String value) =>
      _codingPreferencesRepository.setPermissionMode(value);

  void _onRepositoryChanged() => notifyListeners();

  @override
  void dispose() {
    _workspaceRepository.removeListener(_onRepositoryChanged);
    _codingPreferencesRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
