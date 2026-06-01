# Mobile UI Component Decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the largest Flutter mobile UI files into focused Workbench, Workspace Picker, Settings, and shared helper modules without changing runtime behavior.

**Architecture:** Keep `ui/main/` as the connected shell and Home owner; keep true feature UI in feature directories under `ui/features/`. Split large files by ownership: Workbench message rendering into a Workbench-only `messages/` layer, route/dialog/sheet UI into local folders, shared workspace-list presentation helpers into a non-feature owner, and stateful Workbench controller/ViewModel changes only after tests and dependency sketches exist.

**Tech Stack:** Flutter/Dart, existing `ChangeNotifier`/`ListenableBuilder`, existing widget/ViewModel tests, `mobile/tool/check_architecture_imports.dart`, no new runtime dependencies.

---

## File Structure

- Modify `mobile/tool/check_architecture_imports.dart`: add a small feature-barrel consistency check for configured barrels.
- Modify `mobile/test/architecture_imports_tool_test.dart`: add tests for stale barrel exports and empty exported files.
- Create `mobile/lib/src/ui/features/workbench/messages/`: Workbench conversation message rendering files only.
- Create `mobile/lib/src/ui/features/workbench/widgets/`: Workbench route sections and general Workbench widgets.
- Create `mobile/lib/src/ui/features/workbench/dialogs/`: Workbench-specific dialogs.
- Create `mobile/lib/src/ui/features/workbench/sheets/`: Workbench-wide bottom sheets such as model picker.
- Modify `mobile/lib/src/ui/features/workbench/workbench.dart`: export the public Workbench entry points after files move.
- Modify `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`: reduce to compatibility exports during the first message-rendering split, then delete only after internal imports stop using it.
- Modify `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`: add route-sensitive subscription markers first, then move rendering sections and overlays to focused files.
- Create `mobile/lib/src/ui/core/widgets/workspace_list_presentation.dart`: shared pure presentation helper for workspace list dedupe/path normalization if usage still spans Home and Workspace Picker.
- Modify `mobile/lib/src/ui/core/widgets/widgets.dart`: export the shared workspace presentation helper if created under `ui/core/widgets`.
- Create `mobile/lib/src/ui/features/workspace_picker/models/workspace_creation_request.dart`: workspace creation sheet result model.
- Create `mobile/lib/src/ui/features/workspace_picker/sheets/`: adapter picker, add-workspace, and directory browser sheets.
- Create `mobile/lib/src/ui/features/workspace_picker/widgets/`: workspace list page, row widgets, directory row widgets, mini input, and sheet icon button.
- Modify `mobile/lib/src/ui/features/workspace_picker/workspace_picker.dart`: export stable public Workspace Picker API.
- Modify `mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart`: reduce to compatibility exports during migration.
- Create `mobile/lib/src/ui/features/settings/views/settings_page.dart`: final Settings page location.
- Create `mobile/lib/src/ui/features/settings/sheets/language_picker_sheet.dart`.
- Create `mobile/lib/src/ui/features/settings/widgets/`: settings card/row/switch/action/permission/update widgets.
- Modify `mobile/lib/src/ui/features/settings/settings_page.dart`: reduce to compatibility export or move content to `views/settings_page.dart`.
- Modify `mobile/lib/src/ui/features/settings/settings.dart`: export stable Settings public API.
- Add or modify tests:
  - `mobile/test/architecture_imports_tool_test.dart`
  - `mobile/test/widget_test.dart`
  - `mobile/test/workbench_view_model_repository_state_test.dart`
  - focused new widget tests only when extraction changes public widget entry points.

Use the task-specific format commands below after each implementation task that touches Dart. The common non-format validation commands are:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

For widget tests, prefer targeted commands. If a Flutter/Dart command times out once in this environment, stop retrying and report the exact command.

---

## Task 1: Add Barrel Consistency Guard

**Files:**
- Modify: `mobile/tool/check_architecture_imports.dart`
- Modify: `mobile/test/architecture_imports_tool_test.dart`

- [ ] **Step 1: Add failing test for missing barrel export target**

Append this test to `mobile/test/architecture_imports_tool_test.dart`:

```dart
test('feature barrel exporting missing file is reported as forbidden',
    () async {
  File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('name: architecture_imports_fixture\n');

  final barrel = File(
    '${tempDir.path}${Platform.pathSeparator}'
    'lib${Platform.pathSeparator}'
    'src${Platform.pathSeparator}'
    'ui${Platform.pathSeparator}'
    'features${Platform.pathSeparator}'
    'workbench${Platform.pathSeparator}'
    'workbench.dart',
  )..createSync(recursive: true);

  barrel.writeAsStringSync("export 'missing.dart';\n");

  final output = StringBuffer();
  final exitCode = await checker.checkArchitectureImports(
    root: tempDir,
    err: output,
  );

  expect(exitCode, isNonZero);
  expect(output.toString(), contains('barrel export target is missing'));
  expect(output.toString(), contains('workbench.dart'));
});
```

- [ ] **Step 2: Add failing test for empty barrel export target**

Append this test to the same file:

```dart
test('feature barrel exporting file without public declaration is reported',
    () async {
  File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('name: architecture_imports_fixture\n');

  final featureDir = Directory(
    '${tempDir.path}${Platform.pathSeparator}'
    'lib${Platform.pathSeparator}'
    'src${Platform.pathSeparator}'
    'ui${Platform.pathSeparator}'
    'features${Platform.pathSeparator}'
    'workbench',
  )..createSync(recursive: true);

  File('${featureDir.path}${Platform.pathSeparator}workbench.dart')
      .writeAsStringSync("export 'empty.dart';\n");
  File('${featureDir.path}${Platform.pathSeparator}empty.dart')
      .writeAsStringSync('class _PrivateOnly {}\n');

  final output = StringBuffer();
  final exitCode = await checker.checkArchitectureImports(
    root: tempDir,
    err: output,
  );

  expect(exitCode, isNonZero);
  expect(output.toString(), contains('barrel export target has no public declaration'));
  expect(output.toString(), contains('empty.dart'));
});
```

