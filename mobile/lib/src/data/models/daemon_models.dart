const protocolVersion = 'agent-control.v1';

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
