# Workspace Management and Search Design

Date: 2026-05-10
Status: Awaiting review before implementation planning
Scope: Daemon workspace rename/delete APIs and Flutter workbench workspace-list search/actions

## 1. Problem

The workspace surface currently supports adding workspaces but does not support changing or removing them. Users who mistype a display name, add the wrong directory, or want to clean up stale entries cannot manage the list from the app. The workspace-list search field also fails as an input affordance: it cannot be clicked and typed into reliably, so it does not help users find a workspace by name or path.

This is a safety-sensitive product surface because a workspace is the execution context for AI CLI runs. Management actions must make the context clearer without making local filesystem deletion feel casual or ambiguous.

## 2. Goals

- Add workspace rename support for display names only.
- Add workspace deletion from the app database only; never delete local files or folders.
- Make the workspace-list search field focusable, editable, clearable, and connected to list filtering.
- Filter workspaces by display name and path using case-insensitive matching.
- Keep the UI consistent with the current dark, restrained product theme.
- Preserve Flutter architecture boundaries: views render, view models own UI state, services wrap daemon calls, repositories isolate workspace data access.
- Add regression coverage for daemon behavior and Flutter state/UI behavior.

## 3. Non-Goals

- Do not delete, move, rename, or otherwise mutate local workspace directories on disk.
- Do not allow editing workspace paths in this iteration.
- Do not add batch operations or multi-select management.
- Do not search sessions, runs, file trees, or code content from this search field.
- Do not introduce new dependencies, a routing package, or a dependency-injection framework.
- Do not redesign the entire workbench navigation model.

## 4. Product and UI Direction

This is a product UI surface. The design should feel like a calm coding instrument: dense enough for real work, explicit about safety boundaries, and restrained in color.

Physical scene: a developer checks the mobile control surface during an active coding session in a dim room, trying to pick the right execution directory without accidentally affecting files. This supports the existing dark theme and restrained accent usage.

UI rules for this feature:

- Use the existing theme tokens from `mobile/lib/src/theme/theme.dart` rather than introducing a new visual system.
- Use accent color for focus, selected state, and primary confirmation only.
- Keep cards and rows visually compatible with existing workspace picker/workbench components.
- Avoid decorative motion; use short state transitions only for focus, filtering, and action feedback.
- Use clear copy: deletion removes the workspace from the app, not from disk.
- Avoid modal-heavy flow except for destructive confirmation. Rename uses a lightweight dialog because it is reversible, low risk, and should not compete with row tap navigation.

## 5. Architecture

Use the layered Flutter structure requested by the architecture skill while adapting it to the existing project layout.

```text
UI layer
  Workspace list/search/action widgets
  Rename confirmation input
  Delete confirmation dialog

UI logic layer
  WorkspaceManagementViewModel or focused controller helpers
  Immutable state: query, filtered workspaces, pending action, error/notice

Data layer
  WorkspaceRepository
  DaemonClient workspace methods

Daemon layer
  WorkspaceRegistry
  AppSQLiteStore workspace mutation methods
  HTTP API routes
```

Views must not call daemon mutation methods directly. The view model/controller owns user interactions and exposes commands such as `setSearchQuery`, `renameWorkspace`, and `deleteWorkspace`. The repository wraps `DaemonClient` and provides workspace-specific operations. If the current code path does not yet have a dedicated workspace repository, create a focused one rather than pushing more orchestration into large widgets.

The domain is simple CRUD, so no separate use-case layer is required unless implementation reveals duplicated cross-route orchestration.

## 6. Daemon API Design

Add two routes next to the existing workspace endpoints:

```text
PATCH /api/workspaces/:workspaceId
DELETE /api/workspaces/:workspaceId
```

### 6.1 Rename

`PATCH /api/workspaces/:workspaceId` accepts only a trimmed `name` field.

Rules:

- Reject missing or empty names with `400`.
- Keep `path` unchanged.
- Require the workspace to be authorized for the current device.
- Authorization failure returns the same `404 WORKSPACE_NOT_FOUND` shape used by existing workspace lookup paths, so the API does not disclose whether an unauthorized workspace exists.
- The operation is idempotent for the same `name`: if the trimmed new name equals the current name, return `200` with the current workspace summary and skip the database write.
- Concurrent rename requests are serialized by the SQLite write transaction or in-memory registry mutation. Last write wins, and every successful response contains the workspace state after that request's write.
- Return the updated workspace summary `{ id, name, path }`.
- Do not create a new workspace if the ID is unknown.

### 6.2 Delete

`DELETE /api/workspaces/:workspaceId` deletes the workspace record from app persistence and returns `204 No Content` on success.

Rules:

- Require the workspace to be authorized for the current device before deletion.
- Authorization failure returns the same `404 WORKSPACE_NOT_FOUND` shape used by existing workspace lookup paths, matching rename behavior and avoiding existence disclosure.
- Delete related workspace-device authorizations explicitly in the store method before deleting the workspace row. Do not rely on implicit SQLite cascade behavior unless the migration already guarantees it and tests prove it.
- Delete the workspace database row.
- Do not touch the local directory at `workspace.path`.
- Return `204 No Content` on success. The Flutter client treats any 2xx response as success and does not parse a delete response body.
- After deletion, subsequent authorized lookup for that workspace returns `404`.

