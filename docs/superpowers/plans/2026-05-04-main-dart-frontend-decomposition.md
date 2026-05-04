# Main Dart Frontend Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose `mobile/lib/main.dart` into cohesive Flutter frontend modules while preserving behavior and tests.

**Architecture:** Keep existing protocol, service, and reducer layers stable. Move app bootstrapping, shell composition, feature widgets, shared visual atoms, and testing helpers into explicit modules under `mobile/lib/src/`, with feature-to-feature communication routed through shell callbacks and shared model/state types.

**Tech Stack:** Flutter, Dart, Material 3, `flutter_markdown`, existing `src/models`, `src/services`, and `src/state` modules.

---

## File Structure

### Create

- `mobile/lib/src/app/app.dart` — Owns `LanAiCliControlApp` and `MaterialApp` configuration.
- `mobile/lib/src/app/app_localization.dart` — Owns locale constants and localization delegates.
- `mobile/lib/src/app/app_theme.dart` — Owns app colors, typography, and `ThemeData` construction.
- `mobile/lib/src/shell/mobile_shell.dart` — Owns app composition, route selection, and page callback wiring.
- `mobile/lib/src/shell/shell_routes.dart` — Owns shell route enum and navigation specs.
- `mobile/lib/src/shell/top_bar.dart` — Owns the top bar widget.
- `mobile/lib/src/shell/bottom_nav.dart` — Owns bottom navigation widgets.
- `mobile/lib/src/features/workbench/coding_workbench_page.dart` — Owns the workbench page and page-level state.
- `mobile/lib/src/features/workbench/coding_composer.dart` — Owns composer input, send/cancel buttons, model pill, and composer icons.
- `mobile/lib/src/features/workbench/workbench_messages.dart` — Owns workbench message mapping and transcript view models.
- `mobile/lib/src/features/workbench/workbench_event_cards.dart` — Owns command, diff, approval, question, system, thinking, agent, and pending event cards.
- `mobile/lib/src/features/workbench/workbench_presenter.dart` — Owns workbench pure helper functions used by UI and tests.
- `mobile/lib/src/features/workbench/markdown_body.dart` — Owns assistant markdown rendering.
- `mobile/lib/src/features/workbench/approval_page.dart` — Owns full-page approval preview from workbench conversation data.
- `mobile/lib/src/features/sessions/coding_session_list_page.dart` — Owns session list page layout and interactions.
- `mobile/lib/src/features/sessions/session_cards.dart` — Owns session card, run row, empty state, and grouping widgets.
- `mobile/lib/src/features/sessions/session_helpers.dart` — Owns session merge and visual-state helpers.
- `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart` — Owns workspace picker and first-run workspace sheets.
- `mobile/lib/src/features/workspace_picker/directory_browser_sheet.dart` — Owns directory browser sheet and directory rows.
- `mobile/lib/src/features/workspace_picker/workspace_rows.dart` — Owns workspace picker row/header widgets.
- `mobile/lib/src/features/settings/settings_page.dart` — Owns settings page layout.
- `mobile/lib/src/features/settings/settings_widgets.dart` — Owns settings-only card, row, metric, pill, and action widgets.
- `mobile/lib/src/features/run_detail/run_detail_page.dart` — Owns run detail page layout.
- `mobile/lib/src/features/run_detail/run_detail_widgets.dart` — Owns run detail timeline, diff, preview, and buttons.
- `mobile/lib/src/features/adapters/adapters_page.dart` — Owns adapters page and adapter row.
- `mobile/lib/src/features/notifications/notifications_page.dart` — Owns notifications page and notice widgets.
- `mobile/lib/src/features/diagnostics/diagnostics_page.dart` — Owns diagnostics page and diagnostic row widgets.
- `mobile/lib/src/widgets/cards.dart` — Owns feature-agnostic card widgets used by multiple features.
- `mobile/lib/src/widgets/buttons.dart` — Owns feature-agnostic button widgets used by multiple features.
- `mobile/lib/src/widgets/badges.dart` — Owns feature-agnostic status badge, pill, and icon widgets used by multiple features.
- `mobile/lib/src/widgets/inputs.dart` — Owns feature-agnostic input widgets used by multiple features.
- `mobile/lib/src/widgets/effects.dart` — Owns feature-agnostic visual effects and simple animation atoms.
- `mobile/lib/src/testing/debug_helpers.dart` — Owns `@visibleForTesting` debug helpers currently exported from `main.dart`.
- `mobile/lib/src/testing/widget_previews.dart` — Owns `@visibleForTesting` widget preview builders currently exported from `main.dart`.

