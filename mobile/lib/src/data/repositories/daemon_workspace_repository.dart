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
  int _operationGeneration = 0;

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
    final generation = _startOperation();
    try {
      final loaded = await _listWorkspacesFromClient();
      if (_isCurrentOperation(generation)) {
        _applyWorkspaceCatalog(loaded);
      }
    } catch (error) {
      if (_isCurrentOperation(generation)) {
        _error = error;
      }
      rethrow;
    } finally {
      _finishOperation(generation);
    }
  }

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) =>
      _createAndRefresh(path: path, name: name);

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
  Future<List<WorkspaceSummary>> listWorkspaces() =>
      _listWorkspacesFromClient();

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) =>
      _createAndRefresh(path: path, name: name);

  Future<WorkspaceSummary> _createAndRefresh({
    required String path,
    String? name,
  }) async {
    final generation = _startOperation();
    try {
      final created = await _createWorkspaceOnClient(path: path, name: name);
      final refreshed = await _listWorkspacesFromClient();
      if (_isCurrentOperation(generation)) {
        _applyWorkspaceCatalog(refreshed, preferredWorkspaceId: created.id);
      }
      return created;
    } catch (error) {
      if (_isCurrentOperation(generation)) {
        _error = error;
      }
      rethrow;
    } finally {
      _finishOperation(generation);
    }
  }

  int _startOperation() {
    final generation = ++_operationGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    return generation;
  }

  bool _isCurrentOperation(int generation) =>
      generation == _operationGeneration;

  void _finishOperation(int generation) {
    if (_isCurrentOperation(generation)) {
      _loading = false;
      notifyListeners();
    }
  }

  void _applyWorkspaceCatalog(
    List<WorkspaceSummary> workspaces, {
    String? preferredWorkspaceId,
  }) {
    _workspaces = List<WorkspaceSummary>.unmodifiable(workspaces);
    _selectedWorkspaceId = _resolveSelectedWorkspaceId(
      preferredWorkspaceId ?? _selectedWorkspaceId,
      _workspaces,
    );
  }

  Future<List<WorkspaceSummary>> _listWorkspacesFromClient() =>
      _client.listWorkspaces();

  Future<WorkspaceSummary> _createWorkspaceOnClient({
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
