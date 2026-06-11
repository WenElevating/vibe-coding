# Coding Nested Navigation Design

## Problem

The Coding surface currently uses an internal `_listMode` state machine to switch between workspace list, workspace session list, and conversation detail. Because these states are not real routes, Android system back and phone side-swipe gestures cannot understand the internal page hierarchy. From a subpage such as the session list or conversation page, system back can behave like an app-level exit instead of returning to the previous Coding page.

## Goals

- Make Coding page hierarchy match standard mobile navigation behavior.
- System back or side-swipe should move one level up inside Coding before exiting the app.
- Preserve the existing bottom-tab shell and avoid rewriting the whole app router.
- Keep Coding business state, active conversation state, pollers, and workspace cache in `CodingWorkbenchPageState`.
- Keep conversation pages immersive by hiding bottom navigation only on conversation detail.
- Make the structure easier to extend with future Coding subpages.

## Non-Goals

- Do not migrate the entire app to Navigator 2.0.
- Do not change daemon APIs, conversation persistence, or protocol models.
- Do not redesign the visual layout of workspace, session, or conversation pages.
- Do not move message state or poller ownership into route arguments.
- Do not implement deep links, notification-driven direct conversation open, or external URL routing in this change.
- Do not implement process-death route stack restoration beyond the current in-memory behavior.

## Current Flow

`MainTabsPage` owns the top-level tab shell. `CodingWorkbenchPage` currently renders one of three widgets from `_listMode`:

- `CodingWorkbenchListMode.workspaces` renders `WorkspaceListPage`.
- `CodingWorkbenchListMode.sessions` renders `CodingSessionListPage`.
- `CodingWorkbenchListMode.conversation` renders the conversation detail column.

This works visually, but it is not a route stack. Back gestures cannot pop `conversation` to `sessions` or `sessions` to `workspaces` unless custom interception is added everywhere.

## Proposed Architecture

Keep `MainTabsPage` as the top-level shell and introduce a nested `Navigator` only inside `CodingWorkbenchPage`. The nested navigator owns Coding's page stack with these named routes:

- `workspaces`
- `sessions`
- `conversation`

`CodingWorkbenchPageState` continues to own:

- selected adapter and workspace
- workspace list cache
- active run and conversation IDs
- conversation messages and events
- polling lifecycle
- local session additions
- error and trace ID state

Routes express visible page hierarchy only. They do not become the source of business data.

## Back Behavior

Top-level back handling lives in `MainTabsPage`. To avoid double consumption, the app shell owns system back dispatch with `PopScope(canPop: false)`. The nested Coding navigator must not independently handle system back through its own `PopScope` or `WillPopScope`. Coding page controls such as header back buttons may still call the nested navigator directly because those are explicit in-app actions, not system back gestures.

The back dispatch order is:

1. If an overlay route such as notifications, adapters, diagnostics, approval, or detail is open, close it first.
2. If the current tab is Coding, ask the Coding nested navigator to `maybePop()`.
3. If the Coding navigator cannot pop because it is already at `workspaces`, switch to Home tab.
4. If the current tab is any other non-Home tab, switch to Home tab.
5. If already on Home with no overlay, allow the app-level back action to exit.

Implementation note: because `canPop` is false at the shell, app exit should be explicit from the shell after the dispatch logic determines there is no internal back target. The nested navigator is only invoked once per system back event.

Coding route behavior:

- `conversation` pops to `sessions`.
- `sessions` pops to `workspaces`.
- `workspaces` cannot pop and delegates to the parent shell.

## Flow Mapping

Selecting a workspace sets `_selectedWorkspace`, marks the workspace as confirmed for session creation, and pushes or replaces the nested route with `sessions`.

Opening an existing session performs all asynchronous validation and data preparation before route mutation. It cancels any current poller, resets active conversation view state, stores the selected run/conversation fields, polls any required initial events, and only then pushes `conversation`. If preparation fails, the current route remains visible and the existing traceable error card is shown there.

Starting a new session from the session list follows the same rule: daemon creation and active state setup happen before `conversation` is pushed. Failed starts keep the user on `sessions` and show the traceable error without a transient empty conversation page.

