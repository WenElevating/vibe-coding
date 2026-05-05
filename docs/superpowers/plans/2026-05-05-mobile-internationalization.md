# Mobile Internationalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Settings language preference so the Flutter mobile app can render app-owned UI copy in system default, Simplified Chinese, or English.

**Architecture:** Use Flutter official `gen_l10n` with English as the template ARB and Simplified Chinese as the second locale. Add a small app-owned language controller near `MaterialApp`, persist the selected mode with `shared_preferences`, and expose the controller to Settings via an inherited notifier. Migrate visible app-owned UI copy in batches while keeping user, AI, command, file, path, and adapter-originated text untouched.

**Tech Stack:** Flutter, Dart, `flutter_localizations`, Flutter `gen_l10n`, ARB files, `shared_preferences`, widget tests.

---

## File Structure

- Create: `mobile/l10n.yaml`, configures `gen_l10n` with `app_en.arb` as the template and non-null getters.
- Create: `mobile/lib/l10n/app_en.arb`, English app-owned UI strings.
- Create: `mobile/lib/l10n/app_zh.arb`, Simplified Chinese app-owned UI strings.
- Create: `mobile/lib/src/app/language_mode.dart`, enum, storage values, labels, and locale resolver.
- Create: `mobile/lib/src/app/language_controller.dart`, `ChangeNotifier` that loads, persists, and exposes the selected language mode.
- Create: `mobile/lib/src/app/language_scope.dart`, inherited notifier for reading and updating the app language from lower widgets.
- Modify: `mobile/pubspec.yaml`, add `shared_preferences` and enable generated localizations.
- Modify: `mobile/lib/src/app/app.dart`, wire controller, generated delegates, supported locales, and locale resolution.
- Modify: `mobile/lib/src/app/app_localization.dart` and `mobile/lib/src/theme/app_localization.dart`, remove duplicate hardcoded locale constants or re-export generated/localization helpers consistently.
- Modify: `mobile/lib/src/features/settings/settings_page.dart`, add compact language row and picker.
- Modify: UI files under `mobile/lib/src/features/**`, `mobile/lib/src/ui/**`, and `mobile/lib/src/widgets/**`, replace app-owned hardcoded strings with generated localization getters.
- Modify: `mobile/test/widget_test.dart` and related test helpers, add language tests and update hardcoded-copy assertions.

## ARB Key Rules

- Use lowerCamelCase keys.
- Prefix by feature or surface, for example `settingsLanguageTitle`, `homeRecentRunsTitle`, `workbenchComposerPlaceholder`.
- Use parameter names in the key when it improves clarity, for example `settingsDiagnosticsCount` with `{count}`.
- Do not add generic keys such as `title`, `ok`, `empty`, or `error`.
- Add the English template key first, then add the Simplified Chinese translation in the same task.

---

### Task 1: Add Localization Generation Skeleton

**Files:**
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/l10n.yaml`
- Create: `mobile/lib/l10n/app_en.arb`
- Create: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add the dependency and generation flag**

Modify `mobile/pubspec.yaml` so the dependencies and Flutter sections include:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_markdown: 0.7.4
  http: ^1.2.2
  shared_preferences: ^2.3.3

flutter:
  generate: true
  uses-material-design: true
```

- [ ] **Step 2: Add `l10n.yaml`**

Create `mobile/l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
synthetic-package: false
```

- [ ] **Step 3: Add initial English ARB**

Create `mobile/lib/l10n/app_en.arb`:

```json
{
  "@@locale": "en",
  "appTitle": "AI CLI Control",
  "navHome": "Home",
  "navRuns": "Runs",
  "navCoding": "Coding",
  "navDevices": "Devices",
  "navSettings": "Settings",
  "settingsTitle": "Settings",
  "settingsPreferencesSection": "Preferences",
  "settingsLanguageTitle": "Language",
  "settingsLanguageSystem": "System default",
  "settingsLanguageZhHans": "Simplified Chinese",
  "settingsLanguageEn": "English"
}
```

