import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
}
