import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../view_models/app_update_view_model.dart';

class AppUpdatePanel extends StatelessWidget {
  const AppUpdatePanel({
    super.key,
    required this.state,
    required this.onCheck,
    required this.onDownload,
    required this.onInstall,
    required this.onOpenPermissionSettings,
    required this.onDiscard,
  });

  final AppUpdateState state;
  final VoidCallback onCheck;
  final VoidCallback onDownload;
  final VoidCallback onInstall;
  final VoidCallback onOpenPermissionSettings;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final title = switch (state.status) {
      AppUpdateStatus.upToDate => 'App is up to date',
      AppUpdateStatus.available =>
        state.mandatory ? 'Required update available' : 'Update available',
      AppUpdateStatus.downloading => 'Downloading update',
      AppUpdateStatus.paused => 'Download paused',
      AppUpdateStatus.verifying => 'Verifying update',
      AppUpdateStatus.readyToInstall => state.mandatory
          ? 'Required update ready to install'
          : 'Update ready to install',
      AppUpdateStatus.installPermissionNeeded => state.mandatory
          ? 'Required update install permission needed'
          : 'Install permission needed',
      AppUpdateStatus.installing => 'Opening Android installer',
      AppUpdateStatus.awaitingUserConfirmation => state.mandatory
          ? 'Confirm required update install'
          : 'Confirm update install',
      AppUpdateStatus.installSucceeded => 'Update installed',
      AppUpdateStatus.installCancelled => state.mandatory
          ? 'Required update install cancelled'
          : 'Install cancelled',
      AppUpdateStatus.installFailed =>
        state.mandatory ? 'Required update install failed' : 'Install failed',
      AppUpdateStatus.failed => 'Update failed',
      AppUpdateStatus.checking => 'Checking for updates',
      AppUpdateStatus.cancelled => 'Update discarded',
      AppUpdateStatus.idle => 'App update',
    };
    final subtitle = state.errorMessage ??
        'Installed ${state.installedVersionName}+${state.installedVersionCode}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                color: theme.active,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: theme.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_canCheck(state.status))
                _Button('Check', Icons.refresh_rounded, onCheck),
              if (state.status == AppUpdateStatus.available ||
                  state.status == AppUpdateStatus.paused ||
                  state.status == AppUpdateStatus.cancelled ||
                  state.status == AppUpdateStatus.failed ||
                  state.status == AppUpdateStatus.installCancelled)
                _Button('Download', Icons.download_rounded, onDownload),
              if (state.status == AppUpdateStatus.readyToInstall ||
                  state.status == AppUpdateStatus.installPermissionNeeded ||
                  state.status == AppUpdateStatus.installCancelled)
                _Button('Install', Icons.install_mobile_rounded, onInstall),
              if (state.status == AppUpdateStatus.installPermissionNeeded)
                _Button(
                  'Open settings',
                  Icons.settings_applications_rounded,
                  onOpenPermissionSettings,
                ),
              if (state.status == AppUpdateStatus.paused ||
                  state.status == AppUpdateStatus.readyToInstall ||
                  state.status == AppUpdateStatus.awaitingUserConfirmation ||
                  state.status == AppUpdateStatus.installCancelled ||
                  state.status == AppUpdateStatus.failed)
                _Button('Discard', Icons.delete_outline_rounded, onDiscard),
            ],
          ),
        ],
      ),
    );
  }
}

bool _canCheck(AppUpdateStatus status) {
  return status != AppUpdateStatus.checking &&
      status != AppUpdateStatus.downloading &&
      status != AppUpdateStatus.verifying &&
      status != AppUpdateStatus.installing &&
      status != AppUpdateStatus.awaitingUserConfirmation;
}

class _Button extends StatelessWidget {
  const _Button(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label),
    );
  }
}
