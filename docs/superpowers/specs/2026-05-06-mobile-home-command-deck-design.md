# Mobile Home Command Deck Design

## Context

The current mobile home page uses a familiar dashboard pattern: a title bar, three large colored metric cards, recent runs, quick actions, and a static approval preview. This makes the app feel generic and visually heavy. It also underuses the product domain: a mobile control plane for AI CLI work across trusted desktop workspaces.

The redesign should make the home page feel like a compact command deck. It should answer one question first: what needs attention now? It must preserve a current-workspace focus while still surfacing urgent signals from other workspaces.

## Goals

- Replace the generic overview-card layout with a refined mobile command surface.
- Keep the home page compact, precise, and aligned with the app's calm technical style.
- Prioritize actionable signals over static metrics.
- Support multiple workspaces without turning the first screen into a noisy global dashboard.
- Use existing snapshot data where possible, with one light data addition for cross-workspace run summaries.

## Non-Goals

- Do not redesign bottom navigation.
- Do not show connection state, daemon address, or scan controls on the home page.
- Do not build a complete per-workspace Git, diagnostics, or file summary model in this iteration.
- Do not add a decorative neon, glass, or large-card visual language.
- Do not add new dependencies.

## Product Register

This is a product UI surface. The visual language should be restrained: tinted dark neutrals, fine borders, small state accents, strong spacing discipline, and compact text hierarchy. The page should feel like an instrument panel for real work, not a marketing dashboard.

Scene: a developer checks a phone during an active coding session to see whether an AI CLI needs input, whether another workspace is blocked, and whether the current workspace is safe to continue. Dark, compact, and low-glare presentation is appropriate.

## Information Architecture

### 1. Workspace Command Bar

Purpose: establish the current execution context.

Content:

- Current workspace display name.
- Short path or path tail.
- Small workspace switch affordance.

Explicit removals:

- No connection status.
- No daemon address.
- No scan button.

Behavior:

- Tapping the workspace affordance opens the existing workspace selection path or navigates to the coding/workspace view, depending on the current app pattern.
- The bar should be visually quiet and should not look like a system status alert.

### 2. Now Panel

Purpose: show the highest-priority item that needs attention, plus a compact overflow hint when more important signals exist.

Priority order:

1. Pending approval or blocking item.
2. Failed run or failed conversation.
3. Running conversation or run in the current workspace.
4. Queue blockage.
5. Idle state.

Overflow rule:

- The panel renders one primary item to preserve mobile focus.
- If additional signals exist at the same priority or an adjacent priority, show a compact `+N more` affordance inside the panel footer.
- Overflow items are not silently discarded. Current-workspace overflow can appear in the Execution Stream, and cross-workspace overflow appears in the Interrupt Lane when it matches that lane's visibility rules.
- Example: if current workspace has an approval and a failed run, Now Panel shows the approval and `+1 more`; Execution Stream keeps the failed run visible unless it is the same item as the primary Now item.

Content examples:

- Approval: title, workspace name, adapter, brief action summary, time.
- Failure: title, workspace name, tool or adapter, concise failure state.
- Running: tool or adapter, status, short session or run identifier, updated time.
- Idle: one quiet line stating the current workspace has no blockers.

Design:

- Use a low-height panel, not a large card.
- Use one small severity marker or icon only when it improves scanning.
- Avoid full-background semantic colors. Color should be a state accent, not the surface.

### 3. Cross Workspace Interrupt Lane

Purpose: surface urgent signals outside the current workspace without making the whole page global.

Visibility:

- Hidden when no other workspace needs attention.
- Visible when another workspace has approval, failure, or blocking queue state.
- Visible for other-workspace running state only when the current workspace is idle and there is no approval, failure, or blocked queue signal anywhere.
- Hidden for normal other-workspace running state when the current workspace already has a stronger Now Panel item.

Row format:

- Workspace name.
- Signal type and count.
- Optional adapter/tool label.

Examples:

