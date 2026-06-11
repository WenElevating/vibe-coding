# Mobile Architecture Migration Design

## Purpose

Migrate the Flutter mobile app toward a layered architecture without a broad rewrite. The first phase focuses only on the daemon connection startup path so it can become the reference pattern for later feature migrations.

The target architecture separates UI rendering, UI state, workflow orchestration, persistent data access, external services, and domain models. The migration must preserve current behavior and keep existing tests useful while introducing clearer boundaries.

## Scope

This phase covers the connection startup path:

- Loading saved daemon connection configuration.
- Accepting and validating user connection input.
- Creating the daemon client.
- Probing daemon health.
- Loading the initial daemon data.
- Saving the connected configuration.
- Routing to either the connection form, loading state, error state, or main tabs.

This phase does not migrate the workbench, conversation lifecycle, protocol model file, ASR architecture, language settings, theme system, or all feature pages.

## Current Context

The current mobile code already has some useful seams:

- `mobile/lib/src/services/` contains daemon, conversation, ASR, and config access classes.
- `mobile/lib/src/state/daemon_connection_controller.dart` is already a `ChangeNotifier` and is close to a ViewModel.
- `mobile/lib/src/shell/app_snapshot.dart` loads the startup data currently passed into the main tabs.
- `mobile/lib/src/ui/mobile_ui.dart` currently constructs the connection controller and switches between loading, connected, and connection pages.

The main issue is that connection orchestration, UI state, persistence, client construction, and initial app loading are not expressed as separate architectural roles.

## Target Directory Shape

The first phase introduces the architecture only where the connection path needs it:

```text
mobile/lib/src/
+-- data/
|   +-- repositories/
|   |   +-- daemon_connection_config_repository.dart
|   +-- services/
|       +-- daemon_client.dart
|       +-- daemon_connection_config_store.dart
|       +-- token_store.dart
+-- domain/
|   +-- models/
|       +-- daemon_connection_config.dart
|       +-- daemon_connection_state.dart
|       +-- daemon_initial_data.dart
|       +-- connected_app_session.dart
+-- workflows/
|   +-- connection/
|       +-- daemon_connection_workflow.dart
+-- ui/
    +-- features/
        +-- connection/
            +-- view_models/
            |   +-- daemon_connection_view_model.dart
            +-- views/
                +-- mobile_connection_gate.dart
```

Existing paths can remain as compatibility exports during the migration. The goal is not to force every import to move in one commit.

## Layer Responsibilities

### Data Services

Services wrap external IO and platform boundaries. They do not own product workflows.

Examples:

- Daemon HTTP calls.
- Local config store primitives.
- Token storage primitives.

### Data Repositories

Repositories handle persistence-oriented access and persistence-specific mapping. They must not orchestrate multi-step application flows.

For the connection path, the repository should read and save daemon connection configuration. It should not create a daemon client, call health checks, load initial daemon data, or decide UI status transitions.

### Workflows

Workflows are the application layer. They sit between UI ViewModels and data access, coordinating services, repositories, and domain models without becoming UI state holders or persistence abstractions.

Workflows live at `mobile/lib/src/workflows/` instead of under `domain/` because they describe application use-case sequencing, not pure domain data. Feature-specific workflows should use subdirectories such as `workflows/connection/` so later workflows do not accumulate in one flat folder.

The daemon connection workflow is responsible for:

- Resolving validated connection input into a config.
- Creating or receiving a daemon client, including any token store required by the client.
- Running the health probe.
- Loading the initial daemon data.
- Saving the connected configuration through the config repository.
- Returning a typed success or failure result.

### Domain Models

Domain models are framework-light data structures used across layers. They should make the language of the app explicit.

Important names:

- `DaemonInitialData`, not `AppSnapshot` or `AppState`, for the initial data loaded from the daemon during startup.
- `ConnectedAppSession` for the successful connected bundle of `client`, `initialData`, and `connectedConfig`.
- `DaemonConnectionState` for the immutable state exposed by the connection ViewModel.
- `DaemonConnectionFailure` for normalized connection failures.

### UI ViewModels

ViewModels extend `ChangeNotifier`, expose immutable state, and handle user commands. They call workflows but do not perform low-level daemon or persistence work directly. Mapping `ConnectedAppSession` or `DaemonConnectionFailure` into `DaemonConnectionState` is a ViewModel responsibility, not a workflow responsibility.

