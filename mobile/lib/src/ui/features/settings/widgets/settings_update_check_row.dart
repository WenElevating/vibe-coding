import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../view_models/app_update_view_model.dart';
import 'app_update_panel.dart';
import 'settings_row.dart';

class SettingsUpdateCheckRow extends StatelessWidget {
  const SettingsUpdateCheckRow({super.key, required this.viewModel});

  final AppUpdateViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => AppUpdatePanel(
        state: viewModel.state,
        onCheck: () => unawaited(viewModel.checkForUpdates()),
        onDownload: () => unawaited(viewModel.download(installWhenReady: true)),
        onInstall: () => unawaited(viewModel.install()),
        onDiscard: () => unawaited(viewModel.discard()),
        onPostpone: viewModel.postponeCurrentUpdatePrompt,
        child: SettingsTapRow(
            title: l10n.appUpdateCheckAction,
            value: _appUpdateRowValue(l10n, viewModel.state),
            onTap: () => unawaited(viewModel.checkForUpdates())),
      ),
    );
  }
}

String _appUpdateRowValue(AppLocalizations l10n, AppUpdateState state) {
  if (state.status == AppUpdateStatus.idle) {
    return state.installedVersionName;
  }
  return appUpdateTitleFor(l10n, state);
}
