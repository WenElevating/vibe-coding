# Mobile Internationalization Design

## Goal

Add an application language setting so the mobile Flutter app can render its own UI in either Simplified Chinese or English, while also supporting a system-default mode.

The first implementation pass should migrate visible app-owned UI strings across the mobile app, not only the settings page. Content produced by users, AI models, CLI tools, daemon payloads, command output, file previews, file paths, workspace names, and tool names remains source content and should not be translated.

## Current State

The mobile app already depends on `flutter_localizations` and configures Flutter system localization delegates. `MaterialApp.locale` is currently fixed to Simplified Chinese, and `supportedLocales` already includes Simplified Chinese and English.

There is no app business-string localization layer yet: no `l10n.yaml`, no ARB files, and no generated `AppLocalizations` API. UI copy is hardcoded across Dart files, including navigation, settings, workbench status text, approval prompts, empty states, and tests.

## Chosen Approach

Use Flutter's official `gen_l10n` workflow with ARB files.

This keeps the internationalization layer aligned with Flutter's built-in tooling, avoids additional runtime dependencies, and gives a stable path for a long-lived product UI. Third-party options such as `easy_localization` and `slang` were considered, but the official approach is preferred because the project already uses Flutter localization delegates and the feature is foundational infrastructure.

## Language Modes

The language setting supports three modes:

- `system`: follow the device/system locale.
- `zh-Hans-CN`: force Simplified Chinese.
- `en-US`: force English.

When the user chooses `system`, `MaterialApp.locale` should be `null` so Flutter resolves the locale from the platform. When the user chooses a forced language, `MaterialApp.locale` should be set to the corresponding `Locale`.

## User Experience

The entry point lives in Settings.

Settings should include a compact language row in the preferences section. The row shows a localized title and the current mode label, for example:

- Chinese UI: `语言` with `系统默认`, `简体中文`, or `English`.
- English UI: `Language` with `System default`, `Simplified Chinese`, or `English`.

Tapping the row opens a lightweight language picker using existing mobile UI patterns. The picker should list the three modes and clearly mark the selected one. The setting should apply immediately and persist across app restarts.

## Architecture

Add an app-level localization resource layer:

- `mobile/l10n.yaml` configures Flutter localization generation.
- `mobile/lib/l10n/app_zh.arb` stores Simplified Chinese strings.
- `mobile/lib/l10n/app_en.arb` stores English strings.
- Generated `AppLocalizations` is imported where UI strings are rendered.

Add an app-level language preference state:

- A small enum represents `system`, `zhHansCn`, and `enUs`.
- A persistence adapter stores the selected mode locally.
- The root app observes the selected mode and passes the resolved locale to `MaterialApp`.

Keep boundaries narrow:

- Localization lookup belongs at UI rendering boundaries, not in protocol models.
- Protocol/event reducers should continue to preserve raw source content.
- Helper functions that classify tool events may return stable semantic keys, while widgets map those keys to localized display strings when needed.

## Migration Scope

Migrate app-owned copy across the mobile app, including:

- Bottom navigation labels.
- Settings page labels, values, actions, connection states, and diagnostics copy.
- Home, runs, queue, notifications, adapters, workspaces, and run-detail UI labels.
- Workbench shell labels, composer placeholders, status messages, approval prompts, pending states, thinking labels, tool detail labels, and empty/error states.
- Widget test expectations that currently assert literal Chinese UI copy.

Do not translate:

- User messages.
- Assistant responses.
- Command output.
- File content and diffs.
- Workspace paths and file names.
- Raw daemon or adapter payload text.
- Tool names when they originate from the adapter or model.

## Data Flow

Startup flow:

1. Load the saved language mode from local storage.
2. Build `MaterialApp` with `locale: null` for system mode or a concrete locale for forced modes.
3. Provide Flutter localization delegates plus generated app localization delegates.
4. Render UI strings from generated localization getters.

Change flow:

1. User opens Settings and chooses a language mode.
2. Persist the selected mode.
3. Update app-level state.
4. Rebuild `MaterialApp` so the visible UI changes immediately.

## Error Handling

If loading the saved preference fails, fall back to `system` and keep the app usable. If an unsupported saved value is found, ignore it and overwrite it the next time the user changes the setting.

Missing localization keys should be caught during development through generated code and tests. Runtime fallback should rely on Flutter's locale resolution, not custom string maps.

## Testing Strategy

Add or update tests to cover:

- Root app renders Chinese when forced to Simplified Chinese.
- Root app renders English when forced to English.
- Settings language row shows the current language mode.
- Selecting another language mode persists and rebuilds the UI.
- Existing workbench/widget tests use localization-aware expectations or stable keys where literal copy is not the behavior under test.

Run verification with:

- `flutter analyze`
- `flutter test`
- Optional local `check.bat` after implementation because it formats and runs the mobile checks.

## Implementation Notes

The first implementation should prioritize correctness and consistency over translating every obscure debug-only helper. However, any visible app-owned UI copy found during migration should be moved into ARB files.

Avoid adding a translation management platform or remote translation workflow in this pass. The feature should remain local, reviewable, and easy to maintain in Git.

