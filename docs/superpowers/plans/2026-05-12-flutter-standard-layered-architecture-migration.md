# Flutter Standard Layered Architecture Migration Plan

> **For agentic workers:** REQUIRED NEXT MODE: implement this plan task-by-task. Keep changes small, preserve app behavior, and update checkboxes as tasks complete.

**Goal:** Migrate the Flutter mobile app to the approved standard layered architecture from `docs/superpowers/specs/2026-05-12-flutter-standard-layered-architecture-design.md`.

**Architecture:** Use `app` as a grouped composition root, `data` for API/persistence implementations, `domain` for pure models/contracts/use cases, `ui/core` for shared UI, and `ui/features` for feature views/ViewModels/widgets. Keep old paths only as temporary compatibility exports.

**Tech Stack:** Flutter/Dart mobile app; current dependencies only. Start architecture enforcement with a local Dart script, not a new analyzer plugin dependency.

---

## File Structure

- Create `mobile/tool/check_architecture_imports.dart`: import/export boundary and migration-count checker.
- Create `mobile/lib/src/app/app_dependencies.dart`: grouped app composition root.
- Create `mobile/lib/src/app/app_environment.dart`: runtime environment/config values if needed by dependencies.
- Create `mobile/lib/src/data/api/`: focused daemon API client files as slices require them.
- Create `mobile/lib/src/domain/failures/`: typed domain/feature failures.
- Create `mobile/lib/src/domain/repositories/`: repository contracts.
- Create `mobile/lib/src/domain/use_cases/`: cross-repository workflows.
- Move/create `mobile/lib/src/ui/core/theme/`, `mobile/lib/src/ui/core/widgets/`, and `mobile/lib/src/ui/core/layout/`.
- Move/create `mobile/lib/src/ui/features/[feature]/views|view_models|widgets` per feature migration.
- Modify `mobile/lib/lan_ai_cli_control.dart`: narrow exports after migration references are gone.
- Modify Flutter tests under `mobile/test/` as ownership moves.

---

## Task 1: Add Architecture Import Guard

**Files:**
- Create: `mobile/tool/check_architecture_imports.dart`
- Modify if useful: `mobile/README.md` or `docs/superpowers/specs/2026-05-12-flutter-standard-layered-architecture-design.md`

- [ ] **Step 1: Define forbidden import rules**

Implement a Dart script that scans `mobile/lib/**/*.dart` imports and exports.
Initial hard failures:

- `src/domain/**` must not import `package:flutter/`, `src/ui/`, `src/services/daemon_client.dart`, `package:http/`, or `package:shared_preferences/`.
- `src/ui/core/**` must not import `src/ui/features/` or `src/features/`.
- Production code outside `src/testing/**` must not import `src/testing/`.

- [ ] **Step 2: Track old-path imports**

Have the script print counts for imports/exports that reference migration-only roots:

- `src/features/`
- `src/widgets/`
- `src/theme/`
- `src/state/`

The first run establishes a baseline. Later tasks should include before/after counts and must not increase old-path references.

- [ ] **Step 3: Add usage instructions**

Document the command:

```powershell
cd mobile
dart run tool/check_architecture_imports.dart
```

- [ ] **Step 4: Verify guard**

Run the script and record current old-path counts. If it fails because the current tree violates a future-state rule, tune the script so hard failures only apply to target directories that already exist and are in active use.

---

## Task 2: Introduce Grouped AppDependencies

**Files:**
- Create: `mobile/lib/src/app/app_dependencies.dart`
- Create if needed: `mobile/lib/src/app/app_environment.dart`
- Modify: `mobile/lib/src/ui/mobile_ui.dart`
- Test: existing connection and app bootstrap tests

- [ ] **Step 1: Add dependency group classes**

Create grouped containers:

- `NetworkDependencies`: HTTP/client transport, token/session primitives.
- `DataDependencies`: stores and concrete repositories.
- `DomainDependencies`: shared use cases.
- `FeatureDependencies`: feature ViewModel factories when a feature meets the subgroup threshold.
- `AppDependencies`: top-level aggregate only.

- [ ] **Step 2: Move current object construction**

Move object creation currently done in `MobileUi` into `AppDependencies.createDefault()` or equivalent. Preserve behavior and avoid introducing a DI package.

- [ ] **Step 3: Inject dependencies into UI root**

Update `MobileUi` so it receives or creates `AppDependencies`, then passes specific ViewModels/factories down. Do not let widgets reach into unrelated dependency groups.

- [ ] **Step 4: Verify behavior**

Run focused tests for app bootstrap and daemon connection. Then run:

```powershell
cd mobile
flutter analyze
flutter test
dart run tool/check_architecture_imports.dart
```

---

