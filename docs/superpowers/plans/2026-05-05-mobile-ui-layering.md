# Mobile UI Layering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move mobile UI ownership out of `shell` into a top-down `src/ui/` tree while preserving current behavior.

**Architecture:** Introduce `src/ui/` as the mobile UI root, move top-level pages into `src/ui/pages/`, and make `MainTabsPage` own tab navigation. Keep `AppSnapshot` loading and daemon bootstrap behavior unchanged during this plan; split data loading in a later architecture pass.

**Tech Stack:** Flutter/Dart, existing `DaemonClient`, existing `AppSnapshot`, existing feature barrels, existing `mobile/check.bat` verification.

---

## File Structure

Create:
- `mobile/lib/src/ui/ui.dart` - public UI barrel.
- `mobile/lib/src/ui/mobile_ui.dart` - root mobile UI state: client creation, snapshot future, loading/error/main composition. This is transitional until `AppSnapshot` is split later.
- `mobile/lib/src/ui/mobile_ui_frame.dart` - pure visual phone frame wrapper.
- `mobile/lib/src/ui/mobile_loading_page.dart` - loading state wrapped by `MobileUiFrame`.
- `mobile/lib/src/ui/mobile_connection_error_page.dart` - connection error state wrapped by `MobileUiFrame`.
- `mobile/lib/src/ui/main_tabs_page.dart` - bottom navigation and top-level tab/overlay coordination.
- `mobile/lib/src/ui/pages/pages.dart` - top-level pages barrel.
- `mobile/lib/src/ui/pages/home_page.dart` - extracted home tab page.
- `mobile/lib/src/ui/pages/runs_page.dart` - extracted runs tab page.
- `mobile/lib/src/ui/pages/queue_page.dart` - extracted queue tab page.
- `mobile/lib/src/ui/pages/run_status_color.dart` - shared UI helper for run status colors.
- `mobile/lib/src/ui/pages/coding/coding_pages.dart` - coding pages barrel.
- `mobile/lib/src/ui/pages/coding/coding_page.dart` - coding tab root and thin navigation boundary around the current workbench.

Modify:
- `mobile/lib/src/app/app.dart` - import `../ui/ui.dart` and use `MobileUi` as the home widget.
- `mobile/lib/src/shell/shell.dart` - stop exporting `mobile_shell.dart` after the shim is removed.
- `mobile/lib/lan_ai_cli_control.dart` - export `src/ui/ui.dart` for tests and package consumers.
- `mobile/test/widget_test.dart` - add or update UI layering smoke tests.

Delete at the end:
- `mobile/lib/src/shell/mobile_shell.dart`

Do not move in this plan:
- `mobile/lib/src/shell/app_snapshot.dart`
- `mobile/lib/src/shell/app_route.dart`
- `mobile/lib/src/services/*`
- `mobile/lib/src/state/*`

---

### Task 1: Add UI Frame and State Pages

**Files:**
- Create: `mobile/lib/src/ui/mobile_ui_frame.dart`
- Create: `mobile/lib/src/ui/mobile_loading_page.dart`
- Create: `mobile/lib/src/ui/mobile_connection_error_page.dart`
- Create: `mobile/lib/src/ui/ui.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write the failing frame smoke test**

Append this test to `mobile/test/widget_test.dart`:

```dart
testWidgets('MobileUiFrame renders supplied child', (WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: MobileUiFrame(child: Text('frame child')),
  ));

  expect(find.text('frame child'), findsOneWidget);
});
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
flutter test --no-pub test\widget_test.dart --plain-name "MobileUiFrame renders supplied child"
```

Expected: fail because `MobileUiFrame` is not defined.

- [ ] **Step 3: Create `mobile_ui_frame.dart`**

Create `mobile/lib/src/ui/mobile_ui_frame.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;
import '../widgets/widgets.dart';

class MobileUiFrame extends StatelessWidget {
  const MobileUiFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 390,
          height: 844,
          decoration: BoxDecoration(
            color: theme.bg,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withValues(alpha: .09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .45),
                blurRadius: 50,
                offset: const Offset(0, 28),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                top: -90,
                left: -80,
                child: Glow(
                  size: 260,
                  color: theme.green.withValues(alpha: .10),
                ),
              ),
              Positioned(
                bottom: -120,
                right: -120,
                child: Glow(
                  size: 260,
                  color: theme.purple.withValues(alpha: .08),
                ),
              ),
              child,
            ],
          ),
        ),
      );
}
```

- [ ] **Step 4: Create loading and error pages**

Create `mobile/lib/src/ui/mobile_loading_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;
import 'mobile_ui_frame.dart';

