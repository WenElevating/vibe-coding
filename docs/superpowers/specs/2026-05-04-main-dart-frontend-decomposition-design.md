# Main Dart Frontend Decomposition Design

Date: 2026-05-04
Status: Draft for user review
Scope: Flutter mobile frontend structure, `main.dart` decomposition, widget/module boundaries, test helper exports

## 1. Problem

The Flutter frontend has grown around `mobile/lib/main.dart`, which is currently responsible for application bootstrapping, theme configuration, shell navigation, data polling, workbench rendering, workspace/session selection, settings pages, diagnostics pages, shared visual atoms, and test/debug helpers.

`main.dart` is now over 6000 lines and contains dozens of unrelated widgets and helpers. This makes local reasoning difficult, increases the chance of accidental coupling, and forces unrelated UI work to edit the same file. The existing `src/models`, `src/services`, and `src/state` directories already provide a partial foundation, so the next step should focus on presentation-layer boundaries rather than rewriting data or state infrastructure.

## 2. Goals

- Reduce `main.dart` to a small application entry point.
- Split frontend presentation code into cohesive modules with clear ownership.
- Preserve current user-visible behavior during the first refactor pass.
- Keep existing daemon clients, protocol models, and reducer/state files in place.
- Make feature modules communicate through explicit widget inputs, callbacks, and shared state/model types.
- Keep test-facing debug and preview helpers available through stable public imports.
- Avoid new dependencies and avoid a state-management rewrite.

## 3. Non-Goals

- Do not redesign the visual UI.
- Do not change daemon APIs or protocol shapes.
- Do not replace the current polling and state-update mechanism.
- Do not introduce Provider, Riverpod, Bloc, or another state-management package.
- Do not deeply rewrite feature behavior while extracting files.
- Do not split platform build configuration.

## 4. Chosen Approach

Use a feature-oriented decomposition with a small amount of boundary cleanup.

The first implementation pass should move related widgets and helpers into `app/`, `shell/`, `features/`, `widgets/`, and `testing/` modules while keeping behavior equivalent. This approach was chosen over a mechanical file split because the goal is high cohesion and low coupling, not merely smaller files. It was chosen over a full clean-architecture rewrite because the current app is best served by incremental presentation boundaries before deeper state or domain changes.

## 5. Target Structure

The target structure under `mobile/lib/src/` should be:

```text
app/
  app.dart
  app_localization.dart
  app_theme.dart
shell/
  mobile_shell.dart
  shell_routes.dart
  top_bar.dart
  bottom_nav.dart
features/
  workbench/
    coding_workbench_page.dart
    coding_composer.dart
    workbench_messages.dart
    workbench_event_cards.dart
    workbench_presenter.dart
    markdown_body.dart
  sessions/
    coding_session_list_page.dart
    session_cards.dart
    session_helpers.dart
  workspace_picker/
    workspace_picker_sheet.dart
    directory_browser_sheet.dart
    workspace_rows.dart
  settings/
    settings_page.dart
    settings_widgets.dart
  run_detail/
    run_detail_page.dart
    run_detail_widgets.dart
  adapters/
    adapters_page.dart
  notifications/
    notifications_page.dart
  diagnostics/
    diagnostics_page.dart
widgets/
  cards.dart
  buttons.dart
  badges.dart
  inputs.dart
  effects.dart
testing/
  debug_helpers.dart
  widget_previews.dart
```

The exact file set can be adjusted during implementation when a file would be too small or when two widgets are only meaningful together. The important boundary is ownership: feature-specific widgets stay in their feature folder, and cross-feature visual atoms stay in `widgets/`.

## 6. Module Responsibilities

### 6.1 App Layer

`app/app.dart` owns `LanAiCliControlApp` and configures `MaterialApp`.

`app/app_theme.dart` owns color constants, font fallback, and `ThemeData` creation. Feature modules should use exported theme constants or theme extension helpers instead of redefining palette values.

`app/app_localization.dart` owns locale constants and localization delegates.

`mobile/lib/main.dart` should only import `src/app/app.dart`, call `runApp`, and remain easy to inspect.

### 6.2 Shell Layer

`shell/mobile_shell.dart` owns top-level composition and route selection only. Its job is to assemble the app, wire callbacks, and choose which page is shown.

Long-lived polling, daemon-client lifecycle management, and snapshot refresh loops should move into dedicated service/controller classes under `src/services/` or `src/state/` so the shell does not become the new monolith.

The shell may depend on `src/services`, `src/state`, `src/models`, `src/app`, and public feature page widgets. It must not import feature-internal leaf widgets such as event cards or row widgets.

`shell/shell_routes.dart` owns the current route/page enum and route metadata. Navigation widgets should consume route specs instead of duplicating labels and icons.

### 6.3 Feature Modules

Feature modules own their page-level widgets and feature-specific presentation helpers.

The workbench module should contain conversation rendering, composer UI, markdown rendering, command/diff/approval/question/system/thinking cards, pending/running indicators, and message mapping helpers.

`approval_page.dart` belongs under `features/workbench/` because approval requests are rendered from workbench conversation state and use the same `ConversationSummary`/event data path. The approval UI should be a workbench sub-feature, not a peer module.

The sessions and workspace-picker modules should contain session list/cards, workspace selection, first-run workspace flows, directory browsing, and related row widgets.

Settings, run detail, adapters, notifications, and diagnostics can initially remain page-oriented modules with local widgets beside each page. They can be split further only when a file becomes difficult to reason about.

