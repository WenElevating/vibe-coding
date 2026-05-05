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
