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

  @override
  String get homeOverviewTitle => '??';

  @override
  String get homeRunningMetricLabel => '???';

  @override
  String get homeRunningMetricNote => '????';

  @override
  String get homeQueuedMetricLabel => '???';

  @override
  String get homeQueuedMetricNote => '????';

  @override
  String get homeCompletedMetricLabel => '??? (24h)';

  @override
  String homeFilesLinesNote(int files, int lines) => '$files ?? ? $lines ?';

  @override
  String get homeRecentRunsTitle => '????';

  @override
  String get homeViewAllAction => '????';

  @override
  String get homeNoRuns => '??????';

  @override
  String get homeQuickActionsTitle => '????';

  @override
  String get homeNewTaskTitle => '????';

  @override
  String get homeNewTaskSubtitle => '?????';

  @override
  String get homeCommandTemplatesTitle => '????';

  @override
  String get homeCommandTemplatesSubtitle => '??????';

  @override
  String get homeViewQueueTitle => '????';

  @override
  String get homeViewQueueSubtitle => '??????';

  @override
  String get runsTitle => '????';

  @override
  String runsAllPill(int count) => '?? $count';

  @override
  String runsRunningPill(int count) => '??? $count';

  @override
  String runsCompletedPill(int count) => '??? $count';

  @override
  String runsFailedPill(int count) => '?? $count';

  @override
  String get runsEmpty => '???????????????? AI CLI ???';

  @override
  String get queueTitle => '????';

  @override
  String queueCountAction(int count) => '$count ?';

  @override
  String queueRunningPill(int count) => '??? $count';

  @override
  String queueWaitingPill(int count) => '??? $count';

  @override
  String queueTotalPill(int count) => '?? $count';

  @override
  String get queueRunningSection => '???';

  @override
  String get queueWaitingSection => '???';

  @override
  String get queueNoRunning => '???????';

  @override
  String get queueNoWaiting => '??????';

  @override
  String get queueFootnote => '?????? daemon????????????';
}