### Modify

- `mobile/lib/main.dart` — Reduce to a thin app launcher.
- `mobile/lib/lan_ai_cli_control.dart` — Export stable public app/testing entry points when tests or external consumers require them.
- `mobile/test/widget_test.dart` — Import new app/testing modules instead of `main.dart` helpers.
- `mobile/test/conversation_reducer_test.dart` — No intended production-code import changes unless helper imports move.
- `mobile/test/protocol_compatibility_test.dart` — No intended production-code import changes unless helper imports move.

### Preserve

- `mobile/lib/src/models/protocol.dart` — Keep protocol model shapes unchanged.
- `mobile/lib/src/services/conversation_client.dart` — Keep conversation API behavior unchanged.
- `mobile/lib/src/services/daemon_client.dart` — Keep daemon API behavior unchanged.
- `mobile/lib/src/state/conversation_reducer.dart` — Keep reducer behavior unchanged.
- `mobile/lib/src/state/dashboard_state.dart` — Keep dashboard state behavior unchanged.
- `mobile/lib/src/state/run_detail_state.dart` — Keep run detail state behavior unchanged.

## Guardrails

- Do not add dependencies.
- Do not redesign UI.
- Do not change daemon API or protocol JSON parsing.
- Do not import feature files from another feature; route through shell callbacks or shared `src/models`/`src/state` types.
- Do not export leaf widgets from feature barrel files.
- Preserve StatefulWidget keys and constructor parameters during file moves.
- Keep each task compiling before moving to the next task.
- Use Lore-style commit messages if committing manually; this plan does not require automatic commits.

## Task 1: Lock Current Behavior

**Files:**
- Read: `mobile/test/widget_test.dart`
- Read: `mobile/test/conversation_reducer_test.dart`
- Read: `mobile/test/protocol_compatibility_test.dart`
- Read: `mobile/lib/main.dart`

- [ ] **Step 1: Run Flutter tests before refactor**

Run: `cd mobile && flutter test`

Expected: PASS. If this fails before changes, save the failure output and do not refactor until the baseline is understood.

- [ ] **Step 2: Run Flutter analyzer before refactor**

Run: `cd mobile && flutter analyze`

Expected: No new analyzer errors. Existing warnings, if any, must be recorded before changing code.

- [ ] **Step 3: Record current `main.dart` public testing surface**

Confirm these functions are present and must remain available through `src/testing` after extraction:

```dart
buildAssistantMarkdownPreview
debugVisibleWorkbenchBodyFromEvent
debugMergeSessionRunIds
debugMergeSessionIds
debugConversationPendingStatusText
debugShouldPollAfterApproval
debugHasExplicitWorkspaceSelection
debugVisibleApprovalIdsForConversation
debugWorkbenchMessageRolesForConversationEvents
debugEmptyConversationCompletionDiagnostic
buildRunningComposerPreview
buildNewSessionWorkspacePickerPreview
debugWorkbenchMessageRolesAfterEvents
debugSameCommandDisplay
buildCodingSessionListPreview
buildCodingWorkbenchEntryPreview
buildCompletedCommandCardPreview
buildConversationCommandCardPreview
buildPendingSentinelPreview
```

Expected: The list matches `rg "@visibleForTesting|debug|Preview" mobile/lib/main.dart`.

## Task 2: Extract App Infrastructure

**Files:**
- Create: `mobile/lib/src/app/app_localization.dart`
- Create: `mobile/lib/src/app/app_theme.dart`
- Create: `mobile/lib/src/app/app.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`

- [ ] **Step 1: Create app localization module**

Create `mobile/lib/src/app/app_localization.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const appZhHansCnLocale = Locale.fromSubtags(
    languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');

const appSupportedLocales = <Locale>[
  appZhHansCnLocale,
  Locale('en', 'US'),
];

const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
```

- [ ] **Step 2: Create app theme module**

