# Flutter Standard Layered Architecture Design

## Context

The mobile Flutter app already has a partial MVVM and layered architecture:
`data/`, `domain/`, `ui/features/.../view_models`, and feature-specific tests
are present. The current structure is still mixed, with production code spread
across `src/features`, `src/ui/features`, `src/ui/pages`, `src/widgets`,
`src/theme`, `src/state`, and `src/services`.

Recent work includes a commit named `Refactor mobile app to MVVM architecture`,
so the goal is not a rewrite. The goal is a full migration plan that converges
the current codebase onto one standard layered structure while keeping the app
running and testable throughout the migration.

## Goals

- Standardize `mobile/lib/src` around app, data, domain, and UI layers.
- Make dependency direction explicit and enforceable.
- Move business state and workflow orchestration out of large widgets.
- Split the current all-purpose daemon client into focused API/data services.
- Keep each migration phase reviewable, testable, and reversible.

## Non-Goals

- Do not redesign product behavior or visual UI.
- Do not introduce a new state-management package unless a later phase proves
  that manual dependency injection is no longer sufficient.
- Do not do a one-shot directory move that rewrites most imports in one change.
- Do not remove existing tests during migration; update them as ownership moves.

## Target Project Structure

```text
mobile/lib/src/
├── app/
│   ├── app.dart
│   ├── app_dependencies.dart
│   ├── language_*.dart
│   └── app_environment.dart
├── data/
│   ├── api/
│   ├── models/
│   ├── repositories/
│   └── services/
├── domain/
│   ├── failures/
│   ├── models/
│   ├── repositories/
│   └── use_cases/
├── testing/
└── ui/
    ├── core/
    │   ├── theme/
    │   ├── widgets/
    │   └── layout/
    └── features/
        └── [feature]/
            ├── view_models/
            ├── views/
            └── widgets/
```

Temporary compatibility exports may remain during migration, but new production
code should use the target structure.

## Dependency Rules

- `app` is the composition root. It creates concrete data implementations and
  injects dependencies into UI/ViewModels.
- `ui/features` owns screens, feature widgets, and ViewModels. ViewModels depend
  on use cases or repository abstractions, not on concrete HTTP clients.
- `ui/core` owns shared visual primitives and must not depend on concrete
  features.
- `domain` owns pure models, repository contracts, failures, and use cases. It
  must not import Flutter widgets, SharedPreferences, HTTP clients, or concrete
  daemon client classes.
- `data` owns external access: HTTP, JSON, token/session storage, local storage,
  platform plugins, and repository implementations.
- Top-level public exports must stay narrow. `lan_ai_cli_control.dart` should
  expose the app entrypoint and intentional public/test APIs, not every internal
  implementation detail.

## Component Boundaries

### AppDependencies

`AppDependencies` is the single composition root for the mobile app. It creates
and owns concrete instances such as HTTP clients, token stores, config stores,
API clients, repositories, use cases, and root ViewModels.

This keeps object construction out of widgets such as `MobileUi` and makes test
replacement simpler.

### API Clients

API clients handle HTTP transport, JSON encoding/decoding, auth headers, and raw
response validation. They should expose focused methods and typed exceptions.

Planned examples:

- `DaemonApiClient` for health, version, auth, and shared request behavior.
- `ConversationApiClient` for conversation endpoints.
- `WorkspaceApiClient` for workspace endpoints.
- `RunApiClient` for run/status endpoints.
- `AsrModelApiClient` for ASR model metadata and downloads.

### Repositories

Repositories combine API clients and stores into business-oriented operations.
They provide the single source of truth for each data area and hide transport
details from ViewModels.

Planned examples:

- `ConnectionRepository`
- `ConversationRepository`
- `WorkspaceRepository`
- `RunRepository`
- `AdapterRepository`
- `AsrModelRepository`

### Use Cases

Use cases contain multi-step or cross-repository workflows. Simple CRUD-like
operations can remain on repositories until reuse or complexity justifies a use
case.

Planned examples:

