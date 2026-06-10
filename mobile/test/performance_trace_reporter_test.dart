import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/mobile_app_event_bus.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_client.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_clock.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_publisher.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_reporter.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_startup_buffer.dart';

void main() {
  test('enabled config drains startup marks and folds startup drops', () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: _FakeClock(wallMs: 1000, monoUs: 10),
    );
    final startupBuffer = PerformanceTraceStartupBuffer();
    startupBuffer.capture(
      const MobilePerformanceTraceMark(
        name: 'app.main.started',
        wallTimeMs: 1,
        monotonicUs: 1,
        critical: true,
      ),
    );
    startupBuffer.capture(
      const MobilePerformanceTraceMark(
        name: 'app.first_frame',
        wallTimeMs: 2,
        monotonicUs: 2,
        critical: true,
      ),
    );
    startupBuffer.capture(
      const MobilePerformanceTraceMark(
        name: 'startup.third',
        wallTimeMs: 3,
        monotonicUs: 3,
        critical: true,
      ),
    );
    final client = _FakeTraceClient();
    final reporter = _reporter(
      bus: bus,
      publisher: publisher,
      client: client,
      startupBuffer: startupBuffer,
    );

    await reporter.start();
    await reporter.flushTickForTesting();

    expect(client.uploads, hasLength(1));
    expect(client.uploads.single.marks.map((mark) => mark.name), <String>[
      'app.main.started',
      'app.first_frame',
    ]);
    expect(
        client.uploads.single.droppedCriticalCountSinceLastSuccessfulFlush, 1);
    expect(reporter.droppedCriticalSinceSuccess, 0);
    await reporter.dispose();
    await bus.dispose();
  });

  test('critical mark evicts oldest non-critical mark when queue is full',
      () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: _FakeClock(wallMs: 1000, monoUs: 10),
    );
    final client = _FakeTraceClient(
      config: const PerformanceTraceConfig(
        enabled: true,
        runId: 'perf_1',
        maxQueueSize: 2,
        maxBatchSize: 2,
      ),
    );
    final reporter = _reporter(bus: bus, publisher: publisher, client: client);

    await reporter.start();
    publisher.mark('normal.one');
    publisher.mark('normal.two');
    publisher.mark('critical.done', critical: true);
    await pumpEventQueue();
    await reporter.flushTickForTesting();

    expect(client.uploads.single.marks.map((mark) => mark.name), <String>[
      'normal.two',
      'critical.done',
    ]);
    expect(
        client.uploads.single.droppedNonCriticalCountSinceLastSuccessfulFlush,
        1);
    await reporter.dispose();
    await bus.dispose();
  });

  test('failed upload retries once, drops retry batch, then pauses after three',
      () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: _FakeClock(wallMs: 1000, monoUs: 10),
    );
    final client = _FakeTraceClient();
    client.uploadFailures.addAll(<Object>[
      Exception('first'),
      Exception('second'),
      Exception('third'),
    ]);
    final reporter = _reporter(bus: bus, publisher: publisher, client: client);

    await reporter.start();
    publisher.mark('critical.one', critical: true);
    await pumpEventQueue();
    await reporter.flushTickForTesting();
    await reporter.flushTickForTesting();
    publisher.mark('critical.two', critical: true);
    await pumpEventQueue();
    await reporter.flushTickForTesting();

    expect(client.uploads, hasLength(0));
    expect(reporter.droppedCriticalSinceSuccess, 1);
    expect(reporter.isPaused, isTrue);

    await reporter.flushTickForTesting();
    expect(reporter.isPaused, isFalse);
    await reporter.dispose();
    await bus.dispose();
  });

  test('413 refreshes config and splits retained batch on later ticks',
      () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: _FakeClock(wallMs: 1000, monoUs: 10),
    );
    final client = _FakeTraceClient(
      config: const PerformanceTraceConfig(
        enabled: true,
        runId: 'perf_1',
        maxQueueSize: 10,
        maxBatchSize: 2,
      ),
    );
    client.nextConfig = const PerformanceTraceConfig(
      enabled: true,
      runId: 'perf_1',
      maxQueueSize: 10,
      maxBatchSize: 1,
    );
    client.uploadFailures.add(
      const PerformanceTraceUploadTooLarge(<String, Object?>{
        'error': 'batch_too_large',
      }),
    );
    final reporter = _reporter(bus: bus, publisher: publisher, client: client);

    await reporter.start();
    publisher.mark('mark.one');
    publisher.mark('mark.two');
    await pumpEventQueue();
    await reporter.flushTickForTesting();

    expect(client.uploads, isEmpty);
    expect(reporter.queuedCount, 2);
    await reporter.flushTickForTesting();
    await reporter.flushTickForTesting();

    expect(client.uploads, hasLength(2));
    expect(client.uploads.map((upload) => upload.marks.length), <int>[1, 1]);
    await reporter.dispose();
    await bus.dispose();
  });

  test('413 split retry failure preserves existing failure streak', () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: _FakeClock(wallMs: 1000, monoUs: 10),
    );
    final client = _FakeTraceClient(
      config: const PerformanceTraceConfig(
        enabled: true,
        runId: 'perf_1',
        maxQueueSize: 10,
        maxBatchSize: 2,
      ),
    );
    client.nextConfig = const PerformanceTraceConfig(
      enabled: true,
      runId: 'perf_1',
      maxQueueSize: 10,
      maxBatchSize: 1,
    );
    client.uploadFailures.addAll(<Object>[
      Exception('first failure'),
      Exception('second failure'),
      const PerformanceTraceUploadTooLarge(<String, Object?>{
        'error': 'batch_too_large',
      }),
      Exception('split retry failure'),
    ]);
    final reporter = _reporter(bus: bus, publisher: publisher, client: client);

    await reporter.start();
    publisher.mark('critical.one', critical: true);
    await pumpEventQueue();
    await reporter.flushTickForTesting();
    await reporter.flushTickForTesting();
    publisher.mark('critical.two', critical: true);
    publisher.mark('critical.three', critical: true);
    await pumpEventQueue();
    await reporter.flushTickForTesting();
    await reporter.flushTickForTesting();

    expect(reporter.isPaused, isTrue);
    await reporter.dispose();
    await bus.dispose();
  });

  test('disabled config clears queued marks before a later run is enabled',
      () async {
    final bus = MobileAppEventBus();
    final publisher = PerformanceTracePublisher(
      eventBus: bus,
      clock: _FakeClock(wallMs: 1000, monoUs: 10),
    );
    final client = _FakeTraceClient();
    final reporter = _reporter(bus: bus, publisher: publisher, client: client);

    await reporter.start();
    publisher.mark('old.run.mark');
    await pumpEventQueue();
    expect(reporter.queuedCount, 1);

    client.nextConfig = const PerformanceTraceConfig(enabled: false);
    await reporter.refreshConfig();
    expect(reporter.isEnabled, isFalse);
    expect(reporter.queuedCount, 0);

    client.nextConfig = const PerformanceTraceConfig(
      enabled: true,
      runId: 'perf_2',
      maxQueueSize: 2000,
      maxBatchSize: 200,
    );
    await reporter.refreshConfig();
    await reporter.flushTickForTesting();

    expect(client.uploads, isEmpty);
    await reporter.dispose();
    await bus.dispose();
  });
}

