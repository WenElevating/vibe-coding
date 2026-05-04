# Workspace-First Session Navigation Design

Date: 2026-05-04
Status: Approved for implementation planning
Scope: Flutter mobile workspace list, session list, and new-session navigation

## 1. Problem

The current new-session flow mixes workspace selection and session creation in the same bottom sheet. In the screenshot, tapping `Current Project` does not open a conversation because the selected workspace row is disabled. More importantly, the interaction model is wrong: a workspace is the execution context for CLI runs, while a session is a conversation inside that context.

When workspace selection appears only as a modal before first run, users cannot build a stable mental model of where CLI commands will execute. This conflicts with the product principle that execution context must be visible before action.

## 2. Goals

- Make workspace selection the top-level navigation surface before session selection.
- Make session lists scoped to one selected workspace.
- Keep `+` in a workspace-scoped session list focused on creating a new session only.
- Move folder creation/browsing into the workspace list as an explicit workspace-management action.
- Remove the first-run workspace confirmation bottom sheet from the primary new-session path.
- Preserve existing daemon APIs, conversation APIs, and visual tone.

## 3. Non-Goals

- Do not redesign the whole workbench conversation UI.
- Do not change daemon persistence or workspace/session API shapes unless an existing parameter already supports scoping.
- Do not add new dependencies.
- Do not introduce a new global router package.

## 4. Information Architecture

Use a two-level hierarchy:

```text
Workspace List
  - Current Project
  - Added workspace A
  - Added workspace B
  - Add / browse folder

Workspace Session List
  - Header: workspace name + path
  - Existing sessions for that workspace
  - New session action

Workbench Conversation
  - Active conversation for selected workspace
```

The workspace list answers: where will CLI run?

The session list answers: which conversation inside this workspace?

The composer answers: what should the agent do next?

## 5. UX Behavior

### 5.1 Workspace List

The top-level list should show workspaces as large rows with name, path, and a subtle indicator for the current/default workspace. Tapping any workspace opens that workspace's session list.

The add/browse action opens the existing folder creation/browser flow. When a workspace is created, it is added to the workspace list and opened immediately.

The selected workspace state should initialize from the current in-memory `_selectedWorkspace` when it still exists in the latest workspace snapshot. If it does not exist, fall back to the first workspace returned by the daemon and show the workspace list so the user can see the context reset. This design does not add durable last-workspace persistence yet; that can be added later only after the workspace/session navigation is stable.

### 5.2 Workspace-Scoped Session List

The session list title should include the selected workspace name and path. Its rows should show only sessions/runs that belong to that workspace.

The `+` action creates a new conversation inside the selected workspace and opens the workbench composer. It should not ask for workspace again.

If there are no sessions, show an empty state with `这个工作区还没有会话` and a primary `新建会话` action.

### 5.3 Workbench

The workbench should receive an explicit selected `WorkspaceSummary`. Starting a conversation should use that workspace id directly.

The old first-run workspace confirmation sheet should be removed from the normal app flow in this change. The only remaining workspace modal should be the add/browse folder flow launched from the workspace list.

## 6. Component Boundary

- `features/workspace_picker/` owns the workspace list page, workspace row rendering, folder browsing, and workspace creation sheets.
- `features/sessions/` owns only the workspace-scoped session list and session row rendering.
- `features/workbench/` owns the active conversation and composer, assuming workspace is already selected.
- `shell/` wires page-level callbacks but does not own workspace/session row rendering.

## 7. Data Flow

- `CodingWorkbenchPage` keeps the available workspace list and selected workspace state until a dedicated controller exists.
- Workspace list selection sets `_selectedWorkspace` and shows the session list for that workspace.
- New session from the scoped session list calls `_resetConversationState()`, clears the prompt, marks workspace confirmed, and opens the composer.
- Existing session selection keeps using existing conversation/run ids but must respect the selected workspace filter.
- Snapshot refresh must check whether `_selectedWorkspace` is still present in the latest workspace list. If it is missing and another workspace exists, set `_selectedWorkspace` to the first available workspace, clear the selected session/conversation view, and show the workspace list so the user explicitly sees the fallback context.
- The transitional state ownership should end when session-list widget tests need to mock workspace state directly. That is the signal to extract a small workspace/session navigation controller from `CodingWorkbenchPage`.

## 8. Error Handling

- Workspace creation errors stay in the add/browse sheet.
- Empty workspace list falls back to current project when the daemon returns at least one workspace.
- Empty session list is a normal state, not an error.
- If a selected workspace disappears from the daemon snapshot, fall back to the first available workspace and return to the workspace list.

## 9. Testing

- Add or update widget tests so the new-session path starts at a workspace list.
- Verify tapping `Current Project` opens a workspace-scoped session list.
- Verify tapping `+` from the workspace-scoped session list opens the composer without showing the first-run workspace sheet.
- Verify the session list only shows sessions/runs for the selected workspace.
- Verify that when the selected workspace disappears from a snapshot, the UI returns to the workspace list instead of crashing, blanking, or continuing under a stale workspace.
- Verify `flutter analyze --no-pub` and `flutter test --no-pub` pass.

## 10. Risks

- Risk: Session filtering may accidentally hide valid conversations. Mitigation: reuse existing workspace id fields from run/conversation summaries and keep fallback behavior explicit.
- Risk: Removing the modal path may break preview tests. Mitigation: update preview helpers to render the new workspace-first surface.
- Risk: The first implementation may still keep workspace/session state in `CodingWorkbenchPage`. Mitigation: document it as transitional and avoid adding new feature-to-feature imports.
