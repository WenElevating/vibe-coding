# Codex Tab Console Redesign

- Status: approved design
- Date: 2026-06-07
- Scope: mobile Codex tab UI redesign and read-only thread review

## Context

The mobile app is a LAN-first control surface for CLI coding tools. The bottom
navigation currently exposes Coding, Codex, and Settings. Settings remains a
global app settings surface and is not part of this redesign.

The Codex tab currently renders as a diagnostic-style `Codex app-server` page
with three internal tabs: History, Discovery, and Risk. It also defines a small
Codex-specific visual vocabulary in the feature widgets instead of using the
main app's restrained dark theme. The History rows show a chevron, but they do
not open a useful thread review surface.

Recent backend and daemon work already expose read-only app-server capabilities,
discovery data, workspace-scoped thread lists, thread reads, goals, turns, and
items through daemon-owned HTTP routes. The mobile redesign should productize
the safe read-only subset without exposing a raw app-server tunnel or adding
high-risk mutation controls.

## Goals

- Replace the Codex page's internal History, Discovery, and Risk tabs with a
  single scrollable Codex console overview.
- Keep the bottom navigation as Coding, Codex, and Settings.
- Make Recent sessions actionable by opening a same-page read-only thread
  detail view.
- Show thread details at an audit/review depth: summary plus simplified
  turns/items, not a full Workbench transcript and not raw JSON.
- Use the existing mobile design language: dark, restrained, dense, and aligned
  with Home and Workbench surfaces.
- Put all new user-visible strings behind Flutter localization.
- Preserve the project's Flutter layered architecture and MVVM boundaries.
- Avoid high-risk mutations in the first version.

## Non-Goals

- Do not remove or redesign the global Settings tab.
- Do not jump from Codex thread rows into Workbench in this version.
- Do not implement archive, unarchive, fork, rollback, goal editing, settings
  editing, plugin install, remote-control toggles, config writes, or other
  mutation flows.
- Do not expose raw JSON-RPC payloads or a generic app-server request tunnel to
  mobile.
- Do not implement a complete chat transcript renderer for app-server threads.
- Do not add new dependencies.

## Chosen Approach

Use a Codex Console plus same-page Thread Detail.

The Codex bottom tab opens an overview console. The overview gives the user the
current workspace context, runtime readiness, recent app-server sessions,
resource counts, and daemon-enforced safety boundaries. Tapping a recent thread
switches the Codex page into a local detail state with a back button. The detail
state reads and renders only stable daemon DTOs.

This approach directly addresses the current visual and interaction problem
without coupling app-server thread history to the main Workbench conversation
model.

## Architecture

The implementation must follow the existing mobile layered architecture and the
Flutter MVVM/Repository pattern.

### Layer Boundaries

- `mobile/lib/src/domain/models/codex_app_server_models.dart` owns clean,
  immutable domain models for Codex app-server overview and thread review data.
- `mobile/lib/src/domain/repositories/codex_app_server_repository.dart` remains
  the UI-facing capability boundary for app-server data.
- `mobile/lib/src/data/models/codex_app_server_models.dart` parses daemon DTOs
  into domain models. It may preserve raw maps only where the existing model
  already does, but UI must not depend on raw maps for display.
- `mobile/lib/src/data/repositories/codex_app_server_repository.dart` calls
  daemon HTTP routes and returns domain models.
- `mobile/lib/src/ui/features/codex_app_server/view_models/` owns
  `ChangeNotifier` ViewModels and immutable state snapshots.
- `mobile/lib/src/ui/features/codex_app_server/views/` owns lean page/view
  widgets.
- `mobile/lib/src/ui/features/codex_app_server/widgets/` owns feature-local
  visual components such as overview panels, thread rows, resource rows, and
  review timeline rows.

### ViewModel Rules

- Views must not fetch data directly.
- Views must not call repositories directly.
- ViewModels receive repositories through constructors.
- ViewModels expose immutable state snapshots and command methods such as
  `load`, `openThread`, and `returnToOverview`.
- Long-running async loads must use generation tokens or an equivalent guard so
  stale responses cannot overwrite newer workspace or selected-thread state.
- Disposal must suppress pending notifications.
- Workspace changes clear the selected thread before loading new workspace data.

### Use Case Rule

Do not add a UseCase unless the implementation needs reusable cross-repository
coordination. The first version is a single-repository read-only projection, so
the ViewModel can coordinate loading directly.

## Navigation Model

The bottom navigation remains:

```text
Coding / Codex / Settings
```

The Codex page has local navigation state:

```text
overview -> threadDetail -> overview
```

This is feature-local state, not a global route overlay. Back behavior inside
the Codex page should return from thread detail to overview before leaving the
Codex tab.

