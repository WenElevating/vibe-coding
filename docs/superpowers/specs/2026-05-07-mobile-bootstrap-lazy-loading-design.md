# Mobile Bootstrap Lazy Loading Design

## Context

The mobile app currently connects to the daemon by running `AppSnapshot.load(client)`. That method does more than verify connectivity. It pairs the device, lists workspaces, chooses the first workspace, and then loads many workspace-heavy resources before the user can enter the app.

Current connection-time resources include:

- `health`
- `workspaces`
- current `workspace`
- `overview`
- `adapters`
- `runs`
- `conversations`
- `queue`
- `commandTemplates`
- `gitStatus`
- `diffs`
- `commits`
- `fileTree`
- `diagnostics`
- `extensions`

This creates the wrong scaling behavior. Workspace inspection, file tree loading, diagnostics, git diff, and commit loading can grow with repository size. A connection button should not wait on data that belongs to deeper pages.

## Decision

Use a two-tier loading model:

1. **Bootstrap snapshot** for connection and first home render.
2. **Page lazy loading** for workspace-heavy or page-specific data.

The selected bootstrap level is option B from the brainstorming discussion: enough data for the home Command Deck to be useful immediately, without loading heavy workspace scans.

## Goals

- Make daemon connection time independent from file count and Git history size.
- Enter the app after only minimal, home-critical data loads.
- Keep the home Command Deck useful on first render.
- Move page-specific heavy requests to the page that needs them.
- Keep failures local: a diagnostics failure should not block connection or kick the user back to the connection screen.

## Non-Goals

- Do not redesign the home page again.
- Do not add new dependencies or a global state-management library.
- Do not implement background sync for every page in this slice.
- Do not change daemon API contracts unless a small optional endpoint is clearly required.
- Do not make connection wait on Git, file tree, diagnostics, commits, diffs, extensions, or command templates.

## Bootstrap Snapshot

### Required Data

`AppSnapshot.loadBootstrap(client)` should load:

- `health`
- `workspaces`
- selected `workspace`
- `runs` scoped to the selected workspace
- global `conversations`
- global `queue`

This is enough for:

- current workspace identity
- Now Panel
- Cross-workspace interruption lane, to the extent available from conversations and queue
- Execution Stream based on current workspace runs
- Queue count

### Deferred Data

Bootstrap must not load:

- `overview`
- `adapters`
- `commandTemplates`
- `gitStatus`
- `gitDiff`
- `gitCommits`
- `fileTree`
- `diagnostics`
- `extensions`

### Default Values For Deferred Fields

`AppSnapshot` can remain the shared shell model if deferred fields receive safe empty defaults:

- `overview`: empty `ProjectOverview` for the selected workspace with zero counts and no recent files.
- `adapters`: empty list.
- `templates`: empty list.
- `gitStatus`: `null`.
- `diffs`: empty list.
- `commits`: empty list.
- `fileTree`: empty `FileTreeResponse`.
- `diagnostics`: available `false` with empty diagnostics.
- `extensions`: empty list.

The defaults must be visually honest. UI should not imply a clean Git tree or zero diagnostics if the relevant data has not been loaded. Where that distinction matters, page UI should show loading, unavailable, or deferred state.

## Connection Flow

`DaemonConnectionController` should use `AppSnapshot.loadBootstrap(client)` by default.

Flow:

1. Validate address and proxy settings.
2. Create `DaemonClient`.
3. Health probe.
4. Bootstrap snapshot load.
5. Save connection config.
6. Enter main app.

Connection timeout should return to `10s` after bootstrap is lightweight. If real devices still need more time after this change, investigate network or daemon latency rather than increasing the timeout again.

## Page Lazy Loading

### Home Page

Home should render immediately from bootstrap data.

Current behavior after this change:

- Now Panel: uses runs, conversations, queue.
- Interrupt Lane: uses conversations and queue; cross-workspace run summaries may be incomplete until a broader runs source exists.
- Execution Stream: uses current workspace runs.
- Workspace Signals: Git, diagnostics, and recent files should show a deferred or unknown state instead of pretending to be zero.

Optional follow-up: add a small non-blocking home signals loader for overview/git/diagnostics after first paint. This follow-up should not be part of the blocking connection path.

### Runs Page

Runs page can render bootstrap `runs` immediately. On page entry, it may refresh `client.listRuns(workspaceId: currentWorkspace.id)`.

### Queue Page

Queue page can render bootstrap `queue` immediately. On page entry, it may refresh `client.listQueue()`.

### Coding Page

Coding/workbench entry should own loading command templates and workspace/session/conversation data needed for starting work. Connection must not load `commandTemplates` just for this page.

### Settings Page

Settings should own loading diagnostics-like status that is only useful there:

- Git status
- Extensions
- Adapter details if needed
- Security/about details that are not already present in health

Until lazy data loads, settings should render a local loading, deferred, or unavailable row instead of relying on connection-time data.

### File, Git, Diagnostics, And Detail Pages

These pages should load their own heavy data:

- File tree loads on file page entry.
- Diagnostics load on diagnostics/status page entry.
- Git diff and commits load on the relevant Git/detail page entry.

Failures stay local to the page. They should not invalidate the daemon connection.

## Error Handling

Bootstrap failure:

- Stays on connection page.
- Shows connection failure, because the app cannot render the first workspace context.

Lazy page failure:

- Shows local inline error and retry affordance.
- Does not clear `DaemonConnectionController.client`.
- Does not clear the bootstrap snapshot.
- Does not navigate back to the connection page.

Deferred field access:

- Pages must distinguish between empty data and not-yet-loaded data where the distinction affects user trust.
- Existing pages can temporarily render empty defaults only if the label does not imply a verified state.

## Data Model Notes

`AppSnapshot.load(client)` can remain for tests or compatibility, but new production connection code should use `loadBootstrap`.

Recommended helpers:

- `AppSnapshot.loadBootstrap(DaemonClient client, {DaemonHealth? health})`
- `AppSnapshot.emptyDeferred(WorkspaceSummary workspace, DaemonHealth health, List<WorkspaceSummary> workspaces, ...)` if construction becomes noisy.

Avoid adding nullable fields across the entire app unless necessary. Safe defaults are lower-risk for this existing codebase, as long as UI labels do not misrepresent deferred values.

## Testing Strategy

Unit/widget tests should cover:

- `AppSnapshot.loadBootstrap` does not call heavy methods: `projectOverview`, `gitStatus`, `gitDiff`, `gitCommits`, `fileTree`, `codeDiagnostics`, `listExtensions`, `listCommandTemplates`, or `listAdapters`.
- `DaemonConnectionController` default snapshot loader uses bootstrap and still saves the connected config.
- Home renders from bootstrap defaults without connection status regressions.
- Workspace signal UI does not imply verified Git/diagnostic state when deferred fields are defaults.
- Lazy page failures are local when page loaders are introduced.

Manual verification:

- Start daemon.
- Connect from mobile.
- Confirm entry no longer waits on workspace file scans.
- Navigate to pages that need heavy data and confirm they load locally.

## Implementation Scope

This design should be implemented in small slices:

1. Add bootstrap snapshot loading and switch connection to it.
2. Adjust home workspace signals to represent deferred values honestly.
3. Add or update tests proving heavy methods are not called during bootstrap.
4. Add page lazy loaders only where existing pages visibly need deferred data after bootstrap.

If slice 4 grows too large, split it into separate page-specific follow-up plans.

## Open Decisions Resolved

- Bootstrap option B is selected.
- Connection should not load Git, file tree, diagnostics, diffs, commits, extensions, adapters, or command templates.
- Connection timeout should return to `10s` after bootstrap becomes lightweight.
- Heavy data belongs to the page that uses it.
