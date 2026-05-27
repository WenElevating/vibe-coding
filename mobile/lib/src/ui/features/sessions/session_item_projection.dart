import '../../../models/protocol.dart';
import 'session_item.dart';

List<SessionItem> mergeSessionItems(
    List<SessionItem> localSessions,
    List<ConversationSummary> snapshotConversations,
    List<RunSummary> snapshotRuns) {
  final items = <SessionItem>[];
  final seen = <String>{};
  final localById = <String, SessionItem>{
    for (final item in localSessions) item.id: item
  };
  for (final conversation in snapshotConversations) {
    final local = localById[conversation.id];
    if (local != null && _isPendingSnapshotConversation(conversation)) {
      if (seen.add(local.id)) items.add(local);
      continue;
    }
    if (!shouldShowConversationInSessionList(conversation,
        isOptimistic: local != null)) {
      continue;
    }
    if (seen.add(conversation.id)) {
      items.add(SessionItem(
          run: runSummaryFromConversation(conversation),
          conversation: conversation));
    }
  }
  for (final item in localSessions) {
    if (seen.add(item.id)) items.add(item);
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) items.add(SessionItem(run: run));
  }
  return items;
}

bool shouldShowConversationInSessionList(ConversationSummary conversation,
    {bool isOptimistic = false}) {
  if (isOptimistic) return true;
  if (conversation.status == 'idle' &&
      conversation.cliSessionId == null &&
      conversation.userMessageCount == 0) {
    return false;
  }
  return true;
}

bool _isPendingSnapshotConversation(ConversationSummary conversation) =>
    conversation.status == 'idle' && conversation.userMessageCount == 0;

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
  if (status == 'cancelled' || status == 'failed' || status == 'interrupted') {
    return status;
  }
  return 'running';
}
