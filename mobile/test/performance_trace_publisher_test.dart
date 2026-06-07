import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/mobile_app_event_bus.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_clock.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_publisher.dart';

void main() {
  test('disabled publisher does not publish performance marks', () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: const FakePerformanceTraceClock(wallMs: 10, monoUs: 20),
    );
    final events = <MobilePerformanceTraceMark>[];
    final sub = bus.on<MobilePerformanceTraceMark>().listen(events.add);

    publisher.mark('send.tap');
    await pumpEventQueue();

    expect(events, isEmpty);
    await sub.cancel();
    await bus.dispose();
  });

  test('enabled publisher emits one immutable event bus payload', () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: const FakePerformanceTraceClock(wallMs: 1791200000000, monoUs: 42),
    )..setEnabled(true);
    final events = <MobilePerformanceTraceMark>[];
    final sub = bus.on<MobilePerformanceTraceMark>().listen(events.add);

    publisher.mark(
      'ws.event.received',
      conversationId: 'conv_1',
      seq: 7,
      eventType: 'assistant.message',
      correlationId: 'conv_1:7',
      critical: true,
      clockDriftWarning: true,
      metadata: const <String, Object?>{'bytes': 1200},
    );
    await pumpEventQueue();

    expect(events, hasLength(1));
    final event = events.single;
    expect(event.name, 'ws.event.received');
    expect(event.wallTimeMs, 1791200000000);
    expect(event.monotonicUs, 42);
    expect(event.conversationId, 'conv_1');
    expect(event.seq, 7);
    expect(event.eventType, 'assistant.message');
    expect(event.correlationId, 'conv_1:7');
    expect(event.critical, isTrue);
    expect(event.clockDriftWarning, isTrue);
    expect(event.metadata, const <String, Object?>{'bytes': 1200});

    await sub.cancel();
    await bus.dispose();
  });
}

class FakePerformanceTraceClock implements PerformanceTraceClock {
  const FakePerformanceTraceClock({required this.wallMs, required this.monoUs});

  final int wallMs;
  final int monoUs;

  @override
  int nowMonotonicUs() => monoUs;

  @override
  int nowWallTimeMs() => wallMs;
}