- [ ] **Step 4: Add initial Simplified Chinese ARB**

Create `mobile/lib/l10n/app_zh.arb`:

```json
{
  "@@locale": "zh",
  "appTitle": "AI CLI 控制台",
  "navHome": "首页",
  "navRuns": "运行",
  "navCoding": "编码",
  "navDevices": "设备",
  "navSettings": "设置",
  "settingsTitle": "设置",
  "settingsPreferencesSection": "偏好设置",
  "settingsLanguageTitle": "语言",
  "settingsLanguageSystem": "系统默认",
  "settingsLanguageZhHans": "简体中文",
  "settingsLanguageEn": "English"
}
```

- [ ] **Step 5: Resolve packages and generate localization output**

Run from `mobile`:

```bat
flutter pub get
flutter gen-l10n
```

Expected: `mobile/lib/l10n/app_localizations.dart` and locale-specific generated files appear, and `pubspec.lock` updates with `shared_preferences` packages.

- [ ] **Step 6: Run static analysis**

Run from `mobile`:

```bat
flutter analyze
```

Expected: It may fail only because the generated localization files are not imported yet. If it fails for YAML, ARB, or package resolution errors, fix this task before continuing.

- [ ] **Step 7: Commit Task 1**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/l10n.yaml mobile/lib/l10n
git commit -m "Add Flutter localization resources"
```

---

### Task 2: Add Language Mode Model and Persistence

**Files:**
- Create: `mobile/lib/src/app/language_mode.dart`
- Create: `mobile/lib/src/app/language_controller.dart`
- Create: `mobile/lib/src/app/language_scope.dart`
- Test: `mobile/test/language_controller_test.dart`

- [ ] **Step 1: Write failing tests for mode parsing, locale resolution, and persistence**

Create `mobile/test/language_controller_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/language_controller.dart';
import 'package:lan_ai_cli_control/src/app/language_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LanguageMode parses persisted values and falls back to system', () {
    expect(LanguageModePreference.fromStorageValue('system'),
        LanguageModePreference.system);
    expect(LanguageModePreference.fromStorageValue('zh-Hans-CN'),
        LanguageModePreference.zhHansCn);
    expect(LanguageModePreference.fromStorageValue('en-US'),
        LanguageModePreference.enUs);
    expect(LanguageModePreference.fromStorageValue('ja-JP'),
        LanguageModePreference.system);
  });

  test('resolveSupportedLocale handles exact, Chinese, and fallback locales', () {
    expect(
        resolveSupportedLocale(
            const Locale('en', 'US'), AppLanguage.supportedLocales),
        const Locale('en', 'US'));
    expect(
        resolveSupportedLocale(
            const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
            AppLanguage.supportedLocales),
        AppLanguage.zhHansCnLocale);
    expect(
        resolveSupportedLocale(
            const Locale('ja', 'JP'), AppLanguage.supportedLocales),
        const Locale('en', 'US'));
  });

  test('LanguageController loads and persists selected mode', () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final controller = LanguageController();

    await controller.load();

    expect(controller.mode, LanguageModePreference.enUs);
    expect(controller.locale, const Locale('en', 'US'));

    await controller.setMode(LanguageModePreference.zhHansCn);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppLanguage.storageKey), 'zh-Hans-CN');
    expect(controller.locale, AppLanguage.zhHansCnLocale);
  });
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run from `mobile`:

```bat
flutter test test\language_controller_test.dart
```

Expected: FAIL because `language_controller.dart` and `language_mode.dart` do not exist.

- [ ] **Step 3: Implement `language_mode.dart`**

Create `mobile/lib/src/app/language_mode.dart`:

