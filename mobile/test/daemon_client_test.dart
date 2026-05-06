import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config.dart';

void main() {
  test('empty daemon response becomes a client exception', () async {
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async => http.Response('', 200)),
    );

    expect(
      client.health,
      throwsA(isA<DaemonClientException>()
          .having((error) => error.body['error'], 'error', 'invalid_response')
          .having((error) => error.body['message'], 'message',
              contains('empty response'))),
    );
  });

  test('daemon direct proxy mode always bypasses proxies', () {
    expect(
      daemonClientProxyForUri(
        Uri.parse('http://127.0.0.1:4317'),
        proxyMode: DaemonProxyMode.direct,
      ),
      'DIRECT',
    );
    expect(
      daemonClientProxyForUri(
        Uri.parse('http://example.com:4317'),
        proxyMode: DaemonProxyMode.direct,
      ),
      'DIRECT',
    );
  });

  test('daemon system proxy mode bypasses local and private hosts', () {
    expect(
      daemonClientProxyForUri(
        Uri.parse('http://127.0.0.1:4317'),
        proxyMode: DaemonProxyMode.system,
      ),
      'DIRECT',
    );
    expect(
      daemonClientProxyForUri(
        Uri.parse('http://192.168.1.23:4317'),
        proxyMode: DaemonProxyMode.system,
      ),
      'DIRECT',
    );
  });

  test(
      'daemon manual proxy mode bypasses private hosts and proxies public hosts',
      () {
    final manualProxy = Uri.parse('http://192.168.20.18:27890');

    expect(
      daemonClientProxyForUri(
        Uri.parse('http://192.168.1.23:4317'),
        proxyMode: DaemonProxyMode.manual,
        manualProxy: manualProxy,
      ),
      'DIRECT',
    );
    expect(
      daemonClientProxyForUri(
        Uri.parse('http://example.com:4317'),
        proxyMode: DaemonProxyMode.manual,
        manualProxy: manualProxy,
      ),
      'PROXY 192.168.20.18:27890',
    );
  });
}