The route stack is constrained to a linear canonical order: `workspaces -> sessions -> conversation`. Cross-level pushes are not allowed in this change. Navigation helpers should enforce this by using replace/push-and-remove-until patterns when entering `sessions`, and by only pushing `conversation` from a valid `sessions` state. Back actions still use `popUntil` for robustness:

- The conversation header back button calls `popUntil(sessions)`.
- The session-list header back button calls `popUntil(workspaces)`.

If future deep links need to open a conversation directly, they must first define how to construct a valid synthetic stack. That is outside this change.

When the parent shell reselects the Coding tab, it normalizes Coding to a list route rather than preserving detail context. If a workspace is selected and confirmed, it returns to that workspace's `sessions` route. If no workspace is confirmed, it returns to `workspaces`. This means reselecting Coding from an active `conversation` intentionally returns to `sessions`, matching common bottom-tab "return to section root" behavior while preserving the active conversation in memory for reopening from the session list.

## Bottom Navigation Visibility

`MainTabsPage` should no longer infer bottom-nav visibility from `_listMode`. Instead, `CodingWorkbenchPage` reports whether the current nested route is list-like through the existing parent callback channel. The current `onSessionListChanged(bool open)` callback can be renamed for clarity if desired, but the communication shape should remain a direct callback from Coding to the shell, not an `InheritedWidget` or cross-tree global state.

The nested navigator installs a route observer or equivalent route-change hook. Whenever the top Coding route changes, it computes list visibility and invokes the callback only when the value changes, avoiding redundant shell rebuilds.

Route visibility rules:

- `workspaces`: bottom navigation visible.
- `sessions`: bottom navigation visible.
- `conversation`: bottom navigation hidden.

This preserves the current immersive conversation page while making the source of truth the route stack.

## Migration Plan

`CodingWorkbenchListMode` can be removed if no remaining tests or helpers need it. If deletion creates a large unrelated churn, keep a small route-name-to-state adapter temporarily, but do not let `_listMode` remain the source of page hierarchy.

`CodingWorkbenchController` helpers that only exist to transform `_listMode` should be updated to route-name concepts or removed with their tests.

The migration should avoid broad visual edits and keep page widgets reusable: `WorkspaceListPage`, `CodingSessionListPage`, and the conversation detail body remain the route contents.

## Error Handling

If the nested navigator receives a request to open `sessions` without a valid selected workspace, it should fall back to `workspaces` rather than rendering an invalid session list.

If a conversation open fails, keep the user on the previous route and show the existing traceable error card behavior. Async work must complete before pushing `conversation`; do not push an empty detail route and then pop it on failure.

System back should never cancel an active CLI run. It only changes visible pages. Existing explicit cancel behavior remains unchanged.

Screen rotation and process recreation use the same in-memory behavior as the current implementation. If Flutter rebuilds the widget tree without process death, the current route and business state should remain alive with the `CodingWorkbenchPageState`. If the OS kills the process, the app may restart at `workspaces`; durable route restoration is outside this change.

## Testing

- Widget test: selecting a workspace pushes `sessions`.
- Widget test: opening or starting a conversation pushes `conversation` and hides the bottom navigation.
- Widget test: system back from `conversation` returns to `sessions` and shows bottom navigation.
- Widget test: system back from `sessions` returns to `workspaces`.
- Widget test: system back from `workspaces` returns to Home tab instead of exiting.
- Widget test: overlay route closes before Coding nested navigation handles back.
- Widget test: system back invokes nested `maybePop()` once and does not double-pop from `conversation` to `workspaces`.
- Widget test: reselecting the Coding tab while on `conversation` returns to `sessions`, not `conversation` and not `workspaces` when a workspace is confirmed.
- Regression test: active polling is not cancelled merely by popping from conversation to sessions unless existing lifecycle rules already cancel it.

## Self-Review

- No placeholder requirements remain.
- The design is scoped to Coding navigation and parent back dispatch only.
- The route stack becomes the page hierarchy source of truth, which addresses the root extensibility concern.
- Business state remains in `CodingWorkbenchPageState`, avoiding overloading route arguments with mutable runtime data.
