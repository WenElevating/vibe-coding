# Connected Session Data Architecture Design

- Date: 2026-05-29
- Status: design approved, pending written-spec review
- Scope: Flutter mobile connected-session data ownership, bootstrap hydration,
  adapter probing, workspace switching, and repository-backed feature state.

## Context

The mobile app has been moving away from runtime `AppSnapshot` ownership toward
repository-owned state. Recent review feedback exposed that the migration is
not yet coherent at the connected-session boundary:

- `DaemonInitialData.adapters` is empty after bootstrap, while the CLI adapter
  probe now updates only the connected adapter repository. Settings -> adapters
  can therefore render an empty list even after the adapter probe succeeds.
- The Coding tab's retry path calls the adapter repository's broad `load`,
  which also loads shortcuts, command templates, and extensions. A failure in an
  ancillary endpoint can keep Coding blocked as if adapter probing failed.
- Workspace bootstrap already fetched runs, conversations, and queue, but the
  repository-backed Home path immediately refreshes again because the connected
  repositories are not the bootstrap recipient.

The tempting tactical fix is to let `MainTabsPage` seed several cached
repositories after receiving `DaemonInitialData`. That would solve the immediate
symptoms, but it puts orchestration and data synchronization back in the UI
layer and weakens the architecture migration.

Flutter's recommended architecture separates UI, optional logic/use-case, data,
and service layers. ViewModels consume repositories. Repositories are the data
layer source of truth for their resource and own caching, refresh, retry, and
error state. Use cases are justified when a workflow coordinates multiple
repositories or ordered side effects. This design applies those rules to the
connected daemon session.

References:

- Flutter architecture recommendations:
  <https://docs.flutter.dev/app-architecture/recommendations>
- Flutter architecture guide:
  <https://docs.flutter.dev/app-architecture/guide>
- Flutter data-layer case study:
  <https://docs.flutter.dev/app-architecture/case-study/data-layer>
- Flutter common architecture concepts:
  <https://docs.flutter.dev/app-architecture/concepts>
- Project layered architecture guidance:
  `docs/superpowers/specs/2026-05-12-flutter-standard-layered-architecture-design.md`
- Prior repository-owned state direction:
  `docs/superpowers/specs/2026-05-28-mobile-repository-owned-state-architecture-design.md`

## Decision

Adopt a connected-session architecture with:

- one connected session scope per daemon connection;
- per-resource repositories as the runtime data authorities;
- session/workspace use cases for bootstrap and cross-repository workflows;
- feature ViewModels that consume repositories and expose immutable UI state;
- a composition root that wires dependencies but does not own runtime data.

Do not introduce a single god `ConnectedSessionRepository` that owns every data
type. The best-practice version of the "session repository" idea is a
connected-session module: scoped repositories plus use cases that coordinate
them.

`AppDependencies` may remain as the manual composition root, but its role must
be limited to construction and wiring. If the name continues to imply runtime
state ownership, it can later be renamed to `AppComposition`. That rename is not
required for this migration.

## Goals

- Make the connected session the boundary for repository lifetimes.
- Keep each repository responsible for one resource family.
- Keep UI pages out of bootstrap hydration and cross-repository synchronization.
- Treat `DaemonInitialData` as a bootstrap payload, not as a runtime source of
  truth.
- Make Home, Settings, Workbench, and route overlays consume repository-backed
  ViewModels.
- Split adapter probe state from command catalog/extension state.
- Avoid duplicate startup fetches when bootstrap data already contains the
  required resource lists.
- Preserve current user-visible behavior except where the architecture makes
  stale/empty/loading/error states explicit.

## Non-Goals

- Do not redesign UI visuals.
- Do not rewrite daemon HTTP APIs.
- Do not introduce Provider, Riverpod, Bloc, GetIt, or another dependency
  package in this pass.
- Do not migrate every protocol DTO into new domain models.
- Do not make `AppDependencies` a runtime state container.
- Do not keep `MainTabsPage` as a data synchronization owner.

## Layer Responsibilities

Target flow:

```text
View
  -> ViewModel
    -> UseCase, only for ordered or cross-repository workflows
      -> Repository, the source of truth for one resource family
        -> Service, stateless daemon/platform access
          -> DaemonClient or platform API
```

### UI Layer

Views render state and forward user intent to ViewModels. They may own UI-only
controllers such as scroll controllers, focus nodes, and text editing
controllers.

ViewModels own feature UI state and commands. They receive repositories and use
cases through constructors, subscribe to listenable repositories, and expose
read-only state snapshots or getters. They do not fetch directly from
`DaemonClient` and do not receive `DaemonInitialData` as long-lived runtime
state.

### Domain / Workflow Layer

