# Mobile Part Import Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mobile UI's app-wide Dart `part` library with explicit imports, real feature barrels, and compiler-enforced module boundaries.

**Architecture:** Migrate from stable foundations to risky workflows: theme first, shared widgets second, shell snapshot third, then leaf features, workspace picker, sessions, workbench, testing, and final app cleanup. Keep import-only migration separate from behavior changes and controller rewrites.

**Tech Stack:** Flutter, Dart libraries/imports, existing widget tests, existing `DaemonClient`, existing protocol models, no new dependencies.

---

## Preflight

**Files:**
- Read: `docs/superpowers/specs/2026-05-04-mobile-part-import-boundaries-design.md`
- Read: `docs/mobile-current-architecture.md`
- Read: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Confirm branch**

Run: `cd /d D:\AiProject\vibe-coding && git branch --show-current && git status --short`

Expected: current branch is `mobile-part-import-boundaries`, and status is clean before migration starts.

- [ ] **Step 2: Verify baseline**

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Expected: `flutter analyze --no-pub` reports `No issues found!`, and `flutter test --no-pub` reports `All tests passed!`.

---

### Task 1: Extract Theme Library

**Files:**
- Create: `mobile/lib/src/theme/theme.dart`
- Create: `mobile/lib/src/theme/app_colors.dart`
- Create: `mobile/lib/src/theme/app_typography.dart`
- Create: `mobile/lib/src/theme/app_localization.dart`
- Create: `mobile/lib/src/theme/app_theme.dart`
- Modify: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Create `app_colors.dart`**

Create public color constants matching the current `app.dart` values: `bg`, `panel`, `panelHi`, `stroke`, `purple`, `purple2`, `active`, `activePanel`, `activeStroke`, `green`, `amber`, `red`, `orange`, `text`, `muted`, and `faint`.

- [ ] **Step 2: Create `app_typography.dart`**

Move `Locale.fromSubtags(...)`, font fallback list, and base `TextStyle` into public constants named `zhHansCnLocale`, `appFontFallback`, and `appTextStyle`.

- [ ] **Step 3: Create `app_localization.dart`**

Move localization delegates into `appLocalizationsDelegates`.

- [ ] **Step 4: Create `app_theme.dart`**

Create `ThemeData buildAppTheme()` using the extracted colors and typography.

- [ ] **Step 5: Create `theme.dart` barrel**

Export `app_colors.dart`, `app_typography.dart`, `app_localization.dart`, and `app_theme.dart`.

- [ ] **Step 6: Update `app.dart`**

Import `../theme/theme.dart`, use `zhHansCnLocale`, `appLocalizationsDelegates`, and `buildAppTheme()` in `LanAiCliControlApp`. Keep temporary private aliases such as `const _bg = bg;` so existing `part` files still compile during early migration.

- [ ] **Step 7: Verify and commit**

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/app/app.dart mobile/lib/src/theme && git commit -m "Extract mobile theme tokens"`

---

### Task 2: Split Shared Widgets

**Files:**
- Create: `mobile/lib/src/widgets/widgets.dart`
- Create: `mobile/lib/src/widgets/page_scaffold.dart`
- Create: `mobile/lib/src/widgets/top_bar.dart`
- Create: `mobile/lib/src/widgets/buttons.dart`
- Create: `mobile/lib/src/widgets/cards.dart`
- Create: `mobile/lib/src/widgets/status.dart`
- Create: `mobile/lib/src/widgets/navigation.dart`
- Create: `mobile/lib/src/widgets/inputs.dart`
- Modify: `mobile/lib/src/widgets/shared_widgets.dart`
- Modify: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Classify `shared_widgets.dart` contents**

Move page shells to `page_scaffold.dart`, top bars and section labels to `top_bar.dart`, buttons to `buttons.dart`, card shells to `cards.dart`, status pills/dots to `status.dart`, bottom navigation to `navigation.dart`, and generic input/search widgets to `inputs.dart`.

- [ ] **Step 2: Create `widgets.dart` barrel**

Export the focused widget files. Do not export feature-specific leaf widgets.

- [ ] **Step 3: Rename exported shared widgets**

Drop the leading underscore only for widgets exported by `widgets.dart`, for example `_PageScroll` becomes `PageScroll`, `_TopBar` becomes `TopBar`, and `_PrimaryButton` becomes `PrimaryButton`.

- [ ] **Step 4: Add temporary compatibility wrappers**

Keep `shared_widgets.dart` as a temporary `part` compatibility file with private wrappers such as `_PageScroll extends PageScroll`. Delete these wrappers in the final cleanup task.

- [ ] **Step 5: Verify and commit**

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/widgets mobile/lib/src/app/app.dart && git commit -m "Split shared mobile widgets"`

