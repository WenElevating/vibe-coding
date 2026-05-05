// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AI CLI Control';

  @override
  String get navHome => 'Home';

  @override
  String get navRuns => 'Runs';

  @override
  String get navCoding => 'Coding';

  @override
  String get navDevices => 'Devices';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsPreferencesSection => 'Preferences';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageZhHans => 'Simplified Chinese';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguagePickerTitle => 'Choose language';

  @override
  String get settingsCodingControlSection => 'Coding control';

  @override
  String get settingsStreamOutputTitle => 'Stream output';

  @override
  String get settingsStreamOutputSubtitle => 'When off, only the final answer is shown to avoid duplicate deltas and complete messages.';

  @override
  String get settingsExpandThinkingTitle => 'Show thinking process';

  @override
  String get settingsExpandThinkingSubtitle => 'When on, model thinking is expanded by default; when off, it stays collapsed.';

  @override
  String get settingsPermissionModeTitle => 'Permission mode';

  @override
  String get settingsPermissionDefault => 'Default';

  @override
  String get settingsPermissionAuto => 'Auto';

  @override
  String get settingsPermissionSubtitle => 'Default asks for CLI permission confirmation; auto lets the CLI handle permissions.';
}