```dart
import 'package:flutter/material.dart';

enum LanguageModePreference {
  system('system'),
  zhHansCn('zh-Hans-CN'),
  enUs('en-US');

  const LanguageModePreference(this.storageValue);

  final String storageValue;

  static LanguageModePreference fromStorageValue(String? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return system;
  }
}

abstract final class AppLanguage {
  static const storageKey = 'app.languageMode';
  static const zhHansCnLocale = Locale.fromSubtags(
      languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');
  static const supportedLocales = <Locale>[
    zhHansCnLocale,
    Locale('en', 'US'),
  ];
}

Locale resolveSupportedLocale(Locale? locale, Iterable<Locale> supportedLocales) {
  if (locale == null) return const Locale('en', 'US');
  for (final supported in supportedLocales) {
    if (supported.languageCode == locale.languageCode &&
        supported.scriptCode == locale.scriptCode &&
        supported.countryCode == locale.countryCode) {
      return supported;
    }
  }
  if (locale.languageCode == 'zh') return AppLanguage.zhHansCnLocale;
  return const Locale('en', 'US');
}
```

- [ ] **Step 4: Implement `language_controller.dart`**

Create `mobile/lib/src/app/language_controller.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_mode.dart';

class LanguageController extends ChangeNotifier {
  LanguageModePreference _mode = LanguageModePreference.system;
  bool _loaded = false;

  LanguageModePreference get mode => _mode;
  bool get loaded => _loaded;

  Locale? get locale => switch (_mode) {
        LanguageModePreference.system => null,
        LanguageModePreference.zhHansCn => AppLanguage.zhHansCnLocale,
        LanguageModePreference.enUs => const Locale('en', 'US'),
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = LanguageModePreference.fromStorageValue(
        prefs.getString(AppLanguage.storageKey));
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(LanguageModePreference mode) async {
    if (_mode == mode && _loaded) return;
    _mode = mode;
    _loaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppLanguage.storageKey, mode.storageValue);
  }
}
```

- [ ] **Step 5: Implement `language_scope.dart`**

Create `mobile/lib/src/app/language_scope.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'language_controller.dart';

class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({
    super.key,
    required LanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static LanguageController watch(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    assert(scope != null, 'LanguageScope not found in widget tree');
    return scope!.notifier!;
  }

  static LanguageController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<LanguageScope>()
        ?.widget as LanguageScope?;
    assert(element != null, 'LanguageScope not found in widget tree');
    return element!.notifier!;
  }
}
```

- [ ] **Step 6: Run the new test to verify it passes**

Run from `mobile`:

```bat
flutter test test\language_controller_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

```bash
git add mobile/lib/src/app/language_mode.dart mobile/lib/src/app/language_controller.dart mobile/lib/src/app/language_scope.dart mobile/test/language_controller_test.dart
git commit -m "Add language preference controller"
```

---

### Task 3: Wire Language Controller Into the Root App

**Files:**
- Modify: `mobile/lib/src/app/app.dart`
- Modify: `mobile/lib/src/app/app_localization.dart`
- Modify: `mobile/lib/src/theme/app_localization.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add root app localization widget tests**

Add these imports to `mobile/test/widget_test.dart` if missing:

```dart
import 'package:flutter/material.dart';
import 'package:lan_ai_cli_control/src/app/language_mode.dart';
```

Add tests that pump the app with mocked preferences:

```dart
testWidgets('app renders English when forced to English',
    (WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'en-US'});

  await tester.pumpWidget(const LanAiCliControlApp());
  await tester.pumpAndSettle();

  expect(find.text('Settings'), findsWidgets);
});

testWidgets('app renders Chinese when forced to Simplified Chinese',
    (WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

  await tester.pumpWidget(const LanAiCliControlApp());
  await tester.pumpAndSettle();

  expect(find.text('设置'), findsWidgets);
});
```

If `LanAiCliControlApp` starts daemon network loading in tests and makes these tests brittle, create a smaller test-only root widget in the test file that uses the same `LanguageController`, `LanguageScope`, `MaterialApp`, delegates, and a `Text(AppLocalizations.of(context).navSettings)` child.