class MobileLoadingPage extends StatelessWidget {
  const MobileLoadingPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: MobileUiFrame(
          child: Center(
            child: CircularProgressIndicator(color: theme.purple),
          ),
        ),
      );
}
```

Create `mobile/lib/src/ui/mobile_connection_error_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;
import '../widgets/widgets.dart';
import 'mobile_ui_frame.dart';

class MobileConnectionErrorPage extends StatelessWidget {
  const MobileConnectionErrorPage({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: MobileUiFrame(
          child: PageScroll(children: [
            const TopBar(title: 'Connection failed'),
            const SizedBox(height: 32),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.wifi_off_rounded, color: theme.red, size: 34),
                  const SizedBox(height: 14),
                  const Text(
                    'Cannot connect to local daemon',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(error, style: const TextStyle(color: theme.muted, fontSize: 12)),
                  const SizedBox(height: 16),
                  PrimaryButton('Retry connection', onTap: onRetry),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              r'Run start-daemon.bat from D:\AiProject\vibe-coding. Windows preview connects to http://127.0.0.1:4317.',
              style: TextStyle(color: theme.muted, fontSize: 12, height: 1.5),
            ),
          ]),
        ),
      );
}
```

- [ ] **Step 5: Create the UI barrel**

Create `mobile/lib/src/ui/ui.dart`:

```dart
export 'mobile_connection_error_page.dart';
export 'mobile_loading_page.dart';
export 'mobile_ui_frame.dart';
```

- [ ] **Step 6: Export UI for tests**

Add this line to `mobile/lib/lan_ai_cli_control.dart`:

```dart
export 'src/ui/ui.dart';
```

- [ ] **Step 7: Run focused verification**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
dart format lib test
flutter test --no-pub test\widget_test.dart --plain-name "MobileUiFrame renders supplied child"
flutter analyze --no-pub
```

Expected: focused widget test passes and analyzer reports `No issues found!`.

- [ ] **Step 8: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add mobile/lib/lan_ai_cli_control.dart mobile/lib/src/ui mobile/test/widget_test.dart
git commit -m "Introduce mobile UI frame pages"
```

---

### Task 2: Extract Home, Runs, and Queue Pages

**Files:**
- Create: `mobile/lib/src/ui/pages/pages.dart`
- Create: `mobile/lib/src/ui/pages/run_status_color.dart`
- Create: `mobile/lib/src/ui/pages/home_page.dart`
- Create: `mobile/lib/src/ui/pages/runs_page.dart`
- Create: `mobile/lib/src/ui/pages/queue_page.dart`
- Modify: `mobile/lib/src/ui/ui.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`

- [ ] **Step 1: Create the pages barrel and status helper**

Create `mobile/lib/src/ui/pages/pages.dart`:

```dart
export 'home_page.dart';
export 'queue_page.dart';
export 'runs_page.dart';
```

Create `mobile/lib/src/ui/pages/run_status_color.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/theme.dart' as theme;

Color runStatusColor(String status) {
  final lower = status.toLowerCase();
  if (lower.contains('fail') || lower.contains('error')) return theme.red;
  if (lower.contains('run') || lower.contains('start')) return theme.green;
  if (lower.contains('wait') || lower.contains('queue')) return theme.amber;
  return theme.purple;
}
```

- [ ] **Step 2: Extract `HomePage`**

Create `mobile/lib/src/ui/pages/home_page.dart` by moving `_HomePage` from `mobile/lib/src/shell/mobile_shell.dart`.

Use these exact replacements while moving:

```text
class _HomePage -> class HomePage
const _HomePage -> const HomePage
_statusColor(run.status) -> runStatusColor(run.status)
```

Add these imports:

```dart
import 'package:flutter/material.dart';

import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';
import 'run_status_color.dart';
```

Keep this public constructor:

```dart
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.open,
    required this.selectTab,
    required this.data,
  });

  final ValueChanged<RoutePage> open;
  final ValueChanged<int> selectTab;
  final AppSnapshot data;
}
```

- [ ] **Step 3: Extract `RunsPage`**

Create `mobile/lib/src/ui/pages/runs_page.dart` by moving `_RunsPage` from `mobile/lib/src/shell/mobile_shell.dart`.

Use these exact replacements:

```text
class _RunsPage -> class RunsPage
const _RunsPage -> const RunsPage
_statusColor(run.status) -> runStatusColor(run.status)
```

Add these imports:

```dart
import 'package:flutter/material.dart';