## Task 3: Standardize Connection as Reference Feature

**Files:**
- Move/modify under: `mobile/lib/src/ui/features/connection/`
- Modify: `mobile/lib/src/state/daemon_connection_controller.dart`
- Modify/create: `mobile/lib/src/domain/use_cases/connect_to_daemon_use_case.dart`
- Modify/create: `mobile/lib/src/domain/repositories/connection_repository.dart`
- Modify/create: `mobile/lib/src/data/repositories/connection_repository_impl.dart`
- Test: `mobile/test/daemon_connection_controller_test.dart`, `mobile/test/daemon_connection_workflow_test.dart`

- [ ] **Step 1: Define connection contracts**

Extract repository/use-case interfaces needed by `DaemonConnectionViewModel`. Keep current workflow behavior intact.

- [ ] **Step 2: Move workflow behind use case**

Wrap `DaemonConnectionWorkflow` behind `ConnectToDaemonUseCase`. Keep `DaemonConnectionWorkflow` as an implementation detail until later cleanup.

- [ ] **Step 3: Convert legacy state file**

Change `src/state/daemon_connection_controller.dart` into a compatibility export, or remove it after all imports point to the target feature ViewModel.

- [ ] **Step 4: Verify reference pattern**

Run connection tests and architecture import guard. Confirm old-path import counts do not increase.

---

## Task 4: Add Repository Facades Around DaemonClient

**Files:**
- Create/modify: `mobile/lib/src/domain/repositories/*.dart`
- Create/modify: `mobile/lib/src/data/repositories/*_repository_impl.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart` only as needed for facade compatibility
- Test: daemon client, workflow, and repository tests

- [ ] **Step 1: Define repository contracts by feature area**

Add contracts for conversation, workspace, run, adapter, auth/connection, and ASR as needed. Keep method names business-oriented.

- [ ] **Step 2: Implement facades over existing DaemonClient**

Create repository implementations that delegate to `DaemonClient`. Do not split concrete API clients yet except where needed for a slice.

- [ ] **Step 3: Migrate ViewModels to contracts**

Update already-standardized ViewModels to depend on repository/use-case contracts instead of `DaemonClient`.

- [ ] **Step 4: Verify compatibility**

Run existing daemon client and workflow tests. Add small repository tests with fake clients/stores for any behavior newly moved into repositories.

---

## Task 5: Migrate Workbench in Slices

**Files:**
- Target: `mobile/lib/src/ui/features/workbench/`
- Source: `mobile/lib/src/features/workbench/`
- Modify tests: workbench, reducer, widget tests as applicable

Suggested slice order: sending flow, loading/timeline flow, approval handling, voice/ASR, workspace picker entry.

- [ ] **Step 1: Create target feature shell**

Create target `views`, `view_models`, and `widgets` folders. Add compatibility exports so existing callers continue to compile.

- [ ] **Step 2: Migrate sending flow**

Move prompt send state and daemon calls from `CodingWorkbenchPage` into `WorkbenchViewModel` plus repository/use-case calls. Add or update ViewModel tests for loading/sending/error transitions.

- [ ] **Step 3: Migrate loading and timeline flow**

Move conversation loading, event fetching, and timeline state into ViewModel/repository boundaries. Keep `ConversationViewState` reducer tests intact.

- [ ] **Step 4: Migrate approval handling**

Move approval and question answering actions out of the widget. Use typed failures and structured pending approval state.

- [ ] **Step 5: Migrate voice and ASR**

Extract `VoiceInputViewModel` and move ASR preparation/download coordination behind repository/use-case boundaries. Keep platform/plugin code in data/service classes.

- [ ] **Step 6: Migrate workspace picker entry**

Move workspace selection/creation entry points behind workspace repository/use-case boundaries. Keep picker UI feature-local unless reused elsewhere.

- [ ] **Step 7: Collapse old workbench path**

After target imports are in place, turn old `src/features/workbench` files into compatibility exports or remove files with zero references.

- [ ] **Step 8: Verify each slice**

After every slice, run focused tests plus the architecture import guard. Old-path import counts must not increase.

---

## Task 6: Migrate Secondary Features

**Files:**
- Source: `mobile/lib/src/features/{sessions,settings,adapters,diagnostics,notifications,run_detail,workspace_picker}`
- Source: `mobile/lib/src/ui/pages/{home_page,runs_page,queue_page,settings_page,coding}`
- Target: `mobile/lib/src/ui/features/[feature]/`

- [ ] **Step 1: Migrate sessions**

Move session list views, widgets, and ViewModels under `ui/features/sessions`. Keep compatibility exports until zero references remain.

- [ ] **Step 2: Migrate run detail and run/status pages**

