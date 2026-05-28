import '../../models/protocol.dart';
import '../../services/daemon_client.dart';
import 'workspace_repository.dart';

class DaemonWorkspaceRepository extends WorkspaceRepository {
  DaemonWorkspaceRepository({required DaemonClient client}) : _client = client;

  final DaemonClient _client;
  List<WorkspaceSummary> _workspaces = const <WorkspaceSummary>[];
  String? _selectedWorkspaceId;
  bool _loading = false;
  Object? _error;

  @override
  List<WorkspaceSummary> get workspaces => List.unmodifiable(_workspaces);

  @override
  WorkspaceSummary? get selectedWorkspace {
    final selectedWorkspaceId = _selectedWorkspaceId;
    if (selectedWorkspaceId == null) {
      return _workspaces.isEmpty ? null : _workspaces.first;
    }
    for (final workspace in _workspaces) {
      if (workspace.id == selectedWorkspaceId) return workspace;
    }
    return _workspaces.isEmpty ? null : _workspaces.first;
  }

  @override
  bool get loading => _loading;

  @override
  Object? get error => _error;

  @override
  Future<void> load() => refresh();

  @override
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final loaded = await listWorkspaces();
      _workspaces = List<WorkspaceSummary>.unmodifiable(loaded);
      _selectedWorkspaceId = _resolveSelectedWorkspaceId(
        _selectedWorkspaceId,
        _workspaces,
      );
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final created = await createWorkspace(path: path, name: name);
      final refreshed = await listWorkspaces();
      _workspaces = List<WorkspaceSummary>.unmodifiable(refreshed);
      _selectedWorkspaceId =
          _workspaces.any((workspace) => workspace.id == created.id)
          ? created.id
          : _resolveSelectedWorkspaceId(_selectedWorkspaceId, _workspaces);
      return created;
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  bool select(String workspaceId) {
    if (!_workspaces.any((workspace) => workspace.id == workspaceId)) {
      return false;
    }
    if (_selectedWorkspaceId == workspaceId) return true;
    _selectedWorkspaceId = workspaceId;
    notifyListeners();
    return true;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() => _client.listWorkspaces();

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) => _client.createWorkspace(path: path, name: name);

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) =>
      _client.projectOverview(workspaceId);

  @override
  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path = '',
    int maxDepth = 8,
  }) => _client.fileTree(workspaceId, path: path, maxDepth: maxDepth);

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
  }) => _client.gitCommits(workspaceId, limit: limit);

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

String? _resolveSelectedWorkspaceId(
  String? currentWorkspaceId,
  List<WorkspaceSummary> workspaces,
) {
  if (currentWorkspaceId != null &&
      workspaces.any((workspace) => workspace.id == currentWorkspaceId)) {
    return currentWorkspaceId;
  }
  return workspaces.isEmpty ? null : workspaces.first.id;
}
