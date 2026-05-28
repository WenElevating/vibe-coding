# Mobile Repository-Owned State Architecture Design

- Date: 2026-05-28
- Status: design approved, pending written-spec review
- Scope: Flutter mobile runtime state ownership for connected shell, workspace
  catalog, home, settings, and workbench.

## Context

The mobile app already uses a layered structure with `app`, `data`, `domain`,
`ui`, `services`, and `workflows`. The current runtime state shape still keeps
too much business data in shell-level snapshots:

- `AppSnapshot` aggregates daemon health, workspace catalog, current workspace,
  adapters, runs, conversations, queue, and other workspace-scoped data.
- `MainTabsViewModel` owns `AppSnapshot data` and passes it to Home, Workbench,
  and Settings.
- `CodingWorkbenchPage` creates its own `WorkbenchViewModel`, but
  `didUpdateWidget` calls `updateFromSnapshot(widget.data)` whenever the parent
  rebuilds.
- `WorkbenchRouteState` carries `List<WorkspaceSummary>` in each route state.

This creates competing runtime owners for the same business facts. A concrete
failure is workspace creation from the workbench:

1. Workbench creates a workspace through the daemon.
2. The create workflow refreshes the daemon workspace list.
3. `WorkbenchViewModel` updates only its local route state with the new list.
4. `MainTabsViewModel.data` still contains the old `AppSnapshot`.
5. Switching tabs rebuilds `MainTabsPage`.
6. `CodingWorkbenchPage.didUpdateWidget` reapplies the old snapshot.
7. The newly created workspace disappears until the app restarts and bootstraps
   fresh data from the daemon.

The daemon persistence path is not the root cause. The defect is mobile runtime
state ownership.

## Decision

Adopt repository-owned shared runtime data with feature-owned ViewModels.

Repositories are the connection-scoped data authority. They may keep in-memory
caches and expose `ChangeNotifier` updates. Feature ViewModels subscribe to the
repositories they need and own only feature UI state. The main tab shell owns
only shell/navigation state.

Do not introduce a separate `Store` layer. A `Store` with cache and
`ChangeNotifier` behavior would duplicate the intended Repository role and
would become another global state container.

## Goals

- Remove `AppSnapshot` and `MainTabsViewModel.data` as runtime business state
  sources.
- Make shared business data come from connection-scoped Repository instances.
- Keep Home, Settings, and Workbench independently owned by their feature
  ViewModels.
- Keep MainTabs as a shell-only owner of tab, overlay, bottom-navigation, and
  back behavior.
- Remove workspace catalog copies from `WorkbenchRouteState`.
- Eliminate the parent-snapshot-to-child-state overwrite path that causes newly
  created workspaces to disappear.
- Follow the Flutter layered architecture: View, ViewModel, optional UseCase,
  Repository, Service.
- Preserve current visible UI behavior unless a state transition must be made
  explicit.

## Non-Goals

- Do not redesign visuals.
- Do not introduce Riverpod, Bloc, GetIt, or another state-management or
  dependency-injection package.
- Do not add a `Store` layer above repositories.
- Do not rewrite daemon HTTP APIs.
- Do not split all protocol models into new domain models in this pass.
- Do not refactor unrelated daemon behavior.
- Do not keep the old AppViewModel direction as a parallel architecture.

## Architecture

Target runtime flow:

```text
View
  -> ViewModel
    -> UseCase, only when the workflow has ordered or cross-repository effects
      -> Repository, the shared data authority and cache
        -> Service, stateless API/local platform call wrapper
          -> DaemonClient or platform API
```

Layer responsibilities:

```text
View
  Renders state and forwards user intent to its ViewModel.

ViewModel
  Owns UI state and presentation orchestration for one feature. It subscribes
  to repositories and projects repository data into feature state. It must not
  be the long-term authority for shared business data.

UseCase
  Coordinates ordered side effects. It has no UI state and no listeners. It is
  optional and should exist only when a workflow is more than simple CRUD.

Repository
  Owns connection-scoped business data, in-memory cache, refresh semantics, and
  change notifications. Multiple ViewModels subscribe to the same instance.

Service
  Wraps raw daemon or platform calls. It is stateless and does not notify.
```

