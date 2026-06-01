import '../../../models/protocol.dart';

List<WorkspaceSummary> dedupeWorkspacesByPath(
    Iterable<WorkspaceSummary> workspaces) {
  final seen = <String>{};
  final visible = <WorkspaceSummary>[];
  for (final workspace in workspaces) {
    final key = workspacePathPresentationKey(workspace.path);
    if (!seen.add(key)) continue;
    visible.add(workspace);
  }
  return visible;
}

String workspacePathPresentationKey(String path) {
  var normalized = path.trim().replaceAll('\\', '/').toLowerCase();
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