The selected thread detail state is not sticky across bottom-tab switches. When
the user leaves the Codex bottom tab for Coding or Settings and later returns
to Codex, the page should show the overview. This keeps a diagnostic review
state from feeling like a persistent global destination and avoids showing a
stale thread after the active workspace changes in another tab.

## Overview UI

The overview is a single scrollable console.

### Header

- Title: localized `Codex`.
- Subtitle: current workspace name with compact path when space allows.
- Status chip: localized `ready`, `syncing`, `busy`, or `unavailable`.
- If no workspace is selected, show a workspace-scoped empty state and do not
  render fake resource or thread data.

The status chip is a ViewModel-derived UI status, not a direct daemon heartbeat
field. Derive it from the Codex app-server overview load state:

- `syncing`: any overview load is currently in flight.
- `ready`: the latest overview load completed and capabilities were available.
- `busy`: the latest overview load failed with a recognized app-server busy or
  pool-limit condition.
- `unavailable`: capabilities cannot be loaded because app-server is disabled,
  unauthorized, not configured, or otherwise unavailable.

Unknown load failures should render the unavailable visual state with a
localized diagnostic detail.

### Status Panel

The status panel shows three compact metrics:

- `Threads`: count from the workspace thread list.
- `Resources`: count from model providers, MCP servers, skills, plugins, apps,
  and config availability.
- `Guarded`: count of unique app-server routes that are not read-only. This is
  the union of high-risk routes and approval-required routes, not a sum that
  double-counts routes that belong to both groups.

The panel should feel like a compact operational control surface, not a
marketing hero. Use dense labels, restrained color, and stable dimensions.

### Recent Sessions

Recent sessions replaces the current History tab.

Each row shows:

- thread title, falling back to a short thread id;
- compact workspace path or short thread id as supporting text;
- localized Open or Archived status;
- a clear affordance only when the row is actually tappable.

Tapping a row opens the same-page Thread Detail view. If the thread detail is
loading, show a localized loading state in the detail view or row. Do not render
a fake chevron for non-interactive rows.

### Runtime Resources

Runtime resources replaces the current Discovery tab as a lower-priority
overview section.

Rows:

- Models
- MCP Servers
- Skills
- Plugins
- Apps
- Config

Each row shows a localized label, short localized description, icon, and count
or availability state. This section is read-only in the first version.

### Safety Boundary

Safety boundary replaces the current Risk tab as a visible overview summary.

It shows:

- read-only route count;
- guarded route count, using the same unique-route definition as the Status
  Panel;
- approval-required route count, a subset of guarded routes;
- a localized note that enforcement is daemon-owned.

This section is explanatory and status-oriented. It does not expose mutation
buttons.

## Thread Detail UI

Thread detail is a same-page review view inside the Codex tab.

### Header

- Back icon button returns to overview.
- Title uses the thread title, falling back to a short thread id.
- Subtitle shows workspace context.

### Summary

Render:

- Open or Archived status;
- workspace name/path;
- thread id;
- goal summary if available;
- last updated time if the daemon DTO exposes a stable field.

Missing optional fields render as a localized "not provided" value. The UI must
not show `null`, empty strings, or raw object text.

### Turns And Items Timeline

Render a simplified review timeline from daemon-owned thread detail, turns, and
items DTOs.

Each timeline row should show:

- item or turn type;
- short title or summary;
- status or time when available;
- compact supporting metadata when useful.

This is not a full transcript renderer. It should help the user understand what
the app-server thread did without competing with Workbench.

### Partial States

- If summary loads and timeline data is empty, show a localized empty state for
  no reviewable events.
- If timeline loading fails after summary loads, keep the summary visible and
  show a local timeline error.
- If the selected thread no longer belongs to the active workspace, clear the
  detail state and return to overview.

## Internationalization

All new user-visible strings must be added to both:

```text
mobile/lib/l10n/app_en.arb
mobile/lib/l10n/app_zh.arb
```

No new display text should be hard-coded in widgets.

Required localization coverage includes:

- bottom navigation Codex label;
- page title and status chip labels;
- section titles and row descriptions;
- empty states;
- loading and error states;
- thread detail field labels;
- Open and Archived status;
- Safety Boundary labels;
- "daemon enforced" wording;
- "not provided" fallback.

Chinese copy must be complete for every new localization key added by the
implementation. Do not rely on a partial suggested vocabulary list.

English copy should use product-facing language. Avoid making the overview feel
like raw implementation diagnostics. `Recent sessions` is preferred in the
overview, while `Thread ID` is acceptable in the detail view.

## Visual Direction

Use the existing app theme and design primitives.

