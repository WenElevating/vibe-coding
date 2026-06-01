import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/daemon_connection_config.dart';
import '../../models/protocol.dart';
import '../core/widgets/widgets.dart';
import '../features/settings/settings.dart'
    show
        AppUpdatePanel,
        AppUpdateState,
        AppUpdateStatus,
        AppUpdateViewModel,
        appUpdateTitleFor;
import 'empty_state_widgets.dart';

class EmptySettingsPage extends StatelessWidget {
  const EmptySettingsPage({
    super.key,
    required this.health,
    required this.connectionConfig,
    this.appUpdateViewModel,
  });

  final DaemonHealth? health;
  final DaemonConnectionConfig connectionConfig;
  final AppUpdateViewModel? appUpdateViewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      Subhead(l10n.settingsCurrentConnectionTitle),
      EmptyStateCard(children: [
        EmptyStateRow(
          title: l10n.settingsDaemonAddressLabel,
          value: connectionConfig.addressInput,
        ),
        EmptyStateRow(
          title: l10n.settingsWorkspaceLabel,
          value: l10n.workspaceAvailableSection,
        ),
      ]),
      const SizedBox(height: 20),
      Subhead(l10n.settingsAboutSection),
      EmptyStateCard(children: [
        EmptyStateRow(title: 'daemon', value: health?.daemonVersion ?? '—'),
        if (appUpdateViewModel != null)
          _EmptyAppUpdateCheckRow(viewModel: appUpdateViewModel!),
      ]),
    ]);
  }
}

class _EmptyAppUpdateCheckRow extends StatelessWidget {
  const _EmptyAppUpdateCheckRow({required this.viewModel});

  final AppUpdateViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => AppUpdatePanel(
        state: viewModel.state,
        onCheck: () => unawaited(viewModel.checkForUpdates()),
        onDownload: () => unawaited(viewModel.download()),
        onInstall: () => unawaited(viewModel.install()),
        onDiscard: () => unawaited(viewModel.discard()),
        onPostpone: viewModel.postponeCurrentUpdatePrompt,
        child: EmptyStateTapRow(
          title: l10n.appUpdateCheckAction,
          value: _emptyAppUpdateRowValue(l10n, viewModel.state),
          onTap: () => unawaited(viewModel.checkForUpdates()),
        ),
      ),
    );
  }
}

String _emptyAppUpdateRowValue(AppLocalizations l10n, AppUpdateState state) {
  if (state.status == AppUpdateStatus.idle) {
    return state.installedVersionName;
  }
  return appUpdateTitleFor(l10n, state);
}