The ViewModel owns UI-level concurrency protection for stale attempts. It increments or replaces an attempt token before each load/connect request, ignores results from older attempts, and exposes the current state only from the latest attempt. The workflow returns ordinary `Future` results and does not need a UI cancellation token in this phase.

Initial configuration loading is also initiated by the ViewModel. On initialization, the ViewModel asks the config repository for saved config, applies fallback values when needed, and updates the form state. It does not call the connection workflow until the user submits or an explicit reconnect behavior is added later.

The current `DaemonConnectionController` can become a compatibility wrapper or export around `DaemonConnectionViewModel` during the first phase.

### UI Views

Views render current state and forward user intent to ViewModels. They should not construct services or encode connection workflow order.

`MobileConnectionGate` becomes the connection feature entry point. It decides whether to show loading, connection form, error UI, or main tabs based on `DaemonConnectionViewModel.state`.

Dependencies are assembled manually with constructor injection. A small factory or parent widget near `MobileConnectionGate` may create the config repository, token store, workflow, and ViewModel, but no new dependency injection package is introduced in this phase.

## Data Flow

The target flow is one directional:

```text
MobileConnectionGate
  -> DaemonConnectionViewModel
  -> DaemonConnectionWorkflow
  -> DaemonClient / ConfigRepository / TokenStore / DaemonInitialData loader
  -> ConnectedAppSession or DaemonConnectionFailure
  -> DaemonConnectionState mapped by DaemonConnectionViewModel
  -> UI rebuild
```

The successful connection flow is:

```text
connect()
  -> DaemonConnectionWorkflow.connect()
  -> health()
  -> load DaemonInitialData
  -> save config
  -> ConnectedAppSession(client, initialData, config)
  -> DaemonConnectionViewModel.state
```

The startup configuration flow is separate from the connection workflow:

```text
DaemonConnectionViewModel.init()
  -> DaemonConnectionConfigRepository.load()
  -> fallback config if none is saved
  -> DaemonConnectionState with prefilled form fields
```

## Error Handling

Low-level services may throw existing exceptions such as `DaemonClientException`. The workflow catches those errors and converts them into `DaemonConnectionFailure` values with stable codes.

The ViewModel maps failures into the existing user-facing summaries and details. Views only display fields from `DaemonConnectionState`; they do not inspect exception types.

The existing timeout, connection refused, invalid JSON, empty response, and proxy-intercepted messages should remain behaviorally compatible.

## Migration Plan

1. Lock current connection behavior with tests before moving code.
2. Add the new `data`, `domain`, `workflows/connection`, and `ui/features/connection` directories.
3. Introduce `DaemonConnectionConfigRepository` as a persistence-only wrapper around the existing config store.
4. Extract daemon connection orchestration into `DaemonConnectionWorkflow`.
5. Introduce `DaemonInitialData` and `ConnectedAppSession`; keep compatibility for old `AppSnapshot` names while call sites migrate.
6. Move connection UI state into `DaemonConnectionViewModel`; keep `DaemonConnectionController` as a compatibility surface if needed.
7. Add explicit constructor injection for repository, token store, workflow, and ViewModel near the connection gate.
8. Replace `MobileUi` connection branching with `MobileConnectionGate` while keeping `MainTabsPage` behavior intact.
9. Update imports gradually and keep public exports stable until dependent tests and widgets are migrated.

## Testing Strategy

Connection behavior should be verified at several boundaries:

- ViewModel tests for user input, status transitions, stale attempt cancellation, and failure text mapping.
- Workflow tests for successful connection order, health failures, initial-data load failures, and timeout behavior.
- Repository tests for loading, saving, and fallback config behavior.
- Widget tests for loading, connected, failed, and idle connection gate rendering.

Validation should start with focused connection tests, then run `flutter analyze` and `flutter test` once the migration is implemented.

## Non-Goals

- No new dependency injection package in this phase.
- No broad migration of workbench or conversation features.
- No large rewrite of `protocol.dart`.
- No unrelated UI restyling.
- No theme, localization, or ASR restructuring.

## Acceptance Criteria

- The connection path has explicit data, workflow, domain, ViewModel, and View boundaries.
- Repositories remain persistence-focused and do not orchestrate connection flows.
- Connection orchestration lives in `workflows`.
- User-visible connection behavior remains unchanged.
- Existing tests continue to pass after implementation, with focused tests added for the new workflow boundary.
- New code uses `DaemonInitialData` naming instead of `AppSnapshot` or generic `AppState` for startup daemon data.
