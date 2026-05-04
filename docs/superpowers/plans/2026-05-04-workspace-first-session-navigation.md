# Workspace-First Session Navigation Implementation Plan

**Goal:** Make workspace selection the top-level Coding entry surface. Users choose a workspace first, then see only sessions for that workspace. The session-list `+` creates a session in the selected workspace and must not reopen the old workspace picker flow.

**Architecture:** Keep `CodingWorkbenchPage` as the transitional state owner for this pass, but split its UI modes into workspace list, workspace-scoped session list, and conversation detail. Folder add/browse remains reachable only from the workspace list.

## Guardrails

- Do not add dependencies.
- Do not add durable last-workspace persistence in this pass.
- Do not use the old first-run workspace sheet from the normal new-session path.
- Keep workspace disappearance safe: if the selected workspace disappears from a snapshot, reset conversation state and return to the workspace list.
- Keep feature boundaries inside the existing `part` library structure; do not introduce feature-to-feature imports.

## Tasks

### 1. Lock Regressions

- Add widget coverage that Coding entry starts at the workspace list.
- Add widget coverage that tapping the current workspace opens the workspace-scoped session list.
- Add widget coverage that sessions from other workspaces are hidden.
- Add widget coverage that a missing selected workspace falls back to the workspace list.

### 2. Build Workspace List Surface

- Add `_WorkspaceListPage` in `features/workspace_picker/`.
- Let selected workspace rows be tappable when the list is used as top-level navigation.
- Keep add/browse folder behavior behind the workspace-list Add action.

### 3. Scope Session List

- Update `_CodingSessionListPage` to render sessions for only `currentWorkspace`.
- Remove the old “other projects” section from the session list.
- Add a back affordance from session list to workspace list.
- Show a `New Session` empty-state action when the selected workspace has no sessions.

### 4. Wire Workbench Modes

- Replace the boolean session-list state with explicit modes: workspaces, sessions, conversation.
- Make workspace row taps select the workspace and open its session list.
- Make session-list `+` reset conversation state and open a blank conversation for the selected workspace.
- Make composer workspace chip open the workspace list, not a modal picker.

### 5. Update Previews and Tests

- Update debug preview builders to exercise workspace-first navigation.
- Add preview helpers for workspace-scoped sessions and missing-workspace fallback.
- Keep analyzer clean and all widget tests passing.

## Verification

- `dart format lib test`
- `flutter analyze --no-pub`
- `flutter test --no-pub`

## Manual QA

- Open Coding: workspace list appears first.
- Tap a workspace: only that workspace’s sessions appear.
- Tap `New Session`: composer opens without a workspace picker modal.
- Tap workspace chip from composer: returns to workspace list.
- Add/browse workspace: available only from workspace list.
