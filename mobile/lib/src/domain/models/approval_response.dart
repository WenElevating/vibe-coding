enum ApprovalDecision { allow, deny, cancel }

enum ApprovalScope { once, session }

class ApprovalResponse {
  const ApprovalResponse({
    required this.decision,
    this.scope,
    this.updatedInput,
    this.updatedPermissions = const <Map<String, Object?>>[],
    this.interrupt,
  });

  factory ApprovalResponse.allow({
    ApprovalScope scope = ApprovalScope.once,
  }) =>
      ApprovalResponse(decision: ApprovalDecision.allow, scope: scope);

  factory ApprovalResponse.deny({bool interrupt = true}) =>
      ApprovalResponse(decision: ApprovalDecision.deny, interrupt: interrupt);

  factory ApprovalResponse.cancel() =>
      const ApprovalResponse(decision: ApprovalDecision.cancel);

  final ApprovalDecision decision;
  final ApprovalScope? scope;
  final Map<String, Object?>? updatedInput;
  final List<Map<String, Object?>> updatedPermissions;
  final bool? interrupt;

  String get legacyDecision => switch (decision) {
        ApprovalDecision.allow => 'allow',
        ApprovalDecision.deny => 'deny',
        ApprovalDecision.cancel => 'deny',
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'decision': decision.name,
        if (decision == ApprovalDecision.allow)
          'scope': (scope ?? ApprovalScope.once).name,
        if (updatedInput != null) 'updatedInput': updatedInput,
        if (updatedPermissions.isNotEmpty)
          'updatedPermissions': updatedPermissions,
        if (interrupt != null) 'interrupt': interrupt,
      };
}