import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';
import '../../widgets/widgets.dart';
import 'run_status_color.dart';
```

Keep this public constructor:

```dart
class RunsPage extends StatelessWidget {
  const RunsPage({super.key, required this.open, required this.data});

  final ValueChanged<RoutePage> open;
  final AppSnapshot data;
}
```

- [ ] **Step 4: Extract `QueuePage`**

Create `mobile/lib/src/ui/pages/queue_page.dart` by moving `_QueuePage` from `mobile/lib/src/shell/mobile_shell.dart`.

Use these exact replacements:

```text
class _QueuePage -> class QueuePage
const _QueuePage -> const QueuePage
```

Add these imports:

```dart
import 'package:flutter/material.dart';

import '../../shell/app_snapshot.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';
```

Keep this public constructor:

```dart
class QueuePage extends StatelessWidget {
  const QueuePage({super.key, required this.data});

  final AppSnapshot data;
}
```

- [ ] **Step 5: Export pages from UI barrel**

Add to `mobile/lib/src/ui/ui.dart`:

```dart
export 'pages/pages.dart';
```

- [ ] **Step 6: Update `mobile_shell.dart`**

Add:

```dart
import '../ui/ui.dart';
```

Replace:

```text
_HomePage(...) -> HomePage(...)
_RunsPage(...) -> RunsPage(...)
_QueuePage(...) -> QueuePage(...)
```

Delete these declarations from `mobile_shell.dart` after moving them:

```text
Color _statusColor(String status)
class _HomePage
class _RunsPage
class _QueuePage
```

- [ ] **Step 7: Verify extraction**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 8: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add mobile/lib/src/ui mobile/lib/src/shell/mobile_shell.dart
git commit -m "Move top-level tab pages into ui"
```

---

### Task 3: Introduce MainTabsPage

**Files:**
- Create: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/ui.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`

- [ ] **Step 1: Create `MainTabsPage`**

Create `mobile/lib/src/ui/main_tabs_page.dart` by moving the tab state and page assembly from `_MobileShellState`.

The new file must start with these imports:

```dart
import 'package:flutter/material.dart';

import '../features/adapters/adapters.dart';
import '../features/diagnostics/diagnostics.dart';
import '../features/notifications/notifications.dart';
import '../features/run_detail/run_detail.dart';
import '../features/settings/settings.dart';
import '../features/workbench/workbench.dart';
import '../services/daemon_client.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import '../widgets/widgets.dart';
import 'mobile_ui_frame.dart';
import 'pages/pages.dart';
```

Create the widget with this public API:

```dart
class MainTabsPage extends StatefulWidget {
  const MainTabsPage({super.key, required this.data, required this.client});

  final AppSnapshot data;
  final DaemonClient client;

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}
```

Move these fields and methods from `_MobileShellState` into `_MainTabsPageState`:

```dart
int _tab = 0;
bool _streamOutput = false;
bool _expandThinking = false;
String _permissionMode = 'default';
bool _codingSessionListOpen = true;
int _codingSessionListOpenRequest = 0;
RoutePage _route = RoutePage.tabs;

void _open(RoutePage route) => setState(() => _route = route);
void _back() => setState(() => _route = RoutePage.tabs);
void _selectTab(int index) => setState(() {
      _tab = index;
      _route = RoutePage.tabs;
      if (index == 2) {
        _codingSessionListOpen = true;
        _codingSessionListOpenRequest++;
      }
    });
```

Move `_items`, `pages`, `overlay`, `IndexedStack`, and `BottomNav` logic from `mobile_shell.dart` into `MainTabsPage`. Replace the outer `_PhoneFrame` with `MobileUiFrame`.

- [ ] **Step 2: Export `MainTabsPage`**

Add to `mobile/lib/src/ui/ui.dart`:

```dart
export 'main_tabs_page.dart';
```

- [ ] **Step 3: Replace tab composition in `mobile_shell.dart`**

After this task, `mobile_shell.dart` should still own only `_client`, `_snapshot`, `_refresh`, loading, and error branches.

In the success branch, return:

```dart
return MainTabsPage(data: snapshot.requireData, client: _client);
```

Delete these from `mobile_shell.dart` after moving them:

```text
_tab
_streamOutput
_expandThinking
_permissionMode
_codingSessionListOpen
_codingSessionListOpenRequest
_route
_open
_back
_selectTab
_items
```

- [ ] **Step 4: Verify main tab extraction**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 5: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add mobile/lib/src/ui mobile/lib/src/shell/mobile_shell.dart
git commit -m "Move main tab navigation into ui"
```