- Prefer `theme.bg`, `theme.panel`, `theme.panelHi`, `theme.stroke`,
  `theme.green`, `theme.amber`, `theme.purple`, and `theme.purple2`.
- Remove Codex-specific panel/accent dominance unless a local constant simply
  aliases an existing theme value.
- Keep surfaces dark, restrained, precise, and dense.
- Use cards only for meaningful panels or repeated list rows.
- Avoid nested cards.
- Avoid oversized hero layout.
- Keep text inside stable responsive constraints.
- Use icons as functional affordances, not decoration.

The result should feel related to Home and Workbench, not like a separate
diagnostics micro-app.

## Data Flow

Overview load:

```text
MainPage workspace update
  -> CodexAppServerViewModel.load(workspaceId)
  -> repository.loadCapabilities()
  -> repository.listThreads(workspaceId)
  -> repository.loadDiscovery()
  -> immutable overview state
  -> Codex overview widgets
```

Thread detail load:

```text
Recent session tap
  -> viewModel.openThread(workspaceId, threadId)
  -> repository.loadThreadReview(workspaceId, threadId)
  -> immutable selected thread review state
  -> Codex thread detail widgets
```

The repository can implement `loadThreadReview` by composing existing
workspace-scoped daemon routes for thread read, goal, turns, and items. Mobile
must consume daemon DTOs, not upstream app-server JSON-RPC shapes.

### Thread Review Aggregation

`loadThreadReview` should make error boundaries explicit:

- Thread read is required. If `readThread(workspaceId, threadId)` fails, the
  detail view enters a fatal detail error state and no stale thread summary is
  shown.
- Goal is optional. If `getThreadGoal` fails, render the thread summary without
  a goal and show a localized "goal unavailable" value or note. This does not
  make the detail view fail.
- Turns/items are timeline data. If turns cannot be listed, keep the summary
  visible and render a timeline-local error state. If item loading fails for
  some turns after turns were listed, render available turn rows and show the
  timeline as partial with a localized error note.
- A missing or empty turns/items response is not an error. It renders the
  localized empty timeline state.
- All failures must be generation-guarded so late partial responses cannot
  populate the selected thread after the user returns to overview, changes
  workspace, or opens another thread.

## Error Handling

Overview errors should be productized into localized categories where possible:

- busy;
- unavailable;
- unauthorized;
- unknown.

The UI should not display a full `DaemonClientException(...)` string as the
primary user-facing message. Unknown errors may include a short sanitized detail
line for diagnostics.

Thread detail errors are local to the detail state:

- thread detail summary failure shows a detail error with a back path;
- timeline failure keeps the summary visible;
- returning to overview never requires reloading the whole app;
- workspace changes clear stale selected thread state.

## Testing

Update or add focused tests.

### ViewModel Tests

Update `mobile/test/codex_app_server_view_model_test.dart` to cover:

- overview summary metrics;
- opening a thread loads review data;
- returning to overview clears selected thread detail state;
- workspace changes clear stale selected thread state;
- detail load failure does not corrupt overview state;
- overview load failure does not preserve stale workspace data.

### Model And Repository Tests

Update `mobile/test/codex_app_server_models_test.dart` to cover:

- parsing thread review DTOs;
- parsing goal, turn, and item summary fields used by UI;
- daemon route paths used by the thread review repository method.

### Widget Tests

Add or update widget tests to cover:

- overview renders localized section labels;
- no-workspace empty state;
- Recent sessions row opens thread detail;
- detail back button returns to overview;
- detail shows an empty timeline state when there are no reviewable events.

### Verification Commands

Implementation should run the relevant Flutter checks:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart test\codex_app_server_models_test.dart
dart run tool\check_architecture_imports.dart
dart analyze
```

Cross-platform command shape for CI or non-Windows shells:

```bash
cd mobile
flutter test --no-pub test/codex_app_server_view_model_test.dart test/codex_app_server_models_test.dart
dart run tool/check_architecture_imports.dart
dart analyze
```

If a Flutter or Dart command times out in this Windows/Codex environment, follow
the repository rule: stop retrying automatically after the first timeout and
give the user the exact command to run manually.

## Rollout

This redesign can be implemented as a mobile-only product surface over existing
daemon routes. If a stable thread review DTO is missing, add the narrow daemon
normalization needed for that DTO rather than exposing raw app-server JSON.

High-risk app-server controls remain out of scope until a separate approval and
mutation UX design exists.

## Open Decisions Resolved

- Scope is lightweight productization, not a pure visual pass and not a full
  mutation control center.
- Thread rows open a same-page detail view, not Workbench.
- Detail depth is review-level: summary plus simplified turns/items.
- All new user-visible strings are localized.
- Flutter architecture follows MVVM plus Repository boundaries.
