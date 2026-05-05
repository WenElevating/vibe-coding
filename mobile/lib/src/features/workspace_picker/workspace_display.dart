import '../../models/protocol.dart';

String workspaceDisplayName(WorkspaceSummary workspace) {
  if (workspace.name.trim().isNotEmpty &&
      workspace.name.toLowerCase() != 'current project') {
    return workspace.name;
  }
  final normalized = workspace.path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? '当前工作区' : parts.last;
}
