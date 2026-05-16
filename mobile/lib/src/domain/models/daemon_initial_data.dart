import '../../models/protocol.dart';

class DaemonInitialData {
  const DaemonInitialData({
    required this.health,
    required this.workspaces,
    required this.workspace,
    required this.adapters,
    required this.runs,
    required this.conversations,
    required this.queue,
  });

  final DaemonHealth health;
  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary workspace;
  final List<AdapterStatus> adapters;
  final List<RunSummary> runs;
  final List<ConversationSummary> conversations;
  final List<QueueItem> queue;
}