- [ ] **Step 2: Run the root app tests to verify they fail**

Run from `mobile`:

```bat
flutter test test\widget_test.dart --plain-name "app renders English when forced to English"
```

Expected: FAIL because `LanAiCliControlApp` still hardcodes `locale: zhHansCnLocale`.

- [ ] **Step 3: Update `app_localization.dart` to centralize delegates**

Modify `mobile/lib/src/app/app_localization.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../l10n/app_localizations.dart';
import 'language_mode.dart';

const appSupportedLocales = AppLanguage.supportedLocales;

const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
```

Modify `mobile/lib/src/theme/app_localization.dart` to re-export the app-level definitions instead of duplicating delegates:

```dart
export '../app/app_localization.dart';
export '../app/language_mode.dart' show AppLanguage;
```

- [ ] **Step 4: Update `app.dart` to own the controller**

Modify `mobile/lib/src/app/app.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/theme.dart';
import '../ui/ui.dart';
import 'app_localization.dart';
import 'language_controller.dart';
import 'language_mode.dart';
import 'language_scope.dart';

class LanAiCliControlApp extends StatefulWidget {
  const LanAiCliControlApp({super.key});

  @override
  State<LanAiCliControlApp> createState() => _LanAiCliControlAppState();
}

class _LanAiCliControlAppState extends State<LanAiCliControlApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: AppLocalizations.lookupAppLocalizations(
                    _languageController.locale ?? const Locale('en', 'US'))
                .appTitle,
            locale: _languageController.locale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            localeResolutionCallback: (locale, supportedLocales) =>
                resolveSupportedLocale(locale, supportedLocales),
            theme: buildAppTheme(),
            home: const MobileUi(),
          )));
}
```

If generated `AppLocalizations` does not expose `lookupAppLocalizations`, set `title: 'AI CLI Control'` in this task and localize title later with a builder after checking generated APIs.

- [ ] **Step 5: Run root tests**

Run from `mobile`:

```bat
flutter test test\language_controller_test.dart test\widget_test.dart --plain-name "app renders"
```

Expected: PASS for the added root localization tests.

- [ ] **Step 6: Commit Task 3**

```bash
git add mobile/lib/src/app mobile/lib/src/theme/app_localization.dart mobile/test/widget_test.dart
git commit -m "Wire app locale preference into MaterialApp"
```

---

### Task 4: Add Settings Language Row and Picker