For the no-store in-memory registry used by tests and lightweight runs, mirror the same behavior by updating the in-memory map and device authorization set.

## 7. Flutter Data Flow

`DaemonClient` gains:

```dart
Future<WorkspaceSummary> renameWorkspace({
  required String workspaceId,
  required String name,
});

Future<void> deleteWorkspace(String workspaceId);
```

`WorkspaceRepository` gains matching methods and remains the single workspace data access boundary for the view model. The repository returns clean `WorkspaceSummary` domain models already used by the app.

After a successful rename, the view model updates the local workspace list with the returned summary. After a successful delete, it removes the workspace from local state. If a parent daemon snapshot arrives later, the normal snapshot reconciliation should keep the daemon list authoritative.

## 8. Search Behavior

The workspace list owns a `searchQuery` string in UI state.

Filtering rules:

- Empty query shows all workspaces.
- Non-empty query matches `workspace.name` or `workspace.path`.
- Matching is case-insensitive and whitespace-trimmed.
- Filtering is local only and does not call the daemon.
- The query is view-model state only. It survives daemon snapshot/list updates while the workspace-list route instance remains alive, but route reconstruction resets it to empty.
- If no workspaces match, show an empty filtered state with a clear-search action.

The search field must be a real input control. It should receive focus on tap, show typed text, preserve query across local list updates, and expose a clear icon when non-empty.

## 9. Workspace Actions UI

Each workspace row/card gets a compact trailing overflow menu consistent with the current theme. Rename uses a lightweight dialog rather than inline editing, so row tap behavior remains dedicated to opening the workspace.

Actions:

- `Rename`: opens a focused name editor prefilled with the current display name. Save is disabled while the trimmed name is empty or unchanged. Success updates the row and closes the editor.
- `Delete from app`: opens a confirmation dialog. The dialog must state that local files are not deleted. Confirm removes the workspace from the app database and closes the dialog.

If the deleted workspace is the current route workspace, the preferred behavior is to return to the workspace list with a notice after the controller confirms it can safely replace the current route. If the current controller shape cannot perform that transition without destabilizing conversation state, the implementation must block deletion of the current route workspace and explain that the user should return to the workspace list first. Do not silently keep a deleted workspace as an active execution context.

## 10. Error Handling

- Rename validation failure: keep the editor open and show inline error text.
- Rename daemon failure: keep the previous name and show an error notice.
- Delete daemon failure: keep the workspace visible and show an error notice.
- Deleted current workspace: return to the workspace list with a clear notice when route replacement is safe; otherwise block the delete action before sending the request.
- Empty filtered results: show a quiet empty state and clear-search affordance.
- Empty workspace list: preserve the existing add-workspace path.

## 11. Accessibility and Internationalization

- Search field has a localized label and hint.
- Clear-search, rename, and delete actions have semantic labels.
- Delete confirmation copy avoids color-only warnings.
- Focus state is visible in the existing dark theme.
- Strings are added to the app localization files rather than hard-coded in widgets.

## 12. Testing

Daemon tests:

- Rename updates only the workspace name and preserves path.
- Rename rejects empty names.
- Rename with the same name returns `200` and does not change `updated_at`.
- Concurrent rename requests leave a valid workspace row with the last committed name.
- Rename requires authorization.
- Delete removes the workspace row and related authorizations.
- Delete returns `204 No Content`.
- Delete does not attempt filesystem deletion.
- Deleted workspace is no longer returned by `GET /api/workspaces` for the device.

Flutter tests:

- Search field accepts text and updates query state.
- Search filters by workspace name and path.
- Clear-search restores the full list.
- Search query survives daemon snapshot reconciliation while the route instance remains alive.
- Rename command updates the visible workspace name after repository success.
- Delete command removes the workspace from visible state after repository success.
- Delete-current-workspace returns to the list or is blocked before mutation when safe route replacement is unavailable.

## 13. Implementation Notes

- Keep diffs small: daemon persistence first, daemon API tests second, Flutter data boundary third, UI state and widgets last.
- Prefer reusing existing workspace display helpers for name/path formatting.
- Prefer existing button, sheet, dialog, and text-field styles over new one-off components.
- Do not add dependencies for state management; `ChangeNotifier`, `ValueNotifier`, or existing controller patterns are sufficient.
- Use UTF-8 safe edits for localization files.

## 14. Open Risks

- Existing workbench state may still keep route-level workspace objects after deletion. The implementation must verify whether safe route replacement is available; if not, current-route deletion must be blocked before mutation.
- If the current search field is non-interactive because of gesture layering or nested navigators, the fix may require moving the field or adjusting hit-testing rather than only wiring query state.
- SQLite foreign-key behavior must be verified before assuming workspace deletion cascades authorizations.
