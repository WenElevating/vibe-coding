# Mobile `part` to Import Boundary Migration Design

Date: 2026-05-04
Branch: `mobile-part-import-boundaries`

## Problem

The mobile Flutter UI is physically split across files, but most UI files are still attached to `mobile/lib/src/app/app.dart` through Dart `part` directives. This means shell, features, shared widgets, and testing helpers all share one private library namespace.

That structure makes module boundaries ineffective:

- private classes are visible across unrelated files
- feature files can depend on each other's internals without imports
- widget constructor changes ripple into shell, preview builders, and tests
- shared UI constants are app-private globals instead of a real theme API
- compiler errors do not expose boundary mistakes because there are no real boundaries

The target is to migrate the entire mobile UI away from app-wide `part` files and toward independent Dart libraries with explicit imports and feature barrel files.

## Goals

- Remove the app-wide `part` dependency model from the mobile UI.
- Give each feature folder a single public barrel file.
- Export only page-level entry points, required view models, and required callback types from feature barrels.
- Keep leaf widgets private inside their feature modules.
- Make cross-module private access fail at compile time.
- Keep each migration step small enough to format, analyze, test, and commit independently.
- Preserve current behavior while changing architecture.

## Non-Goals

- Do not redesign the mobile UI visually.
- Do not introduce new dependencies or a state-management package.
- Do not rewrite daemon APIs.
- Do not optimize snapshot loading in the same pass unless required by import boundaries.
- Do not refactor unrelated daemon or desktop code.
- Do not combine behavior changes with import-boundary migration commits.

## Target Directory Structure

```text
mobile/lib/
  main.dart
  lan_ai_cli_control.dart

  src/
    app/
      app.dart
      app_bootstrap.dart

    shell/
      shell.dart
      mobile_shell.dart
      app_snapshot.dart
      app_route.dart

    theme/
      theme.dart
      app_colors.dart
      app_typography.dart
      app_theme.dart
      app_localization.dart

    widgets/
      widgets.dart
      page_scaffold.dart
      top_bar.dart
      buttons.dart
      cards.dart
      status.dart
      navigation.dart
      inputs.dart

    models/
      protocol.dart

    services/
      daemon_client.dart
      conversation_client.dart

    state/
      conversation_reducer.dart
      dashboard_state.dart
      run_detail_state.dart

    features/
      workbench/
        workbench.dart
        coding_workbench_page.dart
        coding_workbench_controller.dart
        coding_workbench_state.dart
        coding_composer.dart
        workbench_messages.dart
        workbench_event_cards.dart
        approval_page.dart

      sessions/
        sessions.dart
        coding_session_list_page.dart
        session_item.dart
        session_list_view_model.dart

      workspace_picker/
        workspace_picker.dart
        workspace_list_page.dart
        add_workspace_sheet.dart
        directory_browser_sheet.dart
        workspace_rows.dart

      settings/
        settings.dart
        settings_page.dart

      run_detail/
        run_detail.dart
        run_detail_page.dart

      adapters/
        adapters.dart
        adapters_page.dart

      notifications/
        notifications.dart
        notifications_page.dart

      diagnostics/
        diagnostics.dart
        diagnostics_page.dart

    testing/
      testing.dart
      preview_builders.dart
      fake_daemon_client.dart
```

The exact file split may change during implementation if compiler errors reveal a better boundary, but the dependency rules below are fixed.

## Dependency Rules

### Allowed Direction

```text
main
  -> app

app
  -> shell
  -> theme

shell
  -> features/* barrel
  -> services
  -> models
  -> state
  -> widgets
  -> theme

features/*
  -> models
  -> services only when the feature owns the side effect
  -> state when needed
  -> widgets
  -> theme

widgets
  -> theme
  -> models only for truly generic display types

theme
  -> Flutter only

models/services/state
  -> no UI imports
```

### Forbidden Direction

- A feature must not import another feature's internal file.
- A feature must not import shell.
- `widgets/` must not import any feature.
- `theme/` must not import widgets, features, services, state, or shell.
- `models/`, `services/`, and `state/` must not import UI code.
- `testing/` must not construct feature-private leaf widgets.

## Barrel Rules

Each feature folder gets one barrel file, for example `features/workbench/workbench.dart`.

A feature barrel may export:

- page-level widgets used by shell
- view models required by those page-level widgets
- callback typedefs required by those page-level widgets
- public preview factories only when tests need stable construction APIs

A feature barrel must not export:

- leaf widgets
- styling helpers
- row/card internals
- private controller implementation details
- broad `export '*.dart'` catch-alls

Barrels are interface contracts, not convenience dumps.

## Migration Strategy

### Step 0: Freeze Behavior Baseline