**Files:**
- Modify: `mobile/lib/src/features/settings/settings_page.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add failing settings picker tests**

Add a widget test that opens Settings, taps the language row, and verifies self-identifying options:

```dart
testWidgets('settings language picker shows self-identifying language names',
    (WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'en-US'});

  await tester.pumpWidget(const LanAiCliControlApp());
  await tester.pumpAndSettle();

  await tester.tap(find.text('Settings').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Language'));
  await tester.pumpAndSettle();

  expect(find.text('System default'), findsOneWidget);
  expect(find.text('简体中文'), findsOneWidget);
  expect(find.text('English'), findsWidgets);
});
```

If app navigation makes this brittle, use the existing settings preview helper and wrap it in `LanguageScope` plus generated localization delegates.

- [ ] **Step 2: Run the picker test to verify it fails**

Run from `mobile`:

```bat
flutter test test\widget_test.dart --plain-name "settings language picker"
```

Expected: FAIL because there is no language row yet.

- [ ] **Step 3: Add missing ARB keys**

Add to `mobile/lib/l10n/app_en.arb`:

```json
"settingsLanguagePickerTitle": "Choose language",
"settingsCodingControlSection": "Coding control",
"settingsStreamOutputTitle": "Stream output",
"settingsStreamOutputSubtitle": "When off, only the final answer is shown to avoid duplicate deltas and complete messages.",
"settingsExpandThinkingTitle": "Show thinking process",
"settingsExpandThinkingSubtitle": "When on, model thinking is expanded by default; when off, it stays collapsed.",
"settingsPermissionModeTitle": "Permission mode",
"settingsPermissionDefault": "Default",
"settingsPermissionAuto": "Auto",
"settingsPermissionSubtitle": "Default asks for CLI permission confirmation; auto lets the CLI handle permissions."
```

Add to `mobile/lib/l10n/app_zh.arb`:

```json
"settingsLanguagePickerTitle": "选择语言",
"settingsCodingControlSection": "编码控制",
"settingsStreamOutputTitle": "流式输出",
"settingsStreamOutputSubtitle": "关闭时只显示最终回复，避免 delta 与完整消息重复。",
"settingsExpandThinkingTitle": "显示思考过程",
"settingsExpandThinkingSubtitle": "开启后默认展开模型 thinking；关闭时折叠显示。",
"settingsPermissionModeTitle": "权限模式",
"settingsPermissionDefault": "默认",
"settingsPermissionAuto": "自动",
"settingsPermissionSubtitle": "默认会请求 CLI 权限确认；自动模式由 CLI 处理。"
```

Run `flutter gen-l10n` after editing ARB.

- [ ] **Step 4: Add language row and picker implementation**

In `mobile/lib/src/features/settings/settings_page.dart`, import:

```dart
import '../../../l10n/app_localizations.dart';
import '../../app/language_mode.dart';
import '../../app/language_scope.dart';
```

Inside `build`, define:

```dart
final l10n = AppLocalizations.of(context);
final language = LanguageScope.watch(context);
```

Add a preferences `_SettingsCard` before coding controls:

```dart
Subhead(l10n.settingsPreferencesSection),
_SettingsCard(children: [
  _SettingsTapRow(
    title: l10n.settingsLanguageTitle,
    value: _languageModeLabel(l10n, language.mode),
    onTap: () => _showLanguagePicker(context),
  ),
]),
const SizedBox(height: 20),
```

Add helper functions below `SettingsPage`:

```dart
String _languageModeLabel(
    AppLocalizations l10n, LanguageModePreference mode) =>
    switch (mode) {
      LanguageModePreference.system => l10n.settingsLanguageSystem,
      LanguageModePreference.zhHansCn => '简体中文',
      LanguageModePreference.enUs => 'English',
    };

void _showLanguagePicker(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final controller = LanguageScope.read(context);
  showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _LanguagePickerSheet(
          title: l10n.settingsLanguagePickerTitle,
          selected: controller.mode,
          onSelected: (mode) async {
            Navigator.of(context).pop();
            await controller.setMode(mode);
          }));
}
```

Add row and sheet widgets:

```dart
class _SettingsTapRow extends StatelessWidget {
  const _SettingsTapRow(
      {required this.title, required this.value, required this.onTap});
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800))),
            Text(value,
                style: const TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: theme.faint, size: 18),
          ])));
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet(
      {required this.title, required this.selected, required this.onSelected});
  final String title;
  final LanguageModePreference selected;
  final ValueChanged<LanguageModePreference> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(LanguageModePreference, String)>[
      (LanguageModePreference.system, l10n.settingsLanguageSystem),
      (LanguageModePreference.zhHansCn, '简体中文'),
      (LanguageModePreference.enUs, 'English'),
    ];
    return SafeArea(
        child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
                color: const Color(0xFF101113),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .08))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: theme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w900))),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: theme.muted, size: 18)),
              ]),
              for (final option in options)
                ListTile(
                    dense: true,
                    title: Text(option.$2),
                    trailing: selected == option.$1
                        ? const Icon(Icons.check_rounded,
                            color: theme.green, size: 18)
                        : null,
                    onTap: () => onSelected(option.$1)),
            ])));
  }
}
```

Replace existing settings hardcoded labels in this file with `l10n` getters from this task's ARB keys.

- [ ] **Step 5: Run picker test**

Run from `mobile`:

```bat
flutter test test\widget_test.dart --plain-name "settings language picker"
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

