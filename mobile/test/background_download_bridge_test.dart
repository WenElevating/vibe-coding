import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/background_download_bridge.dart';
import 'package:lan_ai_cli_control/src/services/method_channel_background_download_bridge.dart';
import 'package:lan_ai_cli_control/src/services/noop_background_download_bridge.dart';

void main() {
  test('snapshot parses native progress payload', () {
    final snapshot =
        BackgroundDownloadSnapshot.fromJson(const <String, Object?>{
      'id': 'asr:model-v1',
      'status': 'downloading',
      'downloadedBytes': 12,
      'totalBytes': 40,
      'destinationPath': '/tmp/model-v1.zip.part',
      'message': 'ok',
    });

    expect(snapshot.id, 'asr:model-v1');
    expect(snapshot.status, BackgroundDownloadStatus.downloading);
    expect(snapshot.downloadedBytes, 12);
    expect(snapshot.totalBytes, 40);
    expect(snapshot.destinationPath, '/tmp/model-v1.zip.part');
    expect(snapshot.fraction, 0.3);
  });

  test('request serializes headers and destination', () {
    const request = BackgroundDownloadRequest(
      id: 'update:17',
      kind: BackgroundDownloadKind.appUpdate,
      url: 'http://127.0.0.1:4317/api/app-updates/android/app.apk',
      destinationPath: '/tmp/app-update-17.apk.part',
      headers: <String, String>{
        'authorization': 'Bearer token',
        'range': 'bytes=10-',
      },
      expectedBytes: 120,
      resumeFromBytes: 10,
      notificationTitle: 'Downloading update',
      notificationBody: 'Version 1.4.15',
    );

    expect(request.toJson(), <String, Object?>{
      'id': 'update:17',
      'kind': 'appUpdate',
      'url': 'http://127.0.0.1:4317/api/app-updates/android/app.apk',
      'destinationPath': '/tmp/app-update-17.apk.part',
      'headers': <String, String>{
        'authorization': 'Bearer token',
        'range': 'bytes=10-',
      },
      'expectedBytes': 120,
      'resumeFromBytes': 10,
      'notificationTitle': 'Downloading update',
      'notificationBody': 'Version 1.4.15',
    });
  });

  test('noop bridge reports unsupported without throwing', () async {
    final bridge = UnsupportedBackgroundDownloadBridge();

    expect(await bridge.isSupported, false);
    expect(await bridge.prepareNotifications(), false);
    expect(
      bridge.events,
      emitsInOrder(<Matcher>[
        isA<BackgroundDownloadSnapshot>().having(
          (event) => event.status,
          'status',
          BackgroundDownloadStatus.failed,
        ),
      ]),
    );
    await bridge.start(const BackgroundDownloadRequest(
      id: 'unsupported',
      kind: BackgroundDownloadKind.asrModel,
      url: 'http://127.0.0.1/file.zip',
      destinationPath: '/tmp/file.zip.part',
      headers: <String, String>{},
      expectedBytes: 1,
      resumeFromBytes: 0,
      notificationTitle: 'Downloading',
      notificationBody: 'Background downloads are unavailable.',
    ));
  });

  test('method channel bridge starts native download and parses result',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    const methodChannel =
        MethodChannel('lan_ai_cli_control/background_downloads');
    const eventChannel =
        EventChannel('lan_ai_cli_control/background_downloads/events');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      if (call.method == 'isSupported') return true;
      if (call.method == 'start') {
        return <String, Object?>{
          'id': 'update:17',
          'status': 'completed',
          'downloadedBytes': 120,
          'totalBytes': 120,
          'destinationPath': '/tmp/app-update-17.apk.part',
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, (_) async => null);

    final bridge = MethodChannelBackgroundDownloadBridge(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    final supported = await bridge.isSupported;
    final result = await bridge.start(const BackgroundDownloadRequest(
      id: 'update:17',
      kind: BackgroundDownloadKind.appUpdate,
      url: 'http://127.0.0.1:4317/apk',
      destinationPath: '/tmp/app-update-17.apk.part',
      headers: <String, String>{},
      expectedBytes: 120,
      resumeFromBytes: 0,
      notificationTitle: 'Downloading update',
      notificationBody: 'Version 1.4.15',
    ));

    expect(supported, true);
    expect(result.status, BackgroundDownloadStatus.completed);
    expect(calls.map((call) => call.method), <String>['isSupported', 'start']);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, null);
  });

  test('method channel bridge keeps listening when native ack is malformed',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const methodChannel =
        MethodChannel('lan_ai_cli_control/background_downloads');
    const eventChannel =
        EventChannel('lan_ai_cli_control/background_downloads/events');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'start') {
        return <String, Object?>{'unexpected': 'shape'};
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, (_) async => null);

    final bridge = MethodChannelBackgroundDownloadBridge(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    final result = await bridge.start(const BackgroundDownloadRequest(
      id: 'update:18',
      kind: BackgroundDownloadKind.appUpdate,
      url: 'http://127.0.0.1:4317/apk',
      destinationPath: '/tmp/app-update-18.apk.part',
      headers: <String, String>{},
      expectedBytes: 120,
      resumeFromBytes: 0,
      notificationTitle: 'Downloading update',
      notificationBody: 'Version 1.4.16',
    ));

    expect(result.id, 'update:18');
    expect(result.status, BackgroundDownloadStatus.queued);
    expect(result.message, contains('Malformed native start acknowledgement'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannel.name, null);
  });

  test('method channel bridge drops malformed native events and keeps stream',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final controller = StreamController<Object?>.broadcast();
    addTearDown(controller.close);
    final bridge = MethodChannelBackgroundDownloadBridge(
      eventStream: controller.stream,
    );

    final expectation = expectLater(
      bridge.events,
      emitsThrough(isA<BackgroundDownloadSnapshot>()
          .having((event) => event.id, 'id', 'update:19')
          .having(
            (event) => event.status,
            'status',
            BackgroundDownloadStatus.completed,
          )),
    );

    await Future<void>.delayed(Duration.zero);
    controller.add(const <String, Object?>{'unexpected': 'shape'});
    controller.add('not a native event map');
    controller.add(const <String, Object?>{
      'id': 'update:19',
      'status': 'completed',
      'downloadedBytes': 120,
      'totalBytes': 120,
      'destinationPath': '/tmp/app-update-19.apk.part',
    });

    await expectation;
  });

  test('method channel bridge permits download when notification is denied',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    var requested = false;
    final bridge = MethodChannelBackgroundDownloadBridge(
      forceAndroidForTesting: true,
      notificationPermissionRequester: () async {
        requested = true;
        return false;
      },
    );

    final prepared = await bridge.prepareNotifications();

    expect(requested, true);
    expect(prepared, true);
  });
}
