bool conversationEventCompletesTurn(ConversationEvent event) {
  if (event.type == 'conversation.completed') return true;
  if (event.type != 'assistant.message') return false;
  return event.raw['turnFinal'] != false;
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
