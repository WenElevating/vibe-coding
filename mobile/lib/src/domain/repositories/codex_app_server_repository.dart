abstract class CodexAppServerRepository {
  Future<CodexAppServerCapabilities> loadCapabilities();
  Future<CodexAppServerThreadPage> listThreads(
    String workspaceId, {
    int limit = 50,
  });
  Future<CodexAppServerThreadDetail> readThread(String threadId);
  Future<CodexAppServerDiscoverySnapshot> loadDiscovery();
}

class CodexAppServerCapabilities {
  const CodexAppServerCapabilities({
    required this.totalMethods,
    required this.capabilityMatrix,
    required this.routes,
  });

  final int totalMethods;
  final Map<String, Object?> capabilityMatrix;
  final List<Map<String, Object?>> routes;

  factory CodexAppServerCapabilities.fromJson(Map<String, Object?> json) {
    final capabilityMatrix =
        _mapValue(json['capabilityMatrix']) ?? const <String, Object?>{};
    final routes = _mapListValue(json['routes']);
    return CodexAppServerCapabilities(
      totalMethods: _intValue(
        capabilityMatrix['totalMethods'] ??
            capabilityMatrix['total'] ??
            json['totalMethods'],
      ),
      capabilityMatrix: capabilityMatrix,
      routes: routes,
    );
  }
}

class CodexAppServerThreadSummary {
  const CodexAppServerThreadSummary({
    required this.id,
    required this.title,
    required this.workspacePath,
    required this.archived,
    required this.raw,
  });

  final String id;
  final String title;
  final String workspacePath;
  final bool archived;
  final Map<String, Object?> raw;

  factory CodexAppServerThreadSummary.fromJson(Map<String, Object?> json) =>
      CodexAppServerThreadSummary(
        id: _stringValue(json['id']),
        title: _stringValue(json['title']),
        workspacePath: _stringValue(json['workspacePath']),
        archived: _boolValue(json['archived']),
        raw: Map<String, Object?>.unmodifiable(json),
      );
}

class CodexAppServerThreadPage {
  const CodexAppServerThreadPage({
    required this.threads,
    required this.nextCursor,
    required this.raw,
  });

  final List<CodexAppServerThreadSummary> threads;
  final String? nextCursor;
  final Map<String, Object?> raw;

  factory CodexAppServerThreadPage.fromJson(Map<String, Object?> json) {
    final items = _objectListValue(json['threads'] ?? json['items']);
    return CodexAppServerThreadPage(
      threads: items.map(CodexAppServerThreadSummary.fromJson).toList(),
      nextCursor: _nullableStringValue(json['nextCursor']),
      raw: Map<String, Object?>.unmodifiable(json),
    );
  }
}

class CodexAppServerThreadDetail {
  const CodexAppServerThreadDetail({
    required this.thread,
    required this.raw,
  });

  final CodexAppServerThreadSummary thread;
  final Map<String, Object?> raw;

  factory CodexAppServerThreadDetail.fromJson(Map<String, Object?> json) {
    final thread = _mapValue(json['thread']) ?? json;
    return CodexAppServerThreadDetail(
      thread: CodexAppServerThreadSummary.fromJson(thread),
      raw: Map<String, Object?>.unmodifiable(json),
    );
  }
}

class CodexAppServerDiscoverySnapshot {
  const CodexAppServerDiscoverySnapshot({
    required this.models,
    required this.mcpServers,
    required this.skills,
    required this.plugins,
    required this.apps,
    required this.config,
  });

  final Map<String, Object?> models;
  final Map<String, Object?> mcpServers;
  final Map<String, Object?> skills;
  final Map<String, Object?> plugins;
  final Map<String, Object?> apps;
  final Map<String, Object?> config;

  factory CodexAppServerDiscoverySnapshot.fromJson(Map<String, Object?> json) =>
      CodexAppServerDiscoverySnapshot(
        models: _mapValue(json['models']) ?? const <String, Object?>{},
        mcpServers: _mapValue(json['mcpServers']) ?? const <String, Object?>{},
        skills: _mapValue(json['skills']) ?? const <String, Object?>{},
        plugins: _mapValue(json['plugins']) ?? const <String, Object?>{},
        apps: _mapValue(json['apps']) ?? const <String, Object?>{},
        config: _mapValue(json['config']) ?? const <String, Object?>{},
      );
}

String _stringValue(Object? value) => value is String ? value : '';

String? _nullableStringValue(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

bool _boolValue(Object? value) => value is bool ? value : false;

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

Map<String, Object?>? _mapValue(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

List<Map<String, Object?>> _mapListValue(Object? value) =>
    _objectListValue(value);

List<Map<String, Object?>> _objectListValue(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value
      .map(_mapValue)
      .whereType<Map<String, Object?>>()
      .toList(growable: false);
}
