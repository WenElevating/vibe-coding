import '../../models/protocol.dart';

abstract class WorkspaceCreationClient {
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  });

  Future<List<WorkspaceSummary>> listWorkspaces();
}

abstract class WorkspaceRepository implements WorkspaceCreationClient {
  @override
  Future<List<WorkspaceSummary>> listWorkspaces();

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  });

  Future<ProjectOverview> projectOverview(String workspaceId);

  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path,
    int maxDepth,
  });

  Future<FileContent> fileContent(String workspaceId, String path);

  Future<GitStatusSummary> gitStatus(String workspaceId);

  Future<List<DiffSummary>> gitDiff(String workspaceId);

  Future<List<GitCommitSummary>> gitCommits(
    String workspaceId, {
    int limit,
  });

  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId);

  Future<List<DirectoryEntrySummary>> listFileSystemRoots();

  Future<DirectoryListing> listDirectory(String path);
}
