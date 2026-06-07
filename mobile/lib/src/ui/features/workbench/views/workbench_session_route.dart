import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../../sessions/sessions.dart';

class WorkbenchSessionRoute extends StatelessWidget {
  const WorkbenchSessionRoute({
    super.key,
    required this.items,
    required this.currentWorkspace,
    required this.onNewSession,
    required this.onSelectItem,
    required this.onBackToWorkspaces,
    this.adapterStatusBanner,
  });

  final List<SessionItem> items;
  final WorkspaceSummary currentWorkspace;
  final VoidCallback onNewSession;
  final ValueChanged<SessionItem> onSelectItem;
  final VoidCallback onBackToWorkspaces;
  final Widget? adapterStatusBanner;

  @override
  Widget build(BuildContext context) => CodingSessionListPage(
        items: items,
        currentWorkspace: currentWorkspace,
        onNewSession: onNewSession,
        onSelectItem: onSelectItem,
        onBackToWorkspaces: onBackToWorkspaces,
        headerBanner: adapterStatusBanner,
      );
}
