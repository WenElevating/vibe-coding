import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../app/language_scope.dart';
import '../../../../shell/shell.dart';
import '../../../core/widgets/widgets.dart';
import '../sheets/language_picker_sheet.dart';
import '../view_models/app_update_view_model.dart';
import '../view_models/settings_view_model.dart';
import '../widgets/permission_mode_row.dart';
import '../widgets/settings_action_button.dart';
import '../widgets/settings_card.dart';
import '../widgets/settings_connection_card.dart';
import '../widgets/settings_row.dart';
import '../widgets/settings_switch_row.dart';
import '../widgets/settings_update_check_row.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.open,
    required this.viewModel,
    required this.streamOutput,
    required this.expandThinking,
    this.appUpdateViewModel,
    required this.onStreamOutputChanged,
    required this.onExpandThinkingChanged,
  });

  final ValueChanged<RoutePage> open;
  final SettingsViewModel viewModel;
  final bool streamOutput;
  final bool expandThinking;
  final AppUpdateViewModel? appUpdateViewModel;
  final ValueChanged<bool> onStreamOutputChanged;
  final ValueChanged<bool> onExpandThinkingChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final language = LanguageScope.watch(context);
        final gitStatus = viewModel.gitStatus;
        final selectedWorkspace = viewModel.selectedWorkspace;
        return PageScroll(
          children: [
            TopBar(title: l10n.settingsTitle),
            const SizedBox(height: 14),
            SettingsConnectionCard(
                workspace: selectedWorkspace,
                connectionConfig: viewModel.connectionConfig,
                mode: viewModel.health.mode,
                lanMode: viewModel.health.lanMode,
                l10n: l10n),
            const SizedBox(height: 20),
            Subhead(l10n.settingsPreferencesSection),
            SettingsCard(children: [
              SettingsTapRow(
                  title: l10n.settingsLanguageTitle,
                  value: languageModeLabel(l10n, language.mode),
                  onTap: () => showLanguagePicker(context)),
            ]),
            const SizedBox(height: 20),
            Subhead(l10n.settingsCodingControlSection),
            SettingsCard(children: [
              PermissionModeRow(
                  value: viewModel.permissionMode,
                  onChanged: (value) =>
                      unawaited(viewModel.setPermissionMode(value)),
                  l10n: l10n),
              SettingsSwitchRow(
                  title: l10n.settingsStreamOutputTitle,
                  subtitle: l10n.settingsStreamOutputSubtitle,
                  value: streamOutput,
                  onChanged: onStreamOutputChanged),
              SettingsSwitchRow(
                  title: l10n.settingsExpandThinkingTitle,
                  subtitle: l10n.settingsExpandThinkingSubtitle,
                  value: expandThinking,
                  onChanged: onExpandThinkingChanged),
              SettingsSwitchRow(
                  title: l10n.settingsKeepSessionLiveInBackgroundTitle,
                  subtitle: l10n.settingsKeepSessionLiveInBackgroundSubtitle,
                  value: viewModel.keepConversationEventsInBackground,
                  onChanged: (value) => unawaited(
                      viewModel.setKeepConversationEventsInBackground(value))),
            ]),
            const SizedBox(height: 20),
            Subhead(l10n.settingsDataStatusSection),
            SettingsCard(children: [
              SettingsRow(
                  title: l10n.settingsDiagnosticsTitle,
                  value: l10n.settingsDiagnosticsCount(
                      viewModel.diagnostics?.diagnostics.length ?? 0)),
              SettingsRow(
                  title: l10n.settingsGitStatusTitle,
                  value: gitStatus?.clean == true
                      ? l10n.settingsGitClean
                      : l10n.settingsGitFiles(gitStatus?.files.length ?? 0)),
            ]),
            const SizedBox(height: 20),
            Subhead(l10n.settingsAboutSection),
            SettingsCard(children: [
              SettingsRow(
                  title: 'daemon', value: viewModel.health.daemonVersion),
              SettingsRow(
                  title: l10n.settingsExtensionsTitle,
                  value:
                      l10n.settingsExtensionsCount(viewModel.extensionsCount)),
              if (appUpdateViewModel != null)
                SettingsUpdateCheckRow(viewModel: appUpdateViewModel!),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                  child: SettingsActionButton(l10n.settingsAdaptersAction,
                      icon: Icons.extension_rounded,
                      onTap: () => open(RoutePage.adapters))),
              const SizedBox(width: 10),
              Expanded(
                  child: SettingsActionButton(l10n.settingsNotificationsAction,
                      icon: Icons.notifications_rounded,
                      onTap: () => open(RoutePage.notifications))),
            ]),
            const SizedBox(height: 10),
            SettingsActionButton(l10n.settingsGenerateDiagnosticsAction,
                icon: Icons.health_and_safety_rounded,
                fullWidth: true,
                onTap: () => open(RoutePage.diagnostics)),
          ],
        );
      },
    );
  }
}
