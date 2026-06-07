import 'mobile_app_event_bus.dart';
import 'performance_trace_clock.dart';

class PerformanceTracePublisher {
  PerformanceTracePublisher({
    required MobileAppEventBus eventBus,
    PerformanceTraceClock clock = const SystemPerformanceTraceClock(),
    bool enabled = false,
  }) : _eventBus = eventBus,
       _clock = clock,
       _enabled = enabled;

  final MobileAppEventBus _eventBus;
  final PerformanceTraceClock _clock;
  bool _enabled;

  bool get isEnabled => _enabled;

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  void mark(
    String name, {
    String? conversationId,
    int? seq,
    String? eventType,
    String? correlationId,
    bool critical = false,
    bool clockDriftWarning = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (!_enabled) return;
    _eventBus.publish(
      MobilePerformanceTraceMark(
        name: name,
        monotonicUs: _clock.nowMonotonicUs(),
        wallTimeMs: _clock.nowWallTimeMs(),
        conversationId: conversationId,
        seq: seq,
        eventType: eventType,
        correlationId: correlationId,
        critical: critical,
        clockDriftWarning: clockDriftWarning,
        metadata: metadata,
      ),
    );
  }
}
