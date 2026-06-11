# Mobile Empty Workspace App ViewModel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the mobile app to connect successfully when the daemon returns an empty workspace list, then render the workspace picker empty state instead of a connection failure.

**Architecture:** Start with the smallest safe slice of the approved AppViewModel design. Keep the existing shell mostly intact, but introduce a bootstrap model that separates daemon connection success from workspace availability. `MainTabsPage` receives connected bootstrap data whose `workspaces` may be empty and renders Coding/workspace selection when no current workspace exists.

**Tech Stack:** Flutter, ChangeNotifier/MVVM, existing DaemonClient repositories, `flutter_test`.

---

## File Structure

- Modify `mobile/lib/src/domain/models/daemon_initial_data.dart`: make selected workspace optional in connection bootstrap data.
- Modify `mobile/lib/src/domain/models/connected_app_session.dart`: keep the session shape but allow bootstrap data without selected workspace.
- Modify `mobile/lib/src/shell/app_snapshot.dart`: stop using `workspaces.first` in bootstrap; add optional conversion helpers and a placeholder-free way to represent no selected workspace.
- Modify `mobile/lib/src/ui/main_tabs_page.dart`: accept bootstrap data with nullable selected workspace and render Coding/workspace selection for the empty catalog case.
- Modify `mobile/lib/src/ui/view_models/main_tabs_view_model.dart`: hold optional bootstrap workspace data and guard workspace-scoped updates.
- Modify `mobile/lib/src/ui/pages/home_page.dart` and `mobile/lib/src/ui/pages/settings_page.dart` only if needed to avoid rendering workspace-scoped pages without a selected workspace.
- Modify tests in `mobile/test/app_snapshot_bootstrap_test.dart`, `mobile/test/daemon_connection_workflow_test.dart`, and `mobile/test/widget_test.dart` for empty workspace behavior.

## Task 1: Lock empty workspace bootstrap behavior

**Files:**
- Test: `mobile/test/app_snapshot_bootstrap_test.dart`
- Modify: `mobile/lib/src/shell/app_snapshot.dart`
- Modify: `mobile/lib/src/domain/models/daemon_initial_data.dart`

- [ ] **Step 1: Write the failing bootstrap test**

Add a test where `listWorkspaces()` returns an empty list and `AppSnapshot.loadBootstrap()` does not throw. Expected state: `workspaces` is empty and no workspace-scoped calls are made.

- [ ] **Step 2: Run the focused test**

Run with mirrors:
`cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\app_snapshot_bootstrap_test.dart`

Expected before implementation: fail with `Bad state: No element`.

- [ ] **Step 3: Implement nullable selected workspace in bootstrap**

Change bootstrap loading so it returns valid daemon-level data when `workspaces.isEmpty`. Do not create a fake workspace. Workspace-scoped detail remains unavailable until a workspace exists.

- [ ] **Step 4: Run focused test again**

Expected after implementation: `app_snapshot_bootstrap_test.dart` passes.

## Task 2: Let connection succeed with empty catalog

**Files:**
- Test: `mobile/test/daemon_connection_workflow_test.dart`
- Modify: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart`
- Modify: `mobile/lib/src/domain/models/connected_app_session.dart`

- [ ] **Step 1: Add workflow regression test**

Test that connection succeeds when the initial data loader returns empty workspaces and does not save a failed connection state.

- [ ] **Step 2: Implement the minimal workflow compatibility changes**

Keep health failures as connection failures. Treat empty workspaces as successful initial data.

- [ ] **Step 3: Run workflow tests**

Run with mirrors:
`cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\daemon_connection_workflow_test.dart`

## Task 3: Render empty workspace UI after connection

**Files:**
- Test: `mobile/test/widget_test.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/view_models/main_tabs_view_model.dart`
- Modify: `mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart` if an empty list affordance is missing.

- [ ] **Step 1: Add widget regression test**

Render connected shell with `workspaces: []`. Expect the workspace list route to show and expose the add workspace action. Expect no connection failure copy.

- [ ] **Step 2: Implement shell rendering for empty catalog**

When connected data has no selected workspace, render the Coding workspace list as the useful first screen. Do not render Home or Settings content that requires `data.workspace`.

- [ ] **Step 3: Run focused widget test**

Run with mirrors:
`cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\widget_test.dart --plain-name "connected app renders empty workspace state"`

## Task 4: Verification

**Files:**
- No code changes unless verification fails.

- [ ] **Step 1: Run architecture import check**

`cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& dart run tool/check_architecture_imports.dart`

- [ ] **Step 2: Run focused tests**

`cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\app_snapshot_bootstrap_test.dart test\daemon_connection_workflow_test.dart`

- [ ] **Step 3: Report any first-attempt timeout**

If a Flutter/Dart command times out on first attempt, stop retrying and give the exact command to run manually.
