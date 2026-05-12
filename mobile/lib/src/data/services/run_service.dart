import '../../models/protocol.dart';

abstract class RunService {
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  });

  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode,
  });

  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq});

  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode,
  });

  Future<RunSummary> cancelRun(String runId);

  Future<void> respondApproval(String approvalId, String decision);
}
