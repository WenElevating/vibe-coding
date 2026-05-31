import 'package:flutter/foundation.dart';

import '../../../../data/repositories/coding_preferences_repository.dart';
import '../../../../data/repositories/workspace_repository.dart';
import '../../../../domain/models/daemon_connection_config.dart';
import '../../../../domain/repositories/conversation_repository.dart';
import '../../../../models/protocol.dart';

typedef ActiveConversationProvider = ConversationSummary? Function();

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required WorkspaceRepository workspaceRepository,
    required CodingPreferencesRepository codingPreferencesRepository,
    required DaemonConnectionConfig connectionConfig,
    required DaemonHealth health,
    ConversationRepository? conversationRepository,
    ActiveConversationProvider? activeConversationProvider,
    CodeDiagnosticsSummary? diagnostics,
    GitStatusSummary? gitStatus,
    int extensionsCount = 0,
  })  : _workspaceRepository = workspaceRepository,
        _codingPreferencesRepository = codingPreferencesRepository,
        _conversationRepository = conversationRepository,
        _activeConversationProvider = activeConversationProvider,
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
  final ConversationRepository? _conversationRepository;
  final ActiveConversationProvider? _activeConversationProvider;
  DaemonConnectionConfig _connectionConfig;
  DaemonHealth _health;
  CodeDiagnosticsSummary? _diagnostics;
  GitStatusSummary? _gitStatus;
  int _extensionsCount;
  Object? _permissionModeSaveError;

  WorkspaceSummary? get selectedWorkspace =>
      _workspaceRepository.selectedWorkspace;
  List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
  String get permissionMode => _codingPreferencesRepository.permissionMode;
  bool get keepConversationEventsInBackground =>
      _codingPreferencesRepository.keepConversationEventsInBackground;
  DaemonConnectionConfig get connectionConfig => _connectionConfig;
  DaemonHealth get health => _health;
  CodeDiagnosticsSummary? get diagnostics => _diagnostics;
  GitStatusSummary? get gitStatus => _gitStatus;
  int get extensionsCount => _extensionsCount;
  bool get loading =>
      _workspaceRepository.loading || _codingPreferencesRepository.loading;
  Object? get error =>
      _permissionModeSaveError ??
      _workspaceRepository.error ??
      _codingPreferencesRepository.error;

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

  Future<void> setPermissionMode(String value) async {
    try {
      final normalized = CodingPreferencesRepository.normalizePermissionMode(
        value,
      );
      await _codingPreferencesRepository.setPermissionMode(normalized);
      await _syncActiveConversationPermissionMode(normalized);
      if (_permissionModeSaveError != null) {
        _permissionModeSaveError = null;
        notifyListeners();
      }
    } catch (error) {
      _permissionModeSaveError = error;
      notifyListeners();
    }
  }

  Future<void> setKeepConversationEventsInBackground(bool value) async {
    try {
      await _codingPreferencesRepository
          .setKeepConversationEventsInBackground(value);
      if (_permissionModeSaveError != null) {
        _permissionModeSaveError = null;
        notifyListeners();
      }
    } catch (error) {
      _permissionModeSaveError = error;
      notifyListeners();
    }
  }

  Future<void> _syncActiveConversationPermissionMode(
    String permissionMode,
  ) async {
    final repository = _conversationRepository;
    final activeConversation = _activeConversationProvider?.call();
    if (repository == null || activeConversation == null) return;
    if (activeConversation.adapter.trim().toLowerCase() != 'claude') return;
    await repository.updateConversationPermissionMode(
      activeConversation.id,
      permissionMode,
    );
  }

  void _onRepositoryChanged() => notifyListeners();

  @override
  void dispose() {
    _workspaceRepository.removeListener(_onRepositoryChanged);
    _codingPreferencesRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
