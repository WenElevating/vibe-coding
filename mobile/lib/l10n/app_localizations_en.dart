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
  @override
  String get commonBack => 'Back';

  @override
  String get adaptersTitle => 'Adapter status';

  @override
  String adaptersCount(int count) => '$count items';

  @override
  String get adaptersEmpty => 'daemon returned no adapters';

  @override
  String get adaptersExtensionsSection => 'Extensions';

  @override
  String get adaptersNoExtensions => 'No extension information';

  @override
  String get adaptersNotInstalled => 'not installed';

  @override
  String get adaptersStatusOk => 'Status                         OK';

  @override
  String get adaptersCapabilitiesLabel => 'Capabilities';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsDescription => 'Export a redacted diagnostics bundle for troubleshooting';

  @override
  String get diagnosticsSystemInfo => 'System information';

  @override
  String get diagnosticsAdapterStatus => 'Adapter status';

  @override
  String get diagnosticsRunLogsRecent => 'Run logs (last 7 days)';

  @override
  String get diagnosticsEventRecordsRecent => 'Event records (last 7 days)';

  @override
  String get diagnosticsConfigInfo => 'Configuration';

  @override
  String get diagnosticsEstimatedSize => 'Estimated size';

  @override
  String get diagnosticsGenerateAction => 'Generate diagnostics bundle';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsTabAll => 'All';

  @override
  String get notificationsTabUnread => 'Unread';

  @override
  String get notificationsTabMentions => '@me';

  @override
  String get notificationsApprovalRequired => 'Approval required';

  @override
  String get notificationsRequestModify => 'Claude Code requests changes\nlib/services/auth_service.dart';

  @override
  String get notificationsTaskComplete => 'Task complete';

  @override
  String get notificationsRunCompletedDuration => 'Add unit tests for user service\nRun completed, duration 28m 15s';

  @override
  String get notificationsTaskFailed => 'Task failed';

  @override
  String get notificationsDataSyncBody => 'Optimize data sync logic\nRun failed, view details';

  @override
  String get notificationsYesterday1422 => 'Yesterday 14:22';

  @override
  String get notificationsQueueUpdate => 'Queue update';

  @override
  String get notificationsCacheBody => 'Optimize cache strategy\nStarted running';

  @override
  String get notificationsYesterday1315 => 'Yesterday 13:15';

  @override
  String get notificationsSystemMessage => 'System message';

  @override
  String get notificationsConnectedBody => 'Connected to DESKTOP-DEV';

  @override
  String get notificationsYesterday1001 => 'Yesterday 10:01';

  @override
  String get runDetailTitle => 'Run details';

  @override
  String get runDetailMockTask => 'Fix login API test failure';

  @override
  String get runDetailRunningStatus => 'Running';

  @override
  String get runDetailStartedDuration => '10:32 started ? Duration 12m 45s';

  @override
  String get runDetailTabOverview => 'Overview';

  @override
  String get runDetailTabEvents => 'Events';

  @override
  String get runDetailTabFileChanges => 'File changes';

  @override
  String get runDetailTabConfig => 'Config';

  @override
  String get runDetailUserPromptTitle => 'User prompt';

  @override
  String get runDetailUserPromptBody => 'Fix the login API test failure and add boundary-condition tests.';

  @override
  String get runDetailThinkingTitle => 'Claude starts thinking';

  @override
  String get runDetailThinkingBody => 'Analyzing the problem and related code...';

  @override
  String get runDetailReadFileTitle => 'Read file';

  @override
  String get runDetailSearchCodeTitle => 'Search code';

  @override
  String get runDetailSearchBody => 'search: "login failure test"\nFound 12 results';

  @override
  String get runDetailEditFileTitle => 'Edit file';

  @override
  String get runDetailRunCommandTitle => 'Run command';

  @override
  String get runDetailCommandBody => 'dart test tests/login_test.dart      running ?';

  @override
  String get sessionsTitle => 'Sessions';

  @override
  String get sessionsCurrentProject => 'Current project';

  @override
  String get sessionsSearchPlaceholder => 'Search sessions, commands, file paths?';

  @override
  String get sessionsFootnote => 'This list only shows sessions in the current workspace.';

  @override
  String get sessionsEmptyTitle => 'No sessions in this workspace yet';

  @override
  String get sessionsNewSession => 'New Session';

  @override
  String get sessionsWaitingApproval => 'Waiting approval';

  @override
  String get sessionsPendingBadge => 'pending';

  @override
  String get sessionsRunning => 'Running';

  @override
  String get sessionsFailed => 'Failed';

  @override
  String get sessionsDone => 'Done';

  @override
  String get sessionsSessionNoun => 'session';

  @override
  String get sessionsTaskNoun => 'task';

}
