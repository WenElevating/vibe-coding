import '../../../models/protocol.dart';

String compactWorkspacePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return '…/${parts[parts.length - 2]}/${parts.last}';
}

String workspaceDisplayName(
  WorkspaceSummary workspace, {
  required String fallbackName,
}) {
  if (workspace.name.trim().isNotEmpty) {
    return workspace.name;
  }
  final normalized = workspace.path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? fallbackName : parts.last;
}
