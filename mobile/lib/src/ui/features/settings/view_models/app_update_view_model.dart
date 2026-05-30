import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../../../domain/models/app_update_manifest.dart';
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

enum AppUpdateCheckTrigger {
  manual('manual'),
  connectedShellCreated('connectedShellCreated'),
  appResumed('appResumed');

  const AppUpdateCheckTrigger(this.diagnosticName);

  final String diagnosticName;

  bool get isSilent => this != AppUpdateCheckTrigger.manual;
}

class AppUpdateState {
  const AppUpdateState({
    required this.status,
    required this.installedVersionName,
    required this.installedVersionCode,
    this.manifest,
    this.mandatory = false,
    this.promptSuppressed = false,
    this.downloadedFile,
    this.errorMessage,
    this.downloadedBytes,
    this.totalBytes,
  });

  final AppUpdateStatus status;
  final String installedVersionName;
  final int installedVersionCode;
  final AppUpdateManifest? manifest;
  final bool mandatory;
  final bool promptSuppressed;
  final File? downloadedFile;
  final String? errorMessage;
  final int? downloadedBytes;
  final int? totalBytes;

  double? get downloadProgress {
    final downloaded = downloadedBytes;
    final total = totalBytes;
    if (downloaded == null || total == null || total <= 0) return null;
    return (downloaded / total).clamp(0, 1).toDouble();
  }

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    AppUpdateManifest? manifest,
    bool clearManifest = false,
    bool? mandatory,
    bool? promptSuppressed,
    File? downloadedFile,
    bool clearDownloadedFile = false,
    String? errorMessage,
    int? downloadedBytes,
    int? totalBytes,
    bool clearDownloadProgress = false,
  }) {
    assert(!clearManifest || manifest == null);
    assert(!clearDownloadedFile || downloadedFile == null);
    assert(!clearDownloadProgress ||
        (downloadedBytes == null && totalBytes == null));
    return AppUpdateState(
      status: status ?? this.status,
      installedVersionName: installedVersionName,
      installedVersionCode: installedVersionCode,
      manifest: clearManifest ? null : manifest ?? this.manifest,
      mandatory: mandatory ?? this.mandatory,
      promptSuppressed: promptSuppressed ?? this.promptSuppressed,
      downloadedFile:
          clearDownloadedFile ? null : downloadedFile ?? this.downloadedFile,
      errorMessage: errorMessage,
      downloadedBytes: clearDownloadProgress
          ? null
          : downloadedBytes ?? this.downloadedBytes,
      totalBytes: clearDownloadProgress ? null : totalBytes ?? this.totalBytes,
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
    _installSubscription = workflow.installEvents.listen(
      _handleInstallEvent,
      onError: _handleInstallEventError,
    );
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
  bool _checkInFlight = false;
  final Set<int> _postponedOptionalVersionCodes = <int>{};

  AppUpdateState state;

  Future<void> checkForUpdates({
    AppUpdateCheckTrigger trigger = AppUpdateCheckTrigger.manual,
  }) async {
    if (_checkInFlight) {
      if (trigger.isSilent) {
        _recordSilentCheckSkipped(trigger, reason: 'checkInFlight');
      }
      return;
    }
    if (_recoveringInstallSession ||
        _installInFlight ||
        _isActiveOperation(state.status)) {
      if (trigger.isSilent) {
        _recordSilentCheckSkipped(trigger, reason: 'activeOperation');
      }
      return;
    }

    _checkInFlight = true;
    if (trigger.isSilent) {
      _recordDiagnostic('update.silent_check.started', {
        'trigger': trigger.diagnosticName,
      });
    } else {
      _recordDiagnostic('update.check.started', const <String, Object?>{});
      _set(
        state.copyWith(
          status: AppUpdateStatus.checking,
          promptSuppressed: false,
        ),
      );
    }
    try {
      final manifest = await workflow.fetchLatest();
      if (!manifest.available || !manifest.isNewerThan(installedVersionCode)) {
        _set(
          state.copyWith(
            status: AppUpdateStatus.upToDate,
            manifest: manifest,
            mandatory: false,
            promptSuppressed: false,
            clearDownloadedFile: true,
          ),
        );
        _recordSilentCheckCompleted(trigger, manifest, false);
        return;
      }
      final mandatory = manifest.isMandatoryFor(installedVersionCode);
      final promptSuppressed = trigger.isSilent &&
          !mandatory &&
          _postponedOptionalVersionCodes.contains(manifest.versionCode);
      final downloadedFile = await workflow.readDownloadedUpdate(manifest);
      _set(
        state.copyWith(
          status: downloadedFile == null
              ? AppUpdateStatus.available
              : AppUpdateStatus.readyToInstall,
          manifest: manifest,
          mandatory: mandatory,
          promptSuppressed: promptSuppressed,
          downloadedFile: downloadedFile,
          clearDownloadedFile: downloadedFile == null,
          clearDownloadProgress: true,
        ),
      );
      _recordSilentCheckCompleted(
        trigger,
        manifest,
        mandatory,
        promptSuppressed: promptSuppressed,
      );
      if (trigger.isSilent && promptSuppressed) {
        _recordDiagnostic('update.prompt.suppressed', {
          'versionCode': manifest.versionCode,
          'reason': 'postponedVersion',
        });
      }
    } catch (error) {
      if (trigger.isSilent) {
        _recordDiagnostic('update.silent_check.failed', {
          'trigger': trigger.diagnosticName,
          'errorSummary': '$error',
        });
      } else {
        _set(
          state.copyWith(
            status: AppUpdateStatus.failed,
            errorMessage: '$error',
          ),
        );
      }
    } finally {
      _checkInFlight = false;
    }
  }

  void postponeCurrentUpdatePrompt() {
    final manifest = state.manifest;
    final versionCode = manifest?.versionCode;
    if (manifest == null || versionCode == null || state.mandatory) return;
    _postponedOptionalVersionCodes.add(versionCode);
    _recordDiagnostic('update.prompt.postponed', {
      'versionCode': versionCode,
    });
    _set(state.copyWith(promptSuppressed: true));
  }

  Future<void> download({bool installWhenReady = false}) async {
    final manifest = state.manifest;
    if (manifest == null) return;
    _set(
      state.copyWith(
        status: AppUpdateStatus.downloading,
        promptSuppressed: false,
        clearDownloadedFile: true,
        downloadedBytes: 0,
        totalBytes: manifest.sizeBytes,
      ),
    );
    try {
      final result = await workflow.download(
        manifest,
        daemonBaseUri,
        onProgress: _handleDownloadProgress,
      );
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
          clearDownloadedFile: result.file == null,
          errorMessage: result.message,
          promptSuppressed: false,
          clearDownloadProgress: result.state != AppUpdateDownloadState.paused,
        ),
      );
      if (installWhenReady &&
          result.state == AppUpdateDownloadState.readyToInstall &&
          result.file != null) {
        await install();
      }
    } catch (error) {
      _set(
        state.copyWith(
          status: AppUpdateStatus.failed,
          errorMessage: '$error',
          promptSuppressed: false,
          clearDownloadedFile: true,
          clearDownloadProgress: true,
        ),
      );
    }
  }

  void _handleDownloadProgress(AppUpdateDownloadProgress progress) {
    if (_disposed || state.status != AppUpdateStatus.downloading) return;
    _set(
      state.copyWith(
        downloadedBytes: progress.downloadedBytes,
        totalBytes: progress.totalBytes,
      ),
    );
  }

  Future<void> install({bool openPermissionSettings = true}) async {
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
      _set(
        state.copyWith(
          status: AppUpdateStatus.installing,
          promptSuppressed: false,
        ),
      );
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
          _set(
            state.copyWith(
              status: AppUpdateStatus.installPermissionNeeded,
              promptSuppressed: false,
            ),
          );
          if (openPermissionSettings) {
            await workflow.openInstallPermissionSettings();
          }
          return;
        case AppUpdateInstallStartState.invalidSession:
          _set(
            state.copyWith(
              status: AppUpdateStatus.readyToInstall,
              errorMessage: result.message,
              promptSuppressed: false,
            ),
          );
          return;
        case AppUpdateInstallStartState.committed:
          _recordDiagnostic('update.install.committed', {
            'sessionId': result.sessionId,
          });
          final message = result.message;
          if (message != null) {
            _recordDiagnostic('update.install.session_record_failed', {
              'sessionId': result.sessionId,
              'errorSummary': message,
            });
          }
          return;
      }
    } catch (error) {
      _set(
        state.copyWith(
          status: AppUpdateStatus.readyToInstall,
          errorMessage: '$error',
          promptSuppressed: false,
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
          await workflow.clearAllInstallSessions();
          if (!_canRecoverInstallSession()) return;
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
          await workflow.clearInstallSession(
            manifest,
            sessionId: recovery.sessionId,
          );
          if (!_canRecoverInstallSession()) return;
          _set(
            state.copyWith(
              status: AppUpdateStatus.readyToInstall,
              manifest: manifest,
              mandatory: manifest.isMandatoryFor(installedVersionCode),
              downloadedFile: recovery.file,
              errorMessage: recovery.message,
              promptSuppressed: false,
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
              promptSuppressed: false,
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
            promptSuppressed: false,
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

  Future<void> handleAppLifecycleStateChanged(
    AppLifecycleState lifecycleState,
  ) async {
    if (lifecycleState == AppLifecycleState.resumed) {
      if (state.status == AppUpdateStatus.installPermissionNeeded) {
        await _continueInstallAfterPermissionGrant();
        return;
      }
      await recoverInstallSession();
    }
  }

  Future<void> _continueInstallAfterPermissionGrant() async {
    if (_disposed || _installInFlight || _recoveringInstallSession) return;
    try {
      if (!await workflow.canRequestPackageInstalls()) return;
    } catch (error) {
      _set(
        state.copyWith(
          status: AppUpdateStatus.readyToInstall,
          errorMessage: '$error',
          promptSuppressed: false,
        ),
      );
      return;
    }
    if (_disposed || state.status != AppUpdateStatus.installPermissionNeeded) {
      return;
    }
    await install(openPermissionSettings: false);
  }

  void _handleInstallEvent(AndroidInstallEvent event) {
    if (event.status == AndroidInstallStatus.cancelled) {
      _clearInstallSession(sessionId: event.sessionId);
      _set(
        state.copyWith(
          status: AppUpdateStatus.installCancelled,
          errorMessage: event.message ?? 'Install cancelled.',
          promptSuppressed: false,
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
    _set(
      state.copyWith(
        status: status,
        errorMessage: event.message,
        promptSuppressed: false,
      ),
    );
  }

  void _handleInstallEventError(Object error, StackTrace stackTrace) {
    _recordDiagnostic('update.install.events_failed', {
      'errorSummary': '$error',
    });
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

  void _recordSilentCheckSkipped(
    AppUpdateCheckTrigger trigger, {
    required String reason,
  }) {
    _recordDiagnostic('update.silent_check.skipped', {
      'trigger': trigger.diagnosticName,
      'reason': reason,
    });
  }

  void _recordSilentCheckCompleted(
    AppUpdateCheckTrigger trigger,
    AppUpdateManifest manifest,
    bool mandatory, {
    bool promptSuppressed = false,
  }) {
    if (!trigger.isSilent) return;
    _recordDiagnostic('update.silent_check.completed', {
      'trigger': trigger.diagnosticName,
      'status': state.status.name,
      'remoteVersionCode': manifest.versionCode,
      'mandatory': mandatory,
      'promptSuppressed': promptSuppressed,
    });
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
    unawaited(_cancelInstallSubscriptionBestEffort());
    super.dispose();
  }

  Future<void> _cancelInstallSubscriptionBestEffort() async {
    try {
      await _installSubscription.cancel();
    } catch (_) {
      // Cleanup is best-effort; cancellation failures must not escape dispose.
    }
  }
}
