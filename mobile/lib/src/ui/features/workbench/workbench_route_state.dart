import '../../../models/protocol.dart';

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