Use cases coordinate workflows that cross repository boundaries or require an
ordered side-effect sequence. They hold no widget state and do not render. They
may update several repositories as part of one user intent.

Use cases needed by this design:

- `ConnectSessionUseCase`: connect to a daemon, pair/authenticate, load initial
  data, and return the daemon client, connected config, and bootstrap payload to
  the composition root.
- `OpenWorkspaceUseCase`: load workspace bootstrap for a selected workspace and
  update the repositories that depend on selected workspace data.
- `ProbeCliAdaptersUseCase`, or an equivalent repository command, for adapter
  availability probing without loading unrelated command catalog resources.

### Data Layer

Repositories are per-resource authorities. They can cache data, expose
operation state, notify listeners, ignore stale responses, and translate raw
service responses into app models.

Services are stateless wrappers around daemon or platform APIs. They do not
cache and do not notify.

## Connected Session Scope

A connected session scope is created once for each daemon connection. It owns
the lifetime of all repositories and use cases that depend on that daemon
client.

Target shape:

```text
ConnectedSessionScope
  repositories
    workspaceRepository
    conversationRepository
    runRepository
    queueRepository
    cliAdapterRepository
    commandCatalogRepository
    diagnosticsRepository
    appUpdateRepository
    codingPreferencesRepository
  useCases
    openWorkspace
    probeCliAdapters
```

The scope is not a store. It is an ownership and wiring boundary. Runtime data
lives in the repositories.

The scope must not contain feature factories or ViewModel factories. ViewModels
belong to the UI layer. The composition root receives the scope and constructs
feature ViewModels from its repositories and use cases:

```text
AppDependencies or AppComposition
  createConnectedFeatures(scope)
    -> HomeViewModel(scope.repositories.workspaceRepository, ...)
    -> WorkbenchViewModel(scope.repositories.workspaceRepository, ...)
    -> SettingsViewModel(...)
    -> AdaptersViewModel(...)
```

After scope creation, UI code receives ViewModels or narrow UI-layer factories,
not raw repositories plus bootstrap DTOs to synchronize manually.

## Repository Boundaries

### WorkspaceRepository

Owns:

- workspace catalog;
- selected workspace id;
- loading/error state for workspace catalog operations.

Commands:

- `load`;
- `refresh`;
- `create`;
- `select`;
- `replaceFromBootstrap`, if needed internally by session use cases.

`replaceFromBootstrap` is not a UI API. Dart cannot make this method
package-private or visible only to a friend class. The internal-only constraint
must therefore be enforced by architecture conventions, code review, and import
checks rather than language-level visibility. UI files must not call repository
bootstrap replacement methods directly.

### ConversationRepository

Owns:

- conversation summaries for the active connected session/workspace context;
- conversation mutation updates;
- conversation event fetch/watch delegation.

It must not be hydrated by `MainTabsPage`. Initial summaries come from
connection/workspace use cases.

### RunRepository

Owns:

- run summaries;
- run mutations and approvals;
- run-event fetch delegation.

Queue data should be split from run data unless a deeper inspection proves the
daemon API and UI semantics require them to remain coupled. The current
`CachedRunRepository` mixing `runs` and `queue` is a migration convenience, not
the desired boundary.

### QueueRepository

Owns:

- queue items;
- loading/error state for queue refresh;
- refresh after queue-affecting run operations when needed.

If queue splitting is too large for the first implementation slice, the spec
allows a temporary compatibility phase where `RunRepository` still exposes
queue. That compatibility must be named and removed in the cleanup slice.

### CliAdapterRepository

Owns:

- CLI adapter availability;
- model/options attached to adapter status;
- adapter-probe loading and error state.

Coding gate depends only on this repository's adapter probe state.

### CommandCatalogRepository

Owns:

- shortcuts;
- command templates;
- extensions or extension summaries, unless extensions later justify a separate
  repository.

Command catalog failures must not block Coding as "adapter unavailable".

## Bootstrap And Workspace Data Flow

### Connection Startup

Target flow:

```text
Connection UI
  -> DaemonConnectionViewModel
    -> ConnectSessionUseCase
      -> DaemonClient/auth/pairing services
      -> load DaemonInitialData
      -> return DaemonClient + DaemonInitialData + connected config
  -> AppDependencies or AppComposition
    -> create ConnectedSessionScope from client + bootstrap payload
    -> hydrate repositories from bootstrap payload
    -> create connected feature ViewModels
  -> Connected tabs render from feature ViewModels
```

`DaemonInitialData` stops at the session boundary. It may appear in tests and
bootstrap adapters, but Home, Settings, Workbench, and route overlays must not
use it as runtime business data.

Bootstrap hydration follows this rule:

- if the bootstrap payload contains a resource, hydrate the corresponding
  repository without fetching that resource again;
- if the bootstrap payload omits a resource, leave that repository in its
  initial not-loaded state and let the ViewModel or use case that first needs
  the resource trigger the fetch;
- if the data model cannot distinguish "absent" from "present but empty", the
  model must be changed before optional bootstrap resources are introduced.

For the current required list fields, an empty list means "present and empty",
not "unknown".

### Workspace Open

Target flow:

```text
User opens workspace
  -> WorkbenchViewModel command
    -> OpenWorkspaceUseCase
      -> workspace bootstrap service
      -> WorkspaceRepository.select or replace selected workspace
      -> ConversationRepository replace summaries
      -> RunRepository replace runs
      -> QueueRepository replace queue
      -> repositories notify their listeners
  -> feature ViewModels re-project from repositories
```

The UI command triggers the use case, not direct repository hydration. The
chosen consistency policy is explicit loading during workspace transition, not
silent repository notification batching. The ViewModel that invokes
`OpenWorkspaceUseCase` sets a workspace-opening/loading state before awaiting
the use case. Repositories may notify independently as their resource data is
replaced, but ViewModels must not render composite "settled" content until all
required resource repositories match the selected workspace id or generation.

Workspace-scoped repositories should expose enough metadata for this check,
such as `loadedWorkspaceId` or a generation token. When the selected workspace
has changed but conversations, runs, or queue still belong to the previous
workspace, ViewModels render loading or an empty transition state rather than
showing stale data.

This metadata is required on `ConversationRepository`, `RunRepository`, and
`QueueRepository`. `WorkspaceRepository` does not need `loadedWorkspaceId`
because it owns the selected workspace. `CliAdapterRepository` and
`CommandCatalogRepository` do not need it unless the daemon later makes those
resources workspace-scoped.

If workspace selection is initiated from a shell overlay, the shell's role is
only to close the overlay and emit an `onWorkspaceSelected(workspaceId)`
callback/event. `WorkbenchViewModel` or a dedicated UI coordinator owns the call
to `OpenWorkspaceUseCase`; `MainTabsShellViewModel` remains shell-only.

### Adapter Probe

Target flow:

```text
Connected session starts
  -> ProbeCliAdaptersUseCase or CliAdapterRepository.probe()
    -> adapter service listAdapters()
    -> CliAdapterRepository updates adapter state
Coding tab
  -> observes CliAdapterRepository.probeState
  -> Retry calls only adapter probe
```

Shortcuts, templates, and extensions load through `CommandCatalogRepository`.
Those resources can show their own loading/error states without blocking the
Coding page.

## Feature ViewModels

### MainTabsShellViewModel

Owns only shell UI state:

- selected tab;
- overlay route;
- back behavior;
- bottom-navigation visibility inputs.

It must not own `DaemonInitialData`, `AppSnapshot`, workspace lists,
conversation summaries, runs, queue, adapters, shortcuts, templates, or
extensions.

### HomeViewModel

Consumes:

- `WorkspaceRepository`;
- `ConversationRepository`;
- `RunRepository`;
- `QueueRepository`.

It projects repository data into the home command deck. It does not call
startup refresh just to compensate for missing bootstrap hydration.

### WorkbenchViewModel

Consumes:

- `WorkspaceRepository`;
- `ConversationRepository`;
- `RunRepository`;
- `QueueRepository`;
- `CliAdapterRepository`;
- command/workflow use cases needed by workbench.

It owns workbench route and interaction state, but shared business data comes
from repositories.

### SettingsViewModel

Consumes:

- `WorkspaceRepository`;
- `CodingPreferencesRepository`;
- `CommandCatalogRepository` for extension counts/status if shown;
- app update repository/use case as needed.

Settings must not receive `AppSnapshot`.

### AdaptersViewModel

Consumes:

- `CliAdapterRepository`;
- `CommandCatalogRepository`, only for extensions if the page continues to show
  them.

Settings -> adapters must render the repository state, not
`DaemonInitialData.adapters`.

Adapters are modeled as a separate ViewModel instead of being folded into
`SettingsViewModel` because Settings -> adapters is a routed subpage with its
own resource dependencies, loading/error state, and retry behavior. Settings can
link to it, but should not own its adapter/catalog projection.

## Composition Root

The composition root creates app-wide and connected-session dependencies. It may
continue to live in `mobile/lib/src/app/app_dependencies.dart` while this design
is implemented.

Rules:

- app-wide dependencies may outlive a daemon connection;
- connected-session dependencies are recreated for each daemon client;
- the composition root builds repositories, services, use cases, and
  ViewModels;
- it does not hold mutable runtime data itself;
- it does not expose a service locator to arbitrary widgets.