```bash
git add mobile/lib/src/features/settings/settings_page.dart mobile/lib/l10n mobile/test/widget_test.dart
git commit -m "Add language picker to settings"
```

---

### Task 5: Localize Navigation and Primary Shell Copy

**Files:**
- Modify: `mobile/lib/src/ui/main_tab_items.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/widgets/navigation.dart`
- Modify: `mobile/lib/src/widgets/section.dart` if section labels are hardcoded there
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Convert `mainTabItems` from const data to localized factory**

Modify `mobile/lib/src/ui/main_tab_items.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/widgets.dart';

List<NavSpec> mainTabItems(AppLocalizations l10n) => [
      NavSpec(Icons.home_rounded, l10n.navHome),
      NavSpec(Icons.manage_search_rounded, l10n.navRuns),
      NavSpec(Icons.terminal_rounded, l10n.navCoding),
      NavSpec(Icons.format_list_bulleted_rounded, l10n.navDevices),
      NavSpec(Icons.settings_rounded, l10n.navSettings),
    ];
```

Modify `mobile/lib/src/ui/main_tabs_page.dart` inside `build`:

```dart
final l10n = AppLocalizations.of(context);
```

and change bottom nav to:

```dart
? BottomNav(selected: _tab, items: mainTabItems(l10n), onTap: _selectTab)
```

- [ ] **Step 2: Add tests for localized navigation**

Add a widget test that verifies English nav labels after forcing `en-US`:

```dart
testWidgets('bottom navigation labels localize to English',
    (WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'en-US'});

  await tester.pumpWidget(const LanAiCliControlApp());
  await tester.pumpAndSettle();

  expect(find.text('Home'), findsWidgets);
  expect(find.text('Runs'), findsWidgets);
  expect(find.text('Coding'), findsWidgets);
  expect(find.text('Devices'), findsWidgets);
  expect(find.text('Settings'), findsWidgets);
});
```

- [ ] **Step 3: Run targeted navigation tests**

Run from `mobile`:

```bat
flutter test test\widget_test.dart --plain-name "bottom navigation labels"
```

Expected: PASS.

- [ ] **Step 4: Commit Task 5**

```bash
git add mobile/lib/src/ui/main_tab_items.dart mobile/lib/src/ui/main_tabs_page.dart mobile/test/widget_test.dart
git commit -m "Localize main navigation labels"
```

---

### Task 6: Localize Core Pages in Batches

**Files:**
- Modify: `mobile/lib/src/ui/pages/home_page.dart`
- Modify: `mobile/lib/src/ui/pages/runs_page.dart`
- Modify: `mobile/lib/src/ui/pages/queue_page.dart`
- Modify: `mobile/lib/src/features/notifications/notifications_page.dart`
- Modify: `mobile/lib/src/features/adapters/adapters_page.dart`
- Modify: `mobile/lib/src/features/run_detail/run_detail_page.dart`
- Modify: `mobile/lib/src/features/workspace_picker/*.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Inventory hardcoded app-owned strings**

Run from repo root:

```bat
rg -n "'[\u4e00-\u9fff][^']*'|\"[\u4e00-\u9fff][^\"]*\"" mobile\lib\src\ui mobile\lib\src\features
```

Expected: A list of Chinese string literals. Classify each as app-owned UI copy or source content. Do not migrate source content.

- [ ] **Step 2: Add ARB keys for one page at a time**

For each page, add module-prefixed keys. For `home_page.dart`, use this shape:

```json
"homeRecentRunsTitle": "Recent runs",
"homeViewAllAction": "View all",
"homeCodingShortcutTitle": "Coding",
"homeDevicesShortcutTitle": "Devices",
"homeSettingsShortcutTitle": "Settings"
```

Chinese:

```json
"homeRecentRunsTitle": "最近运行",
"homeViewAllAction": "查看全部",
"homeCodingShortcutTitle": "编码",
"homeDevicesShortcutTitle": "设备",
"homeSettingsShortcutTitle": "设置"
```

Run `flutter gen-l10n` after each ARB batch.

- [ ] **Step 3: Replace page literals with localization getters**

In each page `build`, add:

```dart
final l10n = AppLocalizations.of(context);
```

Replace app-owned UI text with getters:

```dart
SectionTitle(l10n.homeRecentRunsTitle,
    action: l10n.homeViewAllAction,
    onAction: () => selectTab(1));
