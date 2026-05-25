import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../../../data/models/app_update_models.dart';
import '../../../../workflows/app_update_workflow.dart';

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  paused,
  verifying,
  readyToInstall,
  installPermissionNeeded,
  installing,
  awaitingUserConfirmation,
  installSucceeded,
  installCancelled,
  installFailed,
  cancelled,
  failed,
}

class AppUpdateState {
  const AppUpdateState({
    required this.status,
    required this.installedVersionName,
    required this.installedVersionCode,
    this.manifest,
    this.mandatory = false,
    this.downloadedFile,
    this.errorMessage,
  });

  final AppUpdateStatus status;
  final String installedVersionName;
  final int installedVersionCode;
  final AppUpdateManifest? manifest;
  final bool mandatory;
  final File? downloadedFile;
  final String? errorMessage;

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    AppUpdateManifest? manifest,
    bool? mandatory,
    File? downloadedFile,
    String? errorMessage,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      installedVersionName: installedVersionName,
      installedVersionCode: installedVersionCode,
      manifest: manifest ?? this.manifest,
      mandatory: mandatory ?? this.mandatory,
      downloadedFile: downloadedFile ?? this.downloadedFile,
      errorMessage: errorMessage,
    );
  }
}

class AppUpdateViewModel extends ChangeNotifier {
  AppUpdateViewModel({
    required this.installedVersionCode,
    required this.installedVersionName,
    required this.workflow,
    required this.daemonBaseUri,
    this.recordDiagnostic,
  }) : state = AppUpdateState(
          status: AppUpdateStatus.idle,
          installedVersionName: installedVersionName,
          installedVersionCode: installedVersionCode,
        ) {
    _installSubscription = workflow.installEvents.listen(_handleInstallEvent);
  }

  final int installedVersionCode;
  final String installedVersionName;
  final AppUpdateWorkflow workflow;
  final Uri daemonBaseUri;
  final void Function(String event, Map<String, Object?> metadata)?
      recordDiagnostic;
  late final StreamSubscription<AndroidInstallEvent> _installSubscription;
  bool _disposed = false;
  bool _recoveringInstallSession = false;
  bool _installInFlight = false;

  AppUpdateState state;

  Future<void> checkForUpdates() async {
    if (_recoveringInstallSession || _isActiveOperation(state.status)) return;
    _recordDiagnostic('update.check.started', const <String, Object?>{});
    _set(state.copyWith(status: AppUpdateStatus.checking));
    try {
      final manifest = await workflow.fetchLatest();
      if (!manifest.available || !manifest.isNewerThan(installedVersionCode)) {
        _set(
          state.copyWith(
            status: AppUpdateStatus.upToDate,
            manifest: manifest,
            mandatory: false,
          ),
        );
        return;
      }
      _set(
        state.copyWith(
          status: AppUpdateStatus.available,
          manifest: manifest,
          mandatory: manifest.isMandatoryFor(installedVersionCode),
        ),
      );
    } catch (error) {
      _set(
        state.copyWith(status: AppUpdateStatus.failed, errorMessage: '$error'),
      );
    }
  }

  Future<void> download() async {
    final manifest = state.manifest;
    if (manifest == null) return;
    _set(state.copyWith(status: AppUpdateStatus.downloading));
    try {
      final result = await workflow.download(manifest, daemonBaseUri);
      if (_isStoragePreflightFailure(result)) {
        _recordDiagnostic('update.storage.preflight_failed', {
          'versionCode': manifest.versionCode,
        });
      }
      _set(
        state.copyWith(
          status: switch (result.state) {
            AppUpdateDownloadState.readyToInstall =>
              AppUpdateStatus.readyToInstall,
            AppUpdateDownloadState.paused => AppUpdateStatus.paused,
            AppUpdateDownloadState.verifying => AppUpdateStatus.verifying,
            AppUpdateDownloadState.downloading => AppUpdateStatus.downloading,
            AppUpdateDownloadState.failed => AppUpdateStatus.failed,
          },
          downloadedFile: result.file,
          errorMessage: result.message,
        ),
      );
    } catch (error) {
      _set(
        state.copyWith(status: AppUpdateStatus.failed, errorMessage: '$error'),
      );
    }
  }

  Future<void> install() async {
    if (_installInFlight || _recoveringInstallSession) return;
    if (state.status == AppUpdateStatus.installing ||
        state.status == AppUpdateStatus.awaitingUserConfirmation) {
      return;
    }
    final file = state.downloadedFile;
    final manifest = state.manifest;
    if (file == null) return;
    _installInFlight = true;
    try {
      _set(state.copyWith(status: AppUpdateStatus.installing));
      final result = await workflow.startInstall(
        manifest: manifest,
        file: file,
      );
      switch (result.state) {
        case AppUpdateInstallStartState.missingFile:
          _set(
            AppUpdateState(
              status: AppUpdateStatus.available,
              installedVersionName: installedVersionName,
              installedVersionCode: installedVersionCode,
              manifest: manifest,
              mandatory: state.mandatory,
              errorMessage: result.message,
            ),
          );
          return;
        case AppUpdateInstallStartState.permissionNeeded:
          _set(state.copyWith(status: AppUpdateStatus.installPermissionNeeded));
          return;
        case AppUpdateInstallStartState.invalidSession:
          _set(
            state.copyWith(
              status: AppUpdateStatus.readyToInstall,
              errorMessage: result.message,
            ),
          );
          return;
        case AppUpdateInstallStartState.committed:
          _recordDiagnostic('update.install.committed', {
            'sessionId': result.sessionId,
          });
          return;
      }
    } catch (error) {
      _set(
        state.copyWith(
          status: AppUpdateStatus.readyToInstall,
          errorMessage: '$error',
        ),
      );
    } finally {
      _installInFlight = false;
    }
  }

