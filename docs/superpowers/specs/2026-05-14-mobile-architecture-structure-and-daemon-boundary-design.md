# Mobile Architecture Structure and Daemon Boundary Design

Date: 2026-05-14

## Context

The mobile Flutter app has already moved toward a layered structure:

- `src/app/` creates app dependencies and acts as the composition root.
- `src/domain/` owns repository contracts, use-case contracts, and pure models.
- `src/data/` implements daemon-backed repositories and data models.
- `src/services/` owns infrastructure such as `DaemonClient`, local stores,
  device identity, and ASR adapters.
- `src/workflows/` owns multi-step application flows.
- `src/ui/` owns Flutter pages, feature widgets, ViewModels, and shared UI
  primitives.

The current architecture checker passes and the coding workbench no longer
depends directly on `DaemonClient`. The remaining problem is clarity and
boundary consistency. Some retired directories still exist locally as empty
folders, some feature files are named in a way that obscures their role, and a
few non-workbench UI surfaces still import the concrete daemon client.

This design is for a structure closeout pass. It should make the current app
architecture easier to read and harder to regress without rewriting the
workbench, replacing `ChangeNotifier`, or splitting all protocol models.

## Problem

The architecture is now mostly shaped, but it is not fully obvious from the
tree:

- Empty retired roots such as `src/features/`, `src/state/`, `src/theme/`, and
  `src/widgets/` still exist on disk and make it look like there are two active
  feature roots.
- `ui/features/sessions/session_list_view_model.dart` contains projection
  helpers, while the actual `SessionListViewModel` lives under
  `ui/features/sessions/view_models/`. The naming makes the feature harder to
  scan.
- `ui/features/diagnostics/diagnostics_page.dart` directly imports
  `DaemonClient`.
- `ui/features/run_detail/run_detail_page.dart` directly imports
  `DaemonClient`.
- `ui/main_route_overlay.dart` forwards `DaemonClient` into feature pages.
- `ui/main_tabs_page.dart` still acts as both shell UI and connected dependency
  composition boundary.
- The connection ViewModel/controller still expose the connected client as part
  of the connection lifecycle.
- `tool/check_architecture_imports.dart` reports UI direct daemon-client
  imports, but does not yet enforce a narrow allowlist.

These are not user-facing defects by themselves. They are architecture clarity
defects: a developer can still add new UI code that bypasses repositories, or
look at the wrong feature root and misunderstand where new code belongs.

## Goals

- Make `src/ui/features/` the only visible active UI feature root.
- Remove retired empty source roots that confuse code navigation.
- Rename the sessions projection helper so the actual ViewModel location is
  clear.
- Move diagnostics behavior behind `DiagnosticsRepository` and a
  `DiagnosticsViewModel`.
- Move run-detail behavior behind repository-backed `RunDetailViewModel`
  methods.
- Stop `MainRouteOverlay` from importing or forwarding `DaemonClient`.
- Keep `MainTabsPage` as the temporary connected composition boundary, but stop
  it from passing `DaemonClient` to ordinary feature UI.
- Strengthen the architecture checker so ordinary UI files cannot import
  `services/daemon_client.dart`.
- Preserve current product behavior and visible UI.

## Non-Goals

- Do not split or rewrite `CodingWorkbenchPage`.
- Do not split or rewrite `WorkbenchViewModel`.
- Do not replace `ChangeNotifier`.
- Do not introduce Riverpod, Bloc, GetIt, or another dependency injection
  package.
- Do not split `src/models/protocol.dart` into clean domain models in this pass.
- Do not rename every feature page into a `views/` subdirectory.
- Do not change daemon HTTP APIs.
- Do not redesign UI visuals.
- Do not remove the connection boundary's knowledge that a successful
  connection produces a daemon-backed session.

## Selected Approach

Use a two-stage closeout:

1. Clean up structure and naming so the current architecture is readable.
2. Remove the remaining ordinary UI direct `DaemonClient` paths by adding
   repository-backed ViewModels and tightening the checker.

This approach is recommended because it addresses both sources of confusion:
the file tree and the import boundary. It avoids the larger risk of a full
workbench split or protocol-model migration, while still making the app's
current layered architecture enforceable.

Rejected alternatives:

- Checker-only hardening: this would make the rule stricter while leaving
  confusing directories and direct-client feature pages in place.
- Full clean-architecture model split: this would improve purity but would
  expand the scope into DTO/domain model conversion across most of the mobile
  app.
- Full feature-folder reshuffle: moving every page into `views/` would create
  path churn with little benefit for the current boundary problem.

## Target Structure

The active source roots after this pass should be:

```text
mobile/lib/src/
  app/
  data/
  domain/
  models/
  services/
  shell/
  testing/
  ui/
  workflows/
```

