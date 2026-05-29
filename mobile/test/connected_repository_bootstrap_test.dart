import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/daemon_workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';

void main() {
  test('conversation bootstrap records loaded workspace id', () {
    final repository = CachedConversationRepository(
      delegate: _UnusedConversationRepository(),
    );

    repository.replaceFromBootstrap(
      workspaceId: 'w1',
      conversations: const <ConversationSummary>[_conversation],
    );

    expect(repository.loadedWorkspaceId, 'w1');
    expect(repository.conversations.single.id, 'c1');
    expect(repository.loading, isFalse);
    expect(repository.error, isNull);
  });

  test('pending conversation refresh cannot overwrite bootstrap data',
      () async {
    final delegate = _PendingConversationRepository();
    final repository = CachedConversationRepository(delegate: delegate);
    final pendingRefresh = Completer<List<ConversationSummary>>();
    delegate.listConversationsCompleter = pendingRefresh;

    final refresh = repository.refresh();
    await pumpEventQueue();

    repository.replaceFromBootstrap(
      workspaceId: 'w2',
      conversations: const <ConversationSummary>[_conversationW2],
    );
    pendingRefresh.complete(const <ConversationSummary>[_conversation]);
    await refresh;

    expect(repository.loadedWorkspaceId, 'w2');
    expect(repository.conversations.map((item) => item.id), const <String>[
      'c2',
    ]);
  });

  test('pending conversation mutation cannot upsert old workspace data',
      () async {
    final delegate = _PendingConversationRepository();
    final repository = CachedConversationRepository(delegate: delegate);
    final pendingCreate = Completer<ConversationSummary>();
    delegate.createConversationCompleter = pendingCreate;

    final create = repository.createConversation(workspaceId: 'w1');
    await pumpEventQueue();

    repository.replaceFromBootstrap(
      workspaceId: 'w2',
      conversations: const <ConversationSummary>[_conversationW2],
    );
    pendingCreate.complete(_conversation);
    await create;

    expect(repository.loadedWorkspaceId, 'w2');
    expect(repository.conversations.map((item) => item.id), const <String>[
      'c2',
    ]);
  });

  test('run bootstrap records loaded workspace id and queue', () {
    final repository = CachedRunRepository(delegate: _UnusedRunRepository());

    repository.replaceFromBootstrap(
      workspaceId: 'w1',
      runs: const <RunSummary>[_run],
      queue: const <QueueItem>[_queueItem],
    );

    expect(repository.loadedWorkspaceId, 'w1');
    expect(repository.runs.single.id, 'r1');
    expect(repository.queue.single.runId, 'r1');
    expect(repository.loading, isFalse);
    expect(repository.error, isNull);
  });

  test('pending run refresh cannot overwrite bootstrap data', () async {
    final delegate = _PendingRunRepository();
    final repository = CachedRunRepository(delegate: delegate);
    final pendingRuns = Completer<List<RunSummary>>();
    final pendingQueue = Completer<List<QueueItem>>();
    delegate.listRunsCompleter = pendingRuns;
    delegate.listQueueCompleter = pendingQueue;

    final refresh = repository.refresh();
    await pumpEventQueue();

    repository.replaceFromBootstrap(
      workspaceId: 'w2',
      runs: const <RunSummary>[_runW2],
      queue: const <QueueItem>[_queueItemW2],
    );
    pendingRuns.complete(const <RunSummary>[_run]);
    pendingQueue.complete(const <QueueItem>[_queueItem]);
    await refresh;

    expect(repository.loadedWorkspaceId, 'w2');
    expect(repository.runs.map((item) => item.id), const <String>['r2']);
    expect(repository.queue.map((item) => item.runId), const <String>['r2']);
  });

  test('pending run mutation cannot upsert old workspace data', () async {
    final delegate = _PendingRunRepository();
    final repository = CachedRunRepository(delegate: delegate);
    final pendingCreate = Completer<RunSummary>();
    delegate.createRunCompleter = pendingCreate;

    final create = repository.createRun(tool: 'codex', workspaceId: 'w1');
    await pumpEventQueue();

    repository.replaceFromBootstrap(
      workspaceId: 'w2',
      runs: const <RunSummary>[_runW2],
      queue: const <QueueItem>[_queueItemW2],
    );
    pendingCreate.complete(_run);
    await create;

    expect(repository.loadedWorkspaceId, 'w2');
    expect(repository.runs.map((item) => item.id), const <String>['r2']);
    expect(repository.queue.map((item) => item.runId), const <String>['r2']);
  });

  test('workspace bootstrap keeps catalog when selected workspace is null', () {
    final repository = DaemonWorkspaceRepository(
      client: _UnusedDaemonClient(),
    );

    repository.applyBootstrapCatalog(
      selectedWorkspace: null,
      workspaces: const <WorkspaceSummary>[_workspace],
    );

    expect(repository.workspaces.single.id, 'w1');
    expect(repository.selectedWorkspace, isNull);
  });

  test('workspace bootstrap appends selected workspace missing from catalog',
      () {
    final repository = DaemonWorkspaceRepository(
      client: _UnusedDaemonClient(),
    );

    repository.applyBootstrapCatalog(
      selectedWorkspace: _workspace,
      workspaces: const <WorkspaceSummary>[],
    );

    expect(repository.workspaces.single.id, 'w1');
    expect(repository.selectedWorkspace?.id, 'w1');
  });

  test('pending workspace refresh cannot overwrite bootstrap catalog',
      () async {
    final pendingRefresh = Completer<List<WorkspaceSummary>>();
    final repository = DaemonWorkspaceRepository(
      client: _PendingWorkspaceDaemonClient(pendingRefresh),
    );

    final refresh = repository.refresh();
    await pumpEventQueue();

    repository.applyBootstrapCatalog(
      selectedWorkspace: _workspace2,
      workspaces: const <WorkspaceSummary>[_workspace2],
    );
    pendingRefresh.complete(const <WorkspaceSummary>[_workspace]);
    await refresh;

    expect(repository.workspaces.map((item) => item.id), const <String>['w2']);
    expect(repository.selectedWorkspace?.id, 'w2');
  });
}

