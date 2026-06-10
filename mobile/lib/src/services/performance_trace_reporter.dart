import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'mobile_app_event_bus.dart';
import 'performance_trace_client.dart';
import 'performance_trace_clock.dart';
import 'performance_trace_publisher.dart';
import 'performance_trace_startup_buffer.dart';

typedef PerformanceTraceDeviceIdProvider = String? Function();

class PerformanceTraceReporter {
  PerformanceTraceReporter({
    required MobileAppEventBus eventBus,
    required PerformanceTracePublisher publisher,
    required PerformanceTraceTransport client,
    required PerformanceTraceStartupBuffer startupBuffer,
    required String appSessionId,
    required PerformanceTraceDeviceIdProvider deviceIdProvider,
    PerformanceTraceClock clock = const SystemPerformanceTraceClock(),
    Duration flushInterval = const Duration(seconds: 2),
    Duration lifecycleFlushTimeout = const Duration(milliseconds: 1500),
    int defaultQueueCapacity = 2000,
    int defaultBatchSize = 200,
    bool autoStartTimer = true,
  })  : _eventBus = eventBus,
        _publisher = publisher,
        _client = client,
        _startupBuffer = startupBuffer,
        _appSessionId = appSessionId,
        _deviceIdProvider = deviceIdProvider,
        _clock = clock,
        _flushInterval = flushInterval,
        _lifecycleFlushTimeout = lifecycleFlushTimeout,
        _queueCapacity = defaultQueueCapacity,
        _maxBatchSize = defaultBatchSize,
        _autoStartTimer = autoStartTimer;

  final MobileAppEventBus _eventBus;
  final PerformanceTracePublisher _publisher;
  final PerformanceTraceTransport _client;
  final PerformanceTraceStartupBuffer _startupBuffer;
  final String _appSessionId;
  final PerformanceTraceDeviceIdProvider _deviceIdProvider;
  final PerformanceTraceClock _clock;
  final Duration _flushInterval;
  final Duration _lifecycleFlushTimeout;
  final bool _autoStartTimer;

  final Queue<MobilePerformanceTraceMark> _queue =
      Queue<MobilePerformanceTraceMark>();
  StreamSubscription<MobilePerformanceTraceMark>? _subscription;
  Timer? _timer;
  bool _disposed = false;
  bool _started = false;
  bool _enabled = false;
  bool _paused = false;
  bool _uploadInFlight = false;
  String? _runId;
  int _queueCapacity;
  int _maxBatchSize;
  int _nonCriticalCount = 0;
  int _droppedCriticalSinceSuccess = 0;
  int _droppedNonCriticalSinceSuccess = 0;
  int _consecutiveFailures = 0;
  List<MobilePerformanceTraceMark>? _retryBatch;
  bool _retryAlreadyFailed = false;
  bool _startupDrained = false;
  bool _timeSyncInFlight = false;
  _ClockEstimate? _clockEstimate;

