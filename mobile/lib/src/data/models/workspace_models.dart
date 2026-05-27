class DiffSummary {
  const DiffSummary(
      {required this.filePath,
      required this.additions,
      required this.deletions,
      required this.binary});
  final String filePath;
  final int additions;
  final int deletions;
  final bool binary;
  bool get shouldCollapse => binary || additions + deletions > 120;
  factory DiffSummary.fromJson(Map<String, Object?> json) => DiffSummary(
        filePath: (json['filePath'] as String?) ?? 'unknown file',
        additions: (json['additions'] as int?) ?? 0,
        deletions: (json['deletions'] as int?) ?? 0,
        binary: (json['binary'] as bool?) ?? false,
      );
}

class GitStatusFile {
  const GitStatusFile({required this.status, required this.path});
  final String status;
  final String path;
  factory GitStatusFile.fromJson(Map<String, Object?> json) => GitStatusFile(
      status: json['status'] as String? ?? '',
      path: json['path'] as String? ?? '');
}

class GitStatusSummary {
  const GitStatusSummary(
      {required this.workspaceId, required this.clean, required this.files});
  final String workspaceId;
  final bool clean;
  final List<GitStatusFile> files;
  factory GitStatusSummary.fromJson(Map<String, Object?> json) =>
      GitStatusSummary(
        workspaceId: json['workspaceId'] as String? ?? '',
        clean: json['clean'] as bool? ?? false,
        files: _objectList(json['files']).map(GitStatusFile.fromJson).toList(),
      );
}

class WorkspaceSummary {
  const WorkspaceSummary(
      {required this.id, required this.name, required this.path});
  final String id;
  final String name;
  final String path;
  factory WorkspaceSummary.fromJson(Map<String, Object?> json) =>
      WorkspaceSummary(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          path: json['path'] as String? ?? '');
}

class DirectoryEntrySummary {
  const DirectoryEntrySummary({required this.name, required this.path});
  final String name;
  final String path;
  factory DirectoryEntrySummary.fromJson(Map<String, Object?> json) =>
      DirectoryEntrySummary(
          name: json['name'] as String? ?? '',
          path: json['path'] as String? ?? '');
}

class DirectoryListing {
  const DirectoryListing(
      {required this.path, required this.directories, this.parent});
  final String path;
  final String? parent;
  final List<DirectoryEntrySummary> directories;
  factory DirectoryListing.fromJson(Map<String, Object?> json) =>
      DirectoryListing(
        path: json['path'] as String? ?? '',
        parent: json['parent'] as String?,
        directories: _objectList(json['directories'])
            .map(DirectoryEntrySummary.fromJson)
            .toList(),
      );
}

class ProjectOverview {
  const ProjectOverview(
      {required this.workspaceId,
      required this.name,
      required this.path,
      required this.fileCount,
      required this.codeLineCount,
      required this.symbolCount,
      required this.analysisScore,
      required this.recentFiles});
  final String workspaceId;
  final String name;
  final String path;
  final int fileCount;
  final int codeLineCount;
  final int symbolCount;
  final int analysisScore;
  final List<RecentFileSummary> recentFiles;
  factory ProjectOverview.fromJson(Map<String, Object?> json) =>
      ProjectOverview(
        workspaceId: json['workspaceId'] as String,
        name: json['name'] as String,
        path: json['path'] as String? ?? '',
        fileCount: json['fileCount'] as int,
        codeLineCount: json['codeLineCount'] as int,
        symbolCount: json['symbolCount'] as int,
        analysisScore: json['analysisScore'] as int,
        recentFiles: _objectList(json['recentFiles'])
            .map(RecentFileSummary.fromJson)
            .toList(),
      );
}

class RecentFileSummary {
  const RecentFileSummary({required this.path, required this.modifiedAt});
  final String path;
  final DateTime modifiedAt;
  factory RecentFileSummary.fromJson(Map<String, Object?> json) =>
      RecentFileSummary(
          path: json['path'] as String? ?? '',
          modifiedAt: DateTime.parse(json['modifiedAt'] as String));
}

