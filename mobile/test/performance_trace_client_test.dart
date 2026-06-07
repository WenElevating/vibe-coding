import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/device_identity_store.dart';
import 'package:lan_ai_cli_control/src/services/mobile_app_event_bus.dart';
import 'package:lan_ai_cli_control/src/services/performance_trace_client.dart';

import 'support/fake_http.dart';

void main() {
  test(
    'fetchConfig parses disabled response through authorized daemon path',
    () async {
      late http.BaseRequest configRequest;
      final daemonClient = await _pairedClient((request) {
        configRequest = request;
        expect(request.url.path, '/api/perf/config');
        return jsonResponse(const <String, Object?>{'enabled': false});
      });
      final client = PerformanceTraceClient(daemonClient: daemonClient);

      final config = await client.fetchConfig();

      expect(config.enabled, isFalse);
      expect(config.runId, isNull);
      expect(configRequest.headers['authorization'], 'Bearer access-1');
    },
  );

  test('fetchConfig parses enabled queue limits', () async {
    final daemonClient = await _pairedClient((request) {
      expect(request.url.path, '/api/perf/config');
      return jsonResponse(const <String, Object?>{
        'enabled': true,
        'runId': 'perf_20260606T120001Z_a8f3c2',
        'sampleRate': 1,
        'maxQueueSize': 2000,
        'maxBatchSize': 200,
      });
    });
    final client = PerformanceTraceClient(daemonClient: daemonClient);

    final config = await client.fetchConfig();

    expect(config.enabled, isTrue);
    expect(config.runId, 'perf_20260606T120001Z_a8f3c2');
    expect(config.sampleRate, 1);
    expect(config.maxQueueSize, 2000);
    expect(config.maxBatchSize, 200);
  });

  test('timeSync posts request and parses daemon wall timestamps', () async {
    late Map<String, Object?> uploaded;
    final daemonClient = await _pairedClient((request) async {
      expect(request.url.path, '/api/perf/time-sync');
      expect(request.headers['authorization'], 'Bearer access-1');
      uploaded =
          jsonDecode((request as http.Request).body) as Map<String, Object?>;
      return jsonResponse(const <String, Object?>{
        'daemonReceiveWallMs': 1791200005060,
        'daemonSendWallMs': 1791200005062,
      });
    });
    final client = PerformanceTraceClient(daemonClient: daemonClient);

    final response = await client.timeSync(
      const PerformanceTimeSyncRequest(
        runId: 'perf_1',
        appSessionId: 'mobile_session_1',
        mobileSendWallMs: 1791200005000,
        mobileSendMonoUs: 128000000,
      ),
    );

    expect(uploaded, const <String, Object?>{
      'runId': 'perf_1',
      'appSessionId': 'mobile_session_1',
      'mobileSendWallMs': 1791200005000,
      'mobileSendMonoUs': 128000000,
    });
    expect(response.daemonReceiveWallMs, 1791200005060);
    expect(response.daemonSendWallMs, 1791200005062);
  });

  test('upload posts mobile marks and parses accepted response', () async {
    late Map<String, Object?> uploaded;
    final daemonClient = await _pairedClient((request) async {
      expect(request.url.path, '/api/perf/mobile-marks');
      uploaded =
          jsonDecode((request as http.Request).body) as Map<String, Object?>;
      return jsonResponse(const <String, Object?>{
        'accepted': 1,
        'dropped': 0,
        'daemonReceiveWallMs': 1791200005060,
        'daemonSendWallMs': 1791200005062,
      });
    });
    final client = PerformanceTraceClient(daemonClient: daemonClient);

    final response = await client.upload(
      PerformanceTraceUploadRequest(
        runId: 'perf_1',
        deviceId: 'device-1',
        appSessionId: 'mobile_session_1',
        mobileSentWallMs: 1791200005000,
        mobileSentMonoUs: 128000000,
        droppedCountSinceLastSuccessfulFlush: 3,
        droppedCriticalCountSinceLastSuccessfulFlush: 1,
        droppedNonCriticalCountSinceLastSuccessfulFlush: 2,
        marks: const <MobilePerformanceTraceMark>[
          MobilePerformanceTraceMark(
            name: 'ws.event.received',
            wallTimeMs: 1791200002500,
            monotonicUs: 125500000,
            conversationId: 'conv_1',
            seq: 5485,
            eventType: 'assistant.message',
            correlationId: 'conv_1:5485',
            critical: true,
            metadata: <String, Object?>{'bytes': 1200},
          ),
        ],
        clockSync: const PerformanceTraceClockSync(
          offsetEstimateMs: -12.4,
          roundTripMs: 18.7,
          ageMs: 1530,
          quality: 'good',
          clockDriftWarning: false,
        ),
      ),
    );

    expect(uploaded['runId'], 'perf_1');
    expect(uploaded['deviceId'], 'device-1');
    expect(uploaded['appSessionId'], 'mobile_session_1');
    expect(uploaded['droppedCountSinceLastSuccessfulFlush'], 3);
    expect(uploaded['droppedCriticalCountSinceLastSuccessfulFlush'], 1);
    expect(uploaded['droppedNonCriticalCountSinceLastSuccessfulFlush'], 2);
    expect(uploaded['clockSync'], const <String, Object?>{
      'offsetEstimateMs': -12.4,
      'roundTripMs': 18.7,
      'ageMs': 1530,
      'quality': 'good',
      'clockDriftWarning': false,
    });
    final marks = uploaded['marks'] as List<Object?>;
    expect(marks, hasLength(1));
    expect(marks.single, const <String, Object?>{
      'name': 'ws.event.received',
      'source': 'mobile',
      'wallTimeMs': 1791200002500,
      'monotonicUs': 125500000,
      'conversationId': 'conv_1',
      'seq': 5485,
      'eventType': 'assistant.message',
      'correlationId': 'conv_1:5485',
      'critical': true,
      'clockDriftWarning': false,
      'metadata': <String, Object?>{'bytes': 1200},
    });
    expect(response.accepted, 1);
    expect(response.dropped, 0);
    expect(response.disabled, isFalse);
    expect(response.daemonReceiveWallMs, 1791200005060);
    expect(response.daemonSendWallMs, 1791200005062);
  });

  test(
    'upload parses disabled response as successful disabled delivery',
    () async {
      late Map<String, Object?> uploaded;
      final daemonClient = await _pairedClient((request) {
        expect(request.url.path, '/api/perf/mobile-marks');
        uploaded =
            jsonDecode((request as http.Request).body) as Map<String, Object?>;
        return jsonResponse(const <String, Object?>{
          'accepted': 0,
          'dropped': 0,
          'disabled': true,
        });
      });
      final client = PerformanceTraceClient(daemonClient: daemonClient);

      final response = await client.upload(
        const PerformanceTraceUploadRequest(
          runId: 'perf_1',
          deviceId: 'device-1',
          appSessionId: 'mobile_session_1',
          mobileSentWallMs: 1,
          mobileSentMonoUs: 2,
          marks: <MobilePerformanceTraceMark>[],
          clockSync: PerformanceTraceClockSync.unknown,
        ),
      );

      expect(response.accepted, 0);
      expect(response.dropped, 0);
      expect(response.disabled, isTrue);
      expect(uploaded['clockSync'], const <String, Object?>{
        'offsetEstimateMs': 0.0,
        'roundTripMs': 0.0,
        'ageMs': 0,
        'quality': 'unknown',
        'clockDriftWarning': false,
      });
    },
  );

  test('upload surfaces HTTP 413 as typed upload-too-large error', () async {
    final daemonClient = await _pairedClient((request) {
      expect(request.url.path, '/api/perf/mobile-marks');
      return jsonResponse(const <String, Object?>{
        'error': 'batch_too_large',
      }, statusCode: 413);
    });
    final client = PerformanceTraceClient(daemonClient: daemonClient);

    await expectLater(
      client.upload(
        const PerformanceTraceUploadRequest(
          runId: 'perf_1',
          deviceId: 'device-1',
          appSessionId: 'mobile_session_1',
          mobileSentWallMs: 1,
          mobileSentMonoUs: 2,
          marks: <MobilePerformanceTraceMark>[],
          clockSync: PerformanceTraceClockSync.unknown,
        ),
      ),
      throwsA(
        isA<PerformanceTraceUploadTooLarge>()
            .having((error) => error.statusCode, 'statusCode', 413)
            .having((error) => error.body['error'], 'error', 'batch_too_large'),
      ),
    );
  });
}

Future<DaemonClient> _pairedClient(FakeHttpHandler handler) async {
  final tokenStore = MemoryTokenStore();
  await tokenStore.writeAccessTokenSession(
    'device-1',
    TokenSession(
      token: 'access-1',
      expiresAt: DateTime.parse('2026-06-06T08:00:00.000Z'),
    ),
  );
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenStore: tokenStore,
    httpClient: FakeHttpClient(handler),
  );
  await client.ensurePaired(
    deviceIdentityStore: MemoryDeviceIdentityStore(deviceId: 'device-1'),
  );
  return client;
}
