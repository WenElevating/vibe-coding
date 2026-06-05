class CodexAppServerCapabilities {
  const CodexAppServerCapabilities({
    required this.raw,
    required this.routes,
    required this.totalMethods,
  });

  final Map<String, Object?> raw;
  final List<Map<String, Object?>> routes;
  final int totalMethods;
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
  final String? workspacePath;
  final bool archived;
  final Map<String, Object?> raw;
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
}

class CodexAppServerThreadDetail {
  const CodexAppServerThreadDetail({
    required this.thread,
    required this.raw,
  });

  final CodexAppServerThreadSummary thread;
  final Map<String, Object?> raw;
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
}
