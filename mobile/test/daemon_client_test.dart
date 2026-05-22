import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lan_ai_cli_control/src/data/services/conversation_service.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/device_identity_store.dart';

import 'support/fake_http.dart';

void main() {
  test('close is idempotent and closes injected HTTP client', () {
    final httpClient = FakeHttpClient(
      (_) => jsonResponse(const <String, Object?>{}),
    );
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: httpClient,
    );

    client.close();
    client.close();

    expect(httpClient.closed, isTrue);
  });

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

  test('sendConversationMessage text-only remains JSON', () async {
    late Map<String, Object?> uploaded;
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/conversations/conv_1/messages');
        expect(request.headers['content-type'],
            contains('application/json; charset=utf-8'));
        uploaded = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(jsonEncode(_conversationResponse()), 200);
      }),
    );

    final conversation = await client.sendConversationMessage(
      'conv_1',
      const ConversationServiceMessageSendRequest(text: 'hello'),
    );

    expect(uploaded, const <String, Object?>{'text': 'hello'});
    expect(conversation.id, 'conv_1');
  });

  test('sendConversationMessage with attachments uses multipart form data',
      () async {
    final directory = await Directory.systemTemp.createTemp('daemon-client-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file =
        File('${directory.path}${Platform.pathSeparator}screenshot.png');
    const fileBytes = <int>[1, 2, 3, 4];
    await file.writeAsBytes(fileBytes);

    late String contentType;
    late List<int> multipartBytes;
    late String multipartBody;
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: FakeHttpClient((request) async {
        expect(request.url.path, '/api/conversations/conv_1/messages');
        multipartBytes =
            await request.finalize().expand((chunk) => chunk).toList();
        multipartBody = utf8.decode(multipartBytes, allowMalformed: true);
        contentType = request.headers['content-type'] ?? '';
        return jsonResponse(_conversationResponse());
      }),
    );

    await client.sendConversationMessage(
      'conv_1',
      ConversationServiceMessageSendRequest(
        text: 'see attached',
        clientMessageId: 'client_1',
        capabilityVersion: '4bcf6aa44f7e2e074229f9cd',
        attachments: <ConversationServiceMessageAttachment>[
          ConversationServiceMessageAttachment(
            localPath: file.path,
            name: 'screenshot.png',
            mimeType: 'image/png',
            kind: 'image',
            sizeBytes: 4,
          ),
        ],
      ),
    );

    expect(contentType, startsWith('multipart/form-data; boundary='));
    expect(multipartBody, contains('"text":"see attached"'));
    expect(multipartBody, contains('"clientMessageId":"client_1"'));
    expect(
      multipartBody,
      contains('"capabilityVersion":"4bcf6aa44f7e2e074229f9cd"'),
    );
    expect(multipartBody, contains('"field":"files[0]"'));
    expect(multipartBody, contains('"name":"screenshot.png"'));
    expect(multipartBody, contains('"mimeType":"image/png"'));
    expect(multipartBody, contains('"kind":"image"'));
    expect(multipartBody, contains('name="files[]"'));
    expect(multipartBody, isNot(contains('name="files[0]"')));
    expect(multipartBody, contains('filename="screenshot.png"'));
    expect(_containsSubsequence(multipartBytes, fileBytes), isTrue);
  });

  test('recordException redacts diagnostics before upload', () async {
    late Map<String, Object?> uploaded;
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/exceptions');
        uploaded = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
            '{"traceId":"trc_test","createdAt":"2026-05-07T00:00:00.000Z"}',
            201);
      }),
    );

    await client.recordException(
      message:
          'Authorization: Bearer secret-token at https://example.com/path?token=secret',
      severity: 'info',
      stack: r'C:\Users\Alice\repo\main.dart api_key=secret-key',
      path: r'C:\Users\Alice\repo\main.dart',
      metadata: const <String, Object?>{
        'password': 'hunter2',
        'request': 'https://example.com/run?access_token=secret',
        'id': '123e4567-e89b-12d3-a456-426614174000',
      },
    );

    expect(uploaded['message'], contains('Authorization: Bearer [REDACTED]'));
    expect(uploaded['severity'], 'info');
    expect(uploaded['message'],
        contains('https://example.com/path?[REDACTED_QUERY]'));
    expect(uploaded['message'], isNot(contains('secret-token')));
    expect(uploaded['stack'], contains(r'[USER_PATH]\main.dart'));
    expect(uploaded['stack'], isNot(contains('secret-key')));
    expect(uploaded['path'], r'[USER_PATH]\main.dart');
    final metadata = uploaded['metadata'] as Map<String, Object?>;
    expect(metadata['password'], '[REDACTED]');
    expect(metadata['request'], 'https://example.com/run?[REDACTED_QUERY]');
    expect(metadata['id'], '123e4567-e89b-12d3-a456-426614174000');
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

  test('ensurePaired refreshes stored access token within refresh skew',
      () async {
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

  test('authorized request refreshes and retries once after auth required',
      () async {
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
        if (request.url.path == '/api/adapters' &&
            requests.where((item) => item.url.path == '/api/adapters').length ==
                1) {
          expect(request.headers['authorization'], 'Bearer access-1');
          return http.Response(
              '{"error":"AUTH_REQUIRED","message":"invalid bearer token"}',
              401);
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

  test('list endpoints report typed parse errors for malformed lists',
      () async {
    final cases = <({
      String name,
      String key,
      Map<String, Object?> body,
      Future<Object?> Function(DaemonClient client) call,
    })>[
      (
        name: 'listAdapters',
        key: 'adapters',
        body: const <String, Object?>{'adapters': 'bad'},
        call: (client) => client.listAdapters(),
      ),
      (
        name: 'listShortcuts',
        key: 'shortcuts',
        body: const <String, Object?>{'shortcuts': 'bad'},
        call: (client) => client.listShortcuts(),
      ),
      (
        name: 'listCommandTemplates',
        key: 'templates',
        body: const <String, Object?>{'templates': 'bad'},
        call: (client) => client.listCommandTemplates(),
      ),
      (
        name: 'listQueue',
        key: 'queue',
        body: const <String, Object?>{'queue': 'bad'},
        call: (client) => client.listQueue(),
      ),
      (
        name: 'gitDiff',
        key: 'summaries',
        body: const <String, Object?>{'summaries': 'bad'},
        call: (client) => client.gitDiff('workspace_1'),
      ),
      (
        name: 'listRuns',
        key: 'runs',
        body: const <String, Object?>{'runs': 'bad'},
        call: (client) => client.listRuns(),
      ),
      (
        name: 'fetchEvents',
        key: 'events',
        body: const <String, Object?>{'events': 'bad'},
        call: (client) => client.fetchEvents('run_1'),
      ),
      (
        name: 'listConversations',
        key: 'conversations',
        body: const <String, Object?>{'conversations': 'bad'},
        call: (client) => client.listConversations(),
      ),
      (
        name: 'fetchConversationEvents',
        key: 'events',
        body: const <String, Object?>{'events': 'bad'},
        call: (client) => client.fetchConversationEvents('conv_1'),
      ),
    ];

    for (final entry in cases) {
      final client = DaemonClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore(),
        httpClient: FakeHttpClient((_) => jsonResponse(entry.body)),
      );

      await expectLater(
        entry.call(client),
        throwsA(isA<DaemonClientException>().having(
          (error) => error.body['message'],
          '${entry.name} message',
          contains(entry.key),
        )),
      );
    }
  });
}

Map<String, Object?> _conversationResponse() => const <String, Object?>{
      'conversation': <String, Object?>{
        'id': 'conv_1',
        'workspaceId': 'workspace_1',
        'adapter': 'codex',
        'status': 'running',
        'capabilities': <String, Object?>{},
        'createdAt': '2026-05-20T00:00:00.000Z',
        'updatedAt': '2026-05-20T00:00:01.000Z',
      },
    };

bool _containsSubsequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  if (needle.length > haystack.length) return false;
  for (var start = 0; start <= haystack.length - needle.length; start++) {
    var matched = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[start + offset] != needle[offset]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}