Create `mobile/lib/src/app/app_theme.dart` with the existing color values from `main.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_localization.dart';

const appBg = Color(0xFF0A0B0D);
const appPanel = Color(0xE6111214);
const appPanelHi = Color(0xF2161719);
const appStroke = Color(0x16FFFFFF);
const appPurple = Color(0xFFA78BFA);
const appPurple2 = Color(0xFF8AB4FF);
const appActive = Color(0xFFE3E6EA);
const appActivePanel = Color(0xFF1B2027);
const appActiveStroke = Color(0xFF44505C);
const appGreen = Color(0xFF32D583);
const appAmber = Color(0xFFF2C572);
const appRed = Color(0xFFFF6B6B);
const appOrange = Color(0xFFF2C572);
const appText = Color(0xFFEDEDED);
const appMuted = Color(0xFFA9ADB5);
const appFaint = Color(0xFF747982);

const appFontFallback = <String>[
  'PingFang SC',
  'Microsoft YaHei UI',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'sans-serif',
];

const appTextStyle = TextStyle(
    fontFamily: 'Segoe UI',
    fontFamilyFallback: appFontFallback,
    locale: appZhHansCnLocale);

ThemeData buildAppTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: appBg,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: appFontFallback,
      colorScheme: const ColorScheme.dark(
          primary: appPurple, surface: appPanel, onSurface: appText),
      textTheme: const TextTheme(
          bodyMedium: appTextStyle,
          bodyLarge: appTextStyle,
          bodySmall: appTextStyle),
      useMaterial3: true,
    );
```

- [ ] **Step 3: Create app entry module**

Create `mobile/lib/src/app/app.dart`:

```dart
import 'package:flutter/material.dart';

import '../shell/mobile_shell.dart';
import 'app_localization.dart';
import 'app_theme.dart';

class LanAiCliControlApp extends StatelessWidget {
  const LanAiCliControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI CLI 控制台',
      locale: appZhHansCnLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: buildAppTheme(),
      home: const MobileShell(),
    );
  }
}
```

- [ ] **Step 4: Reduce main launcher**

After shell extraction exists in Task 3, reduce `mobile/lib/main.dart` to:

```dart
import 'package:flutter/material.dart';

import 'src/app/app.dart';

void main() => runApp(const LanAiCliControlApp());
```

- [ ] **Step 5: Export app entry**

Append this export to `mobile/lib/lan_ai_cli_control.dart` if tests or consumers import the app from the package root:

```dart
export 'src/app/app.dart';
```

- [ ] **Step 6: Verify app infrastructure compiles**

Run: `cd mobile && flutter analyze`

Expected: No missing imports for app theme, locale, or `LanAiCliControlApp`.

## Task 3: Extract Shell and Route Boundaries

**Files:**
- Create: `mobile/lib/src/shell/shell_routes.dart`
- Create: `mobile/lib/src/shell/mobile_shell.dart`
- Create: `mobile/lib/src/shell/top_bar.dart`
- Create: `mobile/lib/src/shell/bottom_nav.dart`
- Modify: `mobile/lib/main.dart`

- [ ] **Step 1: Create route enum and nav spec module**

Create `mobile/lib/src/shell/shell_routes.dart` by moving `_RoutePage` and `_NavSpec` from `main.dart`, renaming them:

```dart
import 'package:flutter/material.dart';

enum RoutePage { tabs, detail, approval, adapters, notifications, diagnostics }

class NavSpec {
  const NavSpec(this.icon, this.label);

  final IconData icon;
  final String label;
}
```

- [ ] **Step 2: Create top bar module**

Create `mobile/lib/src/shell/top_bar.dart` by moving `_TopBar` and renaming it to `TopBar`. Replace private color names with `appText`, `appMuted`, `appStroke`, and related app theme constants.

The constructor should keep the same inputs as the original widget:

```dart
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
}
```

- [ ] **Step 3: Create bottom navigation module**

Create `mobile/lib/src/shell/bottom_nav.dart` by moving `_BottomNav`, `_FloatingPlus`, and route navigation helpers. Rename them to `BottomNav` and `FloatingPlus`.

Use this public constructor shape:

```dart
class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.onCreate,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onCreate;
}
```

- [ ] **Step 4: Create shell module with composition only**

Create `mobile/lib/src/shell/mobile_shell.dart` by moving `MobileShell`, `_MobileShellState`, `_AppSnapshot`, `_ConnectionError`, `_PhoneFrame`, `_HomePage`, `_RunsPage`, `_QueuePage`, and `_Tabs` from `main.dart`.