## Repository Boundary In This Codebase

The current `domain/` layer must remain pure and must not import Flutter. A
concrete repository that extends `ChangeNotifier` therefore belongs in `data/`,
not `domain/`.

Target layout:

```text
mobile/lib/src/domain/repositories/
  Pure Dart repository contracts or command interfaces, if still useful.
  No Flutter imports.

mobile/lib/src/data/services/
  Stateless API services. They call DaemonClient or platform APIs.

mobile/lib/src/data/repositories/
  Concrete repositories. They may extend ChangeNotifier, hold in-memory cache,
  implement domain contracts, call services, and notify ViewModels.
```

This keeps the official Flutter Repository role while preserving this repo's
existing import-boundary rules.

## Core Runtime Components

### WorkspaceRepository

`WorkspaceRepository` is the workspace catalog authority for one connected
daemon session.

Responsibilities:

- Hold `List<WorkspaceSummary> workspaces`.
- Hold `String? selectedWorkspaceId` or `WorkspaceSummary? selectedWorkspace`.
- Expose loading and error state for workspace catalog operations.
- Load workspaces from `WorkspaceService`.
- Create, rename, delete, and refresh workspaces through `WorkspaceService`.
- Select a workspace and notify subscribers.
- Refresh the catalog after create and select the created workspace.

It should expose read-only snapshots. This snippet is the listenable runtime
repository contract consumed by UI ViewModels and implemented in
`data/repositories/`. If a separate `domain/` repository interface is kept, that
domain interface must stay pure Dart and must not import Flutter or extend
`ChangeNotifier`.

```dart
abstract class WorkspaceRepository extends ChangeNotifier {
  List<WorkspaceSummary> get workspaces;
  WorkspaceSummary? get selectedWorkspace;
  bool get loading;
  Object? get error;

  Future<void> load();
  Future<void> refresh();
  Future<WorkspaceSummary> create({
    required String path,
    String? name,
  });
  bool select(String workspaceId);
}
```

The implementation may keep private mutable fields, but public lists must be
unmodifiable or defensive copies.

`select` returns `true` only when the requested workspace exists and selection
was accepted. It returns `false` for unknown or deleted workspace ids. Callers
must handle `false` by falling back to a valid route such as the workspace list
instead of silently staying on a stale workspace route.

`create` returns the created workspace on success and completes with an error on
failure. The current codebase has no repository-wide `Result<T>` convention, so
this design must not introduce a one-off `Result<WorkspaceSummary>` just for
workspace creation. Implementations should map daemon/service errors to the
repository's normal typed failure or exception style, set operation error state
if exposed, notify listeners for loading/error changes, and preserve the
previous catalog and selected workspace unless a confirmed refreshed catalog was
successfully applied.

### WorkspaceService

`WorkspaceService` is stateless daemon API access:

```dart
abstract class WorkspaceService {
  Future<List<WorkspaceSummary>> listWorkspaces();
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  });
}
```

It should not cache, select, notify, or know UI routes.

### ConversationRepository

`ConversationRepository` is the authority for conversation summaries, run-like
session projection inputs, and conversation event access for one connected
daemon session.

Responsibilities:

- Cache current conversation summaries.
- Expose refresh and loading/error state.
- Provide send, answer, approval, cancel, and event fetch/subscribe operations
  already used by the workbench.
- Notify subscribers after summary or active conversation metadata changes.

The repository may still delegate WebSocket subscription details to the existing
notification client. The UI must not own daemon event transport.

### AdapterRepository

`AdapterRepository` is the authority for CLI adapter availability and model
options.

Responsibilities:

- Cache adapter status and model options.
- Refresh adapter status.
- Notify Workbench and related UI when adapter data changes.

### CodingPreferencesRepository

Settings values that are shown in multiple places should move behind a
repository-style owner rather than staying inside `MainTabsViewModel`.

Responsibilities:

- Load and save permission mode.
- Load and save stream output preference.
- Load and save expand-thinking preference.
- Notify subscribers after preference changes.

`CodingPreferencesRepository` replaces the existing `CodingPreferencesStore`
as the runtime state owner. During migration it may temporarily delegate file or
SharedPreferences reads and writes to the old store implementation, but that
delegation is an implementation adapter, not a retained Store layer. The old
store type should be deleted or made private after all callers use the
repository.

## Feature ViewModels

### MainTabsShellViewModel

`MainTabsViewModel` should be renamed or reduced to `MainTabsShellViewModel`.
It owns shell state only:

- active tab index;
- active overlay route;
- system back behavior decisions;
- bottom-nav visibility inputs that are purely shell state.

It must not expose `AppSnapshot data` or own workspace, conversation, run,
adapter, or settings business data.

If the shell needs feature state, it reads feature ViewModel projections without
copying the feature's business state into the shell. Workbench should expose a
narrow shell projection:

```dart
class WorkbenchShellProjection {
  const WorkbenchShellProjection({
    required this.isInConversation,
    required this.sessionListOpen,
    required this.hasPendingTask,
  });

  final bool isInConversation;
  final bool sessionListOpen;
  final bool hasPendingTask;
}
```

The shell may use this projection for bottom-navigation visibility and badges.
It must not ask Workbench for workspace lists, conversations, events, or other
business data.

### WorkbenchViewModel

`WorkbenchViewModel` owns workbench UI state:

- route state: workspace list, creating workspace, workspace sessions, or
  conversation detail;
- active conversation id and run id;
- prompt text state that is not already owned by a controller;
- draft attachment state;
- sending/busy/error state;
- event trace state;
- model picker selection state;
- voice input coordination state if it remains part of the workbench feature.

It subscribes to:

- `WorkspaceRepository`;
- `ConversationRepository`;
- `AdapterRepository`;
- repositories or use cases needed for diagnostics, attachments, and ASR.

Every ViewModel that subscribes to a Repository must remove that listener in
`dispose`. This is part of the ViewModel contract, not an implementation
detail:

```dart
class WorkbenchViewModel extends ChangeNotifier {
  WorkbenchViewModel({required WorkspaceRepository workspaceRepository})
      : _workspaceRepository = workspaceRepository {
    _workspaceRepository.addListener(_onWorkspaceChanged);
  }

  final WorkspaceRepository _workspaceRepository;

  void _onWorkspaceChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _workspaceRepository.removeListener(_onWorkspaceChanged);
    super.dispose();
  }
}
```

It must not hold a long-lived copy of `List<WorkspaceSummary>`. It exposes:

```dart
List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
WorkspaceSummary? get selectedWorkspace =>
    _workspaceRepository.selectedWorkspace;
```

It also exposes public commands used by the workbench view and tests:

- `createWorkspaceAndOpen({required String path, String? name})` calls
  `WorkspaceRepository.create`, then routes to
  `WorkspaceSessionsRouteState(created.id)` after the repository has refreshed
  and selected the created workspace. If creation fails, it catches the
  repository error, preserves the previous route/catalog projection, and exposes
  a workbench UI error.
- `openWorkspaceSessions(String workspaceId)` calls
  `WorkspaceRepository.select(workspaceId)`. On `true`, it routes to
  `WorkspaceSessionsRouteState(workspaceId)` and triggers any needed
  workspace-scoped follow-up owned by the ViewModel or a use case. On `false`,
  it routes back to `WorkspaceListRouteState` and exposes an error instead of
  leaving the UI on a stale workspace id.
- Workbench-only commands such as opening a conversation, returning to the
  workspace list, retrying a load, and clearing transient operation errors
  should live on `WorkbenchViewModel`; they must not be pushed into
  `MainTabsShellViewModel`.

Its route state stores ids, not entity lists:

```dart
sealed class WorkbenchRouteState {
  const WorkbenchRouteState();
}

final class WorkspaceListRouteState extends WorkbenchRouteState {
  const WorkspaceListRouteState();
}

final class CreatingWorkspaceRouteState extends WorkbenchRouteState {
  const CreatingWorkspaceRouteState({required this.requestLabel});
  final String requestLabel;
}

final class WorkspaceSessionsRouteState extends WorkbenchRouteState {
  const WorkspaceSessionsRouteState({required this.workspaceId});
  final String workspaceId;
}

final class ConversationRouteState extends WorkbenchRouteState {
  const ConversationRouteState({
    required this.workspaceId,
    required this.conversationId,
  });

  final String workspaceId;
  final String conversationId;
}
```

When a workspace id is stale, the ViewModel should resolve it against
`WorkspaceRepository.workspaces` and fall back to the workspace list route or
the selected workspace. It must not invent a workspace.

### SettingsViewModel

`SettingsViewModel` owns settings UI state:

- permission mode;
- stream output;
- expand thinking;
- current app-update state;
- settings-page errors and busy state.

It subscribes to `WorkspaceRepository` for current workspace display and to
`CodingPreferencesRepository` for coding preferences. `SettingsPage` must not
receive `AppSnapshot`.

### HomeViewModel

`HomeViewModel` owns home-page UI projection:

- selected workspace summary;
- workspace list count or current workspace display;
- recent conversation/run projection;
- command deck or shortcut data already shown on Home.

It subscribes to the repositories that own those facts. `HomePage` must not
receive `AppSnapshot`.

## Use Cases

Use cases should remain focused on ordered or cross-repository side effects.
The base workspace creation flow does not need a use case because
`WorkspaceRepository.create` already owns the complete data sequence:

```text
WorkspaceRepository.create(path, name)
  -> WorkspaceService.createWorkspace()
  -> WorkspaceService.listWorkspaces()
  -> update workspace cache
  -> select created workspace
  -> notify listeners
```

`WorkbenchViewModel` may call `WorkspaceRepository.create` directly and then
switch its route to `WorkspaceSessionsRouteState(created.id)`.

Introduce a `CreateWorkspaceUseCase` only if the workflow grows beyond the
workspace repository boundary, for example if creation must also initialize
conversation summaries, run queues, diagnostics, analytics, or another
repository in a single ordered workflow. Until then, adding a use case would be
an unnecessary pass-through layer.

### Workspace Detail Loading

Workspace detail data such as overview, git status, file tree, diagnostics,
runs, and conversations should not be loaded as one all-or-nothing
`AppSnapshot`. Each repository should own its own refresh path. A feature
ViewModel can coordinate multiple repositories when a page needs a composite
view.

If a composite detail use case is retained temporarily, it must return a
feature-specific projection and must not become the new runtime state owner.

## Composition Root

`AppDependencies` remains the composition root and should create grouped
dependencies. The connected session should produce one set of shared repository
instances per daemon connection.

Target connected graph:

```text
ConnectedDataDependencies
  workspaceRepository
  conversationRepository
  adapterRepository
  runRepository
  diagnosticsRepository
  appUpdateRepository
  codingPreferencesRepository

ConnectedFeatureDependencies
  mainTabsShellViewModel
  homeViewModel
  workbenchViewModel
  settingsViewModel
  appUpdateViewModel
```

Names may follow existing local conventions, but ownership must follow this
graph. The same `WorkspaceRepository` instance must be injected into Home,
Settings, and Workbench ViewModels.

`AppUpdateViewModel` depends on `AppUpdateRepository` through the connected data
graph. It must not call app-update services directly from UI composition code.
If the current implementation still constructs an app-update client inside a
feature factory, this migration should move that construction behind
`AppUpdateRepository` before the connected graph is considered complete.

`MainTabsPage` should receive the connected feature graph or a dependency object
that already contains feature ViewModels. It should not assemble `AppSnapshot`
and distribute it as page data.

## AppSnapshot Decommissioning

`AppSnapshot` may remain temporarily as a bootstrap or compatibility DTO, but it
must not be a runtime business state source after this migration.

Allowed uses after migration:

- adapt old tests while they are being updated;
- hydrate repositories during connection bootstrap;
- compatibility helper for code that has not yet been removed in the same
  migration branch.

