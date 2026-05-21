import 'dart:async';

import '../../../models/protocol.dart';

export 'workbench_route_state.dart';

bool canSendInConversationStatus(String? status) {
  return status == null ||
      status == 'idle' ||
      status == 'cancelled' ||
      status == 'failed' ||
      status == 'interrupted';
}

bool isActiveConversationStatus(String? status) {
  return status == 'sending' ||
      status == 'running' ||
      status == 'waiting_input' ||
      status == 'waiting_approval';
}

bool shouldKeepPollingForTerminalDrain({
  required bool isRunningCli,
  required bool changed,
  required bool drainPending,
}) {
  if (isRunningCli) return true;
  if (drainPending) return false;
  return changed;
}

bool isSendAcknowledgementTimeout(
  Object error, {
  required String? activeConversationId,
  required String? activeRunId,
}) {
  return error is TimeoutException &&
      (activeConversationId != null || activeRunId != null);
}

ConversationSummary applyCancelledConversationSummary(
  ConversationSummary conversation,
) {
  return ConversationSummary(
    id: conversation.id,
    workspaceId: conversation.workspaceId,
    adapter: conversation.adapter,
    status: conversation.status,
    capabilities: conversation.capabilities,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
    protocolVersion: conversation.protocolVersion,
    requestedPermissionMode: conversation.requestedPermissionMode,
    effectivePermissionMode: conversation.effectivePermissionMode,
    permissionSupport: conversation.permissionSupport,
    cliSessionId: conversation.cliSessionId,
    sessionBinding: conversation.sessionBinding,
    userMessageCount: conversation.userMessageCount,
    blockingItem: null,
    idleExpiresAt: conversation.idleExpiresAt,
  );
}
