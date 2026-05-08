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
}