- [ ] **Step 3: Run the failing architecture tool tests**

Run:

```powershell
cd mobile
flutter test test/architecture_imports_tool_test.dart -r expanded
```

Expected: the two new tests fail because the checker does not yet validate barrel export targets.

- [ ] **Step 4: Implement configured barrel checks**

In `mobile/tool/check_architecture_imports.dart`, add:

```dart
const checkedFeatureBarrels = <String>{
  'lib/src/ui/features/workbench/workbench.dart',
  'lib/src/ui/features/workspace_picker/workspace_picker.dart',
  'lib/src/ui/features/settings/settings.dart',
};

final publicDeclarationPattern = RegExp(
  r'^\s*(class|enum|typedef|mixin|extension)\s+[A-Z][A-Za-z0-9_]*',
  multiLine: true,
);
```

Inside `checkArchitectureImports`, after the import/export scan loop and before output is printed, call:

```dart
  _checkFeatureBarrels(
    mobileRoot: mobileRoot,
    violations: violations,
  );
```

Add this helper near the other private helpers:

```dart
void _checkFeatureBarrels({
  required Directory mobileRoot,
  required List<String> violations,
}) {
  for (final barrelPath in checkedFeatureBarrels) {
    final barrel = File(_joinMobilePath(mobileRoot, barrelPath));
    if (!barrel.existsSync()) continue;
    final lines = barrel.readAsLinesSync();
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final match = importOrExportPattern.firstMatch(lines[lineIndex]);
      if (match == null || match.group(1) != 'export') continue;
      final uri = match.group(2)!;
      if (uri.startsWith('package:') || uri.startsWith('dart:')) continue;
      final target = _normalizeTarget(barrelPath, uri);
      final targetFile = File(_joinMobilePath(mobileRoot, target));
      final location = '$barrelPath:${lineIndex + 1}';
      if (!targetFile.existsSync()) {
        violations.add('$location barrel export target is missing ($uri)');
        continue;
      }
      final source = targetFile.readAsStringSync();
      if (!publicDeclarationPattern.hasMatch(source)) {
        violations.add(
          '$location barrel export target has no public declaration ($uri)',
        );
      }
    }
  }
}

String _joinMobilePath(Directory mobileRoot, String normalizedPath) {
  final parts = <String>[mobileRoot.absolute.path];
  parts.addAll(normalizedPath.split('/'));
  return parts.join(Platform.pathSeparator);
}
```

- [ ] **Step 5: Run architecture tool tests**

Run:

```powershell
cd mobile
flutter test test/architecture_imports_tool_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Run architecture import check**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
```

Expected: PASS and no stale feature-barrel exports.

- [ ] **Step 7: Commit**

```powershell
git add mobile/tool/check_architecture_imports.dart mobile/test/architecture_imports_tool_test.dart
git commit -m "Guard mobile feature barrel exports"
```

---

## Task 2: Split Workbench Message Rendering