---

### Task 3: Extract Shell Snapshot Types

**Files:**
- Create: `mobile/lib/src/shell/shell.dart`
- Create: `mobile/lib/src/shell/app_snapshot.dart`
- Create: `mobile/lib/src/shell/app_route.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`
- Modify: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Move route enum**

Create `RoutePage` in `app_route.dart` and replace `_RoutePage` references in `mobile_shell.dart`.

- [ ] **Step 2: Move snapshot type**

Move `_AppSnapshot` and its loading helpers from `mobile_shell.dart` into `app_snapshot.dart`, rename it to `AppSnapshot`, and import `protocol.dart` plus `daemon_client.dart` explicitly.

- [ ] **Step 3: Update shell snapshot references**

Replace `Future<_AppSnapshot>` with `Future<AppSnapshot>` and `_AppSnapshot.load(_client)` with `AppSnapshot.load(_client)`.

- [ ] **Step 4: Create `shell.dart` barrel**

Export `app_route.dart`, `app_snapshot.dart`, and `mobile_shell.dart`.

- [ ] **Step 5: Verify and commit**

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/shell mobile/lib/src/app/app.dart && git commit -m "Extract mobile shell snapshot types"`

---

### Task 4: Migrate Leaf Feature Pages

**Files:**
- Create: `mobile/lib/src/features/adapters/adapters.dart`
- Create: `mobile/lib/src/features/diagnostics/diagnostics.dart`
- Create: `mobile/lib/src/features/notifications/notifications.dart`
- Create: `mobile/lib/src/features/run_detail/run_detail.dart`
- Create: `mobile/lib/src/features/settings/settings.dart`
- Modify: leaf page files in those feature folders
- Modify: `mobile/lib/src/shell/mobile_shell.dart`
- Modify: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Migrate adapters**

Replace `part of '../../app/app.dart';` with explicit imports, rename `_AdaptersPage` to `AdaptersPage`, keep `_AdapterRow` private, and create `adapters.dart` exporting `adapters_page.dart`.

- [ ] **Step 2: Migrate diagnostics**

Replace `part of`, rename `_DiagnosticsPage` to `DiagnosticsPage`, keep row helpers private, and create `diagnostics.dart`.

- [ ] **Step 3: Migrate notifications**

Replace `part of`, rename `_NotificationsPage` to `NotificationsPage`, keep notice/tabs helpers private, and create `notifications.dart`.

- [ ] **Step 4: Migrate run detail**

Replace `part of`, rename `_RunDetailPage` to `RunDetailPage`, import `run_detail_state.dart`, and create `run_detail.dart`.

- [ ] **Step 5: Migrate settings**

Replace `part of`, rename `_SettingsPage` to `SettingsPage`, keep settings rows/cards private, and create `settings.dart`.

- [ ] **Step 6: Update shell and app**

Update `mobile_shell.dart` constructor calls to the public page names and remove these five feature `part` directives from `app.dart`.

- [ ] **Step 7: Verify and commit**

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/features mobile/lib/src/shell mobile/lib/src/app && git commit -m "Migrate leaf mobile features to imports"`

---

### Task 5: Migrate Workspace Picker Feature

**Files:**
- Create: `mobile/lib/src/features/workspace_picker/workspace_picker.dart`
- Create: `mobile/lib/src/features/workspace_picker/workspace_list_page.dart`
- Create: `mobile/lib/src/features/workspace_picker/add_workspace_sheet.dart`
- Create: `mobile/lib/src/features/workspace_picker/directory_browser_sheet.dart`
- Create: `mobile/lib/src/features/workspace_picker/workspace_rows.dart`
- Modify: `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/testing/debug_helpers.dart`
- Modify: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Move rows and display helpers**

Move workspace display helpers and row widgets into `workspace_rows.dart`. Public names are allowed only when used by public page files.

- [ ] **Step 2: Move workspace list page**

Move `_WorkspaceListPage` into `workspace_list_page.dart` and rename it to `WorkspaceListPage` with the same constructor shape.

- [ ] **Step 3: Move add workspace sheet**

Move `_AddWorkspaceSheet` into `add_workspace_sheet.dart` and rename it to `AddWorkspaceSheet`. Preserve the path-empty error behavior.

- [ ] **Step 4: Move directory browser**

Move `_DirectoryBrowserSheet` into `directory_browser_sheet.dart` and rename it to `DirectoryBrowserSheet`. Keep directory row widgets private.

- [ ] **Step 5: Create `workspace_picker.dart` barrel**

Export `workspace_list_page.dart` and `add_workspace_sheet.dart`. Do not export rows, mini inputs, or directory internals.