The following retired roots should not exist in the working tree and should not
have tracked files:

```text
mobile/lib/src/features/
mobile/lib/src/state/
mobile/lib/src/theme/
mobile/lib/src/widgets/
```

The active feature UI root remains:

```text
mobile/lib/src/ui/features/
```

Feature-local ViewModels should live under:

```text
mobile/lib/src/ui/features/<feature>/view_models/
```

Feature pages and smaller widgets may remain in the feature root. Existing
`views/` directories may remain, but this pass does not require every feature
to adopt a `views/` folder.

## Sessions Naming

Current state:

```text
ui/features/sessions/session_list_view_model.dart
ui/features/sessions/view_models/session_list_view_model.dart
```

The root-level file contains projection helpers, not a ViewModel. Rename it to:

```text
ui/features/sessions/session_item_projection.dart
```

Keep the real ViewModel at:

```text
ui/features/sessions/view_models/session_list_view_model.dart
```

The resulting feature shape should be:

```text
ui/features/sessions/
  coding_session_list_page.dart
  session_item.dart
  session_item_projection.dart
  sessions.dart
  view_models/
    session_list_view_model.dart
```

Update imports and barrels accordingly. The projection file should continue to
own `mergeSessionItems`, `shouldShowConversationInSessionList`,
`runSummaryFromConversation`, and `runStatusFromConversation`.

## Diagnostics Boundary

Current state:

```text
DiagnosticsPage -> DaemonClient
```

Target state:

```text
DiagnosticsPage
  -> DiagnosticsViewModel
    -> DiagnosticsRepository
      -> DaemonDiagnosticsRepository
        -> DaemonClient
```

Add:

```text
ui/features/diagnostics/view_models/diagnostics_view_model.dart
```

The ViewModel should own:

- loading state
- error state
- last created diagnostic bundle
- `createBundle()` command

`DiagnosticsPage` should receive a ViewModel or a repository-backed dependency
object. The page should render state and call commands; it should not import
`DaemonClient`.

Dependency creation should happen through the existing dependency path. Prefer
adding a feature builder that accepts `ConnectedDataDependencies`:

```text
FeatureDependencies.createDiagnosticsViewModel(ConnectedDataDependencies data)
```

This keeps daemon wiring in app/composition code instead of the feature page.

## Run Detail Boundary

Current state:

```text
RunDetailPage -> DaemonClient
```

Target state:

```text
RunDetailPage
  -> RunDetailViewModel
    -> RunRepository
      -> DaemonRunRepository
        -> DaemonClient
```

Use the existing file:

```text
ui/features/run_detail/view_models/run_detail_view_model.dart
```

Extend it only for operations currently performed by `RunDetailPage`. The
ViewModel should own:

- event loading state
- event list
- last sequence
- error state
- refresh/fetch command
- approval or cancel commands only if the current page already exposes those
  operations

`RunDetailPage` should receive a repository-backed ViewModel or dependency
builder result. It should not import `DaemonClient`.

Dependency creation should use:

```text
FeatureDependencies.createRunDetailViewModel(
  ConnectedDataDependencies data,
  RunSummary run,
)
```

If the existing repository contract is missing a method already needed by the
page, add the narrow method to the relevant domain repository and daemon
repository implementation. Do not create a duplicate client wrapper.

## Main Route Overlay Boundary

Current state:

```text
MainRouteOverlay(client: DaemonClient)
  -> DiagnosticsPage(client: client)
  -> RunDetailPage(client: client)
```

Target state:

```text
MainRouteOverlay(
  route,
  data,
  connectedData,
  featureDependencies,
  onBack,
)
```

`MainRouteOverlay` may choose which page to display. It should not know or
forward the concrete daemon HTTP client.

It should create feature pages through `FeatureDependencies` builders or pass
already-created repository-backed dependencies. The exact implementation may be
kept lightweight, but the import boundary must be:

```text
MainRouteOverlay -> ConnectedDataDependencies / FeatureDependencies
MainRouteOverlay !-> DaemonClient
```

## Connection and Main Tabs Boundary

Connection and the main tabs shell are special boundaries.

Connection:

- The connection flow creates the daemon-backed connected session.
- `DaemonConnectionViewModel` may continue to depend on
  `ConnectToDaemonUseCase<DaemonClient>` in this pass.
- `DaemonConnectionController` may remain a thin testing/compatibility wrapper.
- These files should not construct real config stores or data repositories
  internally unless a test helper explicitly needs a fake.

Main tabs:

- `MainTabsPage` may remain the temporary connected app composition boundary.
- It may hold the active `DaemonClient`.
- It may call `AppDependencies.data.forDaemonClient(client)`.
- It should not pass `DaemonClient` to `MainRouteOverlay`,
  `DiagnosticsPage`, `RunDetailPage`, or other ordinary feature UI.