**Files:**
- Create: `mobile/lib/src/ui/features/workbench/messages/workbench_message_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/user_message_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/assistant_markdown_body.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/code_block.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/question_event_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/notice_event_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/thinking_event_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/approval_event_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/command_event_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/task_progress_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/diff_event_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/patch_transcript_panel.dart`
- Create: `mobile/lib/src/ui/features/workbench/messages/pending_sentinel.dart`
- Create: `mobile/lib/src/ui/features/workbench/widgets/workbench_inline_status.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Record current public entry points and tests**

Run:

```powershell
rg -n "WorkbenchMessageCard|WorkbenchInlineStatus|PendingSentinel|AssistantMarkdownBody|buildPendingSentinelPreview" mobile\lib\src\ui mobile\test
```

Expected: public callers still use `WorkbenchMessageCard`, `WorkbenchInlineStatus`, `PendingSentinel`, and `AssistantMarkdownBody`. Keep those constructor contracts unchanged.

- [ ] **Step 2: Move message dispatcher and user/assistant cards**

Move these declarations from `workbench_event_cards.dart` into the new `messages/` files while preserving their source bodies:

```text
WorkbenchMessageCard -> messages/workbench_message_card.dart
_UserMessageCard, _UserBubbleFrame, _MessageAttachmentStrip, _MessageAttachmentPill,
_MessageImageAttachmentPreview, _ImageAttachmentViewer -> messages/user_message_card.dart
AssistantMarkdownBody, _AssistantMarkdownBodyState -> messages/assistant_markdown_body.dart
_CopyableCodeBlockBuilder, _CopyableCodeBlock, _CopyableCodeBlockState -> messages/code_block.dart
```

Do not change widget constructors, keys, text, colors, or callback behavior in this step.

- [ ] **Step 3: Move question, notice, thinking, and approval cards**

Move these declarations with their helper widgets:

```text
_QuestionEventCard, _QuestionSuggestionChip -> messages/question_event_card.dart
_SystemNoticeEventCard -> messages/notice_event_card.dart
_ThinkingEventCard, _ThinkingFoldout, _ThinkingFoldoutState -> messages/thinking_event_card.dart
_ApprovalEventCard, _AgentEventCard, _ApprovalActionButton -> messages/approval_event_card.dart
```

Keep these files private to the feature by exporting only through `workbench_event_cards.dart` or `workbench.dart` when needed by callers.

- [ ] **Step 4: Move command/tool/sub-agent/task-progress rendering**

Move these declarations:

```text
_CommandEventCard, _SubAgentCallCard, _SubAgentCallCardState, _SubAgentStatePill,
_ToolLogFoldout, _ToolLogFoldoutState, _ToolKindBadge, _ToolDetailBlock,
_ToolDetailBlockState, _CommandExpandedMeta, _InlineEventTrailing,
_CommandDetailSheet, _EventCodeLine -> messages/command_event_card.dart
_TaskProgressCard, _TaskProgressBadge, _TaskProgressRow, _TaskProgressDot,
_TaskProgressStatePill -> messages/task_progress_card.dart
```

Keep `command_detail_sheet.dart` as a later optional split only if `command_event_card.dart` remains hard to review after this move. Its owner remains `messages/`, not `sheets/`.

- [ ] **Step 5: Move diff/patch/file-change rendering and parser helpers**

Move these declarations:

```text
_DiffEventCard, _FileChangeEventCard, _PatchTranscriptFile, _PatchTranscriptPanel,
_PatchTranscriptPanelState, _PatchTranscriptLine, _PatchGutterText,
_FileChangeFallback, _ParsedPatch, _PatchLine, _PatchLineKind, _HunkStart
-> messages/diff_event_card.dart or messages/patch_transcript_panel.dart
```

Keep parser helpers near the patch rendering that consumes them.

- [ ] **Step 6: Move status and pending widgets**

Move these declarations:

```text
WorkbenchInlineStatus -> widgets/workbench_inline_status.dart
PendingSentinel, _PendingSentinelState, _PulsingStatusText,
_PulsingStatusTextState, _ElapsedTimerPill, _RunningOrb, _PulseBars, _PulseDot
-> messages/pending_sentinel.dart
```

If `_PulseDot` is still needed by `WorkbenchInlineStatus`, either keep a private copy in `workbench_inline_status.dart` or extract a package-private `messages/pulse_dot.dart`. Do not import a private declaration across files.

- [ ] **Step 7: Replace old file with compatibility exports**

Change `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart` to exports only:

```dart
export 'messages/assistant_markdown_body.dart';
export 'messages/pending_sentinel.dart';
export 'messages/workbench_message_card.dart';
export 'widgets/workbench_inline_status.dart';
```

If tests or preview helpers still require `buildPendingSentinelPreview`, keep its implementation in `messages/pending_sentinel.dart` and export it from the compatibility file.

- [ ] **Step 8: Update `workbench.dart` exports**

Ensure `mobile/lib/src/ui/features/workbench/workbench.dart` exports:

```dart
export 'messages/assistant_markdown_body.dart';
export 'messages/pending_sentinel.dart';
export 'messages/workbench_message_card.dart';
export 'widgets/workbench_inline_status.dart';
```

Keep `export 'workbench_event_cards.dart';` only as a short-lived compatibility export until all internal imports stop using it.

- [ ] **Step 9: Format changed Workbench files**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib\src\ui\features\workbench
```

Expected: formatter completes.

- [ ] **Step 10: Run Workbench message widget tests**

Run:

```powershell
cd mobile
flutter test test/widget_test.dart --plain-name "WorkbenchMessageCard" -r expanded
flutter test test/widget_test.dart --plain-name "pending sentinel" -r expanded
```

Expected: PASS. If `--plain-name` does not match local test names, run:

```powershell
cd mobile
flutter test test/widget_test.dart -r expanded
```

- [ ] **Step 11: Run architecture import check and analyze**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

Expected: PASS.

- [ ] **Step 12: Commit**

```powershell
git add mobile/lib/src/ui/features/workbench mobile/test/widget_test.dart
git commit -m "Split workbench message rendering"
```

---

## Task 3: Mark Workbench Route-Sensitive Subscription Ownership And Split Route UI

**Files:**
- Create: `mobile/lib/src/ui/features/workbench/views/workbench_workspace_route.dart`
- Create: `mobile/lib/src/ui/features/workbench/views/workbench_session_route.dart`
- Create: `mobile/lib/src/ui/features/workbench/views/workbench_conversation_route.dart`
- Create: `mobile/lib/src/ui/features/workbench/widgets/workbench_message_list.dart`
- Create: `mobile/lib/src/ui/features/workbench/widgets/workbench_run_error_card.dart`
- Create: `mobile/lib/src/ui/features/workbench/widgets/workbench_header.dart`
- Create: `mobile/lib/src/ui/features/workbench/dialogs/voice_input_error_dialog.dart`
- Create: `mobile/lib/src/ui/features/workbench/dialogs/asr_model_download_dialog.dart`
- Create: `mobile/lib/src/ui/features/workbench/sheets/model_picker_sheet.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add route-sensitive subscription markers**

In `coding_workbench_page.dart`, add concrete comments above these methods or branches:

```dart
// Slice 3 subscription ownership: route reset cancels active conversation event stream.
void _goToWorkspaces()

// Slice 3 subscription ownership: opening a session loads initial events then restarts stream.
Future<void> _openSession(SessionItem item)

// Slice 3 subscription ownership: route switch decides whether conversation stream should stay active.
void _setCurrentRoute(String route)

// Slice 3 subscription ownership: initial event page controls when live stream may append.
Future<void> _loadInitialConversationEventPage

// Slice 3 subscription ownership: background preference suspends or keeps the stream.
void _scheduleBackgroundEventDisconnect()