---

### Task 4: Introduce MobileUi Root and Shell Shim

**Files:**
- Create: `mobile/lib/src/ui/mobile_ui.dart`
- Modify: `mobile/lib/src/ui/ui.dart`
- Modify: `mobile/lib/src/app/app.dart`
- Modify: `mobile/lib/src/shell/mobile_shell.dart`

- [ ] **Step 1: Create `MobileUi`**

Create `mobile/lib/src/ui/mobile_ui.dart` by moving the remaining bootstrap logic from `MobileShell`:

```dart
import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../shell/app_snapshot.dart';
import 'main_tabs_page.dart';
import 'mobile_connection_error_page.dart';
import 'mobile_loading_page.dart';

class MobileUi extends StatefulWidget {
  const MobileUi({super.key});

  @override
  State<MobileUi> createState() => _MobileUiState();
}

class _MobileUiState extends State<MobileUi> {
  late final DaemonClient _client;
  late Future<AppSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
    );
    _snapshot = AppSnapshot.load(_client);
  }

  void _refresh() => setState(() => _snapshot = AppSnapshot.load(_client));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MobileLoadingPage();
        }
        if (snapshot.hasError) {
          return MobileConnectionErrorPage(
            error: snapshot.error.toString(),
            onRetry: _refresh,
          );
        }
        return MainTabsPage(data: snapshot.requireData, client: _client);
      },
    );
  }
}
```

- [ ] **Step 2: Export `MobileUi`**

Add to `mobile/lib/src/ui/ui.dart`:

```dart
export 'mobile_ui.dart';
```

- [ ] **Step 3: Point app entry at `MobileUi`**

In `mobile/lib/src/app/app.dart`, replace:

```dart
import '../shell/shell.dart';
```

with:

```dart
import '../ui/ui.dart';
```

Replace:

```dart
home: const MobileShell(),
```

with:

```dart
home: const MobileUi(),
```

- [ ] **Step 4: Turn `MobileShell` into a temporary shim**

Replace `mobile/lib/src/shell/mobile_shell.dart` with:

```dart
import 'package:flutter/material.dart';

import '../ui/ui.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context) => const MobileUi();
}
```

- [ ] **Step 5: Verify shim transition**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 6: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add mobile/lib/src/app/app.dart mobile/lib/src/ui mobile/lib/src/shell/mobile_shell.dart
git commit -m "Introduce mobile UI root"
```

---

### Task 5: Add Thin CodingPage Boundary

**Files:**
- Create: `mobile/lib/src/ui/pages/coding/coding_pages.dart`
- Create: `mobile/lib/src/ui/pages/coding/coding_page.dart`
- Modify: `mobile/lib/src/ui/pages/pages.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`

- [ ] **Step 1: Create coding pages barrel**

Create `mobile/lib/src/ui/pages/coding/coding_pages.dart`:

```dart
export 'coding_page.dart';
```

- [ ] **Step 2: Create `CodingPage` as a thin boundary**

Create `mobile/lib/src/ui/pages/coding/coding_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../features/workbench/workbench.dart';
import '../../../services/daemon_client.dart';
import '../../../shell/app_snapshot.dart';

class CodingPage extends StatelessWidget {
  const CodingPage({
    super.key,
    required this.data,
    required this.client,
    required this.onBack,
    required this.onSessionListChanged,
    required this.openSessionListRequest,
    required this.streamOutput,
    required this.expandThinking,
    required this.permissionMode,
  });

