abstract class DiagnosticsRepository {
  Future<String> recordException({
    required String message,
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  });
}
