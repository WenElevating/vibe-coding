import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../../workspace_picker/workspace_picker.dart';

class WorkbenchWorkspaceRoute extends StatelessWidget {
  const WorkbenchWorkspaceRoute({
    super.key,
    required this.workspaces,
    required this.onSelected,
    required this.onAddWorkspace,
  });

  final List<WorkspaceSummary> workspaces;
  final ValueChanged<WorkspaceSummary> onSelected;
  final VoidCallback onAddWorkspace;

  @override
  Widget build(BuildContext context) => WorkspaceListPage(
        workspaces: workspaces,
        onSelected: onSelected,
        onAddWorkspace: onAddWorkspace,
      );
}
