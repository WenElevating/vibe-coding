// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AI CLI 控制台';

  @override
  String get navHome => '首页';

  @override
  String get navRuns => '运行';

  @override
  String get navCoding => '编码';

  @override
  String get navDevices => '设备';

  @override
  String get navSettings => '设置';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsPreferencesSection => '偏好设置';

  @override
  String get settingsLanguageTitle => '语言';

  @override
  String get settingsLanguageSystem => '系统默认';

  @override
  String get settingsLanguageZhHans => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguagePickerTitle => '????';

  @override
  String get settingsCodingControlSection => '????';

  @override
  String get settingsStreamOutputTitle => '????';

  @override
  String get settingsStreamOutputSubtitle => '????????????? delta ????????';

  @override
  String get settingsExpandThinkingTitle => '??????';

  @override
  String get settingsExpandThinkingSubtitle => '????????? thinking?????????';

  @override
  String get settingsPermissionModeTitle => '????';

  @override
  String get settingsPermissionDefault => '??';

  @override
  String get settingsPermissionAuto => '??';

  @override
  String get settingsPermissionSubtitle => '????? CLI ?????????? CLI ???';

  @override
  String get settingsDataStatusSection => '????';

  @override
  String get settingsDiagnosticsTitle => '????';

  @override
  String settingsDiagnosticsCount(int count) => '$count ?';

  @override
  String get settingsGitStatusTitle => 'Git ??';

  @override
  String get settingsGitClean => '??';

  @override
  String settingsGitFiles(int count) => '$count ??';

  @override
  String get settingsAboutSection => '??';

  @override
  String get settingsExtensionsTitle => '??';

  @override
  String settingsExtensionsCount(int count) => '$count ?';

  @override
  String get settingsAdaptersAction => '???';

  @override
  String get settingsNotificationsAction => '??';

  @override
  String get settingsGenerateDiagnosticsAction => '??????';

  @override
  String get settingsCurrentConnectionTitle => '????';

  @override
  String get settingsConnected => '???';

  @override
  String get settingsWorkspaceLabel => '???';

  @override
  String get settingsSecurityModeLabel => '????';
}
