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

  @override
  String get settingsDataStatusSection => 'Data status';

  @override
  String get settingsDiagnosticsTitle => 'Code diagnostics';

  @override
  String settingsDiagnosticsCount(int count) => '$count items';

  @override
  String get settingsGitStatusTitle => 'Git status';

  @override
  String get settingsGitClean => 'Clean';

  @override
  String settingsGitFiles(int count) => '$count files';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsExtensionsTitle => 'Extensions';

  @override
  String settingsExtensionsCount(int count) => '$count items';

  @override
  String get settingsAdaptersAction => 'Adapters';

  @override
  String get settingsNotificationsAction => 'Notifications';

  @override
  String get settingsGenerateDiagnosticsAction => 'Generate diagnostics';

  @override
  String get settingsCurrentConnectionTitle => 'Current connection';

  @override
  String get settingsConnected => 'Connected';

  @override
  String get settingsWorkspaceLabel => 'Workspace';

  @override
  String get settingsSecurityModeLabel => 'Security mode';

  @override
  String get homeOverviewTitle => 'Overview';

  @override
  String get homeRunningMetricLabel => 'Running';

  @override
  String get homeRunningMetricNote => 'Active tasks';

  @override
  String get homeQueuedMetricLabel => 'Pending approval';

  @override
  String get homeQueuedMetricNote => 'Queued tasks';

  @override
  String get homeCompletedMetricLabel => 'Completed (24h)';

  @override
  String homeFilesLinesNote(int files, int lines) => '$files files ? $lines lines';

  @override
  String get homeRecentRunsTitle => 'Recent runs';

  @override
  String get homeViewAllAction => 'View all';

  @override
  String get homeNoRuns => 'No runs yet';

  @override
  String get homeQuickActionsTitle => 'Quick actions';

  @override
  String get homeNewTaskTitle => 'New task';

  @override
  String get homeNewTaskSubtitle => 'Create a new task';

  @override
  String get homeCommandTemplatesTitle => 'Command templates';

  @override
  String get homeCommandTemplatesSubtitle => 'Run preset commands';

  @override
  String get homeViewQueueTitle => 'View queue';

  @override
  String get homeViewQueueSubtitle => 'Review queued tasks';

  @override
  String get runsTitle => 'Runs';

  @override
  String runsAllPill(int count) => 'All $count';

  @override
  String runsRunningPill(int count) => 'Running $count';

  @override
  String runsCompletedPill(int count) => 'Completed $count';

  @override
  String runsFailedPill(int count) => 'Failed $count';

  @override
  String get runsEmpty => 'No runs yet. Start a real AI CLI task from command templates.';

  @override
  String get queueTitle => 'Run queue';

  @override
  String queueCountAction(int count) => '$count items';

  @override
  String queueRunningPill(int count) => 'Running $count';

  @override
  String queueWaitingPill(int count) => 'Queued $count';

  @override
  String queueTotalPill(int count) => 'Total $count';

  @override
  String get queueRunningSection => 'Running';

  @override
  String get queueWaitingSection => 'Queued';

  @override
  String get queueNoRunning => 'No running queue items';

  @override
  String get queueNoWaiting => 'No waiting tasks';

  @override
  String get queueFootnote => 'Queue data comes from the daemon. Tasks run in workspace order.';
}
