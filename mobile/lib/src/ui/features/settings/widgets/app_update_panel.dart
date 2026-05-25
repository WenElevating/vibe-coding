import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../view_models/app_update_view_model.dart';

class AppUpdatePanel extends StatefulWidget {
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
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  String? _lastPromptKey;
  bool _promptShowing = false;

  @override
  void initState() {
    super.initState();
    _scheduleUpdatePrompt();
  }

  @override
  void didUpdateWidget(covariant AppUpdatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.status == AppUpdateStatus.checking) {
      _lastPromptKey = null;
    }
    _scheduleUpdatePrompt();
  }

  void _scheduleUpdatePrompt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showUpdatePromptIfNeeded());
    });
  }

  Future<void> _showUpdatePromptIfNeeded() async {
    if (!mounted || _promptShowing) return;
    final state = widget.state;
    if (!_shouldPromptForAvailableUpdate(state)) return;
    final manifest = state.manifest;
    final promptKey = '${manifest?.versionCode}:${state.mandatory}';
    if (_lastPromptKey == promptKey) return;
    _lastPromptKey = promptKey;
    _promptShowing = true;
    final l10n = AppLocalizations.of(context);
    final version =
        manifest?.versionName ?? manifest?.versionCode?.toString() ?? '';
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            state.mandatory
                ? l10n.appUpdateDialogRequiredTitle
                : l10n.appUpdateDialogTitle,
          ),
          content: Text(l10n.appUpdateDialogMessage(version)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.appUpdateLaterAction),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDownload();
              },
              child: Text(l10n.appUpdateDownloadPromptAction),
            ),
          ],
        ),
      );
    } finally {
      _promptShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = AppLocalizations.of(context);
    final checking = state.status == AppUpdateStatus.checking;
    final title = _titleFor(l10n, state);
    final subtitle = state.errorMessage ??
        l10n.appUpdateInstalledVersion(
          state.installedVersionName,
          state.installedVersionCode,
        );

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
              if (_canCheck(state))
                _Button(
                  l10n.appUpdateCheckAction,
                  Icons.refresh_rounded,
                  checking ? null : widget.onCheck,
                ),
              if (_canDownload(state))
                _Button(
                  l10n.appUpdateDownloadAction,
                  Icons.download_rounded,
                  widget.onDownload,
                ),
              if (state.status == AppUpdateStatus.readyToInstall ||
                  state.status == AppUpdateStatus.installPermissionNeeded ||
                  state.status == AppUpdateStatus.installCancelled)
                _Button(
                  l10n.appUpdateInstallAction,
                  Icons.install_mobile_rounded,
                  widget.onInstall,
                ),
              if (state.status == AppUpdateStatus.installPermissionNeeded)
                _Button(
                  l10n.appUpdateOpenSettingsAction,
                  Icons.settings_applications_rounded,
                  widget.onOpenPermissionSettings,
                ),
              if (_canClearUpdate(state))
                _Button(
                  l10n.appUpdateClearAction,
                  Icons.delete_outline_rounded,
                  widget.onDiscard,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _titleFor(AppLocalizations l10n, AppUpdateState state) {
  return switch (state.status) {
    AppUpdateStatus.upToDate => l10n.appUpdateTitleUpToDate,
    AppUpdateStatus.available => state.mandatory
        ? l10n.appUpdateTitleRequiredAvailable
        : l10n.appUpdateTitleAvailable,
    AppUpdateStatus.downloading => l10n.appUpdateTitleDownloading,
    AppUpdateStatus.paused => l10n.appUpdateTitlePaused,
    AppUpdateStatus.verifying => l10n.appUpdateTitleVerifying,
    AppUpdateStatus.readyToInstall => state.mandatory
        ? l10n.appUpdateTitleRequiredReadyToInstall
        : l10n.appUpdateTitleReadyToInstall,
    AppUpdateStatus.installPermissionNeeded => state.mandatory
        ? l10n.appUpdateTitleRequiredInstallPermissionNeeded
        : l10n.appUpdateTitleInstallPermissionNeeded,
    AppUpdateStatus.installing => l10n.appUpdateTitleInstalling,
    AppUpdateStatus.awaitingUserConfirmation => state.mandatory
        ? l10n.appUpdateTitleRequiredAwaitingUserConfirmation
        : l10n.appUpdateTitleAwaitingUserConfirmation,
    AppUpdateStatus.installSucceeded => l10n.appUpdateTitleInstallSucceeded,
    AppUpdateStatus.installCancelled => state.mandatory
        ? l10n.appUpdateTitleRequiredInstallCancelled
        : l10n.appUpdateTitleInstallCancelled,
    AppUpdateStatus.installFailed => state.mandatory
        ? l10n.appUpdateTitleRequiredInstallFailed
        : l10n.appUpdateTitleInstallFailed,
    AppUpdateStatus.failed => l10n.appUpdateTitleFailed,
    AppUpdateStatus.checking => l10n.appUpdateTitleChecking,
    AppUpdateStatus.cancelled => l10n.appUpdateTitleCancelled,
    AppUpdateStatus.idle => l10n.appUpdateTitleIdle,
  };
}

bool _shouldPromptForAvailableUpdate(AppUpdateState state) {
  return state.status == AppUpdateStatus.available && _hasNewerManifest(state);
}

bool _hasNewerManifest(AppUpdateState state) {
  final manifest = state.manifest;
  return manifest != null && manifest.isNewerThan(state.installedVersionCode);
}

bool _canCheck(AppUpdateState state) {
  return switch (state.status) {
    AppUpdateStatus.idle ||
    AppUpdateStatus.checking ||
    AppUpdateStatus.upToDate ||
    AppUpdateStatus.installSucceeded =>
      true,
    AppUpdateStatus.failed => !_hasNewerManifest(state),
    _ => false,
  };
}

bool _canDownload(AppUpdateState state) {
  if (!_hasNewerManifest(state)) return false;
  return state.status == AppUpdateStatus.available ||
      state.status == AppUpdateStatus.paused ||
      state.status == AppUpdateStatus.cancelled ||
      state.status == AppUpdateStatus.failed ||
      state.status == AppUpdateStatus.installCancelled;
}

bool _canClearUpdate(AppUpdateState state) {
  if (!_hasNewerManifest(state)) return false;
  return state.status == AppUpdateStatus.paused ||
      state.status == AppUpdateStatus.readyToInstall ||
      state.status == AppUpdateStatus.awaitingUserConfirmation ||
      state.status == AppUpdateStatus.installCancelled;
}

class _Button extends StatelessWidget {
  const _Button(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label),
    );
  }
}
