import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AI CLI Control'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navRuns.
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get navRuns;

  /// No description provided for @navCoding.
  ///
  /// In en, this message translates to:
  /// **'Coding'**
  String get navCoding;

  /// No description provided for @navDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get navDevices;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsPreferencesSection.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferencesSection;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageZhHans.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZhHans;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsLanguagePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get settingsLanguagePickerTitle;

  /// No description provided for @settingsCodingControlSection.
  ///
  /// In en, this message translates to:
  /// **'Coding control'**
  String get settingsCodingControlSection;

  /// No description provided for @settingsStreamOutputTitle.
  ///
  /// In en, this message translates to:
  /// **'Stream output'**
  String get settingsStreamOutputTitle;

  /// No description provided for @settingsStreamOutputSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When off, only the final answer is shown to avoid duplicate deltas and complete messages.'**
  String get settingsStreamOutputSubtitle;

  /// No description provided for @settingsExpandThinkingTitle.
  ///
  /// In en, this message translates to:
  /// **'Show thinking process'**
  String get settingsExpandThinkingTitle;

  /// No description provided for @settingsExpandThinkingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When on, model thinking is expanded by default; when off, it stays collapsed.'**
  String get settingsExpandThinkingSubtitle;

  /// No description provided for @settingsPermissionModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission mode'**
  String get settingsPermissionModeTitle;

  /// No description provided for @settingsPermissionDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsPermissionDefault;

  /// No description provided for @settingsPermissionAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsPermissionAuto;

  /// No description provided for @settingsPermissionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default asks for CLI permission confirmation; auto lets the CLI handle permissions.'**
  String get settingsPermissionSubtitle;

  /// No description provided for @settingsDataStatusSection.
  ///
  /// In en, this message translates to:
  /// **'Data status'**
  String get settingsDataStatusSection;

  /// No description provided for @settingsDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Code diagnostics'**
  String get settingsDiagnosticsTitle;

  /// No description provided for @settingsDiagnosticsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String settingsDiagnosticsCount(int count);

  /// No description provided for @settingsGitStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Git status'**
  String get settingsGitStatusTitle;

  /// No description provided for @settingsGitClean.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get settingsGitClean;

  /// No description provided for @settingsGitFiles.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String settingsGitFiles(int count);

  /// No description provided for @settingsAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// No description provided for @settingsExtensionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get settingsExtensionsTitle;

  /// No description provided for @settingsExtensionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String settingsExtensionsCount(int count);

  /// No description provided for @settingsAdaptersAction.
  ///
  /// In en, this message translates to:
  /// **'Adapters'**
  String get settingsAdaptersAction;

  /// No description provided for @settingsNotificationsAction.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsAction;

  /// No description provided for @settingsGenerateDiagnosticsAction.
  ///
  /// In en, this message translates to:
  /// **'Generate diagnostics'**
  String get settingsGenerateDiagnosticsAction;

  /// No description provided for @settingsCurrentConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Current connection'**
  String get settingsCurrentConnectionTitle;

  /// No description provided for @settingsConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get settingsConnected;

  /// No description provided for @settingsWorkspaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get settingsWorkspaceLabel;

  /// No description provided for @settingsSecurityModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Security mode'**
  String get settingsSecurityModeLabel;

  /// No description provided for @settingsDaemonAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Daemon address'**
  String get settingsDaemonAddressLabel;

  /// No description provided for @settingsProxyModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Proxy mode'**
  String get settingsProxyModeLabel;

  /// No description provided for @settingsProxyDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get settingsProxyDirect;

  /// No description provided for @settingsProxySystem.
  ///
  /// In en, this message translates to:
  /// **'System proxy'**
  String get settingsProxySystem;

  /// No description provided for @settingsProxyManual.
  ///
  /// In en, this message translates to:
  /// **'Manual proxy'**
  String get settingsProxyManual;

  /// No description provided for @connectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connectionTitle;

  /// No description provided for @connectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm daemon target before workspaces load'**
  String get connectionSubtitle;

  /// No description provided for @connectionAddressSection.
  ///
  /// In en, this message translates to:
  /// **'Connection address'**
  String get connectionAddressSection;

  /// No description provided for @connectionProxySection.
  ///
  /// In en, this message translates to:
  /// **'Network proxy'**
  String get connectionProxySection;

  /// No description provided for @connectionConnectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectionConnectAction;

  /// No description provided for @connectionReconnectAction.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get connectionReconnectAction;

  /// No description provided for @connectionStatusLoadingConfig.
  ///
  /// In en, this message translates to:
  /// **'Loading connection settings'**
  String get connectionStatusLoadingConfig;

  /// No description provided for @connectionStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get connectionStatusIdle;

  /// No description provided for @connectionStatusValidating.
  ///
  /// In en, this message translates to:
  /// **'Resolving connection address'**
  String get connectionStatusValidating;

  /// No description provided for @connectionStatusCheckingHealth.
  ///
  /// In en, this message translates to:
  /// **'Checking daemon health'**
  String get connectionStatusCheckingHealth;

  /// No description provided for @connectionStatusLoadingSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Syncing workspace state'**
  String get connectionStatusLoadingSnapshot;

  /// No description provided for @connectionStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionStatusConnected;

  /// No description provided for @connectionStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get connectionStatusFailed;

  /// No description provided for @connectionStatusReady.
  ///
  /// In en, this message translates to:
  /// **'READY'**
  String get connectionStatusReady;

  /// No description provided for @connectionStatusError.
  ///
  /// In en, this message translates to:
  /// **'ERROR'**
  String get connectionStatusError;

  /// No description provided for @connectionTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get connectionTargetLabel;

  /// No description provided for @connectionProxyLabel.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get connectionProxyLabel;

  /// No description provided for @homeOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get homeOverviewTitle;

  /// No description provided for @homeRunningMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get homeRunningMetricLabel;

  /// No description provided for @homeRunningMetricNote.
  ///
  /// In en, this message translates to:
  /// **'Active tasks'**
  String get homeRunningMetricNote;

  /// No description provided for @homeQueuedMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get homeQueuedMetricLabel;

  /// No description provided for @homeQueuedMetricNote.
  ///
  /// In en, this message translates to:
  /// **'Queued tasks'**
  String get homeQueuedMetricNote;

  /// No description provided for @homeCompletedMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Completed (24h)'**
  String get homeCompletedMetricLabel;

  /// No description provided for @homeFilesLinesNote.
  ///
  /// In en, this message translates to:
  /// **'{files} files ? {lines} lines'**
  String homeFilesLinesNote(int files, int lines);

  /// No description provided for @homeRecentRunsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent runs'**
  String get homeRecentRunsTitle;

  /// No description provided for @homeViewAllAction.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get homeViewAllAction;

  /// No description provided for @homeNoRuns.
  ///
  /// In en, this message translates to:
  /// **'No runs yet'**
  String get homeNoRuns;

  /// No description provided for @homeQuickActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get homeQuickActionsTitle;

  /// No description provided for @homeNewTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get homeNewTaskTitle;

  /// No description provided for @homeNewTaskSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new task'**
  String get homeNewTaskSubtitle;

  /// No description provided for @homeCommandTemplatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Command templates'**
  String get homeCommandTemplatesTitle;

  /// No description provided for @homeCommandTemplatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Run preset commands'**
  String get homeCommandTemplatesSubtitle;

  /// No description provided for @homeViewQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'View queue'**
  String get homeViewQueueTitle;

  /// No description provided for @homeViewQueueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review queued tasks'**
  String get homeViewQueueSubtitle;

  /// No description provided for @homeNowTitle.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get homeNowTitle;

  /// No description provided for @homeInterruptsTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get homeInterruptsTitle;

  /// No description provided for @homeExecutionStreamTitle.
  ///
  /// In en, this message translates to:
  /// **'Execution stream'**
  String get homeExecutionStreamTitle;

  /// No description provided for @homeWorkspaceSignalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace signals'**
  String get homeWorkspaceSignalsTitle;

  /// No description provided for @homeIdleNow.
  ///
  /// In en, this message translates to:
  /// **'No blockers in this workspace'**
  String get homeIdleNow;

  /// No description provided for @homeNoRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No recent activity in this workspace'**
  String get homeNoRecentActivity;

  /// No description provided for @homeGitChangedLabel.
  ///
  /// In en, this message translates to:
  /// **'Git changes'**
  String get homeGitChangedLabel;

  /// No description provided for @homeDiagnosticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get homeDiagnosticsLabel;

  /// No description provided for @homeQueueLabel.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get homeQueueLabel;

  /// No description provided for @homeRecentFilesLabel.
  ///
  /// In en, this message translates to:
  /// **'Recent files'**
  String get homeRecentFilesLabel;

  /// No description provided for @homeMoreSignalsLabel.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String homeMoreSignalsLabel(int count);

  /// No description provided for @runsTitle.
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get runsTitle;

  /// No description provided for @runsAllPill.
  ///
  /// In en, this message translates to:
  /// **'All {count}'**
  String runsAllPill(int count);

  /// No description provided for @runsRunningPill.
  ///
  /// In en, this message translates to:
  /// **'Running {count}'**
  String runsRunningPill(int count);

  /// No description provided for @runsCompletedPill.
  ///
  /// In en, this message translates to:
  /// **'Completed {count}'**
  String runsCompletedPill(int count);

  /// No description provided for @runsFailedPill.
  ///
  /// In en, this message translates to:
  /// **'Failed {count}'**
  String runsFailedPill(int count);

  /// No description provided for @runsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No runs yet. Start a real AI CLI task from command templates.'**
  String get runsEmpty;

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Run queue'**
  String get queueTitle;

  /// No description provided for @queueCountAction.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String queueCountAction(int count);

  /// No description provided for @queueRunningPill.
  ///
  /// In en, this message translates to:
  /// **'Running {count}'**
  String queueRunningPill(int count);

  /// No description provided for @queueWaitingPill.
  ///
  /// In en, this message translates to:
  /// **'Queued {count}'**
  String queueWaitingPill(int count);

  /// No description provided for @queueTotalPill.
  ///
  /// In en, this message translates to:
  /// **'Total {count}'**
  String queueTotalPill(int count);

  /// No description provided for @queueRunningSection.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get queueRunningSection;

  /// No description provided for @queueWaitingSection.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get queueWaitingSection;

  /// No description provided for @queueNoRunning.
  ///
  /// In en, this message translates to:
  /// **'No running queue items'**
  String get queueNoRunning;

  /// No description provided for @queueNoWaiting.
  ///
  /// In en, this message translates to:
  /// **'No waiting tasks'**
  String get queueNoWaiting;

  /// No description provided for @queueFootnote.
  ///
  /// In en, this message translates to:
  /// **'Queue data comes from the daemon. Tasks run in workspace order.'**
  String get queueFootnote;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @adaptersTitle.
  ///
  /// In en, this message translates to:
  /// **'Adapter status'**
  String get adaptersTitle;

  /// No description provided for @adaptersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String adaptersCount(int count);

  /// No description provided for @adaptersEmpty.
  ///
  /// In en, this message translates to:
  /// **'daemon returned no adapters'**
  String get adaptersEmpty;

  /// No description provided for @adaptersExtensionsSection.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get adaptersExtensionsSection;

  /// No description provided for @adaptersNoExtensions.
  ///
  /// In en, this message translates to:
  /// **'No extension information'**
  String get adaptersNoExtensions;

  /// No description provided for @adaptersNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'not installed'**
  String get adaptersNotInstalled;

  /// No description provided for @adaptersStatusOk.
  ///
  /// In en, this message translates to:
  /// **'Status                         OK'**
  String get adaptersStatusOk;

  /// No description provided for @adaptersCapabilitiesLabel.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get adaptersCapabilitiesLabel;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsDescription.
  ///
  /// In en, this message translates to:
  /// **'Export a redacted diagnostics bundle for troubleshooting'**
  String get diagnosticsDescription;

  /// No description provided for @diagnosticsSystemInfo.
  ///
  /// In en, this message translates to:
  /// **'System information'**
  String get diagnosticsSystemInfo;

  /// No description provided for @diagnosticsAdapterStatus.
  ///
  /// In en, this message translates to:
  /// **'Adapter status'**
  String get diagnosticsAdapterStatus;

  /// No description provided for @diagnosticsRunLogsRecent.
  ///
  /// In en, this message translates to:
  /// **'Run logs (last 7 days)'**
  String get diagnosticsRunLogsRecent;

  /// No description provided for @diagnosticsEventRecordsRecent.
  ///
  /// In en, this message translates to:
  /// **'Event records (last 7 days)'**
  String get diagnosticsEventRecordsRecent;

  /// No description provided for @diagnosticsConfigInfo.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get diagnosticsConfigInfo;

  /// No description provided for @diagnosticsEstimatedSize.
  ///
  /// In en, this message translates to:
  /// **'Estimated size'**
  String get diagnosticsEstimatedSize;

  /// No description provided for @diagnosticsGenerateAction.
  ///
  /// In en, this message translates to:
  /// **'Generate diagnostics bundle'**
  String get diagnosticsGenerateAction;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsTabAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notificationsTabAll;

  /// No description provided for @notificationsTabUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get notificationsTabUnread;

  /// No description provided for @notificationsTabMentions.
  ///
  /// In en, this message translates to:
  /// **'@me'**
  String get notificationsTabMentions;

  /// No description provided for @notificationsApprovalRequired.
  ///
  /// In en, this message translates to:
  /// **'Approval required'**
  String get notificationsApprovalRequired;

  /// No description provided for @notificationsRequestModify.
  ///
  /// In en, this message translates to:
  /// **'Claude Code requests changes\nlib/services/auth_service.dart'**
  String get notificationsRequestModify;

  /// No description provided for @notificationsTaskComplete.
  ///
  /// In en, this message translates to:
  /// **'Task complete'**
  String get notificationsTaskComplete;

  /// No description provided for @notificationsRunCompletedDuration.
  ///
  /// In en, this message translates to:
  /// **'Add unit tests for user service\nRun completed, duration 28m 15s'**
  String get notificationsRunCompletedDuration;

  /// No description provided for @notificationsTaskFailed.
  ///
  /// In en, this message translates to:
  /// **'Task failed'**
  String get notificationsTaskFailed;

  /// No description provided for @notificationsDataSyncBody.
  ///
  /// In en, this message translates to:
  /// **'Optimize data sync logic\nRun failed, view details'**
  String get notificationsDataSyncBody;

  /// No description provided for @notificationsYesterday1422.
  ///
  /// In en, this message translates to:
  /// **'Yesterday 14:22'**
  String get notificationsYesterday1422;

  /// No description provided for @notificationsQueueUpdate.
  ///
  /// In en, this message translates to:
  /// **'Queue update'**
  String get notificationsQueueUpdate;

  /// No description provided for @notificationsCacheBody.
  ///
  /// In en, this message translates to:
  /// **'Optimize cache strategy\nStarted running'**
  String get notificationsCacheBody;

  /// No description provided for @notificationsYesterday1315.
  ///
  /// In en, this message translates to:
  /// **'Yesterday 13:15'**
  String get notificationsYesterday1315;

  /// No description provided for @notificationsSystemMessage.
  ///
  /// In en, this message translates to:
  /// **'System message'**
  String get notificationsSystemMessage;

  /// No description provided for @notificationsConnectedBody.
  ///
  /// In en, this message translates to:
  /// **'Connected to DESKTOP-DEV'**
  String get notificationsConnectedBody;

  /// No description provided for @notificationsYesterday1001.
  ///
  /// In en, this message translates to:
  /// **'Yesterday 10:01'**
  String get notificationsYesterday1001;

  /// No description provided for @runDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Run details'**
  String get runDetailTitle;

  /// No description provided for @runDetailMockTask.
  ///
  /// In en, this message translates to:
  /// **'Fix login API test failure'**
  String get runDetailMockTask;

  /// No description provided for @runDetailRunningStatus.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get runDetailRunningStatus;

  /// No description provided for @runDetailStartedDuration.
  ///
  /// In en, this message translates to:
  /// **'10:32 started ? Duration 12m 45s'**
  String get runDetailStartedDuration;

  /// No description provided for @runDetailTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get runDetailTabOverview;

  /// No description provided for @runDetailTabEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get runDetailTabEvents;

  /// No description provided for @runDetailTabFileChanges.
  ///
  /// In en, this message translates to:
  /// **'File changes'**
  String get runDetailTabFileChanges;

  /// No description provided for @runDetailTabConfig.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get runDetailTabConfig;

  /// No description provided for @runDetailUserPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'User prompt'**
  String get runDetailUserPromptTitle;

  /// No description provided for @runDetailUserPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Fix the login API test failure and add boundary-condition tests.'**
  String get runDetailUserPromptBody;

  /// No description provided for @runDetailThinkingTitle.
  ///
  /// In en, this message translates to:
  /// **'Claude starts thinking'**
  String get runDetailThinkingTitle;

  /// No description provided for @runDetailThinkingBody.
  ///
  /// In en, this message translates to:
  /// **'Analyzing the problem and related code...'**
  String get runDetailThinkingBody;

  /// No description provided for @runDetailReadFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Read file'**
  String get runDetailReadFileTitle;

  /// No description provided for @runDetailSearchCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Search code'**
  String get runDetailSearchCodeTitle;

  /// No description provided for @runDetailSearchBody.
  ///
  /// In en, this message translates to:
  /// **'search: \"login failure test\"\nFound 12 results'**
  String get runDetailSearchBody;

  /// No description provided for @runDetailEditFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit file'**
  String get runDetailEditFileTitle;

  /// No description provided for @runDetailRunCommandTitle.
  ///
  /// In en, this message translates to:
  /// **'Run command'**
  String get runDetailRunCommandTitle;

  /// No description provided for @runDetailCommandBody.
  ///
  /// In en, this message translates to:
  /// **'dart test tests/login_test.dart      running ?'**
  String get runDetailCommandBody;

  /// No description provided for @sessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessionsTitle;

  /// No description provided for @sessionsCurrentProject.
  ///
  /// In en, this message translates to:
  /// **'Current project'**
  String get sessionsCurrentProject;

  /// No description provided for @sessionsSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search sessions, commands, file paths?'**
  String get sessionsSearchPlaceholder;

  /// No description provided for @sessionsFootnote.
  ///
  /// In en, this message translates to:
  /// **'This list only shows sessions in the current workspace.'**
  String get sessionsFootnote;

  /// No description provided for @sessionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No sessions in this workspace yet'**
  String get sessionsEmptyTitle;

  /// No description provided for @sessionsNewSession.
  ///
  /// In en, this message translates to:
  /// **'New Session'**
  String get sessionsNewSession;

  /// No description provided for @sessionsWaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting approval'**
  String get sessionsWaitingApproval;

  /// No description provided for @sessionsPendingBadge.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get sessionsPendingBadge;

  /// No description provided for @sessionsRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get sessionsRunning;

  /// No description provided for @sessionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get sessionsFailed;

  /// No description provided for @sessionsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sessionsDone;

  /// No description provided for @sessionsSessionNoun.
  ///
  /// In en, this message translates to:
  /// **'session'**
  String get sessionsSessionNoun;

  /// No description provided for @sessionsTaskNoun.
  ///
  /// In en, this message translates to:
  /// **'task'**
  String get sessionsTaskNoun;

  /// No description provided for @workspaceAdapterPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose model / CLI'**
  String get workspaceAdapterPickerTitle;

  /// No description provided for @workspaceAdapterPickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used for the next real daemon run. It cannot be switched while running.'**
  String get workspaceAdapterPickerSubtitle;

  /// No description provided for @workspaceListTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspaceListTitle;

  /// No description provided for @workspaceAvailableSection.
  ///
  /// In en, this message translates to:
  /// **'Available Workspaces'**
  String get workspaceAvailableSection;

  /// No description provided for @workspaceListFootnote.
  ///
  /// In en, this message translates to:
  /// **'Choose the folder where CLI commands will run, then open or create a session inside it.'**
  String get workspaceListFootnote;

  /// No description provided for @workspaceCurrentFallback.
  ///
  /// In en, this message translates to:
  /// **'Current workspace'**
  String get workspaceCurrentFallback;

  /// No description provided for @workspaceSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get workspaceSheetTitle;

  /// No description provided for @workspaceSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch the CLI execution directory. The current session stays available.'**
  String get workspaceSheetSubtitle;

  /// No description provided for @workspacePathHint.
  ///
  /// In en, this message translates to:
  /// **'Enter or browse a folder path'**
  String get workspacePathHint;

  /// No description provided for @workspaceBrowseAction.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get workspaceBrowseAction;

  /// No description provided for @workspaceNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get workspaceNameHint;

  /// No description provided for @workspaceCreatingAction.
  ///
  /// In en, this message translates to:
  /// **'Creating'**
  String get workspaceCreatingAction;

  /// No description provided for @workspaceCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get workspaceCreateAction;

  /// No description provided for @workspaceExistingSection.
  ///
  /// In en, this message translates to:
  /// **'Existing workspaces'**
  String get workspaceExistingSection;

  /// No description provided for @workspaceSafeDirectoryMeta.
  ///
  /// In en, this message translates to:
  /// **'Safe execution directory'**
  String get workspaceSafeDirectoryMeta;

  /// No description provided for @workspaceAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add workspace'**
  String get workspaceAddTitle;

  /// No description provided for @workspaceChoosePathHint.
  ///
  /// In en, this message translates to:
  /// **'Choose or enter a folder path'**
  String get workspaceChoosePathHint;

  /// No description provided for @workspaceCreateAndUseAction.
  ///
  /// In en, this message translates to:
  /// **'Create and use'**
  String get workspaceCreateAndUseAction;

  /// No description provided for @workspaceChooseFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get workspaceChooseFolderTitle;

  /// No description provided for @workspaceSelectCurrentAction.
  ///
  /// In en, this message translates to:
  /// **'Select current'**
  String get workspaceSelectCurrentAction;

  /// No description provided for @workspaceBrowserPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Choose a drive or root directory, then continue into a folder'**
  String get workspaceBrowserPlaceholder;

  /// No description provided for @workbenchComposerNoAdapter.
  ///
  /// In en, this message translates to:
  /// **'No available CLI adapter'**
  String get workbenchComposerNoAdapter;

  /// No description provided for @workbenchComposerFollowUpHint.
  ///
  /// In en, this message translates to:
  /// **'Request follow-up changes?'**
  String get workbenchComposerFollowUpHint;

  /// No description provided for @workbenchApprovalPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs your approval'**
  String get workbenchApprovalPageTitle;

  /// No description provided for @workbenchModifyFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Modify file'**
  String get workbenchModifyFileTitle;

  /// No description provided for @workbenchDiffTab.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get workbenchDiffTab;

  /// No description provided for @workbenchFileContentTab.
  ///
  /// In en, this message translates to:
  /// **'File content'**
  String get workbenchFileContentTab;

  /// No description provided for @workbenchApprovalActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Approval actions'**
  String get workbenchApprovalActionsSection;

  /// No description provided for @workbenchClaudeSuggestionTitle.
  ///
  /// In en, this message translates to:
  /// **'Claude suggested changes'**
  String get workbenchClaudeSuggestionTitle;

  /// No description provided for @workbenchMockFixEmptyResponse.
  ///
  /// In en, this message translates to:
  /// **'Fix test failure caused by empty responses'**
  String get workbenchMockFixEmptyResponse;

  /// No description provided for @workbenchRejectAction.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get workbenchRejectAction;

  /// No description provided for @workbenchApproveAction.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get workbenchApproveAction;

  /// No description provided for @workbenchInlineReady.
  ///
  /// In en, this message translates to:
  /// **'Ready for a coding task'**
  String get workbenchInlineReady;

  /// No description provided for @workbenchInlineCompleted.
  ///
  /// In en, this message translates to:
  /// **'CLI session complete ? {count} events processed'**
  String workbenchInlineCompleted(int count);

  /// No description provided for @workbenchInlineConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting {adapter} ? {count} events processed'**
  String workbenchInlineConnecting(String adapter, int count);

  /// No description provided for @workbenchApprovalMissingId.
  ///
  /// In en, this message translates to:
  /// **'daemon did not provide approvalId, so mobile cannot process it.'**
  String get workbenchApprovalMissingId;

  /// No description provided for @workbenchQuestionTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs your direction'**
  String get workbenchQuestionTitle;

  /// No description provided for @workbenchCommandDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Command details'**
  String get workbenchCommandDetailTitle;

  /// No description provided for @workbenchOutputDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Output details'**
  String get workbenchOutputDetailTitle;

  /// No description provided for @workbenchCommandMetaEmpty.
  ///
  /// In en, this message translates to:
  /// **'Run 1 command'**
  String get workbenchCommandMetaEmpty;

  /// No description provided for @workbenchCommandMetaWithTitle.
  ///
  /// In en, this message translates to:
  /// **'Run 1 command ? {title}'**
  String workbenchCommandMetaWithTitle(String title);

  /// No description provided for @workbenchCopyAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy full text'**
  String get workbenchCopyAllTooltip;

  /// No description provided for @workbenchCopiedSnack.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get workbenchCopiedSnack;

  /// No description provided for @workbenchCloseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get workbenchCloseTooltip;

  /// No description provided for @workbenchPendingRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get workbenchPendingRunning;

  /// No description provided for @workbenchPreviewReceivingOutput.
  ///
  /// In en, this message translates to:
  /// **'Receiving CLI output...'**
  String get workbenchPreviewReceivingOutput;

  /// No description provided for @workbenchPreviewStartedSession.
  ///
  /// In en, this message translates to:
  /// **'Started claude session'**
  String get workbenchPreviewStartedSession;

  /// No description provided for @workbenchApprovalCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs approval'**
  String get workbenchApprovalCardTitle;

  /// No description provided for @workbenchRunErrorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Run error:'**
  String get workbenchRunErrorPrefix;

  /// No description provided for @workbenchNewSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'New coding session'**
  String get workbenchNewSessionTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