PerformanceTraceReporter _reporter({
  required MobileAppEventBus bus,
  required PerformanceTracePublisher publisher,
  required _FakeTraceClient client,
  PerformanceTraceStartupBuffer? startupBuffer,
}) {
  return PerformanceTraceReporter(
    eventBus: bus,
    publisher: publisher,
    client: client,
    startupBuffer: startupBuffer ?? PerformanceTraceStartupBuffer(),
    appSessionId: 'mobile_session_1',
    deviceIdProvider: () => 'device-1',
    clock: _FakeClock(wallMs: 1000, monoUs: 10),
    autoStartTimer: false,
  );
}

class _FakeTraceClient implements PerformanceTraceTransport {
  _FakeTraceClient({
    PerformanceTraceConfig config = const PerformanceTraceConfig(
      enabled: true,
      runId: 'perf_1',
      maxQueueSize: 2000,
      maxBatchSize: 200,
    ),
  }) : _config = config;

  PerformanceTraceConfig _config;
  PerformanceTraceConfig? nextConfig;
  final List<PerformanceTraceUploadRequest> uploads =
      <PerformanceTraceUploadRequest>[];
  final List<Object> uploadFailures = <Object>[];

  @override
  Future<PerformanceTraceConfig> fetchConfig() async {
    final config = nextConfig ?? _config;
    _config = config;
    nextConfig = null;
    return config;
  }

  @override
  Future<PerformanceTimeSyncResponse> timeSync(
    PerformanceTimeSyncRequest request,
  ) async =>
      const PerformanceTimeSyncResponse(
        daemonReceiveWallMs: 1001,
        daemonSendWallMs: 1002,
      );

  @override
  Future<PerformanceTraceUploadResponse> upload(
    PerformanceTraceUploadRequest request,
  ) async {
    if (uploadFailures.isNotEmpty) {
      final failure = uploadFailures.removeAt(0);
      if (failure is PerformanceTraceUploadTooLarge) throw failure;
      if (failure is Exception) throw failure;
      if (failure is Error) throw failure;
    }
    uploads.add(request);
    return const PerformanceTraceUploadResponse(
      accepted: 1,
      dropped: 0,
      daemonReceiveWallMs: 1001,
      daemonSendWallMs: 1002,
    );
  }
}

class _FakeClock implements PerformanceTraceClock {
  _FakeClock({required this.wallMs, required this.monoUs});

  int wallMs;
  int monoUs;

  @override
  int nowMonotonicUs() => monoUs;

  @override
  int nowWallTimeMs() => wallMs;
}
