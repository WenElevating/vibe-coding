import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/services/app_update_download_manager.dart';

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
        );
      },
      availableBytes: () async => 10000000,
    );

    final result =
        await manager.download(manifest, Uri.parse('http://127.0.0.1:4317'));

    expect(result.state, AppUpdateDownloadState.readyToInstall);
    expect(seenHeaders['rangeStart'], '5');
    expect(seenHeaders['ifRange'], manifest.etag);
    expect(await File(_updateFile(dir, 'app-update-2.apk')).readAsBytes(),
        bytes);
    expect(await part.exists(), false);
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
      'sha256': 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
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
    expect(await File(_updateFile(dir, 'app-update-4.apk')).readAsBytes(),
        bytes);
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
    expect(await File(_updateFile(dir, 'app-update-5.apk')).readAsBytes(),
        bytes);
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
    expect(await File(_updateFile(dir, 'app-update-6.apk')).readAsBytes(),
        bytes);
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

  test('reconciliation prefers verified apk over partial for same version', () async {
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
}

AppUpdateManifest _manifest(List<int> bytes, {int versionCode = 2}) {
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
    etag: '"etag-$versionCode"',
    publishedAt: DateTime.utc(2026, 5, 24),
  );
}

String _updateDir(Directory temp) =>
    '${temp.path}${Platform.pathSeparator}app_updates';

String _updateFile(Directory dir, String name) =>
    '${dir.path}${Platform.pathSeparator}$name';
