const protocolVersion = 'agent-control.v1';

bool isTerminalAgentEventType(String type) =>
    type == 'run.completed' || type == 'run.failed' || type == 'run.cancelled';

class AgentEvent {
  const AgentEvent({
    required this.type,
    required this.seq,
    required this.runId,
    required this.createdAt,
    this.text,
    this.name,
    this.approvalId,
    this.diff,
    this.raw = const <String, Object?>{},
  });

  final String type;
  final int seq;
  final String runId;
  final DateTime createdAt;
  final String? text;
  final String? name;
  final String? approvalId;
  final DiffSummary? diff;
  final Map<String, Object?> raw;

  factory AgentEvent.fromJson(Map<String, Object?> json) {
    return AgentEvent(
      type: json['type'] as String,
      seq: json['seq'] as int,
      runId: json['runId'] as String,
      createdAt: DateTime.parse(
          json['createdAt'] as String? ?? DateTime.now().toIso8601String()),
      text: json['text'] as String?,
      name: (json['name'] ?? json['toolName']) as String?,
      approvalId: json['approvalId'] as String?,
      diff: json['type'] == 'diff.summary' ? DiffSummary.fromJson(json) : null,
      raw: json,
    );
  }
}

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

class AdapterStatus {
  const AdapterStatus(
      {required this.adapter,
      required this.available,
      required this.status,
      this.version,
      this.error,
      this.actionable,
      this.capabilities = const <String, Object?>{}});
  final String adapter;
  final bool available;
  final String status;
  final String? version;
  final String? error;
  final String? actionable;
  final Map<String, Object?> capabilities;
  factory AdapterStatus.fromJson(Map<String, Object?> json) => AdapterStatus(
        adapter: json['adapter'] as String? ?? '',
        available: json['available'] as bool? ?? false,
        status: json['status'] as String? ??
            (json['available'] == true ? 'available' : 'unavailable'),
        version: json['version'] as String?,
        error: json['error'] as String?,
        actionable: json['actionable'] as String?,
        capabilities: (json['capabilities'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      );
  String get statusText {
    if (available) return status;
    if (error != null) return error!;
    return actionable ?? status;
  }
}

class CommandTemplate {
  const CommandTemplate(
      {required this.id,
      required this.label,
      required this.prompt,
      required this.requiresApproval});
  final String id;
  final String label;
  final String prompt;
  final bool requiresApproval;
  factory CommandTemplate.fromJson(Map<String, Object?> json) =>
      CommandTemplate(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        requiresApproval: json['requiresApproval'] as bool? ?? true,
      );
}

class QueueItem {
  const QueueItem(
      {required this.runId,
      required this.workspaceId,
      required this.position,
      required this.status,
      required this.reason});
  final String runId;
  final String workspaceId;
  final int position;
  final String status;
  final String reason;
  factory QueueItem.fromJson(Map<String, Object?> json) => QueueItem(
        runId: json['runId'] as String? ?? '',
        workspaceId: json['workspaceId'] as String? ?? '',
        position: json['position'] as int? ?? 0,
        status: json['status'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
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
        files: (json['files'] as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(GitStatusFile.fromJson)
            .toList(),
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
        directories:
            ((json['directories'] as List<Object?>?) ?? const <Object?>[])
                .cast<Map<String, Object?>>()
                .map(DirectoryEntrySummary.fromJson)
                .toList(),
      );
}

class RunSummary {
  const RunSummary(
      {required this.id,
      required this.tool,
      required this.workspaceId,
      required this.status,
      this.cliSessionId});
  final String id;
  final String tool;
  final String workspaceId;
  final String status;
  final String? cliSessionId;
  factory RunSummary.fromJson(Map<String, Object?> json) => RunSummary(
      id: json['id'] as String? ?? '',
      tool: json['tool'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      cliSessionId: json['cliSessionId'] as String?);
}

class DaemonVersionInfo {
  const DaemonVersionInfo(
      {required this.daemonVersion,
      required this.apiVersion,
      required this.schemaVersion,
      required this.mode,
      required this.minMobileVersion});
  final String daemonVersion;
  final String apiVersion;
  final int schemaVersion;
  final String mode;
  final String minMobileVersion;
  factory DaemonVersionInfo.fromJson(Map<String, Object?> json) =>
      DaemonVersionInfo(
        daemonVersion: json['daemonVersion'] as String? ?? '',
        apiVersion: json['apiVersion'] as String? ?? '',
        schemaVersion: json['schemaVersion'] as int? ?? 0,
        mode: json['mode'] as String? ?? '',
        minMobileVersion: json['minMobileVersion'] as String? ?? '',
      );
}

class DaemonHealth {
  const DaemonHealth(
      {required this.status,
      required this.daemonVersion,
      required this.mode,
      required this.lanMode,
      required this.bindAddress,
      required this.port,
      required this.security});
  final String status;
  final String daemonVersion;
  final String mode;
  final bool lanMode;
  final String bindAddress;
  final int port;
  final Map<String, Object?> security;
  factory DaemonHealth.fromJson(Map<String, Object?> json) => DaemonHealth(
        status: json['status'] as String,
        daemonVersion: json['daemonVersion'] as String? ?? '',
        mode: json['mode'] as String? ?? '',
        lanMode: json['lanMode'] as bool,
        bindAddress: json['bindAddress'] as String,
        port: json['port'] as int,
        security: (json['security'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      );
}

class DiagnosticBundleSummary {
  const DiagnosticBundleSummary(
      {required this.bundleId,
      required this.createdAt,
      required this.path,
      required this.redacted,
      required this.items});
  final String bundleId;
  final DateTime createdAt;
  final String path;
  final bool redacted;
  final List<String> items;
  factory DiagnosticBundleSummary.fromJson(Map<String, Object?> json) =>
      DiagnosticBundleSummary(
        bundleId: json['bundleId'] as String? ?? '',
        createdAt: DateTime.parse(
            json['createdAt'] as String? ?? DateTime.now().toIso8601String()),
        path: json['path'] as String? ?? '',
        redacted: json['redacted'] as bool? ?? false,
        items: (json['items'] as List<Object?>).cast<String>(),
      );
}

class ShortcutCommand {
  const ShortcutCommand(
      {required this.id,
      required this.label,
      required this.prompt,
      required this.tool});
  final String id;
  final String label;
  final String prompt;
  final String tool;
  factory ShortcutCommand.fromJson(Map<String, Object?> json) =>
      ShortcutCommand(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        tool: json['tool'] as String,
      );
}

class SmokeTestResult {
  const SmokeTestResult(
      {required this.ok, required this.adapter, required this.events});
  final bool ok;
  final String adapter;
  final int events;
  factory SmokeTestResult.fromJson(Map<String, Object?> json) =>
      SmokeTestResult(
          ok: json['ok'] as bool,
          adapter: json['adapter'] as String? ?? '',
          events: json['events'] as int);
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
        recentFiles:
            ((json['recentFiles'] as List<Object?>?) ?? const <Object?>[])
                .cast<Map<String, Object?>>()
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
        entries: ((json['entries'] as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>()
            .map(FileTreeEntry.fromJson)
            .toList(),
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
        children: ((json['children'] as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>()
            .map(FileTreeEntry.fromJson)
            .toList(),
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
        diagnostics:
            ((json['diagnostics'] as List<Object?>?) ?? const <Object?>[])
                .cast<Map<String, Object?>>()
                .map(CodeDiagnostic.fromJson)
                .toList(),
      );
}

class ExtensionSummary {
  const ExtensionSummary(
      {required this.id,
      required this.name,
      required this.version,
      required this.installed,
      required this.status,
      required this.description});
  final String id;
  final String name;
  final String version;
  final bool installed;
  final String status;
  final String description;
  factory ExtensionSummary.fromJson(Map<String, Object?> json) =>
      ExtensionSummary(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          version: json['version'] as String? ?? '',
          installed: json['installed'] as bool? ?? false,
          status: json['status'] as String? ?? 'unknown',
          description: json['description'] as String? ?? '');
}

class ConversationCapabilities {
  const ConversationCapabilities({
    required this.longLivedProcess,
    required this.waitingInput,
    required this.waitingApproval,
    required this.resume,
    required this.partialOutput,
  });

  final bool longLivedProcess;
  final bool waitingInput;
  final bool waitingApproval;
  final bool resume;
  final bool partialOutput;

  factory ConversationCapabilities.fromJson(Map<String, Object?> json) =>
      ConversationCapabilities(
        longLivedProcess: json['longLivedProcess'] as bool? ?? false,
        waitingInput: json['waitingInput'] as bool? ?? false,
        waitingApproval: json['waitingApproval'] as bool? ?? false,
        resume: json['resume'] as bool? ?? false,
        partialOutput: json['partialOutput'] as bool? ?? false,
      );
}

class ConversationBlockingItem {
  const ConversationBlockingItem({
    required this.type,
    this.questionId,
    this.approvalId,
    this.toolUseId,
    this.text,
    this.toolName,
    this.summary,
    this.suggestions = const <String>[],
    this.input = const <String, Object?>{},
    this.multiSelect = false,
    this.createdAt,
    this.expiresAt,
  });

  final String type;
  final String? questionId;
  final String? approvalId;
  final String? toolUseId;
  final String? text;
  final String? toolName;
  final String? summary;
  final List<String> suggestions;
  final Map<String, Object?> input;
  final bool multiSelect;
  final String? createdAt;
  final String? expiresAt;

  factory ConversationBlockingItem.fromJson(Map<String, Object?> json) =>
      ConversationBlockingItem(
        type: json['type'] as String? ?? '',
        questionId: json['questionId'] as String?,
        approvalId: json['approvalId'] as String?,
        toolUseId: json['toolUseId'] as String?,
        text: json['text'] as String?,
        toolName: json['toolName'] as String?,
        summary: json['summary'] as String?,
        suggestions:
            ((json['suggestions'] as List<Object?>?) ?? const <Object?>[])
                .map((item) => item.toString())
                .toList(),
        input: (json['input'] as Map<String, Object?>?) ??
            const <String, Object?>{},
        multiSelect: json['multiSelect'] as bool? ?? false,
        createdAt: json['createdAt'] as String?,
        expiresAt: json['expiresAt'] as String?,
      );
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.workspaceId,
    required this.adapter,
    required this.status,
    required this.capabilities,
    required this.createdAt,
    required this.updatedAt,
    this.protocolVersion = 1,
    this.requestedPermissionMode = '',
    this.effectivePermissionMode = '',
    this.permissionSupport = const <String, Object?>{},
    this.cliSessionId,
    this.sessionBinding = 'unknown',
    this.userMessageCount = 0,
    this.blockingItem,
    this.idleExpiresAt,
  });

  final String id;
  final String workspaceId;
  final String adapter;
  final String status;
  final String? cliSessionId;
  final String sessionBinding;
  final int userMessageCount;
  final ConversationBlockingItem? blockingItem;
  final String? idleExpiresAt;
  final String createdAt;
  final String updatedAt;
  final ConversationCapabilities capabilities;
  final int protocolVersion;
  final String requestedPermissionMode;
  final String effectivePermissionMode;
  final Map<String, Object?> permissionSupport;

  factory ConversationSummary.fromJson(Map<String, Object?> json) =>
      ConversationSummary(
        id: json['id'] as String? ?? '',
        workspaceId: json['workspaceId'] as String? ?? '',
        adapter: json['adapter'] as String? ?? '',
        status: json['status'] as String? ?? '',
        cliSessionId: json['cliSessionId'] as String?,
        sessionBinding: json['sessionBinding'] as String? ?? 'unknown',
        userMessageCount: json['userMessageCount'] as int? ?? 0,
        blockingItem: json['blockingItem'] is Map<String, Object?>
            ? ConversationBlockingItem.fromJson(
                json['blockingItem']! as Map<String, Object?>)
            : null,
        idleExpiresAt: json['idleExpiresAt'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
        capabilities: ConversationCapabilities.fromJson(
            (json['capabilities'] as Map<String, Object?>?) ??
                const <String, Object?>{}),
        protocolVersion: json['protocolVersion'] as int? ?? 1,
        requestedPermissionMode:
            json['requestedPermissionMode'] as String? ?? '',
        effectivePermissionMode:
            json['effectivePermissionMode'] as String? ?? '',
        permissionSupport:
            (json['permissionSupport'] as Map<String, Object?>?) ??
                const <String, Object?>{},
      );
}

class ConversationEvent {
  const ConversationEvent({
    required this.type,
    required this.seq,
    required this.conversationId,
    required this.createdAt,
    this.text,
    this.questionId,
    this.approvalId,
    this.toolUseId,
    this.toolName,
    this.summary,
    this.suggestions = const <String>[],
    this.input = const <String, Object?>{},
    this.exitCode,
    this.isError = false,
    this.durationMs,
    this.raw = const <String, Object?>{},
  });

  final String type;
  final int seq;
  final String conversationId;
  final DateTime createdAt;
  final String? text;
  final String? questionId;
  final String? approvalId;
  final String? toolUseId;
  final String? toolName;
  final String? summary;
  final List<String> suggestions;
  final Map<String, Object?> input;
  final int? exitCode;
  final bool isError;
  final int? durationMs;
  final Map<String, Object?> raw;

  factory ConversationEvent.fromJson(Map<String, Object?> json) =>
      ConversationEvent(
        type: json['type'] as String? ?? '',
        seq: json['seq'] as int? ?? 0,
        conversationId: json['conversationId'] as String? ?? '',
        createdAt: DateTime.parse(
            json['createdAt'] as String? ?? DateTime.now().toIso8601String()),
        text: json['text'] as String?,
        questionId: json['questionId'] as String?,
        approvalId: json['approvalId'] as String?,
        toolUseId: json['toolUseId'] as String?,
        toolName: json['toolName'] as String?,
        summary: json['summary'] as String?,
        suggestions:
            ((json['suggestions'] as List<Object?>?) ?? const <Object?>[])
                .map((item) => item.toString())
                .toList(),
        input: (json['input'] as Map<String, Object?>?) ??
            const <String, Object?>{},
        exitCode: json['exitCode'] as int?,
        isError: json['isError'] as bool? ?? false,
        durationMs: json['durationMs'] as int?,
        raw: json,
      );
}