// Slice 3 subscription ownership: this is the live event subscription owner before controller extraction.
Future<void> _restartConversationEventSubscription()
```

Use the exact existing method bodies; add comments only.

- [ ] **Step 2: Extract workspace route widget**

Create `views/workbench_workspace_route.dart` with a `StatelessWidget` that accepts:

```dart
class WorkbenchWorkspaceRoute extends StatelessWidget {
  const WorkbenchWorkspaceRoute({
    super.key,
    required this.workspaces,
    required this.onSelected,
    required this.onAddWorkspace,
  });

  final List<WorkspaceSummary> workspaces;
  final ValueChanged<WorkspaceSummary> onSelected;
  final VoidCallback onAddWorkspace;
}
```

Its `build` body should return the current `_buildWorkspaceList()` content using `WorkspaceListPage`. Replace `_buildWorkspaceList()` with:

```dart
Widget _buildWorkspaceList() => WorkbenchWorkspaceRoute(
      workspaces: _workspaces,
      onSelected: _openWorkspaceSessions,
      onAddWorkspace: _showCreateWorkspaceFromWorkspaceList,
    );
```

- [ ] **Step 3: Extract session route widget**

Create `views/workbench_session_route.dart` with a `StatelessWidget` that accepts the current inputs used by `_buildSessionList()`: route workspace, session items, active conversation id, start-new callback, back callback, open-session callback, and localized title values as needed.

Move only rendering code. Keep `_openSession`, `_startNewSessionFromList`, `_returnToWorkspaceList`, and route mutation in `CodingWorkbenchPageState`.

- [ ] **Step 4: Extract conversation route shell**

Create `views/workbench_conversation_route.dart` with a `StatelessWidget` that composes the current conversation header, message list, error card, and composer slots.

Pass child widgets or callbacks instead of moving send/subscription logic. The page should still own `_sendPrompt`, `_respondApproval`, `_useQuestionSuggestion`, `_showAdapterPicker`, `_showModelPicker`, `_showWorkspacePicker`, `_pickAttachments`, and `_cancelActiveRun`.

- [ ] **Step 5: Extract message list widget**

Create `widgets/workbench_message_list.dart` with:

```dart
class WorkbenchMessageList extends StatelessWidget {
  const WorkbenchMessageList({
    super.key,
    required this.controller,
    required this.messages,
    required this.adapter,
    required this.expandThinking,
    required this.useReverseTranscript,
    required this.loadingOlderConversationEvents,
    required this.showPendingDuringInitialConversationLoad,
    required this.onApproval,
    required this.onSuggestion,
    required this.onScrollNotification,
  });
}
```

Move the rendering from `_buildMessageList` into this widget. Keep `_maybeLoadOlderConversationEvents` and `_loadOlderConversationEvents` in the page.

- [ ] **Step 6: Extract overlays and sheets**

Move these declarations out of `coding_workbench_page.dart`:

```text
_VoiceInputErrorDialog -> dialogs/voice_input_error_dialog.dart as VoiceInputErrorDialog
_AsrModelDownloadDialog, _AsrModelDownloadDialogState -> dialogs/asr_model_download_dialog.dart as AsrModelDownloadDialog
ModelPickerSheet, _ModelChoiceRow -> sheets/model_picker_sheet.dart
_CodingHeader -> widgets/workbench_header.dart as WorkbenchHeader
_buildRunErrorCard rendering -> widgets/workbench_run_error_card.dart as WorkbenchRunErrorCard
```

Update call sites to the public names.

- [ ] **Step 7: Format changed Workbench files**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib\src\ui\features\workbench
```

- [ ] **Step 8: Run targeted Workbench widget tests**

Run:

```powershell
cd mobile
flutter test test/widget_test.dart --plain-name "CodingWorkbenchPage" -r expanded
flutter test test/widget_test.dart --plain-name "workspace preview" -r expanded
```

Expected: PASS. If the names do not match local tests, run `flutter test test/widget_test.dart -r expanded`.

- [ ] **Step 9: Run architecture and analyze checks**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

- [ ] **Step 10: Commit**

```powershell
git add mobile/lib/src/ui/features/workbench mobile/test/widget_test.dart
git commit -m "Split workbench route rendering"
```

---

## Task 4: Split Workspace Picker And Move Shared Workspace Presentation Helper

**Files:**
- Create: `mobile/lib/src/ui/core/widgets/workspace_list_presentation.dart`
- Modify: `mobile/lib/src/ui/core/widgets/widgets.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/models/workspace_creation_request.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/sheets/adapter_picker_sheet.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/sheets/add_workspace_sheet.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/sheets/directory_browser_sheet.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/widgets/workspace_list_page.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/widgets/workspace_choice_row.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/widgets/directory_row.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/widgets/mini_input.dart`
- Create: `mobile/lib/src/ui/features/workspace_picker/widgets/sheet_icon_button.dart`
- Modify: `mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart`
- Modify: `mobile/lib/src/ui/features/workspace_picker/workspace_picker.dart`
- Modify: `mobile/lib/src/ui/main/home/widgets/home_no_workspace_panel.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Verify current helper usage**

Run:

```powershell
rg -n "dedupeWorkspacesByPath|_workspacePathKey|workspaceDisplayName|compactWorkspacePath" mobile\lib mobile\test
```

Expected: `dedupeWorkspacesByPath` is used by Workspace Picker, Home no-workspace, and tests. Because usage spans `ui/main` and `ui/features`, move the pure helper to `ui/core`.

- [ ] **Step 2: Create shared workspace presentation helper**

Create `mobile/lib/src/ui/core/widgets/workspace_list_presentation.dart`:

```dart
import '../../../models/protocol.dart';

