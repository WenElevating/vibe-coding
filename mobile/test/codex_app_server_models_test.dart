import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/codex_app_server_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/codex_app_server_repository.dart';
import 'package:lan_ai_cli_control/src/services/conversation_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';

import 'support/fake_http.dart';

void main() {
  test('CodexAppServerThreadSummary parses stable daemon DTO', () {
    final summary = CodexAppServerThreadSummary.fromJson(const {
      'id': 'thread_1',
      'title': 'Fix auth',
      'workspacePath': 'D:/Repo',
      'archived': false,
    });

    expect(summary.id, 'thread_1');
    expect(summary.title, 'Fix auth');
    expect(summary.workspacePath, 'D:/Repo');
    expect(summary.archived, false);
  });

  test('CodexAppServerCapabilities derives total methods defensively', () {
    final capabilities = CodexAppServerCapabilities.fromJson(const {
      'capabilityMatrix': {
        'totalMethods': '7',
      },
      'routes': [
        {'method': 'thread/list'},
        {'method': 'thread/read'},
      ],
    });

    expect(capabilities.totalMethods, 7);
    expect(capabilities.routes, hasLength(2));
  });

  test('CodexAppServerThreadPage parses list envelope and cursor', () {
    final page = CodexAppServerThreadPage.fromJson(const {
      'threads': [
        {
          'id': 'thread_1',
          'title': 'Fix auth',
          'workspacePath': 'D:/Repo',
          'archived': false,
        }
      ],
      'nextCursor': 'next_page',
    });

    expect(page.threads.single.id, 'thread_1');
    expect(page.nextCursor, 'next_page');
  });

  test('CodexAppServerDiscoverySnapshot preserves discovery route payloads',
      () {
    final snapshot = CodexAppServerDiscoverySnapshot.fromJson(const {
      'models': {
        'providers': [
          {'id': 'openai'}
        ]
      },
      'mcpServers': {
        'servers': [
          {'id': 'server_1'}
        ]
      },
      'skills': {
        'skills': [
          {'id': 'skill_1'}
        ]
      },
      'plugins': {
        'plugins': [
          {'id': 'plugin_1'}
        ]
      },
      'apps': {
        'apps': [
          {'id': 'app_1'}
        ]
      },
      'config': {
        'config': {'model': 'gpt-5'}
      },
    });

    expect(snapshot.models['providers'], isA<List<Object?>>());
    expect(snapshot.mcpServers['servers'], isA<List<Object?>>());
    expect(snapshot.skills['skills'], isA<List<Object?>>());
    expect(snapshot.plugins['plugins'], isA<List<Object?>>());
    expect(snapshot.apps['apps'], isA<List<Object?>>());
    expect(snapshot.config['config'], isA<Map<String, Object?>>());
  });

  test('repository maps Codex app-server calls to daemon routes', () async {
    final requests = <String>[];
    final client = ConversationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: FakeHttpClient((request) {
        requests.add(request.url.path +
            (request.url.hasQuery ? '?${request.url.query}' : ''));
        switch (request.url.path) {
          case '/api/codex-app-server/capabilities':
            return jsonResponse(const {
              'capabilityMatrix': {'totalMethods': 3},
              'routes': [],
            });
          case '/api/codex-app-server/workspaces/workspace_1/threads/search':
            expect(request.url.queryParameters['limit'], '5');
            return jsonResponse(const {
              'threads': [
                {'id': 'thread_1', 'title': 'Fix auth'}
              ],
            });
          case '/api/codex-app-server/workspaces/workspace_1/threads/thread_1':
            return jsonResponse(const {
              'thread': {'id': 'thread_1', 'title': 'Fix auth'},
            });
          case '/api/codex-app-server/model-provider-capabilities':
            return jsonResponse(const {'providers': []});
          case '/api/codex-app-server/mcp/servers':
            return jsonResponse(const {'servers': []});
          case '/api/codex-app-server/skills':
            return jsonResponse(const {'skills': []});
          case '/api/codex-app-server/plugins':
            return jsonResponse(const {'plugins': []});
          case '/api/codex-app-server/apps':
            return jsonResponse(const {'apps': []});
          case '/api/codex-app-server/config':
            return jsonResponse(const {'config': {}});
        }
        fail('Unexpected request: ${request.url}');
      }),
    );
    final repository = DaemonCodexAppServerRepository(client: client);

    final capabilities = await repository.loadCapabilities();
    final page = await repository.listThreads('workspace_1', limit: 5);
    final detail = await repository.readThread('thread_1');
    final discovery = await repository.loadDiscovery();

    expect(capabilities.totalMethods, 3);
    expect(page.threads.single.id, 'thread_1');
    expect(detail.thread.id, 'thread_1');
    expect(discovery.config['config'], isA<Map<String, Object?>>());
    expect(
      requests,
      containsAllInOrder(const <String>[
        '/api/codex-app-server/capabilities',
        '/api/codex-app-server/workspaces/workspace_1/threads/search?limit=5',
        '/api/codex-app-server/workspaces/workspace_1/threads/thread_1',
        '/api/codex-app-server/model-provider-capabilities',
      ]),
    );
  });

  test('readThread requires a workspace-scoped list before route mapping', () {
    final repository = DaemonCodexAppServerRepository(
      client: ConversationClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore(),
        httpClient: FakeHttpClient((_) {
          fail('readThread should fail before HTTP without workspace scope');
        }),
      ),
    );

    expect(
      repository.readThread('thread_1'),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('listThreads'),
      )),
    );
  });
}
