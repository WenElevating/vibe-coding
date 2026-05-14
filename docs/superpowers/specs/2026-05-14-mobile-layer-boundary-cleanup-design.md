# Mobile Layer Boundary Cleanup Design

Date: 2026-05-14

## Context

The mobile Flutter app already follows the repository's layered architecture in
large strokes:

- `main.dart` boots through `src/app/`.
- `src/app/` builds dependency groups instead of a flat service locator.
- `src/data/` implements repository interfaces around daemon APIs.
- `src/domain/` owns pure contracts and business models.
- `src/ui/` owns feature views and ViewModels.
- `src/workflows/` owns multi-step side effects.
- `src/services/` owns platform and infrastructure adapters.

The latest architecture checks pass for the current rules, and the legacy roots
`src/features/`, `src/widgets/`, `src/theme/`, and `src/state/` have no active
imports. The remaining debt is narrower: a few allowed-by-accident imports still
let concrete infrastructure leak into domain and presentation code.

This design is for an incremental hardening pass. It should make the current
boundaries enforceable without rewriting the mobile app or changing the coding
workbench product behavior.

## Problem

The current architecture checker does not catch every boundary the repository
guidelines require. In particular:

- Domain code imports `src/services/daemon_connection_config.dart`.
- `MainTabsViewModel` depends directly on `DaemonClient` even though an
  `AdapterRepository` abstraction already exists.
- `CodingWorkbenchPage` still exposes a `DaemonClient` constructor parameter
  even though its workbench operations now flow through `WorkbenchDependencies`
  and `WorkbenchViewModel`.
- `CodingWorkbenchPage` directly constructs `SherpaSpeechInputService` after
  ASR model readiness, so UI still knows a concrete speech implementation.
- `WorkspacePickerSheet` still has a direct `DaemonClient` path even though the
  repository-based `AddWorkspaceSheet` and `DirectoryBrowserSheet` path already
  exists.

These issues are not user-facing bugs by themselves, but they make the app
harder to evolve safely. A future feature can accidentally bypass repositories,
place orchestration in a widget, or expand the wrong layer because the guardrail
does not fail.

## Goals

- Make the domain layer independent from `src/services/`.
- Keep daemon details behind repository or workflow interfaces before they reach
  UI ViewModels and widgets.
- Keep workbench speech model readiness and concrete ASR service construction
  out of the page where practical, while preserving the current modal UX.
- Remove redundant `DaemonClient` constructor paths from workbench and workspace
  UI surfaces.
- Strengthen `tool/check_architecture_imports.dart` so this cleanup cannot
  regress silently.
- Keep changes small enough to validate with targeted tests and the existing
  architecture checker.

## Non-Goals

- Do not migrate all of `src/ui/pages/` in this pass. That directory is still an
  active presentation area, not one of the retired roots.
- Do not productize the static diagnostics or run-detail pages in this pass.
- Do not introduce a dependency injection package.
- Do not replace `ChangeNotifier` or the current ViewModel pattern.
- Do not change daemon APIs, conversation semantics, ASR download behavior, or
  visible workbench UX.
- Do not add new runtime dependencies unless a later implementation plan proves
  they are necessary.

## Selected Approach

Use guardrail-first incremental cleanup.

This is the recommended approach because the app has already been migrated most
of the way into the layered structure. The remaining violations are concentrated
in a few files and can be handled as separate slices:

1. Move pure connection configuration concepts out of services reach.
2. Replace UI-facing concrete daemon access with repositories or narrow
   factories.
3. Remove obsolete constructor paths from widgets.
4. Expand the architecture checker to encode the newly cleaned boundary.

The rejected alternative is a broad UI tree migration that also moves
`src/ui/pages/` into feature folders. That may be worth doing later, but mixing
it with dependency-boundary cleanup would make review harder and increase the
risk of unrelated routing churn.

The other rejected alternative is checker-only policy work. That would document
the desired boundary but leave the concrete leaks in place, forcing either
allowed debt entries or failing checks before the code is actually ready.

## Target Boundary Rules

After the cleanup, the intended import direction is:

```text
src/app/
  may construct concrete services, data repositories, workflows, and feature
  dependency groups.

src/ui/
  may depend on domain repositories, workflows, feature dependencies,
  ViewModels, and UI primitives.
  should not depend on DaemonClient for feature behavior.

src/workflows/
  may coordinate repositories, services, validation, persistence, and daemon
  side effects.
  should expose a small operation-oriented API to ViewModels or app setup.

src/domain/
  may depend on domain models and repository/use-case contracts.
  must not import Flutter, HTTP, SharedPreferences, UI, services, or concrete
  daemon infrastructure.

src/data/
  may implement domain repositories using DaemonClient and data-facing services.

src/services/
  may wrap platform APIs, daemon HTTP clients, storage, device identity, ASR,
  and other infrastructure.
  must not import UI.
```

