import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/pages/home_command_deck_model.dart';

void main() {
  const current = WorkspaceSummary(
      id: 'workspace_1',
      name: 'vibe-coding',
      path: r'D:\AiProject\vibe-coding');
  const other = WorkspaceSummary(
      id: 'workspace_2', name: 'daemon', path: r'D:\AiProject\daemon');

  test('approval outranks failure and exposes overflow count', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_failed',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'failed'),
      ],
      conversations: <ConversationSummary>[
        conversation(
            id: 'conv_approval',
            workspaceId: 'workspace_1',
            status: 'waiting_approval',
            blockingItem: const ConversationBlockingItem(
                type: 'approval_request',
                approvalId: 'ap1',
                questionId: null,
                summary: 'Modify file')),
      ],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(data.now.kind, HomeSignalKind.approval);
    expect(data.now.id, 'conversation:conv_approval');
    expect(data.nowOverflowCount, 1);
    expect(data.executionStream.map((item) => item.id),
        contains('run:run_failed'));
  });

  test('interrupt lane shows other workspace running only when current is idle',
      () {
    final idleData = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current, other],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_other',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'running'),
      ],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(idleData.now.kind, HomeSignalKind.idle);
    expect(idleData.interrupts.map((item) => item.id),
        contains('workspace-run:workspace_2'));

    final activeData = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current, other],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_current',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'running'),
        RunSummary(
            id: 'run_other',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'running'),
      ],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(activeData.now.id, 'run:run_current');
    expect(activeData.interrupts, isEmpty);
  });

  test('execution stream excludes exact now item', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_current',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'running'),
        RunSummary(
            id: 'run_recent',
            tool: 'claude',
            workspaceId: 'workspace_1',
            status: 'completed'),
      ],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: 0,
      diagnostics: 0,
      recentFiles: 0,
    );

    expect(data.now.id, 'run:run_current');
    expect(data.executionStream.map((item) => item.id),
        isNot(contains('run:run_current')));
    expect(data.executionStream.map((item) => item.id),
        contains('run:run_recent'));
  });

  test('workspace signals preserve current workspace counts', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[
        QueueItem(
            runId: 'run_queued',
            workspaceId: 'workspace_1',
            position: 1,
            status: 'queued',
            reason: 'busy'),
      ],
      changedFiles: 5,
      diagnostics: 2,
      recentFiles: 4,
    );

    expect(data.signals.changedFiles, 5);
    expect(data.signals.diagnostics, 2);
    expect(data.signals.queue, 1);
    expect(data.signals.recentFiles, 4);
  });

  test('workspace signals preserve deferred unknown counts', () {
    final data = buildHomeCommandDeckData(
      currentWorkspace: current,
      workspaces: const <WorkspaceSummary>[current],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      changedFiles: null,
      diagnostics: null,
      recentFiles: null,
    );

    expect(data.signals.changedFiles, isNull);
    expect(data.signals.diagnostics, isNull);
    expect(data.signals.queue, 0);
    expect(data.signals.recentFiles, isNull);
  });
}

ConversationSummary conversation({
  required String id,
  required String workspaceId,
  required String status,
  ConversationBlockingItem? blockingItem,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: 'codex',
      status: status,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-06T10:00:00.000Z',
      updatedAt: '2026-05-06T10:01:00.000Z',
      blockingItem: blockingItem,
    );
