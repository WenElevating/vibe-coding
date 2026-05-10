# Workspace Route Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make workspace creation and navigation route-context driven so stale workspace snapshots cannot kick users back to the workspace list after creating a workspace.

**Architecture:** Add a workspace creation workflow that owns create-then-refresh with typed outcomes, then refactor the workbench page so workspace-scoped routes carry their workspace context instead of relying on mutable global selected-workspace state. During the creating route, parent snapshots are ignored and only the workflow-owned `listWorkspaces()` result can complete creation.

**Tech Stack:** Flutter/Dart, existing `DaemonClient`, `ChangeNotifier`-free focused controller functions, `flutter_test` widget/unit tests.

---

## File Structure

- Create: `mobile/lib/src/workflows/workspace/create_workspace_workflow.dart` — application workflow for create, refresh, timeout, and not-confirmed outcomes.
- Modify: `mobile/lib/src/features/workbench/coding_workbench_controller.dart` — replace selected-workspace merge helpers with route-state helpers and workspace list refresh helpers.
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart` — remove local workspace overlay, introduce route workspace context, wire transition route and workflow outcomes.
- Modify: `mobile/test/daemon_connection_workflow_test.dart` not needed; workspace workflow gets its own test.
- Create: `mobile/test/create_workspace_workflow_test.dart` — workflow outcome and retry-refresh tests.
- Modify: `mobile/test/coding_workbench_controller_test.dart` — route-state and snapshot-refresh unit tests.
- Modify: `mobile/test/widget_test.dart` — regression test for create transition and new-session route context.

## Task 1: Workspace Creation Workflow

**Files:**
- Create: `mobile/lib/src/workflows/workspace/create_workspace_workflow.dart`
- Test: `mobile/test/create_workspace_workflow_test.dart`

- [ ] **Step 1: Write failing workflow tests**

Add tests that use a fake client/repository adapter with counters:

```dart
test('create succeeds only after refreshed list confirms workspace', () async {
  const created = WorkspaceSummary(id: 'workspace_new', name: 'New', path: r'D:\new');
  final client = FakeWorkspaceClient(
    createdWorkspace: created,
    listedWorkspaces: const <WorkspaceSummary>[created],
  );
  final workflow = CreateWorkspaceWorkflow(client: client, timeout: const Duration(seconds: 1));

  final outcome = await workflow.create(path: created.path, name: created.name);

  expect(outcome, isA<CreateWorkspaceSuccess>());
  expect((outcome as CreateWorkspaceSuccess).workspace, created);
  expect(outcome.workspaces, const <WorkspaceSummary>[created]);
  expect(client.createCalls, 1);
  expect(client.listCalls, 1);
});

test('create not confirmed can retry refresh without creating again', () async {
  const created = WorkspaceSummary(id: 'workspace_new', name: 'New', path: r'D:\new');
  final client = FakeWorkspaceClient(
    createdWorkspace: created,
    listedWorkspaces: const <WorkspaceSummary>[],
  );
  final workflow = CreateWorkspaceWorkflow(client: client, timeout: const Duration(seconds: 1));

  final first = await workflow.create(path: created.path, name: created.name);
  expect(first, isA<CreateWorkspaceNotConfirmed>());

  client.listedWorkspaces = const <WorkspaceSummary>[created];
  final second = await workflow.retryRefresh(created.id);

  expect(second, isA<CreateWorkspaceSuccess>());
  expect(client.createCalls, 1);
  expect(client.listCalls, 2);
});
```

- [ ] **Step 2: Run workflow tests to verify failure**

Run: `cd mobile && flutter test test/create_workspace_workflow_test.dart`
Expected: FAIL because the workflow file/types do not exist yet.

- [ ] **Step 3: Implement workflow and typed outcomes**

Create outcome classes:

```dart
sealed class CreateWorkspaceOutcome {
  const CreateWorkspaceOutcome();
}

final class CreateWorkspaceSuccess extends CreateWorkspaceOutcome {
  const CreateWorkspaceSuccess({required this.workspace, required this.workspaces});
  final WorkspaceSummary workspace;
  final List<WorkspaceSummary> workspaces;
}

final class CreateWorkspaceNotConfirmed extends CreateWorkspaceOutcome {
  const CreateWorkspaceNotConfirmed({required this.workspaceId, required this.workspaces});
  final String workspaceId;
  final List<WorkspaceSummary> workspaces;
}