If `run_detail` later needs workbench-owned data helpers, it should consume them through shared `src/state`/`src/models` types or a small explicit helper, not by importing workbench internals.

### 6.4 Shared Widgets

Shared widgets must stay presentation-only. They can accept simple values and callbacks, but must not create daemon clients, poll data, or inspect feature-specific state machines.

Good shared widget candidates include glass cards, metric cards, pills, status badges, mini inputs, action buttons, hairlines, glows, dots, and simple animated accents.

If a widget is used by only one feature, keep it inside that feature even when it looks generic. `widgets/` is only for presentation atoms used by two or more features.

If a widget requires a `ConversationSummary`, `RunSummary`, or feature-specific enum to render correctly, it belongs in a feature module rather than `widgets/`.

### 6.5 Testing Surface

`testing/debug_helpers.dart` should expose the current `@visibleForTesting` debug functions that tests need for reducers, message mapping, approval visibility, polling decisions, and session merge behavior.

`testing/widget_previews.dart` should expose preview builders currently defined in `main.dart`.

Tests should import these stable testing modules instead of importing large feature implementation files. Existing test behavior should remain equivalent.

## 7. Dependency Rules

- `main.dart` may import only the app entry module.
- `app/` may import Flutter, localization packages, app theme/localization, and the shell page.
- `shell/` may import app infrastructure, lifecycle controllers, state/models, shared widgets, and public feature page widgets.
- `features/*` may import app theme/localization, shared widgets, and state/model/service types when needed.
- `widgets/` may import Flutter and app theme only.
- `testing/` may import feature internals when necessary, but production modules must not import `testing/`.
- Feature modules must not import another feature module's files. Feature-to-feature navigation must go through shell callbacks or route enums.
- If sharing is needed, promote the widget to `widgets/` or pass data through a page-level interface.

## 8. Naming and Visibility

Most classes currently use private `_ClassName` names because they live in one file. Moving them across files requires visibility cleanup.

Rules:

- Page-level widgets should become public and descriptive, such as `CodingWorkbenchPage`, `CodingSessionListPage`, and `SettingsPage`.
- Feature leaf widgets can be public when consumed across files in the same feature, using a feature prefix where helpful, such as `WorkbenchMessageCard`.
- Shared visual atoms should use app-level names when generic, such as `AppGlassCard`, `AppPill`, or `AppStatusBadge`.
- Implementation helpers that remain within one file should stay private.
- Each feature may have at most one barrel file, and it may export only page-level widgets or other top-level entry widgets.
- Leaf widgets, helpers, and state adapters must not be re-exported from feature barrels.
- Avoid broad barrel exports that recreate a hidden monolith. Keep barrels optional and narrow.

## 9. Migration Strategy

The implementation should proceed in behavior-preserving slices:

1. Extract app theme, localization, and app entry so `main.dart` becomes a thin launcher.
2. Extract shell routing and navigation widgets while keeping top-level state behavior unchanged.
3. Extract shared visual atoms that have no service/state dependencies.
4. Extract workbench in this order: message cards and transcript helpers first, composer second, event cards third, approval UI last.
5. Keep the first workbench pass file-moving only; preserve public/private shapes until the feature compiles cleanly.
6. If a moved workbench widget needs shell-owned state, pass that state in from the page boundary instead of importing shell internals.
7. Extract session and workspace-picker modules.
8. Extract remaining page modules for settings, run detail, adapters, notifications, and diagnostics.
9. Move test/debug helpers and update tests to import the new testing surface.
10. Run formatting, static analysis, and Flutter tests after the final slice.

Each slice should keep the app compiling. If a slice becomes too large, split it by feature file ownership rather than by mechanical line count.

## 10. Error Handling

This refactor must preserve current error behavior:

- Connection failures still render the existing connection error UI.
- Daemon and conversation client exceptions keep the same user-facing handling.
- Empty conversation completion diagnostics remain available.
- Approval-response polling behavior remains unchanged.
- Directory browsing and workspace picker errors remain local to their sheets.

Any discovered error-handling cleanup should be documented as follow-up unless it is required to preserve behavior after extraction.

## 11. Testing and Verification

Verification should use existing checks:

- `cd mobile && dart format lib test`
- `cd mobile && flutter analyze`
- `cd mobile && flutter test`

The expected evidence is that all existing tests still pass and static analysis reports no new errors. If tests fail because they import old `main.dart` helpers, update them to import `src/testing/debug_helpers.dart` or `src/testing/widget_previews.dart` without changing the assertions' intent.

## 12. Risks and Mitigations

- Risk: Renaming private widgets can create many import and analyzer errors. Mitigation: migrate feature by feature and run analyzer after broad extraction.
- Risk: Shared widgets can become a dumping ground. Mitigation: only promote widgets that are truly feature-agnostic and used by more than one feature.
- Risk: Barrel exports can hide coupling. Mitigation: keep barrels small and optional.
- Risk: Workbench extraction may touch many tests. Mitigation: preserve a dedicated testing surface for debug helpers and previews.
- Risk: StatefulWidget migration can break keys, animation state, input text, or scroll position. Mitigation: preserve keys during extraction and verify scrolling, text entry, and animation continuity on device after each stateful slice.
- Risk: Behavior drift during cleanup. Mitigation: avoid state-management changes and keep existing reducer/client APIs intact.

## 13. Approval Criteria

This design is ready for implementation when:

- The user agrees to the feature-oriented structure.
- The first implementation plan is limited to behavior-preserving decomposition plus small boundary cleanup.
- The plan keeps current state/services/protocol layers stable.
- The plan includes test and analyzer verification before completion.
