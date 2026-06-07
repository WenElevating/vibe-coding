import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/mobile_app_event_bus.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_startup_buffer.dart';

void main() {
  test('retains at most two marks and drops later by arrival order', () {
    final buffer = PerformanceTraceStartupBuffer();

    buffer.capture(
      const MobilePerformanceTraceMark(
        name: 'app.main.started',
        wallTimeMs: 1,
        monotonicUs: 10,
        critical: true,
      ),
    );
    buffer.capture(
      const MobilePerformanceTraceMark(
        name: 'app.first_frame',
        wallTimeMs: 2,
        monotonicUs: 20,
        critical: true,
      ),
    );
    buffer.capture(
      const MobilePerformanceTraceMark(
        name: 'startup.third',
        wallTimeMs: 3,
        monotonicUs: 30,
        critical: true,
      ),
    );
    buffer.capture(
      const MobilePerformanceTraceMark(
        name: 'startup.fourth',
        wallTimeMs: 4,
        monotonicUs: 40,
      ),
    );

    final drained = buffer.drain();

    expect(drained.map((mark) => mark.name), <String>[
      'app.main.started',
      'app.first_frame',
    ]);
    expect(drained.map((mark) => mark.wallTimeMs), <int>[1, 2]);
    expect(drained.map((mark) => mark.monotonicUs), <int>[10, 20]);
    expect(buffer.droppedCriticalCount, 1);
    expect(buffer.droppedNonCriticalCount, 1);
    expect(buffer.droppedCount, 2);
  });

  test('drain clears retained marks without changing dropped counters', () {
    final buffer = PerformanceTraceStartupBuffer();

    buffer.capture(
      const MobilePerformanceTraceMark(
        name: 'app.main.started',
        wallTimeMs: 1,
        monotonicUs: 10,
        critical: true,
      ),
    );
    buffer.capture(
      const MobilePerformanceTraceMark(
        name: 'app.first_frame',
        wallTimeMs: 2,
        monotonicUs: 20,
        critical: true,
      ),
    );
    buffer.capture(
      const MobilePerformanceTraceMark(
        name: 'startup.third',
        wallTimeMs: 3,
        monotonicUs: 30,
        critical: true,
      ),
    );

    expect(buffer.drain(), hasLength(2));
    expect(buffer.drain(), isEmpty);
    expect(buffer.droppedCriticalCount, 1);
    expect(buffer.droppedNonCriticalCount, 0);
  });
}
