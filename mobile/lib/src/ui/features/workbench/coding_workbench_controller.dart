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

bool shouldApplyConversationSendAcknowledgement({
  required int sendStartSeq,
  required int currentSeq,
  required String acknowledgementStatus,
  required String reducerStatus,
}) {
  if (currentSeq <= sendStartSeq) return true;
  if (isActiveConversationStatus(acknowledgementStatus) &&
      !isActiveConversationStatus(reducerStatus)) {
    return false;
  }
  return true;
}

class WorkbenchPollTraceEntry {
  const WorkbenchPollTraceEntry({
    required this.conversationId,
    required this.runId,
    required this.path,
    required this.afterSeq,
    required this.returnedCount,
    required this.durationMs,
    required this.cancelled,
    required this.changed,
    required this.terminalDrainPending,
    this.error,
  });

  final String conversationId;
  final String runId;
  final String path;
  final int afterSeq;
  final int? returnedCount;
  final int durationMs;
  final bool cancelled;
  final bool changed;
  final bool terminalDrainPending;
  final String? error;

  bool get isError => error != null && error!.isNotEmpty;

  String get status {
    if (isError) return 'error';
    if (cancelled) return 'cancelled';
    return 'success';
  }

  String get message => 'pollConversationEvents: $status';

  Map<String, Object?> toMetadata() => <String, Object?>{
        'operation': 'pollConversationEvents',
        'afterSeq': afterSeq,
        'returnedCount': returnedCount,
        'durationMs': durationMs,
        'cancelled': cancelled,
        'changed': changed,
        'terminalDrainPending': terminalDrainPending,
        'status': status,
        if (error != null) 'error': error,
      };
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
    title: conversation.title,
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
