import '../../domain/models/codex_app_server_models.dart';

CodexAppServerCapabilities parseCodexAppServerCapabilities(
  Map<String, Object?> json,
) {
  final capabilityMatrix = _mapValue(json['capabilityMatrix']);
  final routes = _objectListValue(json['routes']);
  final totalMethods = _intValue(capabilityMatrix['totalMethods']) ??
      _intValue(json['totalMethods']) ??
      routes.length;
  return CodexAppServerCapabilities(
    raw: json,
    routes: routes,
    totalMethods: totalMethods,
  );
}

CodexAppServerThreadSummary parseCodexAppServerThreadSummary(
  Map<String, Object?> json,
) {
  return CodexAppServerThreadSummary(
    id: _stringValue(json['id']),
    title: _stringValue(json['title']),
    workspacePath: _nullableStringValue(json['workspacePath']),
    archived: _boolValue(json['archived']) ?? false,
    raw: json,
  );
}

CodexAppServerThreadPage parseCodexAppServerThreadPage(
  Map<String, Object?> json,
) {
  return CodexAppServerThreadPage(
    threads: _objectListValue(json['threads'] ?? json['items'])
        .map(parseCodexAppServerThreadSummary)
        .toList(growable: false),
    nextCursor: _nullableStringValue(json['nextCursor']),
    raw: json,
  );
}

CodexAppServerThreadDetail parseCodexAppServerThreadDetail(
  Map<String, Object?> json,
) {
  final thread = _mapValue(json['thread'] ?? json);
  return CodexAppServerThreadDetail(
    thread: parseCodexAppServerThreadSummary(thread),
    raw: json,
  );
}

CodexAppServerDiscoverySnapshot parseCodexAppServerDiscoverySnapshot(
  Map<String, Object?> json,
) {
  return CodexAppServerDiscoverySnapshot(
    models: _mapValue(json['models']),
    mcpServers: _mapValue(json['mcpServers']),
    skills: _mapValue(json['skills']),
    plugins: _mapValue(json['plugins']),
    apps: _mapValue(json['apps']),
    config: _mapValue(json['config']),
  );
}

String _stringValue(Object? value) {
  if (value is String) return value;
  if (value == null) return '';
  return value.toString();
}

String? _nullableStringValue(Object? value) {
  if (value == null) return null;
  final string = _stringValue(value);
  return string.isEmpty ? null : string;
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _objectListValue(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value.whereType<Map>().map(_mapValue).toList(growable: false);
}
