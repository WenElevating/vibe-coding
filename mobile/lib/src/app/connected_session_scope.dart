import '../data/repositories/cached_conversation_repository.dart';
import '../data/repositories/cached_run_repository.dart';
import '../data/repositories/cli_adapter_repository.dart';
import '../data/repositories/coding_preferences_repository.dart';
import '../data/repositories/command_catalog_repository.dart';
import '../data/repositories/workspace_repository.dart';
import '../domain/models/daemon_initial_data.dart';
import '../domain/repositories/app_update_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/diagnostics_repository.dart';
import '../workflows/connection/open_workspace_use_case.dart';

class ConnectedSessionScope {
  ConnectedSessionScope({
    required this.repositories,
    required this.useCases,
    Future<void> Function()? closeSession,
  }) : _closeSession = closeSession;

  final ConnectedSessionRepositories repositories;
  final ConnectedSessionUseCases useCases;
  final Future<void> Function()? _closeSession;
  bool _disposed = false;

  void recordDiagnosticEvent(
    String event,
    Map<String, Object?> metadata, {
    String severity = 'info',
    String? path,
  }) {
    repositories.recordDiagnosticEvent(
      event,
      metadata,
      severity: severity,
      path: path,
    );
  }

  void hydrateFromBootstrap(DaemonInitialData initialData) {
    final workspace = initialData.workspace;
    repositories.workspaceRepository.applyBootstrapCatalog(
      selectedWorkspace: workspace,
      workspaces: initialData.workspaces,
    );
    repositories.cliAdapterRepository.replaceFromBootstrap(
      initialData.adapters,
    );
    if (workspace == null) return;
    repositories.conversationRepository.replaceFromBootstrap(
      workspaceId: workspace.id,
      conversations: initialData.conversations,
    );
    repositories.runRepository.replaceFromBootstrap(
      workspaceId: workspace.id,
      runs: initialData.runs,
      queue: initialData.queue,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      // ConnectedDataDependencies is the migration cleanup adapter: it closes
      // notification resources and the session-owned repository notifiers.
      // This scope is the canonical disposer and invokes that path once.
      await _closeSession?.call();
    } catch (_) {
      // Cleanup failures must not surface as unhandled async errors.
    }
  }
}

class ConnectedSessionRepositories {
  ConnectedSessionRepositories({
    required this.authRepository,
    required this.workspaceRepository,
    required this.conversationRepository,
    required this.runRepository,
    required this.cliAdapterRepository,
    required this.commandCatalogRepository,
    required this.diagnosticsRepository,
    required this.appUpdateRepository,
    required this.codingPreferencesRepository,
    required this.recordDiagnosticEvent,
  });

  final AuthRepository authRepository;
  final WorkspaceRepository workspaceRepository;
  final CachedConversationRepository conversationRepository;
  final CachedRunRepository runRepository;
  final CliAdapterRepository cliAdapterRepository;
  final CommandCatalogRepository commandCatalogRepository;
  final DiagnosticsRepository diagnosticsRepository;
  final AppUpdateRepository appUpdateRepository;
  final CodingPreferencesRepository codingPreferencesRepository;
  final void Function(
    String event,
    Map<String, Object?> metadata, {
    String severity,
    String? path,
  }) recordDiagnosticEvent;
}

class ConnectedSessionUseCases {
  const ConnectedSessionUseCases({
    required this.openWorkspace,
  });

  final WorkspaceOpeningUseCase openWorkspace;
}
