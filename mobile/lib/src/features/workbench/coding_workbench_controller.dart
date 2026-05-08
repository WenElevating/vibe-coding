import '../../models/protocol.dart';

enum CodingWorkbenchListMode { workspaces, sessions, conversation }

class CodingWorkbenchState {
  const CodingWorkbenchState({
    required this.workspaces,
    required this.selectedWorkspace,
    required this.listMode,
  });

  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary selectedWorkspace;
  final CodingWorkbenchListMode listMode;
}

CodingWorkbenchState upsertAndSelectWorkspace(
  CodingWorkbenchState state,
  WorkspaceSummary workspace,
) {
  final workspaces = List<WorkspaceSummary>.of(state.workspaces);
  final index = workspaces.indexWhere((item) => item.id == workspace.id);
  if (index >= 0) {
    workspaces[index] = workspace;
  } else {
    workspaces.add(workspace);
  }
  return CodingWorkbenchState(
    workspaces: workspaces,
    selectedWorkspace: workspace,
    listMode: CodingWorkbenchListMode.sessions,
  );
}

CodingWorkbenchState replaceWorkspacesFromDaemon(
  CodingWorkbenchState state,
  List<WorkspaceSummary> daemonWorkspaces, {
  String? selectedWorkspaceId,
}) {
  if (daemonWorkspaces.isEmpty) return state;
  final selected = daemonWorkspaces.firstWhere(
    (workspace) => workspace.id == selectedWorkspaceId,
    orElse: () => daemonWorkspaces.firstWhere(
      (workspace) => workspace.id == state.selectedWorkspace.id,
      orElse: () => daemonWorkspaces.first,
    ),
  );
  return CodingWorkbenchState(
    workspaces: List<WorkspaceSummary>.of(daemonWorkspaces),
    selectedWorkspace: selected,
    listMode: state.listMode,
  );
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
