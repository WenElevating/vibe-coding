import 'mobile_app_event_bus.dart';
import 'performance_trace_clock.dart';

class PerformanceTraceStartupBuffer {
  PerformanceTraceStartupBuffer({
    PerformanceTraceClock clock = const SystemPerformanceTraceClock(),
    int capacity = 2,
  }) : _clock = clock,
       _capacity = capacity;

  static final PerformanceTraceStartupBuffer global =
      PerformanceTraceStartupBuffer();

  final PerformanceTraceClock _clock;
  final int _capacity;
  final List<MobilePerformanceTraceMark> _marks =
      <MobilePerformanceTraceMark>[];
  int _droppedCriticalCount = 0;
  int _droppedNonCriticalCount = 0;

  int get droppedCriticalCount => _droppedCriticalCount;
  int get droppedNonCriticalCount => _droppedNonCriticalCount;
  int get droppedCount => _droppedCriticalCount + _droppedNonCriticalCount;

  void capture(MobilePerformanceTraceMark mark) {
    if (_marks.length >= _capacity) {
      if (mark.critical) {
        _droppedCriticalCount++;
      } else {
        _droppedNonCriticalCount++;
      }
      return;
    }
    _marks.add(mark);
  }

  void captureStartupMark(
    String name, {
    bool critical = false,
    bool clockDriftWarning = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    capture(
      MobilePerformanceTraceMark(
        name: name,
        monotonicUs: _clock.nowMonotonicUs(),
        wallTimeMs: _clock.nowWallTimeMs(),
        critical: critical,
        clockDriftWarning: clockDriftWarning,
        metadata: metadata,
      ),
    );
  }

  List<MobilePerformanceTraceMark> drain() {
    final drained = List<MobilePerformanceTraceMark>.unmodifiable(_marks);
    _marks.clear();
    return drained;
  }

  void discard() {
    _marks.clear();
    _droppedCriticalCount = 0;
    _droppedNonCriticalCount = 0;
  }
}