## Component Design

### Connection Configuration Boundary

`DaemonProxyMode`, `DaemonConnectionConfig`, `NormalizedDaemonAddress`,
normalization helpers, and the config exception are pure connection concepts.
They are currently located under `src/services/`, which makes domain use cases
depend on infrastructure by path.

Move these pure types to domain ownership, for example:

```text
mobile/lib/src/domain/models/daemon_connection_config.dart
```

Then update:

- `ConnectedAppSession`
- `ConnectToDaemonUseCase`
- connection workflow and ViewModel imports
- data repository/store imports that persist the config
- tests that import the old service path

`DaemonConnectionConfigStore` stays in `src/services/` because it wraps
SharedPreferences persistence. `DaemonConnectionConfigRepository` stays in
`src/data/` because it adapts the store to app/data usage.

Compatibility barrels should be avoided unless a large test surface makes a
temporary alias cheaper. If a temporary alias is used, it must live outside
domain and be removed in the same implementation plan.

### Architecture Checker

Extend `mobile/tool/check_architecture_imports.dart` so domain imports fail when
they target any `src/services/` file, not only `daemon_client.dart`.

The checker should keep the existing targeted rules:

- domain must not import Flutter.
- domain must not import HTTP.
- domain must not import SharedPreferences.
- domain must not import UI.
- services must not import UI.
- UI core must not import feature code.
- production code must not import `src/testing/`.
- retired roots remain migration-only and should count as zero.

No allowed debt entry should be introduced for the cleaned imports. The point of
this pass is to make the current desired state fail-fast.

### Main Tabs Adapter Loading

`MainTabsViewModel` currently accepts and stores `DaemonClient` only to call
`listAdapters()`. That call belongs behind the existing `AdapterRepository`.

Change `MainTabsViewModel` to receive:

```dart
required AdapterRepository adapterRepository
```

Its reload/reset path should accept the repository with the new connected data:

```dart
resetForNewClient({
  required AdapterRepository adapterRepository,
  required AppSnapshot data,
})
```

The ViewModel continues to own only presentation state:

- active tab
- route overlay state
- adapter load state
- selected coding tab affordances
- current `AppSnapshot`

The app/composition layer remains responsible for creating the repository from
the active daemon client. Tests should fake `AdapterRepository`, not
`DaemonClient`, when exercising adapter load behavior.

### Workbench Dependencies

`CodingWorkbenchPage` still takes `client`, but its operations already flow
through repositories inside `WorkbenchDependencies`. The page should drop the
direct `DaemonClient` constructor parameter if implementation confirms it is no
longer used.

`WorkbenchDependencies` should stay the single feature dependency envelope for
the workbench. If new workbench-facing infrastructure is needed, add a narrow
field there rather than passing concrete daemon services into the page.

The dependency group may grow from:

```text
asrModelManager
conversationRepository
diagnosticsRepository
runRepository
workspaceRepository
```

to include a voice service factory or workflow described below. It should not
become a flat app-wide service locator; it remains feature-scoped.

### Voice Input Preparation

The current page owns three different responsibilities around voice input:

- UI dialog display for ASR model preparation.
- readiness coordination through `AsrModelManager`.
- construction of `SherpaSpeechInputService`.

The page should keep only UI-specific dialog behavior and prompt merging. Move
the concrete speech service construction behind a small feature dependency.

Preferred shape:

```dart
abstract class SpeechInputServiceFactory {
  SpeechInputService createForModelDirectory(String modelDirectory);
}

final class SherpaSpeechInputServiceFactory
    implements SpeechInputServiceFactory {
  const SherpaSpeechInputServiceFactory();

  @override
  SpeechInputService createForModelDirectory(String modelDirectory) =>
      SherpaSpeechInputService(modelDirectory: modelDirectory);
}
```

`CodingWorkbenchPage` can then do:

```text
ask AsrModelManager for a ready model directory
ask SpeechInputServiceFactory for a SpeechInputService
update VoiceInputViewModel
start voice input
```

This still leaves the modal in the page, which is acceptable because the dialog
is UI. The concrete Sherpa class moves out of the page import list.

A larger `VoiceInputPreparationWorkflow` is not necessary unless the
implementation exposes repeated orchestration across more than one ViewModel.
The current behavior only needs a factory plus the existing `AsrModelManager`.

### Workspace Picker

`WorkspacePickerSheet` has a legacy direct-client constructor path that creates
workspaces and browses directories through `DaemonClient`. The active add-flow
already uses `AddWorkspaceSheet` with `WorkspaceRepository`, and
`DirectoryBrowserSheet.forWorkspaceRepository(...)` already exists.

The implementation should remove or replace the direct-client
`WorkspacePickerSheet` path:

- Prefer deleting the unused `WorkspacePickerSheet` if no production code
  references it.
- If it is still referenced by tests or older pages, change it to accept
  `WorkspaceRepository`.
