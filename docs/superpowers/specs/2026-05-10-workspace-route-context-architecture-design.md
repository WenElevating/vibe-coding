# Workspace Route Context Architecture Design

Date: 2026-05-10
Status: Approved for implementation planning
Scope: Flutter mobile workspace creation, workspace-scoped sessions, and workbench navigation state

## 1. Problem

The mobile workbench still treats a workspace as mutable global selection state. `CodingWorkbenchPage` owns the daemon workspace list, the selected workspace, local optimistic workspace IDs, session/conversation state, and navigation side effects in one stateful widget. That makes workspace creation vulnerable to stale daemon snapshots: a user creates a workspace, the UI locally inserts it, an older snapshot arrives, and the page may route back to the workspace list while the created workspace disappears.

The deeper issue is architectural. A workspace is not an app-wide selection that should be reconciled against every snapshot. It is the route context for the page the user entered. If the user taps a workspace, all session-list and conversation actions on that route are inside that workspace. Creating a workspace should be a workflow with a clear pending state, not a local list mutation.

## 2. Goals

- Remove global selected-workspace state from the workbench flow.
- Treat workspace identity as route context for session lists and conversations.
- Move workspace creation orchestration out of repositories and UI widgets into a workflow.
- Make daemon workspace lists authoritative; do not create local ghost workspaces.
- Show a transition state while workspace creation is pending.
- After creation succeeds, refresh the daemon workspace list once and navigate only when the created workspace is confirmed.
- Keep the implementation focused on mobile workbench architecture without changing daemon API contracts.

## 3. Non-Goals

- Do not redesign daemon workspace persistence.
- Do not add a routing package or dependency injection package.
- Do not rewrite the conversation renderer, ASR flow, adapters, or protocol models.
- Do not add durable “last selected workspace” persistence.
- Do not make repositories orchestrate multi-step application flows.

## 4. Architecture

Use the existing Flutter layered style with one added application workflow boundary.

```text
UI views
  WorkspaceListPage
  WorkspaceSessionsPage(workspace)
  WorkbenchConversationPage(workspace)

UI logic
  CodingWorkbenchViewModel / controller
  Immutable state for current route, creation progress, and visible daemon list

Application workflows
  workflows/workspace/create_workspace_workflow.dart

Data access
  WorkspaceRepository or existing DaemonClient wrapper
  DaemonClient.createWorkspace(...)
  DaemonClient.listWorkspaces()
```

Workflows sit in the application layer between UI logic and data access. They coordinate a business process but do not render UI and do not persist state themselves. Repositories and services remain responsible for data access only.

## 5. Route Context Model

Workspace context should come from navigation, not a mutable selected-workspace field.

```text
WorkspaceList
  tap workspace A
    -> WorkspaceSessions(workspace: A)
      New Session
        -> Conversation(workspace: A)
      Open History
        -> Conversation(workspace: A, conversationId)

WorkspaceList
  Create Workspace
    -> CreatingWorkspaceTransition
      success + refreshed list contains created workspace
        -> WorkspaceSessions(workspace: created)
      failure / timeout / refreshed list missing created workspace
        -> WorkspaceList + modal
```

The workbench should not ask “which workspace is selected?” It should ask “which workspace is this route operating in?” Creating a conversation uses the workspace carried by the current sessions or conversation route.

`CreatingWorkspaceTransition` is a blocking transition route. While it is visible, the user cannot interact with the workspace list, start another workspace creation, or open a workspace. The route shows progress and a timeout boundary instead of exposing a cancel action. Workspace creation is a server-side command; once the daemon receives it, client-side cancellation cannot reliably undo it. The safe escape path is timeout/failure handling, followed by an explicit retry refresh or return to the workspace list.

## 6. Workspace Creation Workflow

`CreateWorkspaceWorkflow` owns the multi-step flow:

1. Request workspace creation from data access.
2. Wait for success, failure, or timeout.
3. On success, call `listWorkspaces()` once.
4. Find the created workspace in the refreshed daemon list by ID.
5. Return `CreateWorkspaceSuccess(workspace, workspaces)` if found.
6. Return `CreateWorkspaceNotConfirmed` if creation succeeded but the refreshed list does not contain the workspace.
7. Return `CreateWorkspaceFailure` or `CreateWorkspaceTimeout` for failure paths.

The workflow must not update routes directly. It returns typed outcomes to the ViewModel/controller.

The timeout duration is injected into the workflow constructor, with a product default owned by the mobile composition root. Tests can pass a short timeout, and future environments can tune the value without editing workflow logic.

Retry semantics are split deliberately:

- `Retry refresh` repeats only `listWorkspaces()` and confirmation lookup for the already-created workspace ID.
- `Create another workspace` is a separate user action that returns to the add-workspace flow.
- The not-confirmed modal must not silently run the full create flow again, because that can duplicate workspaces.

## 7. UI State

The workbench UI state should be explicit and illegal combinations should be unrepresentable. Prefer a sealed route model rather than parallel enum fields:

```dart
sealed class WorkbenchRouteState {}

final class WorkspaceListRoute extends WorkbenchRouteState {
  WorkspaceListRoute({required this.workspaces, this.notice});
  final List<WorkspaceSummary> workspaces;
  final WorkspaceNotice? notice;
}

final class CreatingWorkspaceRoute extends WorkbenchRouteState {
  CreatingWorkspaceRoute({required this.requestLabel});
  final String requestLabel;
}

final class WorkspaceSessionsRoute extends WorkbenchRouteState {
  WorkspaceSessionsRoute({required this.workspace, required this.workspaces});
  final WorkspaceSummary workspace;
  final List<WorkspaceSummary> workspaces;
}

final class ConversationRoute extends WorkbenchRouteState {
  ConversationRoute({required this.workspace, required this.workspaces});
  final WorkspaceSummary workspace;
  final List<WorkspaceSummary> workspaces;
}
```

There is no `selectedWorkspace`. Workspace-scoped routes carry a non-null `WorkspaceSummary`; non-workspace routes do not. Creation errors, timeouts, and not-confirmed states return to `WorkspaceListRoute` with a notice/modal request rather than keeping a separate global creation status.

If a snapshot later omits the workspace of an already-open sessions/conversation route, the UI should keep the route stable and surface a non-destructive warning or refresh action. It should not silently pop back to the workspace list.

## 8. Data Flow

### 8.1 Open Existing Workspace

1. User taps a workspace row.
2. ViewModel sets route to `sessions(workspace)`.
3. Session list filters sessions by `workspace.id`.
4. New session creates a conversation with that same `workspace.id`.

### 8.2 Create Workspace

1. User completes the add-workspace sheet.
2. ViewModel sets route to `CreatingWorkspaceRoute`.
3. View shows the existing transition/loading animation.
4. ViewModel calls `CreateWorkspaceWorkflow`.
5. While the route is `CreatingWorkspaceRoute`, parent daemon snapshots do not update the visible workspace list or route context.
6. On success, ViewModel replaces `workspaces` with the list returned by the workflow's explicit `listWorkspaces()` call and routes to `WorkspaceSessionsRoute(createdWorkspace)`.
7. On failure, timeout, or not-confirmed outcome, ViewModel returns to the previous or latest workspace list and asks the View to show a modal dialog.

### 8.3 Daemon Snapshot Refresh

1. Parent app provides a newer daemon snapshot.
2. If the current route is `CreatingWorkspaceRoute`, ignore the snapshot for workbench route state. The workflow's explicit refresh is the only list update that can complete creation.
3. If the current route is `WorkspaceListRoute`, replace the visible list with the snapshot.
4. If the current route is `WorkspaceSessionsRoute` or `ConversationRoute`, update the auxiliary workspace list for future navigation but do not replace the route workspace.
5. If the current route workspace is missing from a later snapshot, expose a warning state but keep the user on the current route unless they choose to leave.

## 9. Error Handling

- Creation failure: show a modal with the daemon error and keep the workspace list unchanged.
- Creation timeout: show a modal explaining that creation did not finish in time; offer return to list and retry create as a new explicit action.
- Creation succeeded but refreshed list missing workspace: show a modal explaining that the daemon did not confirm the workspace yet; offer retry refresh only.
- Snapshot missing current route workspace: show a non-destructive warning, not an automatic navigation reset.
- Empty daemon workspace list: show workspace-list empty state; do not synthesize a selected workspace.

## 10. Testing

- Unit-test `CreateWorkspaceWorkflow` for success, create failure, timeout, and not-confirmed outcomes.
- Unit-test not-confirmed retry so it calls only `listWorkspaces()` and never repeats workspace creation.
- Unit-test the ViewModel/controller so snapshot refresh updates lists without changing route context.
- Unit-test the ViewModel/controller so snapshots are ignored while `CreatingWorkspaceRoute` is active.
- Unit-test concurrent create attempts so a second tap cannot start a second workflow while the transition route is active.
- Unit-test disposal or route exit during an in-flight workflow so completed futures do not mutate disposed state.
- Widget-test creating a workspace: transition appears, success routes to sessions for the daemon-confirmed workspace.
- Widget-test stale snapshot during creation: the app does not navigate back to the workspace list after success.
- Widget-test new session from a workspace route: conversation creation uses that route workspace ID.
- Widget-test opening history from a workspace route: conversation remains in that route workspace.
- Regression-test that missing route workspace in a later snapshot does not silently pop to the workspace list.

## 11. Migration Plan

1. Add the workspace creation workflow and typed outcomes.
2. Extract workspace route state into a small ViewModel/controller while keeping existing widgets.
3. Replace `_selectedWorkspace` reads in session and conversation flows with route workspace context.
4. Remove `_localWorkspaceIds` and optimistic workspace insertion.
5. Change create-workspace UI to show transition, wait for workflow, then route based on typed outcome.
6. Remove snapshot-sync navigation side effects.
7. Add regression tests before deleting old fallback logic.

## 12. Risks

- Risk: Existing tests assume a global selected workspace. Mitigation: update tests to assert route workspace context instead.
- Risk: A missing route workspace may leave users in a stale route. Mitigation: show a warning and give an explicit back-to-workspaces action.
- Risk: The first migration may touch a large widget. Mitigation: keep the workflow and controller small, then move UI pieces incrementally.
- Risk: Creation succeeds but daemon list is eventually consistent. Mitigation: treat missing-after-refresh as a clear not-confirmed outcome rather than inventing a local workspace.
