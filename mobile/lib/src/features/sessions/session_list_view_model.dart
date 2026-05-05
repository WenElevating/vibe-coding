import '../../models/protocol.dart';
import 'session_item.dart';

List<SessionItem> mergeSessionItems(
    List<SessionItem> localSessions,
    List<ConversationSummary> snapshotConversations,
    List<RunSummary> snapshotRuns) {
  final items = <SessionItem>[];
  final seen = <String>{};
  for (final item in localSessions) {
    if (seen.add(item.id)) items.add(item);
  }
  for (final conversation in snapshotConversations) {
    if (conversation.status == 'idle' && conversation.cliSessionId == null) {
      continue;
    }
    if (seen.add(conversation.id)) {
      items.add(SessionItem(
          run: runSummaryFromConversation(conversation),
          conversation: conversation));
    }
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) items.add(SessionItem(run: run));
  }
  return items;
}

RunSummary runSummaryFromConversation(ConversationSummary conversation) {
  return RunSummary(
      id: conversation.id,
      tool: conversation.adapter,
      workspaceId: conversation.workspaceId,
      status: runStatusFromConversation(conversation.status),
      cliSessionId: conversation.cliSessionId);
}

String runStatusFromConversation(String status) {
  if (status == 'idle') return 'completed';
  if (status == 'cancelled' || status == 'failed') return status;
  return 'running';
}
