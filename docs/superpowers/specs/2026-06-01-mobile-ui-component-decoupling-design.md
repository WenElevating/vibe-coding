# Mobile UI Component Decoupling Design

- Date: 2026-06-01
- Status: proposed for implementation planning
- Scope: `mobile/lib/src/ui`

## Context

The recent `home_page.dart` and main-shell work established the direction:
main-shell and Home code belong under `mobile/lib/src/ui/main/`, while true
feature areas remain under `mobile/lib/src/ui/features/<feature>/`.

The same component-coupling smell still exists in other mobile UI modules. The
largest current files are not only long; several of them mix page routing,
modal orchestration, state projection, rendering components, parsing helpers,
and local controllers in one Dart file. This makes review and maintenance
fragile because one UI change can require loading a full page, a state machine,
and many unrelated private widgets at once.

Current high-risk candidates from the source tree:

- `ui/features/workbench/workbench_event_cards.dart`
  - About 100 KB.
  - Contains message dispatch, user/assistant cards, markdown/code block
    rendering, command/tool cards, task progress cards, diff/patch rendering,
    approval/question cards, pending sentinel UI, and parsing helpers.
- `ui/features/workbench/coding_workbench_page.dart`
  - About 90 KB.
  - Contains page lifecycle, nested navigation, event subscription management,
    voice input dialogs, ASR model download dialog, slash-command orchestration,
    model/adapter sheets, workspace creation modal flow, transcript scrolling,
    send/cancel actions, and route rendering.
- `ui/features/workbench/view_models/workbench_view_model.dart`
  - About 60 KB.
  - Owns workspace route state, conversation state, repository listeners,
    adapter/model selection, event application, draft attachment lifecycle,
    pagination, approval responses, diagnostics recording, and workspace
    creation helpers.
- `ui/features/workspace_picker/workspace_picker_sheet.dart`
  - About 40 KB.
  - Contains adapter picker, workspace list, add-workspace form, directory
    browser, directory rows, mini inputs, and path normalization helpers.
  - `dedupeWorkspacesByPath` is already shared by Workspace Picker, Home
    no-workspace presentation, and widget tests, so it should not remain
    accidentally owned by a picker sheet file after the split.
- `ui/features/settings/settings_page.dart`
  - About 23 KB.
  - Contains settings page composition, language modal, connection card,
    metrics, rows, chips, switch rows, action buttons, and update row wrapper.

## Goals

- Split large UI files by ownership, not by arbitrary line count.
- Keep each page file as a lean composer of named sections.
- Keep feature-local widgets near their owner instead of moving everything into
  shared `ui/core`.
- Keep `ui/main/` for the main shell and Home surface; do not introduce
  `ui/features/main`.
- Preserve current runtime behavior while changing structure.
- Make future changes reviewable in small, focused files.
- Add focused tests only where the refactor touches behavioral or stateful
  boundaries.

## Non-Goals

- Do not redesign the mobile UI.
- Do not introduce a new state-management package.
- Do not rename product concepts such as Workbench, Workspace Picker, or
  Settings.
- Do not move main-shell/Home code back into `ui/features`.
- Do not rewrite repository/data/domain layers as part of this UI cleanup.
- Do not split every private helper just to reduce file size; split only when a
  section has a clear responsibility and stable inputs.

## Recommended Approach

Use a phased component-boundary cleanup, starting with the riskiest Workbench
files and then moving to secondary modules.

This is the recommended option because it gives immediate maintainability value
without destabilizing the app shell. A pure "split everything over N lines"
approach would create many shallow files without better ownership. A full
architecture rewrite would mix UI cleanup with repository/domain migration and
make regressions harder to isolate.

## Target Ownership Rules

### Page files

Page files should compose route-level sections and own only page-local UI
lifecycle:

- navigation and back handling;
- route selection;
- focus/scroll controllers when the behavior is purely visual;
- dialog or bottom-sheet presentation;
- wiring callbacks from sections to ViewModels.

Page files should not contain many meaningful child widget classes or feature
subsystems.