This means the allowed UI daemon-client boundary after the pass should be at
most:

```text
lib/src/ui/main_tabs_page.dart
lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart
lib/src/ui/features/connection/view_models/daemon_connection_controller.dart
```

## Architecture Checker

Update `mobile/tool/check_architecture_imports.dart` so UI direct
`DaemonClient` imports are no longer just an informational list.

Rules:

- Any `lib/src/ui/` file that imports `services/daemon_client.dart` should fail
  unless it appears in the explicit allowlist.
- The allowlist should contain only the connection boundary and main tabs shell
  files listed above.
- The checker output should distinguish allowed boundary imports from forbidden
  imports.
- Existing rules for domain, services, UI core, testing imports, and retired
  roots remain active.

Desired checker output shape:

```text
Allowed UI DaemonClient boundary imports:
  lib/src/ui/main_tabs_page.dart:...
  lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart:...
  lib/src/ui/features/connection/view_models/daemon_connection_controller.dart:...

Forbidden UI DaemonClient imports:
  none
```

If a new ordinary UI feature imports `DaemonClient`, the checker must exit with
a non-zero code.

## Tests and Validation

Always run:

```text
cd mobile && dart run tool/check_architecture_imports.dart
cd mobile && dart analyze
```

Structure validation:

```text
git ls-files mobile/lib/src/features mobile/lib/src/state mobile/lib/src/theme mobile/lib/src/widgets
rg "src/features|src/widgets|src/theme|src/state" mobile/lib mobile/test -n
```

Diagnostics validation:

```text
flutter test test/diagnostics_view_model_test.dart -r expanded
```

Run detail validation:

```text
flutter test test/run_detail_view_model_test.dart -r expanded
```

Main shell and connection regression:

```text
flutter test test/main_tabs_view_model_test.dart -r expanded
flutter test test/daemon_connection_controller_test.dart -r expanded
```

Widget regression should include the affected surfaces that exist in the test
suite:

```text
flutter test test/widget_test.dart -r expanded --name "diagnostics|run detail|adapter picker|opening coding tab|coding workbench|workspace"
```

If `diagnostics` or `run detail` widget cases do not exist, do not add broad
snapshot tests only for this refactor. Prefer focused ViewModel tests plus
existing shell/widget smoke coverage.

## Implementation Slices

### Slice 1: Structure Closeout

- Delete retired empty roots from the working tree.
- Rename `ui/features/sessions/session_list_view_model.dart` to
  `ui/features/sessions/session_item_projection.dart`.
- Update imports, barrels, and tests.
- Verify analyzer and session/workbench-related tests.

### Slice 2: Diagnostics Repository ViewModel

- Add `DiagnosticsViewModel`.
- Change `DiagnosticsPage` to depend on the ViewModel or repository-backed
  dependencies.
- Add diagnostics ViewModel tests.
- Do not let `DiagnosticsPage` import `DaemonClient`.

### Slice 3: Run Detail Repository ViewModel

- Extend `RunDetailViewModel` for the operations currently handled by
  `RunDetailPage`.
- Change `RunDetailPage` to depend on the ViewModel or repository-backed
  dependencies.
- Add or update run-detail ViewModel tests.
- Do not let `RunDetailPage` import `DaemonClient`.

### Slice 4: Overlay and Checker Hardening

- Change `MainRouteOverlay` to receive connected data and feature dependency
  builders instead of `DaemonClient`.
- Update `MainTabsPage` so it no longer passes the client to overlay.
- Harden the checker with the explicit UI daemon-client allowlist.
- Verify no ordinary UI direct daemon-client imports remain.

### Slice 5: Final Regression Fixes

- Use only if verification exposes small fallout.
- Do not add new architecture scope.
- Do not create an empty commit if there are no fixes.

## Success Criteria

- Retired roots no longer appear as local source directories.
- No tracked files exist under retired roots.
- `sessions` no longer has a root-level file named
  `session_list_view_model.dart` unless it contains the actual ViewModel.
- `DiagnosticsPage` does not import `DaemonClient`.
- `RunDetailPage` does not import `DaemonClient`.
- `MainRouteOverlay` does not import `DaemonClient`.
- `MainTabsPage` does not pass `DaemonClient` to overlay or ordinary feature
  pages.
- The checker fails on ordinary UI direct `DaemonClient` imports.
- Allowed UI daemon-client imports are limited to the connection boundary and
  main tabs shell.
- `dart analyze` passes.
- `dart run tool/check_architecture_imports.dart` passes.
- Focused ViewModel and affected widget tests pass.

