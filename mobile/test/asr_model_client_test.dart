import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lan_ai_cli_control/src/services/asr_model_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';

void main() {
  test('empty metadata response becomes an ASR client exception', () async {
    final client = AsrModelClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token',
      httpClient: MockClient((request) async => http.Response('', 200)),
    );

    await expectLater(
      client.metadata(),
      throwsA(isA<AsrModelClientException>()
          .having((error) => error.body['error'], 'error', 'invalid_response')
          .having((error) => error.message, 'message',
              contains('empty ASR model response'))),
    );
  });

  test('DaemonClient-created ASR client reuses daemon auth and HTTP transport',
      () async {
    final daemon = DaemonClient(
      baseUri: Uri.parse('http://192.168.1.23:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/pair') {
          return http.Response(
              '{"deviceId":"device_1","token":"paired-token"}', 200);
        }
        expect(request.url.path, '/api/asr-model');
        expect(request.headers['authorization'], 'Bearer paired-token');
        return http.Response(
            '{"version":"model-v1","fileName":"model-v1.zip","sizeBytes":1,"sha256":"digest","downloadPath":"/api/asr-model/download"}',
            200);
      }),
    );

    await daemon.pair(code: '123456');
    final metadata = await daemon.createAsrModelClient().metadata();

    expect(metadata.version, 'model-v1');
  });
}
