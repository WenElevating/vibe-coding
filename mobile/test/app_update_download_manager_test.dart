import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/services/app_update_download_manager.dart';
import 'package:lan_ai_cli_control/src/services/background_download_bridge.dart';

void main() {
  test('resumes matching partial with range and if-range', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-resume-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 2);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final part = File(_updateFile(dir, 'app-update-2.apk.part'));
    await part.writeAsBytes(bytes.sublist(0, 5));
    await File(_updateFile(dir, 'app-update-2.json')).writeAsString(jsonEncode({
      'versionCode': 2,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': 5,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    final seenHeaders = <String, String>{};
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        seenHeaders['rangeStart'] = '$rangeStart';
        seenHeaders['ifRange'] = ifRange ?? '';
        return http.StreamedResponse(
          Stream<List<int>>.value(bytes.sublist(5)),
          206,
          contentLength: bytes.length - 5,
          headers: <String, String>{
            'content-range': 'bytes 5-${bytes.length - 1}/${bytes.length}',
          },
        );
      },
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(seenHeaders['rangeStart'], '5');
    expect(seenHeaders['ifRange'], manifest.etag);
    expect(
        await File(_updateFile(dir, 'app-update-2.apk')).readAsBytes(), bytes);
    expect(await part.exists(), false);
    await temp.delete(recursive: true);
  });

  test('reports download progress while writing response chunks', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-progress-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 15);
    final progress = <AppUpdateDownloadProgress>[];
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          bytes.sublist(0, 5),
          bytes.sublist(5),
        ]),
        200,
      ),
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
      onProgress: progress.add,
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(progress.map((event) => event.downloadedBytes), <int>[
      0,
      5,
      bytes.length,
    ]);
    expect(progress.last.totalBytes, bytes.length);
    expect(progress.last.fraction, 1);
    await temp.delete(recursive: true);
  });

  test('uses native background bridge before verifying downloaded APK',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 21);
    final bridge = _FakeBackgroundDownloadBridge(bytes: bytes);
    var dartStreamOpened = false;
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      backgroundDownloadHeadersProvider: () => const <String, String>{
        'authorization': 'Bearer token',
      },
      openStream: (uri, {rangeStart, ifRange}) async {
        dartStreamOpened = true;
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(dartStreamOpened, false);
    expect(bridge.requests.single.kind, BackgroundDownloadKind.appUpdate);
    expect(bridge.requests.single.headers['authorization'], 'Bearer token');
    expect(
      await File(_updateFile(
        Directory(_updateDir(temp)),
        'app-update-21.apk',
      )).readAsBytes(),
      bytes,
    );
    await temp.delete(recursive: true);
  });

  test('native background bridge starts when notification permission is denied',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 22);
    final bridge = _FakeBackgroundDownloadBridge(
      bytes: bytes,
      notificationsPrepared: false,
    );
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.value(bytes), 200),
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(bridge.prepareNotificationsCalls, 1);
    expect(bridge.requests.single.kind, BackgroundDownloadKind.appUpdate);
    await temp.delete(recursive: true);
  });

  test('native background bridge still starts if notification request fails',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 23);
    final bridge = _FakeBackgroundDownloadBridge(
      bytes: bytes,
      notificationPreparationError: StateError('permission prompt failed'),
    );
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.value(bytes), 200),
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(bridge.requests.single.kind, BackgroundDownloadKind.appUpdate);
    await temp.delete(recursive: true);
  });

  test('native background failure falls back to Dart foreground download',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 24);
    final bridge = _FakeBackgroundDownloadBridge(
      bytes: bytes,
      terminalStatus: BackgroundDownloadStatus.failed,
    );
    var dartStreamOpened = false;
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      openStream: (uri, {rangeStart, ifRange}) async {
        dartStreamOpened = true;
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(dartStreamOpened, true);
    expect(bridge.requests.single.kind, BackgroundDownloadKind.appUpdate);
    await temp.delete(recursive: true);
  });

  test('native partial failure falls back using actual partial length',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 25);
    final bridge = _FakeBackgroundDownloadBridge(
      bytes: bytes.sublist(0, 5),
      terminalStatus: BackgroundDownloadStatus.failed,
    );
    final requestedRanges = <int?>[];
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      openStream: (uri, {rangeStart, ifRange}) async {
        requestedRanges.add(rangeStart);
        return http.StreamedResponse(
          Stream<List<int>>.value(bytes.sublist(rangeStart ?? 0)),
          rangeStart == null ? 200 : 206,
          headers: <String, String>{
            if (rangeStart != null)
              'content-range':
                  'bytes $rangeStart-${bytes.length - 1}/${bytes.length}',
          },
        );
      },
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(requestedRanges, <int?>[5]);
    await temp.delete(recursive: true);
  });

  test('native start exception falls back to Dart foreground download',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 26);
    final bridge = _FakeBackgroundDownloadBridge(
      bytes: bytes,
      startError: StateError('foreground service rejected'),
    );
    var dartStreamOpened = false;
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      openStream: (uri, {rangeStart, ifRange}) async {
        dartStreamOpened = true;
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(dartStreamOpened, true);
    await temp.delete(recursive: true);
  });

  test('native fallback reason is preserved when foreground download pauses',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-native-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 27);
    final bridge = _FakeBackgroundDownloadBridge(
      bytes: const <int>[],
      terminalStatus: BackgroundDownloadStatus.failed,
    );
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      backgroundDownloadBridge: bridge,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 503),
      availableBytes: () async => 10000000,
    );

    final result = await manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.paused);
    expect(result.message, contains('native failed'));
    expect(result.message, contains('Update server returned 503'));
    await temp.delete(recursive: true);
  });

  test('terminal auth failure keeps existing partial file', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-auth-');
    final bytes = utf8.encode('hello');
    final manifest = _manifest(bytes, versionCode: 3);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final part = File(_updateFile(dir, 'app-update-3.apk.part'));
    await part.writeAsBytes(bytes.sublist(0, 2));
    await File(_updateFile(dir, 'app-update-3.json')).writeAsString(jsonEncode({
      'versionCode': 3,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': 2,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          throw const AppUpdateDownloadException('auth failed'),
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.failed);
    expect(result.message, contains('auth failed'));
    expect(await part.exists(), true);
    await temp.delete(recursive: true);
  });

  test('insufficient storage fails before request', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-space-');
    var requested = false;
    final bytes = utf8.encode('large-apk');
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        requested = true;
        return http.StreamedResponse(Stream<List<int>>.empty(), 200);
      },
      availableBytes: () async => 1,
    );

    final result = await manager.download(
      _manifest(bytes),
      Uri.parse('http://127.0.0.1:4317'),
    );

    expect(result.state, AppUpdateDownloadState.failed);
    expect(result.message, contains('storage'));
    expect(requested, false);
    await temp.delete(recursive: true);
  });

  test('metadata mismatch deletes stale partial before request', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-stale-');
    final bytes = utf8.encode('fresh-apk');
    final manifest = _manifest(bytes, versionCode: 4);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final stalePart = File(_updateFile(dir, 'app-update-4.apk.part'));
    await stalePart.writeAsBytes(utf8.encode('stale'));
    await File(_updateFile(dir, 'app-update-4.json')).writeAsString(jsonEncode({
      'versionCode': 4,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256':
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      'sizeBytes': bytes.length,
      'etag': '"old"',
      'downloadedBytes': 5,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    int? requestedRange;
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        requestedRange = rangeStart;
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(requestedRange, isNull);
    expect(
        await File(_updateFile(dir, 'app-update-4.apk')).readAsBytes(), bytes);
    await temp.delete(recursive: true);
  });

  test('server 200 during resume restarts from full response', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-200-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 5);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final part = File(_updateFile(dir, 'app-update-5.apk.part'));
    await part.writeAsBytes(bytes.sublist(0, 5));
    await File(_updateFile(dir, 'app-update-5.json')).writeAsString(jsonEncode({
      'versionCode': 5,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': 5,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    final seenRanges = <int?>[];
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        seenRanges.add(rangeStart);
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(seenRanges, <int?>[5]);
    expect(
        await File(_updateFile(dir, 'app-update-5.apk')).readAsBytes(), bytes);
    await temp.delete(recursive: true);
  });

  test('server 416 during resume restarts from zero', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-416-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 6);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final part = File(_updateFile(dir, 'app-update-6.apk.part'));
    await part.writeAsBytes(bytes.sublist(0, 5));
    await File(_updateFile(dir, 'app-update-6.json')).writeAsString(jsonEncode({
      'versionCode': 6,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': 5,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    final seenRanges = <int?>[];
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        seenRanges.add(rangeStart);
        if (seenRanges.length == 1) {
          return http.StreamedResponse(Stream<List<int>>.empty(), 416);
        }
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(seenRanges, <int?>[5, null]);
    expect(
        await File(_updateFile(dir, 'app-update-6.apk')).readAsBytes(), bytes);
    await temp.delete(recursive: true);
  });

  test('mismatched 206 resume range restarts from zero', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-range-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 14);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final part = File(_updateFile(dir, 'app-update-14.apk.part'));
    await part.writeAsBytes(bytes.sublist(0, 5));
    await File(_updateFile(dir, 'app-update-14.json'))
        .writeAsString(jsonEncode({
      'versionCode': 14,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': 5,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    final seenRanges = <int?>[];
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        seenRanges.add(rangeStart);
        if (seenRanges.length == 1) {
          return http.StreamedResponse(
            Stream<List<int>>.value(bytes),
            206,
            headers: const <String, String>{
              'content-range': 'bytes 0-10/11',
            },
          );
        }
        return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
      },
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(seenRanges, <int?>[5, null]);
    expect(
        await File(_updateFile(dir, 'app-update-14.apk')).readAsBytes(), bytes);
    await temp.delete(recursive: true);
  });

  test('transient server error pauses and keeps partial file', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-5xx-');
    final bytes = utf8.encode('hello-world');
    final manifest = _manifest(bytes, versionCode: 7);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final part = File(_updateFile(dir, 'app-update-7.apk.part'));
    await part.writeAsBytes(bytes.sublist(0, 5));
    await File(_updateFile(dir, 'app-update-7.json')).writeAsString(jsonEncode({
      'versionCode': 7,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': 5,
      'updatedAt': '2026-05-24T10:00:00.000Z',
    }));
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 503),
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.paused);
    expect(await part.exists(), true);
    await temp.delete(recursive: true);
  });

  test('overlapping downloads for same version share one stream owner',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-inflight-');
    final bytes = utf8.encode('concurrent-apk');
    final manifest = _manifest(bytes, versionCode: 12);
    var requests = 0;
    final streamController = StreamController<List<int>>();
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        requests += 1;
        return http.StreamedResponse(streamController.stream, 200);
      },
      availableBytes: () async => 10000000,
    );

    final first = manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );
    final second = manager.download(
      manifest,
      Uri.parse('http://127.0.0.1:4317'),
    );
    await pumpEventQueue();
    streamController.add(bytes);
    await streamController.close();

    final results = await Future.wait(<Future<AppUpdateDownloadResult>>[
      first,
      second,
    ]);

    expect(requests, 1);
    expect(results[0].state, AppUpdateDownloadState.readyToInstall);
    expect(results[1].state, AppUpdateDownloadState.readyToInstall);
    await temp.delete(recursive: true);
  });

  test('same version downloads with different manifests do not share results',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('app-update-inflight-change-');
    final firstBytes = utf8.encode('first-apk');
    final secondBytes = utf8.encode('second-apk');
    final firstManifest = _manifest(firstBytes, versionCode: 13);
    final secondManifest =
        _manifest(secondBytes, versionCode: 13, etag: '"etag-13-b"');
    final streams = <StreamController<List<int>>>[];
    final firstStreamStarted = Completer<void>();
    final secondStreamStarted = Completer<void>();
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async {
        final controller = StreamController<List<int>>();
        streams.add(controller);
        if (streams.length == 1 && !firstStreamStarted.isCompleted) {
          firstStreamStarted.complete();
        } else if (streams.length == 2 && !secondStreamStarted.isCompleted) {
          secondStreamStarted.complete();
        }
        return http.StreamedResponse(controller.stream, 200);
      },
      availableBytes: () async => 10000000,
    );

    final first = manager.download(
      firstManifest,
      Uri.parse('http://127.0.0.1:4317'),
    );
    await firstStreamStarted.future.timeout(const Duration(seconds: 1));
    expect(streams.length, 1);
    final second = manager.download(
      secondManifest,
      Uri.parse('http://127.0.0.1:4317'),
    );
    await pumpEventQueue();
    expect(secondStreamStarted.isCompleted, false);
    expect(streams.length, 1);

    streams[0].add(firstBytes);
    await streams[0].close();
    final firstResult = await first;
    await secondStreamStarted.future.timeout(const Duration(seconds: 1));
    expect(streams.length, 2);
    streams[1].add(secondBytes);
    await streams[1].close();
    final secondResult = await second;

    expect(firstResult.state, AppUpdateDownloadState.readyToInstall);
    expect(secondResult.state, AppUpdateDownloadState.readyToInstall);
    final cachedApk = File(_updateFile(
      Directory(_updateDir(temp)),
      'app-update-13.apk',
    ));
    expect(await cachedApk.readAsBytes(), secondBytes);
    await temp.delete(recursive: true);
  });

  test('reconciliation prefers verified apk over partial for same version',
      () async {
    final temp = await Directory.systemTemp.createTemp('app-update-reconcile-');
    final bytes = utf8.encode('verified');
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 200),
      availableBytes: () async => 1000000,
    );
    final manifest = _manifest(bytes, versionCode: 8);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final apk = File(_updateFile(dir, 'app-update-8.apk'));
    final part = File(_updateFile(dir, 'app-update-8.apk.part'));
    await apk.writeAsBytes(bytes);
    await part.writeAsBytes(utf8.encode('partial'));

    await manager.reconcile(manifest);

    expect(await apk.exists(), true);
    expect(await part.exists(), false);
    await temp.delete(recursive: true);
  });

  test(
      'reconciliation ignores unavailable manifest without creating unknown files',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('app-update-unavailable-');
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 200),
      availableBytes: () async => 1000000,
    );

    await manager.reconcile(const AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: false,
    ));

    expect(await Directory(_updateDir(temp)).exists(), false);
    await temp.delete(recursive: true);
  });

  test('reads matching install session metadata for ready apk', () async {
    final temp = await Directory.systemTemp.createTemp('app-update-session-');
    final bytes = utf8.encode('ready-apk');
    final manifest = _manifest(bytes, versionCode: 9);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final apk = File(_updateFile(dir, 'app-update-9.apk'));
    await apk.writeAsBytes(bytes);
    await File(_updateFile(dir, 'app-update-9.json')).writeAsString(jsonEncode({
      'versionCode': 9,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': bytes.length,
      'updatedAt': '2026-05-24T10:00:00.000Z',
      'installSessionId': 77,
    }));
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 200),
      availableBytes: () async => 1000000,
    );

    final session = await manager.readInstallSession(manifest);

    expect(session?.sessionId, 77);
    expect(session?.file.path, apk.path);
    await temp.delete(recursive: true);
  });

  test('clears install session metadata without deleting ready apk', () async {
    final temp =
        await Directory.systemTemp.createTemp('app-update-clear-session-');
    final bytes = utf8.encode('ready-apk');
    final manifest = _manifest(bytes, versionCode: 10);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final apk = File(_updateFile(dir, 'app-update-10.apk'));
    final metadataFile = File(_updateFile(dir, 'app-update-10.json'));
    await apk.writeAsBytes(bytes);
    await metadataFile.writeAsString(jsonEncode({
      'versionCode': 10,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': bytes.length,
      'updatedAt': '2026-05-24T10:00:00.000Z',
      'installSessionId': 77,
    }));
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 200),
      availableBytes: () async => 1000000,
    );

    await manager.clearInstallSession(manifest, sessionId: 13);

    var metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, Object?>;
    expect(metadata['installSessionId'], 77);

    await manager.clearInstallSession(manifest, sessionId: 77);

    metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, Object?>;
    expect(metadata.containsKey('installSessionId'), false);
    expect(await apk.exists(), true);
    await temp.delete(recursive: true);
  });

  test('clears all install session metadata without a manifest', () async {
    final temp =
        await Directory.systemTemp.createTemp('app-update-clear-orphans-');
    final bytes = utf8.encode('ready-apk');
    final manifest = _manifest(bytes, versionCode: 11);
    final dir = Directory(_updateDir(temp))..createSync(recursive: true);
    final apk = File(_updateFile(dir, 'app-update-11.apk'));
    final metadataFile = File(_updateFile(dir, 'app-update-11.json'));
    await apk.writeAsBytes(bytes);
    await metadataFile.writeAsString(jsonEncode({
      'versionCode': 11,
      'versionName': '1.4.0',
      'apkUrl': manifest.apkUrl,
      'sha256': manifest.sha256,
      'sizeBytes': bytes.length,
      'etag': manifest.etag,
      'downloadedBytes': bytes.length,
      'updatedAt': '2026-05-24T10:00:00.000Z',
      'installSessionId': 77,
    }));
    final manager = AppUpdateDownloadManager(
      cacheDirectory: temp,
      openStream: (uri, {rangeStart, ifRange}) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 200),
      availableBytes: () async => 1000000,
    );

    await manager.clearAllInstallSessions();

    final metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, Object?>;
    expect(metadata.containsKey('installSessionId'), false);
    expect(await apk.exists(), true);
    await temp.delete(recursive: true);
  });
}

