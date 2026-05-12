import '../../domain/repositories/run_repository.dart';
import '../../models/protocol.dart';
import '../../services/daemon_client.dart';

class DaemonRunRepository implements RunRepository {
  DaemonRunRepository({required DaemonClient client}) : _client = client;

  final DaemonClient _client;

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) =>
      _client.listRuns(tool: tool, workspaceId: workspaceId, status: status);

  @override
  Future<List<QueueItem>> listQueue() => _client.listQueue();

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) =>
      _client.createRun(
        tool: tool,
        workspaceId: workspaceId,
        prompt: prompt,
        shortcutId: shortcutId,
        permissionMode: permissionMode,
      );

  @override
  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq = 0}) =>
      _client.fetchEvents(runId, afterSeq: afterSeq);

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) =>
      _client.sendRunInput(runId, prompt, permissionMode: permissionMode);

  @override
  Future<RunSummary> cancelRun(String runId) => _client.cancelRun(runId);

  @override
  Future<void> respondApproval(String approvalId, String decision) =>
      _client.respondApproval(approvalId, decision);

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) =>
      _client.invokeCommandTemplate(
        templateId: templateId,
        workspaceId: workspaceId,
        tool: tool,
      );
}
