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
  /// **'Simplified Chinese'**
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
  String get settingsDataStatusSection;

  /// No description provided for @settingsDiagnosticsTitle.
  String get settingsDiagnosticsTitle;

  /// No description provided for @settingsDiagnosticsCount.
  String settingsDiagnosticsCount(int count);

  /// No description provided for @settingsGitStatusTitle.
  String get settingsGitStatusTitle;

  /// No description provided for @settingsGitClean.
  String get settingsGitClean;

  /// No description provided for @settingsGitFiles.
  String settingsGitFiles(int count);

  /// No description provided for @settingsAboutSection.
  String get settingsAboutSection;

  /// No description provided for @settingsExtensionsTitle.
  String get settingsExtensionsTitle;

  /// No description provided for @settingsExtensionsCount.
  String settingsExtensionsCount(int count);

  /// No description provided for @settingsAdaptersAction.
  String get settingsAdaptersAction;

  /// No description provided for @settingsNotificationsAction.
  String get settingsNotificationsAction;

  /// No description provided for @settingsGenerateDiagnosticsAction.
  String get settingsGenerateDiagnosticsAction;

  /// No description provided for @settingsCurrentConnectionTitle.
  String get settingsCurrentConnectionTitle;

  /// No description provided for @settingsConnected.
  String get settingsConnected;

  /// No description provided for @settingsWorkspaceLabel.
  String get settingsWorkspaceLabel;

  /// No description provided for @settingsSecurityModeLabel.
  String get settingsSecurityModeLabel;

  /// No description provided for @homeOverviewTitle.
  String get homeOverviewTitle;

  /// No description provided for @homeRunningMetricLabel.
  String get homeRunningMetricLabel;

  /// No description provided for @homeRunningMetricNote.
  String get homeRunningMetricNote;

  /// No description provided for @homeQueuedMetricLabel.
  String get homeQueuedMetricLabel;

  /// No description provided for @homeQueuedMetricNote.
  String get homeQueuedMetricNote;

  /// No description provided for @homeCompletedMetricLabel.
  String get homeCompletedMetricLabel;

  /// No description provided for @homeFilesLinesNote.
  String homeFilesLinesNote(int files, int lines);

  /// No description provided for @homeRecentRunsTitle.
  String get homeRecentRunsTitle;

  /// No description provided for @homeViewAllAction.
  String get homeViewAllAction;

  /// No description provided for @homeNoRuns.
  String get homeNoRuns;

  /// No description provided for @homeQuickActionsTitle.
  String get homeQuickActionsTitle;

  /// No description provided for @homeNewTaskTitle.
  String get homeNewTaskTitle;

  /// No description provided for @homeNewTaskSubtitle.
  String get homeNewTaskSubtitle;

  /// No description provided for @homeCommandTemplatesTitle.
  String get homeCommandTemplatesTitle;

  /// No description provided for @homeCommandTemplatesSubtitle.
  String get homeCommandTemplatesSubtitle;

  /// No description provided for @homeViewQueueTitle.
  String get homeViewQueueTitle;

  /// No description provided for @homeViewQueueSubtitle.
  String get homeViewQueueSubtitle;

  /// No description provided for @runsTitle.
  String get runsTitle;

  /// No description provided for @runsAllPill.
  String runsAllPill(int count);

  /// No description provided for @runsRunningPill.
  String runsRunningPill(int count);

  /// No description provided for @runsCompletedPill.
  String runsCompletedPill(int count);

  /// No description provided for @runsFailedPill.
  String runsFailedPill(int count);

  /// No description provided for @runsEmpty.
  String get runsEmpty;

  /// No description provided for @queueTitle.
  String get queueTitle;

  /// No description provided for @queueCountAction.
  String queueCountAction(int count);

  /// No description provided for @queueRunningPill.
  String queueRunningPill(int count);

  /// No description provided for @queueWaitingPill.
  String queueWaitingPill(int count);

  /// No description provided for @queueTotalPill.
  String queueTotalPill(int count);

  /// No description provided for @queueRunningSection.
  String get queueRunningSection;

  /// No description provided for @queueWaitingSection.
  String get queueWaitingSection;

  /// No description provided for @queueNoRunning.
  String get queueNoRunning;

  /// No description provided for @queueNoWaiting.
  String get queueNoWaiting;

  /// No description provided for @queueFootnote.
  String get queueFootnote;
  /// No description provided for @commonBack.
  String get commonBack;

  /// No description provided for @adaptersTitle.
  String get adaptersTitle;

  /// No description provided for @adaptersCount.
  String adaptersCount(int count);

  /// No description provided for @adaptersEmpty.
  String get adaptersEmpty;

  /// No description provided for @adaptersExtensionsSection.
  String get adaptersExtensionsSection;

  /// No description provided for @adaptersNoExtensions.
  String get adaptersNoExtensions;

  /// No description provided for @adaptersNotInstalled.
  String get adaptersNotInstalled;

  /// No description provided for @adaptersStatusOk.
  String get adaptersStatusOk;

  /// No description provided for @adaptersCapabilitiesLabel.
  String get adaptersCapabilitiesLabel;

  /// No description provided for @diagnosticsTitle.
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsDescription.
  String get diagnosticsDescription;

  /// No description provided for @diagnosticsSystemInfo.
  String get diagnosticsSystemInfo;

  /// No description provided for @diagnosticsAdapterStatus.
  String get diagnosticsAdapterStatus;

  /// No description provided for @diagnosticsRunLogsRecent.
  String get diagnosticsRunLogsRecent;

  /// No description provided for @diagnosticsEventRecordsRecent.
  String get diagnosticsEventRecordsRecent;

  /// No description provided for @diagnosticsConfigInfo.
  String get diagnosticsConfigInfo;

  /// No description provided for @diagnosticsEstimatedSize.
  String get diagnosticsEstimatedSize;

  /// No description provided for @diagnosticsGenerateAction.
  String get diagnosticsGenerateAction;

  /// No description provided for @notificationsTitle.
  String get notificationsTitle;

  /// No description provided for @notificationsTabAll.
  String get notificationsTabAll;

  /// No description provided for @notificationsTabUnread.
  String get notificationsTabUnread;

  /// No description provided for @notificationsTabMentions.
  String get notificationsTabMentions;

  /// No description provided for @notificationsApprovalRequired.
  String get notificationsApprovalRequired;

  /// No description provided for @notificationsRequestModify.
  String get notificationsRequestModify;

  /// No description provided for @notificationsTaskComplete.
  String get notificationsTaskComplete;

  /// No description provided for @notificationsRunCompletedDuration.
  String get notificationsRunCompletedDuration;

  /// No description provided for @notificationsTaskFailed.
  String get notificationsTaskFailed;

  /// No description provided for @notificationsDataSyncBody.
  String get notificationsDataSyncBody;

  /// No description provided for @notificationsYesterday1422.
  String get notificationsYesterday1422;

  /// No description provided for @notificationsQueueUpdate.
  String get notificationsQueueUpdate;

  /// No description provided for @notificationsCacheBody.
  String get notificationsCacheBody;

  /// No description provided for @notificationsYesterday1315.
  String get notificationsYesterday1315;

  /// No description provided for @notificationsSystemMessage.
  String get notificationsSystemMessage;

  /// No description provided for @notificationsConnectedBody.
  String get notificationsConnectedBody;

  /// No description provided for @notificationsYesterday1001.
  String get notificationsYesterday1001;

  /// No description provided for @runDetailTitle.
  String get runDetailTitle;

  /// No description provided for @runDetailMockTask.
  String get runDetailMockTask;

  /// No description provided for @runDetailRunningStatus.
  String get runDetailRunningStatus;

  /// No description provided for @runDetailStartedDuration.
  String get runDetailStartedDuration;

  /// No description provided for @runDetailTabOverview.
  String get runDetailTabOverview;

  /// No description provided for @runDetailTabEvents.
  String get runDetailTabEvents;

  /// No description provided for @runDetailTabFileChanges.
  String get runDetailTabFileChanges;

  /// No description provided for @runDetailTabConfig.
  String get runDetailTabConfig;

  /// No description provided for @runDetailUserPromptTitle.
  String get runDetailUserPromptTitle;

  /// No description provided for @runDetailUserPromptBody.
  String get runDetailUserPromptBody;

  /// No description provided for @runDetailThinkingTitle.
  String get runDetailThinkingTitle;

  /// No description provided for @runDetailThinkingBody.
  String get runDetailThinkingBody;

  /// No description provided for @runDetailReadFileTitle.
  String get runDetailReadFileTitle;

  /// No description provided for @runDetailSearchCodeTitle.
  String get runDetailSearchCodeTitle;

  /// No description provided for @runDetailSearchBody.
  String get runDetailSearchBody;

  /// No description provided for @runDetailEditFileTitle.
  String get runDetailEditFileTitle;

  /// No description provided for @runDetailRunCommandTitle.
  String get runDetailRunCommandTitle;

  /// No description provided for @runDetailCommandBody.
  String get runDetailCommandBody;

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
