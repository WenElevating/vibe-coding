import '../../models/protocol.dart';

sealed class WorkbenchRouteState {
  const WorkbenchRouteState();

  List<WorkspaceSummary> get workspaces;
}

final class WorkspaceListRouteState extends WorkbenchRouteState {
  const WorkspaceListRouteState({required this.workspaces, this.notice});

  @override
  final List<WorkspaceSummary> workspaces;
  final String? notice;
}

final class CreatingWorkspaceRouteState extends WorkbenchRouteState {
  const CreatingWorkspaceRouteState({
    required this.previousWorkspaces,
    required this.requestLabel,
  });

  final List<WorkspaceSummary> previousWorkspaces;
  final String requestLabel;

  @override
  List<WorkspaceSummary> get workspaces => previousWorkspaces;
}

final class WorkspaceSessionsRouteState extends WorkbenchRouteState {
  const WorkspaceSessionsRouteState({
    required this.workspace,
    required this.workspaces,
  });

  final WorkspaceSummary workspace;

  @override
  final List<WorkspaceSummary> workspaces;
}

final class ConversationRouteState extends WorkbenchRouteState {
  const ConversationRouteState({
    required this.workspace,
    required this.workspaces,
  });

  final WorkspaceSummary workspace;

  @override
  final List<WorkspaceSummary> workspaces;
}

WorkbenchRouteState applyWorkspaceSnapshot(
  WorkbenchRouteState state,
  List<WorkspaceSummary> snapshot,
) {
  if (snapshot.isEmpty || state is CreatingWorkspaceRouteState) return state;
  final workspaces = List<WorkspaceSummary>.of(snapshot);
  return switch (state) {
    WorkspaceListRouteState(:final notice) => WorkspaceListRouteState(
        workspaces: workspaces,
        notice: notice,
      ),
    WorkspaceSessionsRouteState(:final workspace) =>
      WorkspaceSessionsRouteState(
        workspace: workspace,
        workspaces: workspaces,
      ),
    ConversationRouteState(:final workspace) => ConversationRouteState(
        workspace: workspace,
        workspaces: workspaces,
      ),
    CreatingWorkspaceRouteState() => state,
  };
}

bool canSendInConversationStatus(String? status) {
  return status == null ||
      status == 'idle' ||
      status == 'cancelled' ||
      status == 'failed' ||
      status == 'interrupted';
}

bool isActiveConversationStatus(String? status) {
  return status == 'running' ||
      status == 'waiting_input' ||
      status == 'waiting_approval';
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
