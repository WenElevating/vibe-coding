# Mobile App ViewModel Workspace State Design

## Problem

The mobile app currently treats daemon connection and workspace availability as the same readiness boundary. `AppSnapshot.loadBootstrap()` loads the workspace list and immediately reads `workspaces.first`, which means a valid daemon connection with zero workspaces cannot be represented. On a first mobile connection, an empty workspace list is normal, but the app surfaces it as a connection failure with `Bad state: No element`.

This is an architecture problem, not a networking problem. The connected app needs a state model where workspace availability is repository-backed collection state, and where the UI reacts to collection changes over time.

## Goals

- Let a daemon connection succeed even when `listWorkspaces()` returns an empty list.
- Represent workspace collection state as ordinary observable UI state.
- Avoid fake placeholder workspaces.
- Avoid splitting connection status into `ConnectedNoWorkspace` and `ConnectedWithWorkspace`.
- Keep the current stage simple by using one app-level ViewModel with internal state sections.
- Preserve repository semantics: an empty workspace list is valid data, not an exception.

## Non-Goals

- Do not redesign daemon HTTP endpoints.
- Do not rewrite all feature ViewModels in one pass.
- Do not split workspace-scoped ViewModels during this migration; keep that as a future extraction if `AppViewModel` grows beyond clear ownership.
- Do not make every UI widget own workspace loading logic.
- Do not introduce a new state management dependency.

## Recommended Architecture

Use one app-level ViewModel for the connected mobile shell, with explicit internal state sections.

```dart
class AppViewModel extends ChangeNotifier {
  // Section 1: daemon connection
  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;
  DaemonHealth? health;
  Object? connectionError;

  // Section 2: workspace catalog, repository-backed and allowed to be empty
  List<WorkspaceSummary> workspaces = [];
  String? selectedWorkspaceId;
  bool workspacesLoading = false;
  Object? workspacesError;

  // Section 3: selected workspace scoped content
  WorkspaceDetail? selectedWorkspaceDetail;
  bool detailLoading = false;
  Object? detailError;

  Future<void> connect();
  Future<void> loadWorkspaces();
  Future<void> startCreateWorkspaceFlow();
  Future<void> createWorkspace(String path, String? name);
  void selectWorkspace(String id);
  Future<void> refreshDetail();
}
```

`AppViewModel` is the observable UI state owner. It should be injected with repositories or use cases. Views subscribe to it with `ListenableBuilder` or equivalent Flutter primitives.

`WorkspaceDetail` is the workspace-scoped data object. It replaces `AppSnapshot` for workspace-scoped business logic. During migration, `AppSnapshot` may temporarily become a type alias or adapter around `WorkspaceDetail`, but both names must not remain as competing business concepts.

```dart
class WorkspaceDetail {
  final WorkspaceSummary workspace;
  final ProjectOverview overview;
  final List<RunSummary> runs;
  final List<ConversationSummary> conversations;
  final List<QueueItem> queue;
  final GitStatusSummary? gitStatus;
  final FileTreeResponse fileTree;
  final CodeDiagnosticsSummary diagnostics;
}
```

## State Matrix

Every row below is legal and must render without throwing.

| Connection | Workspaces | Selected Workspace | Detail | UI |
| --- | --- | --- | --- | --- |
| `connecting` | any | any | any | Connection loading |
| `connected` | `[]` | `null` | `null` | Workspace empty state with add workspace action |
| `connected` | `[a, b]` | `null` | `null` | Workspace list visible, no selected workspace |
| `connected` | `[a, b]` | `a` | loading | Workspace shell with scoped loading state |
| `connected` | `[a, b]` | `a` | ready | Normal workspace UI |
| `failed` | any | any | any | Connection failure with retry |

The current bug is that the second row cannot be constructed because the bootstrap path assumes `workspaces.first` exists.

## Repository Rules

Repositories expose facts. They do not convert empty collections into failures.

```dart
Future<List<WorkspaceSummary>> listWorkspaces();
```

`listWorkspaces()` may return `[]`. Errors are reserved for network failures, authorization failures, invalid daemon responses, and other exceptional conditions.

`createWorkspace()` should return the created workspace plus a refreshed catalog, or the ViewModel should refresh the catalog immediately after creation. After a successful create, the ViewModel selects the new workspace, persists that selection, and calls `refreshDetail()`.

## UI Rendering Rule

Views render state. They do not invent connection states or create fake workspaces.

```dart
ListenableBuilder(
  listenable: appViewModel,
  builder: (context, _) {
    if (appViewModel.connectionStatus != ConnectionStatus.connected) {
      return ConnectionScreen(viewModel: appViewModel);
    }

    if (appViewModel.workspacesLoading) {
      return const LoadingView();
    }

    if (appViewModel.workspaces.isEmpty) {
      return EmptyWorkspaceView(onAddWorkspace: appViewModel.startCreateWorkspaceFlow);
    }

    return WorkshellView(viewModel: appViewModel);
  },
)
```

