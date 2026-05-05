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
}
