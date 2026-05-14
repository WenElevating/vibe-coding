import '../../domain/repositories/diagnostics_repository.dart';
import '../../models/protocol.dart';
import '../../services/daemon_client.dart';

class DaemonDiagnosticsRepository implements DiagnosticsRepository {
  DaemonDiagnosticsRepository({required DaemonClient client})
      : _client = client;

  final DaemonClient _client;

  @override
  Future<DiagnosticBundleSummary> exportDiagnostics() =>
      _client.exportDiagnostics();

  @override
  Future<String> recordException({
    required String message,
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final trace = await _client.recordException(
      message: message,
      stack: stack,
      path: path,
      method: method,
      conversationId: conversationId,
      runId: runId,
      metadata: metadata,
    );
    return trace.traceId;
  }
}