Move run detail, runs page, queue page, and run status color helpers under `ui/features/runs` or `ui/features/run_detail` with a consistent naming decision.

- [ ] **Step 3: Migrate adapters and diagnostics**

Move adapter status and diagnostics pages/ViewModels under target feature folders. Replace direct `DaemonClient` usage with repository/use-case boundaries.

- [ ] **Step 4: Migrate settings and notifications**

Move settings and notifications UI into target feature folders. Keep app-level language/theme state in `app` or `ui/core` as appropriate.

- [ ] **Step 5: Migrate workspace picker**

Move workspace picker UI under `ui/features/workspace_picker` unless it becomes a workbench-only widget. Use workspace repository/use case for creation/list operations.

- [ ] **Step 6: Migrate home/coding route wrappers**

Move `ui/pages/coding` and home route wrappers into target feature/view folders or `ui/core/layout` if they are shell-level layout.

- [ ] **Step 7: Verify feature migrations**

Run feature-relevant tests, `flutter analyze`, and architecture import guard after each feature group.

---

## Task 7: Consolidate Shared UI Roots

**Files:**
- Source: `mobile/lib/src/widgets/`
- Source: `mobile/lib/src/theme/`
- Target: `mobile/lib/src/ui/core/widgets/`
- Target: `mobile/lib/src/ui/core/theme/`
- Target: `mobile/lib/src/ui/core/layout/`

- [ ] **Step 1: Move reusable widgets**

Move buttons, cards, inputs, navigation, status, top bar, and scaffold components into `ui/core/widgets` or `ui/core/layout` based on responsibility.

- [ ] **Step 2: Move theme and typography**

Move colors, typography, theme builder, and localization helpers into `ui/core/theme` if they are UI concerns. Keep app language state in `app`.

- [ ] **Step 3: Remove duplicate forwarding**

Remove or replace forwarding files after imports are updated and zero-reference checks pass.

- [ ] **Step 4: Verify shared UI boundaries**

Run architecture guard to confirm `ui/core` does not import concrete features.

---

## Task 8: Split Concrete Daemon APIs Incrementally

**Files:**
- Create/modify: `mobile/lib/src/data/api/*.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: data repository implementations
- Test: API client, repository, daemon client compatibility tests

- [ ] **Step 1: Extract shared request/auth support**

Move common HTTP request, token refresh, auth header, and error mapping behavior into data-level request support.

- [ ] **Step 2: Extract APIs as migrated flows require them**

Extract `ConversationApiClient`, `WorkspaceApiClient`, `RunApiClient`, `AdapterApiClient`, and `AsrModelApiClient` only when the corresponding ViewModel/repository slice is ready.

- [ ] **Step 3: Keep compatibility surface until callers migrate**

Leave `DaemonClient` as a compatibility facade until all direct production callers are removed.

- [ ] **Step 4: Verify direct caller count**

Use grep/import checks to track direct `DaemonClient` imports and method calls. Counts must trend down and reach zero before facade deletion.

---

## Task 9: Narrow Public API and Remove Compatibility Exports

**Files:**
- Modify: `mobile/lib/lan_ai_cli_control.dart`
- Remove/modify: compatibility exports under old roots

- [ ] **Step 1: List public exports**

Decide which exports are intentionally public: app entrypoint, domain/data models required by consumers, and test/debug helpers if needed.

- [ ] **Step 2: Prove zero references before deletion**

Before deleting each compatibility export, run grep/import checks proving zero remaining references to the old path.

- [ ] **Step 3: Delete old roots**

Remove old production primary roots after all imports are updated:

- `src/features`
- `src/widgets`
- `src/theme`
- `src/state`

- [ ] **Step 4: Final verification**

Run:

```powershell
cd mobile
dart run tool/check_architecture_imports.dart
flutter analyze
flutter test
```

---

## Task 10: Final Acceptance Review

**Files:**
- Modify: this plan checkboxes as tasks complete
- Modify/create: final progress note under `docs/superpowers/progress/`

- [ ] **Step 1: Confirm architecture acceptance criteria**

Verify:

- `domain` has no Flutter/HTTP/SharedPreferences/concrete daemon imports.
- `ui/core` has no concrete feature imports.
- production code does not import `src/testing`.
- old production roots are gone or compatibility-only with zero new imports.
- `CodingWorkbenchPage` is a shell, not the owner of business workflows.
- `DaemonClient` is no longer the production god client.

- [ ] **Step 2: Record migration evidence**

Write a progress note listing final test commands, old-path import counts, remaining compatibility exports if any, and follow-up risks.

- [ ] **Step 3: Hand off for product QA**

Ask for manual app verification of connection, workbench send/load, approval, ASR, workspace picker, settings, adapters, diagnostics, notifications, and run detail flows.

