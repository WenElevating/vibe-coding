import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_app_update_repository.dart';
import 'package:lan_ai_cli_control/src/services/app_update_client.dart';

import 'support/fake_http.dart';

void main() {
  test('fetches latest manifest with bearer token and If-None-Match', () async {
    final requests = <http.BaseRequest>[];
    final client = FakeHttpClient((request) {
      requests.add(request);
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(request.headers['if-none-match'], '"old"');
      return jsonResponse(
        const <String, Object?>{
          'schemaVersion': 1,
          'platform': 'android',
          'available': false,
        },
        headers: const <String, String>{'etag': '"new"'},
      );
    });
    final updateClient = AppUpdateClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      httpClient: client,
      tokenProvider: () => 'token-1',
    );

    final result = await updateClient.fetchLatest(ifNoneMatch: '"old"');

    expect(result.notModified, false);
    expect(result.etag, '"new"');
    expect(result.manifest?.available, false);
    expect(requests.single.url.path, '/api/app-updates/android/latest');
  });

  test('opens apk stream with range and if-range headers', () async {
    final client = FakeHttpClient((request) {
      expect(request.method, 'GET');
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(request.headers['range'], 'bytes=5-');
      expect(request.headers['if-range'], '"etag"');
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('bytes')),
        206,
        headers: const <String, String>{
          'content-length': '5',
          'content-range': 'bytes 5-9/10',
        },
      );
    });
    final updateClient = AppUpdateClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      httpClient: client,
      tokenProvider: () => 'token-1',
    );

    final response = await updateClient.openApkStream(
      Uri.parse('http://127.0.0.1:4317/api/app-updates/android/apk/2'),
      rangeStart: 5,
      ifRange: '"etag"',
    );

    expect(response.statusCode, 206);
  });

  test('authorized apk stream rejects cross-origin URL before auth transport',
      () async {
    var transportCalled = false;
    final updateClient = AppUpdateClient.authorized(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      authorizedGet: (path, {required headers}) async {
        throw UnimplementedError();
      },
      authorizedStreamSend: (build) async {
        transportCalled = true;
        return http.StreamedResponse(Stream<List<int>>.empty(), 200);
      },
    );

    expect(
      () => updateClient.openApkStream(
        Uri.parse('https://evil.example.test/app.apk'),
      ),
      throwsArgumentError,
    );
    expect(transportCalled, false);
  });

  test('repository keeps cached manifest on 304 not modified', () async {
    final manifest = _manifest(versionCode: 4);
    final client = _FakeAppUpdateClient(<AppUpdateLatestResult>[
      AppUpdateLatestResult(
        notModified: false,
        etag: manifest.etag,
        manifest: manifest,
      ),
      AppUpdateLatestResult(notModified: true, etag: manifest.etag),
    ]);
    final repository = DaemonAppUpdateRepository(client: client);

    final first = await repository.fetchLatest();
    final second = await repository.fetchLatest(ifNoneMatch: manifest.etag);

    expect(first.versionCode, 4);
    expect(second.versionCode, 4);
    expect(second.available, true);
  });
}

AppUpdateManifest _manifest({required int versionCode}) {
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
    sha256: 'a' * 64,
    sizeBytes: 10,
    etag: '"etag-$versionCode"',
  );
}

class _FakeAppUpdateClient implements AppUpdateClient {
  _FakeAppUpdateClient(this.results);

  final List<AppUpdateLatestResult> results;

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:4317');

  @override
  Future<AppUpdateLatestResult> fetchLatest({String? ifNoneMatch}) async {
    return results.removeAt(0);
  }

  @override
  Future<http.StreamedResponse> openApkStream(
    Uri apkUri, {
    int? rangeStart,
    String? ifRange,
  }) {
    throw UnimplementedError();
  }
}