- `mobile-app · approval 1`
- `daemon · failed run`
- `docs-site · queue blocked 2`

Design:

- Compact list or horizontal chips.
- Fine border, dark neutral background, small semantic dot.
- No full list of all workspaces.

### 4. Execution Stream

Purpose: replace the current empty recent-runs block with a useful activity stream.

Content:

- Current workspace recent runs and relevant conversations.
- Limit to the most recent 3 items on the first screen.
- Each item shows adapter/tool, status, short identifier, and updated time when available.
- Exclude the exact item already rendered as the primary Now Panel item to avoid duplicate rows on the same screen.
- Keep related but distinct signals visible. For example, if Now Panel shows an approval for a conversation, a failed run in the same workspace can still appear in the stream.

Empty state:

- One compact line, such as `No recent activity in this workspace`.
- Do not show a large empty container.

Interaction:

- Tapping an item opens the existing run detail or workbench detail route.
- If an exact detail route is not available for every item, use the closest existing workbench route and keep the implementation explicit.

### 5. Workspace Signals

Purpose: show current workspace health and context without large dashboard cards.

Signals:

- Git changed file count from `gitStatus.files.length`.
- Diagnostics count from `diagnostics.diagnostics.length`.
- Queue count scoped to the current workspace where possible.
- Recent files count or the top recent file path tail.

Design:

- Small chips or two-column compact rows.
- Neutral surfaces with small labels.
- State color only for non-zero warnings or errors.

### 6. Primary Actions

Purpose: keep key actions available without dominating the page.

Actions:

- New task.
- Command templates.
- Queue.

Design:

- Replace three large colored tiles with a compact action row.
- Use small icons and short labels.
- Use consistent border and press states with the rest of the mobile UI.

## Data Design

### Existing Data To Reuse

From `AppSnapshot`:

- `workspace` and `workspaces` for current workspace identity.
- `runs` for current workspace run list.
- `conversations` for global conversation and approval signals.
- `queue` for global queue state.
- `overview.recentFiles` for recent touched files.
- `gitStatus` for changed files.
- `diagnostics` for code health.

### Light Data Addition

Add a lightweight cross-workspace run summary source so the home page can detect urgent run signals outside the current workspace.

Minimum shape:

```dart
class WorkspaceRunSummary {
  const WorkspaceRunSummary({
    required this.workspaceId,
    required this.runningCount,
    required this.failedCount,
    required this.latestRunId,
    required this.latestStatus,
    required this.latestTool,
  });

  final String workspaceId;
  final int runningCount;
  final int failedCount;
  final String latestRunId;
  final String latestStatus;
  final String latestTool;
}
```

Implementation may derive this from existing `/api/runs` calls if the daemon already returns enough global data, or load per workspace with a bounded request pattern. Keep it small: counts and latest state only.

Refresh policy:

- Refresh with the normal `AppSnapshot` load or refresh cycle by default.
- Do not introduce an independent high-frequency timer for the home page.
- If the app already performs foreground polling, run summary refresh should piggyback on that cadence.
- Manual user refresh or returning to foreground may trigger a refresh.
- If summary loading fails, keep the current workspace view and derive any available cross-workspace signals from `conversations` and `queue`.

### Signal Selection Rules

Current workspace remains the default focus. Cross-workspace items enter the home page only if they are actionable or abnormal.

Priority ranking:

1. Conversations with `blockingItem` or approval-like status.
2. Conversations or runs with failed status.
3. Queue items with blocked or non-running waiting state.
4. Running state in other workspaces only if the current workspace is idle and there is no stronger signal.

## Components

### `HomePage`

Responsibility:

- Compose the command deck.
- Own no complex ranking logic directly.
- Receive derived home view data from helper functions or a small view model.

### `HomeCommandBar`

Responsibility:

- Render current workspace identity and switch affordance.
- Exclude connection status and scan controls.

### `HomeNowPanel`

Responsibility:

- Render the single highest-priority current item.
- Support approval, failure, running, queue, and idle variants.

### `HomeInterruptLane`

Responsibility:

- Render urgent cross-workspace items.
- Stay hidden when empty.

### `HomeExecutionStream`

Responsibility:

- Render recent current-workspace activity.
- Use compact rows and a small empty state.

### `HomeWorkspaceSignals`

Responsibility:

- Render Git, diagnostics, queue, and recent-file signals.
- Use compact chips or small rows.

### Home View Model Helpers

Responsibility:

- Rank the Now Panel item.
- Filter cross-workspace interrupts.
- Scope queue and conversation data by workspace.
- Keep `HomePage` readable and testable.

## Visual Direction

Color strategy: restrained.

- Background: dark tinted neutral.
- Panels: slightly raised dark neutral with fine border.
- Text: high-contrast primary, muted secondary.
- Accent: used only for focus, severity, and selected states.

Shape and density:

- Smaller radii than the current large cards.
- Less vertical padding, more deliberate grouping.
- No repeated equal-size metric card grid.
- No large full-color backgrounds.

Motion:

- Use only small state transitions if existing patterns already support them.
- No decorative page-load animation.

## Error And Empty States

- If there are no runs, conversations, queue items, diagnostics, or Git changes, the page should still feel intentional: show current workspace identity and a compact idle state.
- If optional cross-workspace run summary loading fails, keep the current workspace view intact and omit the interrupt lane or show only signals available from `conversations` and `queue`.
- Runtime strings such as workspace names, paths, run ids, adapter names, and error details are not translated.

## Internationalization

All user-facing static labels must use existing app localization patterns.

Likely new keys:

- `homeNowTitle`
- `homeInterruptsTitle`
- `homeExecutionStreamTitle`
- `homeWorkspaceSignalsTitle`
- `homeIdleNow`
- `homeNoRecentActivity`
- `homeGitChangedLabel`
- `homeDiagnosticsLabel`
- `homeQueueLabel`
- `homeRecentFilesLabel`
- `homeMoreSignalsLabel`

Do not translate runtime data: workspace names, paths, adapter names, tool names, run ids, and raw daemon messages.

## Testing Strategy

Widget tests should cover:

- Home page does not render connection status or scan controls.
- Pending approval becomes the Now Panel priority over running state.
- Pending approval and failed run together render one primary Now item plus an overflow hint.
- Cross-workspace interrupt lane appears for another workspace approval or failed run.
- Cross-workspace interrupt lane appears for another workspace running item only when the current workspace is idle and no stronger signal exists.
- Cross-workspace interrupt lane stays hidden when only the current workspace has normal activity.
- Execution Stream excludes the exact primary Now Panel item.
- Empty state is compact when no activity exists.
- Cross-workspace run summary loading failure degrades without breaking current-workspace content.
- Simplified Chinese renders static labels through localization.

Unit tests should cover:

- Signal ranking helper priority order.
- Workspace scoping for current and external signals.
- Run summary aggregation for running and failed counts.
- Overflow count derivation for same-priority and adjacent-priority signals.
- Now Panel and Execution Stream de-duplication by stable item identity.

## Implementation Scope

This design is one implementation slice:

1. Introduce small home view data helpers.
2. Add lightweight cross-workspace run summary support.
3. Replace the current `HomePage` layout with Command Deck components.
4. Add localization keys.
5. Add unit tests for ranking, overflow, workspace scoping, de-duplication, and run-summary aggregation.
6. Add widget tests for layout behavior, hidden connection controls, interrupt lane visibility, compact empty states, and localization.

Keep changes local to home page, snapshot/data helpers, l10n, and tests unless the existing route wiring requires a small adjustment.

## Open Decisions Resolved

- The selected direction is Command Deck.
- The default mode is current-workspace first with smart cross-workspace interruptions.
- The home page must not show connection state, daemon address, or scan UI.
- The data layer should use a light run-summary addition rather than a full multi-workspace dashboard model.