Disallowed runtime uses after migration:

- `MainTabsViewModel.data`;
- passing `AppSnapshot` into Home, Settings, or Workbench as the source of
  truth;
- calling `WorkbenchViewModel.updateFromSnapshot` from
  `CodingWorkbenchPage.didUpdateWidget`;
- using `AppSnapshot.workspace` to imply a connected app always has a selected
  workspace.

The existing `2026-05-17-mobile-app-view-model-workspace-state-design.md`
AppViewModel direction is superseded for runtime ownership. Its valid insight
remains that an empty workspace list is valid connected data, but the owner of
that data is now `WorkspaceRepository`, not an app-level state container.

## Key Data Flows

### Connection Startup

```text
Connection UI
  -> DaemonConnectionViewModel
    -> DaemonConnectionWorkflow
      -> DaemonClient and auth/session setup
      -> AppDependencies creates connected repositories
      -> WorkspaceRepository.load()
      -> AdapterRepository.load()
      -> ConversationRepository.refresh()
      -> Feature ViewModels are created with shared repositories
      -> MainTabsPage renders connected shell
```

Empty workspace lists are valid. `WorkspaceRepository.workspaces` may be empty,
and feature ViewModels must render empty states instead of throwing.

### Workspace Creation From Workbench

```text
WorkbenchPage add workspace
  -> WorkbenchViewModel.createWorkspaceAndOpen()
    -> WorkspaceRepository.create()
      -> WorkspaceService.createWorkspace()
      -> WorkspaceService.listWorkspaces()
      -> cache update and select created workspace
      -> notify listeners
    -> Workbench route becomes WorkspaceSessionsRouteState(created.id)
```

Home and Settings update from the same repository notification. MainTabs does
not participate in workspace data mutation.

### Workspace Selection

Selecting a workspace changes only the workspace catalog repository's selected
workspace id and broadcasts that change:

```text
WorkbenchViewModel.openWorkspaceSessions(workspaceId)
  -> WorkspaceRepository.select(workspaceId)
    -> if id exists: update selectedWorkspaceId, notify listeners, return true
    -> if id is unknown: return false
  -> if true: WorkbenchViewModel route = WorkspaceSessionsRouteState(workspaceId)
  -> if false: WorkbenchViewModel route = WorkspaceListRouteState with an error
```

`WorkspaceRepository.select` must not call `ConversationRepository`,
`RunRepository`, or other repositories. Cross-repository follow-up belongs in
the interested ViewModel or a use case. For workbench, the ViewModel reacts to
the selected workspace and triggers any needed workspace-scoped conversation or
run refresh:

```text
WorkspaceRepository notifies selected workspace changed
  -> WorkbenchViewModel listener runs
  -> WorkbenchViewModel asks ConversationRepository/RunRepository to refresh
     data for the selected workspace when the current route needs it
  -> WorkbenchViewModel ignores stale responses if selection changes again
```

Home and Settings may simply re-project the selected workspace without loading
workspace-scoped conversation data.

### Tab Switching

```text
MainTabsShellViewModel.selectTab(settings)
MainTabsShellViewModel.selectTab(workbench)
```

Tab switching changes only shell state. It must not refresh from an old
snapshot, rebuild repository caches from stale data, or overwrite feature
ViewModel route state.

### Settings Preference Change

```text
SettingsPage
  -> SettingsViewModel.setPermissionMode(value)
    -> CodingPreferencesRepository.savePermissionMode(value)
      -> local persistence
      -> cache update
      -> notify listeners
```

Workbench reads the same preference repository or receives preference changes
through its ViewModel subscription. The shell is not the preference owner.

## Error Handling

Repositories should expose technical operation state in a structured way:

- loading or refreshing flag;
- operation-specific error object or typed failure;
- current cached data, if still valid.

ViewModels map those facts to UI state:

- inline error;
- dialog intent;
- route fallback;
- retry action.

Workspace creation failures should not clear a previously valid workspace
catalog. A failed refresh after create should surface a clear error and leave
the previous catalog intact unless the daemon returned a confirmed new catalog.