- [ ] **Step 6: Update workbench and previews**

Replace `_WorkspaceListPage` with `WorkspaceListPage` and `_AddWorkspaceSheet` with `AddWorkspaceSheet` in workbench and preview builders.

- [ ] **Step 7: Remove workspace picker part and verify**

Remove `part '../features/workspace_picker/workspace_picker_sheet.dart';` from `app.dart`, run verification, and commit.

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/features/workspace_picker mobile/lib/src/features/workbench mobile/lib/src/testing mobile/lib/src/app && git commit -m "Migrate workspace picker to imports"`

---

### Task 6: Migrate Sessions Feature

**Files:**
- Create: `mobile/lib/src/features/sessions/sessions.dart`
- Create: `mobile/lib/src/features/sessions/session_item.dart`
- Create: `mobile/lib/src/features/sessions/session_list_view_model.dart`
- Modify: `mobile/lib/src/features/sessions/coding_session_list_page.dart`
- Modify: `mobile/lib/src/features/workbench/workbench_messages.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/testing/debug_helpers.dart`
- Modify: `mobile/test/widget_test.dart`
- Modify: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Extract `SessionItem`**

Move `_SessionItem` into `session_item.dart` as public `SessionItem` with `RunSummary run`, nullable `ConversationSummary conversation`, and `String get id`.

- [ ] **Step 2: Extract merge helper**

Move `_mergeSessionItems` into `session_list_view_model.dart` as `mergeSessionItems`. Preserve current ordering and deduplication behavior exactly.

- [ ] **Step 3: Make session list page public**

Replace `part of`, rename `_CodingSessionListPage` to `CodingSessionListPage`, use explicit imports, and remove broad `AppSnapshot data` from the constructor unless it is still required.

- [ ] **Step 4: Create `sessions.dart` barrel**

Export `coding_session_list_page.dart`, `session_item.dart`, and `session_list_view_model.dart`.

- [ ] **Step 5: Update workbench, previews, and tests**

Replace `_SessionItem`, `_mergeSessionItems`, and `_CodingSessionListPage` with their public session feature names.

- [ ] **Step 6: Remove sessions part, verify, and commit**

Remove `part '../features/sessions/coding_session_list_page.dart';` from `app.dart`.

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/features/sessions mobile/lib/src/features/workbench mobile/lib/src/testing mobile/test mobile/lib/src/app && git commit -m "Migrate sessions feature to imports"`

---

### Task 7: Migrate Workbench Feature Import Boundary

**Files:**
- Create: `mobile/lib/src/features/workbench/workbench.dart`
- Modify: all files in `mobile/lib/src/features/workbench/`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`
- Modify: `mobile/lib/src/testing/debug_helpers.dart`
- Modify: `mobile/lib/src/app/app.dart`

- [ ] **Step 1: Make workbench page public**

Replace `part of`, add explicit imports, rename `_CodingWorkbenchPage` to `CodingWorkbenchPage`, and keep current state ownership intact.

- [ ] **Step 2: Migrate composer, messages, and event cards**

Replace `part of` in `coding_composer.dart`, `workbench_messages.dart`, and `workbench_event_cards.dart` with explicit imports. Export only what `CodingWorkbenchPage` needs.

- [ ] **Step 3: Migrate approval page**

Replace `part of`, rename `_ApprovalPage` to `ApprovalPage`, and keep approval leaf widgets private.

- [ ] **Step 4: Create `workbench.dart` barrel**

Export only `coding_workbench_page.dart` and `approval_page.dart`.

- [ ] **Step 5: Update shell and previews**

Update shell calls to `CodingWorkbenchPage` and `ApprovalPage`, and update preview builders to use public workbench APIs.

- [ ] **Step 6: Remove workbench parts, verify, and commit**

Remove all workbench `part` directives from `app.dart`.

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/features/workbench mobile/lib/src/shell mobile/lib/src/testing mobile/lib/src/app && git commit -m "Migrate workbench feature to imports"`

---

### Task 8: Migrate Shell and Testing Libraries