Rename private types that cross files:

```dart
class MobileShell extends StatefulWidget { ... }
class AppSnapshot { ... }
class ConnectionError extends StatelessWidget { ... }
class PhoneFrame extends StatelessWidget { ... }
class HomePage extends StatelessWidget { ... }
class RunsPage extends StatelessWidget { ... }
class QueuePage extends StatelessWidget { ... }
class Tabs extends StatelessWidget { ... }
```

Keep `_MobileShellState` private because it remains in the same file.

- [ ] **Step 5: Prevent shell from becoming a new monolith**

If moving `MobileShell` exposes polling or client lifecycle code larger than the page-selection responsibilities, create a follow-up extraction inside the same task before moving feature widgets:

```dart
// mobile/lib/src/state/mobile_shell_controller.dart
class MobileShellController {
  MobileShellController({required this.daemonClient, required this.conversationClient});

  final DaemonClient daemonClient;
  final ConversationClient conversationClient;

  Future<DashboardState> loadDashboard() => DashboardState.load(daemonClient);
}
```

Only add this controller if it can wrap existing calls without changing behavior. Otherwise document the remaining controller extraction as follow-up in the final report.

- [ ] **Step 6: Verify shell extraction compiles**

Run: `cd mobile && flutter analyze`

Expected: No unresolved references to `_RoutePage`, `_TopBar`, `_BottomNav`, `_PhoneFrame`, or moved shell classes.

## Task 4: Extract Shared Presentation Atoms

**Files:**
- Create: `mobile/lib/src/widgets/cards.dart`
- Create: `mobile/lib/src/widgets/buttons.dart`
- Create: `mobile/lib/src/widgets/badges.dart`
- Create: `mobile/lib/src/widgets/inputs.dart`
- Create: `mobile/lib/src/widgets/effects.dart`
- Modify: `mobile/lib/main.dart`
- Modify: moved feature/shell files that use shared atoms

- [ ] **Step 1: Move card atoms used by multiple features**

Move `_GlassCard` and `_MetricCard` to `cards.dart` only if they are used by at least two features after extraction. Rename them:

```dart
class AppGlassCard extends StatelessWidget { ... }
class AppMetricCard extends StatelessWidget { ... }
```

Do not move `_SettingsCard` because it is settings-only.

- [ ] **Step 2: Move button atoms used by multiple features**

Move `_PrimaryButton`, `_GhostButton`, and `_TinyActionButton` to `buttons.dart` only if they are used by at least two features. Rename them:

```dart
class AppPrimaryButton extends StatelessWidget { ... }
class AppGhostButton extends StatelessWidget { ... }
class AppTinyActionButton extends StatelessWidget { ... }
```

Do not move `_ApprovalActionButton` because approval rendering belongs to workbench.

- [ ] **Step 3: Move badge and pill atoms used by multiple features**

Move `_Pill`, `_StatusBadge`, and `_AgentIcon` to `badges.dart` only if they are used by at least two features. Rename them:

```dart
class AppPill extends StatelessWidget { ... }
class AppStatusBadge extends StatelessWidget { ... }
class AppAgentIcon extends StatelessWidget { ... }
```

Do not move `_SettingsPill` or `_PermissionChip` because they are settings-only.

- [ ] **Step 4: Move input atoms used by multiple features**

Move `_MiniInput` and `_SearchBar` to `inputs.dart` only if both remain multi-feature. Rename them:

```dart
class AppMiniInput extends StatelessWidget { ... }
class AppSearchBar extends StatelessWidget { ... }
```

If either is used by one feature only, keep it in that feature folder.

- [ ] **Step 5: Move visual effects used by multiple features**

Move `_Hairline`, `_Dot`, `_Glow`, `_RunningOrb`, `_PulseBars`, and `_PulseDot` to `effects.dart` only if they are multi-feature or part of a multi-feature loading atom. Rename them:

```dart
class AppHairline extends StatelessWidget { ... }
class AppDot extends StatelessWidget { ... }
class AppGlow extends StatelessWidget { ... }
class AppRunningOrb extends StatelessWidget { ... }
class AppPulseBars extends StatelessWidget { ... }
class AppPulseDot extends StatelessWidget { ... }
```

- [ ] **Step 6: Verify shared widgets are not a dumping ground**

Run: `rg "class App" mobile/lib/src/widgets`