This branch is presentation rendering over observable state. It is not a daemon connection state split.

## Data Flow

1. User taps connect.
2. `AppViewModel.connect()` validates address, checks daemon health, pairs device, and stores the connected client/config.
3. `connectionStatus` becomes `connected`.
4. `AppViewModel.loadWorkspaces()` calls `WorkspaceRepository.listWorkspaces()`.
5. If the list is empty, `workspaces = []`, `selectedWorkspaceId = null`, and UI shows the workspace empty state.
6. If the list has items, the ViewModel selects the last persisted workspace id if it still exists, otherwise the first item.
7. Selecting a workspace calls `refreshDetail()`.
8. `refreshDetail()` loads all workspace-scoped resources: overview, runs, conversations, queue, git status, diffs, commits, file tree, diagnostics, and any other detail resources needed by the selected workspace shell.

Workspace selection persistence is part of `loadWorkspaces()` and `selectWorkspace()`:

```dart
final savedId = await _selectionStore.readLastSelectedWorkspaceId();
final hasSavedWorkspace = workspaces.any((workspace) => workspace.id == savedId);
selectedWorkspaceId = hasSavedWorkspace
    ? savedId
    : workspaces.isEmpty
        ? null
        : workspaces.first.id;
```

`selectWorkspace(id)` must write the selected id through the same selection store before notifying listeners. The store can be implemented with `SharedPreferences` or an existing local settings store, but the key and ownership should be centralized, for example `lastSelectedWorkspaceId` inside a workspace selection store.

`startCreateWorkspaceFlow()` is a UI-intent method, not the repository method itself. It may open the existing add-workspace sheet or route to a picker. Once the user supplies `path` and optional `name`, the ViewModel calls `createWorkspace(path, name)` internally.

`refreshDetail()` must protect against stale responses when users switch workspaces quickly. Use a cancellation token, generation counter, or response-time workspace id comparison. A response may update `selectedWorkspaceDetail` only if it still matches the current `selectedWorkspaceId`.

## Migration Plan

1. Add `AppViewModel` with connection, workspace catalog, and workspace detail sections.
2. Keep existing repositories and `DaemonClient` behavior unchanged.
3. Stop using `AppSnapshot.loadBootstrap()` as a daemon connection bootstrap that requires `workspaces.first`.
4. Replace `AppSnapshot` usage in workspace-scoped business logic with `WorkspaceDetail`; during migration only, `AppSnapshot` may be a compatibility alias or adapter for `WorkspaceDetail`.
5. Update `MainTabsPage` or the connected shell to subscribe to `AppViewModel`.
6. Update workspace list UI to render an empty state from `workspaces.isEmpty`.
7. Update Home, Settings, and Workbench to read selected workspace detail only when available.
8. Remove the global assumption that a connected app always has `data.workspace`.

## Testing Strategy

- Unit test `AppViewModel.connect()` succeeds when `WorkspaceRepository.listWorkspaces()` returns `[]`.
- Widget test connected empty workspace UI renders the add workspace action.
- Unit test `createWorkspace()` refreshes the catalog and selects the created workspace.
- Unit test selecting a workspace loads workspace-scoped detail.
- Unit test `loadWorkspaces()` restores `lastSelectedWorkspaceId` when present and falls back to the first workspace when missing or stale.
- Unit test `loadWorkspaces()` network failure sets `workspacesError` and does not change `connectionStatus` to `failed`.
- Unit test stale `refreshDetail()` responses are ignored when `selectedWorkspaceId` changes before the response completes.
- Regression test that real connection failures still show connection failure, not workspace empty state.
- Architecture import check remains required for Flutter architecture changes.

## Risks

- `AppSnapshot.workspace` is used widely. Do not nullable-convert the whole tree in one pass unless the implementation plan scopes that work carefully; replace it with `WorkspaceDetail` behind compatibility adapters first.
- A single `AppViewModel` can become too large. Keep sections explicit and consider extracting smaller ViewModels only when a section grows beyond clear ownership.
- Some pages may currently assume selected workspace data synchronously. Those pages need explicit loading/empty rendering.
- `refreshDetail()` can race with workspace selection changes. Do not apply a detail response unless it belongs to the current `selectedWorkspaceId`.

## Decision

Adopt a single `AppViewModel` with internal state sections for connection, workspace catalog, and selected workspace detail. Workspace availability is mutable collection state, not daemon connection state. Empty workspace lists are valid and must render as first-use UI.