  bool get isEnabled => _enabled;
  bool get isPaused => _paused;
  int get queuedCount => _queue.length;
  int get droppedCriticalSinceSuccess => _droppedCriticalSinceSuccess;
  int get droppedNonCriticalSinceSuccess => _droppedNonCriticalSinceSuccess;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _subscription = _eventBus.on<MobilePerformanceTraceMark>().listen(_enqueue);
    await refreshConfig();
    if (_autoStartTimer && !_disposed) {
      _timer = Timer.periodic(_flushInterval, (_) {
        unawaited(flushTickForTesting());
      });
    }
  }

  Future<void> refreshConfig({bool resetFailureCount = true}) async {
    if (_disposed) return;
    try {
      final config = await _client.fetchConfig();
      if (_disposed) return;
      if (!config.enabled || config.runId == null) {
        _disableTracing();
        return;
      }
      _enabled = true;
      _paused = false;
      if (resetFailureCount) _consecutiveFailures = 0;
      _runId = config.runId;
      final configuredQueueCapacity = config.maxQueueSize;
      if (configuredQueueCapacity != null && configuredQueueCapacity > 0) {
        _queueCapacity = configuredQueueCapacity;
      }
      final configuredBatchSize = config.maxBatchSize;
      if (configuredBatchSize != null && configuredBatchSize > 0) {
        _maxBatchSize = configuredBatchSize;
      }
      _publisher.setEnabled(true);
      _drainStartupBufferOnce();
      unawaited(_syncTimeIfPossible());
    } catch (_) {
      if (!_enabled) _publisher.setEnabled(false);
    }
  }

  Future<void> flushTickForTesting() async {
    if (_disposed) return;
    if (!_enabled || _paused) {
      await refreshConfig();
      return;
    }
    if (_clockEstimate != null && _clockEstimate!.ageMs(_clock) > 30000) {
      unawaited(_syncTimeIfPossible());
    }
    await _flushOnce(countFailures: true);
  }

  Future<void> flushForLifecyclePause() async {
    if (_disposed || !_enabled || _paused) return;
    try {
      await _flushOnce(countFailures: false).timeout(_lifecycleFlushTimeout);
    } on TimeoutException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _publisher.setEnabled(false);
    await _subscription?.cancel();
    _subscription = null;
  }

  void _enqueue(MobilePerformanceTraceMark mark) {
    if (_disposed || !_enabled) return;
    if (_queue.length < _queueCapacity) {
      _queue.addLast(mark);
      if (!mark.critical) _nonCriticalCount++;
      return;
    }
    if (!mark.critical) {
      _droppedNonCriticalSinceSuccess++;
      return;
    }
    if (_nonCriticalCount <= 0) {
      _droppedCriticalSinceSuccess++;
      return;
    }
    final retained = Queue<MobilePerformanceTraceMark>();
    var removed = false;
    while (_queue.isNotEmpty) {
      final current = _queue.removeFirst();
      if (!removed && !current.critical) {
        removed = true;
        _nonCriticalCount--;
        _droppedNonCriticalSinceSuccess++;
        continue;
      }
      retained.addLast(current);
    }
    _queue.addAll(retained);
    _queue.addLast(mark);
  }

  void _drainStartupBufferOnce() {
    if (_startupDrained) return;
    _startupDrained = true;
    for (final mark in _startupBuffer.drain()) {
      _enqueue(mark);
    }
    _droppedCriticalSinceSuccess += _startupBuffer.droppedCriticalCount;
    _droppedNonCriticalSinceSuccess += _startupBuffer.droppedNonCriticalCount;
    _startupBuffer.discard();
  }

  Future<void> _flushOnce({required bool countFailures}) async {
    if (_uploadInFlight || _disposed || !_enabled || _runId == null) return;
    final batch = _retryBatch ?? _takeBatch();
    if (batch.isEmpty) return;
    _uploadInFlight = true;
    try {
      final response = await _uploadBatch(batch);
      if (response.disabled) {
        _disableTracing();
      }
      _markUploadSuccess();
      _retryBatch = null;
      _retryAlreadyFailed = false;
    } on PerformanceTraceUploadTooLarge {
      await _handleTooLarge(batch);
    } catch (_) {
      if (countFailures) {
        _markUploadFailure(batch);
      } else if (_retryBatch == null) {
        _restoreBatchFront(batch);
      }
    } finally {
      _uploadInFlight = false;
    }
  }

  Future<void> _handleTooLarge(List<MobilePerformanceTraceMark> batch) async {
    await refreshConfig(resetFailureCount: false);
    _retryBatch = null;
    _retryAlreadyFailed = false;
    if (!_enabled) return;
    _restoreBatchFront(batch);
  }

  Future<PerformanceTraceUploadResponse> _uploadBatch(
    List<MobilePerformanceTraceMark> batch,
  ) async {
    final runId = _runId;
    final deviceId = _deviceIdProvider();
    if (runId == null || deviceId == null || deviceId.isEmpty) {
      throw StateError('performance trace upload requires an active device id');
    }
    final sentWallMs = _clock.nowWallTimeMs();
    final sentMonoUs = _clock.nowMonotonicUs();
    final response = await _client.upload(
      PerformanceTraceUploadRequest(
        runId: runId,
        deviceId: deviceId,
        appSessionId: _appSessionId,
        mobileSentWallMs: sentWallMs,
        mobileSentMonoUs: sentMonoUs,
        droppedCountSinceLastSuccessfulFlush:
            _droppedCriticalSinceSuccess + _droppedNonCriticalSinceSuccess,
        droppedCriticalCountSinceLastSuccessfulFlush:
            _droppedCriticalSinceSuccess,
        droppedNonCriticalCountSinceLastSuccessfulFlush:
            _droppedNonCriticalSinceSuccess,
        marks: batch,
        clockSync: _clockSyncForUpload(),
      ),
    );
    if (response.daemonReceiveWallMs != null &&
        response.daemonSendWallMs != null) {
      _updateClockEstimate(
        t0: sentWallMs,
        t1: response.daemonReceiveWallMs!,
        t2: response.daemonSendWallMs!,
        t3: _clock.nowWallTimeMs(),
      );
    }
    return response;
  }

  List<MobilePerformanceTraceMark> _takeBatch() {
    final count = math.min(_maxBatchSize, _queue.length);
    final batch = <MobilePerformanceTraceMark>[];
    for (var i = 0; i < count; i++) {
      final mark = _queue.removeFirst();
      if (!mark.critical) _nonCriticalCount--;
      batch.add(mark);
    }
    return batch;
  }

  void _restoreBatchFront(List<MobilePerformanceTraceMark> batch) {
    for (var i = batch.length - 1; i >= 0; i--) {
      final mark = batch[i];
      _queue.addFirst(mark);
      if (!mark.critical) _nonCriticalCount++;
    }
  }

  void _markUploadSuccess() {
    _droppedCriticalSinceSuccess = 0;
    _droppedNonCriticalSinceSuccess = 0;
    _consecutiveFailures = 0;
    _paused = false;
  }

  void _markUploadFailure(List<MobilePerformanceTraceMark> batch) {
    _consecutiveFailures++;
    if (_retryBatch == null) {
      _retryBatch = List<MobilePerformanceTraceMark>.unmodifiable(batch);
      _retryAlreadyFailed = true;
    } else if (_retryAlreadyFailed) {
      _foldDroppedBatch(batch);
      _retryBatch = null;
      _retryAlreadyFailed = false;
    }
    if (_consecutiveFailures >= 3) {
      _paused = true;
    }
  }

  void _foldDroppedBatch(List<MobilePerformanceTraceMark> batch) {
    for (final mark in batch) {
      if (mark.critical) {
        _droppedCriticalSinceSuccess++;
      } else {
        _droppedNonCriticalSinceSuccess++;
      }
    }
  }

  void _disableTracing() {
    _enabled = false;
    _paused = false;
    _runId = null;
    _queue.clear();
    _nonCriticalCount = 0;
    _retryBatch = null;
    _retryAlreadyFailed = false;
    _droppedCriticalSinceSuccess = 0;
    _droppedNonCriticalSinceSuccess = 0;
    _consecutiveFailures = 0;
    _publisher.setEnabled(false);
  }

  PerformanceTraceClockSync _clockSyncForUpload() {
    final estimate = _clockEstimate;
    if (estimate == null) return PerformanceTraceClockSync.unknown;
    final ageMs = estimate.ageMs(_clock);
    final driftWarning = ageMs > 30000;
    final quality = _qualityFor(estimate.roundTripMs, driftWarning);
    return PerformanceTraceClockSync(
      offsetEstimateMs: estimate.offsetEstimateMs,
      roundTripMs: estimate.roundTripMs,
      ageMs: ageMs,
      quality: quality,
      clockDriftWarning: driftWarning,
    );
  }

  Future<void> _syncTimeIfPossible() async {
    if (_timeSyncInFlight || _disposed || !_enabled || _paused) return;
    final runId = _runId;
    if (runId == null) return;
    _timeSyncInFlight = true;
    final t0 = _clock.nowWallTimeMs();
    try {
      final response = await _client.timeSync(
        PerformanceTimeSyncRequest(
          runId: runId,
          appSessionId: _appSessionId,
          mobileSendWallMs: t0,
          mobileSendMonoUs: _clock.nowMonotonicUs(),
        ),
      );
      _updateClockEstimate(
        t0: t0,
        t1: response.daemonReceiveWallMs,
        t2: response.daemonSendWallMs,
        t3: _clock.nowWallTimeMs(),
      );
    } catch (_) {
      return;
    } finally {
      _timeSyncInFlight = false;
    }
  }

  void _updateClockEstimate({
    required int t0,
    required int t1,
    required int t2,
    required int t3,
  }) {
    final roundTripMs = ((t3 - t0) - (t2 - t1)).toDouble();
    final offsetEstimateMs = ((t1 - t0) + (t2 - t3)) / 2;
    _clockEstimate = _ClockEstimate(
      offsetEstimateMs: offsetEstimateMs,
      roundTripMs: roundTripMs < 0 ? 0 : roundTripMs,
      sampledWallMs: _clock.nowWallTimeMs(),
    );
  }
}

class _ClockEstimate {
  const _ClockEstimate({
    required this.offsetEstimateMs,
    required this.roundTripMs,
    required this.sampledWallMs,
  });

  final double offsetEstimateMs;
  final double roundTripMs;
  final int sampledWallMs;

  int ageMs(PerformanceTraceClock clock) =>
      math.max(0, clock.nowWallTimeMs() - sampledWallMs);
}

String _qualityFor(double roundTripMs, bool driftWarning) {
  if (driftWarning) return 'poor';
  if (roundTripMs < 50) return 'good';
  if (roundTripMs < 200) return 'degraded';
  return 'poor';
}