Expected: Only widgets used by at least two features are present in `src/widgets`.

- [ ] **Step 7: Verify shared atoms compile**

Run: `cd mobile && flutter analyze`

Expected: No missing shared widget imports and no feature-specific model imports inside `mobile/lib/src/widgets`.

## Task 5: Extract Workbench Presenter and Message Models

**Files:**
- Create: `mobile/lib/src/features/workbench/workbench_messages.dart`
- Create: `mobile/lib/src/features/workbench/workbench_presenter.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/src/testing/debug_helpers.dart` after Task 10

- [ ] **Step 1: Move pure workbench helpers first**

Move these functions/classes from `main.dart` into `workbench_presenter.dart` or `workbench_messages.dart` without changing behavior:

```dart
class WorkbenchMessage { ... }
enum VisibleTextKind { delta, finalMessage }
class VisibleText { ... }
class SessionItem { ... }
bool shouldPollAfterApproval(ConversationSummary conversation) => ...;
bool hasExplicitWorkspaceSelectionState({ ... }) => ...;
String? emptyConversationCompletionDiagnostic(...) => ...;
String? commandOutput(WorkbenchMessage message) => ...;
String? formatCommandDuration(Duration? duration) => ...;
```

Keep the original logic body exactly the same, except for removing leading underscores from symbols that cross files.

- [ ] **Step 2: Keep compatibility wrappers temporarily**

In `main.dart`, keep private wrappers only until all callers move:

```dart
bool _shouldPollAfterApproval(ConversationSummary conversation) =>
    shouldPollAfterApproval(conversation);
```

Delete wrappers in Task 10 after tests import `src/testing/debug_helpers.dart`.

- [ ] **Step 3: Verify presenter extraction compiles**

Run: `cd mobile && flutter analyze`

Expected: No unresolved references to `_WorkbenchMessage`, `_SessionItem`, `_VisibleText`, or moved helper functions.

## Task 6: Extract Workbench Event Cards

**Files:**
- Create: `mobile/lib/src/features/workbench/workbench_event_cards.dart`
- Create: `mobile/lib/src/features/workbench/markdown_body.dart`
- Modify: `mobile/lib/src/features/workbench/workbench_messages.dart`
- Modify: `mobile/lib/main.dart`

- [ ] **Step 1: Move markdown renderer**

Move `_AssistantMarkdownBody` to `markdown_body.dart` and rename it:

```dart
class AssistantMarkdownBody extends StatelessWidget {
  const AssistantMarkdownBody({super.key, required this.markdown});

  final String markdown;
}
```

The widget body should stay identical except imports and app theme constant names.

- [ ] **Step 2: Move message cards and inline status**

Move and rename these widgets to `workbench_event_cards.dart`:

```dart
class WorkbenchInlineStatus extends StatelessWidget { ... }
class WorkbenchMessageCard extends StatelessWidget { ... }
class QuestionEventCard extends StatelessWidget { ... }
class SystemNoticeEventCard extends StatelessWidget { ... }
class ThinkingEventCard extends StatelessWidget { ... }
class ExpandableThinkingCard extends StatefulWidget { ... }
class QuestionSuggestionChip extends StatelessWidget { ... }
```

Preserve constructor parameters and keys. Keep `_ExpandableThinkingCardState` private in the new file.

- [ ] **Step 3: Move command and event detail cards**

Move and rename these widgets to `workbench_event_cards.dart`:

```dart
class ApprovalActionButton extends StatelessWidget { ... }
class CommandEventCard extends StatelessWidget { ... }
class CommandDetailSheet extends StatelessWidget { ... }
class DiffEventCard extends StatelessWidget { ... }
class ApprovalEventCard extends StatelessWidget { ... }
class AgentEventCard extends StatelessWidget { ... }
class EventCodeLine extends StatelessWidget { ... }
class PendingSentinel extends StatefulWidget { ... }
```

Keep `_PendingSentinelState` private in the new file. Preserve all existing keys and animation controllers.

- [ ] **Step 4: Verify workbench cards compile**

Run: `cd mobile && flutter analyze`

Expected: No unresolved references to moved workbench card widgets and no imports from other feature folders.

## Task 7: Extract Workbench Composer and Page

**Files:**
- Create: `mobile/lib/src/features/workbench/coding_composer.dart`
- Create: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Create: `mobile/lib/src/features/workbench/approval_page.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`
- Modify: `mobile/lib/main.dart`

