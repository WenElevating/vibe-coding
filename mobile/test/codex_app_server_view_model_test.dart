import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/models/codex_app_server_models.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/codex_app_server_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/codex_app_server/codex_app_server.dart';

void main() {
  test('CodexAppServerViewModel loads capabilities and thread history',
      () async {
    final repository = FakeCodexAppServerRepository(
      capabilities: const CodexAppServerCapabilities(
        raw: {},
        routes: [
          {'method': 'thread/list'}
        ],
        totalMethods: 187,
      ),
      threads: const [
        CodexAppServerThreadSummary(
          id: 'thread_1',
          title: 'Fix auth',
          workspacePath: 'D:/Repo',
          archived: false,
          raw: {},
        ),
      ],
    );
    final viewModel = CodexAppServerViewModel(repository: repository);

    await viewModel.load(workspaceId: 'workspace_1');

    expect(viewModel.state.capabilities?.totalMethods, 187);
    expect(viewModel.state.threads.single.id, 'thread_1');
    expect(() => viewModel.state.threads.add(viewModel.state.threads.single),
        throwsUnsupportedError);
    expect(viewModel.state.loading, false);
  });

  test('CodexAppServerViewModel clears stale workspace data on failure',
      () async {
    final repository = FakeCodexAppServerRepository(
      capabilities: const CodexAppServerCapabilities(
        raw: {},
        routes: [],
        totalMethods: 1,
      ),
      threads: const [
        CodexAppServerThreadSummary(
          id: 'thread_a',
          title: 'Workspace A',
          workspacePath: 'D:/A',
          archived: false,
          raw: {},
        ),
      ],
    );
    final viewModel = CodexAppServerViewModel(repository: repository);

    await viewModel.load(workspaceId: 'workspace_a');
    expect(viewModel.state.threads.single.id, 'thread_a');

    repository.failList = true;
    await viewModel.load(workspaceId: 'workspace_b');

    expect(viewModel.state.workspaceId, 'workspace_b');
    expect(viewModel.state.error, isNotNull);
    expect(viewModel.state.threads, isEmpty);
  });

  test('CodexAppServerViewModel ignores in-flight load after dispose',
      () async {
    final repository = FakeCodexAppServerRepository(
      capabilities: const CodexAppServerCapabilities(
        raw: {},
        routes: [],
        totalMethods: 1,
      ),
      delayCapabilities: true,
    );
    final viewModel = CodexAppServerViewModel(repository: repository);

    final load = viewModel.load(workspaceId: 'workspace_1');
    viewModel.dispose();
    repository.completeCapabilities();
    await load;

    expect(repository.listCalls, 0);
  });

  testWidgets('Codex app-server page renders history and discovery tabs',
      (tester) async {
    final viewModel = CodexAppServerViewModel(
      repository: FakeCodexAppServerRepository(
        capabilities: const CodexAppServerCapabilities(
          raw: {},
          routes: [
            {'method': 'thread/list'},
            {'method': 'fs/writeFile'},
          ],
          totalMethods: 187,
        ),
        threads: const [
          CodexAppServerThreadSummary(
            id: 'thread_1',
            title: 'Fix auth',
            workspacePath: 'D:/Repo',
            archived: false,
            raw: {},
          ),
        ],
        discovery: const CodexAppServerDiscoverySnapshot(
          models: {
            'providers': [
              {'id': 'openai'}
            ]
          },
          mcpServers: {
            'servers': [
              {'id': 'filesystem'}
            ]
          },
          skills: {
            'skills': [
              {'id': 'debugging'}
            ]
          },
          plugins: {
            'plugins': [
              {'id': 'superpowers'}
            ]
          },
          apps: {
            'apps': [
              {'id': 'codex'}
            ]
          },
          config: {
            'config': {'model': 'gpt-5'}
          },
        ),
      ),
    );

    await viewModel.load(workspaceId: 'workspace_1');
    await tester.pumpWidget(MaterialApp(
      home: CodexAppServerPage(
        viewModel: viewModel,
        workspace: const WorkspaceSummary(
          id: 'workspace_1',
          name: 'Repo',
          path: 'D:/Repo',
        ),
      ),
    ));

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Discovery'), findsOneWidget);
    expect(find.text('Risk Controls'), findsOneWidget);
    expect(find.text('Fix auth'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    await tester.tap(find.text('Discovery'));
    await tester.pumpAndSettle();

    expect(find.text('Model status'), findsOneWidget);
    expect(find.text('Config status'), findsOneWidget);
    expect(find.text('Capability status'), findsOneWidget);
    expect(find.text('Available'), findsWidgets);
  });
}

class FakeCodexAppServerRepository implements CodexAppServerRepository {
  FakeCodexAppServerRepository({
    required this.capabilities,
    this.threads = const <CodexAppServerThreadSummary>[],
    this.discovery = const CodexAppServerDiscoverySnapshot(
      models: {},
      mcpServers: {},
      skills: {},
      plugins: {},
      apps: {},
      config: {},
    ),
    this.delayCapabilities = false,
  });

  final CodexAppServerCapabilities capabilities;
  final List<CodexAppServerThreadSummary> threads;
  final CodexAppServerDiscoverySnapshot discovery;
  final bool delayCapabilities;
  bool failList = false;
  int listCalls = 0;
  Completer<void>? _capabilitiesCompleter;

  @override
  Future<CodexAppServerCapabilities> loadCapabilities() async {
    if (delayCapabilities) {
      _capabilitiesCompleter ??= Completer<void>();
      await _capabilitiesCompleter!.future;
    }
    return capabilities;
  }

  void completeCapabilities() {
    _capabilitiesCompleter?.complete();
  }

  @override
  Future<CodexAppServerDiscoverySnapshot> loadDiscovery() async => discovery;

  @override
  Future<CodexAppServerThreadPage> listThreads(
    String workspaceId, {
    int limit = 50,
  }) async {
    listCalls += 1;
    if (failList) throw StateError('list failed');
    return CodexAppServerThreadPage(
      threads: threads,
      nextCursor: null,
      raw: const {},
    );
  }

  @override
  Future<CodexAppServerThreadDetail> readThread(
    String workspaceId,
    String threadId,
  ) async =>
      CodexAppServerThreadDetail(
        thread: threads.firstWhere((thread) => thread.id == threadId),
        raw: const {},
      );
}