  final AppSnapshot data;
  final DaemonClient client;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  Widget build(BuildContext context) {
    return CodingWorkbenchPage(
      data: data,
      client: client,
      onBack: onBack,
      onSessionListChanged: onSessionListChanged,
      openSessionListRequest: openSessionListRequest,
      streamOutput: streamOutput,
      expandThinking: expandThinking,
      permissionMode: permissionMode,
    );
  }
}
```

- [ ] **Step 3: Export coding pages**

Add to `mobile/lib/src/ui/pages/pages.dart`:

```dart
export 'coding/coding_pages.dart';
```

- [ ] **Step 4: Use `CodingPage` in `MainTabsPage`**

In `mobile/lib/src/ui/main_tabs_page.dart`, replace the `CodingWorkbenchPage(...)` entry with:

```dart
CodingPage(
  data: data,
  client: widget.client,
  onBack: () => _selectTab(0),
  onSessionListChanged: (open) => setState(() => _codingSessionListOpen = open),
  openSessionListRequest: _codingSessionListOpenRequest,
  streamOutput: _streamOutput,
  expandThinking: _expandThinking,
  permissionMode: _permissionMode,
),
```

Remove the direct `features/workbench/workbench.dart` import from `main_tabs_page.dart` if it becomes unused.

- [ ] **Step 5: Verify coding boundary**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 6: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add mobile/lib/src/ui
git commit -m "Add coding page UI boundary"
```

---

### Task 6: Remove Shell Shim

**Files:**
- Delete: `mobile/lib/src/shell/mobile_shell.dart`
- Modify: `mobile/lib/src/shell/shell.dart`
- Modify: `mobile/lib/lan_ai_cli_control.dart`

- [ ] **Step 1: Confirm no direct `MobileShell` references**

Run:

```bat
cd /d D:\AiProject\vibe-coding
rg "MobileShell" mobile/lib mobile/test
```

Expected: only `mobile/lib/src/shell/mobile_shell.dart` and `mobile/lib/src/shell/shell.dart` mention `MobileShell`.

- [ ] **Step 2: Delete `mobile_shell.dart`**

Delete:

```text
mobile/lib/src/shell/mobile_shell.dart
```

- [ ] **Step 3: Update shell barrel**

Remove this line from `mobile/lib/src/shell/shell.dart`:

```dart
export 'mobile_shell.dart';
```

The final file should be:

```dart
export 'app_route.dart';
export 'app_snapshot.dart';
```

- [ ] **Step 4: Keep package exports pointed at UI**

Ensure `mobile/lib/lan_ai_cli_control.dart` exports UI:

```dart
export 'src/ui/ui.dart';
```

- [ ] **Step 5: Verify no shell page ownership remains**

Run:

```bat
cd /d D:\AiProject\vibe-coding
rg "class _HomePage|class _RunsPage|class _QueuePage|class MobileShell|mobile_shell" mobile/lib mobile/test
```

Expected: no matches.

- [ ] **Step 6: Run full verification**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 7: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add mobile/lib mobile/test
git commit -m "Remove mobile shell UI shim"
```

---

### Task 7: Final UI Layering Acceptance

**Files:**
- Read: `docs/superpowers/specs/2026-05-05-mobile-ui-layering-design.md`
- Read: `mobile/lib/src/ui/`
- Read: `mobile/lib/src/shell/`

- [ ] **Step 1: Verify target file layout**

Run:

```bat
cd /d D:\AiProject\vibe-coding
dir /b mobile\lib\src\ui
dir /b mobile\lib\src\ui\pages
```

Expected `mobile\lib\src\ui` includes:

```text
main_tabs_page.dart
mobile_connection_error_page.dart
mobile_loading_page.dart
mobile_ui.dart
mobile_ui_frame.dart
pages
ui.dart
```

Expected `mobile\lib\src\ui\pages` includes:

```text
coding
home_page.dart
pages.dart
queue_page.dart
run_status_color.dart
runs_page.dart
```

- [ ] **Step 2: Verify forbidden ownership is gone**

Run:

```bat
cd /d D:\AiProject\vibe-coding
rg "class _HomePage|class _RunsPage|class _QueuePage|BottomNav|IndexedStack" mobile\lib\src\shell
```

Expected: no matches.

- [ ] **Step 3: Verify dependency direction**

Run:

```bat
cd /d D:\AiProject\vibe-coding
rg "\.\./\.\./ui|\.\./ui|src/ui" mobile\lib\src\features mobile\lib\src\widgets mobile\lib\src\theme mobile\lib\src\services mobile\lib\src\state
```

Expected: no matches. Features and shared layers must not import `ui`.

- [ ] **Step 4: Run full mobile verification**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 5: Commit acceptance note if needed**

If Tasks 1-6 already have commits and no code changes remain, do not create an empty commit. If documentation changed during execution, commit it with:

```bat
cd /d D:\AiProject\vibe-coding
git add docs mobile
git commit -m "Document mobile UI layering completion"
```
