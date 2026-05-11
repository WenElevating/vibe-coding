import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/device_identity_store.dart';

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

  test('GET retries once after transient client exception', () async {
    var calls = 0;
    final client = DaemonClient(
      baseUri: Uri.parse('http://192.168.3.94:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) throw http.ClientException('write failed', request.url);
        return http.Response(
          '{"status":"ok","daemonVersion":"test","mode":"test","lanMode":false,"bindAddress":"127.0.0.1","port":4317,"security":{}}',
          200,
        );
      }),
    );

    final health = await client.health();

    expect(health.status, 'ok');
    expect(calls, 2);
  });

  test('recordException returns daemon trace id', () async {
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/exceptions');
        return http.Response(
            '{"traceId":"trc_test","createdAt":"2026-05-07T00:00:00.000Z"}',
            201);
      }),
    );

    final trace = await client.recordException(message: 'SocketException');

    expect(trace.traceId, 'trc_test');
  });

  test('pair stores access and refresh tokens separately', () async {
    final tokenStore = MemoryTokenStore();
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/pair');
        return http.Response(
          '{"deviceId":"device-1","token":"access-1","refreshToken":"refresh-1","accessTokenExpiresAt":"2026-05-18T08:00:00.000Z","refreshTokenExpiresAt":"2026-06-10T08:00:00.000Z"}',
          200,
        );
      }),
    );

    await client.pair(code: '123456', deviceId: 'device-1');

    expect(client.currentToken, 'access-1');
    expect(await tokenStore.readAccessToken('device-1'), 'access-1');
    expect(await tokenStore.readRefreshToken('device-1'), 'refresh-1');
    expect((await tokenStore.readAccessTokenSession('device-1'))!.expiresAt,
        DateTime.parse('2026-05-18T08:00:00.000Z'));
    expect((await tokenStore.readRefreshTokenSession('device-1'))!.expiresAt,
        DateTime.parse('2026-06-10T08:00:00.000Z'));
  });

  test('refresh rotates tokens without changing device identity', () async {
    final tokenStore = MemoryTokenStore();
    var refreshCalls = 0;
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/pair') {
          return http.Response(
            '{"deviceId":"device-1","token":"access-1","refreshToken":"refresh-1","accessTokenExpiresAt":"2026-05-18T08:00:00.000Z","refreshTokenExpiresAt":"2026-06-10T08:00:00.000Z"}',
            200,
          );
        }
        expect(request.url.path, '/api/token/refresh');
        expect(request.headers.containsKey('authorization'), false);
        refreshCalls++;
        return http.Response(
          '{"deviceId":"device-1","token":"access-2","refreshToken":"refresh-2","accessTokenExpiresAt":"2026-05-19T08:00:00.000Z","refreshTokenExpiresAt":"2026-06-11T08:00:00.000Z"}',
          200,
        );
      }),
    );

    await client.pair(code: '123456', deviceId: 'device-1');
    await client.refreshToken();

    expect(refreshCalls, 1);
    expect(client.currentToken, 'access-2');
    expect(await tokenStore.readAccessToken('device-1'), 'access-2');
    expect(await tokenStore.readRefreshToken('device-1'), 'refresh-2');
    expect((await tokenStore.readAccessTokenSession('device-1'))!.expiresAt,
        DateTime.parse('2026-05-19T08:00:00.000Z'));
  });

  test('ensurePaired refreshes stored access token within refresh skew', () async {
    final tokenStore = MemoryTokenStore();
    await tokenStore.writeAccessTokenSession(
      'device-1',
      TokenSession(
          token: 'access-1',
          expiresAt: DateTime.parse('2026-05-11T08:05:00.000Z')),
    );
    await tokenStore.writeRefreshTokenSession(
      'device-1',
      TokenSession(
          token: 'refresh-1',
          expiresAt: DateTime.parse('2026-06-10T08:00:00.000Z')),
    );
    var refreshCalls = 0;
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: tokenStore,
      now: () => DateTime.parse('2026-05-11T08:00:00.000Z'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/token/refresh');
        refreshCalls++;
        return http.Response(
          '{"deviceId":"device-1","token":"access-2","refreshToken":"refresh-2","accessTokenExpiresAt":"2026-05-18T08:00:00.000Z","refreshTokenExpiresAt":"2026-06-10T08:00:00.000Z"}',
          200,
        );
      }),
    );

    await client.ensurePaired(
        deviceIdentityStore: MemoryDeviceIdentityStore(deviceId: 'device-1'));

    expect(refreshCalls, 1);
    expect(client.currentToken, 'access-2');
  });

  test('authorized request refreshes and retries once after auth required', () async {
    final tokenStore = MemoryTokenStore();
    final requests = <http.Request>[];
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/pair') {
          return http.Response(
            '{"deviceId":"device-1","token":"access-1","refreshToken":"refresh-1","accessTokenExpiresAt":"2026-05-18T08:00:00.000Z","refreshTokenExpiresAt":"2026-06-10T08:00:00.000Z"}',
            200,
          );
        }
        if (request.url.path == '/api/adapters' && requests.where((item) => item.url.path == '/api/adapters').length == 1) {
          expect(request.headers['authorization'], 'Bearer access-1');
          return http.Response('{"error":"AUTH_REQUIRED","message":"invalid bearer token"}', 401);
        }
        if (request.url.path == '/api/token/refresh') {
          expect(request.headers.containsKey('authorization'), false);
          return http.Response(
            '{"deviceId":"device-1","token":"access-2","refreshToken":"refresh-2","accessTokenExpiresAt":"2026-05-19T08:00:00.000Z","refreshTokenExpiresAt":"2026-06-11T08:00:00.000Z"}',
            200,
          );
        }
        expect(request.url.path, '/api/adapters');
        expect(request.headers['authorization'], 'Bearer access-2');
        return http.Response('{"adapters":[]}', 200);
      }),
    );

    await client.pair(code: '123456', deviceId: 'device-1');
    final adapters = await client.listAdapters();

    expect(adapters, isEmpty);
    expect(client.currentToken, 'access-2');
    expect(await tokenStore.readAccessToken('device-1'), 'access-2');
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