- Keep `DirectoryBrowserSheet` repository-first.
- Remove `DirectoryBrowserSheet({required DaemonClient client})` if no longer
  needed.

Workspace creation should remain coordinated by the workbench ViewModel and
`CreateWorkspaceWorkflow` path, not buried inside a sheet that mutates daemon
state directly.

## Data Flow After Cleanup

### Startup Connection

```text
DaemonConnectionViewModel
  -> ConnectToDaemonUseCase
  -> DaemonConnectionWorkflow
  -> DaemonConnectionConfigRepository
  -> DaemonConnectionConfigStore
```

The use case and connected session models import the domain-owned connection
config model. Persistence remains in services/data.

### Adapter Loading

```text
MainTabsPage / app shell
  -> MainTabsViewModel
  -> AdapterRepository
  -> DaemonAdapterRepository
  -> DaemonClient
```

UI state stays in the ViewModel. Concrete daemon calls stay in the data
repository implementation.

### Workbench Operations

```text
CodingWorkbenchPage
  -> WorkbenchViewModel
  -> ConversationRepository / RunRepository / WorkspaceRepository
  -> daemon repository implementations
  -> DaemonClient
```

The page renders nested routes and dialogs. It should not know how daemon HTTP
calls are made.

### Voice Input

```text
CodingWorkbenchPage
  -> AsrModelManager.ensureReady()
  -> SpeechInputServiceFactory.createForModelDirectory(...)
  -> VoiceInputViewModel.updateService(...)
```

The page still decides when to show the modal and how to merge recognized text
into the composer. It no longer imports the concrete Sherpa implementation.

## Error Handling

- Moving connection config should preserve existing validation messages and
  exception behavior. This is a location/boundary change, not a behavior change.
- Adapter loading failures stay surfaced through `CodingAdapterLoadState.failed`
  and `adapterLoadError`.
- Voice preparation failures continue through the existing ASR dialog and
  page-level voice error modal. The factory should not swallow errors.
- Workspace browse/create failures remain visible in the same UI surfaces as
  today. The only intended change is that calls route through
  `WorkspaceRepository`.
- Architecture checker failures should print file, line, rule, and URI exactly
  like the current checker output.

## Testing Strategy

Run these checks before claiming the implementation complete:

```text
cd mobile && dart run tool/check_architecture_imports.dart
cd mobile && dart analyze
```

Targeted Flutter tests should cover the changed seams:

```text
cd mobile && flutter test test/daemon_connection_config_store_test.dart -r expanded
cd mobile && flutter test test/coding_workbench_controller_test.dart -r expanded
cd mobile && flutter test test/voice_input_controller_test.dart test/voice_input_view_model_test.dart test/speech_input_service_test.dart -r expanded
cd mobile && flutter test test/widget_test.dart -r expanded --name "adapter picker|opening coding tab|coding composer|coding workbench|conversation|workspace"
```

If implementation touches existing tests that fake `DaemonClient`, update only
the relevant fakes to repository interfaces. Do not broaden the test surface
unless a changed boundary demands it.

## Acceptance Criteria

- `src/domain/` has no imports from `src/services/`.
- `check_architecture_imports.dart` rejects domain imports from `src/services/`.
- `MainTabsViewModel` uses `AdapterRepository`, not `DaemonClient`.
- `CodingWorkbenchPage` no longer accepts a direct `DaemonClient` parameter if
  it is unused.
- Workbench speech service creation is behind a narrow factory or equivalent
  feature dependency.
- Workspace picker/directory browser creation flows use `WorkspaceRepository`
  instead of direct `DaemonClient` paths.
- The app composition root remains grouped into network, data, domain, and
  feature dependency groups.
- Existing workbench UI behavior is preserved.
- Architecture check, analyze, and targeted tests pass or any environment-only
  blocker is documented with exact command output.

## Implementation Order

1. Move the pure connection config model to domain and fix imports.
2. Strengthen the architecture checker and prove it catches the old boundary.
3. Convert `MainTabsViewModel` and its callers/tests to `AdapterRepository`.
4. Remove the redundant workbench `DaemonClient` parameter.
5. Add a speech input service factory to `WorkbenchDependencies` and remove the
   concrete Sherpa import from the page.
6. Remove or repository-convert the legacy workspace picker client path.
7. Run architecture, analyze, and targeted Flutter tests.

This order keeps each step reviewable and avoids mixing behavior changes with
guardrail changes.

## Follow-Up Work

After this pass, the next architecture candidates are:

- Decide whether `src/ui/pages/` should be gradually folded into
  `src/ui/features/` or kept as shell/page composition.
- Replace static diagnostics and run-detail placeholder pages with
  repository-backed ViewModels if they become active product surfaces.
- Consider checker rules for UI direct `DaemonClient` imports once the current
  known exceptions are removed.

These are intentionally outside the current implementation scope.