Before migration starts, run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
```

If the workspace creation bugfix needs adjustment, finish and verify it before beginning import migration. Architecture commits should not hide behavior fixes.

### Step 1: Extract Theme

Move app-level UI constants from `app/app.dart` into `src/theme/`:

- colors
- font fallback
- locale
- localization delegates
- base text style
- `ThemeData` construction

Create `theme/theme.dart` as the single public theme barrel.

All UI files should import `theme/theme.dart` instead of relying on app-private constants.

### Step 2: Extract Shared Widgets

Split `widgets/shared_widgets.dart` into focused files:

- `page_scaffold.dart`
- `top_bar.dart`
- `buttons.dart`
- `cards.dart`
- `status.dart`
- `navigation.dart`
- `inputs.dart`

Create `widgets/widgets.dart` as the public widget barrel.

Only components used by two or more features belong in `widgets/`. Single-feature widgets stay inside their feature folder even if they look generic.

### Step 3: Extract Shell Snapshot

Move `_AppSnapshot` from `shell/mobile_shell.dart` into `shell/app_snapshot.dart` and make it `AppSnapshot`.

This step does not optimize data loading. It only makes the snapshot an explicit shell/data boundary rather than a private class shared by all `part` files.

### Step 4: Migrate Leaf Features First

Migrate simpler pages before the coding workflow:

- adapters
- diagnostics
- notifications
- run detail
- settings

For each feature:

- remove `part of '../../app/app.dart'`
- add explicit imports
- rename page widget from private to public, for example `_SettingsPage` to `SettingsPage`
- keep leaf widgets private
- create the feature barrel
- update shell to import the barrel
- format, analyze, test, commit

This establishes the repeatable pattern before touching the hardest feature.

### Step 5: Migrate Workspace Picker

Split `workspace_picker_sheet.dart` into separate files:

- `workspace_list_page.dart`
- `add_workspace_sheet.dart`
- `directory_browser_sheet.dart`
- `workspace_rows.dart`

Create `workspace_picker.dart` and export only:

- `WorkspaceListPage`
- `AddWorkspaceSheet`
- required callback typedefs or view models

Do not export rows, directory rows, mini inputs, or tiny buttons unless they are promoted to shared widgets because multiple features use them.

### Step 6: Migrate Sessions

Make the session list independent from workbench-private types.

Required changes:

- move `_SessionItem` out of workbench internals
- create `SessionItem` or `SessionListItem`
- create `SessionListViewModel` if direct input lists become too wide
- make `CodingSessionListPage` public
- create `sessions.dart`

The page should depend on explicit inputs:

- selected workspace
- session items
- callbacks for new session, selected session, and back to workspaces

It should not depend on broad `AppSnapshot` unless there is a documented reason.

### Step 7: Migrate Workbench

The workbench is the highest-risk feature and must be split in two passes.

#### Pass 1: Import Migration Only

- remove `part of`
- add explicit imports
- make `CodingWorkbenchPage` public
- keep current state ownership intact
- keep leaf widgets private
- create `workbench.dart`
- update shell to use the public entry point

No behavior rewrite belongs in this pass.

#### Pass 2: State Boundary Cleanup

After the import migration compiles and tests pass, split state and side effects:

- `CodingWorkbenchController`
- `CodingWorkbenchState`
- workspace selection state
- conversation polling lifecycle
- local session merge behavior

This pass is allowed to improve structure, but only after Pass 1 gives compiler-enforced module boundaries.

### Step 8: Migrate Testing Helpers

Replace `testing/debug_helpers.dart` with `testing/preview_builders.dart` and `testing/testing.dart`.

Preview builders should construct public feature entry points or explicit public preview factories. They should not construct feature-private leaf widgets.

If a test needs a private widget, either:

- test through the public page behavior, or
- introduce a deliberately public feature-level preview API.

### Step 9: Clean Up `app.dart`

After all feature files are independent libraries:

- delete all UI `part` directives from `app/app.dart`
- keep `LanAiCliControlApp` focused on `MaterialApp`
- import only `theme/theme.dart` and `shell/shell.dart`
- update `lan_ai_cli_control.dart` to export only stable public APIs

## Validation Rules

Every migration step must end with:

```bat
cd /d D:\AiProject\vibe-coding\mobile
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
```

Each step should be its own commit when possible. If a step reveals a behavior bug, stop and fix that bug in a separate behavior-focused commit before continuing architecture migration.

## Risk Register

### Risk: Import Migration Becomes Behavior Rewrite

Mitigation: Separate import-only commits from controller/state cleanup commits.

### Risk: Barrels Become New Monoliths

Mitigation: Only page-level widgets, necessary view models, and callback typedefs may be exported. No catch-all exports.

### Risk: Shared Widgets Become Junk Drawer

Mitigation: A widget enters `widgets/` only if at least two features use it or it is part of the app shell/design system.

### Risk: Tests Overfit Implementation

Mitigation: Tests should prefer public page behavior and stable preview factories over private widget construction.

### Risk: Workbench Migration Breaks Conversation State

Mitigation: Workbench import migration happens before workbench state cleanup. Stateful behavior must be verified before extracting controllers.

### Risk: Flutter Element State Is Lost

Mitigation: When moving `StatefulWidget` classes across files or renaming public classes, verify text input state, scroll position, active polling, and in-progress conversation UI manually.

## Acceptance Criteria

- `app/app.dart` has no feature `part` directives.
- Feature folders expose one public barrel file each.
- Shell imports feature barrels, not feature internals.
- Feature internals remain private to their own Dart libraries.
- `theme/` and `widgets/` are real importable modules.
- `flutter analyze --no-pub` passes.
- `flutter test --no-pub` passes.
- Current workspace-first session navigation behavior remains intact.

