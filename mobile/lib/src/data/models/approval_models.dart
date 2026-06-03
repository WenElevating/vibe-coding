enum ApprovalRequestKind { command, fileChange, permissions, generic }

enum ApprovalDenyBehavior { interrupt, continueTurn }

class ApprovalRequestOptions {
  const ApprovalRequestOptions({
    this.kind = ApprovalRequestKind.generic,
    this.supportsSessionScope = false,
    this.supportsCancel = false,
    this.denyBehavior = ApprovalDenyBehavior.interrupt,
    this.command,
    this.cwd,
    this.reason,
    this.proposedExecPolicyAmendment = const <String>[],
    this.proposedPermissions = const <String, Object?>{},
  });

  final ApprovalRequestKind kind;
  final bool supportsSessionScope;
  final bool supportsCancel;
  final ApprovalDenyBehavior denyBehavior;
  final String? command;
  final String? cwd;
  final String? reason;
  final List<String> proposedExecPolicyAmendment;
  final Map<String, Object?> proposedPermissions;

  factory ApprovalRequestOptions.fromJson(Object? value) {
    final json = _objectMap(value);
    return ApprovalRequestOptions(
      kind: _kind(json['kind']),
      supportsSessionScope: json['supportsSessionScope'] as bool? ?? false,
      supportsCancel: json['supportsCancel'] as bool? ?? false,
      denyBehavior: json['denyBehavior'] == 'continue'
          ? ApprovalDenyBehavior.continueTurn
          : ApprovalDenyBehavior.interrupt,
      command: _text(json['command']),
      cwd: _text(json['cwd']),
      reason: _text(json['reason']),
      proposedExecPolicyAmendment:
          _stringList(json['proposedExecPolicyAmendment']),
      proposedPermissions: _objectMap(json['proposedPermissions']),
    );
  }

  static ApprovalRequestKind _kind(Object? value) => switch (value) {
        'command' => ApprovalRequestKind.command,
        'file_change' => ApprovalRequestKind.fileChange,
        'permissions' => ApprovalRequestKind.permissions,
        _ => ApprovalRequestKind.generic,
      };
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is! Map) return const <String, Object?>{};
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) result[key] = entry.value;
  }
  return result;
}
