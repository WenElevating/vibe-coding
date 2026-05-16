import '../../models/protocol.dart';
import '../../domain/repositories/workspace_repository.dart';

abstract class WorkspaceService implements WorkspaceCreationClient {
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
