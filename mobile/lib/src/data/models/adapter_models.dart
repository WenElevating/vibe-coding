class AdapterModelOption {
  const AdapterModelOption({
    required this.id,
    required this.label,
    required this.source,
    required this.selected,
  });

  final String id;
  final String label;
  final String source;
  final bool selected;

  factory AdapterModelOption.fromJson(Map<String, Object?> json) {
    final id = _optionalString(json['id']) ?? '';
    return AdapterModelOption(
      id: id,
      label: _optionalString(json['label']) ?? id,
      source: _optionalString(json['source']) ?? 'unknown',
      selected: json['selected'] == true,
    );
  }
}

class AdapterStatus {
  const AdapterStatus(
      {required this.adapter,
      required this.available,
      required this.status,
      this.version,
      this.error,
      this.actionable,
      this.models = const <AdapterModelOption>[],
      this.selectedModel,
      this.canSelectModel = false,
      this.capabilities = const <String, Object?>{}});
  final String adapter;
  final bool available;
  final String status;
  final String? version;
  final String? error;
  final String? actionable;
  final List<AdapterModelOption> models;
  final String? selectedModel;
  final bool canSelectModel;
  final Map<String, Object?> capabilities;
  factory AdapterStatus.fromJson(Map<String, Object?> json) => AdapterStatus(
        adapter: json['adapter'] as String? ?? '',
        available: json['available'] as bool? ?? false,
        status: json['status'] as String? ??
            (json['available'] == true ? 'available' : 'unavailable'),
        version: json['version'] as String?,
        error: json['error'] as String?,
        actionable: json['actionable'] as String?,
        models: _adapterModelsFromJson(json['models']),
        selectedModel: _optionalString(json['selectedModel']),
        canSelectModel: json['canSelectModel'] == true,
        capabilities: _objectMap(json['capabilities']),
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

List<AdapterModelOption> _adapterModelsFromJson(Object? value) {
  if (value is! Iterable) {
    return const <AdapterModelOption>[];
  }
  return value
      .map(_objectMap)
      .where((item) => item.isNotEmpty)
      .map(AdapterModelOption.fromJson)
      .toList(growable: false);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is! Map) {
    return const <String, Object?>{};
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      result[key] = entry.value;
    }
  }
  return result;
}

String? _optionalString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
