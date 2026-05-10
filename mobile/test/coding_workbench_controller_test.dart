import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/features/workbench/workbench.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  test('workspace snapshot replaces list route workspaces', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const updated = WorkspaceSummary(
      id: 'workspace_updated',
      name: 'Updated Workspace',
      path: r'D:\updated',
    );

    final next = applyWorkspaceSnapshot(
      const WorkspaceListRouteState(workspaces: <WorkspaceSummary>[current]),
      const <WorkspaceSummary>[updated],
    );

    expect(next, isA<WorkspaceListRouteState>());
    expect(next.workspaces, const <WorkspaceSummary>[updated]);
  });

  test('workspace snapshot is ignored while creating workspace', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const state = CreatingWorkspaceRouteState(
      previousWorkspaces: <WorkspaceSummary>[current],
      requestLabel: 'Created Workspace',
    );

    final next = applyWorkspaceSnapshot(state, const <WorkspaceSummary>[]);

    expect(identical(next, state), isTrue);
  });

  test('workspace snapshot preserves sessions route workspace context', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const created = WorkspaceSummary(
      id: 'workspace_created',
      name: 'Created Workspace',
      path: r'D:\created',
    );

    final next = applyWorkspaceSnapshot(
      const WorkspaceSessionsRouteState(
        workspace: created,
        workspaces: <WorkspaceSummary>[current, created],
      ),
      const <WorkspaceSummary>[current],
    );

    expect(next, isA<WorkspaceSessionsRouteState>());
    final sessions = next as WorkspaceSessionsRouteState;
    expect(sessions.workspace, created);
    expect(sessions.workspaces, const <WorkspaceSummary>[current, created]);
  });

  test('workspace snapshot keeps route workspace in auxiliary list', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const created = WorkspaceSummary(
      id: 'workspace_created',
      name: 'Created Workspace',
      path: r'D:\created',
    );

    final next = applyWorkspaceSnapshot(
      const WorkspaceSessionsRouteState(
        workspace: created,
        workspaces: <WorkspaceSummary>[current, created],
      ),
      const <WorkspaceSummary>[current],
    ) as WorkspaceSessionsRouteState;

    expect(next.workspace, created);
    expect(next.workspaces, const <WorkspaceSummary>[current, created]);
  });

  test('workspace snapshot preserves conversation route workspace context', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const conversationWorkspace = WorkspaceSummary(
      id: 'workspace_conversation',
      name: 'Conversation Workspace',
      path: r'D:\conversation',
    );

    final next = applyWorkspaceSnapshot(
      const ConversationRouteState(
        workspace: conversationWorkspace,
        workspaces: <WorkspaceSummary>[conversationWorkspace],
      ),
      const <WorkspaceSummary>[current],
    );

    expect(next, isA<ConversationRouteState>());
    final conversation = next as ConversationRouteState;
    expect(conversation.workspace, conversationWorkspace);
    expect(conversation.workspaces,
        const <WorkspaceSummary>[current, conversationWorkspace]);
  });

  test('reusable conversation statuses can send another message', () {
    expect(canSendInConversationStatus(null), isTrue);
    expect(canSendInConversationStatus('idle'), isTrue);
    expect(canSendInConversationStatus('cancelled'), isTrue);
    expect(canSendInConversationStatus('failed'), isTrue);
    expect(canSendInConversationStatus('interrupted'), isTrue);
    expect(canSendInConversationStatus('running'), isFalse);
    expect(canSendInConversationStatus('waiting_input'), isFalse);
    expect(canSendInConversationStatus('waiting_approval'), isFalse);
  });

  test('active conversation status helper matches executor states', () {
    expect(isActiveConversationStatus('running'), isTrue);
    expect(isActiveConversationStatus('waiting_input'), isTrue);
    expect(isActiveConversationStatus('waiting_approval'), isTrue);
    expect(isActiveConversationStatus('cancelled'), isFalse);
    expect(isActiveConversationStatus('interrupted'), isFalse);
  });

  test('cancelled conversation summary keeps product identity and binding', () {
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'cancelled',
      cliSessionId: 'claude-session-1',
      sessionBinding: 'confirmed',
      userMessageCount: 2,
      capabilities: ConversationCapabilities(
        longLivedProcess: true,
        waitingInput: true,
        waitingApproval: true,
        resume: true,
        partialOutput: true,
      ),
      blockingItem: ConversationBlockingItem(type: 'approval_request'),
      createdAt: '2026-05-08T00:00:00.000Z',
      updatedAt: '2026-05-08T00:00:01.000Z',
    );

    final cancelled = applyCancelledConversationSummary(conversation);

    expect(cancelled.id, 'conv_1');
    expect(cancelled.cliSessionId, 'claude-session-1');
    expect(cancelled.sessionBinding, 'confirmed');
    expect(cancelled.userMessageCount, 2);
    expect(cancelled.blockingItem, isNull);
  });
}