### Feature widgets

Feature widgets stay inside their feature:

```text
mobile/lib/src/ui/features/<feature>/
+-- views/
+-- widgets/
+-- sheets/
+-- dialogs/
+-- view_models/
+-- models/
```

Use `widgets/` for repeated or section-level presentation components, `sheets/`
for bottom sheets, and `dialogs/` for dialogs. Keep private helper widgets in
the same file only when they are tightly coupled to one small public widget.

### Shared UI

Move a widget to `ui/core/widgets` only when it is reused by more than one
feature or is a real design primitive. Do not promote Workbench-specific cards,
Settings rows, or Workspace Picker rows to core just because they look reusable.

### Main ownership

Main-shell and Home code stays under:

```text
mobile/lib/src/ui/main/
```

Do not add a `main` feature under `ui/features/`. Main is the connected app
shell, not a feature area.

## Target Workbench Layout

```text
mobile/lib/src/ui/features/workbench/
+-- views/
|   +-- coding_workbench_page.dart
|   +-- workbench_conversation_route.dart
|   +-- workbench_session_route.dart
|   +-- workbench_workspace_route.dart
+-- widgets/
|   +-- workbench_header.dart
|   +-- workbench_message_list.dart
|   +-- workbench_run_error_card.dart
|   +-- workbench_inline_status.dart
|   +-- pending_sentinel.dart
+-- messages/
|   +-- workbench_message_card.dart
|   +-- user_message_card.dart
|   +-- assistant_markdown_body.dart
|   +-- code_block.dart
|   +-- command_event_card.dart
|   +-- command_detail_sheet.dart
|   +-- task_progress_card.dart
|   +-- diff_event_card.dart
|   +-- patch_transcript_panel.dart
|   +-- approval_event_card.dart
|   +-- question_event_card.dart
|   +-- notice_event_card.dart
+-- dialogs/
|   +-- voice_input_error_dialog.dart
|   +-- asr_model_download_dialog.dart
+-- sheets/
|   +-- model_picker_sheet.dart
+-- view_models/
|   +-- workbench_view_model.dart
+-- workbench.dart
```

`workbench.dart` remains the feature barrel for intentional public imports.
Callers should import the barrel or the specific public file already used by
the feature, not private leaf files.

The implementation plan should add a lightweight barrel consistency check to
`mobile/tool/check_architecture_imports.dart` before large barrel churn. The
check should verify that configured feature barrels export existing Dart files
and that each exported file still contains at least one public declaration. This
does not need a full analyzer plugin; a conservative file-exists plus public
declaration scan is enough to catch stale exports during this cleanup.

## Workbench Refactor Slices

### Slice 1: Split event/message rendering

Move the rendering-only parts out of `workbench_event_cards.dart`.

Initial extraction groups:

- message dispatcher and top-level public card;
- user and assistant message cards;
- markdown and copyable code block rendering;
- command/tool/sub-agent cards and command detail sheet;
- task progress rendering;
- diff/patch/file-change rendering and patch parser helpers;
- approval/question/notice/thinking cards;
- pending sentinel/status widgets.

The public constructor contracts and observable behavior should remain
equivalent from a caller perspective. `WorkbenchMessageCard`,
`WorkbenchInlineStatus`, and `PendingSentinel` keep their public constructor
contracts unless a test proves a narrower contract is safe.

### Slice 2: Split Workbench page routes and overlays

Reduce `CodingWorkbenchPage` to the stateful route coordinator. Move rendering
sections and overlays into focused files:

- workspace list route;
- session list route;
- conversation detail route;
- message list section;
- run error card;
- model picker sheet;
- voice input error dialog;
- ASR model download dialog.

Before moving route rendering, add explicit source markers in
`coding_workbench_page.dart` for route-sensitive subscription ownership. Use a
consistent marker with a concrete reason, such as:

```dart
// TODO(slice-3): subscription ownership - restarts when opening a conversation route
```

