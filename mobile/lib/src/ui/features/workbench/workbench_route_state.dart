sealed class WorkbenchRouteState {
  const WorkbenchRouteState();
}

final class WorkspaceListRouteState extends WorkbenchRouteState {
  const WorkspaceListRouteState({this.notice});

  final String? notice;
}

final class CreatingWorkspaceRouteState extends WorkbenchRouteState {
  const CreatingWorkspaceRouteState({required this.requestLabel});

  final String requestLabel;
}

final class WorkspaceSessionsRouteState extends WorkbenchRouteState {
  const WorkspaceSessionsRouteState({required this.workspaceId});

  final String workspaceId;
}

final class ConversationRouteState extends WorkbenchRouteState {
  const ConversationRouteState({
    required this.workspaceId,
    required this.conversationId,
  });

  final String workspaceId;
  final String conversationId;
}
