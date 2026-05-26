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
    required this.onDiscard,
    required this.onPostpone,
    this.child,
  });

  final AppUpdateState state;
  final VoidCallback onCheck;
  final VoidCallback onDownload;
  final VoidCallback onInstall;
  final VoidCallback onDiscard;
  final VoidCallback onPostpone;

  // Allows settings screens to reuse update dialogs with a compact row surface.
  final Widget? child;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  String? _lastPromptKey;
  bool _promptShowing = false;
  bool _operationDialogShowing = false;
  late final ValueNotifier<AppUpdateState> _operationState;

  @override
  void initState() {
    super.initState();
    _operationState = ValueNotifier<AppUpdateState>(widget.state);
    _scheduleUpdatePrompt();
    _scheduleOperationDialogSync();
  }

  @override
  void didUpdateWidget(covariant AppUpdatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _operationState.value = widget.state;
    if (widget.state.status == AppUpdateStatus.checking) {
      _lastPromptKey = null;
    }
    _scheduleUpdatePrompt();
    _scheduleOperationDialogSync();
  }

  @override
  void dispose() {
    _operationState.dispose();
    super.dispose();
  }

  void _scheduleUpdatePrompt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showUpdatePromptIfNeeded());
    });
  }

  void _scheduleOperationDialogSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncOperationDialog());
    });
  }

  Future<void> _showUpdatePromptIfNeeded() async {
    if (!mounted || _promptShowing) return;
    final state = widget.state;
    if (!_shouldPromptForAvailableUpdate(state)) return;
    final manifest = state.manifest;
    final promptKey = '${manifest?.versionCode}:${state.mandatory}';
    if (state.mandatory) {
      _lastPromptKey = null;
    } else {
      if (_lastPromptKey == promptKey) return;
      _lastPromptKey = promptKey;
    }
    _promptShowing = true;
    final l10n = AppLocalizations.of(context);
    final version =
        manifest?.versionName ?? manifest?.versionCode?.toString() ?? '';
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !state.mandatory,
        builder: (context) => PopScope(
          canPop: !state.mandatory,
          child: AlertDialog(
            title: Text(
              state.mandatory
                  ? l10n.appUpdateDialogRequiredTitle
                  : l10n.appUpdateDialogTitle,
            ),
            content: Text(l10n.appUpdateDialogMessage(version)),
            actions: [
              if (!state.mandatory)
                TextButton(
                  onPressed: () {
                    widget.onPostpone();
                    Navigator.of(context).pop();
                  },
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
        ),
      );
    } finally {
      _promptShowing = false;
    }
  }

  Future<void> _syncOperationDialog() async {
    if (!mounted) return;
    if (!_isBlockingOperation(widget.state.status)) {
      if (_operationDialogShowing) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }
    if (_operationDialogShowing) return;
    _operationDialogShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: ValueListenableBuilder<AppUpdateState>(
            valueListenable: _operationState,
            builder: (context, state, _) =>
                _AppUpdateProgressDialog(state: state),
          ),
        ),
      );
    } finally {
      _operationDialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child != null) return child;

    final state = widget.state;
    final l10n = AppLocalizations.of(context);
    final checking = state.status == AppUpdateStatus.checking;
    final title = appUpdateTitleFor(l10n, state);
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

String appUpdateTitleFor(AppLocalizations l10n, AppUpdateState state) {
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

bool _isBlockingOperation(AppUpdateStatus status) {
  return status == AppUpdateStatus.downloading ||
      status == AppUpdateStatus.verifying ||
      status == AppUpdateStatus.installing ||
      status == AppUpdateStatus.awaitingUserConfirmation;
}

bool _shouldPromptForAvailableUpdate(AppUpdateState state) {
  return !state.promptSuppressed &&
      state.status == AppUpdateStatus.available &&
      _hasNewerManifest(state);
}

String _progressMessageFor(AppLocalizations l10n, AppUpdateState state) {
  return switch (state.status) {
    AppUpdateStatus.downloading => l10n.appUpdateProgressDownloadingMessage,
    AppUpdateStatus.verifying => l10n.appUpdateProgressVerifyingMessage,
    AppUpdateStatus.installing => l10n.appUpdateProgressInstallingMessage,
    AppUpdateStatus.awaitingUserConfirmation =>
      l10n.appUpdateProgressAwaitingConfirmationMessage,
    _ => l10n.appUpdateProgressDownloadingMessage,
  };
}

class _AppUpdateProgressDialog extends StatelessWidget {
  const _AppUpdateProgressDialog({required this.state});

  final AppUpdateState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('app-update-progress-dialog'),
      backgroundColor: const Color(0xFF111820),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: .1)),
      ),
      title: Text(
        appUpdateTitleFor(l10n, state),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              minHeight: 4,
              color: theme.active,
              backgroundColor: Colors.white.withValues(alpha: .08),
            ),
            const SizedBox(height: 14),
            Text(
              _progressMessageFor(l10n, state),
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
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