- [ ] **Step 1: Move composer widgets**

Move and rename these widgets to `coding_composer.dart`:

```dart
class CodingComposer extends StatelessWidget { ... }
class ComposerWorkspaceCloud extends StatelessWidget { ... }
class SendPromptButton extends StatelessWidget { ... }
class ComposerModelPill extends StatelessWidget { ... }
class ComposerIcon extends StatelessWidget { ... }
class SendGlyph extends StatelessWidget { ... }
class SendGlyphPainter extends CustomPainter { ... }
```

Keep constructor parameters identical and preserve the existing `TextEditingController` ownership rules.

- [ ] **Step 2: Move workbench page**

Move `_CodingWorkbenchPage`, `_CodingWorkbenchPageState`, and `_CodingHeader` to `coding_workbench_page.dart`. Rename only public crossing symbols:

```dart
class CodingWorkbenchPage extends StatefulWidget { ... }
class CodingHeader extends StatelessWidget { ... }
```

Keep `_CodingWorkbenchPageState` private in the new file.

- [ ] **Step 3: Handle shell-owned state through constructor inputs**

If `CodingWorkbenchPage` needs values currently held by `MobileShell`, pass them as constructor parameters rather than importing shell internals:

```dart
class CodingWorkbenchPage extends StatefulWidget {
  const CodingWorkbenchPage({
    super.key,
    required this.snapshot,
    required this.onOpenSettings,
    required this.onOpenApproval,
  });

  final AppSnapshot snapshot;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenApproval;
}
```

If `AppSnapshot` creates a reverse dependency, move only the shared snapshot shape to `src/state` or pass narrower fields.

- [ ] **Step 4: Move approval page into workbench**

Move `_ApprovalPage` to `features/workbench/approval_page.dart` and rename it:

```dart
class ApprovalPage extends StatelessWidget { ... }
```

Do not create `features/approvals/`. Approval rendering remains a workbench sub-feature.

- [ ] **Step 5: Verify workbench page compiles**

Run: `cd mobile && flutter analyze`

Expected: No feature-to-feature imports from workbench, and no shell internals imported into workbench files.

## Task 8: Extract Sessions and Workspace Picker

**Files:**
- Create: `mobile/lib/src/features/sessions/coding_session_list_page.dart`
- Create: `mobile/lib/src/features/sessions/session_cards.dart`
- Create: `mobile/lib/src/features/sessions/session_helpers.dart`
- Create: `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart`
- Create: `mobile/lib/src/features/workspace_picker/directory_browser_sheet.dart`
- Create: `mobile/lib/src/features/workspace_picker/workspace_rows.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`

- [ ] **Step 1: Move session helper data**

Move `_SessionRunVisualState` and session merge helpers to `session_helpers.dart`:

```dart
class SessionRunVisualState { ... }
List<SessionItem> mergeSessionItems(...) => ...;
```

Keep behavior identical. If `SessionItem` is already in workbench messages, move it to `session_helpers.dart` if sessions are its main owner.

- [ ] **Step 2: Move session list page and cards**

Move and rename these widgets:

```dart
class CodingSessionListPage extends StatelessWidget { ... }
class SessionNewButton extends StatelessWidget { ... }
class SessionSearchBox extends StatelessWidget { ... }
class SessionGroupHeader extends StatelessWidget { ... }
class SessionStack extends StatelessWidget { ... }
class EmptySessionStack extends StatelessWidget { ... }
class SessionRunRow extends StatelessWidget { ... }
class ProjectSessionCard extends StatelessWidget { ... }
```

Keep session widgets inside `features/sessions/` unless they are used by two or more features.

- [ ] **Step 3: Move workspace picker sheets**

Move and rename these widgets:

```dart
class AdapterPickerSheet extends StatelessWidget { ... }
class AdapterChoiceRow extends StatelessWidget { ... }
class WorkspacePickerSheet extends StatefulWidget { ... }
class FirstRunWorkspaceSheet extends StatelessWidget { ... }
class CreateFirstRunWorkspaceSheet extends StatefulWidget { ... }
class WorkspaceSheetHeader extends StatelessWidget { ... }
class WorkspaceSectionHeader extends StatelessWidget { ... }
class WorkspaceChoiceRow extends StatelessWidget { ... }
```

