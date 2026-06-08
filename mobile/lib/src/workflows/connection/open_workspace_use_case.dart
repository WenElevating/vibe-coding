import '../../data/repositories/bootstrap_hydration.dart';
import '../../domain/models/daemon_initial_data.dart';
import '../../models/protocol.dart';

typedef LoadWorkspaceBootstrap = Future<DaemonInitialData> Function({
  required List<WorkspaceSummary> workspaces,
  required WorkspaceSummary workspace,
});

abstract interface class WorkspaceOpeningUseCase {
  Future<DaemonInitialData> open({
    required List<WorkspaceSummary> workspaces,
    required WorkspaceSummary workspace,
  });
}

class OpenWorkspaceUseCase implements WorkspaceOpeningUseCase {
  OpenWorkspaceUseCase({
    required LoadWorkspaceBootstrap loadWorkspaceBootstrap,
    required WorkspaceBootstrapTarget workspaceRepository,
    required ConversationBootstrapTarget conversationRepository,
    required RunBootstrapTarget runRepository,
  })  : _loadWorkspaceBootstrap = loadWorkspaceBootstrap,
        _workspaceRepository = workspaceRepository,
        _conversationRepository = conversationRepository,
        _runRepository = runRepository;

  final LoadWorkspaceBootstrap _loadWorkspaceBootstrap;
  final WorkspaceBootstrapTarget _workspaceRepository;
  final ConversationBootstrapTarget _conversationRepository;
  final RunBootstrapTarget _runRepository;

  @override
  Future<DaemonInitialData> open({
    required List<WorkspaceSummary> workspaces,
    required WorkspaceSummary workspace,
  }) async {
    final initialData = await _loadWorkspaceBootstrap(
      workspaces: workspaces,
      workspace: workspace,
    );
    final selectedWorkspace = initialData.workspace;
    _workspaceRepository.applyBootstrapCatalog(
      selectedWorkspace: selectedWorkspace,
      workspaces: initialData.workspaces,
    );
    if (selectedWorkspace == null) {
      _conversationRepository.clearFromBootstrap();
      _runRepository.clearFromBootstrap();
      return initialData;
    }
    _conversationRepository.replaceFromBootstrap(
      workspaceId: selectedWorkspace.id,
      conversations: initialData.conversations,
    );
    _runRepository.replaceFromBootstrap(
      workspaceId: selectedWorkspace.id,
      runs: initialData.runs,
      queue: initialData.queue,
    );
    return initialData;
  }
}
