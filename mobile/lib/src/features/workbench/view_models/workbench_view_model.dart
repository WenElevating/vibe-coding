import 'package:flutter/foundation.dart';

import '../../../models/protocol.dart';
import '../../../shell/app_snapshot.dart';
import '../../sessions/session_item.dart';
import '../../sessions/session_list_view_model.dart';
import '../coding_workbench_controller.dart';

class WorkbenchViewModel extends ChangeNotifier {
  WorkbenchViewModel({required AppSnapshot initialData})
      : _routeState = WorkspaceListRouteState(
          workspaces: List.unmodifiable(initialData.workspaces),
        ),
        _selectedAdapter = _computePreferredAdapter(initialData.adapters);

  WorkbenchRouteState _routeState;
  final List<SessionItem> _localSessions = <SessionItem>[];
  String? _selectedAdapter;

  WorkbenchRouteState get routeState => _routeState;
  List<SessionItem> get localSessions => List.unmodifiable(_localSessions);
  String? get selectedAdapter => _selectedAdapter;
  List<WorkspaceSummary> get workspaces => _routeState.workspaces;

  List<SessionItem> sessionItems(
    List<ConversationSummary> snapshotConversations,
    List<RunSummary> snapshotRuns,
  ) =>
      mergeSessionItems(_localSessions, snapshotConversations, snapshotRuns);

  void showWorkspaceList({String? notice}) {
    _routeState = WorkspaceListRouteState(
      workspaces: _routeState.workspaces,
      notice: notice,
    );
    notifyListeners();
  }

  void showSessions(WorkspaceSummary workspace) {
    _routeState = WorkspaceSessionsRouteState(
      workspace: workspace,
      workspaces: _routeState.workspaces,
    );
    notifyListeners();
  }

  void showConversation(WorkspaceSummary workspace) {
    _routeState = ConversationRouteState(
      workspace: workspace,
      workspaces: _routeState.workspaces,
    );
    notifyListeners();
  }

  void showCreatingWorkspace({required String requestLabel}) {
    _routeState = CreatingWorkspaceRouteState(
      previousWorkspaces: _routeState.workspaces,
      requestLabel: requestLabel,
    );
    notifyListeners();
  }

  void confirmWorkspaceCreated({
    required WorkspaceSummary workspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    _routeState = WorkspaceSessionsRouteState(
      workspace: workspace,
      workspaces: List.unmodifiable(workspaces),
    );
    notifyListeners();
  }

  void cancelWorkspaceCreation(List<WorkspaceSummary> workspaces) {
    _routeState = WorkspaceListRouteState(
      workspaces: List.unmodifiable(workspaces),
    );
    notifyListeners();
  }

  void rememberSession(SessionItem item) {
    _localSessions.removeWhere((s) => s.id == item.id);
    _localSessions.insert(0, item);
    notifyListeners();
  }

  void setSelectedAdapter(String? adapter) {
    if (_selectedAdapter == adapter) return;
    _selectedAdapter = adapter;
    notifyListeners();
  }

  void updateFromSnapshot(AppSnapshot snapshot) {
    final workspaces = List<WorkspaceSummary>.unmodifiable(snapshot.workspaces);
    _routeState = _rebuildRouteState(workspaces);
    final stillAvailable = _selectedAdapter != null &&
        snapshot.adapters.any((a) =>
            a.adapter == _selectedAdapter &&
            a.available &&
            _isSelectableAdapter(a));
    if (!stillAvailable) {
      _selectedAdapter = _computePreferredAdapter(snapshot.adapters);
    }
    notifyListeners();
  }

  WorkbenchRouteState _rebuildRouteState(List<WorkspaceSummary> workspaces) =>
      switch (_routeState) {
        WorkspaceListRouteState(:final notice) =>
          WorkspaceListRouteState(workspaces: workspaces, notice: notice),
        WorkspaceSessionsRouteState(:final workspace) =>
          WorkspaceSessionsRouteState(
            workspace: _resolveWorkspace(workspaces, workspace),
            workspaces: workspaces,
          ),
        ConversationRouteState(:final workspace) => ConversationRouteState(
            workspace: _resolveWorkspace(workspaces, workspace),
            workspaces: workspaces,
          ),
        CreatingWorkspaceRouteState(:final requestLabel) =>
          CreatingWorkspaceRouteState(
            previousWorkspaces: workspaces,
            requestLabel: requestLabel,
          ),
      };

  static WorkspaceSummary _resolveWorkspace(
    List<WorkspaceSummary> workspaces,
    WorkspaceSummary fallback,
  ) {
    for (final w in workspaces) {
      if (w.id == fallback.id) return w;
    }
    return fallback;
  }

  static String? _computePreferredAdapter(List<AdapterStatus> adapters) {
    for (final name in const ['claude', 'codex', 'opencode']) {
      final found = adapters.where(
          (a) => a.adapter == name && a.available && _isSelectableAdapter(a));
      if (found.isNotEmpty) return found.first.adapter;
    }
    final available =
        adapters.where((a) => a.available && _isSelectableAdapter(a));
    return available.isEmpty ? null : available.first.adapter;
  }

  static bool _isSelectableAdapter(AdapterStatus adapter) {
    final id = adapter.adapter.trim().toLowerCase();
    if (id.isEmpty || id.startsWith('synthetic-')) return false;
    return const {'claude', 'codex', 'opencode'}.contains(id);
  }
}
