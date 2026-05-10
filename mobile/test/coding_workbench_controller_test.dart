import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/features/workbench/workbench.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  test('workspace list route exposes daemon-confirmed workspaces', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const route = WorkspaceListRouteState(
      workspaces: <WorkspaceSummary>[current],
    );

    expect(route.workspaces, const <WorkspaceSummary>[current]);
  });

  test(
      'creating workspace route keeps previous workspaces only as display state',
      () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const state = CreatingWorkspaceRouteState(
      previousWorkspaces: <WorkspaceSummary>[current],
      requestLabel: 'Created Workspace',
    );

    expect(state.workspaces, const <WorkspaceSummary>[current]);
    expect(state.requestLabel, 'Created Workspace');
  });

  test('sessions route carries workspace context and workspace list', () {
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

    const route = WorkspaceSessionsRouteState(
      workspace: created,
      workspaces: <WorkspaceSummary>[current, created],
    );

    expect(route.workspace, created);
    expect(route.workspaces, const <WorkspaceSummary>[current, created]);
  });

  test('conversation route carries workspace context and workspace list', () {
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

    const route = ConversationRouteState(
      workspace: conversationWorkspace,
      workspaces: <WorkspaceSummary>[current, conversationWorkspace],
    );

    expect(route.workspace, conversationWorkspace);
    expect(route.workspaces,
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
