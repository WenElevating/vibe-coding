import 'daemon_client.dart';
import 'mobile_app_event_bus.dart';

class PerformanceTraceClient {
  const PerformanceTraceClient({required DaemonClient daemonClient})
    : _daemonClient = daemonClient;

  final DaemonClient _daemonClient;

  Future<PerformanceTraceConfig> fetchConfig() async {
    final response = await _daemonClient.getAuthorizedJson('/api/perf/config');
    return PerformanceTraceConfig.fromJson(response);
  }

  Future<PerformanceTimeSyncResponse> timeSync(
    PerformanceTimeSyncRequest request,
  ) async {
    final response = await _daemonClient.postAuthorizedJson(
      '/api/perf/time-sync',
      request.toJson(),
    );
    return PerformanceTimeSyncResponse.fromJson(response);
  }

  Future<PerformanceTraceUploadResponse> upload(
    PerformanceTraceUploadRequest request,
  ) async {
    try {
      final response = await _daemonClient.postAuthorizedJson(
        '/api/perf/mobile-marks',
        request.toJson(),
      );
      return PerformanceTraceUploadResponse.fromJson(response);
    } on DaemonClientException catch (error) {
      if (error.statusCode == 413) {
        throw PerformanceTraceUploadTooLarge(error.body);
      }
      rethrow;
    }
  }
}

class PerformanceTraceConfig {
  const PerformanceTraceConfig({
    required this.enabled,
    this.runId,
    this.sampleRate,
    this.maxQueueSize,
    this.maxBatchSize,
  });

  final bool enabled;
  final String? runId;
  final int? sampleRate;
  final int? maxQueueSize;
  final int? maxBatchSize;

  factory PerformanceTraceConfig.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'] == true;
    if (!enabled) return const PerformanceTraceConfig(enabled: false);
    return PerformanceTraceConfig(
      enabled: true,
      runId: json['runId'] as String?,
      sampleRate: _readInt(json['sampleRate']),
      maxQueueSize: _readInt(json['maxQueueSize']),
      maxBatchSize: _readInt(json['maxBatchSize']),
    );
  }
}

class PerformanceTimeSyncRequest {
  const PerformanceTimeSyncRequest({
    required this.runId,
    required this.appSessionId,
    required this.mobileSendWallMs,
    required this.mobileSendMonoUs,
  });

  final String runId;
  final String appSessionId;
  final int mobileSendWallMs;
  final int mobileSendMonoUs;

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'appSessionId': appSessionId,
    'mobileSendWallMs': mobileSendWallMs,
    'mobileSendMonoUs': mobileSendMonoUs,
  };
}

class PerformanceTimeSyncResponse {
  const PerformanceTimeSyncResponse({
    required this.daemonReceiveWallMs,
    required this.daemonSendWallMs,
  });

  final int daemonReceiveWallMs;
  final int daemonSendWallMs;

  factory PerformanceTimeSyncResponse.fromJson(Map<String, Object?> json) =>
      PerformanceTimeSyncResponse(
        daemonReceiveWallMs: _readRequiredInt(json, 'daemonReceiveWallMs'),
        daemonSendWallMs: _readRequiredInt(json, 'daemonSendWallMs'),
      );
}

class PerformanceTraceClockSync {
  const PerformanceTraceClockSync({
    required this.offsetEstimateMs,
    required this.roundTripMs,
    required this.ageMs,
    required this.quality,
    required this.clockDriftWarning,
  });

  static const PerformanceTraceClockSync unknown = PerformanceTraceClockSync(
    offsetEstimateMs: 0,
    roundTripMs: 0,
    ageMs: 0,
    quality: 'unknown',
    clockDriftWarning: false,
  );

  final double offsetEstimateMs;
  final double roundTripMs;
  final int ageMs;
  final String quality;
  final bool clockDriftWarning;