List<WorkspaceSummary> dedupeWorkspacesByPath(
    Iterable<WorkspaceSummary> workspaces) {
  final seen = <String>{};
  final visible = <WorkspaceSummary>[];
  for (final workspace in workspaces) {
    final key = workspacePathPresentationKey(workspace.path);
    if (!seen.add(key)) continue;
    visible.add(workspace);
  }
  return visible;
}

String workspacePathPresentationKey(String path) {
  var normalized = path.trim().replaceAll('\\', '/').toLowerCase();
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
```

Export it from `mobile/lib/src/ui/core/widgets/widgets.dart`:

```dart
export 'workspace_list_presentation.dart';
```

- [ ] **Step 3: Update imports for dedupe helper**

Update `home_no_workspace_panel.dart` and Workspace Picker files to import the core helper through:

```dart
import '../../core/widgets/widgets.dart';
```

from Workspace Picker files, and use the existing `../../../core/widgets/widgets.dart`-style relative import from feature files that already import core widgets. Remove the local `dedupeWorkspacesByPath` and `_workspacePathKey` functions from `workspace_picker_sheet.dart`.

- [ ] **Step 4: Move WorkspaceCreationRequest**

Create `models/workspace_creation_request.dart` with the existing class body:

```dart
class WorkspaceCreationRequest {
  const WorkspaceCreationRequest({required this.path, this.name});

  final String path;
  final String? name;
}
```

Update imports and exports.

- [ ] **Step 5: Move adapter picker sheet**

Move `AdapterPickerSheet`, `_AdapterChoiceRow`, and `_AdapterBrandIcon` into `sheets/adapter_picker_sheet.dart`. Preserve constructor signatures and keys.

- [ ] **Step 6: Move workspace list page and row widgets**

Move `WorkspaceListPage`, `_WorkspaceSectionHeader`, `_WorkspaceChoiceRow`, and `_WorkspaceAddIconButton` into `widgets/workspace_list_page.dart` and `widgets/workspace_choice_row.dart`.

- [ ] **Step 7: Move add-workspace sheet and helper controls**

Move `AddWorkspaceSheet` and `_AddWorkspaceSheetState` into `sheets/add_workspace_sheet.dart`. Move `_CreateWorkspaceButton`, `_SheetIconButton`, and `_MiniInput` into `widgets/sheet_icon_button.dart` or `widgets/mini_input.dart` according to the target filenames listed in this task.

- [ ] **Step 8: Move directory browser sheet and row widgets**

Move `DirectoryBrowserSheet`, `_DirectoryBrowserSheetState`, `_DirectoryHeaderIcon`, `_DirectoryPathBar`, `_DirectorySelectButton`, `_DirectoryRow`, and `_DirectoryBackButton` into `sheets/directory_browser_sheet.dart` and `widgets/directory_row.dart`.

- [ ] **Step 9: Reduce `workspace_picker_sheet.dart` to compatibility exports**

Replace `workspace_picker_sheet.dart` with exports:

```dart
export 'models/workspace_creation_request.dart';
export 'sheets/add_workspace_sheet.dart';
export 'sheets/adapter_picker_sheet.dart';
export 'sheets/directory_browser_sheet.dart';
export 'widgets/workspace_list_page.dart';
```

Update `workspace_picker.dart` to export the same public API plus `workspace_display.dart`.

- [ ] **Step 10: Format Workspace Picker and core helper files**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib\src\ui\features\workspace_picker lib\src\ui\core\widgets\workspace_list_presentation.dart lib\src\ui\core\widgets\widgets.dart lib\src\ui\main\home\widgets\home_no_workspace_panel.dart
```

- [ ] **Step 11: Run workspace presentation tests**

Run:

```powershell
cd mobile
flutter test test/widget_test.dart --plain-name "workspace list presentation deduplicates duplicate paths" -r expanded
flutter test test/widget_test.dart --plain-name "new coding session workspace preview shows workspace list" -r expanded
```

Expected: PASS.

- [ ] **Step 12: Run architecture and analyze checks**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

- [ ] **Step 13: Commit**

```powershell
git add mobile/lib/src/ui/core/widgets mobile/lib/src/ui/features/workspace_picker mobile/lib/src/ui/main/home/widgets/home_no_workspace_panel.dart mobile/test/widget_test.dart
git commit -m "Split workspace picker components"
```

---

## Task 5: Split Settings Page Widgets And Sheet

**Files:**
- Create: `mobile/lib/src/ui/features/settings/views/settings_page.dart`
- Create: `mobile/lib/src/ui/features/settings/sheets/language_picker_sheet.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/settings_update_check_row.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/settings_card.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/settings_connection_card.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/settings_metric.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/settings_row.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/settings_switch_row.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/permission_mode_row.dart`
- Create: `mobile/lib/src/ui/features/settings/widgets/settings_action_button.dart`
- Modify: `mobile/lib/src/ui/features/settings/settings_page.dart`
- Modify: `mobile/lib/src/ui/features/settings/settings.dart`
- Test: `mobile/test/widget_test.dart`
- Test: `mobile/test/settings_view_model_test.dart`
- Test: `mobile/test/app_update_panel_test.dart`

- [ ] **Step 1: Move SettingsPage to views**

Move the public `SettingsPage` class body into `views/settings_page.dart`. Keep constructor parameters and imports compatible.

Change `settings_page.dart` to:

```dart
export 'views/settings_page.dart';
```

- [ ] **Step 2: Move language sheet**

Move `_LanguagePickerSheet`, `_languageModeLabel`, and `_showLanguagePicker` into `sheets/language_picker_sheet.dart`. Expose:

```dart
String languageModeLabel(AppLocalizations l10n, LanguageModePreference mode);
void showLanguagePicker(BuildContext context);
```

Update `SettingsPage` to call `showLanguagePicker(context)`.

- [ ] **Step 3: Move update row wrapper**

Move `_SettingsUpdateCheckRow` and `_appUpdateRowValue` into `widgets/settings_update_check_row.dart` as `SettingsUpdateCheckRow`. Keep `AppUpdatePanel` in `widgets/app_update_panel.dart`.

- [ ] **Step 4: Move card, row, switch, permission, action widgets**

Move and rename private widgets to public feature-local widgets:

```text
_SettingsCard -> SettingsCard
_SettingsConnectionCard -> SettingsConnectionCard
_SettingsMetric -> SettingsMetric
_SettingsPill -> SettingsPill
_SettingsActionButton -> SettingsActionButton
_SettingsRow -> SettingsRow
_PermissionModeRow -> PermissionModeRow
_PermissionChip -> PermissionChip
_SettingsSwitchRow -> SettingsSwitchRow
_SettingsTapRow, _SettingsTapRowTrailing -> SettingsTapRow, SettingsTapRowTrailing
```

Keep constructors equivalent and do not change strings, icons, or colors.

- [ ] **Step 5: Update Settings exports**

Update `settings.dart`:

```dart
export 'views/settings_page.dart';
export 'view_models/app_update_view_model.dart';
export 'view_models/settings_view_model.dart';
export 'widgets/app_update_panel.dart';
```

Export the new settings widgets only if tests or other features import them directly. Otherwise keep them feature-local.

- [ ] **Step 6: Format Settings files**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib\src\ui\features\settings
```

- [ ] **Step 7: Run Settings tests**

Run:

```powershell
cd mobile
flutter test test/settings_view_model_test.dart -r expanded
flutter test test/app_update_panel_test.dart -r expanded
flutter test test/widget_test.dart --plain-name "settings" -r expanded
```

Expected: PASS. If the widget test name filter does not match, run `flutter test test/widget_test.dart -r expanded`.

- [ ] **Step 8: Run architecture and analyze checks**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

- [ ] **Step 9: Commit**

```powershell
git add mobile/lib/src/ui/features/settings mobile/test/widget_test.dart
git commit -m "Split settings page components"
```

---

## Task 6: Audit And Test Workbench Stateful Extraction Boundaries

**Files:**
- Modify: `mobile/test/workbench_view_model_repository_state_test.dart`
- Modify: `mobile/test/conversation_reducer_test.dart` only if an event reducer path is missing coverage.
- Create: `docs/superpowers/progress/2026-06-01-workbench-view-model-boundary-audit.md`

- [ ] **Step 1: Create dependency sketch document**

Create `docs/superpowers/progress/2026-06-01-workbench-view-model-boundary-audit.md`:

```markdown
# Workbench ViewModel Boundary Audit

## Candidate State Groups

- Route state: active workspace id, route workspace id, active conversation id, route name.
- Conversation event state: event list, message list, pagination cursors, loading older events, optimistic message reconciliation.
- Draft attachment state: draft attachments, validation, preview binding, client message id lifecycle.
- Approval/model state: approval responses, active run cancellation, selected adapter/model, unsupported model notice.

## Allowed Dependency Direction

- ViewModel coordinates all groups.
- Pure helper/value objects may depend on immutable input values only.
- Candidate state groups must not hold references to each other.
- Route-derived facts are passed as values into helpers that need them.

## Cycle Check

- Draft attachment helpers may receive active conversation id as a value, but must not read route state directly.
- Approval helpers may return effects that the ViewModel applies to event and route state, but must not mutate both groups directly.
- Event helpers may rebuild messages from event inputs, but must not navigate routes.

## Extraction Decision

- Extract pure helpers/value objects first.
- Keep coupled mutable state in `WorkbenchViewModel` until tests prove a clean boundary.
```

- [ ] **Step 2: Audit existing WorkbenchViewModel tests**

Run:

```powershell
rg -n "applyConversationEventsAsync|loadInitialConversationEventPage|loadOlderConversationEventPage|optimistic|attachment|approval|selectModel|showSessions|showConversation" mobile\test\workbench_view_model_repository_state_test.dart mobile\test\conversation_reducer_test.dart
```

Record uncovered paths in the audit document under a new `## Test Gaps` section.

- [ ] **Step 3: Add missing ViewModel tests for route transitions**

If missing, add this test to `workbench_view_model_repository_state_test.dart`:

```dart
test('route transitions keep workspace and conversation route ids consistent', () {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
    ],
  );
  final viewModel = _workbenchViewModel(workspaceRepository);

  viewModel.showSessions('w1');
  expect(viewModel.routeWorkspace?.id, 'w1');
  expect(viewModel.activeConversationId, isNull);

  viewModel.showConversationRoute('w1', 'c1');
  expect(viewModel.routeWorkspace?.id, 'w1');
  expect(viewModel.activeConversationId, 'c1');

  viewModel.showWorkspaceList();
  expect(viewModel.activeConversationId, isNull);
});
```

- [ ] **Step 4: Add missing tests for event pagination and optimistic messages**

If missing, add tests that cover:

```dart
test('older event page prepends events without duplicating existing messages', () async {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
    ],
  );
  final viewModel = _workbenchViewModel(workspaceRepository);

  final loaded = await viewModel.loadOlderConversationEventPage(
    workspaceId: 'w1',
    conversationId: 'c1',
  );

  expect(loaded, isTrue);
  expect(viewModel.messages.map((message) => message.id).toSet().length,
      viewModel.messages.length);
});
```

Use existing fake repositories in the file; if they do not support the method, extend the fake minimally.

- [ ] **Step 5: Add missing tests for model and approval transitions**

If missing, add focused tests that follow this shape and use the existing fake repository patterns in `workbench_view_model_repository_state_test.dart`:

```dart
test('selectModel preserves selected model when repository rejects update',
    () async {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
    ],
  );
  final conversationRepository = _FakeCachedConversationRepository()
    ..updateModelError = const ConversationRepositoryException(
      message: 'model update unsupported',
      statusCode: 404,
    );
  final viewModel = _workbenchViewModel(
    workspaceRepository,
    conversationRepository: conversationRepository,
  );

  final changed = await viewModel.selectModel('gpt-5');

  expect(changed, isFalse);
  expect(viewModel.modelNotice, WorkbenchModelNotice.unsupported);
});

test('conversation approval delegates to repository without route mutation',
    () async {
  final workspaceRepository = _FakeWorkspaceRepository(
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(id: 'w1', name: 'One', path: r'D:\one'),
    ],
  );
  final conversationRepository = _FakeCachedConversationRepository();
  final viewModel = _workbenchViewModel(
    workspaceRepository,
    conversationRepository: conversationRepository,
  );
  viewModel.showConversationRoute('w1', 'c1');

  await viewModel.answerConversationQuestion(
    conversationId: 'c1',
    questionId: 'q1',
    answer: 'yes',
  );

  expect(viewModel.activeConversationId, 'c1');
  expect(conversationRepository.answeredQuestionIds, const <String>['q1']);
});
```

If the current fake repository does not expose `updateModelError` or `answeredQuestionIds`, add those fields to the fake in the same test file. Keep each test scoped to one transition.

If `_workbenchViewModel` cannot inject a custom conversation repository yet, extend the helper signature as follows:

```dart
WorkbenchViewModel _workbenchViewModel(
  _FakeWorkspaceRepository workspaceRepository, {
  _FakeCliAdapterRepository? adapterRepository,
  _FakeCachedConversationRepository? conversationRepository,
  _FakeCachedRunRepository? runRepository,
  WorkspaceOpeningUseCase? openWorkspace,
}) {
  return WorkbenchViewModel(
    workspaceRepository: workspaceRepository,
    adapterRepository: adapterRepository ?? _FakeCliAdapterRepository(),
    conversationRepository:
        conversationRepository ?? _FakeCachedConversationRepository(),
    runRepository: runRepository ?? _FakeCachedRunRepository(),
    workspaceOpeningUseCase: openWorkspace,
  );
}
```

- [ ] **Step 6: Run Workbench state tests**

Run:

```powershell
cd mobile
flutter test test/workbench_view_model_repository_state_test.dart -r expanded
flutter test test/conversation_reducer_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add docs/superpowers/progress/2026-06-01-workbench-view-model-boundary-audit.md mobile/test/workbench_view_model_repository_state_test.dart mobile/test/conversation_reducer_test.dart
git commit -m "Audit workbench state extraction boundaries"
```

---

## Task 7: Extract Workbench Page-Side Controllers Only Where Tests Support It

**Files:**
- Create if boundary is clean: `mobile/lib/src/ui/features/workbench/controllers/conversation_event_subscription_controller.dart`
- Create if boundary is clean: `mobile/lib/src/ui/features/workbench/controllers/slash_command_menu_controller.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/widget_test.dart`
- Test: `mobile/test/workbench_view_model_repository_state_test.dart`

- [ ] **Step 1: Review subscription markers**

Run:

```powershell
rg -n "Slice 3 subscription ownership" mobile\lib\src\ui\features\workbench\coding_workbench_page.dart
```

Expected: markers exist for route reset, session open, route switch, initial event page, background disconnect, and live subscription restart.

- [ ] **Step 2: Decide extraction boundary**

If the marker review shows subscription behavior still depends heavily on route navigation and mounted state, leave subscription ownership in `CodingWorkbenchPageState` and only move pure helper functions. If a clean boundary exists, create `conversation_event_subscription_controller.dart` with explicit callbacks for:

```dart
typedef ConversationEventApplier = Future<void> Function(ConversationEvent event);
typedef SubscriptionErrorReporter = Future<void> Function(Object error, StackTrace stackTrace);
```

Do not let the controller navigate routes or mutate ViewModel route state directly.

- [ ] **Step 3: Extract slash-command token parsing if isolated**

If `_SlashToken` parsing and visible command filtering can be tested without widget context, move `_SlashToken` and token detection helpers into `controllers/slash_command_menu_controller.dart`. Keep overlay positioning and `TextEditingController` ownership in the widget.

- [ ] **Step 4: Add focused controller tests if controllers are created**

Create tests next to existing Workbench tests. Example for token parsing:

```dart
test('slash command token parser returns token only at prompt command position', () {
  final token = SlashCommandMenuController.findToken('/he');
  expect(token?.prefix, '/he');

  expect(SlashCommandMenuController.findToken('say /he'), isNull);
});
```

- [ ] **Step 5: Run route/subscription widget tests**

Run:

```powershell
cd mobile
flutter test test/widget_test.dart --plain-name "CodingWorkbenchPage" -r expanded
flutter test test/workbench_view_model_repository_state_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Run architecture and analyze checks**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/ui/features/workbench mobile/test
git commit -m "Extract safe workbench page controllers"
```

---

## Task 8: Extract WorkbenchViewModel Pure Helpers Only After Cycle Check

**Files:**
- Create if cycle-free: `mobile/lib/src/ui/features/workbench/view_models/workbench_route_state.dart`
- Create if cycle-free: `mobile/lib/src/ui/features/workbench/view_models/workbench_conversation_event_state.dart`
- Create if cycle-free: `mobile/lib/src/ui/features/workbench/view_models/workbench_draft_attachment_state.dart`
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench.dart`
- Test: `mobile/test/workbench_view_model_repository_state_test.dart`
- Test: `mobile/test/conversation_reducer_test.dart`

- [ ] **Step 1: Re-read the boundary audit**

Open `docs/superpowers/progress/2026-06-01-workbench-view-model-boundary-audit.md`. If the audit shows cycles between route, event, attachment, and approval/model state, do not split mutable state objects. Extract only pure value helpers.

- [ ] **Step 2: Extract route value object only if acyclic**

If route state has no dependency on event or attachment state, create `workbench_route_state.dart`:

```dart
class WorkbenchRouteState {
  const WorkbenchRouteState({
    this.routeWorkspaceId,
    this.activeConversationId,
  });

  final String? routeWorkspaceId;
  final String? activeConversationId;

  WorkbenchRouteState showWorkspaceList() => const WorkbenchRouteState();

  WorkbenchRouteState showSessions(String workspaceId) =>
      WorkbenchRouteState(routeWorkspaceId: workspaceId);

  WorkbenchRouteState showConversation({
    required String workspaceId,
    required String conversationId,
  }) =>
      WorkbenchRouteState(
        routeWorkspaceId: workspaceId,
        activeConversationId: conversationId,
      );
}
```

Use it only if it reduces condition duplication without requiring callbacks into event state.

- [ ] **Step 3: Extract event-state pure functions only if acyclic**

If event application is already handled by `conversation_reducer.dart`, prefer keeping it there. Extract only small pure helpers for pagination cursor decisions or duplicate filtering. Do not create a mutable `WorkbenchConversationEventState` that calls back into route state.

- [ ] **Step 4: Extract draft attachment helper only if acyclic**

Extract pure validation or client-message-id helper functions only. Pass active conversation id and draft lists as values. Do not let an attachment helper read route state or repositories directly.

- [ ] **Step 5: Run Workbench state tests after each extraction**

After each helper extraction, run:

```powershell
cd mobile
flutter test test/workbench_view_model_repository_state_test.dart -r expanded
flutter test test/conversation_reducer_test.dart -r expanded
```

Expected: PASS after each small extraction.

- [ ] **Step 6: Run architecture and analyze checks**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

- [ ] **Step 7: Commit**

```powershell
git add mobile/lib/src/ui/features/workbench mobile/test/workbench_view_model_repository_state_test.dart mobile/test/conversation_reducer_test.dart
git commit -m "Extract workbench view model helpers"
```

---

## Task 9: Final Cleanup And Verification

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`
- Modify: `mobile/lib/src/ui/features/workspace_picker/workspace_picker_sheet.dart`
- Modify: `mobile/lib/src/ui/features/settings/settings_page.dart`
- Modify: `mobile/lib/src/ui/features/*/*.dart` imports as needed.
- Modify: `docs/project-knowledge/module-boundaries.md` only if implementation establishes a durable new boundary not already covered there.

- [ ] **Step 1: Check compatibility export usage**

Run:

```powershell
rg -n "workbench_event_cards.dart|workspace_picker_sheet.dart|features/settings/settings_page.dart" mobile\lib mobile\test
```

If only compatibility barrels or public exports reference a file, keep the compatibility file for external/public imports unless the public barrel already replaces it everywhere.

- [ ] **Step 2: Check oversized file regression**

Run:

```powershell
Get-ChildItem -Path mobile\lib\src\ui -Recurse -Filter *.dart | Select-Object FullName,Length | Sort-Object Length -Descending | Select-Object -First 20
```

Expected: `workbench_event_cards.dart`, `coding_workbench_page.dart`, `workspace_picker_sheet.dart`, and `settings_page.dart` are smaller and act as entry/compatibility files or lean composers.

- [ ] **Step 3: Run full mobile architecture and analyze checks**

Run:

```powershell
cd mobile
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\check_architecture_imports.dart
& 'D:\flutter_windows_3.41.9-stable\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
```

Expected: PASS.

- [ ] **Step 4: Run focused mobile test set**

Run:

```powershell
cd mobile
flutter test test/architecture_imports_tool_test.dart -r expanded
flutter test test/workbench_view_model_repository_state_test.dart -r expanded
flutter test test/conversation_reducer_test.dart -r expanded
flutter test test/settings_view_model_test.dart -r expanded
flutter test test/app_update_panel_test.dart -r expanded
flutter test test/widget_test.dart -r expanded
```

Expected: PASS, unless the first run times out. If a command times out, stop retrying and report the exact command and timeout.

- [ ] **Step 5: Decide whether project knowledge needs an update**

If implementation adds a durable boundary beyond the existing `module-boundaries.md` and this spec, update the smallest relevant `docs/project-knowledge/` file. If the implementation only follows this spec, no project-knowledge update is needed.

- [ ] **Step 6: Commit final cleanup**

```powershell
git add mobile docs/project-knowledge
git commit -m "Complete mobile UI component decoupling"
```

---

## Self-Review Checklist

- Spec coverage: Tasks cover Workbench message rendering, Workbench route/overlay split, route-sensitive subscription markers, barrel consistency guard, Workspace Picker split, shared workspace presentation helper ownership, Settings split, Workbench controller/ViewModel safety gates, and final verification.
- Placeholder scan: No task uses an unresolved placeholder. Conditional extraction tasks specify what to do when the boundary is not clean.
- Type consistency: Public names used in the plan match current symbols or explicitly rename private widgets to public feature-local widgets.
- Scope: The plan does not implement product behavior changes and does not move main/Home into `ui/features`.