const _conversationCapabilities = ConversationCapabilities(
  longLivedProcess: false,
  waitingInput: false,
  waitingApproval: false,
  resume: false,
  partialOutput: false,
);

const _conversation = ConversationSummary(
  id: 'c1',
  workspaceId: 'w1',
  adapter: 'codex',
  status: 'idle',
  capabilities: _conversationCapabilities,
  createdAt: '2026-05-29T00:00:00.000Z',
  updatedAt: '2026-05-29T00:00:00.000Z',
);

const _conversationW2 = ConversationSummary(
  id: 'c2',
  workspaceId: 'w2',
  adapter: 'codex',
  status: 'idle',
  capabilities: _conversationCapabilities,
  createdAt: '2026-05-29T00:00:00.000Z',
  updatedAt: '2026-05-29T00:00:00.000Z',
);

const _run = RunSummary(
  id: 'r1',
  tool: 'codex',
  workspaceId: 'w1',
  status: 'completed',
);

const _runW2 = RunSummary(
  id: 'r2',
  tool: 'codex',
  workspaceId: 'w2',
  status: 'completed',
);

const _queueItem = QueueItem(
  runId: 'r1',
  workspaceId: 'w1',
  position: 1,
  status: 'queued',
  reason: 'waiting',
);

const _queueItemW2 = QueueItem(
  runId: 'r2',
  workspaceId: 'w2',
  position: 1,
  status: 'queued',
  reason: 'waiting',
);

const _workspace = WorkspaceSummary(
  id: 'w1',
  name: 'Workspace',
  path: r'D:\workspace',
);

const _workspace2 = WorkspaceSummary(
  id: 'w2',
  name: 'Workspace 2',
  path: r'D:\workspace-2',
);

class _UnusedConversationRepository implements ConversationRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedRunRepository implements RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedDaemonClient implements DaemonClient {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingConversationRepository implements ConversationRepository {
  Completer<List<ConversationSummary>>? listConversationsCompleter;
  Completer<ConversationSummary>? createConversationCompleter;

  @override
  Future<List<ConversationSummary>> listConversations() =>
      listConversationsCompleter!.future;

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) =>
      createConversationCompleter!.future;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingRunRepository implements RunRepository {
  Completer<List<RunSummary>>? listRunsCompleter;
  Completer<List<QueueItem>>? listQueueCompleter;
  Completer<RunSummary>? createRunCompleter;

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) =>
      listRunsCompleter!.future;

  @override
  Future<List<QueueItem>> listQueue() => listQueueCompleter!.future;

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) =>
      createRunCompleter!.future;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingWorkspaceDaemonClient implements DaemonClient {
  _PendingWorkspaceDaemonClient(this.listWorkspacesCompleter);

  final Completer<List<WorkspaceSummary>> listWorkspacesCompleter;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() =>
      listWorkspacesCompleter.future;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
