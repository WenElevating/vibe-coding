import 'dart:async';

import '../../models/protocol.dart';

abstract class WorkspaceCreationClient {
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  });

  Future<List<WorkspaceSummary>> listWorkspaces();
}

sealed class CreateWorkspaceOutcome {
  const CreateWorkspaceOutcome();
}

final class CreateWorkspaceSuccess extends CreateWorkspaceOutcome {
  const CreateWorkspaceSuccess({
    required this.workspace,
    required this.workspaces,
  });

  final WorkspaceSummary workspace;
  final List<WorkspaceSummary> workspaces;
}

final class CreateWorkspaceNotConfirmed extends CreateWorkspaceOutcome {
  const CreateWorkspaceNotConfirmed({
    required this.workspaceId,
    required this.workspaces,
  });

  final String workspaceId;
  final List<WorkspaceSummary> workspaces;
}

final class CreateWorkspaceFailure extends CreateWorkspaceOutcome {
  const CreateWorkspaceFailure(this.error);

  final Object error;
}

final class CreateWorkspaceTimeout extends CreateWorkspaceOutcome {
  const CreateWorkspaceTimeout();
}

class CreateWorkspaceWorkflow {
  const CreateWorkspaceWorkflow({
    required WorkspaceCreationClient client,
    required Duration timeout,
  })  : _client = client,
        _timeout = timeout;

  final WorkspaceCreationClient _client;
  final Duration _timeout;

  Future<CreateWorkspaceOutcome> create({
    required String path,
    String? name,
  }) async {
    try {
      final workspace = await _client
          .createWorkspace(path: path, name: name)
          .timeout(_timeout);
      return retryRefresh(workspace.id);
    } on TimeoutException {
      return const CreateWorkspaceTimeout();
    } catch (error) {
      return CreateWorkspaceFailure(error);
    }
  }

  Future<CreateWorkspaceOutcome> retryRefresh(String workspaceId) async {
    try {
      final workspaces = await _client.listWorkspaces().timeout(_timeout);
      final workspace = workspaces.cast<WorkspaceSummary?>().firstWhere(
            (workspace) => workspace?.id == workspaceId,
            orElse: () => null,
          );
      if (workspace == null) {
        return CreateWorkspaceNotConfirmed(
          workspaceId: workspaceId,
          workspaces: workspaces,
        );
      }
      return CreateWorkspaceSuccess(
        workspace: workspace,
        workspaces: workspaces,
      );
    } on TimeoutException {
      return const CreateWorkspaceTimeout();
    } catch (error) {
      return CreateWorkspaceFailure(error);
    }
  }
}
