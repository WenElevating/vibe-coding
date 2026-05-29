import '../../models/protocol.dart';
import '../../services/daemon_client.dart';
import 'workspace_repository.dart';

class DaemonWorkspaceRepository extends WorkspaceRepository {
  DaemonWorkspaceRepository({required DaemonClient client}) : _client = client;

  final DaemonClient _client;
  List<WorkspaceSummary> _workspaces = const <WorkspaceSummary>[];
  String? _selectedWorkspaceId;
  bool _hasExplicitSelectionState = false;
  bool _loading = false;
  Object? _error;
  int _operationGeneration = 0;
  bool _disposed = false;

  @override
  List<WorkspaceSummary> get workspaces => _workspaces;

  @override
  WorkspaceSummary? get selectedWorkspace {
    final selectedWorkspaceId = _selectedWorkspaceId;
    if (_hasExplicitSelectionState && selectedWorkspaceId == null) {
      return null;
    }
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
    await _refreshAndReturn(generation: generation);
  }

  @override
  Future<WorkspaceSummary> create({required String path, String? name}) =>
      _createAndRefresh(path: path, name: name);

  @override
  bool select(String workspaceId) {
    if (_disposed) return false;
    if (!_workspaces.any((workspace) => workspace.id == workspaceId)) {
      return false;
    }
    if (selectedWorkspace?.id == workspaceId) {
      _selectedWorkspaceId = workspaceId;
      _hasExplicitSelectionState = true;
      return true;
    }
    _selectedWorkspaceId = workspaceId;
    _hasExplicitSelectionState = true;
    notifyListeners();
    return true;
  }

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    if (_disposed) return;
    _operationGeneration++;
    final wasLoading = _loading;
    final hadError = _error != null;
    final nextSelectedWorkspaceId = selectedWorkspace?.id;
    final nextWorkspaces = <WorkspaceSummary>[
      ...workspaces,
      if (selectedWorkspace != null &&
          !workspaces.any(
            (workspace) => workspace.id == nextSelectedWorkspaceId,
          ))
        selectedWorkspace,
    ];
    final changed = !_sameWorkspaceCatalog(_workspaces, nextWorkspaces) ||
        _selectedWorkspaceId != nextSelectedWorkspaceId ||
        !_hasExplicitSelectionState ||
        wasLoading ||
        hadError;
    _workspaces = List<WorkspaceSummary>.unmodifiable(nextWorkspaces);
    _selectedWorkspaceId = nextSelectedWorkspaceId;
    _hasExplicitSelectionState = true;
    _loading = false;
    _error = null;
    if (changed) {
      _notifyListeners();
    }
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final generation = _startOperation();
    return _refreshAndReturn(generation: generation);
  }

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
      if (_canApplyOperation(generation)) {
        _applyWorkspaceCatalog(refreshed, preferredWorkspaceId: created.id);
      }
      return created;
    } catch (error) {
      if (_canApplyOperation(generation)) {
        _error = error;
      }
      rethrow;
    } finally {
      _finishOperation(generation);
    }
  }

  Future<List<WorkspaceSummary>> _refreshAndReturn({
    required int generation,
  }) async {
    try {
      final loaded = await _listWorkspacesFromClient();
      if (_canApplyOperation(generation)) {
        _applyWorkspaceCatalog(loaded);
      }
      return loaded;
    } catch (error) {
      if (_canApplyOperation(generation)) {
        _error = error;
      }
      rethrow;
    } finally {
      _finishOperation(generation);
    }
  }

  int _startOperation() {
    final generation = ++_operationGeneration;
    if (_disposed) return generation;
    _loading = true;
    _error = null;
    _notifyListeners();
    return generation;
  }

  bool _isCurrentOperation(int generation) =>
      generation == _operationGeneration;

  bool _canApplyOperation(int generation) =>
      !_disposed && _isCurrentOperation(generation);

  void _finishOperation(int generation) {
    if (_canApplyOperation(generation)) {
      _loading = false;
      _notifyListeners();
    }
  }

  void _applyWorkspaceCatalog(
    List<WorkspaceSummary> workspaces, {
    String? preferredWorkspaceId,
  }) {
    if (_disposed) return;
    _workspaces = List<WorkspaceSummary>.unmodifiable(workspaces);
    _selectedWorkspaceId = _resolveSelectedWorkspaceId(
      preferredWorkspaceId ?? _selectedWorkspaceId,
      _workspaces,
    );
    if (preferredWorkspaceId != null) {
      _hasExplicitSelectionState = true;
    }
  }

  Future<List<WorkspaceSummary>> _listWorkspacesFromClient() =>
      _client.listWorkspaces();

  Future<WorkspaceSummary> _createWorkspaceOnClient({
    required String path,
    String? name,
  }) =>
      _client.createWorkspace(path: path, name: name);

  void _notifyListeners() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operationGeneration++;
    super.dispose();
  }

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
  return null;
}

bool _sameWorkspaceCatalog(
  List<WorkspaceSummary> current,
  List<WorkspaceSummary> next,
) {
  if (current.length != next.length) return false;
  for (var index = 0; index < current.length; index++) {
    final currentWorkspace = current[index];
    final nextWorkspace = next[index];
    if (currentWorkspace.id != nextWorkspace.id ||
        currentWorkspace.name != nextWorkspace.name ||
        currentWorkspace.path != nextWorkspace.path) {
      return false;
    }
  }
  return true;
}
