# Mobile UI Layering Design

Date: 2026-05-05

## Goal

Make the mobile UI read top-down instead of shell-driven. The app entry should own only app bootstrap, while the UI layer owns page composition, tab navigation, and page hierarchy.

## Current Problem

`mobile/lib/src/shell/mobile_shell.dart` currently mixes three concerns:

- root UI composition and loading/error framing
- top-level navigation and tab selection
- feature page assembly for home, runs, queue, coding, and settings

It also knows too much about feature internals, especially the coding flow and session-list open state. That makes UI changes ripple across unrelated pages.

## Decision

Use a dedicated `src/ui/` layer as the top-down UI tree.

### Top-level structure

```text
LanAiCliControlApp
└── MobileUi
    ├── MobileUiFrame
    ├── MobileLoadingPage
    ├── MobileConnectionErrorPage
    └── MainTabsPage
        ├── HomePage
        ├── RunsPage
        ├── QueuePage
        ├── CodingPage
        └── SettingsPage
```

### Coding sub-tree

```text
CodingPage
├── WorkspaceListPage
└── WorkspaceSessionsPage
    ├── SessionListPage
    └── ConversationPage
        ├── Composer
        ├── ConversationMessages
        └── ApprovalPanel
```

## Module Boundaries

### `src/ui/`

Owns:

- root UI orchestration
- top-level tab navigation
- loading and connection error pages
- the phone frame / shell chrome
- top-level pages

Does not own:

- Daemon API orchestration
- app-wide data loading
- workbench message/event transformation
- feature-specific business logic

### `src/ui/pages/`

Owns the visible top-level pages:

- `home_page.dart`
- `runs_page.dart`
- `queue_page.dart`
- `settings_page.dart`
- `coding/coding_page.dart`
- `coding/workspace_list_page.dart`
- `coding/workspace_sessions_page.dart`
- `coding/conversation_page.dart`

These pages may use feature barrels, but they should not import feature internals directly.

### `src/features/`

Owns reusable business feature modules and subflows:

- `features/workbench/` for message rendering, composer, controller helpers, and approval flow support
- `features/workspace_picker/` for workspace list and selection UI primitives
- `features/sessions/` for session items, list view models, and session list rendering helpers
- `features/adapters/`, `features/diagnostics/`, `features/notifications/`, `features/run_detail/` for feature-specific pages and helpers

These modules are not top-level navigation owners.

## Navigation Model

1. `MobileUi` decides whether to show loading, error, or main tabs.
2. `MainTabsPage` owns the bottom navigation and tab switching.
3. Each top-level page owns its own internal sub-navigation.
4. `CodingPage` owns the workspace/session/conversation flow.

### Navigation rules

- Shell/UI root must not know about workspace/session details.
- Coding navigation must not be coordinated by the global shell.
- Run detail should belong to the Runs page flow, not a global shell overlay.
- Approval UI should be owned by the coding/conversation flow unless a future global approval center is introduced.

## Dependency Rules

- `app` may import `ui`.
- `ui` may import `features`, `widgets`, `theme`, `models`, `services`, and `state`.
- `features` may import shared layers, but not `ui`.
- Shared layers must not import feature pages.

## Migration Scope

This design is UI-only.

Not in scope:

- splitting Daemon snapshot loading
- changing conversation polling
- rewriting workbench business state beyond what is needed for UI ownership
- changing the protocol model

## Risks

- `mobile_shell.dart` currently carries several page implementations; moving them without changing behavior requires careful extraction.
- The coding flow still mixes UI state and business state, so the first UI split should preserve behavior and defer deeper controller work.
- `AppSnapshot` is still broad; this design intentionally does not solve data-loading granularity yet.

## Acceptance Criteria

- `app.dart` only composes the root UI entry.
- Top-level pages live under `src/ui/pages/`.
- `MobileUi` owns loading/error/main-tab composition.
- `MainTabsPage` owns tab navigation.
- `CodingPage` owns workspace/session/conversation page hierarchy.
- `shell` no longer owns concrete feature page implementations.

