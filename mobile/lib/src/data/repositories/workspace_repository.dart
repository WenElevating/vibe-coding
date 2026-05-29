import 'package:flutter/foundation.dart';

import '../../domain/repositories/workspace_repository.dart' as domain;
import '../../models/protocol.dart';
import 'bootstrap_hydration.dart';

abstract class WorkspaceRepository extends ChangeNotifier
    implements domain.WorkspaceRepository, WorkspaceBootstrapTarget {
  List<WorkspaceSummary> get workspaces;
  WorkspaceSummary? get selectedWorkspace;
  bool get loading;
  Object? get error;

  Future<void> load();
  Future<void> refresh();
  Future<WorkspaceSummary> create({required String path, String? name});
  bool select(String workspaceId);
  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  });
}