class FileTreeResponse {
  const FileTreeResponse(
      {required this.workspaceId, required this.root, required this.entries});
  final String workspaceId;
  final String root;
  final List<FileTreeEntry> entries;
  factory FileTreeResponse.fromJson(Map<String, Object?> json) =>
      FileTreeResponse(
        workspaceId: json['workspaceId'] as String? ?? '',
        root: json['root'] as String? ?? '',
        entries:
            _objectList(json['entries']).map(FileTreeEntry.fromJson).toList(),
      );
}

class FileTreeEntry {
  const FileTreeEntry(
      {required this.name,
      required this.path,
      required this.type,
      required this.children});
  final String name;
  final String path;
  final String type;
  final List<FileTreeEntry> children;
  bool get isDirectory => type == 'directory';
  factory FileTreeEntry.fromJson(Map<String, Object?> json) => FileTreeEntry(
        name: json['name'] as String,
        path: json['path'] as String? ?? '',
        type: json['type'] as String,
        children:
            _objectList(json['children']).map(FileTreeEntry.fromJson).toList(),
      );
}

class FileContent {
  const FileContent(
      {required this.workspaceId,
      required this.path,
      required this.binary,
      required this.tooLarge,
      required this.size,
      required this.content,
      this.language});
  final String workspaceId;
  final String path;
  final bool binary;
  final bool tooLarge;
  final int size;
  final String content;
  final String? language;
  factory FileContent.fromJson(Map<String, Object?> json) => FileContent(
        workspaceId: json['workspaceId'] as String,
        path: json['path'] as String? ?? '',
        binary: json['binary'] as bool? ?? false,
        tooLarge: json['tooLarge'] as bool? ?? false,
        size: json['size'] as int? ?? 0,
        content: json['content'] as String? ?? '',
        language: json['language'] as String?,
      );
}

class GitCommitSummary {
  const GitCommitSummary(
      {required this.hash,
      required this.shortHash,
      required this.subject,
      required this.author,
      required this.date});
  final String hash;
  final String shortHash;
  final String subject;
  final String author;
  final String date;
  factory GitCommitSummary.fromJson(Map<String, Object?> json) =>
      GitCommitSummary(
          hash: json['hash'] as String? ?? '',
          shortHash: json['shortHash'] as String? ?? '',
          subject: json['subject'] as String? ?? '',
          author: json['author'] as String? ?? '',
          date: json['date'] as String? ?? '');
}

class CodeDiagnostic {
  const CodeDiagnostic(
      {required this.path,
      required this.line,
      required this.column,
      required this.severity,
      required this.message});
  final String path;
  final int line;
  final int column;
  final String severity;
  final String message;
  factory CodeDiagnostic.fromJson(Map<String, Object?> json) => CodeDiagnostic(
      path: json['path'] as String? ?? '',
      line: json['line'] as int,
      column: json['column'] as int,
      severity: json['severity'] as String,
      message: json['message'] as String);
}

class CodeDiagnosticsSummary {
  const CodeDiagnosticsSummary(
      {required this.workspaceId,
      required this.available,
      required this.diagnostics});
  final String workspaceId;
  final bool available;
  final List<CodeDiagnostic> diagnostics;
  factory CodeDiagnosticsSummary.fromJson(Map<String, Object?> json) =>
      CodeDiagnosticsSummary(
        workspaceId: json['workspaceId'] as String? ?? '',
        available: json['available'] as bool? ?? true,
        diagnostics: _objectList(json['diagnostics'])
            .map(CodeDiagnostic.fromJson)
            .toList(),
      );
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! Iterable) {
    return const <Map<String, Object?>>[];
  }
  return value
      .whereType<Map>()
      .map(_objectMap)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, Object?> _objectMap(Map<dynamic, dynamic> value) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      result[key] = entry.value;
    }
  }
  return result;
}
