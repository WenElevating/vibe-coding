import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/features/workbench/workbench.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  test('upsertAndSelectWorkspace replaces duplicate workspace id', () {
    const original = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Old Workspace',
      path: r'D:\old',
    );
    const updated = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Updated Workspace',
      path: r'D:\updated',
    );

    final next = upsertAndSelectWorkspace(
      const CodingWorkbenchState(
        workspaces: <WorkspaceSummary>[original],
        selectedWorkspace: original,
        listMode: CodingWorkbenchListMode.workspaces,
      ),
      updated,
    );

    expect(next.workspaces, hasLength(1));
    expect(next.workspaces.single, updated);
    expect(next.selectedWorkspace, updated);
    expect(next.listMode, CodingWorkbenchListMode.sessions);
  });

  test('replaceWorkspacesFromDaemon selects daemon-confirmed workspace', () {
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

    final next = replaceWorkspacesFromDaemon(
      const CodingWorkbenchState(
        workspaces: <WorkspaceSummary>[current],
        selectedWorkspace: current,
        listMode: CodingWorkbenchListMode.workspaces,
      ),
      const <WorkspaceSummary>[current, created],
      selectedWorkspaceId: created.id,
    );

    expect(next.workspaces, hasLength(2));
    expect(next.workspaces.map((workspace) => workspace.id),
        const <String>['workspace_current', 'workspace_created']);
    expect(next.selectedWorkspace, created);
    expect(next.listMode, CodingWorkbenchListMode.workspaces);
  });

  test(
      'replaceWorkspacesFromDaemon keeps selected local workspace when daemon is stale',
      () {
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

    final next = replaceWorkspacesFromDaemon(
      const CodingWorkbenchState(
        workspaces: <WorkspaceSummary>[current, created],
        selectedWorkspace: created,
        listMode: CodingWorkbenchListMode.sessions,
      ),
      const <WorkspaceSummary>[current],
      selectedWorkspaceId: created.id,
      preserveWorkspaceIds: <String>[created.id],
    );

    expect(next.workspaces.map((workspace) => workspace.id),
        const <String>['workspace_current', 'workspace_created']);
    expect(next.selectedWorkspace, created);
    expect(next.listMode, CodingWorkbenchListMode.sessions);
  });

  test('replaceWorkspacesFromDaemon drops unpreserved stale workspace', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const stale = WorkspaceSummary(
      id: 'workspace_stale',
      name: 'Stale Workspace',
      path: r'D:\stale',
    );

    final next = replaceWorkspacesFromDaemon(
      const CodingWorkbenchState(
        workspaces: <WorkspaceSummary>[current, stale],
        selectedWorkspace: stale,
        listMode: CodingWorkbenchListMode.sessions,
      ),
      const <WorkspaceSummary>[current],
      selectedWorkspaceId: stale.id,
    );

    expect(next.workspaces, const <WorkspaceSummary>[current]);
    expect(next.selectedWorkspace, current);
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