**Files:**
- Create: `mobile/lib/src/testing/testing.dart`
- Create: `mobile/lib/src/testing/preview_builders.dart`
- Modify: `mobile/lib/src/testing/debug_helpers.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`
- Modify: `mobile/lib/src/shell/shell.dart`
- Modify: `mobile/lib/src/app/app.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Make `MobileShell` independent**

Replace `part of '../app/app.dart';` with explicit imports for feature barrels, models, services, theme, widgets, `app_route.dart`, and `app_snapshot.dart`.

- [ ] **Step 2: Move preview builders**

Move widget preview builders from `debug_helpers.dart` into `preview_builders.dart`. Preview builders must import public feature barrels, not feature internals.

- [ ] **Step 3: Keep pure debug helpers separate**

Leave reducer or formatting debug helpers in `debug_helpers.dart` only if they do not construct private widgets.

- [ ] **Step 4: Create `testing.dart` barrel**

Export `debug_helpers.dart` and `preview_builders.dart`.

- [ ] **Step 5: Update package exports**

Update `lan_ai_cli_control.dart` to export `src/testing/testing.dart` instead of relying on app-wide part visibility.

- [ ] **Step 6: Remove shell/testing parts, verify, and commit**

Remove `part '../testing/debug_helpers.dart';` and `part '../shell/mobile_shell.dart';` from `app.dart`.

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/shell mobile/lib/src/testing mobile/lib/src/app mobile/lib/lan_ai_cli_control.dart mobile/test && git commit -m "Migrate shell and testing to imports"`

---

### Task 9: Remove App-Wide Part Compatibility

**Files:**
- Modify: `mobile/lib/src/app/app.dart`
- Modify: `mobile/lib/src/widgets/shared_widgets.dart`
- Modify: `mobile/lib/src/widgets/widgets.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`

- [ ] **Step 1: Delete remaining `part` directives**

Remove all remaining `part` directives from `app.dart`. `app.dart` should import only Flutter, `../shell/shell.dart`, and `../theme/theme.dart` unless a concrete app-level dependency remains.

- [ ] **Step 2: Delete temporary aliases**

Remove temporary app-private aliases like `_bg`, `_purple`, `_appTextStyle`, and `_appLocalizationsDelegates`. Each independent library must import `theme/theme.dart` directly.

- [ ] **Step 3: Delete shared widget compatibility wrappers**

Delete `shared_widgets.dart` if it only contains compatibility wrappers. If real widgets remain, move them to focused files and export them from `widgets.dart`.

- [ ] **Step 4: Audit forbidden dependencies**

Run: `cd /d D:\AiProject\vibe-coding && rg "part of|^part " mobile/lib/src && rg "../shell|../../shell" mobile/lib/src/features && rg "features/" mobile/lib/src/widgets mobile/lib/src/theme mobile/lib/src/models mobile/lib/src/services mobile/lib/src/state`

Expected: no app-wide part directives; no feature imports shell; no lower-level layer imports feature files.

- [ ] **Step 5: Verify and commit**

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib mobile/test && git commit -m "Remove app-wide mobile part library"`

---

### Task 10: Extract Workbench State Transitions

**Files:**
- Create: `mobile/lib/src/features/workbench/coding_workbench_state.dart`
- Create: `mobile/lib/src/features/workbench/coding_workbench_controller.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/features/workbench/workbench.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Create `CodingWorkbenchState`**

Create an immutable state object holding workspaces, selected workspace, list mode, local sessions, active run/conversation ids, selected adapter, error, and workspace-confirmed flag.

- [ ] **Step 2: Extract pure workspace transition helper**

Create `upsertAndSelectWorkspace(CodingWorkbenchState state, WorkspaceSummary workspace)` in `coding_workbench_controller.dart`. It must replace an existing workspace with the same id, append new workspaces, select the returned workspace, and set list mode to sessions.

- [ ] **Step 3: Add regression test for duplicate workspace id**

Add a test that starts with one workspace, calls `upsertAndSelectWorkspace` with the same id and a new name/path, and expects one workspace, selected updated workspace, and session-list mode.

- [ ] **Step 4: Replace page-local upsert logic**

Replace the local `_upsertWorkspace` implementation in `CodingWorkbenchPage` with the controller helper. Do not move polling in this task.

- [ ] **Step 5: Verify and commit**

Run: `cd /d D:\AiProject\vibe-coding\mobile && dart format lib test && flutter analyze --no-pub && flutter test --no-pub`

Commit: `cd /d D:\AiProject\vibe-coding && git add mobile/lib/src/features/workbench mobile/test && git commit -m "Extract workbench workspace state transitions"`

---

## Final Acceptance Checklist

- [ ] `rg "part of|^part " mobile/lib/src` reports no app-wide UI part directives.
- [ ] Every feature folder has exactly one public barrel file.
- [ ] Shell imports feature barrels, not feature internals.
- [ ] No feature imports shell.
- [ ] `widgets/`, `theme/`, `models/`, `services/`, and `state/` do not import feature files.
- [ ] `dart format lib test` completes successfully.
- [ ] `flutter analyze --no-pub` reports `No issues found!`.
- [ ] `flutter test --no-pub` reports `All tests passed!`.
- [ ] Manual QA confirms workspace list, workspace creation, session list, new session, active conversation, approval page, run detail, and settings still work.

