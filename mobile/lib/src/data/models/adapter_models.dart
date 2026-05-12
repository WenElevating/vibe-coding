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
