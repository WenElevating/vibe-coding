import '../../models/protocol.dart';

// These interfaces live in data/ for this migration because they use protocol
// models. Move them to domain/ when protocol/domain model separation lands.
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
