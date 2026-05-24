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
  late final StreamSubscription<AndroidInstallEvent> _installSubscription;
  bool _disposed = false;

  AppUpdateState state;

  Future<void> checkForUpdates() async {
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
    final result = await downloader.download(manifest, daemonBaseUri);
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
  }

  Future<void> install() async {
    final file = state.downloadedFile;
    if (file == null) return;
    if (!await installer.canRequestPackageInstalls()) {
      _set(state.copyWith(status: AppUpdateStatus.installPermissionNeeded));
      return;
    }
    _set(state.copyWith(status: AppUpdateStatus.installing));
    await installer.installApk(file.path);
  }

  Future<void> discard() async {
    final manifest = state.manifest;
    final versionCode = manifest?.versionCode;
    if (versionCode != null) {
      await downloader.discard(versionCode);
    }
    state = AppUpdateState(
      status: AppUpdateStatus.cancelled,
      installedVersionName: installedVersionName,
      installedVersionCode: installedVersionCode,
      manifest: manifest,
      mandatory: state.mandatory,
    );
    notifyListeners();
  }

  Future<void> openInstallPermissionSettings() {
    return installer.openInstallPermissionSettings();
  }

  void _handleInstallEvent(AndroidInstallEvent event) {
    final status = switch (event.status) {
      AndroidInstallStatus.committed => AppUpdateStatus.installing,
      AndroidInstallStatus.pendingUserAction => AppUpdateStatus.installing,
      AndroidInstallStatus.success => AppUpdateStatus.installSucceeded,
      AndroidInstallStatus.cancelled => AppUpdateStatus.installCancelled,
      AndroidInstallStatus.failed => AppUpdateStatus.installFailed,
    };
    _set(state.copyWith(status: status, errorMessage: event.message));
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
