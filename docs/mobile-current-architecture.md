# Mobile Current Architecture

Date: 2026-05-04

This document describes the current Flutter mobile architecture as it exists after the `main.dart` decomposition and workspace-first navigation changes. It is intentionally descriptive, not a target design.

## Summary

The mobile app now has a thin launcher and a `src/` directory split into app, shell, feature, service, state, testing, and widget folders. However, most UI files are still joined by Dart `part` directives under one private library rooted at `mobile/lib/src/app/app.dart`. This means the code is physically split into files, but many architectural boundaries are not enforced by Dart imports or public APIs.

The result is a semi-modular structure:

- File size is smaller than the old monolithic `main.dart`.
- Feature code is easier to locate than before.
- Private classes remain visible across all `part` files.
- UI state, daemon calls, navigation, and test preview helpers are still tightly coupled.
- Small changes to a widget constructor or callback often ripple through shell, workbench, previews, and tests.

## Entry Points

### `mobile/lib/main.dart`

The runtime entry point is thin:

- Imports Flutter.
- Imports `src/app/app.dart`.
- Runs `LanAiCliControlApp`.

### `mobile/lib/lan_ai_cli_control.dart`

The package-level library exports:

- `src/app/app.dart`
- protocol models
- daemon and conversation clients
- state helpers and reducers

Because `src/app/app.dart` includes many `part` files, exporting it also exposes testing helper functions annotated with `@visibleForTesting` when they are public names.

## App Library Shape

### Root Library

`mobile/lib/src/app/app.dart` is the root UI library. It imports shared dependencies and declares a large list of `part` files:

- `testing/debug_helpers.dart`
- `shell/mobile_shell.dart`
- `features/workbench/coding_workbench_page.dart`
- `features/sessions/coding_session_list_page.dart`
- `features/workspace_picker/workspace_picker_sheet.dart`
- `features/workbench/coding_composer.dart`
- `features/workbench/workbench_messages.dart`
- `features/workbench/workbench_event_cards.dart`
- `features/workbench/approval_page.dart`
- `features/settings/settings_page.dart`
- `widgets/shared_widgets.dart`
- `features/run_detail/run_detail_page.dart`
- `features/adapters/adapters_page.dart`
- `features/notifications/notifications_page.dart`
- `features/diagnostics/diagnostics_page.dart`

This is the central architectural fact: these files are not independent Dart libraries. They share one private namespace.

### Global UI Constants

`app.dart` also owns shared visual constants:

- colors such as `_bg`, `_panel`, `_purple`, `_text`, `_muted`
- font fallback list
- locale and localization delegates
- base text style

All `part` files can use these private constants directly. This keeps styling convenient, but it also prevents feature files from becoming standalone modules.

## Shell Layer

### File

`mobile/lib/src/shell/mobile_shell.dart`

### Responsibilities

`MobileShell` currently owns:

- bottom tab selection
- route overlay selection
- shell-level settings such as stream output, expanded thinking, and permission mode
- whether the coding session list is open
- daemon client creation
- app snapshot loading
- retry behavior for connection errors
- assembly of all top-level pages

### Snapshot Loading

`_AppSnapshot.load()` lives in `mobile_shell.dart`. It performs a broad load:

- health
- pairing and token bootstrap
- workspaces
- project overview for the first workspace
- adapters
- runs for the first workspace
- conversations
- queue
- command templates
- git status, diff, commits
- file tree
- diagnostics
- extensions

This makes the shell a data gateway and view composer at the same time. It also means features receive a broad `_AppSnapshot` instead of smaller feature-specific view models.

## Feature Layer

### Workbench

Main files:

- `features/workbench/coding_workbench_page.dart`
- `features/workbench/coding_composer.dart`
- `features/workbench/workbench_messages.dart`
- `features/workbench/workbench_event_cards.dart`
- `features/workbench/approval_page.dart`

`_CodingWorkbenchPage` is the most important state owner in the mobile UI. It currently manages:

- workspace list mode
- workspace-scoped session list mode
- conversation detail mode
- selected workspace
- selected adapter
- prompt controller
- scroll controller
- local session merge cache
- active run and conversation ids
- conversation polling timer
- conversation events and reduced state
- approval resolution state
- send, cancel, create conversation, continue conversation, and polling flows

This file is the main coupling hotspot. The workspace-first flow added more responsibilities to a file that already owned conversation execution.

### Sessions

File:

- `features/sessions/coding_session_list_page.dart`

The session list currently renders sessions scoped to the selected workspace. It receives:

- full `_AppSnapshot`
- merged `_SessionItem` list
- `currentWorkspace`
- callbacks for new session, selecting an item, and returning to workspace list

It is visually a session-list component, but its inputs still depend on workbench-private types such as `_SessionItem` and app-private snapshot types such as `_AppSnapshot`.

### Workspace Picker

File:

- `features/workspace_picker/workspace_picker_sheet.dart`

This file currently contains several related but distinct surfaces:

- adapter picker sheet
- workspace list page
- legacy workspace picker sheet
- add workspace sheet
- directory browser sheet
- workspace rows
- directory rows
- mini input
- tiny action button
- workspace display helpers

It is both a feature surface and a local component library. This makes small UI changes easy to do locally, but it also makes ownership unclear.

### Other Pages

Other feature pages are thinner:

- adapters
- diagnostics
- notifications
- run detail
- settings

They are still `part` files, so they can access shared private widgets and constants directly.

## Services and Models

### Models

`mobile/lib/src/models/protocol.dart` contains protocol models shared by the mobile client:

- daemon health and version data
- workspace summaries
- project overview
- adapters
- runs
- conversations
- queue items
- command templates
- git, file tree, diagnostics, and extension models