  Map<String, Object?> toJson() => <String, Object?>{
    'offsetEstimateMs': offsetEstimateMs,
    'roundTripMs': roundTripMs,
    'ageMs': ageMs,
    'quality': quality,
    'clockDriftWarning': clockDriftWarning,
  };
}

class PerformanceTraceUploadRequest {
  const PerformanceTraceUploadRequest({
    required this.runId,
    required this.deviceId,
    required this.appSessionId,
    required this.mobileSentWallMs,
    required this.mobileSentMonoUs,
    required this.marks,
    required this.clockSync,
    this.droppedCountSinceLastSuccessfulFlush = 0,
    this.droppedCriticalCountSinceLastSuccessfulFlush = 0,
    this.droppedNonCriticalCountSinceLastSuccessfulFlush = 0,
  });

  final String runId;
  final String deviceId;
  final String appSessionId;
  final int mobileSentWallMs;
  final int mobileSentMonoUs;
  final int droppedCountSinceLastSuccessfulFlush;
  final int droppedCriticalCountSinceLastSuccessfulFlush;
  final int droppedNonCriticalCountSinceLastSuccessfulFlush;
  final List<MobilePerformanceTraceMark> marks;
  final PerformanceTraceClockSync clockSync;

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'deviceId': deviceId,
    'appSessionId': appSessionId,
    'mobileSentWallMs': mobileSentWallMs,
    'mobileSentMonoUs': mobileSentMonoUs,
    'droppedCountSinceLastSuccessfulFlush':
        droppedCountSinceLastSuccessfulFlush,
    'droppedCriticalCountSinceLastSuccessfulFlush':
        droppedCriticalCountSinceLastSuccessfulFlush,
    'droppedNonCriticalCountSinceLastSuccessfulFlush':
        droppedNonCriticalCountSinceLastSuccessfulFlush,
    'marks': marks.map(_markToJson).toList(growable: false),
    'clockSync': clockSync.toJson(),
  };
}

class PerformanceTraceUploadResponse {
  const PerformanceTraceUploadResponse({
    required this.accepted,
    required this.dropped,
    this.disabled = false,
    this.daemonReceiveWallMs,
    this.daemonSendWallMs,
  });

  final int accepted;
  final int dropped;
  final bool disabled;
  final int? daemonReceiveWallMs;
  final int? daemonSendWallMs;

  factory PerformanceTraceUploadResponse.fromJson(Map<String, Object?> json) =>
      PerformanceTraceUploadResponse(
        accepted: _readRequiredInt(json, 'accepted'),
        dropped: _readRequiredInt(json, 'dropped'),
        disabled: json['disabled'] == true,
        daemonReceiveWallMs: _readInt(json['daemonReceiveWallMs']),
        daemonSendWallMs: _readInt(json['daemonSendWallMs']),
      );
}

class PerformanceTraceUploadTooLarge implements Exception {
  const PerformanceTraceUploadTooLarge(this.body);

  final int statusCode = 413;
  final Map<String, Object?> body;

  @override
  String toString() => 'PerformanceTraceUploadTooLarge($body)';
}

Map<String, Object?> _markToJson(MobilePerformanceTraceMark mark) =>
    <String, Object?>{
      'name': mark.name,
      'source': 'mobile',
      'wallTimeMs': mark.wallTimeMs,
      'monotonicUs': mark.monotonicUs,
      if (mark.conversationId != null) 'conversationId': mark.conversationId,
      if (mark.seq != null) 'seq': mark.seq,
      if (mark.eventType != null) 'eventType': mark.eventType,
      if (mark.correlationId != null) 'correlationId': mark.correlationId,
      'critical': mark.critical,
      'clockDriftWarning': mark.clockDriftWarning,
      'metadata': mark.metadata,
    };

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

int _readRequiredInt(Map<String, Object?> json, String key) {
  final value = _readInt(json[key]);
  if (value == null) {
    throw DaemonClientException(200, <String, Object?>{
      'error': 'invalid_response',
      'message': 'daemon response field "$key" is missing or invalid',
    });
  }
  return value;
}