Keep private state classes private in their new files.

- [ ] **Step 4: Move directory browser sheet**

Move and rename these widgets:

```dart
class DirectoryBrowserSheet extends StatefulWidget { ... }
class DirectoryRow extends StatelessWidget { ... }
```

Preserve directory browsing error handling and loading state exactly.

- [ ] **Step 5: Verify sessions/workspace extraction compiles**

Run: `cd mobile && flutter analyze`

Expected: No imports from `features/workbench` into `features/sessions` or `features/workspace_picker`.

## Task 9: Extract Remaining Pages

**Files:**
- Create: `mobile/lib/src/features/settings/settings_page.dart`
- Create: `mobile/lib/src/features/settings/settings_widgets.dart`
- Create: `mobile/lib/src/features/run_detail/run_detail_page.dart`
- Create: `mobile/lib/src/features/run_detail/run_detail_widgets.dart`
- Create: `mobile/lib/src/features/adapters/adapters_page.dart`
- Create: `mobile/lib/src/features/notifications/notifications_page.dart`
- Create: `mobile/lib/src/features/diagnostics/diagnostics_page.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`

- [ ] **Step 1: Move settings page and settings-only widgets**

Move and rename:

```dart
class SettingsPage extends StatelessWidget { ... }
class SettingsCard extends StatelessWidget { ... }
class SettingsConnectionCard extends StatelessWidget { ... }
class SettingsMetric extends StatelessWidget { ... }
class SettingsPill extends StatelessWidget { ... }
class SettingsActionButton extends StatelessWidget { ... }
class SettingsRow extends StatelessWidget { ... }
class PermissionModeRow extends StatelessWidget { ... }
class PermissionChip extends StatelessWidget { ... }
class SettingsSwitchRow extends StatelessWidget { ... }
class SectionTitle extends StatelessWidget { ... }
class Subhead extends StatelessWidget { ... }
```

Keep settings-only widgets out of `src/widgets`.

- [ ] **Step 2: Move run detail page and widgets**

Move and rename:

```dart
class RunDetailPage extends StatelessWidget { ... }
class Timeline extends StatelessWidget { ... }
class CodeDiff extends StatelessWidget { ... }
class ApprovalPreview extends StatelessWidget { ... }
```

If run detail needs workbench helpers, use shared `src/state` or `src/models` types instead of importing workbench files.

- [ ] **Step 3: Move adapters page**

Move and rename:

```dart
class AdaptersPage extends StatelessWidget { ... }
class AdapterRow extends StatelessWidget { ... }
```

- [ ] **Step 4: Move notifications page**

Move and rename:

```dart
class NotificationsPage extends StatelessWidget { ... }
class Notice extends StatelessWidget { ... }
```

- [ ] **Step 5: Move diagnostics page**

Move and rename:

```dart
class DiagnosticsPage extends StatelessWidget { ... }
class DiagRow extends StatelessWidget { ... }
```

- [ ] **Step 6: Verify remaining pages compile**

Run: `cd mobile && flutter analyze`

Expected: No feature-to-feature imports and no moved page references left in `main.dart`.

## Task 10: Move Testing Helpers and Update Tests

**Files:**
- Create: `mobile/lib/src/testing/debug_helpers.dart`
- Create: `mobile/lib/src/testing/widget_previews.dart`
- Modify: `mobile/test/widget_test.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`
- Modify: `mobile/lib/main.dart`

- [ ] **Step 1: Create debug helper module**

Move `@visibleForTesting` non-widget debug helpers into `debug_helpers.dart` and keep their public names unchanged:

```dart
@visibleForTesting
String? debugVisibleWorkbenchBodyFromEvent(Map<String, Object?> json,
        {bool streamOutput = false}) =>
    WorkbenchMessage.fromEvent(AgentEvent.fromJson(json), streamOutput)?.body;
```

Apply the same pattern for merge helpers, polling helpers, approval visibility helpers, and empty completion diagnostics.

- [ ] **Step 2: Create widget preview module**

Move `@visibleForTesting` widget preview builders into `widget_previews.dart` and keep public names unchanged:

```dart
@visibleForTesting
Widget buildAssistantMarkdownPreview(String markdown) => MaterialApp(
    locale: appZhHansCnLocale,
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    theme: buildAppTheme(),
    home: Scaffold(
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: AssistantMarkdownBody(markdown: markdown))));
```