- `ConnectToDaemonUseCase`
- `CreateWorkspaceUseCase`
- `LoadConversationUseCase`
- `SendConversationPromptUseCase`
- `AnswerConversationQuestionUseCase`
- `PrepareAsrModelUseCase`

### ViewModels

ViewModels own UI state, invoke use cases, and expose immutable or read-only
state to views. They should not construct URLs, parse exception strings, read
SharedPreferences directly, or call a god client.

### Views and Feature Widgets

Views render state and forward user intent to ViewModels. They may own purely UI
concerns such as animation controllers, scroll controllers, focus, and dialog
presentation. They must not own long-lived business workflows.

Feature-specific widgets stay under their feature. Only widgets reused by more
than one feature should move to `ui/core/widgets`.

## Key Data Flows

### Startup and Connection

1. `LanAiCliControlApp` creates or receives `AppDependencies`.
2. `MobileConnectionGate` receives a connection ViewModel.
3. `DaemonConnectionViewModel` calls `ConnectToDaemonUseCase`.
4. The use case coordinates config storage, device identity, token/session
   handling, daemon health, and snapshot loading through repositories.
5. The successful result is an app/session-level object containing session
   metadata and initial snapshot data. It should not be a domain model that
   directly owns `DaemonClient`.

### Workbench

1. `CodingWorkbenchPage` becomes a page shell that composes feature widgets.
2. `WorkbenchViewModel` owns selected workspace, active conversation, timeline
   state, loading/sending state, and user-visible failures.
3. Conversation and workspace operations go through repositories or use cases.
4. Approval handling and question answering use typed use cases rather than
   widget-local daemon calls.

### Voice and ASR

1. Voice input state moves behind `VoiceInputViewModel` or an ASR-specific
   ViewModel.
2. Model preparation and download logic moves to `PrepareAsrModelUseCase` and
   `AsrModelRepository`.
3. The UI displays states and triggers actions; it does not coordinate platform
   storage, download validation, and recognition lifecycle directly.

## Error Handling

Data-layer code should throw typed technical exceptions such as:

- `ApiException`
- `AuthExpiredException`
- `NetworkException`
- `InvalidResponseException`

Repository and use-case layers convert technical exceptions into feature/domain
failures such as:

- `ConnectionFailure.timeout()`
- `ConnectionFailure.authExpired()`
- `ConversationFailure.invalidResponse()`
- `WorkspaceFailure.permissionDenied()`

ViewModels expose structured UI state such as `isLoading`, `isBusy`,
`errorSummary`, `errorDetail`, `requiresReauth`, and `pendingApproval`. Widgets
choose the visual presentation: inline error, dialog, snackbar, or navigation
back to the connection gate.

Authentication expiry should become an app-level effect: clear the active
session and return to the connection flow. Individual pages should not each
implement their own string-based auth-expiry handling.

## Migration Phases

### Phase 0: Freeze the Rules

- Add architecture documentation for the target structure and dependency rules.
- Mark old production roots as migration-only: `src/features`, `src/widgets`,
  `src/theme`, `src/state`, and broad top-level exports.
- Prefer compatibility exports during migration rather than immediate deletion.

### Phase 1: Add the Composition Root

- Add `app/app_dependencies.dart`.
- Move object construction currently done in `MobileUi` into dependencies.
- Keep the same runtime behavior and constructor injection style.
- Do not add a dependency injection package in this phase.

### Phase 2: Standardize Connection

- Treat the current `ui/features/connection` implementation as the target
  pattern.
- Move connection workflow boundaries toward use cases/repositories.
- Replace `state/daemon_connection_controller.dart` with a compatibility export
  or remove it after imports are migrated.

### Phase 3: Standardize the Data Layer

- Split `DaemonClient` into focused API clients and shared request/auth support.
- Keep public behavior stable through repository interfaces.
- Move token/session handling and HTTP error mapping into data-level utilities.
- Keep existing daemon client tests as regression tests while introducing
  focused API/repository tests.