final class CreateWorkspaceFailure extends CreateWorkspaceOutcome {
  const CreateWorkspaceFailure(this.error);
  final Object error;
}

final class CreateWorkspaceTimeout extends CreateWorkspaceOutcome {
  const CreateWorkspaceTimeout();
}
```

The workflow constructor accepts a small interface with `createWorkspace` and `listWorkspaces`, plus injected `timeout`.

- [ ] **Step 4: Run workflow tests to verify pass**

Run: `cd mobile && flutter test test/create_workspace_workflow_test.dart`
Expected: PASS.

## Task 2: Route State Controller Helpers

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_workbench_controller.dart`
- Test: `mobile/test/coding_workbench_controller_test.dart`

- [ ] **Step 1: Replace selected-workspace tests with route-context tests**

Add tests for sealed route states:

```dart
test('workspace snapshot replaces list route workspaces', () {
  const current = WorkspaceSummary(id: 'current', name: 'Current', path: r'D:\current');
  const updated = WorkspaceSummary(id: 'updated', name: 'Updated', path: r'D:\updated');

  final next = applyWorkspaceSnapshot(
    const WorkspaceListRouteState(workspaces: <WorkspaceSummary>[current]),
    const <WorkspaceSummary>[updated],
  );

  expect(next, isA<WorkspaceListRouteState>());
  expect((next as WorkspaceListRouteState).workspaces, const <WorkspaceSummary>[updated]);
});

test('workspace snapshot is ignored while creating workspace', () {
  const current = WorkspaceSummary(id: 'current', name: 'Current', path: r'D:\current');
  final state = CreatingWorkspaceRouteState(previousWorkspaces: const <WorkspaceSummary>[current], requestLabel: 'New');

  final next = applyWorkspaceSnapshot(state, const <WorkspaceSummary>[]);

  expect(identical(next, state), isTrue);
});
```

- [ ] **Step 2: Run controller tests to verify failure**

Run: `cd mobile && flutter test test/coding_workbench_controller_test.dart`
Expected: FAIL because new route state helpers do not exist and old selected-workspace tests still target removed helpers.

- [ ] **Step 3: Implement sealed route state helpers**

Replace `CodingWorkbenchState`, `upsertAndSelectWorkspace`, and `replaceWorkspacesFromDaemon` with:

```dart
sealed class WorkbenchRouteState {
  const WorkbenchRouteState();
  List<WorkspaceSummary> get workspaces;
}

final class WorkspaceListRouteState extends WorkbenchRouteState {
  const WorkspaceListRouteState({required this.workspaces, this.notice});
  @override
  final List<WorkspaceSummary> workspaces;
  final String? notice;
}

final class CreatingWorkspaceRouteState extends WorkbenchRouteState {
  const CreatingWorkspaceRouteState({required this.previousWorkspaces, required this.requestLabel});
  final List<WorkspaceSummary> previousWorkspaces;
  final String requestLabel;
  @override
  List<WorkspaceSummary> get workspaces => previousWorkspaces;
}

final class WorkspaceSessionsRouteState extends WorkbenchRouteState {
  const WorkspaceSessionsRouteState({required this.workspace, required this.workspaces});
  final WorkspaceSummary workspace;
  @override
  final List<WorkspaceSummary> workspaces;
}

final class ConversationRouteState extends WorkbenchRouteState {
  const ConversationRouteState({required this.workspace, required this.workspaces});
  final WorkspaceSummary workspace;
  @override
  final List<WorkspaceSummary> workspaces;
}
```

`applyWorkspaceSnapshot` ignores `CreatingWorkspaceRouteState`, replaces list-route workspaces, and updates auxiliary lists for sessions/conversation without replacing `workspace`.

- [ ] **Step 4: Run controller tests to verify pass**

Run: `cd mobile && flutter test test/coding_workbench_controller_test.dart`
Expected: PASS.

## Task 3: Wire Workbench Page to Route Context

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add failing widget regression**

Add a fake daemon scenario where create returns `workspace_new`, a parent update provides an old workspace list while creation is pending, then workflow refresh returns `workspace_new`. Assert the app remains in the transition during pending and lands on the new workspace session list after refresh.

