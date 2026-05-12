import '../../domain/repositories/workspace_repository.dart';
import '../../models/protocol.dart';
import '../../services/daemon_client.dart';

class DaemonWorkspaceRepository implements WorkspaceRepository {
  DaemonWorkspaceRepository({required DaemonClient client}) : _client = client;

  final DaemonClient _client;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() => _client.listWorkspaces();

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) =>
      _client.createWorkspace(path: path, name: name);

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) =>
      _client.projectOverview(workspaceId);

  @override
  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path = '',
    int maxDepth = 8,
  }) =>
      _client.fileTree(workspaceId, path: path, maxDepth: maxDepth);

  @override
  Future<FileContent> fileContent(String workspaceId, String path) =>
      _client.fileContent(workspaceId, path);

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) =>
      _client.gitStatus(workspaceId);

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) =>
      _client.gitDiff(workspaceId);

  @override
  Future<List<GitCommitSummary>> gitCommits(
    String workspaceId, {
    int limit = 20,
  }) =>
      _client.gitCommits(workspaceId, limit: limit);

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) =>
      _client.codeDiagnostics(workspaceId);

  @override
  Future<List<DirectoryEntrySummary>> listFileSystemRoots() =>
      _client.listFileSystemRoots();

  @override
  Future<DirectoryListing> listDirectory(String path) =>
      _client.listDirectory(path);
}