Use the same module for composer, workspace picker, coding session list, workbench entry, command card, conversation command card, and pending sentinel previews.

- [ ] **Step 3: Export testing helpers if tests use package root**

Append to `mobile/lib/lan_ai_cli_control.dart` if needed:

```dart
export 'src/testing/debug_helpers.dart';
export 'src/testing/widget_previews.dart';
```

- [ ] **Step 4: Update widget tests imports**

Change `mobile/test/widget_test.dart` from importing `main.dart` to importing stable app/testing modules:

```dart
import 'package:lan_ai_cli_control/lan_ai_cli_control.dart';
import 'package:lan_ai_cli_control/src/testing/debug_helpers.dart';
import 'package:lan_ai_cli_control/src/testing/widget_previews.dart';
```

Remove `import 'package:lan_ai_cli_control/main.dart';`.

- [ ] **Step 5: Delete temporary compatibility wrappers**

Remove debug/preview helpers from `main.dart` after tests import `src/testing` directly.

- [ ] **Step 6: Verify testing surface compiles**

Run: `cd mobile && flutter analyze`

Expected: No test imports depend on `main.dart` helpers.

## Task 11: Final Thin Launcher and Import Cleanup

**Files:**
- Modify: `mobile/lib/main.dart`
- Modify: all new files under `mobile/lib/src/`

- [ ] **Step 1: Ensure `main.dart` is only launcher code**

Final `mobile/lib/main.dart` must be exactly this shape:

```dart
import 'package:flutter/material.dart';

import 'src/app/app.dart';

void main() => runApp(const LanAiCliControlApp());
```

- [ ] **Step 2: Check no feature imports another feature**

Run: `rg "features/.*/.*features/" mobile/lib/src/features`

Expected: No matches. If the command is too coarse on Windows paths, manually inspect feature imports with `rg "import '.*features/" mobile/lib/src/features`.

- [ ] **Step 3: Check widgets do not import models/services/state**

Run: `rg "src/(models|services|state)|\.\./(models|services|state)" mobile/lib/src/widgets`

Expected: No matches.

- [ ] **Step 4: Check no independent approvals feature exists**

Run: `Test-Path mobile/lib/src/features/approvals`

Expected: `False`.

- [ ] **Step 5: Check `main.dart` size**

Run: `(Get-Content mobile/lib/main.dart).Length`

Expected: Less than 10 lines.

## Task 12: Verification and Manual QA

**Files:**
- Modify: formatted Dart files under `mobile/lib/` and `mobile/test/`

- [ ] **Step 1: Format Dart files**

Run: `cd mobile && dart format lib test`

Expected: Formatter completes without syntax errors.

- [ ] **Step 2: Run analyzer**

Run: `cd mobile && flutter analyze`

Expected: No analyzer errors.

- [ ] **Step 3: Run tests**

Run: `cd mobile && flutter test`

Expected: All tests pass.

- [ ] **Step 4: Build debug app if local environment supports it**

Run: `cd mobile && flutter build windows --debug`

Expected: Windows debug build completes. If Windows build prerequisites are missing, record the exact missing prerequisite.

- [ ] **Step 5: Manual state preservation QA**

Run the app and verify:

```text
1. Open workbench and type into composer; navigate away and back; text behavior matches pre-refactor behavior.
2. Scroll a conversation transcript; new events or navigation do not unexpectedly reset scroll beyond existing behavior.
3. Pending sentinel and thinking card animations still animate smoothly.
4. Approval page renders the same active approval data as the workbench approval card.
5. Workspace picker and directory browser retain loading/error behavior.
```

Expected: No new lost input, broken animation, or unexpected scroll reset.

## Self-Review

- Spec coverage: The plan covers app, shell, workbench, approvals-as-workbench, sessions, workspace picker, settings, run detail, adapters, notifications, diagnostics, shared widgets, testing helpers, dependency rules, migration order, and StatefulWidget state risks.
- Placeholder scan: No `TBD`, `TODO`, `implement later`, or unresolved placeholder sections are intentionally present.
- Type consistency: Public names use the approved prefixes and avoid cross-feature imports. `ApprovalPage` is placed under workbench. Shared widgets use `App*` prefixes and are restricted to multi-feature use.
- Scope check: The plan is one presentation-layer decomposition and does not include daemon/API/state-management rewrites.