Stale async responses must be ignored when they target an outdated workspace,
conversation, or generation. This applies especially to workbench conversation
events and workspace detail projections. The preferred implementation is a
ViewModel-owned generation counter or target id check:

```dart
int _loadGeneration = 0;

Future<void> loadConversation(String conversationId) async {
  final generation = ++_loadGeneration;
  final result = await _conversationRepository.fetch(conversationId);
  if (generation != _loadGeneration ||
      conversationId != _activeConversationId) {
    return;
  }
  _applyConversation(result);
  notifyListeners();
}
```

Repository caches should also avoid applying stale mutation results when they
support overlapping requests. ViewModels remain responsible for ignoring stale
UI projections because they own route and active-id state.

## Migration Plan

This is a single architecture migration with multiple reviewable slices. The
branch is not complete until all slices land and the old runtime snapshot path
is removed.

### Slice 1: Repository-Owned Workspace Catalog

- Introduce or refactor a concrete listenable `WorkspaceRepository`.
- Move workspace cache, selected workspace, load, refresh, create, and select
  into the repository.
- Keep the domain repository contract pure if retained.
- Add unit tests for empty list, create refresh, selected workspace fallback,
  and listener notifications.

### Slice 2: Connected Composition Graph

- Build one connected repository set per daemon connection.
- Inject the same `WorkspaceRepository` instance into Home, Settings, and
  Workbench ViewModels.
- Add `CodingPreferencesRepository` if needed to remove settings state from
  MainTabs.
- Keep app dependency groups readable; do not create a UI-owned service
  locator.
- This slice may keep Home and Settings on temporary compatibility inputs until
  Slices 5 and 6 introduce their final ViewModels. Those compatibility inputs
  must be built directly in `MainTabsPage` or app-layer feature factories from
  the connected repositories or bootstrap DTO adapters. They must not be stored
  on `MainTabsViewModel`, and they must not reintroduce
  `MainTabsViewModel.data`. The compatibility path must be removed before this
  migration is complete.

### Slice 3: Shell-Only Main Tabs

- Rename or reduce `MainTabsViewModel` to shell-only responsibilities.
- Remove `AppSnapshot data` from `MainTabsViewModel`.
- Move settings preferences and adapter loading out of the shell and into
  feature/repository owners.
- Update `MainTabsPage` to compose feature ViewModels instead of distributing a
  runtime snapshot.
- Until Slices 5 and 6 land, any legacy Home or Settings constructor that still
  needs snapshot-shaped data receives a temporary projection from
  `MainTabsPage` or an app-layer factory. This is a direct view compatibility
  adapter, not shell ViewModel state, and it must be deleted with the final Home
  and Settings ViewModel migration.

### Slice 4: Workbench Runtime State

- Inject repositories and only necessary non-pass-through use cases into
  `WorkbenchViewModel`.
- Remove workspace list fields from `WorkbenchRouteState`.
- Remove `WorkbenchViewModel.updateFromSnapshot`.
- Remove `CodingWorkbenchPage.didUpdateWidget` snapshot overwrite behavior.
- Make workspace list, route workspace, and selected workspace resolve from
  `WorkspaceRepository`.
- Keep widget-owned UI controllers such as scroll and text controllers in the
  view where appropriate.

### Slice 5: Settings Runtime State

- Add or complete `SettingsViewModel`.
- Make `SettingsPage` render from `SettingsViewModel`.
- Remove `SettingsPage(data: AppSnapshot)`.
- Move permission mode, stream output, and expand thinking into
  `CodingPreferencesRepository` plus `SettingsViewModel` projection.

### Slice 6: Home Runtime State

- Add or complete `HomeViewModel`.
- Make `HomePage` render from `HomeViewModel`.
- Remove `HomePage(data: AppSnapshot)`.
- Use repositories for workspace and conversation/run projections.

### Slice 7: Bootstrap Compatibility Cleanup