At minimum, mark the code paths that cancel, restart, suspend, or apply
conversation event subscriptions during route changes, conversation opening,
workspace/session navigation, app backgrounding, and initial conversation event
loading. This makes the later Slice 3 extraction source-guided instead of
memory-guided.

The page may continue to own the nested navigator, route observer, scroll
controller, prompt controller, and event subscription during this slice. Those
are behavior-sensitive and should not be moved at the same time as the visual
split unless the target boundary is very small.

### Slice 3: Isolate Workbench page-side controllers

After route/overlay rendering is separated, identify page-side state that has
grown beyond UI lifecycle:

- slash-command menu loading and token parsing;
- conversation event subscription reconnect/suspend behavior;
- transcript pagination trigger;
- approval notification forwarding;
- voice input coordination.

Move only stable, testable groups behind feature-local controllers or
ViewModel/use-case methods. Keep purely visual controllers such as
`ScrollController` and `TextEditingController` in the page unless a narrower
widget owns the actual interaction.

### Slice 4: Split `WorkbenchViewModel` by data-flow responsibility

Do not split the ViewModel first. Its current size is a symptom, but it also
holds delicate state transitions. Split after rendering and page routing are
easier to read.

Candidate extraction boundaries:

- `WorkbenchRouteState` for workspace/session/conversation route projection;
- `WorkbenchConversationEventState` for event pagination and application;
- `WorkbenchDraftAttachmentState` for draft attachment validation and preview
  binding;
- small domain/use-case helpers only when an operation crosses repositories or
  has an ordered side-effect sequence.

Before implementing this slice, create a dependency sketch for the candidate
state groups and approval/model/conversation flows. The sketch must identify:

- which state group can depend on which other group;
- which group owns route-derived facts such as active workspace and active
  conversation;
- whether draft attachment validation reads route/conversation state;
- whether approval responses mutate both event state and route state;
- whether any proposed extraction would create a cycle.

Do not split the ViewModel into mutually referencing sibling objects. If the
dependency sketch shows cycles, keep the state in one ViewModel and extract
pure helpers or value objects first.

The main `WorkbenchViewModel` should remain the single object consumed by the
page during this cleanup. Avoid creating a web of sibling ViewModels until a
concrete UI section needs independent lifecycle or independent tests.

## Workspace Picker Refactor

Target layout:

```text
mobile/lib/src/ui/features/workspace_picker/
+-- workspace_picker.dart
+-- models/
|   +-- workspace_creation_request.dart
+-- sheets/
|   +-- adapter_picker_sheet.dart
|   +-- add_workspace_sheet.dart
|   +-- directory_browser_sheet.dart
+-- widgets/
|   +-- workspace_list_page.dart
|   +-- workspace_choice_row.dart
|   +-- directory_row.dart
|   +-- mini_input.dart
|   +-- sheet_icon_button.dart
+-- workspace_display.dart
```

Before splitting this file, run a full usage search for
`dedupeWorkspacesByPath`, workspace path normalization, and workspace display
helpers. Current usage already includes Workspace Picker, Home no-workspace
presentation, and widget tests. Because the dedupe logic is shared by main/Home
and a feature picker, do not leave it privately owned by a sheet file.

If the usage search confirms main/Home still uses the dedupe or path
normalization helper, move the pure helper directly to a shared owner instead of
temporarily parking it under Workspace Picker. Use `ui/core` for presentation
helpers that only prepare workspace-list display data and have no domain
semantics. Use a domain-level workspace value helper only if the logic becomes a
business rule outside UI presentation. Keep barrel exports deliberate after the
shared owner is chosen; do not use the barrel to hide unclear ownership.

The directory browser uses repository callbacks for filesystem listing. Its
stateful browse/open/back behavior should move with the sheet, not into the
main Workbench page.

## Settings Refactor

Target layout:

```text
mobile/lib/src/ui/features/settings/
+-- settings.dart
+-- views/
|   +-- settings_page.dart
+-- sheets/
|   +-- language_picker_sheet.dart
+-- widgets/
|   +-- app_update_panel.dart
|   +-- settings_card.dart
|   +-- settings_connection_card.dart
|   +-- settings_metric.dart
|   +-- settings_row.dart
|   +-- settings_switch_row.dart
|   +-- permission_mode_row.dart
|   +-- settings_action_button.dart
|   +-- settings_update_check_row.dart
+-- view_models/
```

`SettingsPage` should read the ViewModel and compose sections. Row/card/chip
widgets should move to `widgets/`. Language picker should move to `sheets/`
because it owns modal UI and language-scope interaction.

## Main Shell Follow-Up

`mobile/lib/src/ui/main/main_page.dart` is still moderately large but belongs
under `ui/main/`. Do not move it into `features`.

Potential future extractions:

- app update lifecycle helper;
- approval notification tap coordinator;
- connected ViewModel construction helpers;
- workspace creation/loading presentation.

These should remain under `ui/main/` or a main-local helper directory, because
they compose the connected shell rather than a feature tab.

## Testing Strategy

This cleanup should rely on existing behavior tests only after they are audited
against the slice risk. Before Workbench page-side controller extraction or
ViewModel state extraction, add or identify focused tests that lock down key
`WorkbenchViewModel` transitions:

- event application and rebuild ordering;
- initial and older event pagination;
- optimistic user messages and acknowledgement reconciliation;
- draft attachment validation, preview binding, and orphan cleanup;
- approval responses for conversation and run approvals;
- model selection and unsupported-model fallback;
- route transitions between workspace list, session list, and conversation.

If these paths are not covered, add behavior tests before refactoring the
stateful code. Snapshot-style tests are acceptable only for stable input/output
state projections; they must not replace behavior tests for ordered async
flows.

Run after each implementation slice:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' format <changed dart files>
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

Run targeted Flutter tests for touched behavior:

- Workbench message/card rendering tests when splitting message files.
- Conversation reducer/ViewModel tests when touching event application,
  pagination, optimistic messages, approvals, or attachment state.
- Workspace picker widget tests when moving directory browser or add-workspace
  flow.
- Settings widget tests if row/sheet interactions change.

If any Flutter/Dart command times out on the first attempt in this environment,
stop retrying automatically and report the exact command as timed out.

## Acceptance Criteria

- No new production code is added to retired roots:
  `mobile/lib/src/features`, `mobile/lib/src/widgets`,
  `mobile/lib/src/theme`, or `mobile/lib/src/state`.
- Main-shell code remains under `mobile/lib/src/ui/main/`.
- `coding_workbench_page.dart` becomes a route coordinator instead of a file
  containing page logic plus many route, dialog, and sheet widgets.
- `workbench_event_cards.dart` is replaced by a public entry file/barrel plus
  focused message/card modules.
- `workspace_picker_sheet.dart` is split into sheets, widgets, and model files
  with stable public exports.
- `settings_page.dart` keeps page composition while row/card/sheet widgets move
  into local files.
- Architecture import checks pass.
- Relevant analyze/test targets pass or the first timeout is reported honestly.

## Implementation Order

1. Workbench event/message rendering split.
2. Add route-sensitive subscription ownership markers in
   `coding_workbench_page.dart`, then split Workbench page route and overlay
   rendering.
3. Add barrel consistency coverage to the architecture check before large
   barrel churn.
4. Workspace Picker sheet/widget split, after confirming shared workspace-list
   helper ownership from actual usage.
5. Settings page widget/sheet split.
6. Workbench page-side controller extraction, only after the visual split is
   stable.
7. Workbench ViewModel dependency sketch and missing state-transition tests.
8. Workbench ViewModel responsibility split, only if the sketch has no cycles
   or the extraction is limited to pure helpers/value objects.
9. Optional `ui/main/main_page.dart` helper extraction under `ui/main/`.

This order starts with the largest rendering-only file, then simplifies the
Workbench page before touching delicate state ownership. It leaves the main
shell in its correct location and avoids mixing feature cleanup with broader
data/domain architecture changes.