### Phase 4: Clean the Domain Layer

- Keep domain models pure.
- Move session objects that contain concrete clients into `app`, `shell`, or a
  use-case result type outside pure domain models.
- Add repository contracts or use-case input/output models where ViewModels need
  stable abstractions.

### Phase 5: Migrate Workbench

- Move workbench into `ui/features/workbench` with clear subfolders.
- Reduce `CodingWorkbenchPage` to a shell responsible for layout, navigation,
  and composing child widgets.
- Move session loading, prompt sending, question answering, approval handling,
  and workspace creation into ViewModels/use cases.
- Extract voice/ASR state into a separate ViewModel or feature-local controller.
- Split timeline, composer, workspace picker entry, approval cards, and status
  panels into focused widgets.

### Phase 6: Migrate Secondary Features

Migrate the remaining feature areas to `ui/features/[feature]`:

- sessions
- settings
- adapters
- diagnostics
- notifications
- run detail
- workspace picker
- home/runs/queue pages

Each migration should update imports and tests for one feature at a time.

### Phase 7: Consolidate Shared UI

- Move reusable widgets from `src/widgets` to `ui/core/widgets`.
- Move theme and typography from `src/theme` to `ui/core/theme`.
- Remove forwarding files such as duplicated app/theme localization exports once
  callers use the target paths.
- Keep feature-local widgets out of `ui/core` unless they are actually reused.

### Phase 8: Clean Public API and Compatibility Exports

- Narrow `lan_ai_cli_control.dart` exports.
- Delete migration-only compatibility exports once all internal imports are
  updated.
- Add or update architecture boundary checks.

## Workbench Target Layout

```text
mobile/lib/src/ui/features/workbench/
├── view_models/
│   ├── workbench_view_model.dart
│   └── voice_input_view_model.dart
├── views/
│   └── coding_workbench_page.dart
├── widgets/
│   ├── approval_card.dart
│   ├── composer.dart
│   ├── conversation_timeline.dart
│   ├── workspace_panel.dart
│   └── workbench_header.dart
└── workbench.dart
```

Optional use cases can live under `domain/use_cases/workbench` or more generic
domain folders if they are reused by other features.

## Testing Strategy

- Add architecture boundary tests or scripts that reject invalid imports, such
  as `domain` importing Flutter UI or concrete daemon client classes.
- Keep protocol and reducer compatibility tests intact during data migration.
- Add API client tests for paths, auth headers, refresh behavior, JSON parsing,
  and typed error mapping.
- Add repository/use-case tests with fake clients and stores.
- Add ViewModel tests for connection, workbench, voice input, and common failure
  transitions.
- Keep widget tests focused on rendering and user interaction, not full business
  workflow orchestration.
- Run `flutter analyze` and `flutter test` for migration phases that touch
  Flutter code.

## Acceptance Criteria

- `mobile/lib/src` no longer uses `features`, `widgets`, `theme`, or `state` as
  production primary roots. Any remaining files there are compatibility exports
  with documented removal targets.
- `domain` does not depend on Flutter widgets, concrete daemon clients, HTTP, or
  SharedPreferences.
- The daemon client is no longer a full-feature god client. Shared HTTP/auth
  behavior and feature-specific APIs are separated.
- `CodingWorkbenchPage` is primarily a view shell. Business workflows live in
  ViewModels, repositories, or use cases.
- Connection, workbench, ASR, and secondary feature ViewModels expose structured
  state rather than requiring widgets to parse exception strings.
- Top-level public exports are intentional and narrow.
- `flutter analyze`, `flutter test`, and architecture boundary checks pass.

## Recommended First Implementation Plan

1. Add architecture rules and import-boundary checks.
2. Introduce `AppDependencies` without changing behavior.
3. Finish the connection feature as the reference implementation.
4. Split `DaemonClient` behind repositories while keeping compatibility tests.
5. Migrate workbench in small slices, starting with sending/loading flows.
6. Migrate secondary features and shared UI roots.
7. Remove compatibility exports and narrow public API.

