// These interfaces live in data/ for this migration because they use protocol
// models. Move them to domain/ when protocol/domain model separation lands.
import '../../models/protocol.dart';

abstract interface class WorkspaceBootstrapTarget {
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  });
}

abstract interface class ConversationBootstrapTarget {
  String? get loadedWorkspaceId;

  void replaceFromBootstrap({
    required String workspaceId,
    required List<ConversationSummary> conversations,
  });
}

abstract interface class RunBootstrapTarget {
  String? get loadedWorkspaceId;

  void replaceFromBootstrap({
    required String workspaceId,
    required List<RunSummary> runs,
    required List<QueueItem> queue,
  });
}