AppUpdateManifest _manifest(
  List<int> bytes, {
  int versionCode = 2,
  String? etag,
}) {
  return AppUpdateManifest(
    schemaVersion: 1,
    platform: 'android',
    available: true,
    packageName: 'com.example.lan_ai_cli_control',
    versionName: '1.4.0',
    versionCode: versionCode,
    minSupportedVersionCode: 1,
    mandatory: false,
    apkUrl: '/api/app-updates/android/apk/$versionCode',
    sha256: AppUpdateDownloadManager.sha256HexForTest(bytes),
    sizeBytes: bytes.length,
    etag: etag ?? '"etag-$versionCode"',
    publishedAt: DateTime.utc(2026, 5, 24),
  );
}

String _updateDir(Directory temp) =>
    '${temp.path}${Platform.pathSeparator}app_updates';

String _updateFile(Directory dir, String name) =>
    '${dir.path}${Platform.pathSeparator}$name';

class _FakeBackgroundDownloadBridge implements BackgroundDownloadBridge {
  _FakeBackgroundDownloadBridge({
    required this.bytes,
    this.notificationsPrepared = true,
    this.notificationPreparationError,
    this.terminalStatus = BackgroundDownloadStatus.completed,
    this.startError,
  });

  final List<int> bytes;
  final bool notificationsPrepared;
  final Object? notificationPreparationError;
  final BackgroundDownloadStatus terminalStatus;
  final Object? startError;
  final requests = <BackgroundDownloadRequest>[];
  var prepareNotificationsCalls = 0;
  final _events = StreamController<BackgroundDownloadSnapshot>.broadcast();

  @override
  Future<bool> get isSupported async => true;

  @override
  Future<bool> prepareNotifications() async {
    prepareNotificationsCalls++;
    final error = notificationPreparationError;
    if (error != null) throw error;
    return notificationsPrepared;
  }

  @override
  Stream<BackgroundDownloadSnapshot> get events => _events.stream;

  @override
  Future<BackgroundDownloadSnapshot> start(
    BackgroundDownloadRequest request,
  ) async {
    final error = startError;
    if (error != null) throw error;
    requests.add(request);
    final file = File(request.destinationPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    final snapshot = BackgroundDownloadSnapshot(
      id: request.id,
      status: terminalStatus,
      downloadedBytes: bytes.length,
      totalBytes: request.expectedBytes,
      destinationPath: request.destinationPath,
      message: terminalStatus == BackgroundDownloadStatus.failed
          ? 'native failed'
          : null,
    );
    _events.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<BackgroundDownloadSnapshot?> snapshot(String id) async => null;
}
