import '../../models/protocol.dart';

abstract class DiagnosticsRepository {
  Future<DiagnosticBundleSummary> exportDiagnostics();

  Future<String> recordException({
    required String message,
    String severity = 'error',
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  });
}
