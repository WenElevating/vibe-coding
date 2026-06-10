import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/codex_app_server_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/codex_app_server_repository.dart';

void main() {
  test('CodexAppServerThreadSummary parses stable daemon DTO', () {
    final summary = parseCodexAppServerThreadSummary(const {
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
    final capabilities = parseCodexAppServerCapabilities(const {
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
    final page = parseCodexAppServerThreadPage(const {
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

  test('CodexAppServerThreadPage ignores non-object list entries', () {
    final page = parseCodexAppServerThreadPage(const {
      'threads': [
        'not a thread object',
        {
          'id': 'thread_1',
          'title': 'Fix auth',
        },
        null,
      ],
    });

    expect(page.threads, hasLength(1));
    expect(page.threads.single.id, 'thread_1');
  });

  test('CodexAppServerDiscoverySnapshot preserves discovery route payloads',
      () {
    final snapshot = parseCodexAppServerDiscoverySnapshot(const {
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
    final repository = DaemonCodexAppServerRepository(
      getJson: (path) async {
        requests.add(path);
        switch (path) {
          case '/api/codex-app-server/capabilities':
            return const {
              'capabilityMatrix': {'totalMethods': 3},
              'routes': [],
            };
          case '/api/codex-app-server/workspaces/workspace_1/threads?limit=5':
            return const {
              'threads': [
                {'id': 'thread_1', 'title': 'Fix auth'}
              ],
            };
          case '/api/codex-app-server/workspaces/workspace_1/threads/thread_1':
            return const {
              'thread': {'id': 'thread_1', 'title': 'Fix auth'},
            };
          case '/api/codex-app-server/model-provider-capabilities':
            return const {'providers': []};
          case '/api/codex-app-server/mcp/servers':
            return const {'servers': []};
          case '/api/codex-app-server/skills':
            return const {'skills': []};
          case '/api/codex-app-server/plugins':
            return const {'plugins': []};
          case '/api/codex-app-server/apps':
            return const {'apps': []};
          case '/api/codex-app-server/config':
            return const {'config': <String, Object?>{}};
        }
        fail('Unexpected request: $path');
      },
    );

    final capabilities = await repository.loadCapabilities();
    final page = await repository.listThreads('workspace_1', limit: 5);
    final detail = await repository.readThread('workspace_1', 'thread_1');
    final discovery = await repository.loadDiscovery();

    expect(capabilities.totalMethods, 3);
    expect(page.threads.single.id, 'thread_1');
    expect(detail.thread.id, 'thread_1');
    expect(discovery.config['config'], isA<Map<String, Object?>>());
    expect(
      requests,
      containsAllInOrder(const <String>[
        '/api/codex-app-server/capabilities',
        '/api/codex-app-server/workspaces/workspace_1/threads?limit=5',
        '/api/codex-app-server/workspaces/workspace_1/threads/thread_1',
        '/api/codex-app-server/model-provider-capabilities',
        '/api/codex-app-server/mcp/servers',
        '/api/codex-app-server/skills',
        '/api/codex-app-server/plugins',
        '/api/codex-app-server/apps',
        '/api/codex-app-server/config',
      ]),
    );
  });

  test('readThread uses explicit workspace scope without list state', () async {
    final requests = <String>[];
    final repository = DaemonCodexAppServerRepository(
      getJson: (path) async {
        requests.add(path);
        switch (path) {
          case '/api/codex-app-server/workspaces/workspace_b/threads?limit=50':
            return const {'threads': []};
          case '/api/codex-app-server/workspaces/workspace_a/threads/thread_a':
            return const {
              'thread': {'id': 'thread_a', 'title': 'Fix auth'},
            };
        }
        fail('Unexpected request: $path');
      },
    );

    await repository.listThreads('workspace_b');
    final detail = await repository.readThread('workspace_a', 'thread_a');

    expect(detail.thread.id, 'thread_a');
    expect(
      requests,
      const <String>[
        '/api/codex-app-server/workspaces/workspace_b/threads?limit=50',
        '/api/codex-app-server/workspaces/workspace_a/threads/thread_a',
      ],
    );
  });
}
