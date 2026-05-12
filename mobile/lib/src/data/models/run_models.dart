import 'workspace_models.dart';

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