- Keep bootstrap DTOs only long enough to hydrate repositories.
- Remove runtime `AppSnapshot` propagation through MainTabs, Home, Settings,
  and Workbench.
- Update tests and debug helpers away from `AppSnapshot` where possible.
- Keep compatibility adapters only if a focused test migration needs them in
  the same branch.

### Slice 8: Regression and Architecture Checks

- Add the workspace tab-switch regression test.
- Add repository and ViewModel unit tests for the new ownership rules.
- Run architecture import checks.
- Update architecture checker only if new repository placement requires an
  explicit rule adjustment.

## Testing Strategy

Required unit tests:

- `WorkspaceRepository.load` accepts an empty workspace list and notifies.
- `WorkspaceRepository.create` calls create, refreshes the catalog, selects the
  created workspace, and notifies subscribers.
- `WorkspaceRepository.select` returns `false` for unknown ids, returns `true`
  for accepted ids, and notifies on valid changes.
- `WorkbenchViewModel.createWorkspaceAndOpen` routes to sessions using the
  created workspace id and does not copy the workspace list.
- `WorkbenchViewModel.openWorkspaceSessions` falls back to the workspace list
  route when `WorkspaceRepository.select` returns `false`.
- `MainTabsShellViewModel.selectTab` changes only shell state.
- `SettingsViewModel` reflects workspace repository changes without receiving
  `AppSnapshot`.
- `HomeViewModel` reflects workspace repository changes without receiving
  `AppSnapshot`.

Required widget regression:

```text
Given the connected shell is showing workbench with one workspace
When the user creates a second workspace from the workbench
And the workbench opens that workspace's sessions
And the user switches to Settings
And the user switches back to Workbench
Then the second workspace is still present
And the workbench route still resolves the second workspace
```

Required validation commands:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze
flutter test --no-pub test\main_tabs_view_model_test.dart -r expanded
flutter test --no-pub test\coding_workbench_controller_test.dart -r expanded
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "workspace"
```

If a first Flutter/Dart attempt times out in the local agent environment, stop
automatic retries and report the exact mirror-configured command for manual
execution.

## Acceptance Criteria

- Runtime `MainTabsViewModel.data` no longer exists.
- `MainTabsViewModel` is shell-only or replaced by `MainTabsShellViewModel`.
- Home, Settings, and Workbench do not receive `AppSnapshot` as their runtime
  business data source.
- `AppSnapshot` is not used to overwrite feature ViewModel state after
  connection bootstrap.
- `CodingWorkbenchPage.didUpdateWidget` no longer calls
  `WorkbenchViewModel.updateFromSnapshot`.
- `WorkbenchViewModel.updateFromSnapshot` is removed or no longer part of the
  runtime path.
- `WorkbenchRouteState` does not carry `List<WorkspaceSummary>`.
- One connection-scoped `WorkspaceRepository` instance is shared by Home,
  Settings, and Workbench ViewModels.
- No separate `WorkspaceStore` or generic Store layer is introduced.
- Workspace creation from the workbench remains visible after switching to
  Settings and back.
- Empty workspace lists remain valid connected data.
- Domain layer remains free of Flutter imports.
- Architecture import check passes.
- Focused repository, ViewModel, and widget regression tests pass.

## Risks

- This migration touches central constructors and tests. Keep slices small and
  verify after each slice.
- `AppSnapshot` appears in tests and debug helpers. Test migration should avoid
  weakening coverage by replacing realistic setup with empty placeholders.
- `CodingWorkbenchPage` is large. Do not mix this state-ownership migration
  with visual refactors.
- Repository `ChangeNotifier` placement must not leak Flutter imports into
  `domain/`.
- Conversation event subscriptions have lifecycle edge cases. Preserve existing
  notification-client tests and avoid changing transport semantics unless a
  slice explicitly requires it.

## Out Of Scope Follow-Up

- Splitting `DaemonClient` into focused API clients can continue later.
- Moving every feature page into `views/` folders is not required here.
- Replacing `ChangeNotifier` with another state-management approach is not part
  of this design.
- Full protocol/domain model separation remains a separate architecture effort.