It is a large data model file and is one of the few real importable modules.

### Services

`mobile/lib/src/services/daemon_client.dart` owns HTTP access to the daemon:

- pairing and token storage
- workspaces
- adapters
- runs
- conversations
- file system browser
- diagnostics and git endpoints

`mobile/lib/src/services/conversation_client.dart` is a smaller service around conversation behavior.

These are real Dart libraries, unlike most UI feature files.

## State Layer

State files are separate libraries:

- `state/conversation_reducer.dart`
- `state/dashboard_state.dart`
- `state/run_detail_state.dart`

The strongest state boundary is the conversation reducer. Workbench still owns most orchestration around it, including polling, active ids, and local view state.

## Shared Widgets

File:

- `widgets/shared_widgets.dart`

This file contains broadly reusable UI building blocks such as page scroll, top bars, cards, buttons, status pills, navigation, and layout helpers.

Because it is a `part` file, these widgets are not a real package-level design system. They are private names available everywhere in the app library.

The current risk is that `shared_widgets.dart` becomes a junk drawer. A widget can move there without proving that two or more features need it.

## Testing Architecture

File:

- `testing/debug_helpers.dart`

The widget tests import `package:lan_ai_cli_control/lan_ai_cli_control.dart` and use public debug preview builders from `debug_helpers.dart`.

Current preview builders directly construct private widgets such as:

- `_WorkspaceListPage`
- `_CodingSessionListPage`
- `_CodingWorkbenchPage`

This makes tests easy to write, but it couples tests to private constructors. When a private widget callback changes, the debug helper must change even if behavior is unchanged.

## Dependency Reality

The intended directory structure suggests this layering:

```text
app
shell
features
widgets
state
services
models
```

The actual Dart dependency structure is closer to this:

```text
lan_ai_cli_control.dart
  exports app.dart

app.dart
  imports models, services, state
  parts shell, features, widgets, testing

all part files
  share one private namespace
  can reference each other's private classes
  can reference app-level private constants
```

So the folder structure looks modular, but the compiler sees one large UI library.

## Main Coupling Hotspots

### 1. The `part` Super-Library

Private names are global across all UI files. This removes compiler-enforced boundaries between shell, features, widgets, and tests.

Impact:

- feature files can reference each other without imports
- private helper names can leak across files
- constructor changes ripple through unrelated preview helpers
- it is unclear which file owns which concept

### 2. `_CodingWorkbenchPage` as Workflow Owner

The workbench owns workspace navigation, session navigation, conversation detail, daemon mutations, polling, local caches, and UI state.

Impact:

- workspace changes affect conversation code
- session-list changes affect workbench state
- shell callbacks change when workbench internals change
- bug fixes often touch multiple files

### 3. `_AppSnapshot` Is Too Broad

Many pages receive the full snapshot even when they only need a slice.

Impact:

- feature inputs are wider than necessary
- snapshot refresh behavior is centralized in shell
- changing workspace loading can affect unrelated pages

### 4. Workspace UI Has Mixed Responsibilities

`workspace_picker_sheet.dart` contains page-level navigation, modal forms, directory browsing, row rendering, and small reusable controls.

Impact:

- add-workspace fixes risk affecting legacy picker behavior
- button styling changes happen in a file that also owns directory browsing
- workspace list and workspace creation do not have separate state boundaries

### 5. Debug Helpers Construct Private Widgets

Tests use preview helpers that instantiate private feature widgets directly.

Impact:

- changing a private constructor requires updating tests even when public behavior is stable
- preview builders duplicate app state setup
- tests validate implementation shape as much as user-visible behavior

## Current Change Pressure Example

The recent workspace add bug shows the architectural pressure:

Changing the behavior of one `+` button touched or threatened to touch:

- workspace list UI
- add workspace sheet
- workbench selected workspace state
- shell snapshot refresh
- debug preview constructors
- widget tests

That is a sign that creation flow, selected workspace state, and app snapshot refresh are not isolated behind a stable boundary.

## What Is Good About the Current State

- The old monolithic `main.dart` is gone.
- Features are at least physically discoverable by directory.
- Protocol models and HTTP clients are already separate importable modules.
- Conversation reducer logic is separated enough to unit test.
- The workspace-first behavior now has widget coverage.
- There is a clear next step: turn physical file boundaries into real Dart library boundaries.

## What Is Weak About the Current State

- `part` files prevent true feature encapsulation.
- Workbench owns too many workflows.
- Shell owns too much data loading.
- UI widgets often depend on broad app-private types.
- Shared widgets are not governed by usage rules.
- Debug helpers are coupled to implementation details.
- Workspace creation lacks a dedicated controller/state boundary.

## Architecture Smell Summary

| Smell | Current Example | Effect |
| --- | --- | --- |
| Physical split without module boundary | `app.dart` plus many `part` files | Any private class can become cross-file dependency |
| God state owner | `_CodingWorkbenchPage` | Workspace, session, and conversation changes collide |
| Broad view model | `_AppSnapshot` | Features receive more data than they need |
| Mixed feature/component file | `workspace_picker_sheet.dart` | Small UI changes risk unrelated flows |
| Test helper leakage | `debug_helpers.dart` builds private widgets | Constructor churn breaks tests |
| Shared junk drawer risk | `shared_widgets.dart` | Reuse is convenient but ownership is vague |

## Immediate Architectural Question

The next architecture decision is not where to move another widget. The next decision is what boundary should become real first.

The most valuable first boundary is likely the Coding feature boundary:

```text
features/coding/
  public page API
  workspace navigation state
  session list state
  conversation state
  add workspace flow
```

Shell should depend on one public Coding entry point, not on its internal pages, callbacks, and private helper types.

