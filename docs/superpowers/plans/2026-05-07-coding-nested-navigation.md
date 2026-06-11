# Coding Nested Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Coding's `_listMode` page switcher with a nested Navigator so system back and side-swipe gestures navigate up the Coding hierarchy before exiting the app.

**Architecture:** `MainTabsPage` owns app-level `PopScope` dispatch and delegates one system-back event to the Coding nested navigator when the Coding tab is active. `CodingWorkbenchPageState` keeps business state while its nested `Navigator` owns the visible route stack: `workspaces -> sessions -> conversation`.

**Tech Stack:** Flutter widgets, nested `Navigator`, `GlobalKey`, `PopScope`, existing widget tests.

---

### Task 1: Coding Nested Navigator

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_controller.dart`
- Test: `mobile/test/widget_test.dart`
- Test: `mobile/test/coding_workbench_controller_test.dart`

- [ ] Add route constants for `workspaces`, `sessions`, and `conversation`.
- [ ] Add a nested `Navigator` with a private `GlobalKey<NavigatorState>` inside `CodingWorkbenchPageState`.
- [ ] Replace `_listMode` rendering with route builders for the three existing page bodies.
- [ ] Keep business state fields in `CodingWorkbenchPageState`.
- [ ] Convert workspace selection to set selected workspace, mark confirmation, and normalize stack to `workspaces -> sessions`.
- [ ] Convert session open/new session success to prepare state first, then normalize stack to `workspaces -> sessions -> conversation`.
- [ ] Convert in-page back buttons to `popUntil` the intended route.
- [ ] Notify `onSessionListChanged` only when top route changes between list routes and conversation.

### Task 2: Shell Back Dispatch

**Files:**
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/pages/coding/coding_page.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] Pass a `GlobalKey<CodingWorkbenchPageState>` from `MainTabsPage` through `CodingPage` into `CodingWorkbenchPage`.
- [ ] Wrap `MainTabsPage` scaffold in `PopScope(canPop: false)`.
- [ ] Implement app-level back dispatch: close overlay, then Coding `maybePop`, then switch non-home tabs to Home, then exit from Home.
- [ ] Implement Coding tab reselection to normalize Coding to `sessions` when a workspace is confirmed, otherwise `workspaces`.
- [ ] Ensure one system back event calls Coding `maybePop()` at most once.

### Task 3: Tests and Verification

**Files:**
- Modify: `mobile/test/widget_test.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`

- [ ] Update tests that assert page keys to work with nested Navigator.
- [ ] Add widget test: workspace selection opens sessions.
- [ ] Add widget test: conversation detail hides bottom navigation.
- [ ] Add widget test: system back from conversation returns to sessions.
- [ ] Add widget test: system back from sessions returns to workspaces.
- [ ] Add widget test: system back from workspaces returns to Home.
- [ ] Add widget test: Coding tab reselection from conversation returns to sessions.
- [ ] Run focused widget tests if Flutter tooling responds.

## Self-Review

- Spec coverage: nested routes, shell-owned back dispatch, tab reselection, bottom-nav visibility, async-before-push, and tests are covered.
- Placeholder scan: no placeholder task remains.
- Scope: only Coding navigation and shell back dispatch are changed; daemon and protocol remain untouched.