  Future<void> recoverInstallSession() async {
    if (_recoveringInstallSession) return;
    if (!_canRecoverInstallSession()) return;
    _recoveringInstallSession = true;
    try {
      final recovery = await workflow.recoverInstall(
        installedVersionCode: installedVersionCode,
      );
      if (!_canRecoverInstallSession()) return;
      switch (recovery.state) {
        case AppUpdateRecoveryState.noUpdate:
          if (state.status != AppUpdateStatus.idle) {
            _set(
              AppUpdateState(
                status: AppUpdateStatus.upToDate,
                installedVersionName: installedVersionName,
                installedVersionCode: installedVersionCode,
                manifest: recovery.manifest,
              ),
            );
          }
          return;
        case AppUpdateRecoveryState.noSession:
          return;
        case AppUpdateRecoveryState.staleSession:
          final manifest = recovery.manifest;
          if (manifest == null) return;
          _set(
            state.copyWith(
              status: AppUpdateStatus.readyToInstall,
              manifest: manifest,
              mandatory: manifest.isMandatoryFor(installedVersionCode),
              downloadedFile: recovery.file,
              errorMessage: recovery.message,
            ),
          );
          return;
        case AppUpdateRecoveryState.installerEvent:
          final manifest = recovery.manifest;
          final event = recovery.event;
          if (manifest == null || event == null) return;
          _set(
            state.copyWith(
              status: AppUpdateStatus.readyToInstall,
              manifest: manifest,
              mandatory: manifest.isMandatoryFor(installedVersionCode),
              downloadedFile: recovery.file,
            ),
          );
          _handleInstallEvent(event);
          return;
      }
    } catch (error) {
      _recordDiagnostic('update.install.recovery_failed', {'error': '$error'});
      if (_canRecoverInstallSession()) {
        _set(
          state.copyWith(
            status: AppUpdateStatus.failed,
            errorMessage: '$error',
          ),
        );
      }
    } finally {
      _recoveringInstallSession = false;
    }
  }

  Future<void> discard() async {
    final manifest = state.manifest;
    final versionCode = manifest?.versionCode;
    if (versionCode != null) {
      await workflow.discard(versionCode);
    }
    _recordDiagnostic('update.discard', {'versionCode': versionCode});
    final nextStatus =
        manifest != null && manifest.isNewerThan(installedVersionCode)
            ? AppUpdateStatus.available
            : AppUpdateStatus.idle;
    _set(
      AppUpdateState(
        status: nextStatus,
        installedVersionName: installedVersionName,
        installedVersionCode: installedVersionCode,
        manifest: manifest,
        mandatory: state.mandatory,
      ),
    );
  }

  Future<void> openInstallPermissionSettings() {
    return workflow.openInstallPermissionSettings();
  }

  void handleAppLifecycleStateChanged(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      unawaited(recoverInstallSession());
    }
  }

  void _handleInstallEvent(AndroidInstallEvent event) {
    if (event.status == AndroidInstallStatus.cancelled) {
      _clearInstallSession(sessionId: event.sessionId);
      _set(
        state.copyWith(
          status: AppUpdateStatus.installCancelled,
          errorMessage: event.message ?? 'Install cancelled.',
        ),
      );
      return;
    }
    final status = switch (event.status) {
      AndroidInstallStatus.committed => AppUpdateStatus.installing,
      AndroidInstallStatus.pendingUserAction =>
        AppUpdateStatus.awaitingUserConfirmation,
      AndroidInstallStatus.success => AppUpdateStatus.installSucceeded,
      AndroidInstallStatus.cancelled => AppUpdateStatus.readyToInstall,
      AndroidInstallStatus.failed => AppUpdateStatus.installFailed,
    };
    if (event.status == AndroidInstallStatus.success ||
        event.status == AndroidInstallStatus.failed) {
      _clearInstallSession(sessionId: event.sessionId);
    }
    _set(state.copyWith(status: status, errorMessage: event.message));
  }

  bool _canRecoverInstallSession() {
    return state.status == AppUpdateStatus.idle ||
        state.status == AppUpdateStatus.upToDate ||
        state.status == AppUpdateStatus.available ||
        state.status == AppUpdateStatus.paused ||
        state.status == AppUpdateStatus.failed;
  }

  void _clearInstallSession({int? sessionId}) {
    final manifest = state.manifest;
    if (manifest == null) return;
    unawaited(_clearInstallSessionNow(manifest, sessionId: sessionId));
  }

  Future<void> _clearInstallSessionNow(
    AppUpdateManifest manifest, {
    int? sessionId,
  }) async {
    try {
      await workflow.clearInstallSession(manifest, sessionId: sessionId);
    } catch (error) {
      _recordDiagnostic('update.install.clear_session_failed', {
        'error': '$error',
      });
    }
  }

  bool _isStoragePreflightFailure(AppUpdateDownloadResult result) {
    return result.state == AppUpdateDownloadState.failed &&
        (result.message ?? '').toLowerCase().contains('storage');
  }

  bool _isActiveOperation(AppUpdateStatus status) {
    return status == AppUpdateStatus.checking ||
        status == AppUpdateStatus.downloading ||
        status == AppUpdateStatus.verifying ||
        status == AppUpdateStatus.installing ||
        status == AppUpdateStatus.awaitingUserConfirmation;
  }

  void _recordDiagnostic(String event, Map<String, Object?> metadata) {
    if (_disposed) return;
    recordDiagnostic?.call(event, metadata);
  }

  void _set(AppUpdateState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_installSubscription.cancel());
    super.dispose();
  }
}