If the current `AppDependencies` type obscures those rules, a follow-up rename
to `AppComposition` is acceptable but not required for the fix.

## Migration Strategy

### Slice 1: Define Connected Session Scope

- Introduce a connected-session scope/factory in the app layer.
- Keep it as a construction boundary, not a state store.
- Move per-session repository ownership out of ad hoc page setup.
- Update tests that construct `MainTabsDependencies`.

### Slice 2: Split Adapter And Command Catalog State

- Extract adapter probe state into `CliAdapterRepository`.
- Move shortcuts/templates/extensions into `CommandCatalogRepository` or an
  explicitly named compatibility catalog path.
- Update Coding gate retry to call only the adapter probe command.
- Add regression coverage for "adapter succeeds, extension/template fails".

### Slice 3: Bootstrap Through Use Cases

- Route connection bootstrap through `ConnectSessionUseCase`.
- Route workspace switching through `OpenWorkspaceUseCase`.
- Hydrate repositories through use cases and the composition root, not in
  `MainTabsPage`.
- Remove the immediate Home refresh used only to compensate for empty
  repository caches.

### Slice 4: Repository-Backed Feature ViewModels

- Update `HomeViewModel`, `AdaptersViewModel`, and relevant settings/workbench
  paths to consume the new repositories.
- Remove `DaemonInitialData` and `AppSnapshot` runtime business data from those
  paths.
- Keep compatibility adapters only inside tests or short-lived migration code.

### Slice 5: Cleanup Runtime Snapshot Paths

- Remove remaining runtime `toAppSnapshot()` usage from connected UI paths.
- Keep `DaemonInitialData` only at bootstrap and test boundaries.
- Remove broad cached repository error states that combine unrelated resources.
- Remove `RunRepository` queue compatibility if the queue split was deferred in
  an earlier slice.

## Testing Strategy

Repository/unit tests:

- `CliAdapterRepository` adapter probe success/failure updates only adapter
  probe state.
- `CommandCatalogRepository` failures do not change adapter probe state.
- `ConnectSessionUseCase` completes auth/bootstrap and returns
  `DaemonInitialData` without hydrating repositories directly.
- `AppDependencies` or `AppComposition` hydrates workspace, conversations, runs,
  queue, and adapter repositories from the bootstrap payload before ViewModels
  read them.
- `OpenWorkspaceUseCase` replaces selected workspace data without making UI
  pages manually seed repositories.

ViewModel tests:

- `AdaptersViewModel` renders adapters from `CliAdapterRepository` when
  bootstrap adapters are empty.
- `HomeViewModel` renders bootstrap runs/conversations/queue from repositories
  without forcing an immediate refresh.
- Coding gate retry calls only adapter probe.

Widget regression tests:

- Settings -> adapters shows loaded adapters after bootstrap/probe.
- Coding tab is not blocked when adapters loaded but catalog/extension loading
  fails.
- Connected startup does not re-fetch workspace bootstrap lists before Home can
  render repository data.

Validation commands:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze
flutter test --no-pub test\main_route_overlay_test.dart -r expanded
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "adapter"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "bootstrap"
```

If a first Flutter/Dart attempt times out in the agent environment, stop
automatic retries and report the exact mirror-configured command for manual
execution.

## Acceptance Criteria

- Connected UI runtime data comes from repositories, not `DaemonInitialData` or
  `AppSnapshot`.
- `MainTabsPage` does not hydrate individual resource repositories.
- `MainTabsShellViewModel` remains shell-only.
- Adapter availability and command catalog resources have independent loading
  and error state.
- Coding retry only retries adapter probing.
- Settings adapters view reads adapter repository state.
- Home can render bootstrap runs/conversations/queue without an immediate
  duplicate refresh.
- Workspace opening uses a use case/workflow for cross-repository updates.
- The composition root creates dependencies but owns no mutable runtime data.
- Domain remains free of Flutter imports.
- Architecture import checks and focused tests pass.

## Risks

- Splitting queue from runs may touch more call sites than the review fix
  strictly needs. Keep it as a named slice and allow temporary compatibility if
  needed.
- Existing tests rely heavily on `AppSnapshot`; migration should replace those
  setups with repository-backed harnesses without losing behavioral coverage.
- A single connected-session scope can become a service locator if exposed too
  broadly. Widgets should receive ViewModels or narrow factories, not the whole
  scope.
- Use cases should coordinate workflows, not become new state owners.

## Out Of Scope Follow-Up

- Renaming `AppDependencies` to `AppComposition`.
- Replacing `ChangeNotifier` with another state-management library.
- Splitting every daemon endpoint into focused service classes.
- Full protocol/domain model separation.