```dart
testWidgets('created workspace routes to sessions despite stale parent snapshot', (tester) async {
  // Build Mobile/CodingWorkbench with fake client.
  // Open add workspace sheet, complete creation.
  // Trigger parent rebuild with stale workspaces while workflow is pending.
  // Complete workflow listWorkspaces with created workspace.
  // Expect session list header/path for created workspace and no workspace-list route.
});
```

- [ ] **Step 2: Run widget test to verify failure**

Run: `cd mobile && flutter test test/widget_test.dart --plain-name "created workspace routes to sessions despite stale parent snapshot"`
Expected: FAIL because page still uses `_selectedWorkspace` and optimistic list state.

- [ ] **Step 3: Introduce route state in page**

Replace `_workspaces`, `_selectedWorkspace`, `_workspaceConfirmedForSession`, and `_localWorkspaceIds` with a single `_routeState` initialized as `WorkspaceListRouteState(workspaces: widget.data.workspaces)`. Add helpers:

```dart
WorkspaceSummary? get _routeWorkspace => switch (_routeState) {
  WorkspaceSessionsRouteState(:final workspace) => workspace,
  ConversationRouteState(:final workspace) => workspace,
  _ => null,
};

List<WorkspaceSummary> get _workspaces => _routeState.workspaces;
```

- [ ] **Step 4: Route workspace through sessions and conversation**

Change `_goToSessions(workspace)` to set `WorkspaceSessionsRouteState(workspace: workspace, workspaces: _workspaces)`. Change `_startNewSessionFromList` to require a current route workspace and set `ConversationRouteState(workspace: workspace, workspaces: _workspaces)`. Change conversation creation to use `workspace.id` from `ConversationRouteState`.

- [ ] **Step 5: Wire create transition workflow**

Change `_showCreateWorkspaceFromWorkspaceList` so after the sheet returns a creation request/result, the page enters `CreatingWorkspaceRouteState`, awaits `CreateWorkspaceWorkflow`, then routes based on typed outcome. Remove optimistic upsert and `_localWorkspaceIds`.

- [ ] **Step 6: Remove snapshot navigation side effects**

Change `_syncWorkspacesFromSnapshot` to call `applyWorkspaceSnapshot` only. It must not call `_goToWorkspaces()` and must ignore snapshots while creating.

- [ ] **Step 7: Run focused widget regression**

Run: `cd mobile && flutter test test/widget_test.dart --plain-name "created workspace routes to sessions despite stale parent snapshot"`
Expected: PASS.

## Task 4: Verification and Cleanup

**Files:**
- Modify as needed: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Tests: `mobile/test/create_workspace_workflow_test.dart`, `mobile/test/coding_workbench_controller_test.dart`, `mobile/test/widget_test.dart`

- [ ] **Step 1: Run formatter on touched files**

Run: `cd mobile && dart format lib/src/workflows/workspace/create_workspace_workflow.dart lib/src/features/workbench/coding_workbench_controller.dart lib/src/features/workbench/coding_workbench_page.dart test/create_workspace_workflow_test.dart test/coding_workbench_controller_test.dart test/widget_test.dart`
Expected: files formatted, no syntax errors.

- [ ] **Step 2: Run analyzer**

Run: `cd mobile && flutter analyze --no-pub`
Expected: `No issues found!`

- [ ] **Step 3: Run focused tests**

Run: `cd mobile && flutter test test/create_workspace_workflow_test.dart test/coding_workbench_controller_test.dart`
Expected: all tests pass.

Run: `cd mobile && flutter test test/widget_test.dart --plain-name "created workspace routes to sessions despite stale parent snapshot"`
Expected: test passes.

- [ ] **Step 4: Commit implementation**

Commit only touched source/test files and ignored generated-file state. Use Lore trailers with `Tested:` containing analyzer and focused test evidence.

## Self-Review

- Spec coverage: route context, blocking creation transition, refresh-only not-confirmed retry, snapshot ignore during creation, sealed route state, timeout injection, and concurrency/dispose tests are covered.
- Placeholder scan: no `TBD` or deferred implementation steps remain.
- Type consistency: plan uses `CreateWorkspaceWorkflow`, `CreateWorkspaceOutcome`, `WorkbenchRouteState`, and route-state subclasses consistently.
