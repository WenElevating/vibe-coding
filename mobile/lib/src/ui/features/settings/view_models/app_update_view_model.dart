import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../data/models/app_update_models.dart';
import '../../../../domain/repositories/app_update_repository.dart';
import '../../../../services/android_package_installer.dart';
import '../../../../services/app_update_download_manager.dart';

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
    required this.repository,
    required this.installer,
    required this.downloader,
    required this.daemonBaseUri,
    this.recordDiagnostic,
  }) : state = AppUpdateState(
         status: AppUpdateStatus.idle,
         installedVersionName: installedVersionName,
         installedVersionCode: installedVersionCode,
       ) {
    _installSubscription = installer.events.listen(_handleInstallEvent);
  }

  final int installedVersionCode;
  final String installedVersionName;
  final AppUpdateRepository repository;
  final PackageInstallerService installer;
  final AppUpdateDownloader downloader;
  final Uri daemonBaseUri;
  final void Function(String event, Map<String, Object?> metadata)?
  recordDiagnostic;
  late final StreamSubscription<AndroidInstallEvent> _installSubscription;
  bool _disposed = false;

  AppUpdateState state;

  Future<void> checkForUpdates() async {
    _recordDiagnostic('update.check.started', const <String, Object?>{});
    _set(state.copyWith(status: AppUpdateStatus.checking));
    try {
      final manifest = await repository.fetchLatest();
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
      final result = await downloader.download(manifest, daemonBaseUri);
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
    final file = state.downloadedFile;
    final manifest = state.manifest;
    if (file == null) return;
    if (!await installer.canRequestPackageInstalls()) {
      _set(state.copyWith(status: AppUpdateStatus.installPermissionNeeded));
      return;
    }
    _set(state.copyWith(status: AppUpdateStatus.installing));
    final sessionId = await installer.installApk(file.path);
    if (manifest != null && sessionId >= 0) {
      await downloader.recordInstallSession(manifest, sessionId);
    }
    _recordDiagnostic('update.install.committed', {'sessionId': sessionId});
  }

  Future<void> discard() async {
    final manifest = state.manifest;
    final versionCode = manifest?.versionCode;
    if (versionCode != null) {
      await downloader.discard(versionCode);
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
    return installer.openInstallPermissionSettings();
  }

  void _handleInstallEvent(AndroidInstallEvent event) {
    if (event.status == AndroidInstallStatus.cancelled) {
      _set(state.copyWith(status: AppUpdateStatus.installCancelled));
      _set(
        state.copyWith(
          status: AppUpdateStatus.readyToInstall,
          errorMessage: event.message ?? 'Install cancelled.',
        ),
      );
      return;
    }
    final status = switch (event.status) {
      AndroidInstallStatus.committed => AppUpdateStatus.installing,
      AndroidInstallStatus.pendingUserAction => AppUpdateStatus.installing,
      AndroidInstallStatus.success => AppUpdateStatus.installSucceeded,
      AndroidInstallStatus.failed => AppUpdateStatus.installFailed,
    };
    _set(state.copyWith(status: status, errorMessage: event.message));
  }

  bool _isStoragePreflightFailure(AppUpdateDownloadResult result) {
    return result.state == AppUpdateDownloadState.failed &&
        (result.message ?? '').toLowerCase().contains('storage');
  }

  void _recordDiagnostic(String event, Map<String, Object?> metadata) {
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