```

- [ ] **Step 4: Run tests after each page batch**

Run from `mobile`:

```bat
flutter test test\widget_test.dart
```

Expected: PASS. Update tests that assert app-owned literal copy to use the selected locale's expected text or stable keys.

- [ ] **Step 5: Commit each page batch**

Use one commit per coherent group:

```bash
git add mobile/lib/src/ui/pages mobile/lib/src/features mobile/lib/l10n mobile/test/widget_test.dart
git commit -m "Localize primary mobile pages"
```

---

### Task 7: Localize Workbench Shell and Event UI

**Files:**
- Modify: `mobile/lib/src/features/workbench/workbench_event_cards.dart`
- Modify: `mobile/lib/src/features/workbench/workbench_messages.dart`
- Modify: `mobile/lib/src/features/workbench/coding_page.dart`
- Modify: `mobile/lib/src/features/workbench/approval_page.dart`
- Modify: `mobile/lib/src/state/conversation_reducer.dart` only if it currently creates app-owned UI labels
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/widget_test.dart`
- Test: `mobile/test/conversation_reducer_test.dart`

- [ ] **Step 1: Preserve source-content boundaries**

Before editing, identify strings that must not be translated:

```bat
rg -n "message\.body|event\.text|toolEventBody|output|filePath|workspace\.path" mobile\lib\src\features\workbench mobile\lib\src\state
```

Expected: Source content remains in model/reducer functions. Only labels such as thinking title, permission title, button labels, placeholders, status explanations, and sheet titles move to localization.

- [ ] **Step 2: Add workbench ARB keys**

Add English keys shaped like:

```json
"workbenchComposerPlaceholder": "Add feedback...",
"workbenchThinkingTitle": "Thinking",
"workbenchToolInputLabel": "input",
"workbenchToolOutputLabel": "output",
"workbenchCommandDetailTitle": "Command details",
"workbenchOutputDetailTitle": "Output details",
"workbenchApprovalTitle": "Permission confirmation",
"workbenchApprovalAllowAction": "Allow",
"workbenchApprovalDenyAction": "Deny"
```

Add Chinese translations:

```json
"workbenchComposerPlaceholder": "Add feedback...",
"workbenchThinkingTitle": "思考过程",
"workbenchToolInputLabel": "input",
"workbenchToolOutputLabel": "output",
"workbenchCommandDetailTitle": "命令详情",
"workbenchOutputDetailTitle": "输出详情",
"workbenchApprovalTitle": "权限确认",
"workbenchApprovalAllowAction": "允许",
"workbenchApprovalDenyAction": "拒绝"
```

Keep `input` and `output` as English in Chinese UI if that matches the current compact tool-log style. This is app-owned copy but intentionally technical.

- [ ] **Step 3: Move UI labels out of model/reducer code where needed**

If `workbench_messages.dart` creates visible titles such as `思考过程` or `权限确认`, prefer returning semantic roles with source text, then map role titles in widgets:

```dart
String workbenchMessageTitle(AppLocalizations l10n, WorkbenchMessage message) =>
    switch (message.role) {
      'thinking' => l10n.workbenchThinkingTitle,
      'approval' => l10n.workbenchApprovalTitle,
      _ => message.title,
    };
```

Do not localize `message.body` when it comes from user, assistant, command output, or file content.

- [ ] **Step 4: Update workbench widgets**

In `workbench_event_cards.dart`, add `final l10n = AppLocalizations.of(context);` in build methods and replace labels:

```dart
_ToolDetailBlock(
  label: l10n.workbenchToolInputLabel,
  text: message.body,
  onTap: () => _showCommandDetailSheet(
    context: context,
    title: l10n.workbenchCommandDetailTitle,
    subtitle: _commandDetailSubtitle(message),
    text: message.body,
  ),
)
```

- [ ] **Step 5: Update workbench tests**

For tests that verify user or command content, keep literal assertions. For tests that verify UI labels, assert localized labels for the active test locale or use stable widget keys.

Example update:

```dart
expect(find.text('Command details'), findsOneWidget);
```

only in an English-locale test. Otherwise prefer:

```dart
expect(find.byTooltip('复制全文'), findsOneWidget);
```

after localizing tooltip expectations for the test's locale.

- [ ] **Step 6: Run workbench tests**

Run from `mobile`:

```bat
flutter test test\conversation_reducer_test.dart test\widget_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 7**

```bash
git add mobile/lib/src/features/workbench mobile/lib/src/state mobile/lib/l10n mobile/test
git commit -m "Localize workbench UI labels"
```

---

### Task 8: System Locale Tests and Final Sweep

**Files:**
- Modify: `mobile/test/widget_test.dart`
- Modify: any remaining files found by the hardcoded string sweep
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add platform locale tests for system mode**

Add tests using `tester.binding.platformDispatcher.localeTestValue`:

```dart
testWidgets('system mode follows supported platform Chinese locale',
    (WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'system'});
  tester.binding.platformDispatcher.localeTestValue =
      const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN');
  addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

  await tester.pumpWidget(const LanAiCliControlApp());
  await tester.pumpAndSettle();

  expect(find.text('设置'), findsWidgets);
});

testWidgets('system mode falls back to English for unsupported Japanese locale',
    (WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'system'});
  tester.binding.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
  addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

  await tester.pumpWidget(const LanAiCliControlApp());
  await tester.pumpAndSettle();

  expect(find.text('Settings'), findsWidgets);
});
```

- [ ] **Step 2: Run hardcoded UI string sweeps**

Run from repo root:

```bat
rg -n "'[\u4e00-\u9fff][^']*'|\"[\u4e00-\u9fff][^\"]*\"" mobile\lib\src
rg -n "Add feedback|Settings|Home|Runs|Devices|Permission|Thinking|Command details|Output details" mobile\lib\src
```

Expected: Remaining matches are source content, test-only helpers, locale resources, or intentionally untranslated technical labels. Migrate any remaining app-owned UI copy.

- [ ] **Step 3: Run full mobile verification**

Run from `mobile`:

```bat
flutter analyze
flutter test
```

Expected: Both pass.

- [ ] **Step 4: Run local check script if available**

Run from `mobile`:

```bat
check.bat
```

Expected: package resolution, formatting, analyze, and tests pass. If sandbox blocks this in an agent environment, ask the user to run it locally and paste failures.

- [ ] **Step 5: Commit final sweep**

```bash
git add mobile/lib mobile/test mobile/lib/l10n mobile/l10n.yaml mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "Complete mobile internationalization sweep"
```

---

## Self-Review

- Spec coverage: The plan covers official `gen_l10n`, English template ARB, Simplified Chinese ARB, `shared_preferences` persistence with `app.languageMode`, system/forced language modes, Settings entry point, self-identifying picker names, root `MaterialApp` rebuild strategy, explicit locale fallback, migration boundaries, and tests for forced and system locales.
- Scope check: This is one coherent mobile-app internationalization feature. It is split into infrastructure, settings UI, page migration, workbench migration, and final verification tasks so each commit remains reviewable.
- Placeholder scan: The plan contains no `TBD`, no `TODO`, and no unspecified implementation steps. The word `placeholder` appears only as part of a UI concept and not as missing work.
- Type consistency: `LanguageModePreference`, `AppLanguage.storageKey`, `LanguageController`, `LanguageScope`, and `resolveSupportedLocale` are introduced before later tasks use them.

